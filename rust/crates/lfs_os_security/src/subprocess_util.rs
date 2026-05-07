//! Cross-platform helpers used by per-OS modules.
//!
//! Lives outside any `cfg(target_os = "...")` gate so the unit
//! tests below run on every CI host (`rust-ci` only fires
//! `cargo test` on `ubuntu-latest`; the `rust-cross-check` matrix
//! is compile-validation only). Putting these helpers inside e.g.
//! `macos/code_signing.rs` would have made the tests dead weight
//! in CI.

// Every callsite outside the `#[cfg(test)]` block lives in
// `macos/code_signing.rs`, which is itself cfg-gated to macOS.
// On Linux / Windows the helpers register as `dead_code` against
// the lib build even though the test build does use them — the
// lint runs per-target. Allow at module scope so the lib build
// passes; tests remain real coverage.
#![allow(dead_code)]

use std::path::{Path, PathBuf};

use tokio::process::Command;

/// Outcome of a subprocess that returned non-zero. Keeps the
/// stage label, exit code, and stderr separate so callers can
/// build their own typed errors without re-parsing strings.
#[derive(Debug)]
pub(crate) struct SubprocessFailure {
    pub stage: String,
    pub exit_code: Option<i32>,
    pub stderr: String,
}

/// Composite error from [`run_subprocess`]: either the program
/// could not be spawned ([`RunError::Io`]) or it spawned but
/// exited non-zero ([`RunError::NonZero`]).
#[derive(Debug)]
pub(crate) enum RunError {
    NonZero(SubprocessFailure),
    Io(std::io::Error),
}

impl From<std::io::Error> for RunError {
    fn from(e: std::io::Error) -> Self {
        RunError::Io(e)
    }
}

/// Run `program` with `args` to completion. Returns `Ok` on a
/// clean exit, [`RunError::NonZero`] on a non-zero exit (with
/// the stage label, exit code, and captured stderr), and
/// [`RunError::Io`] on a spawn failure (executable not found,
/// permission error). The caller owns the stage label so the
/// composite error in their domain enum can localise the
/// failure to a specific pipeline step.
pub(crate) async fn run_subprocess(
    program: &str,
    args: &[&str],
    stage: &str,
) -> Result<(), RunError> {
    let output = Command::new(program).args(args).output().await?;
    if output.status.success() {
        Ok(())
    } else {
        Err(RunError::NonZero(SubprocessFailure {
            stage: stage.to_string(),
            exit_code: output.status.code(),
            stderr: String::from_utf8_lossy(&output.stderr).into_owned(),
        }))
    }
}

