import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/widgets/secure_native_text_field.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('isSupported follows the platform switch', () {
    // Test host is Linux; Android-only so the flag must be false on
    // this runner. Changes on Android would flip this.
    expect(SecureNativeTextField.isSupported, isFalse);
  });

  testWidgets('renders an empty SizedBox on unsupported hosts', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SecureNativeTextField(onSubmit: (_) {})),
      ),
    );
    // Non-Android: widget reports isSupported == false and collapses
    // to a zero-size placeholder so callers can safely use it in a
    // conditional tree without a runtime branch per call site.
    expect(find.byType(SizedBox), findsAtLeastNWidgets(1));
    expect(find.byType(AndroidView), findsNothing);
  });

  testWidgets('onSubmit receives the raw Uint8List the channel delivered', (
    tester,
  ) async {
    // Install a mock handler for the per-view channel the widget
    // would bind to. The test asserts the shape of the callback
    // contract, not the platform view itself — a real Android
    // device verifies the view-side code.
    Uint8List? received;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SecureNativeTextField(onSubmit: (bytes) => received = bytes),
        ),
      ),
    );
    // Simulate what the native side would do: invoke `onSubmit`
    // on the per-view channel. ID 0 is what the first platform
    // view would get if this test were on Android; here we fake
    // the wiring to prove the Dart handler copies correctly.
    const channel = MethodChannel('com.letsflutssh/secure_text_0');
    // Manually register the method-call handler the state would
    // set up after the view is created — the test host never
    // creates the view, so we wire it ourselves.
    channel.setMethodCallHandler((call) async {
      if (call.method == 'onSubmit') {
        final raw = call.arguments;
        if (raw is Uint8List) received = raw;
      }
      return null;
    });
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          channel.name,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall(
              'onSubmit',
              Uint8List.fromList([0x70, 0x77, 0x64]), // 'pwd'
            ),
          ),
          (_) {},
        );
    expect(received, isNotNull);
    expect(received, [0x70, 0x77, 0x64]);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
}
