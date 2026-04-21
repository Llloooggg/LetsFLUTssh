import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/biometric_key_vault.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, String> fakeStore;

  setUp(() {
    fakeStore = {};
    // FlutterSecureStorage talks to the host via a MethodChannel — replace
    // it with an in-memory fake so the test doesn't need a keychain.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (call) async {
            final args =
                (call.arguments as Map?)?.cast<String, Object?>() ?? {};
            switch (call.method) {
              case 'write':
                fakeStore[args['key'] as String] = args['value'] as String;
                return null;
              case 'read':
                return fakeStore[args['key']];
              case 'delete':
                fakeStore.remove(args['key']);
                return null;
              case 'containsKey':
                return fakeStore.containsKey(args['key']);
              case 'readAll':
                return Map<String, String>.from(fakeStore);
              case 'deleteAll':
                fakeStore.clear();
                return null;
            }
            return null;
          },
        );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          null,
        );
  });

  group('BiometricKeyVault', () {
    test('store → read round-trips the key bytes', () async {
      final vault = BiometricKeyVault();
      final key = Uint8List.fromList(List<int>.generate(32, (i) => i));

      expect(await vault.store(key), isTrue);
      expect(await vault.isStored(), isTrue);
      final read = await vault.read();
      expect(read, key);
    });

    test('encodes key as base64 for transport', () async {
      final vault = BiometricKeyVault();
      final key = Uint8List.fromList([1, 2, 3, 4, 5]);
      await vault.store(key);
      // Verify the stored blob is base64 — we don't want plaintext bytes
      // shuttled through a platform channel log on iOS/Android.
      final raw = fakeStore.values.first;
      expect(base64Decode(raw), key);
    });

    test('clear wipes the stored key', () async {
      final vault = BiometricKeyVault();
      await vault.store(Uint8List.fromList([1, 2, 3]));
      await vault.clear();
      expect(await vault.isStored(), isFalse);
      expect(await vault.read(), isNull);
    });

    test('read returns null when nothing stored', () async {
      final vault = BiometricKeyVault();
      expect(await vault.read(), isNull);
      expect(await vault.isStored(), isFalse);
    });

    test('iOS options bind the key to Secure Enclave + biometryCurrentSet', () {
      // Anchors the iOS/macOS Secure Enclave binding invariant: a change that
      // removes the biometryCurrentSet flag (or downgrades the
      // accessibility tier away from passcode-required) must break this
      // test so the regression is caught before ship.
      expect(
        BiometricKeyVault.iosOptions.accessibility,
        KeychainAccessibility.passcode,
      );
      expect(
        BiometricKeyVault.iosOptions.accessControlFlags,
        contains(AccessControlFlag.biometryCurrentSet),
      );
      expect(BiometricKeyVault.iosOptions.synchronizable, isFalse);
    });

    test('macOS options mirror iOS (Secure Enclave + biometryCurrentSet)', () {
      expect(
        BiometricKeyVault.macOsOptions.accessibility,
        KeychainAccessibility.passcode,
      );
      expect(
        BiometricKeyVault.macOsOptions.accessControlFlags,
        contains(AccessControlFlag.biometryCurrentSet),
      );
      expect(BiometricKeyVault.macOsOptions.synchronizable, isFalse);
    });
  });
}
