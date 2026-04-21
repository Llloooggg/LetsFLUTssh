/// Very coarse password-strength classifier, purely informational.
///
/// The master-password dialogs flash a small coloured bar + label under
/// the new-password field so the user sees *something* when they type a
/// 4-character password — but we never block Save. Users who want a
/// short password get a red bar; that is the end of the warning.
///
/// Heuristic is intentionally simple: length + character-class diversity.
/// No `zxcvbn` wordlist — shipping 30k entries of common-password dictionary
/// would bloat the binary for an informational-only feature. If a future
/// review wants a real score, swap the body of [assessPasswordStrength];
/// the enum surface is what the UI locks onto.
enum PasswordStrength {
  /// No characters entered — the meter hides itself.
  empty,

  /// Length < 8 or fewer than 2 character classes. Red bar.
  weak,

  /// 8–11 chars with ≥ 2 classes, or 12+ chars with < 3 classes. Orange bar.
  moderate,

  /// 12–15 chars with ≥ 3 classes. Green bar.
  strong,

  /// 16+ chars with ≥ 3 classes. Green bar, full width.
  veryStrong,
}

/// Classify [password] into a [PasswordStrength] tier. Pure function —
/// unit-testable, no I/O, no allocations beyond the regex matches the
/// caller already pays for.
PasswordStrength assessPasswordStrength(String password) {
  if (password.isEmpty) return PasswordStrength.empty;

  final length = password.length;
  final hasLower = password.contains(RegExp(r'[a-z]'));
  final hasUpper = password.contains(RegExp(r'[A-Z]'));
  final hasDigit = password.contains(RegExp(r'[0-9]'));
  final hasSymbol = password.contains(RegExp(r'[^A-Za-z0-9]'));
  final classes =
      (hasLower ? 1 : 0) +
      (hasUpper ? 1 : 0) +
      (hasDigit ? 1 : 0) +
      (hasSymbol ? 1 : 0);

  if (length < 8 || classes < 2) return PasswordStrength.weak;
  if (length < 12 || classes < 3) return PasswordStrength.moderate;
  if (length < 16) return PasswordStrength.strong;
  return PasswordStrength.veryStrong;
}
