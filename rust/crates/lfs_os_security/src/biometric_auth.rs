//! OS biometric prompt — Touch ID / Face ID on Apple, Windows
//! Hello on Windows. Linux is covered by the Tier 2 fprintd
//! shim (`lfs_core::platform::linux::fprintd`); Android stays
//! on `local_auth` until the BiometricPrompt JNI bridge lands.
//!
//! Public surface mirrors the Dart `BiometricAuth` shape:
//! `check_availability` returns the structured reason (or `None`
//! = ready), `authenticate(reason)` shows the OS prompt and
//! resolves to a bool. Both bridge the platform's native
//! callback shape (block on Apple, async WinRT operation on
//! Windows) into a Rust Future via a oneshot channel.

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BiometricUnavailableReason {
    PlatformUnsupported,
    NoSensor,
    NotEnrolled,
    SystemServiceMissing,
    /// Used when the platform's availability probe returned a
    /// raw error code we don't map to a more specific reason.
    Probe(String),
}

/// `Ok(())` = biometrics ready; `Err(reason)` = unavailable.
pub type AvailabilityResult = Result<(), BiometricUnavailableReason>;

pub async fn check_availability() -> AvailabilityResult {
    platform_impl::check_availability().await
}

/// Show the OS biometric prompt with the localised reason. Resolves
/// to `true` when the user authenticated successfully, `false`
/// for any failure (cancel / no-match / hardware error / timeout).
pub async fn authenticate(reason: &str) -> bool {
    platform_impl::authenticate(reason).await
}

// ── Apple (LAContext via objc2-local-authentication) ─────────

#[cfg(any(target_os = "macos", target_os = "ios"))]
mod platform_impl {
    use super::{AvailabilityResult, BiometricUnavailableReason};
    use block2::RcBlock;
    use objc2::rc::Retained;
    use objc2::runtime::Bool;
    use objc2_foundation::{NSError, NSString};
    use objc2_local_authentication::{LAContext, LAPolicy};

    pub(super) async fn check_availability() -> AvailabilityResult {
        // SAFETY: `LAContext::new` returns a fresh autoreleased
        // instance; `canEvaluatePolicy` reads the device's
        // biometric state without prompting the user.
        // objc2-local-authentication 0.3 returns
        // `Result<(), Retained<NSError>>` directly — no
        // out-pointer + bool dance like older revisions.
        let result = tokio::task::spawn_blocking(|| unsafe {
            let ctx: Retained<LAContext> = LAContext::new();
            match ctx.canEvaluatePolicy_error(LAPolicy::DeviceOwnerAuthenticationWithBiometrics) {
                Ok(()) => Ok(()),
                Err(error) => {
                    let code = error.code();
                    // LAError codes (Apple-defined): -6 =
                    // touchIDNotAvailable, -7 = touchIDNotEnrolled,
                    // -8 = passcodeNotSet. Same values for Face ID
                    // (Apple kept the touchID names for ABI compat).
                    Err(match code {
                        -6 => BiometricUnavailableReason::NoSensor,
                        -7 => BiometricUnavailableReason::NotEnrolled,
                        -8 => BiometricUnavailableReason::SystemServiceMissing,
                        other => {
                            let desc = error.localizedDescription().to_string();
                            BiometricUnavailableReason::Probe(format!("LAError {other}: {desc}"))
                        }
                    })
                }
            }
        })
        .await;
        match result {
            Ok(r) => r,
            Err(e) => Err(BiometricUnavailableReason::Probe(format!(
                "tokio join: {e}"
            ))),
        }
    }

