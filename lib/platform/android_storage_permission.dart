import 'dart:io' show Platform;

import 'package:flutter/services.dart';

import '../utils/logger.dart';

/// Method channel backing the Android broad-storage-access flow
/// (`MANAGE_EXTERNAL_STORAGE` on 11+, runtime `READ_EXTERNAL_STORAGE`
/// below). Exposed so tests can install a mock handler without the
/// production code branching on `Platform.isAndroid`.
const androidStoragePermissionChannel = MethodChannel(
  'com.letsflutssh/permissions',
);

/// Request broad storage access (`MANAGE_EXTERNAL_STORAGE` / pre-11
/// runtime permission) via the native channel.
///
/// Returns `true` when the app holds full-filesystem access after the
/// call, `false` otherwise. On non-Android platforms it is a no-op
/// returning `true` — callers read the result as "can write anywhere"
/// without a platform guard.
///
/// Lives in `platform/` (not a UI module) so settings, the file
/// browser, and transfer code reuse the same flow.
Future<bool> requestAndroidStoragePermission() async {
  if (!Platform.isAndroid) return true;
  try {
    final granted = await androidStoragePermissionChannel.invokeMethod<bool>(
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
      error: e,
    );
    return false;
  }
}

/// Probe whether broad storage access is already held, without
/// prompting. Drives the "grant access" banner so it only shows when
/// the grant is actually missing. Non-Android → `true` (no banner).
Future<bool> hasAndroidStoragePermission() async {
  if (!Platform.isAndroid) return true;
  try {
    final has = await androidStoragePermissionChannel.invokeMethod<bool>(
      'hasStoragePermission',
    );
    return has ?? false;
  } catch (e) {
    AppLogger.instance.log(
      'Storage permission probe failed: $e',
      name: 'Permission',
      error: e,
    );
    return false;
  }
}
