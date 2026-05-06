import 'dart:convert' show utf8;

import '../../src/rust/api/password_strength.dart' as rust_pw;

/// Very coarse password-strength classifier, purely informational.
///
/// The master-password dialogs flash a small coloured bar + label under
/// the new-password field so the user sees *something* when they type a
/// 4-character password — but we never block Save. Users who want a
/// short password get a red bar; that is the end of the warning.
///
/// Heuristic is intentionally simple: length + character-class diversity.
/// Lives canonically in `lfs_core::password_strength::assess`; tests that
/// exercise this helper (directly or via the password-strength meter
/// widget) bootstrap FRB through `requireFrbLoaded`.
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

/// Classify [password] into a [PasswordStrength] tier.
PasswordStrength assessPasswordStrength(String password) =>
    _fromRust(rust_pw.assessPasswordStrength(password: utf8.encode(password)));

PasswordStrength _fromRust(rust_pw.DbPasswordStrength s) => switch (s) {
  rust_pw.DbPasswordStrength.empty => PasswordStrength.empty,
  rust_pw.DbPasswordStrength.weak => PasswordStrength.weak,
  rust_pw.DbPasswordStrength.moderate => PasswordStrength.moderate,
  rust_pw.DbPasswordStrength.strong => PasswordStrength.strong,
  rust_pw.DbPasswordStrength.veryStrong => PasswordStrength.veryStrong,
};
