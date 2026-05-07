//! Self-sign / re-sign pipeline for the macOS bundle.
//!
//! Mirrors the prior Dart `lib/platform/macos/code_signing/`
//! orchestrator function-for-function — same subprocess
//! grammar, same ordering, same idempotency. Moving the logic
//! here keeps Dart on the rendering side of the Rust split.
//!
//! ## Pipeline overview
//!
//! 1. **`ensure_identity(common_name)`** — checks the user's
//!    login keychain for an existing cert under `common_name`;
//!    if absent, generates a fresh self-signed cert via
//!    `/usr/bin/openssl`, packages it as PKCS#12, imports via
//!    `/usr/bin/security import`, and adds the cert to the
//!    user-domain trust DB scoped to `codeSign`. Returns `true`
//!    when a cert was created in this call, `false` when one
//!    already existed.
//!
//! 2. **`resign_bundle(bundle_path, common_name)`** — extracts
//!    the live entitlements plist from the bundle's current
//!    signature, then signs leaf-first (dylibs → frameworks →
//!    xpc/appex → outer `.app` with `--options runtime` +
//!    `--entitlements`) so Keychain Services keeps recognising
//!    the bundle as the same designated requirement after
//!    auto-update.
//!
//! 3. **`uninstall_identity(common_name)`** — drops the
//!    identity + cert. The trust-DB entry survives but becomes
//!    a dangling reference (macOS skips entries whose cert is
//!    missing), which is equivalent to removal — see the prior
//!    Dart `ResignService.uninstallIdentity` rationale.
//!
//! 4. **`has_identity(common_name)`** — read-only probe used by
//!    settings UI to decide between "Enable secure tiers" and
//!    "Remove secure identity".

#![cfg(target_os = "macos")]

use std::path::{Path, PathBuf};
use std::process::Stdio;

use tokio::fs;
use tokio::process::Command;

/// Outcome enum returned by [`resign_bundle`]. Mirrors the prior
/// Dart `ResignOutcome` shape; the values are 1:1 with the
/// settings-UI branches that consume them.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ResignOutcome {
    Succeeded,
    CancelledOrFailed,
    BundleNotWritable,
}

/// Pipeline error. The `stage` discriminator keeps the
/// settings-UI error toast pinpointable to a specific subprocess
/// step.
#[derive(Debug)]
pub enum Error {
    /// A subprocess (`openssl` / `security` / `codesign`) exited
    /// non-zero. `stage` tags which step (e.g. `"openssl_req"`,
    /// `"security_import"`, `"codesign:Contents/MacOS/foo"`).
    Subprocess {
        stage: String,
        exit_code: Option<i32>,
        stderr: String,
    },
    /// Local file-system operation (mkdir tmp, read/write tmp
    /// plist, walk the bundle tree) returned an `io::Error`.
    Io(std::io::Error),
}

impl std::fmt::Display for Error {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Error::Subprocess {
                stage,
                exit_code,
                stderr,
            } => write!(
                f,
                "{stage} exited {}: {stderr}",
                exit_code.map_or_else(|| "<signal>".into(), |c| c.to_string())
            ),
            Error::Io(e) => write!(f, "io: {e}"),
        }
    }
}

impl std::error::Error for Error {}

impl From<std::io::Error> for Error {
    fn from(e: std::io::Error) -> Self {
        Error::Io(e)
    }
}

/// Default subject CN. Stable across releases — changing it
/// invalidates every keychain item already minted under the
/// existing designated requirement.
pub const DEFAULT_COMMON_NAME: &str = "LetsFLUTssh Self-Sign";

const DEFAULT_ORGANISATION: &str = "LetsFLUTssh";

// Tool paths. macOS ships these at fixed locations; using
// absolute paths bypasses any `PATH` shenanigans an installer
// might inflict.
const OPENSSL: &str = "/usr/bin/openssl";
const SECURITY: &str = "/usr/bin/security";
const CODESIGN: &str = "/usr/bin/codesign";

