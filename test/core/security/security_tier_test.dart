import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/security_tier.dart';

import '../../helpers/frb_bootstrap.dart';

void main() {
  // SecurityConfig.toJson / fromJson route through
  // `lfs_core::security::SecurityConfig` — bootstrap FRB so the
  // canonical wire-format encode + permissive decode are exercised.
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(requireFrbLoaded);

  group('SecurityTier enum', () {
    test('carries the four bank-style tier values', () {
      // Bank-style v3: one tier per key-storage strategy. The
      // pre-v3 dedicated `keychainWithPassword` value is gone —
      // L1 + password is `keychain` + `modifiers.password = true`.
      // Adding or removing a tier without updating the wizard,
      // settings, and locales is a bug that must surface here
      // first.
      expect(SecurityTier.values, hasLength(4));
      expect(
        SecurityTier.values,
        containsAll(<SecurityTier>[
          SecurityTier.plaintext,
          SecurityTier.keychain,
          SecurityTier.hardware,
          SecurityTier.paranoid,
        ]),
      );
    });
  });

  group('SecurityConfig predicates', () {
    test('usesKeychain matches the keychain tier (modifier-agnostic)', () {
      for (final tier in SecurityTier.values) {
        final cfg = SecurityConfig(
          tier: tier,
          modifiers: SecurityTierModifiers.defaults,
        );
        expect(
          cfg.usesKeychain,
          tier == SecurityTier.keychain,
          reason: 'tier=$tier',
        );
      }
    });

    test(
      'hasUserSecret reflects modifier-aware bank-style password gating',
      () {
        for (final tier in SecurityTier.values) {
          for (final pw in [false, true]) {
            final cfg = SecurityConfig(
              tier: tier,
              modifiers: SecurityTierModifiers(password: pw),
            );
            // Paranoid is mandatory-password by definition; keychain
            // + pw is the bank-style L2, hardware + pw is the
            // L3-with-typed-password variant. Plaintext stays out
            // even when the modifier is on — there's no key store
            // for the password to gate against, so the predicate
            // returns false to keep the auto-lock helper from arming.
            final expected =
                tier == SecurityTier.paranoid ||
                ((tier == SecurityTier.keychain ||
                        tier == SecurityTier.hardware) &&
                    pw);
            expect(cfg.hasUserSecret, expected, reason: 'tier=$tier pw=$pw');
          }
        }
      },
    );

    test('isParanoid is strictly paranoid', () {
      for (final tier in SecurityTier.values) {
        final cfg = SecurityConfig(
          tier: tier,
          modifiers: SecurityTierModifiers.defaults,
        );
        expect(
          cfg.isParanoid,
          tier == SecurityTier.paranoid,
          reason: 'tier=$tier',
        );
      }
    });
  });

  group('SecurityConfig JSON round-trip', () {
    test('hardware with 4-digit PIN + biometric shortcut round-trips', () {
      const cfg = SecurityConfig(
        tier: SecurityTier.hardware,
        modifiers: SecurityTierModifiers(biometricShortcut: true, pinLength: 4),
      );
      final decoded = SecurityConfig.fromJson(cfg.toJson());
      expect(decoded, cfg);
    });

    test('paranoid with defaults round-trips', () {
      const cfg = SecurityConfig(
        tier: SecurityTier.paranoid,
        modifiers: SecurityTierModifiers.defaults,
      );
      final decoded = SecurityConfig.fromJson(cfg.toJson());
      expect(decoded, cfg);
    });

    test('unknown tier string falls back to plaintext (defensive)', () {
      final decoded = SecurityConfig.fromJson({
        'tier': 'made_up_tier',
        'modifiers': const SecurityTierModifiers().toJson(),
      });
      expect(decoded.tier, SecurityTier.plaintext);
    });

    test('out-of-range pinLength snaps back to the default', () {
      final decoded = SecurityTierModifiers.fromJson({
        'biometric_shortcut': false,
        'pin_length': 42,
      });
      expect(decoded.pinLength, SecurityTierModifiers.defaults.pinLength);
    });

    test(
      'pinLength at the low and high ends of the accepted range survives',
      () {
        for (final n in [4, 5, 6, 7, 8]) {
          final decoded = SecurityTierModifiers.fromJson({
            'biometric_shortcut': true,
            'pin_length': n,
          });
          expect(decoded.pinLength, n);
        }
      },
    );
  });

  group('SecurityConfig + SecurityTierModifiers value-type contract', () {
    test('SecurityTierModifiers.copyWith replaces only the named fields', () {
      const base = SecurityTierModifiers(
        password: true,
        biometric: true,
        biometricShortcut: true,
        pinLength: 4,
      );
      final tweaked = base.copyWith(pinLength: 8);
      expect(tweaked.pinLength, 8);
      expect(tweaked.password, isTrue);
      expect(tweaked.biometric, isTrue);
      expect(tweaked.biometricShortcut, isTrue);
      final swapped = base.copyWith(password: false, biometric: false);
      expect(swapped.password, isFalse);
      expect(swapped.biometric, isFalse);
      expect(swapped.pinLength, 4);
    });

    test(
      'SecurityTierModifiers == + hashCode agree on every compared field',
      () {
        const a = SecurityTierModifiers(
          password: true,
          biometric: false,
          biometricShortcut: true,
          pinLength: 6,
        );
        const b = SecurityTierModifiers(
          password: true,
          biometric: false,
          biometricShortcut: true,
          pinLength: 6,
        );
        expect(a, b);
        expect(a.hashCode, b.hashCode);
        expect(a == b.copyWith(pinLength: 8), isFalse);
        expect(a == b.copyWith(password: false), isFalse);
      },
    );

    test('SecurityConfig.copyWith + == cover tier and modifiers', () {
      const base = SecurityConfig(
        tier: SecurityTier.keychain,
        modifiers: SecurityTierModifiers(),
      );
      final tierOnly = base.copyWith(tier: SecurityTier.hardware);
      expect(tierOnly.tier, SecurityTier.hardware);
      expect(tierOnly.modifiers, base.modifiers);
      expect(tierOnly, isNot(equals(base)));

      final modsOnly = base.copyWith(
        modifiers: const SecurityTierModifiers(pinLength: 8),
      );
      expect(modsOnly.tier, base.tier);
      expect(modsOnly.modifiers.pinLength, 8);
      expect(modsOnly, isNot(equals(base)));
    });

    test('SecurityConfig == + hashCode + identical() short-circuit', () {
      const a = SecurityConfig(
        tier: SecurityTier.paranoid,
        modifiers: SecurityTierModifiers(password: true, pinLength: 6),
      );
      const b = SecurityConfig(
        tier: SecurityTier.paranoid,
        modifiers: SecurityTierModifiers(password: true, pinLength: 6),
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      // ignore: unrelated_type_equality_checks
      expect(a == a, isTrue);
    });

    test('usesHardwareVault matches the hardware tier exclusively', () {
      for (final tier in SecurityTier.values) {
        final cfg = SecurityConfig(
          tier: tier,
          modifiers: SecurityTierModifiers.defaults,
        );
        expect(
          cfg.usesHardwareVault,
          tier == SecurityTier.hardware,
          reason: 'tier=$tier',
        );
      }
    });

    test('isPlaintext returns true only for plaintext tier', () {
      for (final tier in SecurityTier.values) {
        final cfg = SecurityConfig(
          tier: tier,
          modifiers: SecurityTierModifiers.defaults,
        );
        expect(
          cfg.isPlaintext,
          tier == SecurityTier.plaintext,
          reason: 'tier=$tier',
        );
      }
    });

    test(
      'SecurityConfig.toString carries tier + modifiers for triage logs',
      () {
        const cfg = SecurityConfig(
          tier: SecurityTier.paranoid,
          modifiers: SecurityTierModifiers(password: true),
        );
        final repr = cfg.toString();
        expect(repr, contains('SecurityConfig'));
        expect(repr, contains('paranoid'));
      },
    );
  });
}
