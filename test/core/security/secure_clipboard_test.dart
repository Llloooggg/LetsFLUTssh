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

  test(
    'routes through the native channel when the plugin is present',
    () async {
      MethodCall? seen;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            seen = call;
            return true;
          });

      await SecureClipboard(
        channel: channel,
        hasNativePlugin: true,
      ).setText('hunter2');

      expect(seen, isNotNull);
      expect(seen!.method, 'setSecureText');
      expect((seen!.arguments as Map)['text'], 'hunter2');
    },
  );

  test(
    'falls back to stock Clipboard.setData when the plugin is missing',
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
        hasNativePlugin: true,
      ).setText('hunter2');

      expect(stockText, 'hunter2');
    },
  );

  test('falls back to stock clipboard on native error', () async {
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

    await SecureClipboard(channel: channel).setText('hunter2');

    expect(stockText, 'hunter2');
  });
}
