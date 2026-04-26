//! High-level orchestrator over `keychain` + `cert_factory` +
//! `codesigner`. Mirrors the Dart `ResignService` flow.

use std::path::Path;

use super::cert_factory::{CertFactory, CertFactoryError, DEFAULT_COMMON_NAME, DEFAULT_ORGANISATION};
use super::codesigner::{Codesigner, CodesignError};
use super::keychain::{Keychain, KeychainError};
use super::process::Runner;

/// Outcome of a self-sign flow. Surfaces back to the UI so the
/// wizard can pick a tailored message + next step.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ResignOutcome {
    /// Fresh cert created, trust granted, bundle re-signed.
    Succeeded,
    /// Existing cert reused, bundle re-signed. No password
    /// prompt was shown — the wizard can return silently.
    ReusedExisting,
    /// User dismissed the macOS prompt or some keychain op
    /// failed. Surface the error and leave the app on a
    /// fallback tier.
    CancelledOrFailed,
    /// Bundle is writable only via elevation. Wizard suggests
    /// moving to `~/Applications` or accepting an admin prompt.
    BundleNotWritable,
}

#[derive(Debug, thiserror::Error)]
pub enum ResignServiceError {
    #[error(transparent)]
    Keychain(#[from] KeychainError),
    #[error(transparent)]
    CertFactory(#[from] CertFactoryError),
    #[error(transparent)]
    Codesign(#[from] CodesignError),
}

pub struct ResignService<'a> {
    runner: &'a dyn Runner,
}

impl<'a> ResignService<'a> {
    pub fn new(runner: &'a dyn Runner) -> Self {
        Self { runner }
    }

    /// Make sure the keychain holds a cert under `common_name`.
    /// `Ok(true)` → cert was created in this call (password
    /// prompt shown); `Ok(false)` → already present (silent).
    pub fn ensure_identity(&self, common_name: &str) -> Result<bool, ResignServiceError> {
        let keychain = Keychain::new(self.runner);
        if keychain.has_certificate(common_name)? {
            return Ok(false);
        }
        let factory = CertFactory::new(self.runner);
        let material = factory.generate(common_name, DEFAULT_ORGANISATION, 3650)?;
        let p12_str = material.p12_path.to_string_lossy().into_owned();
        let crt_str = material.crt_path.to_string_lossy().into_owned();
        keychain.import_pkcs12(&p12_str, &material.p12_passphrase)?;
        // Password prompt happens here — user-domain trust DB
        // writes are always auth-gated.
        keychain.add_trusted_cert(&crt_str)?;
        Ok(true)
    }

    /// Re-sign `app_bundle` against the cert with `common_name`.
    /// Caller must have already run [`ensure_identity`]. The
    /// writability probe up front lets the caller surface
    /// `BundleNotWritable` before the codesign spawn wastes
    /// effort.
    pub fn resign_bundle(
        &self,
        app_bundle: &Path,
        common_name: &str,
    ) -> Result<ResignOutcome, ResignServiceError> {
        if !is_writable(app_bundle) {
            return Ok(ResignOutcome::BundleNotWritable);
        }
        let codesigner = Codesigner::new(self.runner);
        let entitlements = codesigner.extract_entitlements(app_bundle);
        codesigner.resign_inside_out(
            app_bundle,
            common_name,
            entitlements.as_deref(),
            false,
        )?;
        let ok = codesigner.verify(app_bundle);
        Ok(if ok {
            ResignOutcome::Succeeded
        } else {
            ResignOutcome::CancelledOrFailed
        })
    }

    /// Drop the identity + cert from the keychain. The .app
    /// itself stays — the user's T1 items become unreadable
    /// but the bundle keeps running on the original ad-hoc
    /// signature.
    ///
    /// No `remove-trusted-cert` step: the user-domain trust
    /// entry is keyed by the cert's SHA-1 hash, and macOS
    /// skips trust entries whose referenced cert is missing
    /// from any keychain.
    pub fn uninstall_identity(&self, common_name: &str) -> Result<(), ResignServiceError> {
        let keychain = Keychain::new(self.runner);
        keychain.delete_identity(common_name)?;
        keychain.delete_certificate(common_name)?;
        Ok(())
    }

    /// Has the user previously accepted the self-sign prompt?
    pub fn has_identity(&self, common_name: &str) -> Result<bool, ResignServiceError> {
        let keychain = Keychain::new(self.runner);
        Ok(keychain.has_certificate(common_name)?)
    }
}

/// Default common-name re-export for convenience.
pub fn default_common_name() -> &'static str {
    DEFAULT_COMMON_NAME
}

fn is_writable(dir: &Path) -> bool {
    use std::fs::OpenOptions;
    let probe = dir.join(".lfs-write-probe");
    let opened = OpenOptions::new()
        .create(true)
        .write(true)
        .truncate(true)
        .open(&probe);
    match opened {
        Ok(_) => {
            let _ = std::fs::remove_file(&probe);
            true
        }
        Err(_) => false,
    }
}

#[cfg(test)]
mod tests {
    use super::super::process::test_support::MockRunner;
    use super::*;

    #[test]
    fn ensure_identity_skips_when_cert_present() {
        let runner = MockRunner::new();
        // find-certificate exits 0 → cert present.
        runner.enqueue(0, "", "");
        let svc = ResignService::new(&runner);
        let created = svc.ensure_identity(default_common_name()).unwrap();
        assert!(!created);
        // Single call dispatched (find-certificate); no
        // openssl / import / add-trusted spawns.
        assert_eq!(runner.calls().len(), 1);
    }

    #[test]
    fn has_identity_round_trips_through_keychain() {
        let runner = MockRunner::new();
        runner.enqueue(0, "", "");
        let svc = ResignService::new(&runner);
        assert!(svc.has_identity(default_common_name()).unwrap());
        assert_eq!(runner.calls()[0].args[0], "find-certificate");
    }

    #[test]
    fn uninstall_identity_dispatches_delete_pair() {
        let runner = MockRunner::new();
        runner.enqueue(0, "", "");
        runner.enqueue(0, "", "");
        let svc = ResignService::new(&runner);
        svc.uninstall_identity(default_common_name()).unwrap();
        let calls = runner.calls();
        assert_eq!(calls.len(), 2);
        assert!(calls.iter().any(|c| c.args[0] == "delete-identity"));
        assert!(calls.iter().any(|c| c.args[0] == "delete-certificate"));
    }

    #[test]
    fn resign_bundle_returns_not_writable_on_root_owned_path() {
        let runner = MockRunner::new();
        let svc = ResignService::new(&runner);
        // /etc is not writable to a normal user — perfect proxy
        // for a root-owned .app bundle.
        let outcome = svc
            .resign_bundle(Path::new("/etc"), default_common_name())
            .unwrap();
        assert_eq!(outcome, ResignOutcome::BundleNotWritable);
        // No subprocess spawns — writability gate fires first.
        assert!(runner.calls().is_empty());
    }
}
