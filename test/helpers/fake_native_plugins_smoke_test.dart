import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/platform/qr_scanner.dart';

import 'fake_native_plugins.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Pin the fake_native_plugins.dart contract so a refactor that
  // accidentally drops a channel or renames a method gets caught
  // before any real test that relies on the fixture flakes.

  late NativeCallLog log;

  tearDown(uninstallFakeNativePlugins);

  test('qrscanner returns configured payload', () async {
    log = installFakeNativePlugins(
      config: FakeNativePluginsConfig(qrScanResult: 'ssh://user@host'),
    );
    expect(await scanQrCode(), 'ssh://user@host');
    expect(log.forChannel('com.letsflutssh/qrscanner').single.method, 'scan');
  });

  test('uninstall scrubs every handler', () async {
    installFakeNativePlugins();
    uninstallFakeNativePlugins();
    // After uninstall, invokeMethod throws MissingPluginException —
    // the same error the production code catches, so this verifies
    // that the teardown actually removes the mock rather than silently
    // keeping it registered.
    const channel = MethodChannel('com.letsflutssh/qrscanner');
    await expectLater(
      channel.invokeMethod<String>('scan'),
      throwsA(isA<MissingPluginException>()),
    );
  });
}
