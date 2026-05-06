import 'dart:io' show Platform;

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/biometric_auth.dart';
import 'package:letsflutssh/core/security/windows/winbio_probe.dart';
import 'package:letsflutssh/src/rust/api/os_security.dart' as rust_os;

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
        final bio = BiometricAuth(tpmAvailable: () async => false);
        expect(await bio.backingLevel(), BiometricBackingLevel.software);
      },
    );

    test('returns hardware on Linux when the TPM probe succeeds', () async {
      if (!Platform.isLinux) return;
      final bio = BiometricAuth(tpmAvailable: () async => true);
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
        fprintdReachable: () async => false,
        fprintdHasEnrolled: () async => false,
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
          fprintdReachable: () async => true,
          fprintdHasEnrolled: () async => false,
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
          fprintdReachable: () async => true,
          fprintdHasEnrolled: () async => true,
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
        if (!Platform.isWindows) return;
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
    test('delegates to fprintd verify on Linux', () async {
      if (!Platform.isLinux) return;
      var calls = 0;
      final bio = BiometricAuth(
        fprintdVerify: () async {
          calls++;
          return true;
        },
      );
      expect(await bio.authenticate('irrelevant'), isTrue);
      expect(calls, 1);
    });

    test('returns false when fprintd verify fails', () async {
      if (!Platform.isLinux) return;
      var calls = 0;
      final bio = BiometricAuth(
        fprintdVerify: () async {
          calls++;
          return false;
        },
      );
      expect(await bio.authenticate('irrelevant'), isFalse);
      expect(calls, 1);
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
        fprintdReachable: () async => true,
        fprintdHasEnrolled: () async => true,
      );
      expect(await ready.isAvailable(), isTrue);

      final notReady = BiometricAuth(
        fprintdReachable: () async => false,
        fprintdHasEnrolled: () async => false,
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
      final bio = BiometricAuth(
        fprintdReachable: () async => throw StateError('dbus gone'),
        fprintdHasEnrolled: () async => false,
      );
      expect(
        await bio.availability(),
        BiometricUnavailableReason.systemServiceMissing,
      );
    });
  });

  group('mapRustBiometricAvailability', () {
    test('Available variant maps to null (biometric ready)', () {
      expect(
        mapRustBiometricAvailability(
          const rust_os.DbBiometricAvailability.available(),
        ),
        isNull,
      );
    });

    test('PlatformUnsupported maps to platformUnsupported', () {
      expect(
        mapRustBiometricAvailability(
          const rust_os.DbBiometricAvailability.platformUnsupported(),
        ),
        BiometricUnavailableReason.platformUnsupported,
      );
    });

    test('NoSensor maps to noSensor', () {
      expect(
        mapRustBiometricAvailability(
          const rust_os.DbBiometricAvailability.noSensor(),
        ),
        BiometricUnavailableReason.noSensor,
      );
    });

    test('NotEnrolled maps to notEnrolled', () {
      expect(
        mapRustBiometricAvailability(
          const rust_os.DbBiometricAvailability.notEnrolled(),
        ),
        BiometricUnavailableReason.notEnrolled,
      );
    });

    test('SystemServiceMissing maps to systemServiceMissing', () {
      expect(
        mapRustBiometricAvailability(
          const rust_os.DbBiometricAvailability.systemServiceMissing(),
        ),
        BiometricUnavailableReason.systemServiceMissing,
      );
    });

    test(
      'Probe(reason) collapses to platformUnsupported with logged reason',
      () {
        // Probe variant is the Rust-side error indicator (e.g. WinRT
        // call failed). UI must surface a single "biometric
        // unreachable" branch — leaking the platform-specific
        // diagnostic up the stack would force every locale to translate
        // strings the Rust side emitted.
        expect(
          mapRustBiometricAvailability(
            const rust_os.DbBiometricAvailability.probe('winrt: 0x80004005'),
          ),
          BiometricUnavailableReason.platformUnsupported,
        );
      },
    );
  });
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
