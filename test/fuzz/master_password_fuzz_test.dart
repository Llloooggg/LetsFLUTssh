import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/master_password.dart';

/// Fuzz tests for MasterPasswordManager — verify that malformed
/// `credentials.kdf` / `credentials.verify` files never cause
/// unhandled exceptions (crashes).
void main() {
  late Directory tempDir;
  late MasterPasswordManager manager;
  final random = Random(42); // fixed seed for reproducibility

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('master_pw_fuzz_');
    manager = MasterPasswordManager(basePath: tempDir.path);
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  /// Generate random bytes of the given length.
  Uint8List randomBytes(int length) {
    return Uint8List.fromList(
      List.generate(length, (_) => random.nextInt(256)),
    );
  }

  group('MasterPasswordManager fuzz — malformed kdf record', () {
    for (final length in [0, 1, 5, 16, 31, 32, 33, 64, 128, 256]) {
      test('kdf length $length does not crash verify', () async {
        await File(
          '${tempDir.path}/credentials.kdf',
        ).writeAsBytes(randomBytes(length));
        await File(
          '${tempDir.path}/credentials.verify',
        ).writeAsBytes(randomBytes(64));

        // Should return false (bad data) or throw
        // MasterPasswordException / FormatException, but never an
        // unhandled exception.
        try {
          final result = await manager.verify('anypassword');
          expect(result, isFalse);
        } on MasterPasswordException {
          // acceptable
        } on FormatException {
          // acceptable — bad magic / truncated header
        }
      });
    }
  });

  group('MasterPasswordManager fuzz — malformed verifier', () {
    for (final length in [0, 1, 5, 11, 12, 13, 16, 32, 64]) {
      test('verifier length $length does not crash verify', () async {
        await File(
          '${tempDir.path}/credentials.kdf',
        ).writeAsBytes(randomBytes(64));
        await File(
          '${tempDir.path}/credentials.verify',
        ).writeAsBytes(randomBytes(length));

        try {
          final result = await manager.verify('anypassword');
          expect(result, isFalse);
        } on MasterPasswordException {
          // acceptable
        } on FormatException {
          // acceptable
        }
      });
    }
  });

  group('MasterPasswordManager fuzz — random password strings', () {
    test(
      'random passwords do not crash enable/verify cycle',
      timeout: const Timeout(Duration(seconds: 60)),
      () async {
        for (var i = 0; i < 3; i++) {
          final length = random.nextInt(100) + 1;
          final password = String.fromCharCodes(
            List.generate(length, (_) => random.nextInt(0x10000)),
          );

          // Clean up for each iteration.
          final kdf = File('${tempDir.path}/credentials.kdf');
          final verify = File('${tempDir.path}/credentials.verify');
          if (await kdf.exists()) await kdf.delete();
          if (await verify.exists()) await verify.delete();

          final freshManager = MasterPasswordManager(basePath: tempDir.path);

          try {
            await freshManager.enable(password);
            final result = await freshManager.verify(password);
            expect(result, isTrue, reason: 'Password at iteration $i');
          } on MasterPasswordException {
            // acceptable for weird inputs
          }
        }
      },
    );
  });

  group('MasterPasswordManager fuzz — empty/missing files', () {
    test('empty kdf file does not crash', () async {
      await File('${tempDir.path}/credentials.kdf').writeAsBytes([]);
      await File(
        '${tempDir.path}/credentials.verify',
      ).writeAsBytes(randomBytes(32));

      try {
        await manager.verify('test');
      } on MasterPasswordException {
        // acceptable
      } on FormatException {
        // acceptable
      }
    });

    test('empty verifier file does not crash', () async {
      await File(
        '${tempDir.path}/credentials.kdf',
      ).writeAsBytes(randomBytes(64));
      await File('${tempDir.path}/credentials.verify').writeAsBytes([]);

      try {
        final result = await manager.verify('test');
        expect(result, isFalse);
      } on MasterPasswordException {
        // acceptable
      } on FormatException {
        // acceptable
      }
    });

    test('kdf with bad magic throws without stalling', () async {
      // All-zero bytes guarantee bad magic → FormatException immediately,
      // no Argon2id spin-up on random parameter fields.
      await File('${tempDir.path}/credentials.kdf').writeAsBytes(Uint8List(64));

      Object? caught;
      try {
        await manager.verify('test');
      } catch (e) {
        caught = e;
      }
      expect(
        caught,
        anyOf(isA<MasterPasswordException>(), isA<FormatException>()),
      );
    });
  });
}
