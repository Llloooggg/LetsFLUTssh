import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/secure_clipboard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  test('successful Rust write returns true and never touches stock', () async {
    String? stockText;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            stockText = (call.arguments as Map?)?['text'] as String?;
          }
          return null;
        });

    String? written;
    final clip = SecureClipboard(
      rustWriter: (text) {
        written = text;
      },
      platformOs: 'android',
    );

    final landed = await clip.setText('hunter2');

    expect(landed, isTrue);
    expect(written, 'hunter2');
    expect(stockText, isNull, reason: 'stock path must not run on success');
  });

  test('Linux falls back to stock clipboard on Rust failure', () async {
    String? stockText;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            stockText = (call.arguments as Map?)?['text'] as String?;
          }
          return null;
        });

    final clip = SecureClipboard(
      rustWriter: (_) => throw StateError('Rust unavailable'),
      platformOs: 'linux',
    );

    final landed = await clip.setText('hunter2');

    expect(landed, isTrue, reason: 'Linux fallback must land the copy');
    expect(stockText, 'hunter2');
  });

  for (final os in const ['windows', 'macos', 'ios', 'android']) {
    test('$os refuses the write on Rust failure (cloud-sync gate)', () async {
      // The opt-out flags are part of the same write session as the
      // text. A stock `Clipboard.setData` fallback would deposit the
      // secret on the cloud-syncing pasteboard (Win+V history,
      // Universal Clipboard, Handoff, Android 13+ history preview)
      // without the per-platform "do not sync, do not history"
      // markers — strictly worse than refusing the copy and
      // surfacing a "copy failed" toast to the user.
      String? stockText;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              stockText = (call.arguments as Map?)?['text'] as String?;
            }
            return null;
          });

      final clip = SecureClipboard(
        rustWriter: (_) => throw StateError('Rust unavailable'),
        platformOs: os,
      );

      final landed = await clip.setText('hunter2');

      expect(landed, isFalse, reason: '$os must refuse on Rust failure');
      expect(
        stockText,
        isNull,
        reason: '$os must NOT touch the stock clipboard',
      );
    });
  }
}
