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
    'Android path falls back to stock Clipboard.setData when the plugin is missing',
    () async {
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

      await SecureClipboard(
        channel: channel,
        isAndroidPlatform: true,
      ).setText('hunter2');

      expect(stockText, 'hunter2');
    },
  );

  test('Android path falls back to stock clipboard on native error', () async {
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

    await SecureClipboard(
      channel: channel,
      isAndroidPlatform: true,
    ).setText('hunter2');

    expect(stockText, 'hunter2');
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
