//! FRB adapter for `lfs_core::security::biometric_probe_prompt`.
//!
//! Sync — every op is a small mutex acquire + oneshot send.
//! Dart subscriber executes
//! `local_auth.canCheckBiometrics` + enrolment check after
//! seeing `BusEvent::BiometricProbePromptRequest`, dispatches
//! the typed response via this shim.

use lfs_core::security::biometric_probe_prompt::{self, BiometricProbeResponse};

/// Resolve a pending biometric probe with the Dart-plugin
/// answer. `available` reflects `canCheckBiometrics() &&
/// hasEnrolment()`; `classifier_code` carries the per-platform
/// classifier (`ios_passcode_not_set` /
/// `android_no_enrolment` / `linux_no_fprintd` / etc) so the
/// UI shows an actionable hint. Empty when `available == true`.
///
/// Returns `true` when a receiver was actually woken; `false`
/// for an unknown / already-resolved prompt id.
#[flutter_rust_bridge::frb(sync)]
pub fn biometric_probe_prompt_resolve(
    prompt_id: String,
    available: bool,
    classifier_code: String,
) -> bool {
    biometric_probe_prompt::instance().resolve(
        &prompt_id,
        BiometricProbeResponse {
            available,
            classifier_code,
        },
    )
}

/// Cancel a pending probe without resolving — capabilities
/// cache abandoned the await (shutdown, fresh probe started).
/// Idempotent on a missing id.
#[flutter_rust_bridge::frb(sync)]
pub fn biometric_probe_prompt_cancel(prompt_id: String) {
    biometric_probe_prompt::instance().cancel(&prompt_id);
}