/// PKCS#12 passphrase. Held in-memory only — `security import`
/// strips it on landing the bundle into the keychain. Rotating
/// it does not invalidate the imported identity.
const P12_PASSPHRASE: &str = "lfs-transient";

/// Returns `true` when a cert with `common_name` exists in the
/// user's login keychain. Cheaper read-only counterpart to
/// `ensure_identity`.
pub async fn has_identity(common_name: &str) -> Result<bool, Error> {
    let path = login_keychain_path()?;
    let res = Command::new(SECURITY)
        .args(["find-certificate", "-c", common_name])
        .arg(&path)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .await?;
    Ok(res.success())
}

/// Make sure a cert under `common_name` lives in the user's
/// login keychain. Returns `true` when a fresh cert was created
/// in this call (the user saw the macOS password prompt for the
/// trust-DB write); `false` when an existing cert was reused
/// silently.
pub async fn ensure_identity(common_name: &str) -> Result<bool, Error> {
    if has_identity(common_name).await? {
        return Ok(false);
    }
    let material = generate_cert(common_name).await?;
    let result = (async {
        let keychain = login_keychain_path()?;
        run_security_import(&material.p12_path, &keychain).await?;
        run_security_add_trusted_cert(&material.crt_path, &keychain).await?;
        Ok::<(), Error>(())
    })
    .await;
    // Tmp dir cleanup runs regardless of success — the PKCS#12 +
    // private key bytes never need to survive past `security
    // import`'s landing the identity in the keychain.
    let _ = fs::remove_dir_all(&material.tmp_dir).await;
    result?;
    Ok(true)
}

/// Re-sign the bundle at `bundle_path` with the cert under
/// `common_name`. Caller must have run [`ensure_identity`]
/// earlier — codesign fails with "no identity found" otherwise.
pub async fn resign_bundle(bundle_path: &Path, common_name: &str) -> Result<ResignOutcome, Error> {
    if !is_writable(bundle_path).await {
        return Ok(ResignOutcome::BundleNotWritable);
    }
    let entitlements = extract_entitlements(bundle_path).await?;
    resign_inside_out(bundle_path, common_name, entitlements.as_deref()).await?;
    let ok = verify(bundle_path).await?;
    Ok(if ok {
        ResignOutcome::Succeeded
    } else {
        ResignOutcome::CancelledOrFailed
    })
}

/// Read the entitlements plist embedded in the bundle's current
/// signature. Returns `None` when the signature carries no
/// entitlements (CI ad-hoc bundle without `Release.entitlements`,
/// or a corrupt one). The installer uses pre-/post-resign
/// snapshots of this value to detect a re-sign that silently
/// stripped `keychain-access-groups`, which would survive
/// `codesign --verify` but kill T1 keychain access at first read.
pub async fn extract_entitlements_for_bundle(bundle_path: &Path) -> Result<Option<String>, Error> {
    extract_entitlements(bundle_path).await
}

/// Run `codesign --verify --deep --strict --verbose=2` against
/// the bundle. Returns `true` on a clean exit. Used by the
/// installer to gate the atomic swap on a structurally-sound
/// staged bundle.
pub async fn verify_bundle(bundle_path: &Path) -> Result<bool, Error> {
    verify(bundle_path).await
}

/// Drop the identity + cert from the user's login keychain.
/// Subsequent `has_identity(common_name)` returns `false` until
/// the next `ensure_identity` rebuilds the slot.
pub async fn uninstall_identity(common_name: &str) -> Result<(), Error> {
    let keychain = login_keychain_path()?;
    // Both calls are best-effort — they routinely return
    // non-zero on a clean keychain (nothing to delete) and that
    // is the success path from the caller's POV.
    let _ = Command::new(SECURITY)
        .args(["delete-identity", "-c", common_name])
        .arg(&keychain)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .await;
    let _ = Command::new(SECURITY)
        .args(["delete-certificate", "-c", common_name])
        .arg(&keychain)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .await;
    Ok(())
}

// ---- internal helpers --------------------------------------------------

struct CertMaterial {
    tmp_dir: PathBuf,
    crt_path: PathBuf,
    p12_path: PathBuf,
}

