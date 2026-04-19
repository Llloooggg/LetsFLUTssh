import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/secure_key_storage.dart';

/// In-memory fake that mirrors FlutterSecureStorage API.
class FakeFlutterSecureStorage implements FlutterSecureStorage {
  final Map<String, String> _store = {};
  bool shouldThrow = false;

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (shouldThrow) throw Exception('Keychain unavailable');
    if (value == null) {
      _store.remove(key);
    } else {
      _store[key] = value;
    }
  }

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (shouldThrow) throw Exception('Keychain unavailable');
    return _store[key];
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (shouldThrow) throw Exception('Keychain unavailable');
    _store.remove(key);
  }

  @override
  Future<bool> containsKey({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (shouldThrow) throw Exception('Keychain unavailable');
    return _store.containsKey(key);
  }

  @override
  Future<Map<String, String>> readAll({
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (shouldThrow) throw Exception('Keychain unavailable');
    return Map.of(_store);
  }

  @override
  Future<void> deleteAll({
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (shouldThrow) throw Exception('Keychain unavailable');
    _store.clear();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late FakeFlutterSecureStorage fakeStorage;
  late SecureKeyStorage keyStorage;

  setUp(() {
    fakeStorage = FakeFlutterSecureStorage();
    keyStorage = SecureKeyStorage(storage: fakeStorage);
  });

  group('SecureKeyStorage', () {
    group('isAvailable', () {
      test('returns true when keychain works', () async {
        expect(await keyStorage.isAvailable(), isTrue);
      });

      test('returns false when keychain throws', () async {
        fakeStorage.shouldThrow = true;
        expect(await keyStorage.isAvailable(), isFalse);
      });

      test('cleans up probe key after successful check', () async {
        await keyStorage.isAvailable();
        final all = await fakeStorage.readAll();
        expect(all.containsKey('letsflutssh_keychain_probe'), isFalse);
      });
    });

    group('writeKey / readKey', () {
      test('roundtrip stores and retrieves key', () async {
        final key = Uint8List.fromList(List.generate(32, (i) => i));
        final wrote = await keyStorage.writeKey(key);
        expect(wrote, isTrue);

        final read = await keyStorage.readKey();
        expect(read, equals(key));
      });

      test('readKey returns null when no key stored', () async {
        expect(await keyStorage.readKey(), isNull);
      });

      test('writeKey returns false on failure', () async {
        fakeStorage.shouldThrow = true;
        final key = Uint8List(32);
        expect(await keyStorage.writeKey(key), isFalse);
      });

      test('readKey returns null on failure', () async {
        final key = Uint8List.fromList(List.generate(32, (i) => i));
        await keyStorage.writeKey(key);
        fakeStorage.shouldThrow = true;
        expect(await keyStorage.readKey(), isNull);
      });

      test('key is stored as base64', () async {
        final key = Uint8List.fromList(List.generate(32, (i) => i * 2));
        await keyStorage.writeKey(key);
        final all = await fakeStorage.readAll();
        final stored = all['letsflutssh_encryption_key']!;
        expect(base64Decode(stored), equals(key));
      });
    });

    group('deleteKey', () {
      test('removes stored key', () async {
        final key = Uint8List(32);
        await keyStorage.writeKey(key);
        await keyStorage.deleteKey();
        expect(await keyStorage.readKey(), isNull);
      });

      test('does not throw when key does not exist', () async {
        await keyStorage.deleteKey(); // should not throw
      });

      test('does not throw on failure', () async {
        fakeStorage.shouldThrow = true;
        await keyStorage.deleteKey(); // should not throw
      });
    });

    group('multiple keys isolation', () {
      test('writeKey does not affect probe key', () async {
        final key = Uint8List(32);
        await keyStorage.writeKey(key);
        expect(await keyStorage.isAvailable(), isTrue);
        // encryption key should still be there
        expect(await keyStorage.readKey(), equals(key));
      });

      test('isAvailable does not affect encryption key', () async {
        final key = Uint8List.fromList(List.generate(32, (i) => i));
        await keyStorage.writeKey(key);
        await keyStorage.isAvailable();
        expect(await keyStorage.readKey(), equals(key));
      });
    });

    group('biometric-gated key', () {
      test('writeBiometricKey + readBiometricKey round-trip', () async {
        final key = Uint8List.fromList(
          List.generate(32, (i) => (i * 7) & 0xFF),
        );
        expect(await keyStorage.writeBiometricKey(key), isTrue);
        expect(await keyStorage.readBiometricKey(), equals(key));
      });

      test(
        'biometric key lives under a distinct alias — not readable via readKey',
        () async {
          final key = Uint8List.fromList(List.generate(32, (i) => i));
          await keyStorage.writeBiometricKey(key);
          expect(
            await keyStorage.readKey(),
            isNull,
            reason: 'plain readKey() must not return the biometric-gated alias',
          );
        },
      );

      test('plain writeKey does not populate the biometric alias', () async {
        final key = Uint8List.fromList(List.generate(32, (i) => i));
        await keyStorage.writeKey(key);
        expect(await keyStorage.readBiometricKey(), isNull);
      });

      test('deleteBiometricKey clears only the biometric alias', () async {
        final keyA = Uint8List.fromList(List.generate(32, (i) => i));
        final keyB = Uint8List.fromList(
          List.generate(32, (i) => (i * 3) & 0xFF),
        );
        await keyStorage.writeKey(keyA);
        await keyStorage.writeBiometricKey(keyB);

        await keyStorage.deleteBiometricKey();

        expect(await keyStorage.readKey(), equals(keyA));
        expect(await keyStorage.readBiometricKey(), isNull);
      });

      test('writeBiometricKey surfaces failures as false', () async {
        fakeStorage.shouldThrow = true;
        final key = Uint8List.fromList(List.generate(32, (i) => i));
        expect(await keyStorage.writeBiometricKey(key), isFalse);
      });

      test('readBiometricKey returns null on backing-store failure', () async {
        final key = Uint8List.fromList(List.generate(32, (i) => i));
        await keyStorage.writeBiometricKey(key);
        fakeStorage.shouldThrow = true;
        expect(await keyStorage.readBiometricKey(), isNull);
      });
    });
  });
}
