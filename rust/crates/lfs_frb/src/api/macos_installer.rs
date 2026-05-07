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

/// Install `dmg_path` on top of `target_bundle_path`. The Rust
/// side mounts the DMG with `hdiutil`, rsyncs into
/// `<target>.new`, re-signs under the user's personal cert (if
/// installed), verifies, and atomically swaps. On any failure
/// before the swap, the live bundle is untouched and the
/// outcome surfaces to the Dart caller for fallback.
pub async fn macos_installer_install(
    dmg_path: String,
    target_bundle_path: String,
) -> Result<MacosInstallOutcome, String> {
    #[cfg(target_os = "macos")]
    {
        lfs_os_security::macos::installer::install(
            std::path::Path::new(&dmg_path),
            std::path::Path::new(&target_bundle_path),
        )
        .await
        .map(MacosInstallOutcome::from)
        .map_err(|e| e.to_string())
    }
    #[cfg(not(target_os = "macos"))]
    {
        let _ = (dmg_path, target_bundle_path);
        Ok(MacosInstallOutcome::NotApplicable)
    }
}

/// Drop the `<target>.backup` directory once the new bundle has
/// run cleanly. Called from `main._bootstrap` a few seconds
/// after startup so a crash during early init still finds the
/// backup. Best-effort.
pub async fn macos_installer_cleanup_backup(target_bundle_path: String) -> Result<(), String> {
    #[cfg(target_os = "macos")]
    {
        lfs_os_security::macos::installer::cleanup_backup(std::path::Path::new(
            &target_bundle_path,
        ))
        .await;
        Ok(())
    }
    #[cfg(not(target_os = "macos"))]
    {
        let _ = target_bundle_path;
        Ok(())
    }
}
