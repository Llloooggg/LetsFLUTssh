//! Typed wrapper around the macOS `security` CLI.
//!
//! Mirrors `lib/platform/macos/code_signing/keychain.dart`
//! verb-for-verb: identity import, cert lookup, trust DB write,
//! identity + cert delete. Every call delegates to a
//! [`super::process::Runner`] so unit tests assert on argv
//! composition without touching the host's keychain.

use super::process::Runner;

const SECURITY_PATH: &str = "/usr/bin/security";

/// Default login keychain path for the current user. Reads
/// `$HOME` lazily — the env var is process-wide and we want to
/// pick up overrides set by tests.
fn default_keychain_path() -> String {
    let home = std::env::var("HOME").unwrap_or_default();
    format!("{home}/Library/Keychains/login.keychain-db")
}

#[derive(Debug, thiserror::Error)]
pub enum KeychainError {
    #[error("keychain {stage}: {message}")]
    Failed { stage: &'static str, message: String },
    #[error("keychain spawn: {0}")]
    Spawn(String),
}

pub struct Keychain<'a> {
    runner: &'a dyn Runner,
    keychain_path: String,
}

impl<'a> Keychain<'a> {
    pub fn new(runner: &'a dyn Runner) -> Self {
        Self {
            runner,
            keychain_path: default_keychain_path(),
        }
    }

    pub fn with_keychain_path(runner: &'a dyn Runner, path: impl Into<String>) -> Self {
        Self {
            runner,
            keychain_path: path.into(),
        }
    }

    pub fn keychain_path(&self) -> &str {
        &self.keychain_path
    }

    /// True when a cert with `common_name` is already present.
    /// Lets the resign flow stay idempotent — re-running on a
    /// host that already has the identity skips both cert
    /// generation and the trust-DB password prompt.
    pub fn has_certificate(&self, common_name: &str) -> Result<bool, KeychainError> {
        let res = self
            .runner
            .run(
                SECURITY_PATH,
                &["find-certificate", "-c", common_name, &self.keychain_path],
            )
            .map_err(|e| KeychainError::Spawn(e.to_string()))?;
        Ok(res.success())
    }

    /// Import a PKCS#12 bundle into the keychain. `-T` grants
    /// silent access to `codesign` + `security` so subsequent
    /// re-signs and uninstalls don't prompt.
    pub fn import_pkcs12(
        &self,
        p12_path: &str,
        passphrase: &str,
    ) -> Result<(), KeychainError> {
        let res = self
            .runner
            .run(
                SECURITY_PATH,
                &[
                    "import",
                    p12_path,
                    "-k",
                    &self.keychain_path,
                    "-P",
                    passphrase,
                    "-T",
                    "/usr/bin/codesign",
                    "-T",
                    "/usr/bin/security",
                ],
            )
            .map_err(|e| KeychainError::Spawn(e.to_string()))?;
        if !res.success() {
            return Err(KeychainError::Failed {
                stage: "import",
                message: format!("security import exit={} stderr={}", res.status, res.stderr),
            });
        }
        Ok(())
    }

    /// Add the cert to the user-domain trust DB scoped to
    /// `codeSign`. The single password-gated step in the
    /// resign flow — surfacing errors verbatim lets the caller
    /// distinguish "user hit Cancel" from a real failure.
    pub fn add_trusted_cert(&self, crt_path: &str) -> Result<(), KeychainError> {
        let res = self
            .runner
            .run(
                SECURITY_PATH,
                &[
                    "add-trusted-cert",
                    "-r",
                    "trustRoot",
                    "-p",
                    "codeSign",
                    "-k",
                    &self.keychain_path,
                    crt_path,
                ],
            )
            .map_err(|e| KeychainError::Spawn(e.to_string()))?;
        if !res.success() {
            return Err(KeychainError::Failed {
                stage: "add-trusted-cert",
                message: format!(
                    "security add-trusted-cert exit={} stderr={}",
                    res.status, res.stderr
                ),
            });
        }
        Ok(())
    }

