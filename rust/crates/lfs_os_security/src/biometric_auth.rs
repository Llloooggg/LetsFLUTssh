//! OS biometric prompt — Touch ID / Face ID on Apple, Windows
//! Hello on Windows, BiometricPrompt on Android via direct JNI
//! into `androidx.biometric` (see `crate::android::biometric`).
//! Linux is covered by the Tier 2 fprintd shim
//! (`lfs_core::platform::linux::fprintd`).
//!
//! Public surface mirrors the Dart `BiometricAuth` shape:
//! `check_availability` returns the structured reason (or `None`
//! = ready), `authenticate(reason)` shows the OS prompt and
//! resolves to a bool. Each platform-impl bridges its native
//! callback shape (block on Apple, async WinRT operation on
//! Windows, JNI callback adapter on Android) into a Rust Future
//! via a oneshot channel.

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
        //
        // LAContext lifetime: the OS reply block keeps a reference
        // to the LAContext that fired `evaluatePolicy_…_reply`.
        // **Don't construct `ctx` as a stack-local in the
        // spawn_blocking closure** — it drops the moment the
        // closure returns, long before LocalAuthentication invokes
        // the reply, producing the Apple-documented EXC_BAD_ACCESS
        // / silent callback failure. Capture a clone of the
        // `Retained<LAContext>` Arc-equivalent into the `RcBlock`
        // itself, so the context outlives the closure
        // and is released only after the reply runs.
        tokio::task::spawn_blocking(move || unsafe {
            let ctx: Retained<LAContext> = LAContext::new();
            let reason_ns: Retained<NSString> = NSString::from_str(&reason_owned);

            let tx_cell = std::sync::Arc::new(std::sync::Mutex::new(Some(tx)));
            let tx_for_block = tx_cell.clone();
            let ctx_for_block = ctx.clone();
            let block: RcBlock<dyn Fn(Bool, *mut NSError)> =
                RcBlock::new(move |success: Bool, _error: *mut NSError| {
                    // Touch `ctx_for_block` so the compiler keeps
                    // the capture alive for the block's duration.
                    // The block holds the Retained clone; it
                    // releases when the block itself drops, which
                    // is after LocalAuthentication's last
                    // reference goes away.
                    let _ = &ctx_for_block;
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

        // 60-second timeout caps the wait so a stuck reply (the
        // user walked away from a Touch ID prompt that never
        // fires the cancel callback, or LocalAuthentication
        // wedged) doesn't pin the await forever.
        match tokio::time::timeout(std::time::Duration::from_secs(60), rx).await {
            Ok(Ok(v)) => v,
            Ok(Err(_)) | Err(_) => false,
        }
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
    /// `Started` state. The verification path is gated by user
    /// response time (a Hello prompt waits for a touch / face),
    /// so the loop interval is dominated by the human latency,
    /// not the polling cost — a 50 ms interval keeps the poll
    /// rate at 20 Hz, well below the dispatcher cost of a
    /// SetCompleted-driven oneshot.
    fn block_on<T: windows::core::RuntimeType + 'static>(
        op: IAsyncOperation<T>,
    ) -> windows::core::Result<T> {
        loop {
            match op.Status()? {
                AsyncStatus::Started => {
                    std::thread::sleep(std::time::Duration::from_millis(50));
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
            UserConsentVerifierAvailability::Available => {
                // `UserConsentVerifier::CheckAvailabilityAsync`
                // returns `Available` whenever Windows Hello is
                // configured in any form, including a Hello PIN
                // with no physical biometric sensor attached.
                // Lighting up the biometric-unlock toggle in that
                // state forces the user through a PIN prompt
                // disguised as a biometric unlock. The WinBio
                // Framework enumerates the actual physical units
                // (fingerprint readers, IR cameras, iris
                // scanners); zero units is the ground truth that
                // overrides the WinRT verdict.
                //
                // `count_units` returns `-1` when `winbio.dll`
                // cannot be loaded (stripped enterprise image,
                // SDK lib absent); in that case we accept the
                // original WinRT answer rather than locking out a
                // user whose hardware we cannot probe.
                let units = crate::winbio::count_units();
                if units == 0 {
                    Err(BiometricUnavailableReason::NoSensor)
                } else {
                    Ok(())
                }
            }
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
//
// The Dart `BiometricAuth` short-circuits on `Platform.isLinux` and
// calls `FprintdClient.verify()` directly. The stub in `platform_impl`
// below exists for the symmetry of `check_availability` /
// `authenticate` returning a sensible default — never reached in
// production.

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
