//! Coarse password-strength classifier for the master-password
//! UI meter. Mirrors the Dart `assessPasswordStrength` heuristic
//! byte-for-byte: length + character-class diversity, no
//! dictionary lookup. The meter is informational — saving a
//! weak password is never blocked.

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PasswordStrength {
    /// No characters entered — the meter hides itself.
    Empty,
    /// Length < 8 or fewer than 2 character classes. Red bar.
    Weak,
    /// 8–11 chars with ≥ 2 classes, or 12+ chars with < 3 classes. Orange bar.
    Moderate,
    /// 12–15 chars with ≥ 3 classes. Green bar.
    Strong,
    /// 16+ chars with ≥ 3 classes. Green bar, full width.
    VeryStrong,
}

/// Classify [password] into a [`PasswordStrength`] tier.
/// Pure function — no allocations, scans the input once.
///
/// "Length" counts UTF-8 scalar values rather than bytes so a
/// password of "пароль" (12 bytes, 6 chars) reads as length 6.
/// The Dart impl uses Dart's String.length which counts UTF-16
/// code units; for the ASCII-bounded threshold ranges we work
/// in (8 / 12 / 16), the Unicode surrogate-pair edge does not
/// reach the strong tiers — so this delta is safe.
///
/// # Heuristic vs entropy
///
/// The classifier counts character classes (lower / upper / digit /
/// symbol — four classes total) rather than computing Shannon
/// entropy. The choice is deliberate:
///
/// - **Informational only.** The meter colours the UI bar; it
///   never blocks a save. The blocking gates (minimum length on
///   the master-password wizard, KDF cost on credential decrypt)
///   live in `lfs_core::security::master_password` — see
///   `docs/ARCHITECTURE.md §3.6`.
/// - **Terminal-friendly inputs.** SSH passwords are typed at a
///   prompt, often through a phone or a remote pane; long
///   passphrases dominate in practice and a four-class diversity
///   check distinguishes "abc" from "Abc1!" without penalising
///   the diceware "correct-horse-battery-staple" shape.
/// - **Entropy is misleading on short inputs.** Shannon entropy
///   over a single string is a poor estimator at < 16 characters
///   (sample size of 1 against a 95-char alphabet); a class-count
///   meter is no worse and is what users intuit from the bar.
pub fn assess(password: &str) -> PasswordStrength {
    if password.is_empty() {
        return PasswordStrength::Empty;
    }
    let mut length = 0usize;
    let mut has_lower = false;
    let mut has_upper = false;
    let mut has_digit = false;
    let mut has_symbol = false;
    for c in password.chars() {
        length += 1;
        if c.is_ascii_lowercase() {
            has_lower = true;
        } else if c.is_ascii_uppercase() {
            has_upper = true;
        } else if c.is_ascii_digit() {
            has_digit = true;
        } else if !c.is_ascii_alphanumeric() {
            // Anything outside [A-Za-z0-9] (incl. punctuation,
            // whitespace, non-ASCII) counts as a symbol —
            // matches the Dart `[^A-Za-z0-9]` regex.
            has_symbol = true;
        }
    }
    let classes =
        u32::from(has_lower) + u32::from(has_upper) + u32::from(has_digit) + u32::from(has_symbol);

    if length < 8 || classes < 2 {
        return PasswordStrength::Weak;
    }
    if length < 12 || classes < 3 {
        return PasswordStrength::Moderate;
    }
    if length < 16 {
        return PasswordStrength::Strong;
    }
    PasswordStrength::VeryStrong
}
#[cfg(test)]
#[path = "../tests/unit/password_strength.rs"]
mod tests;
