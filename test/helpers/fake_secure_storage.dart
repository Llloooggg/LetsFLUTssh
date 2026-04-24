import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Back the `flutter_secure_storage` plugin with an in-memory map for
/// the lifetime of a single test.
///
/// The real plugin hits the OS keychain / Credential Manager /
/// EncryptedSharedPreferences; in a test run that path throws
/// `MissingPluginException`, which propagates out of every
/// `SecureKeyStorage.readKey` call and kills the test before the
/// code under test has a chance to react.
///
/// Usage:
/// ```dart
/// late Map<String, String> fakeKeychain;
/// setUp(() { fakeKeychain = installFakeSecureStorage(); });
/// tearDown(uninstallFakeSecureStorage);
/// ```
///
/// The returned map is live — pre-seed or inspect keys from tests.
Map<String, String> installFakeSecureStorage() {
  final keychain = <String, String>{};
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
        (call) async {
          final args = (call.arguments as Map?)?.cast<String, Object?>() ?? {};
          switch (call.method) {
            case 'write':
              keychain[args['key'] as String] = args['value'] as String;
              return null;
            case 'read':
              return keychain[args['key']];
            case 'delete':
              keychain.remove(args['key']);
              return null;
            case 'containsKey':
              return keychain.containsKey(args['key']);
            case 'readAll':
              return Map<String, String>.from(keychain);
            case 'deleteAll':
              keychain.clear();
              return null;
          }
          return null;
        },
      );
  return keychain;
}

void uninstallFakeSecureStorage() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
        null,
      );
}