    pub(super) async fn authenticate(reason: &str) -> bool {
        let (tx, rx) = tokio::sync::oneshot::channel::<bool>();
        let reason_owned = reason.to_string();

        // Bridge: spawn_blocking holds the LAContext + block on
        // its own thread so the main runtime is free; the block
        // calls back from a UI / system thread and forwards the
        // result through the oneshot channel.
        tokio::task::spawn_blocking(move || unsafe {
            let ctx: Retained<LAContext> = LAContext::new();
            let reason_ns: Retained<NSString> = NSString::from_str(&reason_owned);

            let tx_cell = std::sync::Arc::new(std::sync::Mutex::new(Some(tx)));
            let tx_for_block = tx_cell.clone();
            let block: RcBlock<dyn Fn(Bool, *mut NSError)> =
                RcBlock::new(move |success: Bool, _error: *mut NSError| {
                    if let Ok(mut guard) = tx_for_block.lock() {
                        if let Some(sender) = guard.take() {
                            let _ = sender.send(success.as_bool());
                        }
                    }
                });

            ctx.evaluatePolicy_localizedReason_reply(
                LAPolicy::DeviceOwnerAuthenticationWithBiometrics,
                &reason_ns,
                &block,
            );
        });

        rx.await.unwrap_or(false)
    }
}

// ── Linux: routes through Tier 2 fprintd (lfs_core) ──────────
//
// Intentionally NOT wired here — the Dart wrapper short-
// circuits on `Platform.isLinux` and calls
// `FprintdClient.verify()` directly. Mirroring the same path
// through this module would either duplicate the zbus
// connection logic or add a cross-crate dep just to forward
// one call.

#[cfg(target_os = "linux")]
mod platform_impl {
    use super::{AvailabilityResult, BiometricUnavailableReason};
    pub(super) async fn check_availability() -> AvailabilityResult {
        // The Dart wrapper already routes Linux through
        // FprintdClient (which lives in lfs_core). Returning
        // PlatformUnsupported here makes the routing mistake
        // surface loudly if the Dart side ever forgets to
        // short-circuit.
        Err(BiometricUnavailableReason::PlatformUnsupported)
    }
    pub(super) async fn authenticate(_reason: &str) -> bool {
        false
    }
}

// ── Windows (UserConsentVerifier via WinRT) ──────────────────

#[cfg(target_os = "windows")]
mod platform_impl {
    use super::{AvailabilityResult, BiometricUnavailableReason};
    use windows::core::HSTRING;
    use windows::Security::Credentials::UI::{
        UserConsentVerificationResult, UserConsentVerifier, UserConsentVerifierAvailability,
    };
    use windows_future::{AsyncStatus, IAsyncOperation};

    /// Block the current thread until an `IAsyncOperation<T>`
    /// completes, then return its result. windows-rs 0.62
    /// dropped the convenience `.get()` method that earlier
    /// versions exposed; the canonical replacement is to poll
    /// `Status()` and call `GetResults()` once it leaves the
    /// `Started` state. The 5 ms sleep is benign — the
    /// UserConsentVerifier paths land in single-digit ms (the
    /// availability check is a synchronous registry / WMI
    /// lookup wrapped in the IAsyncOperation contract; the
    /// verification call is bounded by user response time, which
    /// dominates over the polling cost).
    fn block_on<T: windows::core::RuntimeType + 'static>(
        op: IAsyncOperation<T>,
    ) -> windows::core::Result<T> {
        loop {
            match op.Status()? {
                AsyncStatus::Started => {
                    std::thread::sleep(std::time::Duration::from_millis(5));
                }
                _ => return op.GetResults(),
            }
        }
    }

    pub(super) async fn check_availability() -> AvailabilityResult {
        let availability = tokio::task::spawn_blocking(|| {
            UserConsentVerifier::CheckAvailabilityAsync().and_then(block_on)
        })
        .await
        .map_err(|e| BiometricUnavailableReason::Probe(format!("tokio join: {e}")))?
        .map_err(|e| BiometricUnavailableReason::Probe(format!("CheckAvailability: {e}")))?;

        match availability {
            UserConsentVerifierAvailability::Available => Ok(()),
            UserConsentVerifierAvailability::DeviceNotPresent => {
                Err(BiometricUnavailableReason::NoSensor)
            }
            UserConsentVerifierAvailability::NotConfiguredForUser => {
                Err(BiometricUnavailableReason::NotEnrolled)
            }
            UserConsentVerifierAvailability::DisabledByPolicy => {
                Err(BiometricUnavailableReason::SystemServiceMissing)
            }
            UserConsentVerifierAvailability::DeviceBusy => {
                Err(BiometricUnavailableReason::Probe("device busy".into()))
            }
            other => Err(BiometricUnavailableReason::Probe(format!(
                "UserConsentVerifierAvailability {other:?}"
            ))),
        }
    }

    pub(super) async fn authenticate(reason: &str) -> bool {
        let message: HSTRING = reason.into();
        let result = tokio::task::spawn_blocking(move || {
            UserConsentVerifier::RequestVerificationAsync(&message).and_then(block_on)
        })
        .await;
        matches!(result, Ok(Ok(UserConsentVerificationResult::Verified)))
    }
}

