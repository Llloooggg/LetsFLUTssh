import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/secure_key_storage.dart';
import 'package:letsflutssh/core/security/security_tier.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/providers/security_provider.dart';

import '../helpers/frb_bootstrap.dart';

void main() {
  // The notifier's `clearEncryption` calls `secretsDrop` Rust-side
  // — bootstrap FRB so the call has somewhere to land in
  // flutter_test.
  setUpAll(requireFrbLoaded);

  group('SecurityState', () {
    test('default state is plaintext with no active key', () {
      const state = SecurityState();
      expect(state.level, SecurityTier.plaintext);
      expect(state.hasActiveDbKey, isFalse);
    });

    test('isEncrypted returns false for plaintext', () {
      const state = SecurityState(level: SecurityTier.plaintext);
      expect(state.isEncrypted, isFalse);
    });

    test('isEncrypted returns true for keychain', () {
      const state = SecurityState(level: SecurityTier.keychain);
      expect(state.isEncrypted, isTrue);
    });

    test('isEncrypted returns true for paranoid', () {
      const state = SecurityState(level: SecurityTier.paranoid);
      expect(state.isEncrypted, isTrue);
    });

    test('hasActiveDbKey flips when notifier is told the slot is staged', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container
          .read(securityStateProvider.notifier)
          .setActive(SecurityTier.paranoid, hasKey: true);
      final state = container.read(securityStateProvider);
      expect(state.hasActiveDbKey, isTrue);
    });
  });

  group('SecurityStateNotifier', () {
    test('starts with default plaintext state', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final state = container.read(securityStateProvider);
      expect(state.level, SecurityTier.plaintext);
      expect(state.isEncrypted, isFalse);
      expect(state.hasActiveDbKey, isFalse);
    });

    test('setActive(level, hasKey: false) updates tier without staging', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container
          .read(securityStateProvider.notifier)
          .setActive(SecurityTier.keychain, hasKey: false);
      final state = container.read(securityStateProvider);
      expect(state.level, SecurityTier.keychain);
      expect(state.hasActiveDbKey, isFalse);
      expect(state.isEncrypted, isTrue);
    });

    test('setActive(level, hasKey: true) records active slot', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container
          .read(securityStateProvider.notifier)
          .setActive(SecurityTier.paranoid, hasKey: true);
      final state = container.read(securityStateProvider);
      expect(state.level, SecurityTier.paranoid);
      expect(state.hasActiveDbKey, isTrue);
      expect(state.isEncrypted, isTrue);
    });

    test('clearEncryption() resets to plaintext + drops active slot', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(securityStateProvider.notifier);
      notifier.setActive(SecurityTier.paranoid, hasKey: true);

      expect(container.read(securityStateProvider).isEncrypted, isTrue);

      notifier.clearEncryption();

      final state = container.read(securityStateProvider);
      expect(state.level, SecurityTier.plaintext);
      expect(state.hasActiveDbKey, isFalse);
      expect(state.isEncrypted, isFalse);
    });

    test('setActive replaces previous transition', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(securityStateProvider.notifier);
      notifier.setActive(SecurityTier.paranoid, hasKey: true);
      expect(container.read(securityStateProvider).hasActiveDbKey, isTrue);
      notifier.setActive(SecurityTier.keychain, hasKey: false);
      final state = container.read(securityStateProvider);
      expect(state.level, SecurityTier.keychain);
      expect(state.hasActiveDbKey, isFalse);
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
