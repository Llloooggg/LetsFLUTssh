import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/password_strength.dart';

void main() {
  group('assessPasswordStrength', () {
    test('empty input maps to empty tier — meter hides', () {
      expect(assessPasswordStrength(''), PasswordStrength.empty);
    });

    test('short or one-class passwords classify as weak', () {
      expect(assessPasswordStrength('abc'), PasswordStrength.weak);
      expect(assessPasswordStrength('12345678'), PasswordStrength.weak);
      expect(assessPasswordStrength('aaaaaaaa'), PasswordStrength.weak);
      // Length on its own is not enough if only one class.
      expect(
        assessPasswordStrength('aaaaaaaaaaaaaaaaaaaa'),
        PasswordStrength.weak,
      );
    });

    test('8-11 chars with ≥ 2 classes → moderate', () {
      expect(assessPasswordStrength('password1'), PasswordStrength.moderate);
      expect(assessPasswordStrength('Pass1word'), PasswordStrength.moderate);
    });

    test('12-15 chars with ≥ 3 classes → strong', () {
      expect(assessPasswordStrength('CorrectHorse1'), PasswordStrength.strong);
      expect(assessPasswordStrength('MySecret_2025'), PasswordStrength.strong);
    });

    test('16+ chars with ≥ 3 classes → very strong', () {
      expect(
        assessPasswordStrength('Correct Horse Battery!'),
        PasswordStrength.veryStrong,
      );
      expect(
        assessPasswordStrength('Tr0ub4dor&3_longer'),
        PasswordStrength.veryStrong,
      );
    });

    test('is informational only — never throws on adversarial input', () {
      expect(
        () => assessPasswordStrength('\u0000\u0001\u0002'),
        returnsNormally,
      );
      expect(() => assessPasswordStrength('🔒🔑🗝️'), returnsNormally);
      expect(() => assessPasswordStrength('a' * 10000), returnsNormally);
    });
  });
}
