/// Unit tests extracted from password_strength.rs
/// Declared via `#[path] mod tests;` in the source file.
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