    /// Sweep both the cert and its private key in one call.
    /// Errors swallow — the uninstall flow continues even if
    /// the entry has already been removed.
    pub fn delete_identity(&self, common_name: &str) -> Result<(), KeychainError> {
        self.runner
            .run(
                SECURITY_PATH,
                &["delete-identity", "-c", common_name, &self.keychain_path],
            )
            .map_err(|e| KeychainError::Spawn(e.to_string()))?;
        Ok(())
    }

    /// Delete a stray cert (no matching private key). Cleans
    /// up legacy `-legacy` imports that left a lone cert.
    pub fn delete_certificate(&self, common_name: &str) -> Result<(), KeychainError> {
        self.runner
            .run(
                SECURITY_PATH,
                &["delete-certificate", "-c", common_name, &self.keychain_path],
            )
            .map_err(|e| KeychainError::Spawn(e.to_string()))?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::super::process::test_support::MockRunner;
    use super::*;

    #[test]
    fn has_certificate_dispatches_correct_argv() {
        let runner = MockRunner::new();
        runner.enqueue(0, "", "");
        let kc = Keychain::with_keychain_path(&runner, "/tmp/test.keychain-db");
        assert!(kc.has_certificate("LetsFLUTssh Self-Sign").unwrap());
        let calls = runner.calls();
        assert_eq!(calls.len(), 1);
        assert_eq!(calls[0].executable, SECURITY_PATH);
        assert_eq!(
            calls[0].args,
            vec![
                "find-certificate",
                "-c",
                "LetsFLUTssh Self-Sign",
                "/tmp/test.keychain-db",
            ]
        );
    }

    #[test]
    fn import_pkcs12_passes_dual_t_flags() {
        let runner = MockRunner::new();
        runner.enqueue(0, "", "");
        let kc = Keychain::with_keychain_path(&runner, "/tmp/test.keychain-db");
        kc.import_pkcs12("/tmp/cert.p12", "lfs-transient").unwrap();
        let args = &runner.calls()[0].args;
        assert!(args.contains(&"-T".to_string()));
        let t_indices: Vec<usize> = args
            .iter()
            .enumerate()
            .filter(|(_, a)| *a == "-T")
            .map(|(i, _)| i)
            .collect();
        // Two `-T` flags, one for codesign, one for security.
        assert_eq!(t_indices.len(), 2);
        assert_eq!(args[t_indices[0] + 1], "/usr/bin/codesign");
        assert_eq!(args[t_indices[1] + 1], "/usr/bin/security");
    }

    #[test]
    fn add_trusted_cert_uses_user_domain_codesign_scope() {
        let runner = MockRunner::new();
        runner.enqueue(0, "", "");
        let kc = Keychain::with_keychain_path(&runner, "/tmp/test.keychain-db");
        kc.add_trusted_cert("/tmp/cert.crt").unwrap();
        let args = &runner.calls()[0].args;
        assert_eq!(args[0], "add-trusted-cert");
        // -r trustRoot (root cert in user trust domain)
        assert!(args.contains(&"trustRoot".to_string()));
        // -p codeSign (scoped policy, NOT global trust)
        assert!(args.contains(&"codeSign".to_string()));
    }

    #[test]
    fn import_failure_surfaces_keychain_error() {
        let runner = MockRunner::new();
        runner.enqueue(1, "", "stale or missing");
        let kc = Keychain::with_keychain_path(&runner, "/tmp/test.keychain-db");
        let err = kc.import_pkcs12("/tmp/cert.p12", "x").unwrap_err();
        match err {
            KeychainError::Failed { stage, .. } => assert_eq!(stage, "import"),
            other => panic!("unexpected: {other:?}"),
        }
    }

    #[test]
    fn missing_cert_returns_false_not_error() {
        let runner = MockRunner::new();
        runner.enqueue(1, "", "not found");
        let kc = Keychain::with_keychain_path(&runner, "/tmp/test.keychain-db");
        assert!(!kc.has_certificate("missing").unwrap());
    }
}
