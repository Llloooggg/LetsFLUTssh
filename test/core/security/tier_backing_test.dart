import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/security_tier.dart';
import 'package:letsflutssh/core/security/tier_backing.dart';

void main() {
  group('classifyTierBacking', () {
    test('plaintext tier → none on every platform', () {
      for (final os in const ['ios', 'macos', 'android', 'windows', 'linux']) {
        expect(
          classifyTierBacking(SecurityTier.plaintext, osOverride: os),
          TierBackingLevel.none,
          reason: 'os=$os',
        );
      }
    });

    test('paranoid → none regardless of OS (key not persisted)', () {
      for (final os in const ['ios', 'macos', 'android', 'windows', 'linux']) {
        expect(
          classifyTierBacking(SecurityTier.paranoid, osOverride: os),
          TierBackingLevel.none,
        );
      }
    });

    test('T1 Apple → Secure Enclave', () {
      for (final os in const ['ios', 'macos']) {
        expect(
          classifyTierBacking(SecurityTier.keychain, osOverride: os),
          TierBackingLevel.hardwareSecureEnclave,
        );
      }
    });

    test(
      'T1 Android → TEE (default; StrongBox refinement needs plugin probe)',
      () {
        expect(
          classifyTierBacking(SecurityTier.keychain, osOverride: 'android'),
          TierBackingLevel.hardwareTee,
        );
      },
    );

    test(
      'T1 Windows → software DPAPI (hardware-binding not surfaced by API)',
      () {
        expect(
          classifyTierBacking(SecurityTier.keychain, osOverride: 'windows'),
          TierBackingLevel.softwareDpapi,
        );
      },
    );

    test('T1 Linux → software libsecret (weakest default)', () {
      expect(
        classifyTierBacking(SecurityTier.keychain, osOverride: 'linux'),
        TierBackingLevel.softwareLibsecret,
      );
    });

    test('T1+password (keychainWithPassword) classifies identically to T1', () {
      for (final os in const ['ios', 'android', 'linux', 'windows']) {
        expect(
          classifyTierBacking(
            SecurityTier.keychainWithPassword,
            osOverride: os,
          ),
          classifyTierBacking(SecurityTier.keychain, osOverride: os),
          reason: 'password modifier does not change the KEK backing',
        );
      }
    });

    test('T2 hardware routes to the platform hw module', () {
      expect(
        classifyTierBacking(SecurityTier.hardware, osOverride: 'ios'),
        TierBackingLevel.hardwareSecureEnclave,
      );
      expect(
        classifyTierBacking(SecurityTier.hardware, osOverride: 'android'),
        TierBackingLevel.hardwareTee,
      );
      expect(
        classifyTierBacking(SecurityTier.hardware, osOverride: 'windows'),
        TierBackingLevel.hardwareTpm,
      );
      expect(
        classifyTierBacking(SecurityTier.hardware, osOverride: 'linux'),
        TierBackingLevel.hardwareTpm,
      );
    });

    test('unknown OS fallback → unknown', () {
      expect(
        classifyTierBacking(SecurityTier.keychain, osOverride: 'haiku'),
        TierBackingLevel.unknown,
      );
    });
  });

  group('TierBackingLevel.isHardware', () {
    test('hardware variants report true', () {
      expect(TierBackingLevel.hardwareSecureEnclave.isHardware, isTrue);
      expect(TierBackingLevel.hardwareStrongbox.isHardware, isTrue);
      expect(TierBackingLevel.hardwareTee.isHardware, isTrue);
      expect(TierBackingLevel.hardwareTpm.isHardware, isTrue);
    });

    test('software / none / unknown report false', () {
      expect(TierBackingLevel.softwareKeychainApple.isHardware, isFalse);
      expect(TierBackingLevel.softwareDpapi.isHardware, isFalse);
      expect(TierBackingLevel.softwareLibsecret.isHardware, isFalse);
      expect(TierBackingLevel.none.isHardware, isFalse);
      expect(TierBackingLevel.unknown.isHardware, isFalse);
    });
  });

  group('TierBackingLevel.shortName', () {
    test('every variant has a non-empty label', () {
      for (final level in TierBackingLevel.values) {
        expect(level.shortName, isNotEmpty);
      }
    });
  });
}
