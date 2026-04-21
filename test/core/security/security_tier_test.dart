import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/security_tier.dart';

void main() {
  group('SecurityTier enum', () {
    test('carries all five named tiers', () {
      // Freezes the tier vocabulary. Adding or removing a tier without
      // updating wizard, settings, and locales is a bug that must
      // surface here first.
      expect(SecurityTier.values, hasLength(5));
      expect(
        SecurityTier.values,
        containsAll(<SecurityTier>[
          SecurityTier.plaintext,
          SecurityTier.keychain,
          SecurityTier.keychainWithPassword,
          SecurityTier.hardware,
          SecurityTier.paranoid,
        ]),
      );
    });
  });

  group('SecurityConfig predicates', () {
    test('usesKeychain covers L1 and L2 but no other tier', () {
      for (final tier in SecurityTier.values) {
        final cfg = SecurityConfig(
          tier: tier,
          modifiers: SecurityTierModifiers.defaults,
        );
        final expected =
            tier == SecurityTier.keychain ||
            tier == SecurityTier.keychainWithPassword;
        expect(cfg.usesKeychain, expected, reason: 'tier=$tier');
      }
    });

    test('hasUserSecret reflects every tier that prompts at unlock', () {
      for (final tier in SecurityTier.values) {
        final cfg = SecurityConfig(
          tier: tier,
          modifiers: SecurityTierModifiers.defaults,
        );
        final expected =
            tier == SecurityTier.keychainWithPassword ||
            tier == SecurityTier.hardware ||
            tier == SecurityTier.paranoid;
        expect(cfg.hasUserSecret, expected, reason: 'tier=$tier');
      }
    });

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
}
