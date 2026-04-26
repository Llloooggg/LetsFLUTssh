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
mod tests {
    use super::*;

    #[test]
    fn empty_string_is_empty() {
        assert_eq!(assess(""), PasswordStrength::Empty);
    }

    #[test]
    fn short_lowercase_only_is_weak() {
        assert_eq!(assess("abc"), PasswordStrength::Weak);
        assert_eq!(assess("abcdefg"), PasswordStrength::Weak); // 7 chars
    }

    #[test]
    fn long_single_class_still_weak() {
        // 20 lowercase chars but only one class.
        assert_eq!(assess("abcdefghijklmnopqrst"), PasswordStrength::Weak);
    }

    #[test]
    fn eight_chars_two_classes_is_moderate() {
        assert_eq!(assess("Abcdefgh"), PasswordStrength::Moderate);
        assert_eq!(assess("ab123456"), PasswordStrength::Moderate);
    }

    #[test]
    fn twelve_chars_two_classes_stays_moderate() {
        // 12 chars, 2 classes (lowercase + digit) → "12+ chars
        // with < 3 classes" → Moderate per the Dart heuristic.
        assert_eq!(assess("abcd12345678"), PasswordStrength::Moderate);
    }

    #[test]
    fn twelve_chars_three_classes_is_strong() {
        assert_eq!(assess("Abcdefgh1234"), PasswordStrength::Strong);
    }

    #[test]
    fn sixteen_chars_three_classes_is_very_strong() {
        assert_eq!(assess("Abcdefgh12345678"), PasswordStrength::VeryStrong);
    }

    #[test]
    fn symbol_class_counts_separately() {
        // 12 chars, lower + symbol = 2 classes → Moderate
        assert_eq!(assess("a!b@c#d$e%f^"), PasswordStrength::Moderate);
        // 12 chars, lower + digit + symbol = 3 → Strong
        assert_eq!(assess("a1b!c2d@e3f#"), PasswordStrength::Strong);
    }

    #[test]
    fn non_ascii_char_counts_as_symbol() {
        // 8 chars: "паssword" — Cyrillic 'п' + 'а' (symbol class)
        // + lowercase ascii = 2 classes, length 8 → Moderate.
        assert_eq!(assess("паssword"), PasswordStrength::Moderate);
    }

    #[test]
    fn whitespace_is_a_symbol() {
        // "ab cd ef" — 8 chars, lower + space (symbol) → Moderate.
        assert_eq!(assess("ab cd ef"), PasswordStrength::Moderate);
    }

    #[test]
    fn boundary_seven_with_three_classes_is_weak() {
        // Length-first cutoff: <8 chars is Weak regardless of class diversity.
        assert_eq!(assess("Ab1!Ab1"), PasswordStrength::Weak);
    }
}
