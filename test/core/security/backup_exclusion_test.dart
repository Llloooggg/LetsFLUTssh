import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/backup_exclusion.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('invokes the exclude impl with the app-support path on Apple', () async {
    String? seenPath;
    await BackupExclusion(
      isApplePlatform: true,
      supportDir: () async => Directory('/tmp/lfs-test-support'),
      excludeImpl: (path) => seenPath = path,
    ).applyOnStartup();
    expect(seenPath, '/tmp/lfs-test-support');
  });

  test('is a no-op off Apple platforms', () async {
    var called = false;
    await BackupExclusion(
      isApplePlatform: false,
      supportDir: () async => Directory('/tmp/lfs-test-support'),
      excludeImpl: (_) => called = true,
    ).applyOnStartup();
    expect(called, isFalse);
  });

  test('swallows native errors', () async {
    // The startup path must never crash on a backup-exclusion failure
    // — the user gets a usable app even when the OS rejected the call.
    await BackupExclusion(
      isApplePlatform: true,
      supportDir: () async => Directory('/tmp/lfs-test-support'),
      excludeImpl: (_) => throw StateError('exclude failed'),
    ).applyOnStartup();
  });
}
