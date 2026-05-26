//! FRB adapter for `lfs_core::platform::linux::fprintd`.
//!
//! Linux-only: the underlying module is gated on
//! `cfg(target_os = "linux")`. Every shim here matches that gate
//! so a Windows / macOS build doesn't drag the zbus tree in.
//! Non-Linux callers should never reach these functions; the Dart
//! wrapper short-circuits with `Platform.isLinux` before
//! invoking, but for safety the no-Linux compile path still
//! provides the same signatures returning the
//! "biometric-unavailable" defaults.

#[cfg(target_os = "linux")]
pub async fn fprintd_is_service_reachable() -> bool {
    lfs_core::platform::linux::fprintd::is_service_reachable().await
}

#[cfg(not(target_os = "linux"))]
pub async fn fprintd_is_service_reachable() -> bool {
    false
}

#[cfg(target_os = "linux")]
pub async fn fprintd_get_enrolment_hash() -> Option<Vec<u8>> {
    lfs_core::platform::linux::fprintd::get_enrolment_hash()
        .await
        .map(|arr| arr.to_vec())
}

#[cfg(not(target_os = "linux"))]
pub async fn fprintd_get_enrolment_hash() -> Option<Vec<u8>> {
    None
}

#[cfg(target_os = "linux")]
pub async fn fprintd_has_enrolled_fingers() -> bool {
    lfs_core::platform::linux::fprintd::has_enrolled_fingers().await
}

#[cfg(not(target_os = "linux"))]
pub async fn fprintd_has_enrolled_fingers() -> bool {
    false
}

/// Run the verify cycle, capping the wait at `timeout_ms`. The
/// Dart caller uses 30 000 ms by default; production never passes
/// a value the user can tweak.
#[cfg(target_os = "linux")]
pub async fn fprintd_verify(timeout_ms: u32) -> bool {
    let timeout = std::time::Duration::from_millis(timeout_ms as u64);
    lfs_core::platform::linux::fprintd::verify(timeout).await
}

#[cfg(not(target_os = "linux"))]
pub async fn fprintd_verify(_timeout_ms: u32) -> bool {
    false
}

#[cfg(test)]
mod tests {
    use super::*;

    // The non-Linux fallback shims return the
    // "biometric-unavailable" defaults; verify the contract on the
    // current build target. On Linux the production path runs the
    // real fprintd dbus probe — same shape the Dart wrapper relies
    // on. The four shims are reached unconditionally here to ensure
    // the cross-platform stub signatures stay callable.

    #[tokio::test]
    async fn is_service_reachable_returns_a_bool_without_panic() {
        let _ = fprintd_is_service_reachable().await;
    }

    #[tokio::test]
    async fn get_enrolment_hash_returns_option_without_panic() {
        let _ = fprintd_get_enrolment_hash().await;
    }

    #[tokio::test]
    async fn has_enrolled_fingers_returns_bool_without_panic() {
        let _ = fprintd_has_enrolled_fingers().await;
    }

    #[tokio::test]
    async fn verify_with_short_timeout_returns_without_panic() {
        // 1 ms — the fprintd verify cycle takes much longer; the
        // important contract is "returns rather than panics", not
        // the bool value.
        let _ = fprintd_verify(1).await;
    }

    #[cfg(not(target_os = "linux"))]
    #[tokio::test]
    async fn non_linux_fallbacks_return_unavailable_defaults() {
        // Pin the cross-platform stub contract — these are the
        // values the Dart wrapper's `Platform.isLinux` short-circuit
        // collapses to.
        assert!(!fprintd_is_service_reachable().await);
        assert!(fprintd_get_enrolment_hash().await.is_none());
        assert!(!fprintd_has_enrolled_fingers().await);
        assert!(!fprintd_verify(0).await);
    }
}
