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

/// Character-class regexes compiled once at load time. Previously the
/// body of [assessPasswordStrength] allocated four fresh [RegExp] objects
/// on every keystroke while the master-password meter re-ran live; on a
/// long typed password that churn showed up in the paint budget next to
/// the meter widget itself.
final _hasLowerRegex = RegExp(r'[a-z]');
final _hasUpperRegex = RegExp(r'[A-Z]');
final _hasDigitRegex = RegExp(r'[0-9]');
final _hasSymbolRegex = RegExp(r'[^A-Za-z0-9]');

/// Classify [password] into a [PasswordStrength] tier. Pure function —
/// unit-testable, no I/O, no allocations beyond the regex matches the
/// caller already pays for.
PasswordStrength assessPasswordStrength(String password) {
  if (password.isEmpty) return PasswordStrength.empty;

  final length = password.length;
  final hasLower = password.contains(_hasLowerRegex);
  final hasUpper = password.contains(_hasUpperRegex);
  final hasDigit = password.contains(_hasDigitRegex);
  final hasSymbol = password.contains(_hasSymbolRegex);
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
