import '../../src/rust/api/password_strength.dart' as rust_pw;

/// Very coarse password-strength classifier, purely informational.
///
/// The master-password dialogs flash a small coloured bar + label under
/// the new-password field so the user sees *something* when they type a
/// 4-character password — but we never block Save. Users who want a
/// short password get a red bar; that is the end of the warning.
///
/// Heuristic is intentionally simple: length + character-class diversity.
/// Lives canonically in `lfs_core::password_strength::assess`. The Dart
/// fallback below mirrors the same heuristic byte-for-byte; production
/// never reaches it (FRB native lib is loaded at app start) but
/// flutter_test does not load it and widget tests rendering the
/// password-strength meter call this synchronously during build —
/// the fallback keeps that test surface working without a per-suite
/// RustLib.init bootstrap.
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
PasswordStrength assessPasswordStrength(String password) {
  try {
    final db = rust_pw.assessPasswordStrength(password: password);
    return _fromRust(db);
  } catch (_) {
    return _dartFallback(password);
  }
}

PasswordStrength _fromRust(rust_pw.DbPasswordStrength s) => switch (s) {
  rust_pw.DbPasswordStrength.empty => PasswordStrength.empty,
  rust_pw.DbPasswordStrength.weak => PasswordStrength.weak,
  rust_pw.DbPasswordStrength.moderate => PasswordStrength.moderate,
  rust_pw.DbPasswordStrength.strong => PasswordStrength.strong,
  rust_pw.DbPasswordStrength.veryStrong => PasswordStrength.veryStrong,
};

/// Tiny ASCII-only fallback for unit-test contexts without
/// the FRB native lib loaded. Matches the production heuristic
/// shape so tests that hit the fallback still observe the same
/// thresholds.
PasswordStrength _dartFallback(String password) {
  if (password.isEmpty) return PasswordStrength.empty;
  var hasLower = false;
  var hasUpper = false;
  var hasDigit = false;
  var hasSymbol = false;
  for (final c in password.codeUnits) {
    if (c >= 0x61 && c <= 0x7A) {
      hasLower = true;
    } else if (c >= 0x41 && c <= 0x5A) {
      hasUpper = true;
    } else if (c >= 0x30 && c <= 0x39) {
      hasDigit = true;
    } else {
      hasSymbol = true;
    }
  }
  final classes =
      (hasLower ? 1 : 0) +
      (hasUpper ? 1 : 0) +
      (hasDigit ? 1 : 0) +
      (hasSymbol ? 1 : 0);
  final length = password.length;
  if (length < 8 || classes < 2) return PasswordStrength.weak;
  if (length < 12 || classes < 3) return PasswordStrength.moderate;
  if (length < 16) return PasswordStrength.strong;
  return PasswordStrength.veryStrong;
}
