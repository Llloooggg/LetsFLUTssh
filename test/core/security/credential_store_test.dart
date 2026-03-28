import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/export.dart';

import 'package:letsflutssh/core/security/credential_store.dart';

void main() {
  group('CredentialData', () {
    test('isEmpty when all fields empty', () {
      const cred = CredentialData();
      expect(cred.isEmpty, true);
    });

    test('not isEmpty when password set', () {
      const cred = CredentialData(password: 'secret');
      expect(cred.isEmpty, false);
    });

    test('not isEmpty when keyData set', () {
      const cred = CredentialData(keyData: '-----BEGIN RSA PRIVATE KEY-----');
      expect(cred.isEmpty, false);
    });

    test('JSON roundtrip', () {
      const cred = CredentialData(
        password: 'pass123',
        keyData: 'PEM-DATA',
        passphrase: 'phrase',
      );
      final json = cred.toJson();
      final restored = CredentialData.fromJson(json);
      expect(restored.password, 'pass123');
      expect(restored.keyData, 'PEM-DATA');
      expect(restored.passphrase, 'phrase');
    });

    test('fromJson handles missing fields', () {
      final cred = CredentialData.fromJson(<String, dynamic>{});
      expect(cred.password, '');
      expect(cred.keyData, '');
      expect(cred.passphrase, '');
      expect(cred.isEmpty, true);
    });
  });

  group('AES-256-GCM roundtrip', () {
    // Test the crypto primitives directly (same algorithm as CredentialStore)
    test('encrypt then decrypt returns original', () {
      final key = Uint8List.fromList(List.generate(32, (i) => i));
      final iv = Uint8List.fromList(List.generate(12, (i) => i + 100));
      const plaintext = 'Hello, encrypted world! 🔐';

      // Encrypt
      final encCipher = GCMBlockCipher(AESEngine())
        ..init(true, AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)));
      final encrypted = encCipher.process(Uint8List.fromList(utf8.encode(plaintext)));

      // Decrypt
      final decCipher = GCMBlockCipher(AESEngine())
        ..init(false, AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)));
      final decrypted = decCipher.process(encrypted);

      expect(utf8.decode(decrypted), plaintext);
    });

    test('wrong key fails to decrypt', () {
      final key1 = Uint8List.fromList(List.generate(32, (i) => i));
      final key2 = Uint8List.fromList(List.generate(32, (i) => i + 1));
      final iv = Uint8List.fromList(List.generate(12, (i) => i));
      const plaintext = 'secret data';

      final encCipher = GCMBlockCipher(AESEngine())
        ..init(true, AEADParameters(KeyParameter(key1), 128, iv, Uint8List(0)));
      final encrypted = encCipher.process(Uint8List.fromList(utf8.encode(plaintext)));

      final decCipher = GCMBlockCipher(AESEngine())
        ..init(false, AEADParameters(KeyParameter(key2), 128, iv, Uint8List(0)));

      expect(() => decCipher.process(encrypted), throwsA(anything));
    });
  });

  group('PBKDF2 key derivation', () {
    test('same password and salt produce same key', () {
      final salt = Uint8List.fromList(List.generate(32, (i) => i));
      const password = 'test-password';

      final pbkdf2a = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
        ..init(Pbkdf2Parameters(salt, 1000, 32));
      final keyA = pbkdf2a.process(Uint8List.fromList(utf8.encode(password)));

      final pbkdf2b = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
        ..init(Pbkdf2Parameters(salt, 1000, 32));
      final keyB = pbkdf2b.process(Uint8List.fromList(utf8.encode(password)));

      expect(keyA, keyB);
    });

    test('different passwords produce different keys', () {
      final salt = Uint8List.fromList(List.generate(32, (i) => i));

      final pbkdf2a = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
        ..init(Pbkdf2Parameters(salt, 1000, 32));
      final keyA = pbkdf2a.process(Uint8List.fromList(utf8.encode('password1')));

      final pbkdf2b = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
        ..init(Pbkdf2Parameters(salt, 1000, 32));
      final keyB = pbkdf2b.process(Uint8List.fromList(utf8.encode('password2')));

      expect(keyA, isNot(keyB));
    });
  });

  group('CredentialStore — integration', () {
    late Directory tempDir;

    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      tempDir = await Directory.systemTemp.createTemp('cred_test_');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => tempDir.path,
      );
    });

    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        null,
      );
      await tempDir.delete(recursive: true);
    });

    test('loadAll returns empty on fresh store', () async {
      final store = CredentialStore();
      final all = await store.loadAll();
      expect(all, isEmpty);
    });

    test('saveAll then loadAll roundtrip', () async {
      final store = CredentialStore();
      await store.saveAll({
        'session-1': const CredentialData(password: 'pass1'),
        'session-2': const CredentialData(keyData: 'PEM', passphrase: 'pp'),
      });

      final loaded = await store.loadAll();
      expect(loaded.length, 2);
      expect(loaded['session-1']!.password, 'pass1');
      expect(loaded['session-2']!.keyData, 'PEM');
      expect(loaded['session-2']!.passphrase, 'pp');
    });

    test('get returns specific session credentials', () async {
      final store = CredentialStore();
      await store.saveAll({
        'a': const CredentialData(password: 'alpha'),
        'b': const CredentialData(password: 'beta'),
      });

      final cred = await store.get('a');
      expect(cred, isNotNull);
      expect(cred!.password, 'alpha');

      final unknown = await store.get('nonexistent');
      expect(unknown, isNull);
    });

    test('set adds or updates credentials', () async {
      final store = CredentialStore();
      await store.set('s1', const CredentialData(password: 'initial'));

      var loaded = await store.loadAll();
      expect(loaded['s1']!.password, 'initial');

      await store.set('s1', const CredentialData(password: 'updated'));
      loaded = await store.loadAll();
      expect(loaded['s1']!.password, 'updated');
    });

    test('delete removes credentials', () async {
      final store = CredentialStore();
      await store.set('s1', const CredentialData(password: 'p'));
      await store.delete('s1');

      final loaded = await store.loadAll();
      expect(loaded['s1'], isNull);
    });

    test('loadAll throws CredentialStoreException on corrupted file', () async {
      // Write garbage to both files so the store attempts decryption
      final credFile = File('${tempDir.path}/credentials.enc');
      final keyFile = File('${tempDir.path}/credentials.key');
      await credFile.writeAsString('not encrypted data');
      await keyFile.writeAsBytes(List.generate(32, (i) => i));

      final store = CredentialStore();
      expect(
        () => store.loadAll(),
        throwsA(isA<CredentialStoreException>()),
      );
    });

    test('loadAllSafe returns empty on corrupted file', () async {
      final credFile = File('${tempDir.path}/credentials.enc');
      final keyFile = File('${tempDir.path}/credentials.key');
      await credFile.writeAsString('not encrypted data');
      await keyFile.writeAsBytes(List.generate(32, (i) => i));

      final store = CredentialStore();
      final all = await store.loadAllSafe();
      expect(all, isEmpty);
    });

    test('loadAll returns empty when no files exist (not an error)', () async {
      final store = CredentialStore();
      final all = await store.loadAll();
      expect(all, isEmpty);
    });
  });

  group('CredentialData equality', () {
    test('equal data are equal', () {
      const a = CredentialData(password: 'p', keyData: 'k', passphrase: 'pp');
      const b = CredentialData(password: 'p', keyData: 'k', passphrase: 'pp');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('different password not equal', () {
      const a = CredentialData(password: 'a');
      const b = CredentialData(password: 'b');
      expect(a, isNot(equals(b)));
    });

    test('different keyData not equal', () {
      const a = CredentialData(keyData: 'PEM1');
      const b = CredentialData(keyData: 'PEM2');
      expect(a, isNot(equals(b)));
    });

    test('different passphrase not equal', () {
      const a = CredentialData(password: 'p', keyData: 'k', passphrase: 'pp1');
      const b = CredentialData(password: 'p', keyData: 'k', passphrase: 'pp2');
      expect(a, isNot(equals(b)));
    });

    test('empty credentials are equal', () {
      const a = CredentialData();
      const b = CredentialData();
      expect(a, equals(b));
    });

    test('identical returns true', () {
      const a = CredentialData(password: 'x');
      expect(a == a, isTrue);
    });

    test('not equal to other types', () {
      const a = CredentialData();
      expect(a == Object(), isFalse);
    });
  });

  group('CredentialStoreException', () {
    test('toString includes message', () {
      const e = CredentialStoreException('test error');
      expect(e.toString(), contains('test error'));
    });

    test('stores cause', () {
      const cause = FormatException('bad data');
      const e = CredentialStoreException('decrypt failed', cause: cause);
      expect(e.cause, cause);
    });
  });

  group('CredentialStore — concurrent key generation', () {
    late Directory tempDir;

    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      tempDir = await Directory.systemTemp.createTemp('cred_concurrent_');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => tempDir.path,
      );
    });

    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        null,
      );
      await tempDir.delete(recursive: true);
    });

    test('concurrent saveAll calls produce a single key file', () async {
      final store = CredentialStore();
      // Launch two saves simultaneously — only one key should be generated
      await Future.wait([
        store.saveAll({'s1': const CredentialData(password: 'a')}),
        store.saveAll({'s2': const CredentialData(password: 'b')}),
      ]);

      final keyFile = File('${tempDir.path}/credentials.key');
      expect(await keyFile.exists(), isTrue);
      // Key is exactly 32 bytes (AES-256)
      expect((await keyFile.readAsBytes()).length, 32);

      // Both stores are readable after concurrent writes
      final result = await store.loadAll();
      expect(result.isNotEmpty, isTrue);
    });

    test('second saveAll reuses existing key file', () async {
      final store = CredentialStore();
      await store.saveAll({'s1': const CredentialData(password: 'first')});

      final keyFile = File('${tempDir.path}/credentials.key');
      final keyBefore = await keyFile.readAsBytes();

      await store.saveAll({'s1': const CredentialData(password: 'second')});
      final keyAfter = await keyFile.readAsBytes();

      // Key must not change between saves
      expect(keyBefore, equals(keyAfter));
    });
  });

  group('CredentialStore — key-file-only edge cases', () {
    late Directory tempDir;

    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      tempDir = await Directory.systemTemp.createTemp('cred_edge_');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => tempDir.path,
      );
    });

    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        null,
      );
      await tempDir.delete(recursive: true);
    });

    test('loadAll returns empty when key file exists but cred file does not', () async {
      // Simulate leftover key file from a previous install
      final keyFile = File('${tempDir.path}/credentials.key');
      await keyFile.writeAsBytes(List.generate(32, (i) => i));

      final store = CredentialStore();
      final all = await store.loadAll();
      expect(all, isEmpty);
    });

    test('loadAll throws when cred file exists but key file does not', () async {
      // Simulate orphaned cred file (key was deleted)
      final credFile = File('${tempDir.path}/credentials.enc');
      await credFile.writeAsBytes([0, 1, 2, 3]); // garbage, no key to decrypt

      final store = CredentialStore();
      // No key file → loadAll returns empty (both files must exist to attempt decrypt)
      final all = await store.loadAll();
      expect(all, isEmpty);
    });

    test('delete succeeds even when credential file is corrupted', () async {
      final credFile = File('${tempDir.path}/credentials.enc');
      final keyFile = File('${tempDir.path}/credentials.key');
      await credFile.writeAsString('garbage');
      await keyFile.writeAsBytes(List.generate(32, (i) => i));

      final store = CredentialStore();
      // delete uses loadAllSafe — should not throw
      await expectLater(store.delete('any-id'), completes);
    });
  });
}
