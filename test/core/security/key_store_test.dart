import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/key_store.dart';
import 'package:letsflutssh/core/security/security_level.dart';

void main() {
  group('SshKeyEntry', () {
    test('JSON roundtrip preserves all fields', () {
      final entry = SshKeyEntry(
        id: 'test-id',
        label: 'My Key',
        privateKey:
            '-----BEGIN OPENSSH PRIVATE KEY-----\nfake\n-----END OPENSSH PRIVATE KEY-----',
        publicKey: 'ssh-ed25519 AAAA test',
        keyType: 'ssh-ed25519',
        createdAt: DateTime(2025, 6, 15),
        isGenerated: true,
      );

      final json = entry.toJson();
      final restored = SshKeyEntry.fromJson(json);

      expect(restored.id, entry.id);
      expect(restored.label, entry.label);
      expect(restored.privateKey, entry.privateKey);
      expect(restored.publicKey, entry.publicKey);
      expect(restored.keyType, entry.keyType);
      expect(restored.createdAt, entry.createdAt);
      expect(restored.isGenerated, isTrue);
    });

    test('fromJson handles missing fields gracefully', () {
      final entry = SshKeyEntry.fromJson({'id': 'x'});
      expect(entry.id, 'x');
      expect(entry.label, isEmpty);
      expect(entry.privateKey, isEmpty);
      expect(entry.isGenerated, isFalse);
    });

    test('equality compares id, label, privateKey', () {
      final a = SshKeyEntry(
        id: '1',
        label: 'A',
        privateKey: 'pk',
        publicKey: 'pub',
        keyType: 'ssh-ed25519',
        createdAt: DateTime(2025),
      );
      final b = SshKeyEntry(
        id: '1',
        label: 'A',
        privateKey: 'pk',
        publicKey: 'pub-different',
        keyType: 'ssh-rsa',
        createdAt: DateTime(2026),
      );
      expect(a, equals(b));
    });

    test('copyWith updates label', () {
      final entry = SshKeyEntry(
        id: '1',
        label: 'Old',
        privateKey: 'pk',
        publicKey: 'pub',
        keyType: 'ssh-ed25519',
        createdAt: DateTime(2025),
      );
      final updated = entry.copyWith(label: 'New');
      expect(updated.label, 'New');
      expect(updated.id, entry.id);
      expect(updated.privateKey, entry.privateKey);
    });
  });

  group('Key generation', () {
    test('generateKeyPair Ed25519 produces valid PEM', () {
      final entry = KeyStore.generateKeyPair(SshKeyType.ed25519, 'test-ed');
      expect(entry.keyType, 'ssh-ed25519');
      expect(entry.privateKey, contains('OPENSSH PRIVATE KEY'));
      expect(entry.publicKey, startsWith('ssh-ed25519 '));
      expect(entry.publicKey, endsWith(' test-ed'));
      expect(entry.label, 'test-ed');
      expect(entry.isGenerated, isTrue);
      expect(entry.id, isNotEmpty);

      // Verify dartssh2 can parse the generated PEM back
      final pairs = SSHKeyPair.fromPem(entry.privateKey);
      expect(pairs, isNotEmpty);
      expect(pairs.first.type, 'ssh-ed25519');
    });

    test('generateKeyPair RSA-2048 produces valid PEM', () {
      final entry = KeyStore.generateKeyPair(SshKeyType.rsa2048, 'test-rsa');
      expect(entry.keyType, contains('rsa'));
      expect(entry.privateKey, contains('OPENSSH PRIVATE KEY'));
      expect(entry.publicKey, contains('rsa'));
      expect(entry.isGenerated, isTrue);

      // Verify dartssh2 can parse
      final pairs = SSHKeyPair.fromPem(entry.privateKey);
      expect(pairs, isNotEmpty);
    });

    test('two generated Ed25519 keys are different', () {
      final a = KeyStore.generateKeyPair(SshKeyType.ed25519, 'key-a');
      final b = KeyStore.generateKeyPair(SshKeyType.ed25519, 'key-b');
      expect(a.privateKey, isNot(b.privateKey));
      expect(a.publicKey, isNot(b.publicKey));
      expect(a.id, isNot(b.id));
    });
  });

  group('Key import', () {
    test('importKey parses Ed25519 PEM', () {
      // Generate a valid PEM first
      final generated = KeyStore.generateKeyPair(SshKeyType.ed25519, 'gen');
      final store = KeyStore();
      final entry = store.importKey(generated.privateKey, 'imported');

      expect(entry.label, 'imported');
      expect(entry.keyType, 'ssh-ed25519');
      expect(entry.privateKey, isNotEmpty);
      expect(entry.publicKey, startsWith('ssh-ed25519 '));
      expect(entry.isGenerated, isFalse);
    });

    test('importKey throws on invalid PEM', () {
      final store = KeyStore();
      expect(() => store.importKey('not a PEM', 'bad'), throwsA(isA<Object>()));
    });
  });

  group('KeyStore encryption', () {
    // Uses the same AES-256-GCM encrypt/decrypt as SessionStore.
    // Test via the full KeyStore with mocked path_provider.
    TestWidgetsFlutterBinding.ensureInitialized();
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('key_store_test_');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async => tempDir.path,
          );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            null,
          );
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    final testKey = Uint8List.fromList(List.generate(32, (i) => i));

    /// Create an encrypted KeyStore for testing.
    KeyStore createEncryptedStore() {
      final store = KeyStore();
      store.setEncryptionKey(testKey, SecurityLevel.keychain);
      return store;
    }

    test('plaintext save and load roundtrip', () async {
      final store = KeyStore();
      final entry = KeyStore.generateKeyPair(SshKeyType.ed25519, 'roundtrip');
      await store.save(entry);

      final store2 = KeyStore();
      final loaded = await store2.loadAll();
      expect(loaded.length, 1);
      expect(loaded[entry.id]!.label, 'roundtrip');
      expect(loaded[entry.id]!.keyType, 'ssh-ed25519');
      expect(loaded[entry.id]!.privateKey, entry.privateKey);
    });

    test('encrypted save and load roundtrip', () async {
      final store = createEncryptedStore();
      final entry = KeyStore.generateKeyPair(SshKeyType.ed25519, 'roundtrip');
      await store.save(entry);

      final store2 = createEncryptedStore();
      final loaded = await store2.loadAll();
      expect(loaded.length, 1);
      expect(loaded[entry.id]!.label, 'roundtrip');
    });

    test('loadAll returns empty when no files exist', () async {
      final store = KeyStore();
      final result = await store.loadAll();
      expect(result, isEmpty);
    });

    test('loadAllSafe returns empty on decrypt error', () async {
      await File('${tempDir.path}/keys.enc').writeAsBytes([1, 2, 3]);
      final store = createEncryptedStore();
      final result = await store.loadAllSafe();
      expect(result, isEmpty);
    });

    test('loadAll throws KeyStoreException on corrupt data', () async {
      await File('${tempDir.path}/keys.enc').writeAsBytes([1, 2, 3]);
      final store = createEncryptedStore();
      expect(() => store.loadAll(), throwsA(isA<KeyStoreException>()));
    });

    test('delete removes entry', () async {
      final store = KeyStore();
      final e1 = KeyStore.generateKeyPair(SshKeyType.ed25519, 'one');
      final e2 = KeyStore.generateKeyPair(SshKeyType.ed25519, 'two');
      await store.save(e1);
      await store.save(e2);

      await store.delete(e1.id);
      final loaded = await store.loadAll();
      expect(loaded.length, 1);
      expect(loaded.containsKey(e2.id), isTrue);
    });

    test('get returns single entry or null', () async {
      final store = KeyStore();
      final entry = KeyStore.generateKeyPair(SshKeyType.ed25519, 'test');
      await store.save(entry);

      final found = await store.get(entry.id);
      expect(found, isNotNull);
      expect(found!.label, 'test');

      final missing = await store.get('nonexistent');
      expect(missing, isNull);
    });

    test('cache is used on subsequent loadAll calls', () async {
      final store = KeyStore();
      final entry = KeyStore.generateKeyPair(SshKeyType.ed25519, 'cached');
      await store.save(entry);

      final first = await store.loadAll();
      // Delete the file — cached data should still be returned
      await File('${tempDir.path}/keys.json').delete();
      final second = await store.loadAll();
      expect(second.length, first.length);
    });

    test('reEncrypt from plaintext to encrypted', () async {
      final store = KeyStore();
      final entry = KeyStore.generateKeyPair(SshKeyType.ed25519, 're-enc');
      await store.save(entry);

      await store.reEncrypt(testKey, SecurityLevel.keychain);
      expect(await File('${tempDir.path}/keys.json').exists(), isFalse);
      expect(await File('${tempDir.path}/keys.enc').exists(), isTrue);

      final store2 = createEncryptedStore();
      final loaded = await store2.loadAll();
      expect(loaded[entry.id]!.label, 're-enc');
    });
  });

  group('SshKeyType', () {
    test('all types have labels', () {
      for (final t in SshKeyType.values) {
        expect(t.label, isNotEmpty);
      }
    });
  });
}
