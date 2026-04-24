import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/secure_clipboard.dart';
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

      test('heuristic PEM branch requires BOTH BEGIN and PRIVATE KEY', () {
        // A refactor that short-circuited on just `-----BEGIN` would
        // flag harmless public-key paste ("-----BEGIN CERTIFICATE-----")
        // as sensitive. The heuristic intentionally checks both tokens.
        expect(
          TerminalClipboard.debugLooksSensitive(
            '-----BEGIN CERTIFICATE-----\nMIIBIjAN',
          ),
          isFalse,
          reason: 'Certificate PEM without "PRIVATE KEY" must stay allowed',
        );
        expect(
          TerminalClipboard.debugLooksSensitive(
            'PRIVATE KEY lives in /etc/ssh',
          ),
          isFalse,
          reason: 'Bare "PRIVATE KEY" string without -----BEGIN is fine',
        );
      });

      test(
        '199-char base64-alphabet string stays below the wipe threshold',
        () {
          // The regex is intentionally `{200,}` — guard the boundary.
          expect(TerminalClipboard.debugLooksSensitive('a' * 199), isFalse);
          expect(TerminalClipboard.debugLooksSensitive('a' * 200), isTrue);
        },
      );
    });

    group('copy — routing sensitive content', () {
      tearDown(() {
        clearClipboardMock();
        TerminalClipboard.debugResetSecureClipboard();
      });

      test(
        'sensitive payload goes through SecureClipboard (no stock fallback)',
        () async {
          // Regression guard for Bug #13. A long base64 run or a
          // private-key PEM must opt out of Windows clipboard history /
          // macOS Handoff / Android 13+ preview / iOS Universal
          // Clipboard — the `SecureClipboard` channel handles those
          // flags. Before the fix, terminal copy always took the stock
          // `Clipboard.setData` path; a user copying `cat
          // ~/.ssh/id_ed25519` landed the private key in Win+V history.
          final fakeSecure = _RecordingSecureClipboard();
          TerminalClipboard.debugSetSecureClipboard(fakeSecure);

          var stockWrites = 0;
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(SystemChannels.platform, (call) async {
                if (call.method == 'Clipboard.setData') stockWrites++;
                return null;
              });

          // Wide terminal so the 250-char run fits on one row and the
          // anchor-based selection captures it without wrap ambiguity.
          terminal.resize(400, 24);
          // 250-char base64-alphabet run trips the sensitivity heuristic.
          final secret = 'A' * 250;
          terminal.write('$secret\r\n');
          final base = terminal.buffer.createAnchor(0, 0);
          final extent = terminal.buffer.createAnchor(secret.length, 0);
          controller.setSelection(base, extent);

          TerminalClipboard.copy(terminal, controller);
          // setText is async fire-and-forget; give the zone a tick.
          await Future<void>.delayed(Duration.zero);

          expect(
            fakeSecure.writes,
            hasLength(1),
            reason: 'Sensitive payload must route through SecureClipboard',
          );
          expect(fakeSecure.writes.single, contains(secret));
          expect(
            stockWrites,
            0,
            reason:
                'Stock Clipboard.setData must be skipped when the payload '
                'looks sensitive — the whole point of the SecureClipboard '
                'opt-out is to bypass the system clipboard-history ring.',
          );
        },
      );

      test(
        'non-sensitive payload still takes the stock clipboard path',
        () async {
          // Flip side: non-secrets must keep normal sync / history so
          // routine workflows (copy a filename, paste into another app)
          // still benefit from Win+V, Handoff, etc.
          final fakeSecure = _RecordingSecureClipboard();
          TerminalClipboard.debugSetSecureClipboard(fakeSecure);

          String? lastWrite;
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(SystemChannels.platform, (call) async {
                if (call.method == 'Clipboard.setData') {
                  lastWrite = (call.arguments as Map)['text'] as String?;
                }
                return null;
              });

          terminal.resize(80, 24);
          terminal.write('ls -la\r\n');
          final base = terminal.buffer.createAnchor(0, 0);
          final extent = terminal.buffer.createAnchor(6, 0);
          controller.setSelection(base, extent);

          TerminalClipboard.copy(terminal, controller);
          await Future<void>.delayed(Duration.zero);

          expect(
            fakeSecure.writes,
            isEmpty,
            reason: 'Non-secret copy must not hit SecureClipboard',
          );
          expect(lastWrite, contains('ls -la'));
        },
      );
    });

    group('copy — with an active selection (non-sensitive)', () {
      tearDown(clearClipboardMock);

      test(
        'writes selected text to the clipboard and clears the selection',
        () async {
          // Non-sensitive path — the 11-char "hello world" payload is
          // below the 200-char base64 threshold and has no PEM markers,
          // so it takes the stock clipboard route. The selected text
          // drops into the mocked clipboard; the controller's selection
          // gets cleared as a side-effect.
          terminal.resize(80, 24);
          terminal.write('hello world\r\n');

          String? lastWrite;
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(SystemChannels.platform, (call) async {
                if (call.method == 'Clipboard.setData') {
                  lastWrite = (call.arguments as Map)['text'] as String?;
                }
                return null;
              });

          // Select rows 0..0 (first line).
          final base = terminal.buffer.createAnchor(0, 0);
          final extent = terminal.buffer.createAnchor(11, 0);
          controller.setSelection(base, extent);
          expect(controller.selection, isNotNull);

          TerminalClipboard.copy(terminal, controller);

          expect(
            lastWrite,
            isNotNull,
            reason: 'Clipboard.setData must be invoked with selection text',
          );
          expect(lastWrite, contains('hello'));
          expect(
            controller.selection,
            isNull,
            reason: 'Copy must clear the selection as a side-effect',
          );
        },
      );
    });
  });
}

/// Captures every `setText` call so the sensitivity-routing test can
/// assert routing without needing the real `com.letsflutssh/clipboard_secure`
/// method channel.
class _RecordingSecureClipboard implements SecureClipboard {
  final writes = <String>[];

  @override
  Future<void> setText(String text) async {
    writes.add(text);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
