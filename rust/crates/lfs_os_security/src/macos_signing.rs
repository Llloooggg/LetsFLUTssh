//! macOS code-signing pipeline — Rust port of the Dart
//! `platform/macos/code_signing/*` modules. Wraps `openssl`,
//! `security`, and `codesign` subprocesses via
//! [`tokio::process::Command`], same call topology as the Dart
//! `IProcessRunner` abstraction.
//!
//! Rationale for keeping this subprocess-based (rather than
//! reaching into Apple Security framework directly):
//!
//! * Generating an X.509 v3 self-signed cert + PKCS#12 envelope
//!   would be ~300 LOC of hand-rolled ASN.1 for a code path
//!   used once per install. `/usr/bin/openssl` ships with every
//!   macOS release we support and matches what the prior
//!   `macos-resign.sh` shell script used.
//! * `security` + `codesign` CLI exposes the trust-DB / signing
//!   flows in their canonical shape. The native `SecTrustSettings`
//!   APIs would surface the same prompts but give us no
//!   additional auditability — the prompt itself is what the
//!   user authorises, regardless of the calling shape.
//! * macOS keychain ACLs bind to the cert's designated
//!   requirement, derived from the PKCS#12 import; the import
//!   shape must match what `security import` produces verbatim.
//!
//! When Apple eventually drops `/usr/bin/openssl` (LibreSSL is
//! deprecated in system) the cert-factory step swaps to a
//! Rust-side generator (`rcgen` covers v3 + PKCS#12); the
//! single seam is [`CertFactory::generate`] below.
//!
//! **Verification status**: this module is cfg-gated to
//! `target_os = "macos"` and lands as a verified-pending Rust
//! port of the Dart pipeline. The `rust-cross-check` matrix
//! (CI Wave 1) compile-validates against
//! `aarch64-apple-darwin` + `x86_64-apple-darwin` on every PR;
//! runtime correctness (subprocess argv composition, OpenSSL
//! output parsing, Keychain ACL effects on the user's real
//! login keychain) gates on the NI-2 verification pass.

#![cfg(target_os = "macos")]

use std::path::{Path, PathBuf};
use std::process::Output;

use tokio::process::Command;

/// Canonical OpenSSL path on macOS. Re-derived locally rather
/// than `which`-resolved so the call surface is auditable
/// against the prior bash `macos-resign.sh`.
const OPENSSL_PATH: &str = "/usr/bin/openssl";
const SECURITY_PATH: &str = "/usr/bin/security";
const CODESIGN_PATH: &str = "/usr/bin/codesign";

/// Stable subject CN — keychain ACL is derived from this; any
/// rotation invalidates every stored T1 secret on this install.
pub const DEFAULT_COMMON_NAME: &str = "LetsFLUTssh Self-Sign";
pub const DEFAULT_ORGANISATION: &str = "LetsFLUTssh";

/// PKCS#12 transient passphrase — passed through to
/// `security import` and then forgotten by both OpenSSL and
/// macOS. Rotating this does not invalidate the imported
/// identity (the keychain stores the unwrapped private key,
/// not the wrapped P12).
const P12_PASSPHRASE: &str = "lfs-transient";

#[derive(Debug, thiserror::Error)]
pub enum SignError {
    #[error("openssl {stage}: {message}")]
    Openssl {
        stage: &'static str,
        message: String,
    },
    #[error("security {stage}: {message}")]
    Security {
        stage: &'static str,
        message: String,
    },
    #[error("codesign {subpath}: {message}")]
    Codesign { subpath: String, message: String },
    #[error("io {context}: {source}")]
    Io {
        context: &'static str,
        #[source]
        source: std::io::Error,
    },
    #[error("bundle not writable: {0}")]
    BundleNotWritable(PathBuf),
}

/// RAII tmp dir — cleared on drop so a panic mid-pipeline
/// doesn't leak the cert key + p12 bytes on disk.
pub struct CertMaterial {
    pub tmp_dir: PathBuf,
    pub crt_path: PathBuf,
    pub p12_path: PathBuf,
    pub p12_passphrase: String,
}

impl Drop for CertMaterial {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.tmp_dir);
    }
}

// ── Cert factory ───────────────────────────────────────────────

