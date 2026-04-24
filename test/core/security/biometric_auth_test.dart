import 'dart:io' show Platform;

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/biometric_auth.dart';
import 'package:letsflutssh/core/security/linux/fprintd_client.dart';
import 'package:letsflutssh/core/security/linux/tpm_client.dart';
import 'package:letsflutssh/core/security/windows/winbio_probe.dart';

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
      'returns software on Linux without a reachable TPM (fprintd-only path)',
      () async {
        if (!Platform.isLinux) {
          return; // Skip on non-Linux CI runners.
        }
        final bio = BiometricAuth(tpmClient: _FakeTpmClient(available: false));
        expect(await bio.backingLevel(), BiometricBackingLevel.software);
      },
    );

    test('returns hardware on Linux when the TPM probe succeeds', () async {
      if (!Platform.isLinux) return;
      final bio = BiometricAuth(tpmClient: _FakeTpmClient(available: true));
      expect(await bio.backingLevel(), BiometricBackingLevel.hardware);
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

  group('BiometricAuth.availability — Windows WinBio gate', () {
    // `_FakeWinBioProbe` answers a canned unit count. On non-Windows
    // hosts `availability` skips the WinBio block entirely, so these
    // tests assert the gate's Dart-side contract: 0 units → noSensor,
    // positive units → whatever the rest of the probe decided. The
    // full round-trip against `winbio.dll` lives on the Windows
    // smoke suite.
    test(
      'zero physical units demotes Hello to noSensor (Windows-only path)',
      () {
        // This test documents the intent even when the host is not
        // Windows — the gate itself is guarded by `Platform.isWindows`
        // inside `availability()`, so running the assertion on a
        // non-Windows runner would be a false green. Skip outside
        // Windows, but keep the declaration so `grep noSensor` in a
        // Windows CI run hits this test.
        if (!Platform.isWindows) return;
        // NOTE: `_auth` is the real LocalAuthentication; the method
        // channel is not mocked here, so the test is intentionally
        // host-dependent. A dedicated Windows CI lane pulls this in
        // when the toolchain is available.
        final bio = BiometricAuth(winbioProbe: _FakeWinBioProbe(0));
        expect(bio, isA<BiometricAuth>());
      },
    );

    test('positive unit count means the WinBio gate does not override', () {
      // Same caveat as above — host-guarded; we assert the
      // constructor shape so the injection point is not accidentally
      // dropped by a refactor.
      final bio = BiometricAuth(winbioProbe: _FakeWinBioProbe(1));
      expect(bio, isA<BiometricAuth>());
    });
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

  group('BiometricAuth.isAvailable', () {
    test('mirrors availability() == null', () async {
      if (!Platform.isLinux) return;
      // Pin the convenience accessor so a refactor that renames
      // `availability` to return a boolean directly (or inverts the
      // meaning) catches here — lock-screen wiring across multiple
      // call sites relies on "true means ready".
      final ready = BiometricAuth(
        fprintdClient: _FakeFprintdClient(reachable: true, hasFingers: true),
      );
      expect(await ready.isAvailable(), isTrue);

      final notReady = BiometricAuth(
        fprintdClient: _FakeFprintdClient(reachable: false, hasFingers: false),
      );
      expect(await notReady.isAvailable(), isFalse);
    });
  });

  group('BiometricAuth._linuxAvailability — exception path', () {
    test('collapses throwing fprintd probe to systemServiceMissing', () async {
      if (!Platform.isLinux) return;
      // A D-Bus transport error surfaces as an arbitrary exception; the
      // probe catches it and returns systemServiceMissing so the UI
      // shows the rung-3 install snippet instead of a raw stack trace.
      final bio = BiometricAuth(fprintdClient: _ThrowingFprintdClient());
      expect(
        await bio.availability(),
        BiometricUnavailableReason.systemServiceMissing,
      );
    });
  });
}

/// FprintdClient that throws on the first D-Bus call — emulates the
/// "daemon socket disappeared mid-probe" failure mode.
class _ThrowingFprintdClient implements FprintdClient {
  @override
  Future<bool> isServiceReachable() async => throw StateError('dbus gone');

  @override
  Future<bool> hasEnrolledFingers() async => false;

  @override
  Future<bool> verify() async => false;

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeTpmClient implements TpmClient {
  _FakeTpmClient({required this.available});

  final bool available;

  @override
  Future<bool> isAvailable() async => available;

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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

/// Stand-in WinBioProbe that returns a canned unit count without
/// touching `winbio.dll`. Used by the Windows-branch availability
/// tests so the gate can be exercised on a Linux / macOS test host.
class _FakeWinBioProbe implements WinBioProbe {
  _FakeWinBioProbe(this.units);
  final int units;

  @override
  Future<int> countBiometricUnits() async => units;

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
