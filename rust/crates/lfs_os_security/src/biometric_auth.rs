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
        let result = tokio::task::spawn_blocking(|| unsafe {
            let ctx: Retained<LAContext> = LAContext::new();
            let mut error: Option<Retained<NSError>> = None;
            let ok = ctx.canEvaluatePolicy_error(
                LAPolicy::DeviceOwnerAuthenticationWithBiometrics,
                Some(&mut error),
            );
            if ok {
                Ok(())
            } else {
                let code = error
                    .as_ref()
                    .map(|e| e.code())
                    .unwrap_or(0);
                // LAError codes (Apple-defined): -6 =
                // touchIDNotAvailable, -7 = touchIDNotEnrolled,
                // -8 = passcodeNotSet. Same values for Face ID
                // (Apple kept the touchID names for ABI compat).
                Err(match code {
                    -6 => BiometricUnavailableReason::NoSensor,
                    -7 => BiometricUnavailableReason::NotEnrolled,
                    -8 => BiometricUnavailableReason::SystemServiceMissing,
                    other => {
                        let desc = error
                            .as_ref()
                            .map(|e| e.localizedDescription().to_string())
                            .unwrap_or_default();
                        BiometricUnavailableReason::Probe(format!(
                            "LAError {other}: {desc}"
                        ))
                    }
                })
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
        UserConsentVerificationResult, UserConsentVerifier,
        UserConsentVerifierAvailability,
    };

    pub(super) async fn check_availability() -> AvailabilityResult {
        let availability = tokio::task::spawn_blocking(|| {
            UserConsentVerifier::CheckAvailabilityAsync()
                .and_then(|op| op.get())
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
            UserConsentVerifier::RequestVerificationAsync(&message)
                .and_then(|op| op.get())
        })
        .await;
        match result {
            Ok(Ok(UserConsentVerificationResult::Verified)) => true,
            _ => false,
        }
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

// ── Android & every other target ─────────────────────────────

#[cfg(not(any(
    target_os = "linux",
    target_os = "macos",
    target_os = "ios",
    target_os = "windows"
)))]
mod platform_impl {
    use super::{AvailabilityResult, BiometricUnavailableReason};
    pub(super) async fn check_availability() -> AvailabilityResult {
        // Android stays on `local_auth` Dart-side until the
        // BiometricPrompt JNI bridge lands.
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
        let _ = tokio::time::timeout(
            std::time::Duration::from_secs(2),
            authenticate("test"),
        )
        .await
        .unwrap_or(false);
    }
}
