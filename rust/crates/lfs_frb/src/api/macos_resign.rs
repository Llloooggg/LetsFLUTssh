//! FRB shim for the macOS self-sign / re-sign pipeline.
//!
//! Delegates to `lfs_os_security::macos::code_signing` on Apple
//! hosts; on every other target the calls return harmless
//! defaults (`hasIdentity` → `false`) or "unsupported" errors so
//! the Dart caller can surface a clean message without
//! `Platform.isMacOS` checks bleeding into the Rust contract.
//! Dart-side guards (`Platform.isMacOS`) keep the pipeline calls
//! confined to macOS in practice.
//!
//! The cert's subject CN is fixed Rust-side
//! ([`code_signing::DEFAULT_COMMON_NAME`]) because rotating it
//! invalidates every keychain item already minted under the
//! prior designated requirement — there is no legitimate caller-
//! tunable use case for a different value.

/// FRB-visible mirror of
/// `lfs_os_security::macos::code_signing::ResignOutcome`. One
/// variant per Dart settings-UI branch.
#[derive(Debug, Clone, Copy)]
pub enum MacosResignOutcome {
    Succeeded,
    CancelledOrFailed,
    BundleNotWritable,
}

#[cfg(target_os = "macos")]
impl From<lfs_os_security::macos::code_signing::ResignOutcome> for MacosResignOutcome {
    fn from(value: lfs_os_security::macos::code_signing::ResignOutcome) -> Self {
        use lfs_os_security::macos::code_signing::ResignOutcome as Core;
        match value {
            Core::Succeeded => MacosResignOutcome::Succeeded,
            Core::CancelledOrFailed => MacosResignOutcome::CancelledOrFailed,
            Core::BundleNotWritable => MacosResignOutcome::BundleNotWritable,
        }
    }
}

/// Returns `true` when the self-sign cert exists in the user's
/// login keychain. Read-only — never mutates the keychain. On
/// non-macOS hosts always returns `false` so the settings UI
/// keeps showing "Enable secure tiers" rather than failing
/// loudly on the wrong OS.
pub async fn macos_resign_has_identity() -> Result<bool, String> {
    #[cfg(target_os = "macos")]
    {
        lfs_os_security::macos::code_signing::has_identity(
            lfs_os_security::macos::code_signing::DEFAULT_COMMON_NAME,
        )
        .await
        .map_err(|e| e.to_string())
    }
    #[cfg(not(target_os = "macos"))]
    {
        Ok(false)
    }
}

/// Make sure the self-sign cert exists in the keychain. Returns
/// `true` when a fresh cert was created in this call (the macOS
/// password prompt fired); `false` when an existing one was
/// reused silently.
pub async fn macos_resign_ensure_identity() -> Result<bool, String> {
    #[cfg(target_os = "macos")]
    {
        lfs_os_security::macos::code_signing::ensure_identity(
            lfs_os_security::macos::code_signing::DEFAULT_COMMON_NAME,
        )
        .await
        .map_err(|e| e.to_string())
    }
    #[cfg(not(target_os = "macos"))]
    {
        Err("macos code-signing is only available on macOS".into())
    }
}

/// Re-sign the bundle at `bundle_path` leaf-first with the
/// self-sign cert. Caller must have run
/// [`macos_resign_ensure_identity`] earlier.
pub async fn macos_resign_bundle(bundle_path: String) -> Result<MacosResignOutcome, String> {
    #[cfg(target_os = "macos")]
    {
        lfs_os_security::macos::code_signing::resign_bundle(
            std::path::Path::new(&bundle_path),
            lfs_os_security::macos::code_signing::DEFAULT_COMMON_NAME,
        )
        .await
        .map(MacosResignOutcome::from)
        .map_err(|e| e.to_string())
    }
    #[cfg(not(target_os = "macos"))]
    {
        let _ = bundle_path;
        Err("macos code-signing is only available on macOS".into())
    }
}

/// Drop the self-sign identity + cert from the user's login
/// keychain.
pub async fn macos_resign_uninstall_identity() -> Result<(), String> {
    #[cfg(target_os = "macos")]
    {
        lfs_os_security::macos::code_signing::uninstall_identity(
            lfs_os_security::macos::code_signing::DEFAULT_COMMON_NAME,
        )
        .await
        .map_err(|e| e.to_string())
    }
    #[cfg(not(target_os = "macos"))]
    {
        Err("macos code-signing is only available on macOS".into())
    }
}
