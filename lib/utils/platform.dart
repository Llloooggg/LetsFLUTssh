import 'dart:io';

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

/// True on Android or iOS.
bool get isMobilePlatform => Platform.isAndroid || Platform.isIOS;

/// True on Linux, macOS, or Windows.
bool get isDesktopPlatform => Platform.isLinux || Platform.isMacOS || Platform.isWindows;
