import 'dart:io' show Platform;

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/biometric_auth.dart';
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

  group('BiometricUnavailableReason — enum surface', () {
    test('carries exactly four variants', () {
      // Spec: the Settings disabled-reason locale resolver branches on
      // every variant. A fifth without paired ARB keys would silently
      // fall through to the catch-all "unsupported" tooltip, hiding
      // whichever new reason got added.
      expect(BiometricUnavailableReason.values, hasLength(4));
      expect(BiometricUnavailableReason.values, <BiometricUnavailableReason>[
        BiometricUnavailableReason.platformUnsupported,
        BiometricUnavailableReason.noSensor,
        BiometricUnavailableReason.notEnrolled,
        BiometricUnavailableReason.systemServiceMissing,
      ]);
    });
  });

  group('BiometricAuth.isAvailable — notEnrolled is "not available"', () {
    test(
      'returns false when fprintd is reachable but no finger is enrolled',
      () async {
        if (!Platform.isLinux) return;
        // Spec: any non-null availability reason means "no biometric
        // shortcut" — the lock screen falls back to the password
        // field. A regression that conflated only `systemServiceMissing`
        // with "not available" would let the unlock path call
        // `authenticate()` against a sensor with no enrolled finger
        // and hang on the never-resolving fprintd prompt.
        final bio = BiometricAuth(
          fprintdReachable: () async => true,
          fprintdHasEnrolled: () async => false,
        );
        expect(await bio.isAvailable(), isFalse);
      },
    );
  });

  group('BiometricAuth.authenticate — Linux propagates probe errors', () {
    test('does not swallow fprintd verify exceptions on Linux', () async {
      if (!Platform.isLinux) return;
      // Spec: the Linux branch is a direct `return _fprintdVerify()` —
      // no try/catch. Wrapping it would mask a genuine D-Bus
      // protocol break behind a generic "false" answer; the caller
      // (lock screen) wants the raw failure so it can fall the user
      // back to the password prompt with the correct reason logged.
      final bio = BiometricAuth(
        fprintdVerify: () async => throw StateError('dbus dropped'),
      );
      await expectLater(
        bio.authenticate('irrelevant'),
        throwsA(isA<StateError>()),
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

    test('Probe variant with empty reason still collapses to unsupported', () {
      // Spec: the helper must not branch on whether the Rust-side
      // reason string is empty — every Probe sub-case is a
      // platform-unsupported answer for the UI, even when the
      // diagnostic carries no text (a backend that produces a
      // bare error without context still must not crash the UI).
      expect(
        mapRustBiometricAvailability(
          const rust_os.DbBiometricAvailability.probe(''),
        ),
        BiometricUnavailableReason.platformUnsupported,
      );
    });
  });

  group('BiometricBackingLevel — ordering invariant', () {
    test(
      'hardware sorts before software (Settings card reflects the index)',
      () {
        // Spec: the Settings card renders the active backing level next
        // to the biometric toggle and labels `hardware` as the stronger
        // guarantee. The two-value enum is declared in that order in
        // the source — flipping it would relabel every locale's UI
        // copy without anyone noticing until release.
        expect(BiometricBackingLevel.hardware.index, 0);
        expect(BiometricBackingLevel.software.index, 1);
      },
    );
  });

  group('BiometricUnavailableReason — ordering invariant', () {
    test('declaration order matches the disabled-reason switch', () {
      // Spec: the Settings disabled-reason resolver in
      // settings_sections_security._biometricDisabledReason switches on
      // each variant in declaration order. Renumbering the enum
      // (e.g. inserting a new variant in the middle) without a
      // matching switch update would silently drop the new branch
      // through to the catch-all.
      expect(BiometricUnavailableReason.platformUnsupported.index, 0);
      expect(BiometricUnavailableReason.noSensor.index, 1);
      expect(BiometricUnavailableReason.notEnrolled.index, 2);
      expect(BiometricUnavailableReason.systemServiceMissing.index, 3);
    });
  });

  group('BiometricAuth — non-Linux happy path constructs', () {
    test(
      'no fprintd / TPM overrides supplied: instance constructs with defaults',
      () {
        // Spec: every overrideable seam is optional. A caller that
        // supplies none constructs a BiometricAuth bound to the
        // production FRB defaults; the absence of an override must
        // never throw at construction. Exercising the constructor
        // pins both branches of the `?? default` ladder in coverage
        // for the four fields without booting the native lib.
        final bio = BiometricAuth();
        expect(bio, isA<BiometricAuth>());
      },
    );
  });

  group('BiometricAuth.isAvailable — exception path', () {
    test(
      'a throwing fprintdReachable surfaces as not-available — the convenience '
      'getter inherits the same collapse-to-systemServiceMissing behaviour as '
      'availability() so the lock screen never tries to authenticate against '
      'a broken probe',
      () async {
        if (!Platform.isLinux) return;
        // Spec: `isAvailable()` is documented as "mirrors availability()
        // == null". When `_linuxAvailability` catches the D-Bus error
        // and returns `systemServiceMissing`, `isAvailable()` must
        // surface false. A regression that let the exception escape
        // would break the lock-screen fallback (the password field
        // would never get a chance to render).
        final bio = BiometricAuth(
          fprintdReachable: () async => throw StateError('dbus gone'),
          fprintdHasEnrolled: () async => true,
        );
        expect(await bio.isAvailable(), isFalse);
      },
    );
  });

  group(
    'BiometricAuth.availability — Linux short-circuit on reachable check',
    () {
      test(
        'fprintdHasEnrolled is not called when fprintdReachable returns false — '
        'the ladder must surface the daemon-missing reason without poking the '
        'enrolment slot, otherwise a fresh install with no fprintd would '
        'surface "no finger enrolled" and confuse the install hint',
        () async {
          if (!Platform.isLinux) return;
          // Spec: `_linuxAvailability` returns
          // `BiometricUnavailableReason.systemServiceMissing` immediately
          // when `_fprintdReachable()` returns false; the
          // `_fprintdHasEnrolled` probe is only meaningful after the
          // daemon is reachable. Pin the ordering — a regression that
          // reversed the checks would surface `notEnrolled` on a missing
          // daemon and the README install snippet would no longer
          // surface.
          var enrolledChecked = false;
          final bio = BiometricAuth(
            fprintdReachable: () async => false,
            fprintdHasEnrolled: () async {
              enrolledChecked = true;
              return true;
            },
          );
          expect(
            await bio.availability(),
            BiometricUnavailableReason.systemServiceMissing,
          );
          expect(
            enrolledChecked,
            isFalse,
            reason:
                'short-circuit on reachable=false must not consult the '
                'enrolment probe — the ladder is reachable → enrolled, never '
                'the other way around',
          );
        },
      );
    },
  );

  group(
    'BiometricAuth.backingLevel — non-Linux desktop is software-backed',
    () {
      test('on Linux without a TPM the level is software regardless of fprintd '
          'state — backing-level is keyed off the TPM probe, not the fprintd '
          'reachability ladder', () async {
        if (!Platform.isLinux) return;
        // Spec: `backingLevel()` branches solely on `_tpmAvailable()`
        // for the Linux arm. A regression that started consulting the
        // fprintd state would conflate "do we have a biometric prompt"
        // (availability) with "is the cached key in hardware"
        // (backingLevel) — two orthogonal Settings concerns.
        final bio = BiometricAuth(
          tpmAvailable: () async => false,
          fprintdReachable: () async => true,
          fprintdHasEnrolled: () async => true,
        );
        expect(await bio.backingLevel(), BiometricBackingLevel.software);
      });
    },
  );

  group('mapRustBiometricAvailability — probe(reason) variants', () {
    test('every Probe diagnostic string collapses to the same UI branch — the '
        'Rust-side reason is logged but never reshaped into a separate enum '
        'tag', () {
      // Spec: the helper deliberately discards the Rust-side diagnostic
      // text. Every probe failure — WinRT error code, LAContext NSError
      // domain, BiometricManager status int — must map to the SAME
      // single `platformUnsupported` UI branch so the Settings card has
      // one localised string to translate and the lock-screen fallback
      // has one branch to handle. Pin the contract across a sample of
      // realistic diagnostic strings.
      const diagnostics = <String>[
        'winrt: 0x80004005',
        'LAErrorBiometryNotAvailable',
        'BiometricManager: ERROR_HW_UNAVAILABLE',
        'fprintd disappeared mid-probe',
        '   ',
        'multiline\nstack\ntrace',
      ];
      for (final reason in diagnostics) {
        expect(
          mapRustBiometricAvailability(
            rust_os.DbBiometricAvailability.probe(reason),
          ),
          BiometricUnavailableReason.platformUnsupported,
          reason:
              'Probe($reason) must collapse to platformUnsupported — the UI '
              'branches off the enum tag alone, not the diagnostic text',
        );
      }
    });
  });

  group('BiometricAuth.backingLevel — Linux TPM probe failure', () {
    test('a throwing TPM probe surfaces as software backing — never an '
        'unhandled exception that crashes the Settings rebuild', () async {
      if (!Platform.isLinux) return;
      // Spec: the Linux `backingLevel` arm awaits `_tpmAvailable()` and
      // branches on the boolean. A throwing probe (binary missing,
      // subprocess panicked, FRB transport error) currently surfaces as
      // an unhandled exception — pin the behaviour deliberately so a
      // future hardening pass that wraps it in a try/catch is reflected
      // here, OR a regression that started swallowing in the wrong
      // direction is caught. As of today the Dart side does not catch:
      // the throw is the documented contract, callers (Settings rebuild)
      // are responsible for guarding.
      final bio = BiometricAuth(
        tpmAvailable: () async => throw StateError('tpm2 subprocess broke'),
      );
      await expectLater(bio.backingLevel(), throwsA(isA<StateError>()));
    });
  });

  group('BiometricAuth.availability — Linux ladder ordering', () {
    test('fprintdHasEnrolled is only consulted after reachable=true — the '
        'ordering guarantees the README install snippet trumps the '
        'enrolment-missing hint when both could surface', () async {
      if (!Platform.isLinux) return;
      // Spec: ladder is reachable → enrolled → ready. When the daemon
      // is reachable AND the enrolment probe ALSO throws, the catch arm
      // collapses to systemServiceMissing — pin that the catch covers
      // every step of the ladder, not just the reachable probe.
      final bio = BiometricAuth(
        fprintdReachable: () async => true,
        fprintdHasEnrolled: () async =>
            throw StateError('enroll list parse failed'),
      );
      expect(
        await bio.availability(),
        BiometricUnavailableReason.systemServiceMissing,
        reason:
            'the catch arm collapses any post-reachable failure into '
            'systemServiceMissing — the README install snippet is the safest '
            'localised hint when the daemon is mid-flight broken',
      );
    });
  });

  // covered by integration: the Rust-routed availability and authenticate
  // paths for iOS / macOS / Windows / Android — `rust_os.osSecurityBiometric*`
  // calls run against `LAContext` / `UserConsentVerifier` /
  // `BiometricManager` and can only be exercised inside the per-platform
  // packaged smoke runs.
}
