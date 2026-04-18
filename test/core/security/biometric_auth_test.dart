import 'dart:io' show Platform;

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/biometric_auth.dart';
import 'package:letsflutssh/core/security/linux/fprintd_client.dart';

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
    test(
      'returns software on Linux (fprintd + libsecret; hardware upgrade lands '
      'when TPM seal is wired)',
      () {
        if (!Platform.isLinux) {
          return; // Skip on non-Linux CI runners.
        }
        final bio = BiometricAuth();
        expect(bio.backingLevel(), BiometricBackingLevel.software);
      },
    );

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

  // The Linux availability() branch only runs on a Linux host — mocking
  // Platform.isLinux is not feasible in pure-VM tests. We guard each
  // test so they become no-ops on non-Linux runners rather than flipping
  // platform state globally.
  group('BiometricAuth.availability — Linux branch', () {
    test('reports systemServiceMissing when fprintd is unreachable', () async {
      if (!Platform.isLinux) return;
      final bio = BiometricAuth(
        fprintdClient: _FakeFprintdClient(reachable: false, hasFingers: false),
      );
      expect(
        await bio.availability(),
        BiometricUnavailableReason.systemServiceMissing,
      );
    });

    test(
      'reports notEnrolled when fprintd is up but no finger is enrolled',
      () async {
        if (!Platform.isLinux) return;
        final bio = BiometricAuth(
          fprintdClient: _FakeFprintdClient(reachable: true, hasFingers: false),
        );
        expect(
          await bio.availability(),
          BiometricUnavailableReason.notEnrolled,
        );
      },
    );

    test(
      'returns null (ready) when fprintd is reachable and a finger is enrolled',
      () async {
        if (!Platform.isLinux) return;
        final bio = BiometricAuth(
          fprintdClient: _FakeFprintdClient(reachable: true, hasFingers: true),
        );
        expect(await bio.availability(), isNull);
      },
    );
  });

  group('BiometricAuth.authenticate — Linux branch', () {
    test('delegates to FprintdClient.verify on Linux', () async {
      if (!Platform.isLinux) return;
      final fake = _FakeFprintdClient(
        reachable: true,
        hasFingers: true,
        verifyResult: true,
      );
      final bio = BiometricAuth(fprintdClient: fake);
      expect(await bio.authenticate('irrelevant'), isTrue);
      expect(fake.verifyCalls, 1);
    });

    test('returns false when fprintd verify fails', () async {
      if (!Platform.isLinux) return;
      final fake = _FakeFprintdClient(
        reachable: true,
        hasFingers: true,
        verifyResult: false,
      );
      final bio = BiometricAuth(fprintdClient: fake);
      expect(await bio.authenticate('irrelevant'), isFalse);
      expect(fake.verifyCalls, 1);
    });
  });
}

class _FakeFprintdClient implements FprintdClient {
  _FakeFprintdClient({
    required this.reachable,
    required this.hasFingers,
    this.verifyResult = false,
  });

  final bool reachable;
  final bool hasFingers;
  final bool verifyResult;
  int verifyCalls = 0;

  @override
  Future<bool> isServiceReachable() async => reachable;

  @override
  Future<bool> hasEnrolledFingers() async => hasFingers;

  @override
  Future<bool> verify() async {
    verifyCalls++;
    return verifyResult;
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
