import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/security_tier.dart';
import 'package:letsflutssh/src/rust/api/security_config.dart' as rust_sec_cfg;

import '../../helpers/frb_bootstrap.dart';

void main() {
  // Wire codec routes through `lfs_core::security::SecurityConfig`
  // via the FRB shim — bootstrap FRB so the canonical wire-format
  // encode + permissive decode are exercised.
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(requireFrbLoaded);

  group('SecurityTier enum', () {
    test('carries the four bank-style tier values', () {
      // Bank-style: one tier per key-storage strategy. There is no
      // dedicated `keychainWithPassword` value — L1 + password is
      // `keychain` + `modifiers.password = true`.
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
            // Paranoid and Hardware are mandatory-password by
            // definition — Hardware uses the typed password as the
            // primary gate, biometric is the optional shortcut on
            // top. Keychain flips on the explicit modifier (the
            // bank-style T1+pw shape). Plaintext stays out even
            // when the modifier is on — there's no key store for
            // the password to gate against, so the predicate
            // returns false to keep the auto-lock helper from
            // arming.
            final expected =
                tier == SecurityTier.paranoid ||
                tier == SecurityTier.hardware ||
                (tier == SecurityTier.keychain && pw);
            expect(cfg.hasUserSecret, expected, reason: 'tier=$tier pw=$pw');
          }
        }
      },
    );

    test('requiresPasswordForTier matches the mandatory-password set', () {
      // Hardware and Paranoid always require a password; Keychain
      // leaves the call to the modifier toggle; Plaintext has
      // nothing to gate. The static helper is the wizard /
      // Settings entry point for "should the password slot
      // render?" decisions.
      expect(
        SecurityConfig.requiresPasswordForTier(SecurityTier.paranoid),
        isTrue,
      );
      expect(
        SecurityConfig.requiresPasswordForTier(SecurityTier.hardware),
        isTrue,
      );
      expect(
        SecurityConfig.requiresPasswordForTier(SecurityTier.keychain),
        isFalse,
      );
      expect(
        SecurityConfig.requiresPasswordForTier(SecurityTier.plaintext),
        isFalse,
      );
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

  group('SecurityConfig JSON round-trip via Rust codec', () {
    // The canonical wire codec lives in
    // `lfs_core::security::SecurityConfig` (see the `lfs_core`
    // unit tests). These tests pin the FRB-shim contract — that
    // the typed Dart `SecurityConfig` round-trips byte-identically
    // through `securityConfigToJson` + `securityConfigFromJson` so
    // the persistence boundary in `app_config.dart` keeps the
    // shape stable.

    SecurityConfig roundTrip(SecurityConfig cfg) {
      final json = rust_sec_cfg.securityConfigToJson(
        tier: cfg.tier,
        password: cfg.modifiers.password,
        biometric: cfg.modifiers.biometric,
      );
      final decoded = rust_sec_cfg.securityConfigFromJson(json: json);
      expect(decoded, isNotNull, reason: 'permissive decoder returned null');
      return SecurityConfig(
        tier: decoded!.tier,
        modifiers: SecurityTierModifiers(
          password: decoded.password,
          biometric: decoded.biometric,
        ),
      );
    }

    test('hardware with password + biometric round-trips', () {
      const cfg = SecurityConfig(
        tier: SecurityTier.hardware,
        modifiers: SecurityTierModifiers(password: true, biometric: true),
      );
      expect(roundTrip(cfg), cfg);
    });

    test('keychain with password modifier round-trips (bank-style L2)', () {
      // This combo is tier=keychain + modifiers.password=true, not a
      // dedicated tier. The
      // round-trip exercises both the encode (Rust `to_json_value`)
      // and the decode (permissive parser).
      const cfg = SecurityConfig(
        tier: SecurityTier.keychain,
        modifiers: SecurityTierModifiers(password: true),
      );
      expect(roundTrip(cfg), cfg);
    });

    test('paranoid with defaults round-trips', () {
      const cfg = SecurityConfig(
        tier: SecurityTier.paranoid,
        modifiers: SecurityTierModifiers.defaults,
      );
      expect(roundTrip(cfg), cfg);
    });

    test('unknown tier string falls back to plaintext (defensive)', () {
      // Hand-craft a wire payload with a future-version tier token;
      // the permissive decoder collapses it onto `plaintext` so the
      // caller routes into the wizard rather than landing on a
      // silently-wrong tier.
      final json = jsonEncode({
        'tier': 'made_up_tier',
        'modifiers': {'password': false, 'biometric': false},
      });
      final decoded = rust_sec_cfg.securityConfigFromJson(json: json);
      expect(decoded, isNotNull);
      expect(decoded!.tier, SecurityTier.plaintext);
    });
  });

  group('SecurityConfig + SecurityTierModifiers value-type contract', () {
    test('SecurityTierModifiers.copyWith replaces only the named fields', () {
      const base = SecurityTierModifiers(password: true, biometric: true);
      final pwOff = base.copyWith(password: false);
      expect(pwOff.password, isFalse);
      expect(pwOff.biometric, isTrue);
      final bioOff = base.copyWith(biometric: false);
      expect(bioOff.password, isTrue);
      expect(bioOff.biometric, isFalse);
    });

    test(
      'SecurityTierModifiers == + hashCode agree on every compared field',
      () {
        const a = SecurityTierModifiers(password: true, biometric: false);
        const b = SecurityTierModifiers(password: true, biometric: false);
        expect(a, b);
        expect(a.hashCode, b.hashCode);
        expect(a == b.copyWith(biometric: true), isFalse);
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
        modifiers: const SecurityTierModifiers(password: true),
      );
      expect(modsOnly.tier, base.tier);
      expect(modsOnly.modifiers.password, isTrue);
      expect(modsOnly, isNot(equals(base)));
    });

    test('SecurityConfig == + hashCode + identical() short-circuit', () {
      const a = SecurityConfig(
        tier: SecurityTier.paranoid,
        modifiers: SecurityTierModifiers(password: true),
      );
      const b = SecurityConfig(
        tier: SecurityTier.paranoid,
        modifiers: SecurityTierModifiers(password: true),
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
