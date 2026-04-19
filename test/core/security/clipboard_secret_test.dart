import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/clipboard_secret.dart';

/// Mock the Flutter clipboard channel so tests can simulate writes /
/// reads / user-pasted-over scenarios without touching the host
/// clipboard.
class _FakeClipboardBackend {
  // Direct public field so tests can both read and inject values
  // (simulating the user pasting in something else mid-wipe-window).
  String? text;

  Future<dynamic> handle(MethodCall call) async {
    switch (call.method) {
      case 'Clipboard.setData':
        text = (call.arguments as Map?)?['text'] as String?;
        return null;
      case 'Clipboard.getData':
        return {'text': text};
      default:
        return null;
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeClipboardBackend backend;

  setUp(() {
    backend = _FakeClipboardBackend();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, backend.handle);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  // Short wipe window so tests stay fast; the production default is
  // 30 seconds but the logic is identical at 50ms.
  const wipe = Duration(milliseconds: 50);

  group('ClipboardSecret.copySecret', () {
    test('writes to the clipboard immediately', () async {
      final clip = ClipboardSecret(autoWipeAfter: wipe);
      await clip.copySecret('hunter2');
      expect(backend.text, 'hunter2');
      clip.cancelPendingWipe();
    });

    test('auto-wipes after the configured window', () async {
      final clip = ClipboardSecret(autoWipeAfter: wipe);
      await clip.copySecret('hunter2');
      expect(backend.text, 'hunter2');

      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(backend.text, '');
    });

    test(
      'does not wipe when the user has copied something else in the window',
      () async {
        final clip = ClipboardSecret(autoWipeAfter: wipe);
        await clip.copySecret('hunter2');

        // Simulate the user copying a URL in the middle of the
        // auto-wipe window via another app / platform action.
        backend.text = 'https://example.com';

        await Future<void>.delayed(const Duration(milliseconds: 120));

        expect(
          backend.text,
          'https://example.com',
          reason:
              'clipboard watcher must not clobber an unrelated value '
              'the user copied in the interim',
        );
      },
    );

    test(
      'subsequent copy cancels the earlier timer and starts a new one',
      () async {
        final clip = ClipboardSecret(autoWipeAfter: wipe);
        await clip.copySecret('first');
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await clip.copySecret('second');

        // First timer was due at +50ms; we are now at +20ms + the
        // second copy reset, so the first timer should already be
        // cancelled. Wait past the first-timer deadline but before
        // the second-timer deadline.
        await Future<void>.delayed(const Duration(milliseconds: 35));
        expect(
          backend.text,
          'second',
          reason: 'first-timer wipe must be cancelled by second copy',
        );

        await Future<void>.delayed(const Duration(milliseconds: 40));
        expect(
          backend.text,
          '',
          reason: 'second timer fires after its own window',
        );
      },
    );

    test(
      'cancelPendingWipe disarms the timer without touching clipboard',
      () async {
        final clip = ClipboardSecret(autoWipeAfter: wipe);
        await clip.copySecret('hunter2');
        clip.cancelPendingWipe();

        await Future<void>.delayed(const Duration(milliseconds: 120));

        expect(
          backend.text,
          'hunter2',
          reason:
              'cancelPendingWipe must leave the clipboard value intact — '
              'call sites rely on it for clean disposal',
        );
      },
    );

    test('cancelPendingWipe is a no-op when nothing is scheduled', () {
      final clip = ClipboardSecret();
      clip.cancelPendingWipe();
      clip.cancelPendingWipe();
    });
  });
}
