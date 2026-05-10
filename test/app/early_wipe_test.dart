import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/app/early_wipe.dart';
import 'package:path/path.dart' as p;

/// `earlyWipeAppSupportFiles` is the FRB-free fallback used by
/// `FatalErrorApp` when the bundled native blob itself is broken and
/// `WipeAllService.wipeAll()` (Rust-backed) cannot reach the disk.
/// The function deletes every immediate child of the app-support
/// directory — files and subdirectories — keeping the parent
/// directory intact so `path_provider` caches and any post-restart
/// logic see a familiar empty home. The catalogue lives Rust-side
/// (`lfs_core::security::wipe::MANAGED_FILES`); the Dart fallback
/// stays drift-proof by sweeping by enumeration rather than against a
/// hardcoded list.
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

  test('removes every file under app-support', () async {
    // The sweep is by enumeration, not by name — any file the app
    // writes under app-support is covered. The seed list below mirrors
    // a representative subset of `lfs_core::security::wipe::MANAGED_FILES`
    // plus the `.wipe-pending` crash marker (`WIPE_PENDING_MARKER`)
    // and a never-seen `future_artefact.bin` to pin the drift-proof
    // property: a future Rust artefact lands without any Dart edit.
    const seeded = [
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
      // Drift-proof guard: an artefact the Rust catalogue does not yet
      // know about must still be wiped on this path.
      'future_artefact.bin',
    ];
    for (final name in seeded) {
      await seed(name);
    }
    // Logs subdir.
    final logsDir = Directory(p.join(tempDir.path, 'logs'));
    await logsDir.create(recursive: true);
    await File(p.join(logsDir.path, 'letsflutssh.log')).writeAsString('log');

    await earlyWipeAppSupportFiles();

    for (final name in seeded) {
      expect(
        File(p.join(tempDir.path, name)).existsSync(),
        isFalse,
        reason: '$name should have been deleted by earlyWipeAppSupportFiles',
      );
    }
    expect(logsDir.existsSync(), isFalse);
    expect(
      tempDir.existsSync(),
      isTrue,
      reason:
          'the parent directory must survive so path_provider caches '
          'and post-wipe restart code keep their handles',
    );
  });

  test('is a no-op on an empty support directory (no throw)', () async {
    await earlyWipeAppSupportFiles();
    expect(tempDir.existsSync(), isTrue);
  });

  test('partial wipe — survives a missing subset gracefully', () async {
    await seed('config.json');
    // Only one file present; iteration handles the lone child and
    // does not throw on the (non-existent) others.
    await earlyWipeAppSupportFiles();
    expect(File(p.join(tempDir.path, 'config.json')).existsSync(), isFalse);
  });
}
