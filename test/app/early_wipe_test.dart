import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/app/early_wipe.dart';
import 'package:path/path.dart' as p;

/// `earlyWipeAppSupportFiles` is the FRB-free fallback used by
/// `FatalErrorApp` when the bundled native blob itself is the broken
/// artefact and `WipeAllService.wipeAll()` (Rust-backed) cannot be
/// reached. This suite mocks `path_provider` to point at a temp dir
/// and pins that the catalogue covers every artefact the production
/// `lfs_core::security::wipe::MANAGED_FILES` declares — without that
/// invariant a future write under app-support would silently escape
/// the early-stage wipe and resurface as orphan state on the next
/// launch.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('early_wipe_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async {
            if (call.method == 'getApplicationSupportDirectory') {
              return tempDir.path;
            }
            return null;
          },
        );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  Future<void> seed(String name) async {
    final f = File(p.join(tempDir.path, name));
    await f.create(recursive: true);
    await f.writeAsString('seed');
  }

  test('removes every managed file under app-support', () async {
    // Each entry mirrors `lfs_core::security::wipe::MANAGED_FILES`
    // (plus `.wipe-pending`, the crash marker `WIPE_PENDING_MARKER`).
    // Add a new file here whenever the Rust catalogue grows.
    const managed = [
      '.tier-transition-pending',
      '.wipe-pending',
      'keychain_enabled',
      'rate_limit_state.bin',
      'hardware_vault_android_bio.bin',
      'hardware_vault_password_overlay_android.bin',
      'hardware_vault_password_overlay_apple.bin',
      'hardware_vault_password_overlay_windows.bin',
      'security_pass_hash.bin',
      'hardware_vault.bin',
      'hardware_vault_android.bin',
      'hardware_vault_apple.bin',
      'hardware_vault_ios.bin',
      'hardware_vault_macos.bin',
      'hardware_vault_windows.bin',
      'hardware_vault_linux.bin',
      'hardware_vault_salt.bin',
      'credentials.kdf',
      'credentials.verify',
      'credentials.key',
      'config.json',
      'migration_history.json',
      'letsflutssh.db',
      'letsflutssh.db-wal',
      'letsflutssh.db-shm',
      'letsflutssh.db-journal',
      'lfs_core.db',
      'lfs_core.db-wal',
      'lfs_core.db-shm',
      'lfs_core.db-journal',
    ];
    for (final name in managed) {
      await seed(name);
    }
    // Logs subdir.
    final logsDir = Directory(p.join(tempDir.path, 'logs'));
    await logsDir.create(recursive: true);
    await File(p.join(logsDir.path, 'letsflutssh.log')).writeAsString('log');

    await earlyWipeAppSupportFiles();

    for (final name in managed) {
      expect(
        File(p.join(tempDir.path, name)).existsSync(),
        isFalse,
        reason: '$name should have been deleted by earlyWipeAppSupportFiles',
      );
    }
    expect(logsDir.existsSync(), isFalse);
  });

  test('is a no-op on an empty support directory (no throw)', () async {
    await earlyWipeAppSupportFiles();
    expect(tempDir.existsSync(), isTrue);
  });

  test('partial wipe — survives a missing subset gracefully', () async {
    await seed('config.json');
    // Only one file present; the rest do not exist. The sweep must
    // not throw on the missing ones.
    await earlyWipeAppSupportFiles();
    expect(File(p.join(tempDir.path, 'config.json')).existsSync(), isFalse);
  });
}