fn login_keychain_path() -> Result<PathBuf, Error> {
    let home = std::env::var_os("HOME").ok_or_else(|| {
        Error::Io(std::io::Error::new(
            std::io::ErrorKind::NotFound,
            "HOME env var unset — cannot resolve login keychain",
        ))
    })?;
    Ok(PathBuf::from(home).join("Library/Keychains/login.keychain-db"))
}

async fn generate_cert(common_name: &str) -> Result<CertMaterial, Error> {
    // `tokio::fs` does not expose a `create_temp_dir`; fall back
    // to the `tempfile` crate would add a workspace dep for one
    // call site, so we hand-roll a non-colliding path under
    // `std::env::temp_dir()` instead.
    let tmp_dir = make_temp_dir("lfs-macos-sign-").await?;
    let cnf_path = tmp_dir.join("cert.cnf");
    let key_path = tmp_dir.join("cert.key");
    let crt_path = tmp_dir.join("cert.crt");
    let p12_path = tmp_dir.join("cert.p12");

    fs::write(&cnf_path, openssl_config(common_name, DEFAULT_ORGANISATION)).await?;

    run_subprocess(
        OPENSSL,
        &[
            "req",
            "-x509",
            "-nodes",
            "-new",
            "-newkey",
            "rsa:2048",
            "-days",
            "3650",
            "-config",
            &cnf_path.to_string_lossy(),
            "-extensions",
            "v3_req",
            "-keyout",
            &key_path.to_string_lossy(),
            "-out",
            &crt_path.to_string_lossy(),
        ],
        "openssl_req",
    )
    .await?;

    run_subprocess(
        OPENSSL,
        &[
            "pkcs12",
            "-export",
            "-legacy",
            "-in",
            &crt_path.to_string_lossy(),
            "-inkey",
            &key_path.to_string_lossy(),
            "-out",
            &p12_path.to_string_lossy(),
            "-name",
            common_name,
            "-passout",
            &format!("pass:{P12_PASSPHRASE}"),
        ],
        "openssl_pkcs12",
    )
    .await?;

    Ok(CertMaterial {
        tmp_dir,
        crt_path,
        p12_path,
    })
}

async fn make_temp_dir(prefix: &str) -> Result<PathBuf, Error> {
    use std::sync::atomic::{AtomicU64, Ordering};
    static SEQ: AtomicU64 = AtomicU64::new(0);
    let n = SEQ.fetch_add(1, Ordering::Relaxed);
    let pid = std::process::id();
    // `nanos()` collides under sub-microsecond loops; combine
    // with the per-process atomic so tests that hammer this
    // function in parallel get distinct paths.
    let nanos = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.subsec_nanos())
        .unwrap_or(0);
    let path = std::env::temp_dir().join(format!("{prefix}{pid}-{n}-{nanos}"));
    fs::create_dir_all(&path).await?;
    Ok(path)
}

fn openssl_config(cn: &str, org: &str) -> String {
    format!(
        "[req]
distinguished_name = dn
prompt = no
req_extensions = v3_req
[dn]
CN = {cn}
O  = {org}
[v3_req]
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
basicConstraints = critical,CA:FALSE
"
    )
}

async fn run_security_import(p12: &Path, keychain: &Path) -> Result<(), Error> {
    run_subprocess(
        SECURITY,
        &[
            "import",
            &p12.to_string_lossy(),
            "-k",
            &keychain.to_string_lossy(),
            "-P",
            P12_PASSPHRASE,
            "-T",
            CODESIGN,
            "-T",
            SECURITY,
        ],
        "security_import",
    )
    .await
}

async fn run_security_add_trusted_cert(crt: &Path, keychain: &Path) -> Result<(), Error> {
    run_subprocess(
        SECURITY,
        &[
            "add-trusted-cert",
            "-r",
            "trustRoot",
            "-p",
            "codeSign",
            "-k",
            &keychain.to_string_lossy(),
            &crt.to_string_lossy(),
        ],
        "security_add_trusted_cert",
    )
    .await
}

