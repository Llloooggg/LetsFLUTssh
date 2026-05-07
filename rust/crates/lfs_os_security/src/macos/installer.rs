//! Silent DMG installer for the macOS auto-update path.
//!
//! Mirrors the prior Dart `MacosInstaller` orchestrator step for
//! step. The flow turns a downloaded `.dmg` into a swapped-in
//! `.app` bundle without user interaction; failures roll back to
//! the pre-install state, so a partial install never leaves the
//! user with a corrupt bundle.
//!
//! ## Pipeline
//!
//! 1. **Writability probe.** Drop a sentinel file in the target's
//!    parent directory; bail with `NotApplicable` if the user cannot
//!    write there (`/Applications/letsflutssh.app` owned by root,
//!    typical for an admin install). The caller then falls back to
//!    the Finder-reveal path.
//!
//! 2. **`hdiutil attach -nobrowse -noautoopen -mountpoint <tmp>`** —
//!    mount the DMG without surfacing a Finder window or auto-
//!    opening the volume. `NotApplicable` if attach fails.
//!
//! 3. **Locate `.app` inside the mount** — single-level scan; the
//!    DMG is expected to ship one bundle at the root.
//!
//! 4. **`rsync -a --delete <src>/ <staged>/`** — copy the bundle
//!    into `<target>.new` so the live bundle is never partially
//!    overwritten. Detach the DMG immediately after rsync to keep
//!    mounts short-lived even on a failure path.
//!
//! 5. **Pre-resign entitlements snapshot** — read the entitlements
//!    plist out of the staged bundle's signature. Used to detect
//!    the silent-strip bug after re-signing.
//!
//! 6. **Re-sign under the user's cert if one is installed** —
//!    `code_signing::has_identity()` short-circuits the no-cert
//!    case so a user who declined the first-launch self-sign offer
//!    still gets silent updates with the CI ad-hoc signature.
//!    Calling `resign_bundle()` unconditionally would fail
//!    `codesign` with "no identity found" and roll back every
//!    update for users who never opted in.
//!
//! 7. **Verify** — `codesign --verify --deep --strict --verbose=2`
//!    on the staged bundle. Failure aborts the install before the
//!    atomic swap; staged copy is removed and the live bundle is
//!    untouched.
//!
//! 8. **Post-resign entitlement probe** — re-extract entitlements
//!    from the now-signed staged bundle. If the pre-resign snapshot
//!    had content but the post-resign one is empty, the re-sign
//!    silently stripped `keychain-access-groups`; the signature is
//!    valid (so verify passes) but T1 keychain access is dead and
//!    every stored item returns `errSecMissingEntitlement` (-34018).
//!    Roll back before the swap so the user keeps the working prior
//!    version.
//!
//! 9. **Atomic swap** — `<target>` → `<target>.backup`, then
//!    `<target>.new` → `<target>`. Sequence matters: rename order
//!    keeps the live path resolvable at every moment except a
//!    sub-millisecond gap between the two calls. If the second
//!    rename fails, restore `<target>` from `<target>.backup` and
//!    return `RolledBack` so the user keeps the prior bundle.
//!    `<target>.backup` survives as a crash-recovery trail; a
//!    follow-up `cleanup_backup` call drops it once the new bundle
//!    has run cleanly.
//!
//! 10. **Mount cleanup** — best-effort remove the temp mountpoint
//!     directory; idempotent on a bundle that detached cleanly.

#![cfg(target_os = "macos")]

use std::path::{Path, PathBuf};

use tokio::fs;
use tokio::process::Command;

use crate::macos::code_signing;
use crate::subprocess_util::{
    append_suffix, find_first_directory_with_extension, make_temp_dir,
    run_subprocess as run_subprocess_util, RunError,
};

