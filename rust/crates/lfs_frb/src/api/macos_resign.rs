//! FRB shim for the macOS self-sign / re-sign pipeline.
//!
//! Delegates to `lfs_os_security::macos::code_signing` on Apple
//! hosts; on every other target the calls return an
//! "unsupported" error so the Dart caller can surface a clean
//! message without `Platform.isMacOS` checks bleeding into the
//! Rust contract. Dart-side guards (`isMacosPlatform`) keep the
//! pipeline calls confined to macOS in practice.

/// FRB-visible mirror of
/// `lfs_os_security::macos::code_signing::ResignOutcome`.
/// Stays a discriminator-only enum — the wire shape is one
/// variant per Dart `ResignOutcome` branch the settings UI
/// already understands.
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

/// Returns `true` when a cert under `common_name` exists in the
/// user's login keychain. Read-only — never mutates the
/// keychain. On non-macOS hosts always returns `false` so the
/// settings UI keeps showing "Enable secure tiers" rather than
/// failing loudly on the wrong OS.
pub async fn macos_resign_has_identity(common_name: String) -> Result<bool, String> {
    #[cfg(target_os = "macos")]
    {
        lfs_os_security::macos::code_signing::has_identity(&common_name)
            .await
            .map_err(|e| e.to_string())
    }
    #[cfg(not(target_os = "macos"))]
    {
        let _ = common_name;
        Ok(false)
    }
}

/// Make sure a self-signed cert under `common_name` exists in
/// the user's login keychain. Returns `true` when a fresh cert
/// was created in this call (the macOS password prompt fired);
/// `false` when an existing one was reused silently.
pub async fn macos_resign_ensure_identity(common_name: String) -> Result<bool, String> {
    #[cfg(target_os = "macos")]
    {
        lfs_os_security::macos::code_signing::ensure_identity(&common_name)
            .await
            .map_err(|e| e.to_string())
    }
    #[cfg(not(target_os = "macos"))]
    {
        let _ = common_name;
        Err("macos code-signing is only available on macOS".into())
    }
}

/// Re-sign the bundle at `bundle_path` leaf-first with the cert
/// under `common_name`. Caller must have run
/// [`macos_resign_ensure_identity`] earlier.
pub async fn macos_resign_bundle(
    bundle_path: String,
    common_name: String,
) -> Result<MacosResignOutcome, String> {
    #[cfg(target_os = "macos")]
    {
        lfs_os_security::macos::code_signing::resign_bundle(
            std::path::Path::new(&bundle_path),
            &common_name,
        )
        .await
        .map(MacosResignOutcome::from)
        .map_err(|e| e.to_string())
    }
    #[cfg(not(target_os = "macos"))]
    {
        let _ = (bundle_path, common_name);
        Err("macos code-signing is only available on macOS".into())
    }
}

/// Read the entitlements plist embedded in the bundle at
/// `bundle_path`'s current signature. Returns `null` when the
/// signature carries no entitlements (CI ad-hoc build) or the
/// bundle is corrupt. The installer uses this to take pre-/
/// post-resign snapshots and detect a re-sign that silently
/// stripped `keychain-access-groups`.
pub async fn macos_resign_extract_entitlements(
    bundle_path: String,
) -> Result<Option<String>, String> {
    #[cfg(target_os = "macos")]
    {
        lfs_os_security::macos::code_signing::extract_entitlements_for_bundle(std::path::Path::new(
            &bundle_path,
        ))
        .await
        .map_err(|e| e.to_string())
    }
    #[cfg(not(target_os = "macos"))]
    {
        let _ = bundle_path;
        Ok(None)
    }
}

/// Run `codesign --verify --deep --strict --verbose=2` against
/// the bundle at `bundle_path`. Used by the installer to gate
/// the atomic-swap step on a structurally-sound staged bundle.
pub async fn macos_resign_verify_bundle(bundle_path: String) -> Result<bool, String> {
    #[cfg(target_os = "macos")]
    {
        lfs_os_security::macos::code_signing::verify_bundle(std::path::Path::new(&bundle_path))
            .await
            .map_err(|e| e.to_string())
    }
    #[cfg(not(target_os = "macos"))]
    {
        let _ = bundle_path;
        Ok(false)
    }
}

/// Drop the identity + cert under `common_name` from the user's
/// login keychain.
pub async fn macos_resign_uninstall_identity(common_name: String) -> Result<(), String> {
    #[cfg(target_os = "macos")]
    {
        lfs_os_security::macos::code_signing::uninstall_identity(&common_name)
            .await
            .map_err(|e| e.to_string())
    }
    #[cfg(not(target_os = "macos"))]
    {
        let _ = common_name;
        Err("macos code-signing is only available on macOS".into())
    }
}

/// Stable subject CN used by the cert; mirrored in Dart so the
/// settings UI labels stay in sync without hard-coding the
/// string in two places.
pub fn macos_resign_default_common_name() -> String {
    #[cfg(target_os = "macos")]
    {
        lfs_os_security::macos::code_signing::DEFAULT_COMMON_NAME.to_string()
    }
    #[cfg(not(target_os = "macos"))]
    {
        // Same constant the macOS path returns. Kept literal
        // here so the FRB shape doesn't depend on the
        // platform-gated dependency tree.
        "LetsFLUTssh Self-Sign".to_string()
    }
}
