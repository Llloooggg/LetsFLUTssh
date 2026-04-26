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
pub fn assess_password_strength(password: String) -> DbPasswordStrength {
    lfs_core::password_strength::assess(&password).into()
}
