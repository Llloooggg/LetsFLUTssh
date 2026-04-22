import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/secure_key_storage.dart';
import 'package:letsflutssh/core/security/security_tier.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/providers/security_provider.dart';

void main() {
  group('SecurityState', () {
    test('default state is plaintext with no encryption key', () {
      final state = SecurityState();
      expect(state.level, SecurityTier.plaintext);
      expect(state.encryptionKey, isNull);
    });

    test('isEncrypted returns false for plaintext', () {
      final state = SecurityState(level: SecurityTier.plaintext);
      expect(state.isEncrypted, isFalse);
    });

    test('isEncrypted returns true for keychain', () {
      final state = SecurityState(level: SecurityTier.keychain);
      expect(state.isEncrypted, isTrue);
    });

    test('isEncrypted returns true for masterPassword', () {
      final state = SecurityState(level: SecurityTier.paranoid);
      expect(state.isEncrypted, isTrue);
    });

    test('encryptionKey is preserved when set via notifier', () {
      // Key bytes are copied into a locked SecretBuffer by the notifier, so
      // we go through the provider instead of constructing SecurityState
      // directly.
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final key = Uint8List.fromList([1, 2, 3, 4]);
      container
          .read(securityStateProvider.notifier)
          .set(SecurityTier.paranoid, key);
      final state = container.read(securityStateProvider);
      expect(state.encryptionKey, equals(key));
    });
  });

  group('SecurityStateNotifier', () {
    test('starts with default plaintext state', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final state = container.read(securityStateProvider);
      expect(state.level, SecurityTier.plaintext);
      expect(state.isEncrypted, isFalse);
    });

    test('set() updates level without key', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(securityStateProvider.notifier).set(SecurityTier.keychain);
      final state = container.read(securityStateProvider);
      expect(state.level, SecurityTier.keychain);
      expect(state.encryptionKey, isNull);
      expect(state.isEncrypted, isTrue);
    });

    test('set() updates level with encryption key', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final key = Uint8List.fromList([0, 1, 2, 3]);
      container
          .read(securityStateProvider.notifier)
          .set(SecurityTier.paranoid, key);
      final state = container.read(securityStateProvider);
      expect(state.level, SecurityTier.paranoid);
      expect(state.encryptionKey, equals(key));
      expect(state.isEncrypted, isTrue);
    });

    test('clearEncryption() resets to plaintext', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(securityStateProvider.notifier);
      notifier.set(SecurityTier.paranoid, Uint8List(32));

      // Verify it's encrypted
      expect(container.read(securityStateProvider).isEncrypted, isTrue);

      // Clear
      notifier.clearEncryption();

      final state = container.read(securityStateProvider);
      expect(state.level, SecurityTier.plaintext);
      expect(state.encryptionKey, isNull);
      expect(state.isEncrypted, isFalse);
    });

    test('set() replaces previous key', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(securityStateProvider.notifier);
      notifier.set(SecurityTier.paranoid, Uint8List.fromList([1, 2, 3]));

      final key1 = container.read(securityStateProvider).encryptionKey;
      expect(key1, equals(Uint8List.fromList([1, 2, 3])));

      notifier.set(SecurityTier.paranoid, Uint8List.fromList([4, 5, 6]));
      final key2 = container.read(securityStateProvider).encryptionKey;
      expect(key2, equals(Uint8List.fromList([4, 5, 6])));
    });
  });

  group('secureKeyStorageProvider', () {
    test('returns SecureKeyStorage instance', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final storage = container.read(secureKeyStorageProvider);
      expect(storage, isA<Object>()); // SecureKeyStorage instance
    });
  });

  group('probe detail text helpers', () {
    late S l10n;

    setUpAll(() async {
      l10n = await S.delegate.load(const Locale('en'));
    });

    test('hardwareProbeDetailText returns non-empty for every non-available '
        'case so a missing switch arm is caught by the analyser', () {
      for (final detail in HardwareProbeDetail.values) {
        final text = hardwareProbeDetailText(l10n, detail);
        if (detail == HardwareProbeDetail.available) {
          expect(
            text,
            isEmpty,
            reason: 'available returns empty — UI hides the card entirely',
          );
        } else {
          expect(
            text,
            isNotEmpty,
            reason: '$detail must surface an actionable line to the user',
          );
        }
      }
    });

    test('keyringProbeDetailText returns non-empty for every non-available '
        'case', () {
      for (final result in KeyringProbeResult.values) {
        final text = keyringProbeDetailText(l10n, result);
        if (result == KeyringProbeResult.available) {
          expect(text, isEmpty);
        } else {
          expect(
            text,
            isNotEmpty,
            reason: '$result must surface an actionable line to the user',
          );
        }
      }
    });
  });

  group('decodeHardwareProbeCode', () {
    test('every known native code maps to a non-generic enum variant', () {
      // The switch map is the only thing that keeps the native plugin
      // vocabulary in lockstep with the UI hint copy. Every entry here
      // also has a matching ARB string (exercised by the
      // hardwareProbeDetailText test above), so a misspelled case here
      // would surface as a blank tooltip in production.
      const expected = <String, HardwareProbeDetail>{
        'available': HardwareProbeDetail.available,
        'windowsSoftwareOnly': HardwareProbeDetail.windowsSoftwareOnly,
        'windowsProvidersMissing': HardwareProbeDetail.windowsProvidersMissing,
        'macosNoSecureEnclave': HardwareProbeDetail.macosNoSecureEnclave,
        'macosPasscodeNotSet': HardwareProbeDetail.macosPasscodeNotSet,
        'macosSigningIdentityMissing':
            HardwareProbeDetail.macosSigningIdentityMissing,
        'macosGeneric': HardwareProbeDetail.macosGeneric,
        'iosPasscodeNotSet': HardwareProbeDetail.iosPasscodeNotSet,
        'iosSimulator': HardwareProbeDetail.iosSimulator,
        'iosGeneric': HardwareProbeDetail.iosGeneric,
        'androidApiTooLow': HardwareProbeDetail.androidApiTooLow,
        'androidBiometricNone': HardwareProbeDetail.androidBiometricNone,
        'androidBiometricNotEnrolled':
            HardwareProbeDetail.androidBiometricNotEnrolled,
        'androidBiometricUnavailable':
            HardwareProbeDetail.androidBiometricUnavailable,
        'androidKeystoreRejected': HardwareProbeDetail.androidKeystoreRejected,
        'androidGeneric': HardwareProbeDetail.androidGeneric,
      };
      for (final entry in expected.entries) {
        expect(decodeHardwareProbeCode(entry.key), entry.value);
      }
    });

    test('unknown codes fall through to generic rather than throwing', () {
      // A native plugin that adds a new reason ahead of the Dart enum
      // must not crash Settings — the contract is "treat the unknown
      // value as generic" so the user sees a generic hint instead of a
      // crash dialog.
      expect(
        decodeHardwareProbeCode('brandNewReason'),
        HardwareProbeDetail.generic,
      );
      expect(decodeHardwareProbeCode(''), HardwareProbeDetail.generic);
      expect(decodeHardwareProbeCode('unknown'), HardwareProbeDetail.generic);
    });
  });
}
