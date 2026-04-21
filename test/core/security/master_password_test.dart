import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/db/database_opener.dart';
import 'package:letsflutssh/core/security/key_store.dart';
import 'package:letsflutssh/core/security/master_password.dart';

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
    test('isEnabled returns false when no kdf file', () async {
      expect(await manager.isEnabled(), isFalse);
    });

    test('enable creates credentials.kdf and verifier files', () async {
      await manager.enable('testpassword');

      final kdfFile = File('${tempDir.path}/credentials.kdf');
      final verifierFile = File('${tempDir.path}/credentials.verify');
      expect(await kdfFile.exists(), isTrue);
      expect(await verifierFile.exists(), isTrue);
      expect(await manager.isEnabled(), isTrue);
    });

    test('credentials.kdf starts with the LFKD magic + version 0x01', () async {
      await manager.enable('testpassword');
      final bytes = await File('${tempDir.path}/credentials.kdf').readAsBytes();
      expect(bytes[0], 0x4C); // 'L'
      expect(bytes[1], 0x46); // 'F'
      expect(bytes[2], 0x4B); // 'K'
      expect(bytes[3], 0x44); // 'D'
      expect(bytes[4], 0x01, reason: 'file version');
      expect(bytes[5], 0x01, reason: 'KDF algorithm id (Argon2id)');
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

    test('verifyAndDerive returns the same key as deriveKey on success, null '
        'on wrong password — one PBKDF2 run instead of two', () async {
      final originalKey = await manager.enable('secretpass');

      final fresh = MasterPasswordManager(basePath: tempDir.path);
      final derivedOk = await fresh.verifyAndDerive('secretpass');
      expect(derivedOk, isNotNull);
      expect(derivedOk, equals(originalKey));

      expect(await fresh.verifyAndDerive('wrongpass'), isNull);
    });

    test(
      'verifyAndDerive throws when master password is not enabled',
      () async {
        expect(
          () => manager.verifyAndDerive('anything'),
          throwsA(isA<MasterPasswordException>()),
        );
      },
    );

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

    test('disable removes kdf and verifier files', () async {
      await manager.enable('password');
      expect(await manager.isEnabled(), isTrue);

      await manager.disable();
      expect(await manager.isEnabled(), isFalse);

      expect(await File('${tempDir.path}/credentials.kdf').exists(), isFalse);
      expect(
        await File('${tempDir.path}/credentials.verify').exists(),
        isFalse,
      );
    });

    test('disable is safe when not enabled', () async {
      await manager.disable(); // should not throw
      expect(await manager.isEnabled(), isFalse);
    });

    test('reset deletes all credential files', () async {
      await File('${tempDir.path}/credentials.kdf').writeAsBytes([1, 2, 3]);
      await File('${tempDir.path}/credentials.verify').writeAsBytes([4, 5, 6]);
      await File('${tempDir.path}/credentials.key').writeAsBytes([7, 8, 9]);

      await manager.reset();

      expect(await File('${tempDir.path}/credentials.kdf').exists(), isFalse);
      expect(
        await File('${tempDir.path}/credentials.verify').exists(),
        isFalse,
      );
      expect(await File('${tempDir.path}/credentials.key').exists(), isFalse);
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

  group('KeyStore with DB', () {
    test('setDatabase allows save and loadAll', () async {
      final db = openTestDatabase();
      final store = KeyStore()..setDatabase(db);

      await store.save(
        SshKeyEntry(
          id: 'k1',
          label: 'test',
          privateKey: 'pk',
          publicKey: 'pub',
          keyType: 'ed25519',
          createdAt: DateTime(2024),
        ),
      );

      final all = await store.loadAll();
      expect(all['k1']?.label, 'test');
      await db.close();
    });
  });
}
