import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../utils/logger.dart';

/// Breaking-change reset helper for the new tier model.
///
/// The old model (pre-tier: plaintext / keychain / masterPassword)
/// inferred tier from file presence. The new model persists an
/// explicit `security_tier` field inside `config.json`. Users on the
/// new app binary who still have old-world files without that field
/// must acknowledge a wipe — we are not writing an automatic
/// migration path. This helper detects the condition and performs
/// the wipe.
class LegacyStateReset {
  /// Files that belonged to the pre-tier security model. Every one of
  /// them is deleted by [wipe] after the user confirms the reset.
  static const _legacySecurityFiles = [
    'credentials.kdf', // new Argon2id salt file
    'credentials.salt', // pre-Argon2id PBKDF2 salt
    'credentials.verify', // encrypted known plaintext
    'credentials.key', // key file for legacy keychain mode
    'keychain_enabled', // Linux opt-in marker
    'biometric_vault.tpm', // Linux TPM-sealed biometric vault
    'rate_limit_state.bin', // persisted rate-limit counter (future)
  ];

  /// Files for the encrypted database + its SQLite sidecars.
  static const _dbFiles = [
    'letsflutssh.db',
    'letsflutssh.db-wal',
    'letsflutssh.db-shm',
    'letsflutssh.db-journal',
  ];

  /// Resolver for the app-support directory. Overridable in tests so
  /// the code under test does not have to talk to `path_provider`.
  final Future<Directory> Function() _supportDir;

  /// When non-null, [wipe] also purges OS secure-storage entries.
  /// Tests disable it to avoid a real keychain round-trip.
  final bool _purgeKeychain;

  LegacyStateReset({
    Future<Directory> Function()? supportDirFactory,
    bool purgeKeychain = true,
  }) : _supportDir = supportDirFactory ?? getApplicationSupportDirectory,
       _purgeKeychain = purgeKeychain;

  /// True when *any* legacy-era file lives in the app-support dir.
  /// Caller must check `appConfig.security == null` on top of this —
  /// together those two predicates trigger the reset dialog.
  Future<bool> hasLegacyState() async {
    try {
      final dir = await _supportDir();
      for (final name in [..._legacySecurityFiles, ..._dbFiles]) {
        if (await File(p.join(dir.path, name)).exists()) return true;
      }
      return false;
    } catch (e) {
      AppLogger.instance.log(
        'LegacyStateReset.hasLegacyState probe failed: $e',
        name: 'LegacyStateReset',
      );
      return false;
    }
  }

  /// Unconditionally wipe every legacy file and the encrypted DB.
  ///
  /// Best-effort per file: a single delete failure is logged and
  /// skipped so one stuck file never prevents the user from
  /// re-entering the wizard. The keychain is also purged via
  /// [FlutterSecureStorage.deleteAll] so any key left in the OS
  /// keychain by the old code path cannot re-decrypt a freshly-made
  /// DB in the new one.
  Future<void> wipe() async {
    final dir = await _supportDir();

    for (final name in [..._legacySecurityFiles, ..._dbFiles]) {
      final file = File(p.join(dir.path, name));
      try {
        if (await file.exists()) {
          await file.delete();
          AppLogger.instance.log(
            'LegacyStateReset: deleted $name',
            name: 'LegacyStateReset',
          );
        }
      } catch (e) {
        AppLogger.instance.log(
          'LegacyStateReset: failed to delete $name: $e',
          name: 'LegacyStateReset',
        );
      }
    }

    if (!_purgeKeychain) return;

    // Purge keychain / OS secure-storage entries. The new tier
    // switcher will re-create them with fresh keys on the user's
    // post-wizard selection, so we must not leave any residue the
    // new code could accidentally read.
    try {
      const storage = FlutterSecureStorage();
      await storage.deleteAll();
      AppLogger.instance.log(
        'LegacyStateReset: OS secure storage cleared',
        name: 'LegacyStateReset',
      );
    } catch (e) {
      // Not fatal — if the keychain is unreachable (common on
      // Linux / WSL in test environments), nothing was stored there
      // by the old code either.
      AppLogger.instance.log(
        'LegacyStateReset: keychain wipe skipped: $e',
        name: 'LegacyStateReset',
      );
    }
  }
}