async fn is_writable(dir: &Path) -> bool {
    // Ephemeral probe — create + delete a file inside the
    // bundle root. Succeeds only when the user owns the bundle
    // tree; root-owned `/Applications/letsflutssh.app` trips
    // the error and we route the user to the admin-prompt
    // fallback.
    let probe = dir.join(".lfs-write-probe");
    if fs::write(&probe, b"x").await.is_err() {
        return false;
    }
    let _ = fs::remove_file(&probe).await;
    true
}

async fn extract_entitlements(bundle_path: &Path) -> Result<Option<String>, Error> {
    let output = Command::new(CODESIGN)
        .args(["-d", "--entitlements", ":-"])
        .arg(bundle_path)
        .output()
        .await?;
    if !output.status.success() {
        return Ok(None);
    }
    let plist = String::from_utf8_lossy(&output.stdout).trim().to_string();
    Ok(if plist.is_empty() { None } else { Some(plist) })
}

async fn resign_inside_out(
    bundle_path: &Path,
    common_name: &str,
    entitlements_plist: Option<&str>,
) -> Result<(), Error> {
    // Order of operations matches the prior Dart implementation:
    //   1. every `*.dylib` under `Contents/`
    //   2. every `*.framework` dir under `Contents/Frameworks/`
    //   3. every `*.xpc` / `*.appex` helper under `Contents/`
    //   4. the outer `.app` with `--options runtime` + entitlements
    let dylibs = walk_extension(bundle_path, ".dylib", true).await;
    for path in dylibs {
        sign_one(&path, common_name, &[]).await?;
    }

    let frameworks_dir = bundle_path.join("Contents/Frameworks");
    if frameworks_dir.is_dir() {
        let frameworks = walk_extension(&frameworks_dir, ".framework", false).await;
        for path in frameworks {
            sign_one(&path, common_name, &[]).await?;
        }
    }

    let xpc = walk_extension(bundle_path, ".xpc", false).await;
    for path in xpc {
        sign_one(&path, common_name, &[]).await?;
    }
    let appex = walk_extension(bundle_path, ".appex", false).await;
    for path in appex {
        sign_one(&path, common_name, &[]).await?;
    }

    // Outer bundle — entitlements pass.
    let mut tmp_dir: Option<PathBuf> = None;
    let entitlements_path = if let Some(plist) = entitlements_plist {
        let dir = make_temp_dir("lfs-codesign-ent-").await?;
        let path = dir.join("entitlements.plist");
        fs::write(&path, plist).await?;
        tmp_dir = Some(dir);
        Some(path)
    } else {
        None
    };
    let outer_extra: Vec<String> = entitlements_path
        .as_ref()
        .map(|p| {
            vec![
                "--entitlements".to_string(),
                p.to_string_lossy().into_owned(),
            ]
        })
        .unwrap_or_default();
    let outer_extra_refs: Vec<&str> = outer_extra.iter().map(String::as_str).collect();
    let result = sign_one(bundle_path, common_name, &outer_extra_refs).await;
    if let Some(dir) = tmp_dir {
        let _ = fs::remove_dir_all(&dir).await;
    }
    result
}

async fn sign_one(path: &Path, common_name: &str, extra: &[&str]) -> Result<(), Error> {
    let mut args: Vec<&str> = vec!["--force", "--options", "runtime", "--sign", common_name];
    args.extend_from_slice(extra);
    let path_str = path.to_string_lossy();
    args.push(&path_str);
    let stage = format!("codesign:{}", path.display());
    run_subprocess(CODESIGN, &args, &stage).await
}

async fn verify(bundle: &Path) -> Result<bool, Error> {
    let res = Command::new(CODESIGN)
        .args(["--verify", "--deep", "--strict", "--verbose=2"])
        .arg(bundle)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .await?;
    Ok(res.success())
}

