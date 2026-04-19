import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/wipe_all_service.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late WipeAllService service;
  late List<String> nativeCalls;
  late MethodChannel channel;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('wipe_all_test_');
    nativeCalls = <String>[];
    channel = const MethodChannel('com.letsflutssh/hardware_vault');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          nativeCalls.add(call.method);
          return true;
        });
    service = WipeAllService(
      supportDirFactory: () async => tempDir,
      hardwareVaultChannel: channel,
      purgeKeychain: false,
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  void touch(String name, [String content = 'x']) {
    File(p.join(tempDir.path, name)).writeAsStringSync(content);
  }

  group('WipeAllService.hasAnyState', () {
    test('returns false on an empty app-support dir', () async {
      expect(await service.hasAnyState(), isFalse);
    });

    test('returns true when the encrypted DB exists', () async {
      touch('letsflutssh.db');
      expect(await service.hasAnyState(), isTrue);
    });

    test('returns true when a hw vault blob exists', () async {
      touch('hardware_vault_android.bin');
      expect(await service.hasAnyState(), isTrue);
    });

    test('returns true when only the biometric overlay is present', () async {
      touch('hardware_vault_password_overlay_apple.bin');
      expect(await service.hasAnyState(), isTrue);
    });

    test('returns true when legacy pre-tier files remain', () async {
      touch('credentials.kdf');
      expect(await service.hasAnyState(), isTrue);
    });
  });

  group('WipeAllService.hasPendingWipe', () {
    test('returns false when no marker is on disk', () async {
      expect(await service.hasPendingWipe(), isFalse);
    });

    test('returns true when a .wipe-pending marker is present', () async {
      touch('.wipe-pending', 'timestamp\n');
      expect(await service.hasPendingWipe(), isTrue);
    });
  });

  group('WipeAllService.wipeAll', () {
    test(
      'deletes every managed file that exists, tolerates missing ones',
      () async {
        for (final name in const [
          'config.json',
          'credentials.kdf',
          'letsflutssh.db',
          'letsflutssh.db-wal',
          'security_pass_hash.bin',
          'hardware_vault_android.bin',
          'hardware_vault_password_overlay_android.bin',
          'hardware_vault_salt.bin',
        ]) {
          touch(name);
        }

        final report = await service.wipeAll();
        expect(report.hasFailures, isFalse);
        expect(report.deletedFiles, hasLength(8));
        for (final name in const [
          'config.json',
          'credentials.kdf',
          'letsflutssh.db',
          'letsflutssh.db-wal',
          'security_pass_hash.bin',
          'hardware_vault_android.bin',
          'hardware_vault_password_overlay_android.bin',
          'hardware_vault_salt.bin',
        ]) {
          expect(
            File(p.join(tempDir.path, name)).existsSync(),
            isFalse,
            reason: '$name should have been deleted',
          );
        }
      },
    );

    test(
      'invokes native clear + clearBiometricPassword on the hw-vault channel',
      () async {
        await service.wipeAll();
        expect(nativeCalls, containsAll(['clear', 'clearBiometricPassword']));
      },
    );

    test(
      'writes the pending marker before starting and clears it on success',
      () async {
        // Stub the native channel to set an observable side-effect so we
        // can assert the marker existed at the mid-point of the wipe.
        final marker = File(p.join(tempDir.path, '.wipe-pending'));
        bool markerExistedDuringWipe = false;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              markerExistedDuringWipe =
                  markerExistedDuringWipe || marker.existsSync();
              return true;
            });
        await service.wipeAll();
        expect(
          markerExistedDuringWipe,
          isTrue,
          reason: 'marker must be present during native channel calls',
        );
        expect(
          marker.existsSync(),
          isFalse,
          reason: 'marker must be cleared after success',
        );
      },
    );

    test('resumes idempotently from a leftover marker', () async {
      touch('.wipe-pending', 'stale');
      touch('letsflutssh.db');
      expect(await service.hasPendingWipe(), isTrue);
      await service.wipeAll();
      expect(await service.hasPendingWipe(), isFalse);
      expect(
        File(p.join(tempDir.path, 'letsflutssh.db')).existsSync(),
        isFalse,
      );
    });

    test('logs directory is wiped alongside managed files', () async {
      final logsDir = Directory(p.join(tempDir.path, 'logs'));
      logsDir.createSync();
      File(p.join(logsDir.path, 'letsflutssh.log')).writeAsStringSync('x');
      File(p.join(logsDir.path, 'letsflutssh.log.1')).writeAsStringSync('x');
      await service.wipeAll();
      expect(logsDir.listSync(), isEmpty);
    });

    test(
      'missing native plugin surfaces as nativeVaultCleared=false but does not throw',
      () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (_) async {
              throw PlatformException(code: 'NO_PLUGIN');
            });
        final report = await service.wipeAll();
        expect(report.nativeVaultCleared, isFalse);
        expect(report.biometricOverlayCleared, isFalse);
        expect(report.hasFailures, isFalse);
      },
    );
  });
}
