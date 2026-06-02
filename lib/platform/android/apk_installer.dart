import 'package:flutter/services.dart';

import '../../utils/logger.dart';

/// Hands a downloaded, signature-verified update apk to the Android
/// system package installer over the `com.letsflutssh/apk_installer`
/// MethodChannel (implemented in `MainActivity.kt`).
///
/// Lives in `lib/platform/` because it's a plugin/MethodChannel adapter
/// — `lib/core/`'s `UpdateService` stays Flutter-free and receives
/// [install] as an injected callback from `updateServiceProvider`,
/// mirroring the macOS `.dmg` installer wiring.
class ApkInstaller {
  static const MethodChannel _channel = MethodChannel(
    'com.letsflutssh/apk_installer',
  );

  /// Launch the system installer for the apk at [path]. Returns `true`
  /// when the install UI opened (`"launched"`) or the one-time "install
  /// unknown apps" permission screen was shown (`"needsPermission"` —
  /// the user grants once, then re-triggers the update). Returns
  /// `false` on any platform error so the caller falls back to opening
  /// the release page.
  static Future<bool> install(String path) async {
    try {
      final result = await _channel.invokeMethod<String>('installApk', {
        'path': path,
      });
      return result == 'launched' || result == 'needsPermission';
    } on PlatformException catch (e) {
      AppLogger.instance.log(
        'APK install hand-off failed: ${e.code} ${e.message}',
        name: 'ApkInstaller',
        level: LogLevel.warn,
      );
      return false;
    }
  }
}
