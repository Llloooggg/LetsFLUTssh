//! FRB adapter for `lfs_core::password_strength`. Surfaces the
//! coarse master-password strength meter as a synchronous
//! one-shot — the meter re-runs per keystroke so the FRB call
//! must avoid worker scheduling latency.

#[derive(Debug, Clone, Copy)]
pub enum DbPasswordStrength {
    Empty,
    Weak,
    Moderate,
    Strong,
    VeryStrong,
}

impl From<lfs_core::password_strength::PasswordStrength> for DbPasswordStrength {
    fn from(s: lfs_core::password_strength::PasswordStrength) -> Self {
        use lfs_core::password_strength::PasswordStrength as P;
        match s {
            P::Empty => DbPasswordStrength::Empty,
            P::Weak => DbPasswordStrength::Weak,
            P::Moderate => DbPasswordStrength::Moderate,
            P::Strong => DbPasswordStrength::Strong,
            P::VeryStrong => DbPasswordStrength::VeryStrong,
        }
    }
}

#[flutter_rust_bridge::frb(sync)]
pub fn assess_password_strength(password: Vec<u8>) -> DbPasswordStrength {
    // Wire-shape parity with the rest of the password-marshalling
    // family. Invalid UTF-8 (Dart-side encoding bug, never user
    // typing) routes through `from_utf8_lossy` so the strength
    // estimator still sees the input bytes as a best-effort
    // Unicode string — the previous `unwrap_or_default()` collapsed
    // any non-UTF-8 input to `Empty`, masking a real password
    // estimation behind a mid-meter "weak" hint when the user's
    // bytes happened to start with a stray byte from a paste.
    let password = String::from_utf8_lossy(&password);
    lfs_core::password_strength::assess(&password).into()
}