/// Recursive walk under `root` that yields paths whose final
/// component ends with `suffix`, filtered to files vs
/// directories. Mirrors the Dart `_walk` helper. Symlinks are
/// not followed (matches Dart's `followLinks: false`).
async fn walk_extension(root: &Path, suffix: &str, want_file: bool) -> Vec<PathBuf> {
    let root = root.to_path_buf();
    let suffix = suffix.to_string();
    // The walk is sync `std::fs` because `tokio::fs` does not
    // ship a recursive-walk helper and the directory tree is
    // tiny (Flutter macOS bundle = a few hundred entries). Run
    // it on the blocking pool so the FRB worker thread isn't
    // pinned by the disk seeks.
    tokio::task::spawn_blocking(move || {
        let mut out = Vec::new();
        walk_rec(&root, &suffix, want_file, &mut out);
        out
    })
    .await
    .unwrap_or_default()
}

fn walk_rec(dir: &Path, suffix: &str, want_file: bool, out: &mut Vec<PathBuf>) {
    let entries = match std::fs::read_dir(dir) {
        Ok(it) => it,
        Err(_) => return,
    };
    for entry in entries.flatten() {
        let path = entry.path();
        let metadata = match entry.metadata() {
            Ok(m) => m,
            Err(_) => continue,
        };
        // Match the Dart `followLinks: false` behaviour.
        if metadata.file_type().is_symlink() {
            continue;
        }
        let is_dir = metadata.is_dir();
        if path
            .file_name()
            .and_then(|n| n.to_str())
            .is_some_and(|n| n.ends_with(suffix))
            && (if want_file { !is_dir } else { is_dir })
        {
            out.push(path.clone());
        }
        if is_dir {
            walk_rec(&path, suffix, want_file, out);
        }
    }
}

async fn run_subprocess(program: &str, args: &[&str], stage: &str) -> Result<(), Error> {
    let output = Command::new(program).args(args).output().await?;
    if output.status.success() {
        Ok(())
    } else {
        Err(Error::Subprocess {
            stage: stage.to_string(),
            exit_code: output.status.code(),
            stderr: String::from_utf8_lossy(&output.stderr).into_owned(),
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn openssl_config_holds_the_expected_extensions() {
        let cfg = openssl_config("Test CN", "Test Org");
        assert!(cfg.contains("CN = Test CN"));
        assert!(cfg.contains("O  = Test Org"));
        assert!(cfg.contains("keyUsage = critical,digitalSignature"));
        assert!(cfg.contains("extendedKeyUsage = critical,codeSigning"));
        assert!(cfg.contains("basicConstraints = critical,CA:FALSE"));
    }

    #[tokio::test]
    async fn walk_extension_skips_symlinks_and_filters_by_suffix() {
        let dir = make_temp_dir("lfs-walk-").await.unwrap();
        std::fs::create_dir(dir.join("Contents")).unwrap();
        std::fs::write(dir.join("Contents/a.dylib"), b"x").unwrap();
        std::fs::write(dir.join("Contents/b.txt"), b"x").unwrap();
        std::fs::create_dir(dir.join("Contents/Frameworks")).unwrap();
        std::fs::create_dir(dir.join("Contents/Frameworks/Foo.framework")).unwrap();

        let dylibs = walk_extension(&dir, ".dylib", true).await;
        assert!(
            dylibs.iter().any(|p| p.ends_with("a.dylib")),
            "expected a.dylib in {dylibs:?}"
        );
        assert!(!dylibs.iter().any(|p| p.ends_with("b.txt")));

        let frameworks =
            walk_extension(&dir.join("Contents/Frameworks"), ".framework", false).await;
        assert!(
            frameworks.iter().any(|p| p.ends_with("Foo.framework")),
            "expected Foo.framework in {frameworks:?}"
        );

        let _ = fs::remove_dir_all(&dir).await;
    }

    #[tokio::test]
    async fn run_subprocess_surfaces_exit_code_and_stderr() {
        // `false` exits 1 with no stderr — exercises the Err
        // path without depending on macOS-specific tools.
        let res = run_subprocess("/usr/bin/false", &[], "false_smoke").await;
        match res {
            Err(Error::Subprocess {
                stage, exit_code, ..
            }) => {
                assert_eq!(stage, "false_smoke");
                assert_eq!(exit_code, Some(1));
            }
            other => panic!("expected Subprocess error, got {other:?}"),
        }
    }
}