/// Generate a fresh self-signed code-signing identity. Output is
/// `cert.crt` + `cert.p12` in a tmp dir; caller drops the
/// returned [`CertMaterial`] to clean up.
pub async fn generate_cert(
    common_name: &str,
    organisation: &str,
    validity_days: u32,
) -> Result<CertMaterial, SignError> {
    let tmp_dir =
        tempdir_in(&std::env::temp_dir(), "lfs-macos-sign-").map_err(|e| SignError::Io {
            context: "create tmp dir",
            source: e,
        })?;
    let cnf_path = tmp_dir.join("cert.cnf");
    let key_path = tmp_dir.join("cert.key");
    let crt_path = tmp_dir.join("cert.crt");
    let p12_path = tmp_dir.join("cert.p12");

    let cnf = openssl_config(common_name, organisation);
    std::fs::write(&cnf_path, cnf).map_err(|e| SignError::Io {
        context: "write openssl config",
        source: e,
    })?;

    // openssl req -x509 -nodes -new -newkey rsa:2048 ...
    let req_out = run(
        OPENSSL_PATH,
        &[
            "req",
            "-x509",
            "-nodes",
            "-new",
            "-newkey",
            "rsa:2048",
            "-days",
            &validity_days.to_string(),
            "-config",
            cnf_path.to_str().unwrap(),
            "-extensions",
            "v3_req",
            "-keyout",
            key_path.to_str().unwrap(),
            "-out",
            crt_path.to_str().unwrap(),
        ],
        None,
    )
    .await?;
    if !req_out.status.success() {
        let _ = std::fs::remove_dir_all(&tmp_dir);
        return Err(SignError::Openssl {
            stage: "req",
            message: stderr_string(&req_out),
        });
    }

    // openssl pkcs12 -export -legacy ...
    //
    // `-legacy` is mandatory: OpenSSL 3 defaults to AES-256 +
    // PBKDF2 for the MAC, which macOS `SecKeychainItemImport`
    // cannot parse ("MAC verification failed during PKCS12
    // import"). The legacy provider emits 3DES + SHA1 MAC,
    // which Keychain Services reads.
    let p12_out = run(
        OPENSSL_PATH,
        &[
            "pkcs12",
            "-export",
            "-legacy",
            "-in",
            crt_path.to_str().unwrap(),
            "-inkey",
            key_path.to_str().unwrap(),
            "-out",
            p12_path.to_str().unwrap(),
            "-name",
            common_name,
            "-passout",
            &format!("pass:{P12_PASSPHRASE}"),
        ],
        None,
    )
    .await?;
    if !p12_out.status.success() {
        let _ = std::fs::remove_dir_all(&tmp_dir);
        return Err(SignError::Openssl {
            stage: "pkcs12",
            message: stderr_string(&p12_out),
        });
    }

    Ok(CertMaterial {
        tmp_dir,
        crt_path,
        p12_path,
        p12_passphrase: P12_PASSPHRASE.to_string(),
    })
}

