//! FRB shim for `lfs_os_security::installer_launch` — the
//! `xdg-open` / `open` / `cmd /c start` hand-off the Dart side
//! uses to launch a freshly-downloaded installer artefact.
//!
//! The subprocess plumbing and the Windows `cmd.exe`
//! metacharacter allowlist live in the audited
//! `lfs_os_security` crate. This shim mirrors the outcome
//! taxonomy as a local enum so FRB codegen emits a proper
//! Dart sealed-class hierarchy (cross-crate `pub use` enums
//! surface as opaque handles instead). Same mirror pattern as
//! `macos_installer.rs`.

/// FRB-visible mirror of
/// `lfs_os_security::installer_launch::InstallerLaunchOutcome`.
/// The Dart caller (`UpdateService.openFile`) maps each
/// variant onto a UI surface — `Launched` returns `true`,
/// every other variant returns `false` and lets the Settings
/// page fall back to opening the GitHub release page in a
/// browser.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum InstallerLaunchOutcome {
    /// Subprocess spawned and exited zero. The OS handler has
    /// accepted the path; whether the user completes the
    /// install from here is outside the app's loop.
    Launched,
    /// Windows arm only — the path carried at least one
    /// `cmd.exe` metacharacter and was refused before any
    /// spawn. See `lfs_os_security::installer_launch` for the
    /// attack model the allowlist defends against.
    RefusedUnsafePath,
    /// The `platform` argument did not match `"linux"` /
    /// `"macos"` / `"windows"`. Used by Dart to short-circuit
    /// on iOS / Android / `"unknown"` hosts where there is no
    /// installer-launch primitive to call.
    UnsupportedPlatform,
    /// Spawn happened but the helper either failed to launch
    /// the program (executable missing, permission denied) or
    /// the program exited non-zero. `exit_code` is the
    /// process exit code when the program ran; `-1` when the
    /// failure was a spawn error rather than a non-zero exit.
    /// `stderr` carries whatever the helper / program wrote
    /// to stderr.
    LaunchFailed { exit_code: i32, stderr: String },
}

impl From<lfs_os_security::installer_launch::InstallerLaunchOutcome> for InstallerLaunchOutcome {
    fn from(value: lfs_os_security::installer_launch::InstallerLaunchOutcome) -> Self {
        use lfs_os_security::installer_launch::InstallerLaunchOutcome as Core;
        match value {
            Core::Launched => InstallerLaunchOutcome::Launched,
            Core::RefusedUnsafePath => InstallerLaunchOutcome::RefusedUnsafePath,
            Core::UnsupportedPlatform => InstallerLaunchOutcome::UnsupportedPlatform,
            Core::LaunchFailed { exit_code, stderr } => InstallerLaunchOutcome::LaunchFailed {
                exit_code: exit_code.unwrap_or(-1),
                stderr,
            },
        }
    }
}

/// Open `path` under the host's default handler for `platform`
/// (`linux` / `macos` / `windows`). Any other platform string
/// surfaces as [`InstallerLaunchOutcome::UnsupportedPlatform`]
/// without ever reaching a spawn. The Dart caller
/// (`UpdateService.openFile`) maps each variant onto a UI
/// surface — `Launched` returns `true`, every other variant
/// returns `false` and lets the Settings page fall back to
/// opening the GitHub release page in a browser.
///
/// See `lfs_os_security::installer_launch::open_installer_file`
/// for the per-platform binding and the Windows allowlist
/// rationale.
pub async fn open_installer_file(path: String, platform: String) -> InstallerLaunchOutcome {
    lfs_os_security::installer_launch::open_installer_file(path, platform)
        .await
        .into()
}

/// FRB-visible mirror of
/// `lfs_os_security::installer_launch::AppImageApplyOutcome`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum AppImageApplyOutcome {
    /// New image in place and the new process spawned. Dart exits the
    /// old process so only the new instance remains.
    Relaunched,
    /// Empty `$APPIMAGE` path or the downloaded image was missing.
    InvalidInput { reason: String },
    /// Copy / chmod / rename failed; the live image is untouched.
    ReplaceFailed { stage: String, error: String },
    /// New image is in place but spawning it failed; the next manual
    /// launch picks up the new version.
    RelaunchFailed { error: String },
}

impl From<lfs_os_security::installer_launch::AppImageApplyOutcome> for AppImageApplyOutcome {
    fn from(value: lfs_os_security::installer_launch::AppImageApplyOutcome) -> Self {
        use lfs_os_security::installer_launch::AppImageApplyOutcome as Core;
        match value {
            Core::Relaunched => AppImageApplyOutcome::Relaunched,
            Core::InvalidInput { reason } => AppImageApplyOutcome::InvalidInput { reason },
            Core::ReplaceFailed { stage, error } => {
                AppImageApplyOutcome::ReplaceFailed { stage, error }
            }
            Core::RelaunchFailed { error } => AppImageApplyOutcome::RelaunchFailed { error },
        }
    }
}

/// Replace the running AppImage (`appimage_path` = `$APPIMAGE`) with the
/// verified download at `new_path`, then spawn the new image. On
/// [`AppImageApplyOutcome::Relaunched`] the Dart caller exits the old
/// process. Linux AppImage channel only — Dart gates on the detected
/// install method before calling. See
/// `lfs_os_security::installer_launch::replace_appimage_and_relaunch`.
pub async fn replace_appimage_and_relaunch(
    new_path: String,
    appimage_path: String,
) -> AppImageApplyOutcome {
    lfs_os_security::installer_launch::replace_appimage_and_relaunch(new_path, appimage_path)
        .await
        .into()
}

#[cfg(test)]
mod tests {
    //! Regression coverage for the FRB shim's two
    //! short-circuit branches — both return BEFORE the
    //! `run_subprocess` call inside `lfs_os_security`, so no
    //! `xdg-open` / `open` / `cmd` process is ever spawned by
    //! these tests. The end-to-end spawn path is exercised in
    //! the Dart `update_service_test.dart` group through an
    //! injected `InstallerOpener`.

    use super::*;

    #[tokio::test]
    async fn unsupported_platform_routes_through_shim_without_spawn() {
        let res = open_installer_file("/tmp/anything".into(), "ios".into()).await;
        assert_eq!(res, InstallerLaunchOutcome::UnsupportedPlatform);
    }

    #[tokio::test]
    async fn windows_metacharacter_path_refused_through_shim() {
        // Re-asserts that the allowlist gate in
        // `lfs_os_security` fires through the FRB conversion. A
        // future regression that bypassed the gate (e.g.
        // dispatching directly to `cmd` from this shim) would
        // surface as `LaunchFailed` / `Launched` instead.
        let res = open_installer_file(r"C:\tmp\bad|name.exe".into(), "windows".into()).await;
        assert_eq!(res, InstallerLaunchOutcome::RefusedUnsafePath);
    }
}
