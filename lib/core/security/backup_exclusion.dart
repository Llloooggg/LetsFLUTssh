import 'dart:io' show Directory, Platform;

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../utils/logger.dart';

/// Opt the app-support directory out of Apple's backup paths.
///
/// On iOS the application sandbox is indexed by iCloud Backup and by
/// encrypted iTunes/Finder backups by default. On macOS the same path
/// (`~/Library/Application Support/<bundle_id>`) is picked up by Time
/// Machine. Either of those turns the encrypted SQLite file, the KDF
/// parameters, the hardware-vault blob, and the password rate-limiter
/// journal into long-lived copies outside the device's trusted boot
/// chain — a restored backup on an attacker-controlled device gives
/// them offline brute-force time against the master password without
/// the per-device hardware binding the live install would have.
///
/// Both platforms honour the same API: setting
/// `URLResourceKey.isExcludedFromBackupKey` on a directory URL. On iOS
/// this maps to the `NSURLIsExcludedFromBackupKey` attribute (skipped
/// by iCloud + iTunes backup). On macOS the same resource-value call
/// writes the `com.apple.metadata:com_apple_backup_excludeItem`
/// extended attribute, which Time Machine honours.
///
/// Applied once on startup — idempotent, so re-running is cheap and
/// will refresh the flag if a system process stripped the xattr.
///
/// No-op on Android / Linux / Windows. Android's auto-backup exclusion
/// is handled at the manifest level via `data_extraction_rules.xml`;
/// Linux and Windows have no OS-level cloud-backup default the app
/// needs to opt out of.
class BackupExclusion {
  BackupExclusion({
    MethodChannel? channel,
    bool? isApplePlatform,
    Future<Directory> Function()? supportDir,
  }) : _channel = channel ?? const MethodChannel(_channelName),
       _isApplePlatform =
           isApplePlatform ?? (Platform.isIOS || Platform.isMacOS),
       _supportDir = supportDir ?? getApplicationSupportDirectory;

  static const _channelName = 'com.letsflutssh/backup_exclusion';

  final MethodChannel _channel;
  final bool _isApplePlatform;
  final Future<Directory> Function() _supportDir;

  /// Flag the app-support directory so Apple backup paths skip it.
  /// Resolves to a no-op on non-Apple platforms.
  Future<void> applyOnStartup() async {
    if (!_isApplePlatform) return;
    try {
      final dir = await _supportDir();
      await _channel.invokeMethod<void>('excludeFromBackup', {
        'path': dir.path,
      });
    } catch (e) {
      AppLogger.instance.log(
        'BackupExclusion.applyOnStartup failed: $e',
        name: 'BackupExclusion',
      );
    }
  }
}