/// Outcome enum returned by [`install`]. Mirrors the prior
/// Dart `InstallOutcome` shape; consumers (the silent-update
/// callback in `update_provider.dart`) collapse `Succeeded` →
/// `true` and the others → `false` to drive the relaunch
/// vs. fall-back-to-Finder branch.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum InstallOutcome {
    /// Bundle swapped, re-signed under the existing personal
    /// cert (if any), ready to relaunch.
    Succeeded,
    /// Atomic-swap path bailed mid-flight; target bundle is
    /// still the pre-install version.
    RolledBack,
    /// Writability or privilege barrier prevented the swap. Caller
    /// falls back to the Finder-reveal path.
    NotApplicable,
}

/// Pipeline error. Mirrors the shape of `code_signing::Error`
/// — same subprocess + io split.
#[derive(Debug)]
pub enum InstallError {
    Subprocess {
        stage: String,
        exit_code: Option<i32>,
        stderr: String,
    },
    Io(std::io::Error),
    /// A code-signing step inside the pipeline (extract /
    /// has_identity / resign / verify) returned an error. The
    /// inner `code_signing::Error` carries the details.
    CodeSigning(code_signing::Error),
}

impl std::fmt::Display for InstallError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            InstallError::Subprocess {
                stage,
                exit_code,
                stderr,
            } => write!(
                f,
                "{stage} exited {}: {stderr}",
                exit_code.map_or_else(|| "<signal>".into(), |c| c.to_string())
            ),
            InstallError::Io(e) => write!(f, "io: {e}"),
            InstallError::CodeSigning(e) => write!(f, "code-signing: {e}"),
        }
    }
}

impl std::error::Error for InstallError {}

impl From<std::io::Error> for InstallError {
    fn from(e: std::io::Error) -> Self {
        InstallError::Io(e)
    }
}

impl From<RunError> for InstallError {
    fn from(e: RunError) -> Self {
        match e {
            RunError::NonZero(f) => InstallError::Subprocess {
                stage: f.stage,
                exit_code: f.exit_code,
                stderr: f.stderr,
            },
            RunError::Io(io) => InstallError::Io(io),
        }
    }
}

impl From<code_signing::Error> for InstallError {
    fn from(e: code_signing::Error) -> Self {
        InstallError::CodeSigning(e)
    }
}

const HDIUTIL: &str = "/usr/bin/hdiutil";
const RSYNC: &str = "/usr/bin/rsync";

/// Install `dmg_path` on top of `target_bundle`. `target_bundle`
/// is the live `.app` directory the running process was launched
/// from — caller resolves it via `Platform.resolvedExecutable`
/// walked up to the bundle root.
pub async fn install(
    dmg_path: &Path,
    target_bundle: &Path,
) -> Result<InstallOutcome, InstallError> {
    let target_parent = match target_bundle.parent() {
        Some(p) => p,
        // Bundle path with no parent (e.g. "/letsflutssh.app")
        // means an unwritable root install — drop into the
        // Finder fallback.
        None => return Ok(InstallOutcome::NotApplicable),
    };
    if !is_writable(target_parent).await {
        return Ok(InstallOutcome::NotApplicable);
    }

    let mount_point = make_temp_dir("lfs-dmg-mount-").await?;
    let staged_path: PathBuf = append_suffix(target_bundle, ".new");
    let backup_path: PathBuf = append_suffix(target_bundle, ".backup");

    let result = install_with_mount(
        dmg_path,
        target_bundle,
        &staged_path,
        &backup_path,
        &mount_point,
    )
    .await;

    if mount_point.exists() {
        let _ = fs::remove_dir_all(&mount_point).await;
    }
    result
}

/// Drop the rollback backup directory `<target>.backup` once the
/// new bundle has run cleanly. Called from `main._bootstrap`
/// a few seconds after startup so a crash during early init
/// still finds the backup. Best-effort — failures are swallowed
/// because the next successful install's swap will sweep the
/// stale `.backup` regardless.
pub async fn cleanup_backup(target_bundle: &Path) {
    let backup = append_suffix(target_bundle, ".backup");
    if backup.exists() {
        let _ = fs::remove_dir_all(&backup).await;
    }
}

// ---- internal helpers -------------------------------------------------

