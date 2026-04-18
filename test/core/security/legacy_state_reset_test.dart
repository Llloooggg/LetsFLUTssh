import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/legacy_state_reset.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late LegacyStateReset reset;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('legacy_reset_test_');
    reset = LegacyStateReset(
      supportDirFactory: () async => tempDir,
      purgeKeychain: false, // no native channel in pure-VM tests
    );
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('LegacyStateReset.hasLegacyState', () {
    test('returns false on a clean support dir', () async {
      expect(await reset.hasLegacyState(), isFalse);
    });

    test('returns true when credentials.kdf is present', () async {
      File('${tempDir.path}/credentials.kdf').writeAsStringSync('stub');
      expect(await reset.hasLegacyState(), isTrue);
    });

    test('returns true when DB file is present', () async {
      File('${tempDir.path}/letsflutssh.db').writeAsStringSync('stub');
      expect(await reset.hasLegacyState(), isTrue);
    });

    test('returns true when only a Linux keychain marker is present', () async {
      File('${tempDir.path}/keychain_enabled').writeAsStringSync('1');
      expect(await reset.hasLegacyState(), isTrue);
    });
  });

  group('LegacyStateReset.wipe', () {
    test('deletes every legacy file + DB + sidecars', () async {
      final files = [
        'credentials.kdf',
        'credentials.salt',
        'credentials.verify',
        'credentials.key',
        'keychain_enabled',
        'biometric_vault.tpm',
        'rate_limit_state.bin',
        'letsflutssh.db',
        'letsflutssh.db-wal',
        'letsflutssh.db-shm',
      ];
      for (final n in files) {
        File('${tempDir.path}/$n').writeAsStringSync('stub');
      }
      await reset.wipe();
      for (final n in files) {
        expect(
          File('${tempDir.path}/$n').existsSync(),
          isFalse,
          reason: 'expected $n to be deleted',
        );
      }
      expect(await reset.hasLegacyState(), isFalse);
    });

    test('wipe on a clean dir is a no-op and does not throw', () async {
      await reset.wipe();
      expect(await reset.hasLegacyState(), isFalse);
    });

    test('unrelated files are preserved', () async {
      File('${tempDir.path}/config.json').writeAsStringSync('{}');
      File('${tempDir.path}/logs/letsflutssh.log').createSync(recursive: true);
      File('${tempDir.path}/credentials.kdf').writeAsStringSync('stub');
      await reset.wipe();
      expect(File('${tempDir.path}/config.json').existsSync(), isTrue);
      expect(File('${tempDir.path}/logs/letsflutssh.log').existsSync(), isTrue);
      expect(File('${tempDir.path}/credentials.kdf').existsSync(), isFalse);
    });
  });
}
