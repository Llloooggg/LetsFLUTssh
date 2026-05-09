//! FRB shim for the macOS silent DMG-install pipeline.
//!
//! Delegates to `lfs_os_security::macos::installer` on Apple
//! hosts; on every other target the calls return `NotApplicable`
//! / "unsupported" so the Dart caller can surface a clean state
//! without `Platform.isMacOS` checks bleeding into the Rust
//! contract. Dart-side guards (`Platform.isMacOS`) keep the
//! pipeline calls confined to macOS in practice.

/// FRB-visible mirror of
/// `lfs_os_security::macos::installer::InstallOutcome`. Discriminator
/// only — the wire shape is one variant per `Platform.isMacOS`
/// branch the silent-update callback in `update_provider.dart`
/// understands.
#[derive(Debug, Clone, Copy)]
pub enum MacosInstallOutcome {
    Succeeded,
    RolledBack,
    NotApplicable,
}

#[cfg(target_os = "macos")]
impl From<lfs_os_security::macos::installer::InstallOutcome> for MacosInstallOutcome {
    fn from(value: lfs_os_security::macos::installer::InstallOutcome) -> Self {
        use lfs_os_security::macos::installer::InstallOutcome as Core;
        match value {
            Core::Succeeded => MacosInstallOutcome::Succeeded,
            Core::RolledBack => MacosInstallOutcome::RolledBack,
            Core::NotApplicable => MacosInstallOutcome::NotApplicable,
        }
    }
}

/// Install `dmg_path` on top of the running app bundle. Caller
/// passes its own `Platform.resolvedExecutable`; the Rust side
/// walks three parents up to the `.app` root and treats that as
/// the swap target. The pipeline mounts the DMG with `hdiutil`,
/// rsyncs into `<target>.new`, re-signs under the user's
/// personal cert (if installed), verifies, and atomically
/// swaps. On any failure before the swap, the live bundle is
/// untouched and the outcome surfaces to the Dart caller for
/// fallback.
pub async fn macos_installer_install(
    dmg_path: String,
    executable_path: String,
) -> Result<MacosInstallOutcome, String> {
    #[cfg(target_os = "macos")]
    {
        let bundle_root = lfs_os_security::bundle_root_from_macos_executable(std::path::Path::new(
            &executable_path,
        ));
        lfs_os_security::macos::installer::install(std::path::Path::new(&dmg_path), &bundle_root)
            .await
            .map(MacosInstallOutcome::from)
            .map_err(|e| crate::api::frb_err::from_core(&e))
    }
    #[cfg(not(target_os = "macos"))]
    {
        let _ = (dmg_path, executable_path);
        Ok(MacosInstallOutcome::NotApplicable)
    }
}

/// Drop the `<target>.backup` directory once the new bundle has
/// run cleanly. Called from `main._bootstrap` a few seconds
/// after startup so a crash during early init still finds the
/// backup. Best-effort. `executable_path` is
/// `Platform.resolvedExecutable`; Rust walks up to the bundle
/// root and removes its sibling `.backup` directory.
pub async fn macos_installer_cleanup_backup(executable_path: String) -> Result<(), String> {
    #[cfg(target_os = "macos")]
    {
        let bundle_root = lfs_os_security::bundle_root_from_macos_executable(std::path::Path::new(
            &executable_path,
        ));
        lfs_os_security::macos::installer::cleanup_backup(&bundle_root).await;
        Ok(())
    }
    #[cfg(not(target_os = "macos"))]
    {
        let _ = executable_path;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // The macOS install / cleanup pipeline shells out to `hdiutil` /
    // `rsync` / `codesign` against the running app bundle; covered
    // by hand-driven runs on macOS host hardware. The standalone
    // tests below pin the cross-platform stub contract — Dart
    // callers route through here on every platform but `Platform.isMacOS`
    // is the production guard.

    #[cfg(not(target_os = "macos"))]
    #[tokio::test]
    async fn non_macos_install_returns_not_applicable_sentinel() {
        let res = macos_installer_install("/tmp/x.dmg".into(), "/tmp/exec".into()).await;
        assert!(matches!(res, Ok(MacosInstallOutcome::NotApplicable)));
    }

    #[cfg(not(target_os = "macos"))]
    #[tokio::test]
    async fn non_macos_cleanup_backup_is_no_op_ok() {
        let res = macos_installer_cleanup_backup("/tmp/exec".into()).await;
        assert!(res.is_ok());
    }

    #[test]
    fn macos_install_outcome_clone_round_trip() {
        let v = MacosInstallOutcome::Succeeded;
        let c = v;
        assert!(matches!(c, MacosInstallOutcome::Succeeded));
    }
}