/// Recursive walk under `root` that yields paths whose final
/// component ends with `suffix`, filtered to files vs
/// directories. Symlinks are not followed.
///
/// The walk runs sync `std::fs` because `tokio::fs` does not
/// ship a recursive-walk helper and the directory trees this is
/// applied to are tiny (e.g. a Flutter macOS bundle = a few
/// hundred entries). Wrapped in `spawn_blocking` so the FRB
/// runtime worker isn't pinned by the disk seeks.
pub(crate) async fn walk_extension(root: &Path, suffix: &str, want_file: bool) -> Vec<PathBuf> {
    let root = root.to_path_buf();
    let suffix = suffix.to_string();
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

/// Construct the OpenSSL config snippet for self-signed
/// code-signing cert generation. Caller writes the result to a
/// tmp file and passes it to `openssl req -config <path>`. Lives
/// here (not inside `macos/code_signing.rs`) so the format-
/// stability assertion below runs on every CI host — the cert's
/// keyUsage / extendedKeyUsage / basicConstraints lines are the
/// load-bearing bits the macOS Keychain Services validates, and
/// a regression in this string would silently corrupt every
/// future cert.
pub(crate) fn openssl_self_sign_config(cn: &str, org: &str) -> String {
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

/// Sequence-suffixed temp dir under `std::env::temp_dir()`. Used
/// by per-OS modules that need a scratch tree for subprocess
/// inputs (e.g. the macOS cert-factory's `cert.cnf`/`cert.key`/
/// `cert.crt`/`cert.p12`). Per-process atomic + nanosecond mix
/// keeps tests that hammer this in parallel from colliding on
/// the same directory name.
pub(crate) async fn make_temp_dir(prefix: &str) -> Result<PathBuf, std::io::Error> {
    use std::sync::atomic::{AtomicU64, Ordering};
    static SEQ: AtomicU64 = AtomicU64::new(0);
    let n = SEQ.fetch_add(1, Ordering::Relaxed);
    let pid = std::process::id();
    let nanos = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.subsec_nanos())
        .unwrap_or(0);
    let path = std::env::temp_dir().join(format!("{prefix}{pid}-{n}-{nanos}"));
    tokio::fs::create_dir_all(&path).await?;
    Ok(path)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn openssl_self_sign_config_holds_the_expected_extensions() {
        let cfg = openssl_self_sign_config("Test CN", "Test Org");
        assert!(cfg.contains("CN = Test CN"));
        assert!(cfg.contains("O  = Test Org"));
        assert!(cfg.contains("keyUsage = critical,digitalSignature"));
        assert!(cfg.contains("extendedKeyUsage = critical,codeSigning"));
        assert!(cfg.contains("basicConstraints = critical,CA:FALSE"));
    }

    #[tokio::test]
    async fn walk_extension_filters_by_suffix_and_respects_want_file() {
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

        // walk_extension(dylib, want_file=true) must skip the
        // Foo.framework directory even though its name happens to
        // end with the suffix.
        let frameworks_as_files = walk_extension(&dir, ".framework", true).await;
        assert!(frameworks_as_files.is_empty());

        let _ = tokio::fs::remove_dir_all(&dir).await;
    }

    #[tokio::test]
    async fn run_subprocess_returns_ok_on_zero_exit() {
        // `cargo --version` exists on every CI runner because the
        // workflow runs cargo to build/test in the first place.
        // Same trick keeps the test cross-platform without
        // depending on `/usr/bin/true`-style POSIX-only commands.
        run_subprocess("cargo", &["--version"], "cargo_smoke")
            .await
            .expect("cargo --version should succeed");
    }

    #[tokio::test]
    async fn run_subprocess_returns_failure_on_nonzero_exit() {
        // `cargo` rejects unknown top-level flags with exit 1.
        // Picking cargo (not `false` / `cmd /c`) keeps the test
        // portable across every CI runner.
        let res = run_subprocess(
            "cargo",
            &["--this-flag-does-not-exist-and-will-not"],
            "cargo_bogus",
        )
        .await;
        match res {
            Err(RunError::NonZero(f)) => {
                assert_eq!(f.stage, "cargo_bogus");
                assert!(
                    f.exit_code.is_some(),
                    "cargo --bogus-flag should yield an exit code"
                );
            }
            other => panic!("expected RunError::NonZero, got {other:?}"),
        }
    }

    #[tokio::test]
    async fn run_subprocess_returns_io_error_on_missing_program() {
        // No PATH lookup will resolve this name. spawn returns
        // an `io::Error` (NotFound on Unix, similar on Windows).
        let res = run_subprocess("lfs-definitely-not-a-real-program-xyz123", &[], "missing").await;
        match res {
            Err(RunError::Io(_)) => {}
            other => panic!("expected RunError::Io for missing program, got {other:?}"),
        }
    }

    #[tokio::test]
    async fn make_temp_dir_creates_unique_paths_under_temp() {
        let a = make_temp_dir("lfs-tmp-uniq-").await.unwrap();
        let b = make_temp_dir("lfs-tmp-uniq-").await.unwrap();
        assert_ne!(a, b, "concurrent calls must yield distinct paths");
        assert!(a.exists());
        assert!(b.exists());
        let _ = tokio::fs::remove_dir_all(&a).await;
        let _ = tokio::fs::remove_dir_all(&b).await;
    }
}
