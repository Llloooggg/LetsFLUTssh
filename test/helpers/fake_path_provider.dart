import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Redirects `getApplicationSupportDirectory()` (and siblings) to a
/// fresh `Directory.systemTemp.createTempSync(...)` for the lifetime
/// of a single test.
///
/// Many core modules (`AppLogger`, `ConfigStore`, `KeychainPasswordGate`,
/// `KdfArtefact`, drift's `openDatabase`) resolve the app-support
/// directory through the path_provider plugin. In a plain test run
/// that call returns `MissingPluginException`; every security / DB
/// path is unreachable until the channel is stubbed out.
///
/// Usage:
/// ```dart
/// late Directory tmp;
/// setUp(() => tmp = installFakePathProvider());
/// tearDown(() => uninstallFakePathProvider(tmp));
/// ```
///
/// Returns the temp directory so the caller can inspect written
/// files / pre-seed state before the code under test runs.
Directory installFakePathProvider() {
  final tmp = Directory.systemTemp.createTempSync('lfs_path_provider_');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async {
          switch (call.method) {
            case 'getApplicationSupportDirectory':
            case 'getApplicationDocumentsDirectory':
            case 'getTemporaryDirectory':
            case 'getLibraryDirectory':
              return tmp.path;
          }
          return null;
        },
      );
  return tmp;
}

/// Tear down the path_provider channel mock and delete the tmp
/// directory seeded by [installFakePathProvider].
void uninstallFakePathProvider(Directory tmp) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        null,
      );
  if (tmp.existsSync()) tmp.deleteSync(recursive: true);
}
