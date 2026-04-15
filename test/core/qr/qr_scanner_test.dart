import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/qr/qr_scanner.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('scanQrCode', () {
    const channel = MethodChannel('com.letsflutssh/qrscanner');
    final binding = TestDefaultBinaryMessengerBinding.instance;

    tearDown(() {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    });

    test('returns the native method channel result on success', () async {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        expect(call.method, 'scan');
        return 'letsflutssh://import?d=abc';
      });

      final result = await scanQrCode();
      expect(result, 'letsflutssh://import?d=abc');
    });

    test('returns null when the native side yields null (cancelled)', () async {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (call) async => null,
      );

      final result = await scanQrCode();
      expect(result, isNull);
    });

    test(
      'swallows PlatformException and returns null (e.g. permission denied)',
      () async {
        binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
          call,
        ) async {
          throw PlatformException(
            code: 'PERMISSION_DENIED',
            message: 'user said no',
          );
        });

        final result = await scanQrCode();
        expect(result, isNull);
      },
    );
  });
}
