//! Self-signed code-signing identity generator. Mirrors
//! `lib/platform/macos/code_signing/cert_factory.dart`
//! step-for-step: emit an OpenSSL config with the right
//! v3 extensions, run `openssl req -x509 -nodes`, pack the
//! result into a `-legacy` PKCS#12 (3DES + SHA1 MAC because
//! macOS `SecKeychainItemImport` cannot parse OpenSSL 3's
//! AES-256 / PBKDF2 default).

use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};

use super::process::Runner;

const OPENSSL_PATH: &str = "/usr/bin/openssl";

/// Default common-name of the generated identity. Treat as a
/// stable invariant across releases — changing it invalidates
/// every keychain item written under the prior cert's
/// designated requirement, locking the user out of every
/// stored T1 secret.
pub const DEFAULT_COMMON_NAME: &str = "LetsFLUTssh Self-Sign";
pub const DEFAULT_ORGANISATION: &str = "LetsFLUTssh";
const P12_PASSPHRASE: &str = "lfs-transient";

#[derive(Debug, thiserror::Error)]
pub enum CertFactoryError {
    #[error("cert factory {stage}: {message}")]
    Failed { stage: &'static str, message: String },
    #[error("cert factory io: {0}")]
    Io(String),
}

/// Output paths the caller hands to `security import`. The
/// `Drop` impl recursively removes [`tmp_dir`] so a panic'd
/// caller still cleans up.
#[derive(Debug)]
pub struct GeneratedCertMaterial {
    tmp_dir: PathBuf,
    pub crt_path: PathBuf,
    pub p12_path: PathBuf,
    pub p12_passphrase: String,
}

impl GeneratedCertMaterial {
    pub fn tmp_dir(&self) -> &Path {
        &self.tmp_dir
    }
}

impl Drop for GeneratedCertMaterial {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.tmp_dir);
    }
}

pub struct CertFactory<'a> {
    runner: &'a dyn Runner,
}

impl<'a> CertFactory<'a> {
    pub fn new(runner: &'a dyn Runner) -> Self {
        Self { runner }
    }

    /// Run the two-step pipeline: `openssl req -x509 -nodes`
    /// then `openssl pkcs12 -export -legacy`. Returns the cert
    /// + p12 paths for `security import`.
    pub fn generate(
        &self,
        common_name: &str,
        organisation: &str,
        validity_days: i64,
    ) -> Result<GeneratedCertMaterial, CertFactoryError> {
        let tmp = mkdtemp("lfs-macos-sign-")?;
        let cnf_path = tmp.join("cert.cnf");
        let key_path = tmp.join("cert.key");
        let crt_path = tmp.join("cert.crt");
        let p12_path = tmp.join("cert.p12");

        fs::write(&cnf_path, openssl_config(common_name, organisation))
            .map_err(|e| CertFactoryError::Io(format!("write cnf: {e}")))?;

        let cnf_str = cnf_path.to_string_lossy().into_owned();
        let key_str = key_path.to_string_lossy().into_owned();
        let crt_str = crt_path.to_string_lossy().into_owned();
        let p12_str = p12_path.to_string_lossy().into_owned();
        let validity_str = validity_days.to_string();

        let req_res = self
            .runner
            .run(
                OPENSSL_PATH,
                &[
                    "req",
                    "-x509",
                    "-nodes",
                    "-new",
                    "-newkey",
                    "rsa:2048",
                    "-days",
                    &validity_str,
                    "-config",
                    &cnf_str,
                    "-extensions",
                    "v3_req",
                    "-keyout",
                    &key_str,
                    "-out",
                    &crt_str,
                ],
            )
            .map_err(|e| CertFactoryError::Io(format!("openssl spawn: {e}")))?;
        if !req_res.success() {
            let _ = fs::remove_dir_all(&tmp);
            return Err(CertFactoryError::Failed {
                stage: "openssl_req",
                message: format!(
                    "openssl x509 generation exit={} stderr={}",
                    req_res.status, req_res.stderr
                ),
            });
        }

        let p12_pass_arg = format!("pass:{P12_PASSPHRASE}");
        let p12_res = self
            .runner
            .run(
                OPENSSL_PATH,
                &[
                    "pkcs12",
                    "-export",
                    "-legacy",
                    "-in",
                    &crt_str,
                    "-inkey",
                    &key_str,
                    "-out",
                    &p12_str,
                    "-name",
                    common_name,
                    "-passout",
                    &p12_pass_arg,
                ],
            )
            .map_err(|e| CertFactoryError::Io(format!("openssl pkcs12 spawn: {e}")))?;
        if !p12_res.success() {
            let _ = fs::remove_dir_all(&tmp);
            return Err(CertFactoryError::Failed {
                stage: "openssl_pkcs12",
                message: format!(
                    "openssl pkcs12 -export -legacy exit={} stderr={}",
                    p12_res.status, p12_res.stderr
                ),
            });
        }

        Ok(GeneratedCertMaterial {
            tmp_dir: tmp,
            crt_path,
            p12_path,
            p12_passphrase: P12_PASSPHRASE.to_string(),
        })
    }
}

