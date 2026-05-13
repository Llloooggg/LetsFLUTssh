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
        .map_err(|e| crate::api::frb_err::wire_str(crate::api::frb_err::kind::PLATFORM, e))
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
        .map_err(|e| crate::api::frb_err::wire_str(crate::api::frb_err::kind::PLATFORM, e))
    }
    #[cfg(not(target_os = "macos"))]
    {
        Err("macos code-signing is only available on macOS".into())
    }
}

/// Re-sign the running app bundle leaf-first with the self-sign
/// cert. Caller passes its own `Platform.resolvedExecutable`;
/// the Rust side walks three parents up to the `.app` root and
/// signs from there. Caller must have run
/// [`macos_resign_ensure_identity`] earlier.
pub async fn macos_resign_bundle(executable_path: String) -> Result<MacosResignOutcome, String> {
    #[cfg(target_os = "macos")]
    {
        let bundle_root = lfs_os_security::bundle_root_from_macos_executable(std::path::Path::new(
            &executable_path,
        ));
        lfs_os_security::macos::code_signing::resign_bundle(
            &bundle_root,
            lfs_os_security::macos::code_signing::DEFAULT_COMMON_NAME,
        )
        .await
        .map(MacosResignOutcome::from)
        .map_err(|e| crate::api::frb_err::wire_str(crate::api::frb_err::kind::PLATFORM, e))
    }
    #[cfg(not(target_os = "macos"))]
    {
        let _ = executable_path;
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
        .map_err(|e| crate::api::frb_err::wire_str(crate::api::frb_err::kind::PLATFORM, e))
    }
    #[cfg(not(target_os = "macos"))]
    {
        Err("macos code-signing is only available on macOS".into())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // The macOS code-signing pipeline shells out to `security` /
    // `codesign` against the user's login keychain; covered by
    // hand-driven runs on macOS host hardware. The standalone tests
    // below pin the cross-platform stub contract — every shim
    // surfaces a consistent fallback so the Dart settings UI never
    // panics on a misrouted call.

    #[cfg(not(target_os = "macos"))]
    #[tokio::test]
    async fn non_macos_has_identity_returns_false() {
        // Settings UI keeps showing "Enable secure tiers" rather
        // than failing loudly. Pin the contract.
        let res = macos_resign_has_identity().await;
        assert!(matches!(res, Ok(false)));
    }

    #[cfg(not(target_os = "macos"))]
    #[tokio::test]
    async fn non_macos_ensure_identity_returns_err() {
        let res = macos_resign_ensure_identity().await;
        assert!(res.is_err());
    }

    #[cfg(not(target_os = "macos"))]
    #[tokio::test]
    async fn non_macos_resign_bundle_returns_err() {
        let res = macos_resign_bundle("/tmp/exec".into()).await;
        assert!(res.is_err());
    }

    #[cfg(not(target_os = "macos"))]
    #[tokio::test]
    async fn non_macos_uninstall_identity_returns_err() {
        let res = macos_resign_uninstall_identity().await;
        assert!(res.is_err());
    }

    #[test]
    fn macos_resign_outcome_clone_round_trip() {
        let v = MacosResignOutcome::BundleNotWritable;
        let c = v;
        assert!(matches!(c, MacosResignOutcome::BundleNotWritable));
    }
}
