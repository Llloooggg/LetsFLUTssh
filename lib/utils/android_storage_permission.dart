import 'dart:io' show Platform;

import 'package:flutter/services.dart';

import 'logger.dart';

/// Request `MANAGE_EXTERNAL_STORAGE` (or the pre-11 equivalent) via the
/// native MethodChannel that backs the file-browser permission flow.
///
/// Returns `true` when the app has full Downloads write access after the
/// call, `false` otherwise.  On non-Android platforms the function is a
/// no-op returning `true` — callers can use the result as "can write
/// anywhere" without a platform guard.
///
/// Kept here (not inside `features/file_browser/`) so settings and
/// transfer code can reuse the same flow without importing a UI module.
Future<bool> requestAndroidStoragePermission() async {
  if (!Platform.isAndroid) return true;
  try {
    const channel = MethodChannel('com.letsflutssh/permissions');
    final granted = await channel.invokeMethod<bool>(
      'requestStoragePermission',
    );
    if (granted != true) {
      AppLogger.instance.log(
        'Storage permission denied by user',
        name: 'Permission',
      );
      return false;
    }
    return true;
  } catch (e) {
    AppLogger.instance.log(
      'Storage permission request failed: $e',
      name: 'Permission',
    );
    return false;
  }
}
