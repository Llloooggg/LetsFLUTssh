import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/secure_clipboard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.letsflutssh/clipboard_secure');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  // Android path keeps the native MethodChannel because
  // `EXTRA_IS_SENSITIVE` needs the platform `ClipboardManager` API.
  // Tests below exercise both arms of the platform branch.

  test('Android path routes through the native channel', () async {
    MethodCall? seen;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          seen = call;
          return true;
        });

    await SecureClipboard(
      channel: channel,
      isAndroidPlatform: true,
    ).setText('hunter2');

    expect(seen, isNotNull);
    expect(seen!.method, 'setSecureText');
    expect((seen!.arguments as Map)['text'], 'hunter2');
  });

  test(
    'Android path REFUSES the write when the plugin is missing — never falls back',
    () async {
      // Plugin missing on Android means the native EXTRA_IS_SENSITIVE
      // flag never lands; falling back to stock `Clipboard.setData`
      // would deposit the secret into the Android 13+ clipboard
      // history preview without the opt-out marker. The hardened
      // posture is to refuse, surface the failure to the caller, and
      // let the UI render a "copy failed" toast — same as the
      // Win/macOS/iOS arms below.
      String? stockText;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            throw MissingPluginException('no plugin');
          });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              stockText = (call.arguments as Map?)?['text'] as String?;
            }
            return null;
          });

      final landed = await SecureClipboard(
        channel: channel,
        isAndroidPlatform: true,
      ).setText('hunter2');

      expect(landed, isFalse, reason: 'must refuse on plugin missing');
      expect(stockText, isNull, reason: 'must NOT touch stock clipboard');
    },
  );

  test('Android path REFUSES the write on native error', () async {
    String? stockText;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          throw PlatformException(code: 'CLIPBOARD_FAILED');
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            stockText = (call.arguments as Map?)?['text'] as String?;
          }
          return null;
        });

    final landed = await SecureClipboard(
      channel: channel,
      isAndroidPlatform: true,
    ).setText('hunter2');

    expect(landed, isFalse);
    expect(stockText, isNull);
  });

  test(
    'non-Android path falls back to stock when Rust call fails (FRB unloaded in tests)',
    () async {
      // Without `requireFrbLoaded`, the FRB call throws StateError
      // and the writer routes to the stock Clipboard.setData. The
      // production path on a real desktop / iOS device hits Rust
      // first instead.
      String? stockText;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              stockText = (call.arguments as Map?)?['text'] as String?;
            }
            return null;
          });

      await SecureClipboard(
        channel: channel,
        isAndroidPlatform: false,
      ).setText('hunter2');

      expect(stockText, 'hunter2');
    },
  );
}
