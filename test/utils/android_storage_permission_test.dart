/// Coverage for [requestAndroidStoragePermission].
///
/// On non-Android platforms (Linux / macOS / Windows / iOS) the
/// helper short-circuits to `true` without touching the
/// `com.letsflutssh/permissions` MethodChannel — callers can use
/// the result as "this platform can write anywhere" without a
/// per-call platform guard. The Android branch is exercised
/// through real-device QA (the system permission dialog cannot be
/// driven from a unit test).
library;

import 'dart:io' show Platform;

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/utils/android_storage_permission.dart';

void main() {
  group('requestAndroidStoragePermission', () {
    test(
      'returns true on non-Android platforms without channel call',
      () async {
        if (Platform.isAndroid) {
          // The Android branch invokes a MethodChannel that has no
          // mock in unit-test context — skip and let device QA
          // exercise it.
          markTestSkipped('Android channel branch — device QA only');
          return;
        }
        // The early `if (!Platform.isAndroid) return true;` guard
        // means callers can use this helper as "can write anywhere"
        // without a per-call platform check.
        expect(await requestAndroidStoragePermission(), isTrue);
      },
    );
  });
}