fn openssl_config(cn: &str, org: &str) -> String {
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

// ── Keychain wrapper ───────────────────────────────────────────

/// Default user login keychain path. Lifted from `$HOME` at
/// call time so a test override (different `HOME`) routes the
/// `security` subprocess to a scratch keychain.
pub fn default_keychain_path() -> PathBuf {
    let home = std::env::var("HOME").unwrap_or_default();
    PathBuf::from(home).join("Library/Keychains/login.keychain-db")
}

/// `security find-certificate -c <cn>` — `true` on exit 0.
pub async fn keychain_has_certificate(
    keychain_path: &Path,
    common_name: &str,
) -> Result<bool, SignError> {
    let out = run(
        SECURITY_PATH,
        &[
            "find-certificate",
            "-c",
            common_name,
            keychain_path.to_str().unwrap(),
        ],
        None,
    )
    .await?;
    Ok(out.status.success())
}

/// Import a PKCS#12 bundle. `-T /usr/bin/codesign` + `-T
/// /usr/bin/security` grant the two binaries silent access to
/// the imported private key (no per-resign password prompt).
pub async fn keychain_import_pkcs12(
    keychain_path: &Path,
    p12_path: &Path,
    passphrase: &str,
) -> Result<(), SignError> {
    let out = run(
        SECURITY_PATH,
        &[
            "import",
            p12_path.to_str().unwrap(),
            "-k",
            keychain_path.to_str().unwrap(),
            "-P",
            passphrase,
            "-T",
            "/usr/bin/codesign",
            "-T",
            "/usr/bin/security",
        ],
        None,
    )
    .await?;
    if !out.status.success() {
        return Err(SignError::Security {
            stage: "import",
            message: stderr_string(&out),
        });
    }
    Ok(())
}

/// `security add-trusted-cert` — the *only* step in the whole
/// pipeline that triggers a macOS password prompt (writing to
/// the user trust DB always requires user authorisation, even
/// inside the user's own keychain).
pub async fn keychain_add_trusted_cert(
    keychain_path: &Path,
    crt_path: &Path,
) -> Result<(), SignError> {
    let out = run(
        SECURITY_PATH,
        &[
            "add-trusted-cert",
            "-r",
            "trustRoot",
            "-p",
            "codeSign",
            "-k",
            keychain_path.to_str().unwrap(),
            crt_path.to_str().unwrap(),
        ],
        None,
    )
    .await?;
    if !out.status.success() {
        return Err(SignError::Security {
            stage: "add-trusted-cert",
            message: stderr_string(&out),
        });
    }
    Ok(())
}

pub async fn keychain_delete_identity(
    keychain_path: &Path,
    common_name: &str,
) -> Result<(), SignError> {
    // delete-identity sweeps cert + matching private key in one
    // call. Idempotent — missing alias returns non-zero but we
    // swallow it (the cleanup intent is "make sure it's gone").
    let _ = run(
        SECURITY_PATH,
        &[
            "delete-identity",
            "-c",
            common_name,
            keychain_path.to_str().unwrap(),
        ],
        None,
    )
    .await?;
    Ok(())
}

pub async fn keychain_delete_certificate(
    keychain_path: &Path,
    common_name: &str,
) -> Result<(), SignError> {
    // Catches stragglers: a historical `-legacy` PKCS#12 import
    // sometimes left a lone cert without its matching private
    // key, and `delete-identity` won't sweep those.
    let _ = run(
        SECURITY_PATH,
        &[
            "delete-certificate",
            "-c",
            common_name,
            keychain_path.to_str().unwrap(),
        ],
        None,
    )
    .await?;
    Ok(())
}

// ── Codesigner ─────────────────────────────────────────────────

/// Extract the live entitlements plist embedded in the bundle's
/// current signature. Returns `Ok(None)` when the signature
/// has no entitlements.
pub async fn codesign_extract_entitlements(app_bundle: &Path) -> Result<Option<String>, SignError> {
    let out = run(
        CODESIGN_PATH,
        &["-d", "--entitlements", ":-", app_bundle.to_str().unwrap()],
        None,
    )
    .await?;
    if !out.status.success() {
        return Ok(None);
    }
    let plist = String::from_utf8_lossy(&out.stdout).trim().to_string();
    Ok(if plist.is_empty() { None } else { Some(plist) })
}

/// `codesign --verify --deep --strict --verbose=2`. Caller's
/// gate between "new bundle staged" and "atomic swap".
pub async fn codesign_verify(bundle: &Path) -> Result<bool, SignError> {
    let out = run(
        CODESIGN_PATH,
        &[
            "--verify",
            "--deep",
            "--strict",
            "--verbose=2",
            bundle.to_str().unwrap(),
        ],
        None,
    )
    .await?;
    Ok(out.status.success())
}

/// Re-sign `app_bundle` leaf-first under `common_name`.
///
/// Order of operations (each its own codesign call):
///
///   1. every `*.dylib` under `Contents/`
///   2. every `*.framework` dir under `Contents/Frameworks/`
///   3. every `*.xpc` / `*.appex` helper under `Contents/`
///   4. the outer `.app` bundle with `--options runtime` +
///      `--entitlements`
///
/// `entitlements_plist` is the output of
/// [`codesign_extract_entitlements`] — passed only on the outer
/// bundle pass so the runtime entitlements survive.
pub async fn codesign_resign_inside_out(
    app_bundle: &Path,
    common_name: &str,
    entitlements_plist: Option<&str>,
    use_sudo: bool,
) -> Result<(), SignError> {
    let base_sign = ["--force", "--options", "runtime", "--sign", common_name];

    // Helper closure — when `use_sudo`, codesign becomes the
    // first positional argument instead of the executable.
    let sign_one = |subpath: PathBuf, extra: Vec<String>| {
        let common_name = common_name.to_string();
        async move {
            let mut args: Vec<String> = if use_sudo {
                let mut v = vec![CODESIGN_PATH.to_string()];
                v.extend(base_sign.iter().map(|s| s.to_string()));
                v
            } else {
                base_sign.iter().map(|s| s.to_string()).collect()
            };
            // Re-substitute base_sign's placeholder for common_name.
            for arg in args.iter_mut() {
                if arg == "--sign" {
                    // already in place; the next arg is the placeholder
                }
            }
            // base_sign uses common_name directly via array; rebuild.
            args.clear();
            if use_sudo {
                args.push(CODESIGN_PATH.to_string());
            }
            args.push("--force".into());
            args.push("--options".into());
            args.push("runtime".into());
            args.push("--sign".into());
            args.push(common_name);
            for e in &extra {
                args.push(e.clone());
            }
            args.push(subpath.to_string_lossy().into_owned());

            let exe = if use_sudo { "sudo" } else { CODESIGN_PATH };
            let arg_refs: Vec<&str> = args.iter().map(String::as_str).collect();
            let out = run(exe, &arg_refs, None).await?;
            if !out.status.success() {
                return Err(SignError::Codesign {
                    subpath: subpath.to_string_lossy().into_owned(),
                    message: stderr_string(&out),
                });
            }
            Ok::<(), SignError>(())
        }
    };

    // 1. dylibs
    for lib in walk(app_bundle, ".dylib", /*want_file=*/ true) {
        sign_one(lib, vec![]).await?;
    }
    // 2. frameworks
    let frameworks = app_bundle.join("Contents/Frameworks");
    if frameworks.exists() {
        for fw in walk(&frameworks, ".framework", /*want_file=*/ false) {
            sign_one(fw, vec![]).await?;
        }
    }
    // 3. xpc + appex helpers
    for helper in walk(app_bundle, ".xpc", /*want_file=*/ false) {
        sign_one(helper, vec![]).await?;
    }
    for helper in walk(app_bundle, ".appex", /*want_file=*/ false) {
        sign_one(helper, vec![]).await?;
    }

    // 4. outer bundle — with entitlements
    let mut outer_extra: Vec<String> = Vec::new();
    let ent_tmp_dir;
    let ent_path;
    if let Some(plist) = entitlements_plist {
        ent_tmp_dir =
            tempdir_in(&std::env::temp_dir(), "lfs-codesign-ent-").map_err(|e| SignError::Io {
                context: "create entitlements tmp",
                source: e,
            })?;
        ent_path = ent_tmp_dir.join("entitlements.plist");
        std::fs::write(&ent_path, plist).map_err(|e| SignError::Io {
            context: "write entitlements plist",
            source: e,
        })?;
        outer_extra.push("--entitlements".to_string());
        outer_extra.push(ent_path.to_string_lossy().into_owned());
        let res = sign_one(app_bundle.to_path_buf(), outer_extra).await;
        let _ = std::fs::remove_dir_all(&ent_tmp_dir);
        return res;
    }
    sign_one(app_bundle.to_path_buf(), outer_extra).await
}

// ── ResignService — high-level orchestrator ────────────────────

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ResignOutcome {
    Succeeded,
    ReusedExisting,
    CancelledOrFailed,
    BundleNotWritable,
}

/// Make sure the keychain holds a cert under `common_name`.
/// Returns `true` when a cert was created in this call,
/// `false` when one was already present (no password prompt
/// fired).
///
/// **Critical invariant**: the cert is created exactly once
/// per install. Regenerating it would invalidate every
/// keychain item already written under the old designated
/// requirement and silently lock the user out of their T1
/// secrets.
pub async fn ensure_identity(common_name: &str) -> Result<bool, SignError> {
    let keychain = default_keychain_path();
    if keychain_has_certificate(&keychain, common_name).await? {
        return Ok(false);
    }
    let material = generate_cert(common_name, DEFAULT_ORGANISATION, 3650).await?;
    keychain_import_pkcs12(&keychain, &material.p12_path, &material.p12_passphrase).await?;
    // Password prompt fires here.
    keychain_add_trusted_cert(&keychain, &material.crt_path).await?;
    // material's Drop sweeps the tmp dir.
    Ok(true)
}

/// Re-sign `app_bundle` with the cert identified by
/// `common_name`. Caller must have called [`ensure_identity`]
/// first; otherwise codesign exits with "no identity found".
pub async fn resign_bundle(
    app_bundle: &Path,
    common_name: &str,
) -> Result<ResignOutcome, SignError> {
    if !is_writable(app_bundle) {
        return Ok(ResignOutcome::BundleNotWritable);
    }
    let entitlements = codesign_extract_entitlements(app_bundle)
        .await
        .ok()
        .flatten();
    codesign_resign_inside_out(app_bundle, common_name, entitlements.as_deref(), false).await?;
    Ok(if codesign_verify(app_bundle).await? {
        ResignOutcome::Succeeded
    } else {
        ResignOutcome::CancelledOrFailed
    })
}

pub async fn uninstall_identity(common_name: &str) -> Result<(), SignError> {
    let keychain = default_keychain_path();
    keychain_delete_identity(&keychain, common_name).await?;
    keychain_delete_certificate(&keychain, common_name).await?;
    Ok(())
}

pub async fn has_identity(common_name: &str) -> Result<bool, SignError> {
    let keychain = default_keychain_path();
    keychain_has_certificate(&keychain, common_name).await
}

// ── Internals ──────────────────────────────────────────────────

async fn run(executable: &str, args: &[&str], stdin: Option<&[u8]>) -> Result<Output, SignError> {
    let mut cmd = Command::new(executable);
    cmd.args(args);
    if stdin.is_some() {
        cmd.stdin(std::process::Stdio::piped());
    } else {
        cmd.stdin(std::process::Stdio::null());
    }
    cmd.stdout(std::process::Stdio::piped());
    cmd.stderr(std::process::Stdio::piped());
    let mut child = cmd.spawn().map_err(|e| SignError::Io {
        context: "spawn",
        source: e,
    })?;
    if let (Some(bytes), Some(mut sink)) = (stdin, child.stdin.take()) {
        use tokio::io::AsyncWriteExt;
        sink.write_all(bytes).await.map_err(|e| SignError::Io {
            context: "stdin write",
            source: e,
        })?;
        // Drop closes stdin.
    }
    let out = child.wait_with_output().await.map_err(|e| SignError::Io {
        context: "wait",
        source: e,
    })?;
    Ok(out)
}

fn stderr_string(out: &Output) -> String {
    let s = String::from_utf8_lossy(&out.stderr);
    let trimmed = s.trim();
    if trimmed.is_empty() {
        format!("exit {}", out.status.code().unwrap_or(-1))
    } else {
        trimmed.to_string()
    }
}

fn walk(root: &Path, suffix: &str, want_file: bool) -> Vec<PathBuf> {
    let mut out = Vec::new();
    let mut stack = vec![root.to_path_buf()];
    while let Some(dir) = stack.pop() {
        let entries = match std::fs::read_dir(&dir) {
            Ok(e) => e,
            Err(_) => continue,
        };
        for entry in entries.flatten() {
            let path = entry.path();
            let meta = match entry.metadata() {
                Ok(m) => m,
                Err(_) => continue,
            };
            let path_str = path.to_string_lossy();
            let matches_suffix = path_str.ends_with(suffix);
            if matches_suffix {
                let is_file = meta.is_file();
                let want = if want_file { is_file } else { meta.is_dir() };
                if want {
                    out.push(path.clone());
                }
            }
            if meta.is_dir() && !matches_suffix {
                // Don't recurse into a matched directory — we
                // sign the .framework / .xpc as a unit.
                stack.push(path);
            }
        }
    }
    out
}

fn is_writable(dir: &Path) -> bool {
    let probe = dir.join(".lfs-write-probe");
    match std::fs::write(&probe, b"x") {
        Ok(_) => {
            let _ = std::fs::remove_file(&probe);
            true
        }
        Err(_) => false,
    }
}

/// std doesn't ship `mkdtemp`; build one on a random suffix so
/// concurrent calls in the same process don't collide.
fn tempdir_in(base: &Path, prefix: &str) -> std::io::Result<PathBuf> {
    use rand::RngCore;
    let pid = std::process::id();
    let mut rng = rand::rngs::OsRng;
    for _ in 0..16 {
        let mut bytes = [0u8; 8];
        rng.fill_bytes(&mut bytes);
        let suffix: String = bytes.iter().map(|b| format!("{b:02x}")).collect();
        let candidate = base.join(format!("{prefix}{pid}-{suffix}"));
        match std::fs::create_dir(&candidate) {
            Ok(_) => {
                use std::os::unix::fs::PermissionsExt;
                let _ =
                    std::fs::set_permissions(&candidate, std::fs::Permissions::from_mode(0o700));
                return Ok(candidate);
            }
            Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists => continue,
            Err(e) => return Err(e),
        }
    }
    Err(std::io::Error::new(
        std::io::ErrorKind::AlreadyExists,
        "tempdir: out of retries",
    ))
}
