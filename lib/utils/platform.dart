import 'dart:io';

/// Returns the user's home directory path.
/// Works on Linux, macOS (HOME) and Windows (USERPROFILE).
String get homeDirectory =>
    Platform.environment['HOME'] ??
    Platform.environment['USERPROFILE'] ??
    '';

/// True on Android or iOS.
bool get isMobilePlatform => Platform.isAndroid || Platform.isIOS;

/// True on Linux, macOS, or Windows.
bool get isDesktopPlatform => Platform.isLinux || Platform.isMacOS || Platform.isWindows;
