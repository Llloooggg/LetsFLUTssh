import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/master_password.dart';

/// Fuzz tests for MasterPasswordManager — verify that malformed salt/verifier
/// files never cause unhandled exceptions (crashes).
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

  group('MasterPasswordManager fuzz — malformed salt', () {
    for (final length in [0, 1, 5, 16, 31, 32, 33, 64, 128, 256]) {
      test('salt length $length does not crash verify', () async {
        await File(
          '${tempDir.path}/credentials.salt',
        ).writeAsBytes(randomBytes(length));
        // Create a valid-looking verifier (may or may not decrypt).
        await File(
          '${tempDir.path}/credentials.verify',
        ).writeAsBytes(randomBytes(64));

        // Should return false (bad data) or throw MasterPasswordException,
        // but never an unhandled exception.
        try {
          final result = await manager.verify('anypassword');
          expect(result, isFalse);
        } on MasterPasswordException {
          // acceptable
        }
      });
    }
  });

  group('MasterPasswordManager fuzz — malformed verifier', () {
    for (final length in [0, 1, 5, 11, 12, 13, 16, 32, 64]) {
      test('verifier length $length does not crash verify', () async {
        // Valid-length salt.
        await File(
          '${tempDir.path}/credentials.salt',
        ).writeAsBytes(randomBytes(32));
        await File(
          '${tempDir.path}/credentials.verify',
        ).writeAsBytes(randomBytes(length));

        try {
          final result = await manager.verify('anypassword');
          expect(result, isFalse);
        } on MasterPasswordException {
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
          final salt = File('${tempDir.path}/credentials.salt');
          final verify = File('${tempDir.path}/credentials.verify');
          if (await salt.exists()) await salt.delete();
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
    test('empty salt file does not crash', () async {
      await File('${tempDir.path}/credentials.salt').writeAsBytes([]);
      await File(
        '${tempDir.path}/credentials.verify',
      ).writeAsBytes(randomBytes(32));

      try {
        await manager.verify('test');
      } on MasterPasswordException {
        // acceptable
      }
    });

    test('empty verifier file does not crash', () async {
      await File(
        '${tempDir.path}/credentials.salt',
      ).writeAsBytes(randomBytes(32));
      await File('${tempDir.path}/credentials.verify').writeAsBytes([]);

      try {
        final result = await manager.verify('test');
        expect(result, isFalse);
      } on MasterPasswordException {
        // acceptable
      }
    });

    test('salt exists but verifier missing does not crash', () async {
      await File(
        '${tempDir.path}/credentials.salt',
      ).writeAsBytes(randomBytes(32));

      expect(
        () => manager.verify('test'),
        throwsA(isA<MasterPasswordException>()),
      );
    });
  });
}
