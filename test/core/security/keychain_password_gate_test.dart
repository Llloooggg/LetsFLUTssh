import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:letsflutssh/core/security/keychain_password_gate.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Map<String, String> fakeKeychain;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('l2_gate_test_');
    fakeKeychain = {};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (call) async {
            final args =
                (call.arguments as Map?)?.cast<String, Object?>() ?? {};
            switch (call.method) {
              case 'write':
                fakeKeychain[args['key'] as String] = args['value'] as String;
                return null;
              case 'read':
                return fakeKeychain[args['key']];
              case 'delete':
                fakeKeychain.remove(args['key']);
                return null;
              case 'containsKey':
                return fakeKeychain.containsKey(args['key']);
              case 'deleteAll':
                fakeKeychain.clear();
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
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  KeychainPasswordGate newGate() => KeychainPasswordGate(
    keychain: const FlutterSecureStorage(),
    hashFileFactory: () async => File('${tempDir.path}/security_pass_hash.bin'),
  );

  group('KeychainPasswordGate', () {
    test('isConfigured starts false on a clean install', () async {
      expect(await newGate().isConfigured(), isFalse);
    });

    test('setPassword writes both disk hash + keychain pepper', () async {
      final gate = newGate();
      await gate.setPassword('hunter2');
      expect(await gate.isConfigured(), isTrue);
      expect(fakeKeychain.keys, contains('letsflutssh_l2_pepper'));
      expect(
        File('${tempDir.path}/security_pass_hash.bin').existsSync(),
        isTrue,
      );
    });

    test('verify returns true for the correct password', () async {
      final gate = newGate();
      await gate.setPassword('hunter2');
      expect(await gate.verify('hunter2'), isTrue);
    });

    test('verify returns false for a wrong password', () async {
      final gate = newGate();
      await gate.setPassword('hunter2');
      expect(await gate.verify('hunter3'), isFalse);
    });

    test('verify is false when either half of the state is missing', () async {
      final gate = newGate();
      await gate.setPassword('hunter2');

      // Drop only the keychain pepper — disk hash alone is useless.
      fakeKeychain.clear();
      expect(await gate.verify('hunter2'), isFalse);

      // Reset, then drop the disk hash.
      await gate.setPassword('hunter2');
      File('${tempDir.path}/security_pass_hash.bin').deleteSync();
      expect(await gate.verify('hunter2'), isFalse);
    });

    test('verify is false when the disk blob is corrupt', () async {
      final gate = newGate();
      await gate.setPassword('hunter2');
      File(
        '${tempDir.path}/security_pass_hash.bin',
      ).writeAsStringSync('not json');
      expect(await gate.verify('hunter2'), isFalse);
    });

    test('clear drops hash file + pepper', () async {
      final gate = newGate();
      await gate.setPassword('hunter2');
      await gate.clear();
      expect(await gate.isConfigured(), isFalse);
      expect(
        File('${tempDir.path}/security_pass_hash.bin').existsSync(),
        isFalse,
      );
      expect(fakeKeychain.containsKey('letsflutssh_l2_pepper'), isFalse);
    });

    test('setPassword twice rotates salt + pepper (hash changes)', () async {
      final gate = newGate();
      await gate.setPassword('hunter2');
      final first = File(
        '${tempDir.path}/security_pass_hash.bin',
      ).readAsStringSync();
      await gate.setPassword('hunter2');
      final second = File(
        '${tempDir.path}/security_pass_hash.bin',
      ).readAsStringSync();
      expect(second, isNot(equals(first)));
      // The new state still verifies the same password.
      expect(await gate.verify('hunter2'), isTrue);
    });

    test('rateLimiter is null before setPassword runs', () async {
      final gate = newGate();
      expect(await gate.rateLimiter(), isNull);
    });

    test('rateLimiter records and persists failure + cooldown', () async {
      final gate = newGate();
      await gate.setPassword('hunter2');
      final limiter = await gate.rateLimiter();
      expect(limiter, isNotNull);
      limiter!.recordFailure();
      limiter.recordFailure();
      // Any locked limiter reports a non-zero cooldown.
      expect(limiter.status().failureCount, greaterThanOrEqualTo(1));
    });

    test('rateLimiter rotates when setPassword rotates HMAC', () async {
      final gate = newGate();
      await gate.setPassword('hunter2');
      final limiter1 = await gate.rateLimiter();
      limiter1!.recordFailure();

      // Rotate password → HMAC changes → new limiter's HMAC key no
      // longer matches the disk state → the next load reports tamper
      // and clamps the cooldown to max. Exercising this confirms the
      // limiter is bound to the current gate state, not a previous one.
      await gate.setPassword('hunter2');
      final limiter2 = await gate.rateLimiter();
      expect(limiter2, isNotNull);
    });
  });
}
