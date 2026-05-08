import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Best-effort, FRB-free wipe of every file the app manages under
/// app-support. Used by [FatalErrorApp] when the bootstrap chain
/// stops before `_initRustCoreOrFatal` has loaded the Rust core, so
/// `WipeAllService.wipeAll()` (which routes through FRB) is not yet
/// reachable. Mirror of `lfs_core::security::wipe::MANAGED_FILES` —
/// keep both lists in sync; the Rust-side test
/// `wipe_managed_files_covers_known_writers` also pins the catalogue
/// from the production-side, so a write that lands a new file under
/// app-support will fail there first.
///
/// Keychain / hardware-vault / Apple SE artefacts are NOT covered
/// here because those routes need FRB. Any leftover OS-secure-storage
/// entries surface on the next launch as orphan state, which
/// `_handleLegacyStateIfPresent` catches and offers a tier-reset
/// dialog for. Net effect: a user who hits this path lands in a
/// clean fresh-install state on the second cold start.
Future<void> earlyWipeAppSupportFiles() async {
  try {
    final dir = await getApplicationSupportDirectory();
    const files = <String>[
      // Markers / transient state.
      '.tier-transition-pending',
      '.wipe-pending',
      'keychain_enabled',
      'rate_limit_state.bin',
      // Biometric / hw overlay blobs.
      'hardware_vault_android_bio.bin',
      'hardware_vault_password_overlay_android.bin',
      'hardware_vault_password_overlay_apple.bin',
      'hardware_vault_password_overlay_windows.bin',
      // Password gate.
      'security_pass_hash.bin',
      // Hardware vault primary blobs — one per platform.
      'hardware_vault.bin',
      'hardware_vault_android.bin',
      'hardware_vault_apple.bin',
      'hardware_vault_ios.bin',
      'hardware_vault_macos.bin',
      'hardware_vault_windows.bin',
      'hardware_vault_linux.bin',
      'hardware_vault_salt.bin',
      // KDF descriptors + verifier + key.
      'credentials.kdf',
      'credentials.verify',
      'credentials.key',
      // Config.
      'config.json',
      // Migration framework state.
      'migration_history.json',
      // Drift DB + SQLite sidecars.
      'letsflutssh.db',
      'letsflutssh.db-wal',
      'letsflutssh.db-shm',
      'letsflutssh.db-journal',
      // Legacy DB filename — installs that touched the early-Rust-port
      // window have an orphan at this name.
      'lfs_core.db',
      'lfs_core.db-wal',
      'lfs_core.db-shm',
      'lfs_core.db-journal',
    ];
    for (final name in files) {
      final f = File(p.join(dir.path, name));
      if (await f.exists()) {
        try {
          await f.delete();
        } catch (_) {
          // Best-effort — partial wipe is better than no wipe.
        }
      }
    }
    final logsDir = Directory(p.join(dir.path, 'logs'));
    if (await logsDir.exists()) {
      try {
        await logsDir.delete(recursive: true);
      } catch (_) {
        // Best-effort — log dir contention is rare here because the
        // logger sink may be holding a handle, but the file is set
        // up for `FileMode.append` not exclusive lock.
      }
    }
  } catch (_) {
    // path_provider unreachable — nothing to do.
  }
}
