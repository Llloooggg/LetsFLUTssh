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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn empty_bytes_classify_as_empty() {
        assert!(matches!(
            assess_password_strength(vec![]),
            DbPasswordStrength::Empty
        ));
    }

    #[test]
    fn short_simple_password_classifies_as_weak() {
        assert!(matches!(
            assess_password_strength(b"abc".to_vec()),
            DbPasswordStrength::Weak
        ));
    }

    #[test]
    fn long_diverse_password_classifies_above_weak() {
        // The exact bucket (Strong vs VeryStrong) is the meter's
        // job; this assertion guards "long + diverse never demotes
        // to Empty / Weak" — the load-bearing UI contract that the
        // meter never tells the user a strong password is weak.
        let strong = b"Tr0ub4dor&3-Pneumonoultramicroscopic-Silicovolcanoconiosis";
        let s = assess_password_strength(strong.to_vec());
        assert!(matches!(
            s,
            DbPasswordStrength::Moderate
                | DbPasswordStrength::Strong
                | DbPasswordStrength::VeryStrong
        ));
    }

    #[test]
    fn invalid_utf8_lossy_decodes_into_a_real_estimate() {
        // The pre-fix path mapped invalid UTF-8 to Empty via
        // `unwrap_or_default()`; this test pins the
        // from_utf8_lossy contract by feeding a long byte run with
        // a stray non-UTF-8 byte and asserting the meter does NOT
        // collapse to Empty.
        let mut bytes = vec![0xFFu8];
        bytes.extend_from_slice(b"verylongpasswordwithinvalidleadingbyte!!");
        let s = assess_password_strength(bytes);
        assert!(!matches!(s, DbPasswordStrength::Empty));
    }
}
