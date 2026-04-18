import 'dart:io' show Platform;

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/biometric_auth.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BiometricAuth.backingLevel', () {
    // The method is keyed off [Platform], which we cannot override in a
    // pure Dart VM test. The suite runs on the host (Linux in CI / WSL),
    // so we assert the Linux-branch outcome here and lean on the iOS /
    // macOS / Android / Windows branches being exercised manually on
    // those platforms before a release. The goal of this test is to
    // pin the **shape** of the contract — not to pretend we're mocking
    // the host platform.
    test('returns null on Linux (wiring lands in follow-on commits)', () {
      if (!Platform.isLinux) {
        return; // Skip on non-Linux CI runners.
      }
      final bio = BiometricAuth();
      expect(bio.backingLevel(), isNull);
    });

    test('enum carries both hardware and software variants', () {
      // Freezes the two-value vocabulary — adding a third backing level
      // without updating the Settings subtitle formatter / locales is a
      // bug, and this test is where that shows up first.
      expect(BiometricBackingLevel.values, hasLength(2));
      expect(
        BiometricBackingLevel.values,
        containsAll(<BiometricBackingLevel>[
          BiometricBackingLevel.hardware,
          BiometricBackingLevel.software,
        ]),
      );
    });
  });

  group('BiometricUnavailableReason', () {
    test(
      'carries systemServiceMissing for Linux rung-3 (fprintd not installed)',
      () {
        // Locale wiring in settings_sections_security._biometricDisabledReason
        // relies on this enum value; keeping the test here ensures the
        // ARB keys (biometricSystemServiceMissing) and the enum stay
        // in lockstep.
        expect(
          BiometricUnavailableReason.values,
          contains(BiometricUnavailableReason.systemServiceMissing),
        );
      },
    );
  });
}
