import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/utils/terminal_clipboard.dart';
import 'package:xterm/xterm.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Terminal terminal;
  late TerminalController controller;

  setUp(() {
    terminal = Terminal();
    controller = TerminalController();
  });

  void mockClipboard({String? text}) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.getData') {
            if (text == null) return null;
            return <String, dynamic>{'text': text};
          }
          if (call.method == 'Clipboard.setData') {
            return null;
          }
          return null;
        });
  }

  void clearClipboardMock() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  }

  group('TerminalClipboard', () {
    group('copy', () {
      test('does nothing when no selection', () {
        // No selection set — should not throw.
        TerminalClipboard.copy(terminal, controller);
        expect(controller.selection, isNull);
      });
    });

    group('paste', () {
      tearDown(clearClipboardMock);

      test('sends clipboard text to terminal', () async {
        mockClipboard(text: 'hello world');

        String? received;
        terminal.onOutput = (text) => received = text;

        await TerminalClipboard.paste(terminal);

        expect(received, 'hello world');
      });

      test('does nothing when clipboard is empty', () async {
        mockClipboard(text: '');

        String? received;
        terminal.onOutput = (text) => received = text;

        await TerminalClipboard.paste(terminal);

        expect(received, isNull);
      });

      test('does nothing when clipboard returns null', () async {
        mockClipboard();

        String? received;
        terminal.onOutput = (text) => received = text;

        await TerminalClipboard.paste(terminal);

        expect(received, isNull);
      });
    });

    group('sensitive-content auto wipe', () {
      test('looks-sensitive heuristic catches PEM blocks and long base64', () {
        expect(
          TerminalClipboard.debugLooksSensitive(
            '-----BEGIN OPENSSH PRIVATE KEY-----\nABCD\n-----END OPENSSH PRIVATE KEY-----',
          ),
          isTrue,
          reason: 'PEM block must be flagged for auto-wipe',
        );
        expect(
          TerminalClipboard.debugLooksSensitive('A' * 250),
          isTrue,
          reason: 'Long base64 run must be flagged for auto-wipe',
        );
      });

      test('looks-sensitive heuristic ignores normal short text', () {
        expect(
          TerminalClipboard.debugLooksSensitive('ls -la /var/log'),
          isFalse,
        );
        expect(TerminalClipboard.debugLooksSensitive('hello world'), isFalse);
      });
    });
  });
}