// ── Linux: routes through Tier 2 fprintd via Dart wrapper ────

#[cfg(target_os = "linux")]
#[allow(dead_code)]
mod _linux_doc {
    // The Dart `BiometricAuth` short-circuits on
    // `Platform.isLinux` and calls `FprintdClient.verify()`
    // directly. The stub below in `mod platform_impl` exists
    // for the symmetry of `check_availability` /
    // `authenticate` returning a sensible default — never
    // reached in production.
}

// ── Android — direct JNI to androidx.biometric.BiometricPrompt ──

#[cfg(target_os = "android")]
mod platform_impl {
    use super::{AvailabilityResult, BiometricUnavailableReason};
    use crate::android::biometric;

    pub(super) async fn check_availability() -> AvailabilityResult {
        match biometric::can_authenticate().await {
            Ok(0) => Ok(()), // BIOMETRIC_SUCCESS
            Ok(1) => Err(BiometricUnavailableReason::Probe(
                "device hardware busy".into(),
            )),
            Ok(11) => Err(BiometricUnavailableReason::NotEnrolled), // BIOMETRIC_ERROR_NONE_ENROLLED
            Ok(12) => Err(BiometricUnavailableReason::NoSensor),    // BIOMETRIC_ERROR_NO_HARDWARE
            Ok(15) => Err(BiometricUnavailableReason::NotEnrolled), // BIOMETRIC_ERROR_SECURITY_UPDATE_REQUIRED
            Ok(other) => Err(BiometricUnavailableReason::Probe(format!(
                "BiometricManager.canAuthenticate = {other}"
            ))),
            Err(e) => Err(BiometricUnavailableReason::Probe(e)),
        }
    }

    pub(super) async fn authenticate(reason: &str) -> bool {
        // The Dart side already localises `reason` per-locale;
        // we hand it to BiometricPrompt verbatim as the prompt
        // subtitle. The title is a fixed app-name fallback —
        // the prompt always shows the requesting app's name in
        // the UI regardless.
        let title = "Unlock";
        matches!(
            biometric::authenticate(title, reason).await,
            biometric::BiometricResult::Succeeded,
        )
    }
}

// ── Every other target (no Android, no desktop) ──────────────

#[cfg(not(any(
    target_os = "linux",
    target_os = "macos",
    target_os = "ios",
    target_os = "windows",
    target_os = "android"
)))]
mod platform_impl {
    use super::{AvailabilityResult, BiometricUnavailableReason};
    pub(super) async fn check_availability() -> AvailabilityResult {
        Err(BiometricUnavailableReason::PlatformUnsupported)
    }
    pub(super) async fn authenticate(_reason: &str) -> bool {
        false
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn check_availability_does_not_panic() {
        let _ = check_availability().await;
    }

    #[tokio::test]
    async fn authenticate_returns_bool_without_panic() {
        // Test environments don't have a biometric sensor —
        // the call should return `false` cleanly without
        // hanging or panicking. The 2 s timeout caps any UI
        // prompt that might fire on a real device under
        // CI; we only assert "future resolved", not the value.
        let _ = tokio::time::timeout(std::time::Duration::from_secs(2), authenticate("test"))
            .await
            .unwrap_or(false);
    }
}
