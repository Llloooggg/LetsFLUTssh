import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/backup_exclusion.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.letsflutssh/backup_exclusion');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'invokes excludeFromBackup with the app-support path on Apple',
    () async {
      MethodCall? seen;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            seen = call;
            return true;
          });

      await BackupExclusion(
        channel: channel,
        isApplePlatform: true,
        supportDir: () async => Directory('/tmp/lfs-test-support'),
      ).applyOnStartup();

      expect(seen, isNotNull);
      expect(seen!.method, 'excludeFromBackup');
      expect((seen!.arguments as Map)['path'], '/tmp/lfs-test-support');
    },
  );

  test('is a no-op off Apple platforms', () async {
    var called = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          called = true;
          return true;
        });

    await BackupExclusion(
      channel: channel,
      isApplePlatform: false,
      supportDir: () async => Directory('/tmp/lfs-test-support'),
    ).applyOnStartup();

    expect(called, isFalse);
  });

  test('swallows native errors', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          throw PlatformException(code: 'EXCLUDE_FAILED');
        });

    await BackupExclusion(
      channel: channel,
      isApplePlatform: true,
      supportDir: () async => Directory('/tmp/lfs-test-support'),
    ).applyOnStartup();
  });
}
