import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;

/// Returns the user's home directory path.
/// Desktop: HOME (Linux/macOS) or USERPROFILE (Windows).
/// Android: EXTERNAL_STORAGE or /storage/emulated/0 (shared internal storage).
/// iOS: app sandbox (HOME).
String get homeDirectory {
  if (Platform.isAndroid) {
    return Platform.environment['EXTERNAL_STORAGE'] ?? '/storage/emulated/0';
  }
  return Platform.environment['HOME'] ??
      Platform.environment['USERPROFILE'] ??
      '';
}

/// Override for testing — when non-null, [isMobilePlatform] returns this value.
@visibleForTesting
bool? debugMobilePlatformOverride;

/// Override for testing — when non-null, [isDesktopPlatform] returns this value.
@visibleForTesting
bool? debugDesktopPlatformOverride;

/// True on Android or iOS.
bool get isMobilePlatform =>
    debugMobilePlatformOverride ?? (Platform.isAndroid || Platform.isIOS);

/// True on Linux, macOS, or Windows.
bool get isDesktopPlatform =>
    debugDesktopPlatformOverride ?? (Platform.isLinux || Platform.isMacOS || Platform.isWindows);