/// Tests cover the OpenSSL config emitter independently — it
/// is the one piece that can drift away from the macOS
/// keychain's parser without anybody noticing.
pub(crate) fn openssl_config(cn: &str, org: &str) -> String {
    format!(
        "[req]\n\
         distinguished_name = dn\n\
         prompt = no\n\
         req_extensions = v3_req\n\
         [dn]\n\
         CN = {cn}\n\
         O  = {org}\n\
         [v3_req]\n\
         keyUsage = critical,digitalSignature\n\
         extendedKeyUsage = critical,codeSigning\n\
         basicConstraints = critical,CA:FALSE\n"
    )
}

fn mkdtemp(prefix: &str) -> Result<PathBuf, CertFactoryError> {
    use rand::RngCore;
    let base = std::env::temp_dir();
    let pid = std::process::id();
    let mut rng = rand::rngs::OsRng;
    for _ in 0..16 {
        let mut bytes = [0u8; 8];
        rng.fill_bytes(&mut bytes);
        let suffix: String = bytes.iter().map(|b| format!("{b:02x}")).collect();
        let candidate = base.join(format!("{prefix}{pid}-{suffix}"));
        match fs::create_dir(&candidate) {
            Ok(_) => {
                let _ = fs::set_permissions(&candidate, fs::Permissions::from_mode(0o700));
                return Ok(candidate);
            }
            Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists => continue,
            Err(e) => return Err(CertFactoryError::Io(format!("mkdtemp: {e}"))),
        }
    }
    Err(CertFactoryError::Io("mkdtemp: out of retries".to_string()))
}

#[cfg(test)]
mod tests {
    use super::super::process::test_support::MockRunner;
    use super::*;

    #[test]
    fn openssl_config_carries_required_extensions() {
        let cnf = openssl_config("ACME Cert", "Acme Corp");
        assert!(cnf.contains("CN = ACME Cert"));
        assert!(cnf.contains("O  = Acme Corp"));
        assert!(cnf.contains("keyUsage = critical,digitalSignature"));
        assert!(cnf.contains("extendedKeyUsage = critical,codeSigning"));
        assert!(cnf.contains("basicConstraints = critical,CA:FALSE"));
        assert!(cnf.contains("req_extensions = v3_req"));
    }

    #[test]
    fn generate_invokes_openssl_req_then_pkcs12() {
        let runner = MockRunner::new();
        // Replies pop in reverse-push order — push pkcs12 first
        // so it lands after `req`.
        runner.enqueue(0, "", "");
        runner.enqueue(0, "", "");
        let factory = CertFactory::new(&runner);
        let _material = factory.generate("ACME", "Acme", 365).unwrap();
        let calls = runner.calls();
        assert_eq!(calls.len(), 2);
        assert_eq!(calls[0].executable, OPENSSL_PATH);
        assert_eq!(calls[0].args[0], "req");
        assert!(calls[0].args.contains(&"-x509".to_string()));
        assert!(calls[0].args.contains(&"rsa:2048".to_string()));
        assert!(calls[0].args.contains(&"v3_req".to_string()));
        assert_eq!(calls[1].args[0], "pkcs12");
        assert!(calls[1].args.contains(&"-legacy".to_string()));
        assert!(calls[1].args.contains(&"-export".to_string()));
    }

    #[test]
    fn generate_propagates_openssl_req_failure() {
        let runner = MockRunner::new();
        runner.enqueue(1, "", "boom");
        let factory = CertFactory::new(&runner);
        let err = factory.generate("ACME", "Acme", 365).unwrap_err();
        match err {
            CertFactoryError::Failed { stage, .. } => assert_eq!(stage, "openssl_req"),
            other => panic!("unexpected: {other:?}"),
        }
    }

    #[test]
    fn generate_propagates_pkcs12_failure() {
        let runner = MockRunner::new();
        // Pop order — pkcs12 fails (status 5), req succeeds.
        runner.enqueue(5, "", "pkcs12 boom");
        runner.enqueue(0, "", "");
        let factory = CertFactory::new(&runner);
        let err = factory.generate("ACME", "Acme", 365).unwrap_err();
        match err {
            CertFactoryError::Failed { stage, .. } => assert_eq!(stage, "openssl_pkcs12"),
            other => panic!("unexpected: {other:?}"),
        }
    }
}
