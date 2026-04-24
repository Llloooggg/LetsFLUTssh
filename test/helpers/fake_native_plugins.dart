import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Captures every `invokeMethod` call across every mocked channel.
/// Tests assert on shape ("was `setSecure` called with secure:true?")
/// without having to swap handlers mid-flight.
class NativeCallLog {
  final List<NativeCall> calls = [];

  List<NativeCall> forChannel(String name) =>
      calls.where((c) => c.channel == name).toList(growable: false);

  void clear() => calls.clear();
}

class NativeCall {
  NativeCall(this.channel, this.method, this.arguments);

  final String channel;
  final String method;
  final Object? arguments;

  @override
  String toString() => '$channel.$method($arguments)';
}

/// Configure the default return values and seeded state every mocked
/// channel hands back to the code under test. Every field has a
/// sensible no-op default; pass a custom `FakeNativePluginsConfig` to
/// flip one dimension per test without rewriting handlers.
class FakeNativePluginsConfig {
  FakeNativePluginsConfig({
    this.hardwareVaultAvailable = false,
    this.hardwareVaultProbeDetail = 'unknown',
    Uint8List? seededHardwareVaultKey,
    this.storagePermissionGranted = true,
    this.qrScanResult,
    this.secureClipboardSucceeds = true,
  }) : _seededHardwareVaultKey = seededHardwareVaultKey;

  /// `isAvailable` response on the `hardware_vault` channel.
  final bool hardwareVaultAvailable;

  /// `probeDetail` response — maps to `HardwareProbeDetail` enum.
  final String hardwareVaultProbeDetail;

  /// When non-null, `isStored` returns true and `read` returns this
  /// payload. `store` overwrites this slot in-memory.
  Uint8List? _seededHardwareVaultKey;
  Uint8List? get seededHardwareVaultKey => _seededHardwareVaultKey;

  /// `requestStoragePermission` response.
  final bool storagePermissionGranted;

  /// `scan` response from the QR scanner channel. `null` simulates a
  /// user cancellation / denied permission.
  final String? qrScanResult;

  /// `setSecureText` response from the clipboard_secure channel.
  /// false triggers the Dart-side fallback to `Clipboard.setData`.
  final bool secureClipboardSucceeds;
}

/// Install mock handlers for every MethodChannel the app uses.
///
/// Covers:
/// - `com.letsflutssh/hardware_vault`
/// - `com.letsflutssh/clipboard_secure`
/// - `com.letsflutssh/session_lock`
/// - `com.letsflutssh/backup_exclusion`
/// - `com.letsflutssh/permissions`
/// - `com.letsflutssh/secure_screen`
/// - `com.letsflutssh/qrscanner`
/// - `miguelruivo.flutter.plugins.filepicker`
///
/// Returns the shared [NativeCallLog] so tests can assert on what the
/// code under test invoked. Call [uninstallFakeNativePlugins] in a
/// `tearDown` to scrub every handler back to null.
///
/// `local_auth` and `path_provider` / `flutter_secure_storage` are NOT
/// covered here — those have dedicated helpers (`FakeBiometricAuth`,
/// `installFakePathProvider`, `installFakeSecureStorage`) that other
/// tests already rely on.
NativeCallLog installFakeNativePlugins({FakeNativePluginsConfig? config}) {
  final cfg = config ?? FakeNativePluginsConfig();
  final log = NativeCallLog();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void mock(String name, Future<Object?> Function(MethodCall) handler) {
    messenger.setMockMethodCallHandler(MethodChannel(name), (call) async {
      log.calls.add(NativeCall(name, call.method, call.arguments));
      return handler(call);
    });
  }

  // com.letsflutssh/hardware_vault — in-memory sealed-blob slot.
  mock('com.letsflutssh/hardware_vault', (call) async {
    switch (call.method) {
      case 'isAvailable':
        return cfg.hardwareVaultAvailable;
      case 'probeDetail':
        return cfg.hardwareVaultProbeDetail;
      case 'isStored':
        return cfg._seededHardwareVaultKey != null;
      case 'store':
        final args = (call.arguments as Map).cast<String, Object?>();
        final dbKey = args['dbKey'];
        if (dbKey is Uint8List) {
          cfg._seededHardwareVaultKey = Uint8List.fromList(dbKey);
        }
        return true;
      case 'read':
        return cfg._seededHardwareVaultKey;
      case 'clear':
        cfg._seededHardwareVaultKey = null;
        return true;
    }
    return null;
  });

  // com.letsflutssh/clipboard_secure — returns the configured success
  // flag; tests that care assert on `log.forChannel(...)`.
  mock('com.letsflutssh/clipboard_secure', (call) async {
    if (call.method == 'setSecureText') return cfg.secureClipboardSucceeds;
    return null;
  });

  // com.letsflutssh/session_lock — production code only calls `start`
  // and registers a native->dart handler for `sessionLocked`. Dart-
  // driven tests do not need to simulate the event here; for that use
  // `messenger.handlePlatformMessage`.
  mock('com.letsflutssh/session_lock', (call) async {
    if (call.method == 'start') return null;
    return null;
  });

  // com.letsflutssh/backup_exclusion — fire-and-forget.
  mock('com.letsflutssh/backup_exclusion', (call) async => null);

  // com.letsflutssh/permissions — single storage-permission gate.
  mock('com.letsflutssh/permissions', (call) async {
    if (call.method == 'requestStoragePermission') {
      return cfg.storagePermissionGranted;
    }
    return null;
  });

  // com.letsflutssh/secure_screen — no-op on the test host.
  mock('com.letsflutssh/secure_screen', (call) async => null);

  // com.letsflutssh/qrscanner — return the scripted scan payload.
  mock('com.letsflutssh/qrscanner', (call) async {
    if (call.method == 'scan') return cfg.qrScanResult;
    return null;
  });

  // file_picker — return an empty selection by default so dialogs that
  // call `FilePicker.pickFiles` do not explode on a platform-channel
  // exception.
  mock('miguelruivo.flutter.plugins.filepicker', (call) async {
    switch (call.method) {
      case 'any':
      case 'custom':
      case 'media':
      case 'image':
      case 'video':
      case 'audio':
      case 'dir':
        return null;
      case 'clear':
        return true;
      case 'save':
        return null;
    }
    return null;
  });

  return log;
}

/// Drop every mock handler installed by [installFakeNativePlugins].
void uninstallFakeNativePlugins() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channels = [
    'com.letsflutssh/hardware_vault',
    'com.letsflutssh/clipboard_secure',
    'com.letsflutssh/session_lock',
    'com.letsflutssh/backup_exclusion',
    'com.letsflutssh/permissions',
    'com.letsflutssh/secure_screen',
    'com.letsflutssh/qrscanner',
    'miguelruivo.flutter.plugins.filepicker',
  ];
  for (final name in channels) {
    messenger.setMockMethodCallHandler(MethodChannel(name), null);
  }
}
