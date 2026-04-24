import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/qr/qr_scanner.dart';
import 'package:letsflutssh/utils/android_storage_permission.dart';

import 'fake_native_plugins.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Pin the fake_native_plugins.dart contract so a refactor that
  // accidentally drops a channel or renames a method gets caught
  // before any real test that relies on the fixture flakes.
  //
  // Each case flips one `FakeNativePluginsConfig` field and verifies
  // the corresponding Dart-side wrapper picks it up — the harness'
  // value add is that tests reading one dimension do not have to
  // hand-write the other six channels' handlers.

  late NativeCallLog log;

  tearDown(uninstallFakeNativePlugins);

  test('hardware_vault channel returns configured values', () async {
    // Hit the mocked channel directly — the Dart-side wrapper
    // `HardwareTierVault` picks `TpmClient` (not the channel) on a
    // Linux test host, so we validate the mock shape here and let
    // real per-platform integration tests cover the wrapper branch.
    log = installFakeNativePlugins(
      config: FakeNativePluginsConfig(
        hardwareVaultAvailable: true,
        hardwareVaultProbeDetail: 'androidStrongBoxAvailable',
      ),
    );
    const ch = MethodChannel('com.letsflutssh/hardware_vault');
    expect(await ch.invokeMethod<bool>('isAvailable'), isTrue);
    expect(
      await ch.invokeMethod<String>('probeDetail'),
      'androidStrongBoxAvailable',
    );
    expect(
      log.forChannel('com.letsflutssh/hardware_vault').map((c) => c.method),
      ['isAvailable', 'probeDetail'],
    );
  });

  test('hardware_vault store then read round-trips via the mock', () async {
    log = installFakeNativePlugins(
      config: FakeNativePluginsConfig(hardwareVaultAvailable: true),
    );
    const ch = MethodChannel('com.letsflutssh/hardware_vault');
    expect(await ch.invokeMethod<bool>('isStored'), isFalse);
    final stored = await ch.invokeMethod<bool>('store', <String, Object>{
      'dbKey': Uint8List.fromList(const [1, 2, 3, 4]),
      'pinHmac': Uint8List(32),
    });
    expect(stored, isTrue);
    expect(await ch.invokeMethod<bool>('isStored'), isTrue);
    final read = await ch.invokeMethod<Uint8List>('read', <String, Object>{
      'pinHmac': Uint8List(32),
    });
    expect(read, equals(Uint8List.fromList(const [1, 2, 3, 4])));
  });

  test('permissions.requestStoragePermission honours config flag', () async {
    log = installFakeNativePlugins(
      config: FakeNativePluginsConfig(storagePermissionGranted: false),
    );
    // On non-Android hosts the Dart-side wrapper short-circuits to
    // `true` without ever touching the channel. Pin that path here —
    // on Android the call lands on the mocked handler and returns
    // `false` matching the config, but we cannot fake `Platform.is*`
    // in-process, so the Linux-host expected value is `true`.
    expect(await requestAndroidStoragePermission(), isTrue);
    expect(log.forChannel('com.letsflutssh/permissions'), isEmpty);
  });

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
    const channel = MethodChannel('com.letsflutssh/hardware_vault');
    await expectLater(
      channel.invokeMethod<bool>('isAvailable'),
      throwsA(isA<MissingPluginException>()),
    );
  });
}
