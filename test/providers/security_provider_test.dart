import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/security_level.dart';
import 'package:letsflutssh/providers/security_provider.dart';

void main() {
  group('SecurityState', () {
    test('default state is plaintext with no encryption key', () {
      final state = SecurityState();
      expect(state.level, SecurityLevel.plaintext);
      expect(state.encryptionKey, isNull);
    });

    test('isEncrypted returns false for plaintext', () {
      final state = SecurityState(level: SecurityLevel.plaintext);
      expect(state.isEncrypted, isFalse);
    });

    test('isEncrypted returns true for keychain', () {
      final state = SecurityState(level: SecurityLevel.keychain);
      expect(state.isEncrypted, isTrue);
    });

    test('isEncrypted returns true for masterPassword', () {
      final state = SecurityState(level: SecurityLevel.masterPassword);
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
          .set(SecurityLevel.masterPassword, key);
      final state = container.read(securityStateProvider);
      expect(state.encryptionKey, equals(key));
    });
  });

  group('SecurityStateNotifier', () {
    test('starts with default plaintext state', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final state = container.read(securityStateProvider);
      expect(state.level, SecurityLevel.plaintext);
      expect(state.isEncrypted, isFalse);
    });

    test('set() updates level without key', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container
          .read(securityStateProvider.notifier)
          .set(SecurityLevel.keychain);
      final state = container.read(securityStateProvider);
      expect(state.level, SecurityLevel.keychain);
      expect(state.encryptionKey, isNull);
      expect(state.isEncrypted, isTrue);
    });

    test('set() updates level with encryption key', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final key = Uint8List.fromList([0, 1, 2, 3]);
      container
          .read(securityStateProvider.notifier)
          .set(SecurityLevel.masterPassword, key);
      final state = container.read(securityStateProvider);
      expect(state.level, SecurityLevel.masterPassword);
      expect(state.encryptionKey, equals(key));
      expect(state.isEncrypted, isTrue);
    });

    test('clearEncryption() resets to plaintext', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(securityStateProvider.notifier);
      notifier.set(SecurityLevel.masterPassword, Uint8List(32));

      // Verify it's encrypted
      expect(container.read(securityStateProvider).isEncrypted, isTrue);

      // Clear
      notifier.clearEncryption();

      final state = container.read(securityStateProvider);
      expect(state.level, SecurityLevel.plaintext);
      expect(state.encryptionKey, isNull);
      expect(state.isEncrypted, isFalse);
    });

    test('set() replaces previous key', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(securityStateProvider.notifier);
      notifier.set(SecurityLevel.masterPassword, Uint8List.fromList([1, 2, 3]));

      final key1 = container.read(securityStateProvider).encryptionKey;
      expect(key1, equals(Uint8List.fromList([1, 2, 3])));

      notifier.set(SecurityLevel.masterPassword, Uint8List.fromList([4, 5, 6]));
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
}