async fn install_with_mount(
    dmg_path: &Path,
    target_bundle: &Path,
    staged_path: &Path,
    backup_path: &Path,
    mount_point: &Path,
) -> Result<InstallOutcome, InstallError> {
    // 1. mount the DMG
    let attach_status = Command::new(HDIUTIL)
        .args(["attach", "-nobrowse", "-noautoopen", "-mountpoint"])
        .arg(mount_point)
        .arg(dmg_path)
        .stdin(std::process::Stdio::null())
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .status()
        .await?;
    if !attach_status.success() {
        return Ok(InstallOutcome::NotApplicable);
    }

    // 2. locate the .app inside the mount
    let mounted_app = match find_first_directory_with_extension(mount_point, ".app") {
        Some(p) => p,
        None => {
            detach(mount_point).await;
            return Ok(InstallOutcome::NotApplicable);
        }
    };

    // 3. rsync into staging
    if staged_path.exists() {
        let _ = fs::remove_dir_all(staged_path).await;
    }
    let src = format!("{}/", mounted_app.display());
    let dst = format!("{}/", staged_path.display());
    let rsync_res = run_subprocess_util(RSYNC, &["-a", "--delete", &src, &dst], "rsync").await;
    detach(mount_point).await;
    if rsync_res.is_err() {
        if staged_path.exists() {
            let _ = fs::remove_dir_all(staged_path).await;
        }
        return Ok(InstallOutcome::NotApplicable);
    }

    // 4. snapshot pre-resign entitlements so a silent-strip during
    //    the re-sign pass shows up against this baseline.
    let pre_resign_ent = code_signing::extract_entitlements_for_bundle(staged_path).await?;

    // 5. re-sign if the user has a personal cert installed.
    if code_signing::has_identity(code_signing::DEFAULT_COMMON_NAME).await? {
        // Outcome is collapsed inside resign_bundle into Ok variants
        // (`BundleNotWritable` won't happen here because the writability
        // probe already passed for the parent directory). Any inner
        // codesign subprocess error surfaces as a code_signing::Error
        // and propagates via the From impl.
        let _ = code_signing::resign_bundle(staged_path, code_signing::DEFAULT_COMMON_NAME).await?;
    }

    // 6. verify — if the staged bundle isn't structurally sound,
    //    drop staging and leave the live target untouched.
    if !code_signing::verify_bundle(staged_path).await? {
        let _ = fs::remove_dir_all(staged_path).await;
        return Ok(InstallOutcome::RolledBack);
    }

    // 7. post-resign entitlement probe — see top-of-file
    //    rationale for the -34018 trap.
    if pre_resign_ent.is_some() {
        let post_resign_ent = code_signing::extract_entitlements_for_bundle(staged_path).await?;
        if post_resign_ent.is_none() {
            let _ = fs::remove_dir_all(staged_path).await;
            return Ok(InstallOutcome::RolledBack);
        }
    }

    // 8. atomic swap — old → backup, then new → target. The order
    //    is the one Apple's own update flows use: backup first
    //    means a failed second rename leaves the user with a
    //    `.backup` at the install root and no live `.app`, which
    //    the next launch's recovery sweep can detect.
    if backup_path.exists() {
        let _ = fs::remove_dir_all(backup_path).await;
    }
    if let Err(e) = fs::rename(target_bundle, backup_path).await {
        return Err(InstallError::Io(e));
    }
    if let Err(_e) = fs::rename(staged_path, target_bundle).await {
        // Rollback: restore the original bundle. Leave staging
        // for diagnostics — the second-rename failure is rare and
        // the Dart caller's log already captures the reason.
        let _ = fs::rename(backup_path, target_bundle).await;
        return Ok(InstallOutcome::RolledBack);
    }
    Ok(InstallOutcome::Succeeded)
}

async fn detach(mount_point: &Path) {
    let _ = Command::new(HDIUTIL)
        .args(["detach"])
        .arg(mount_point)
        .arg("-force")
        .stdin(std::process::Stdio::null())
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .status()
        .await;
}

async fn is_writable(dir: &Path) -> bool {
    let probe = dir.join(".lfs-install-probe");
    if fs::write(&probe, b"x").await.is_err() {
        return false;
    }
    let _ = fs::remove_file(&probe).await;
    true
}
