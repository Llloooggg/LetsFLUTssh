import 'dart:io';

/// Returns the user's home directory path.
/// Works on Linux, macOS (HOME) and Windows (USERPROFILE).
String get homeDirectory =>
    Platform.environment['HOME'] ??
    Platform.environment['USERPROFILE'] ??
    '';
