import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/key_store.dart';
import 'package:letsflutssh/core/security/master_password.dart';
import 'package:letsflutssh/core/security/security_level.dart';
import 'package:letsflutssh/core/session/session.dart';
import 'package:letsflutssh/core/session/session_store.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;
  late MasterPasswordManager manager;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('master_pw_test_');
    manager = MasterPasswordManager(basePath: tempDir.path);
    // Mock path_provider so CredentialStore/KeyStore resolve to tempDir.
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

  group('MasterPasswordManager', () {
    test('isEnabled returns false when no salt file', () async {
      expect(await manager.isEnabled(), isFalse);
    });

    test('enable creates salt and verifier files', () async {
      await manager.enable('testpassword');

      final saltFile = File('${tempDir.path}/credentials.salt');
      final verifierFile = File('${tempDir.path}/credentials.verify');
      expect(await saltFile.exists(), isTrue);
      expect(await verifierFile.exists(), isTrue);
      expect(await manager.isEnabled(), isTrue);
    });

    test('enable returns 32-byte key', () async {
      final key = await manager.enable('testpassword');
      expect(key.length, 32);
    });

    test('verify returns true for correct password', () async {
      await manager.enable('correctpassword');
      expect(await manager.verify('correctpassword'), isTrue);
    });

    test('verify returns false for wrong password', () async {
      await manager.enable('correctpassword');
      expect(await manager.verify('wrongpassword'), isFalse);
    });

    test('verify works with fresh instance (app restart)', () async {
      await manager.enable('mypassword');

      // Simulate app restart — new instance, same basePath.
      final fresh = MasterPasswordManager(basePath: tempDir.path);
      expect(await fresh.verify('mypassword'), isTrue);
      expect(await fresh.verify('wrongpassword'), isFalse);
    });

    test('deriveKey from fresh instance matches original', () async {
      final originalKey = await manager.enable('mypassword');

      final fresh = MasterPasswordManager(basePath: tempDir.path);
      final freshKey = await fresh.deriveKey('mypassword');
      expect(freshKey, equals(originalKey));
    });

    test('verify throws when not enabled', () async {
      expect(
        () => manager.verify('anything'),
        throwsA(isA<MasterPasswordException>()),
      );
    });

    test('deriveKey returns same key for same password', () async {
      await manager.enable('mypassword');
      final key1 = await manager.deriveKey('mypassword');
      final key2 = await manager.deriveKey('mypassword');
      expect(key1, equals(key2));
    });

    test('deriveKey throws when not enabled', () async {
      expect(
        () => manager.deriveKey('anything'),
        throwsA(isA<MasterPasswordException>()),
      );
    });

    test('changePassword verifies old password', () async {
      await manager.enable('oldpass12');
      expect(
        () => manager.changePassword('wrongold1', 'newpass12'),
        throwsA(
          isA<MasterPasswordException>().having(
            (e) => e.message,
            'message',
            contains('incorrect'),
          ),
        ),
      );
    });

    test('changePassword generates new key', () async {
      final oldKey = await manager.enable('oldpass12');
      final newKey = await manager.changePassword('oldpass12', 'newpass12');
      expect(newKey.length, 32);
      expect(newKey, isNot(equals(oldKey)));
    });

    test('after changePassword old password fails and new succeeds', () async {
      await manager.enable('oldpass12');
      await manager.changePassword('oldpass12', 'newpass12');
      expect(await manager.verify('oldpass12'), isFalse);
      expect(await manager.verify('newpass12'), isTrue);
    });

    test('disable removes salt and verifier files', () async {
      await manager.enable('password');
      expect(await manager.isEnabled(), isTrue);

      await manager.disable();
      expect(await manager.isEnabled(), isFalse);

      final saltFile = File('${tempDir.path}/credentials.salt');
      final verifierFile = File('${tempDir.path}/credentials.verify');
      expect(await saltFile.exists(), isFalse);
      expect(await verifierFile.exists(), isFalse);
    });

    test('disable is safe when not enabled', () async {
      await manager.disable(); // should not throw
      expect(await manager.isEnabled(), isFalse);
    });

    test('reset deletes all encrypted files', () async {
      // Create files that reset should delete.
      await File('${tempDir.path}/credentials.salt').writeAsBytes([1, 2, 3]);
      await File('${tempDir.path}/credentials.verify').writeAsBytes([4, 5, 6]);
      await File('${tempDir.path}/credentials.key').writeAsBytes([7, 8, 9]);
      await File('${tempDir.path}/credentials.enc').writeAsBytes([10, 11]);
      await File('${tempDir.path}/keys.enc').writeAsBytes([12, 13]);

      await manager.reset();

      expect(await File('${tempDir.path}/credentials.salt').exists(), isFalse);
      expect(
        await File('${tempDir.path}/credentials.verify').exists(),
        isFalse,
      );
      expect(await File('${tempDir.path}/credentials.key').exists(), isFalse);
      expect(await File('${tempDir.path}/credentials.enc').exists(), isFalse);
      expect(await File('${tempDir.path}/keys.enc').exists(), isFalse);
    });

    test('enable then re-enable with different password works', () async {
      await manager.enable('first123');
      expect(await manager.verify('first123'), isTrue);

      // Disable and re-enable with different password.
      await manager.disable();
      await manager.enable('second12');
      expect(await manager.verify('first123'), isFalse);
      expect(await manager.verify('second12'), isTrue);
    });
  });

  group('KeyStore with external key', () {
    test('setEncryptionKey allows loadAll and saveAll', () async {
      final key = await manager.enable('mypassword');
      final store = KeyStore();

      store.setEncryptionKey(key, SecurityLevel.masterPassword);
      await store.saveAll({
        'k1': SshKeyEntry(
          id: 'k1',
          label: 'test',
          privateKey: 'pk',
          publicKey: 'pub',
          keyType: 'ed25519',
          createdAt: DateTime(2024),
        ),
      });

      final store2 = KeyStore();
      store2.setEncryptionKey(key, SecurityLevel.masterPassword);
      final all = await store2.loadAll();
      expect(all['k1']?.label, 'test');
    });

    test('plaintext mode stores keys.json', () async {
      final store = KeyStore();
      await store.saveAll({
        'k1': SshKeyEntry(
          id: 'k1',
          label: 'test',
          privateKey: 'pk',
          publicKey: 'pub',
          keyType: 'ed25519',
          createdAt: DateTime(2024),
        ),
      });
      expect(await File('${tempDir.path}/keys.json').exists(), isTrue);
    });
  });

  group('Re-encryption flow', () {
    Session makeSession(String label, String password) => Session(
      label: label,
      server: const ServerAddress(host: 'example.com', user: 'root'),
      auth: SessionAuth(password: password),
    );

    test('enable → re-encrypt → load with derived key', () async {
      // Save session in plaintext first.
      final store = SessionStore(directory: tempDir.path);
      await store.add(makeSession('s1', 'secret'));

      // Enable master password and re-encrypt.
      final key = await manager.enable('masterpass');
      await store.reEncrypt(key, SecurityLevel.masterPassword);

      // Plaintext file should be gone, encrypted file should exist.
      expect(await File('${tempDir.path}/sessions.json').exists(), isFalse);
      expect(await File('${tempDir.path}/sessions.enc').exists(), isTrue);

      // Verify data loads correctly with derived key.
      final freshStore = SessionStore(directory: tempDir.path);
      freshStore.setEncryptionKey(key, SecurityLevel.masterPassword);
      final loaded = await freshStore.load();
      expect(loaded.length, 1);
      expect(loaded.first.label, 's1');
      expect(loaded.first.auth.password, 'secret');
    });

    test('disable → re-encrypt to plaintext → load without key', () async {
      // Start with master password enabled.
      final key = await manager.enable('masterpass');
      final store = SessionStore(directory: tempDir.path);
      store.setEncryptionKey(key, SecurityLevel.masterPassword);
      await store.add(makeSession('s1', 'secret'));

      // Disable master password — re-encrypt to plaintext.
      await store.reEncrypt(null, SecurityLevel.plaintext);
      await manager.disable();

      // Encrypted file should be gone, plaintext file should exist.
      expect(await File('${tempDir.path}/sessions.enc').exists(), isFalse);
      expect(await File('${tempDir.path}/sessions.json').exists(), isTrue);

      // Verify data loads without key.
      final freshStore = SessionStore(directory: tempDir.path);
      final loaded = await freshStore.load();
      expect(loaded.length, 1);
      expect(loaded.first.auth.password, 'secret');
    });
  });
}
