import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/secure_clipboard.dart';
import 'package:letsflutssh/utils/terminal_clipboard.dart';

import '../helpers/frb_bootstrap.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // _looksSensitive routes through `lfs_core::log_sanitize` —
  // bootstrap FRB so the canonical Rust heuristic is exercised.
  setUpAll(requireFrbLoaded);

  void clearClipboardMock() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  }

  group('TerminalClipboard', () {
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

    group('copyText — sensitive-content routing + auto-wipe', () {
      tearDown(() {
        clearClipboardMock();
        TerminalClipboard.debugResetSecureClipboard();
      });

      test('empty text is a no-op (no clipboard writes)', () async {
        final fakeSecure = _RecordingSecureClipboard();
        TerminalClipboard.debugSetSecureClipboard(fakeSecure);

        var stockWrites = 0;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, (call) async {
              if (call.method == 'Clipboard.setData') stockWrites++;
              return null;
            });

        TerminalClipboard.copyText('');
        await Future<void>.delayed(Duration.zero);

        expect(fakeSecure.writes, isEmpty);
        expect(stockWrites, 0);
      });

      test(
        'sensitive text routes through SecureClipboard (no stock fallback)',
        () async {
          // A long base64 run or a private-key PEM must opt out of Windows
          // clipboard history / macOS Handoff / Android 13+ preview / iOS
          // Universal Clipboard — the SecureClipboard channel handles those
          // flags. The stock `Clipboard.setData` path must be skipped so the
          // secret never lands in the system clipboard-history ring.
          final fakeSecure = _RecordingSecureClipboard();
          TerminalClipboard.debugSetSecureClipboard(fakeSecure);

          var stockWrites = 0;
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(SystemChannels.platform, (call) async {
                if (call.method == 'Clipboard.setData') stockWrites++;
                return null;
              });

          final secret = 'A' * 250;
          TerminalClipboard.copyText(secret);
          await Future<void>.delayed(Duration.zero);

          expect(fakeSecure.writes, [secret]);
          expect(stockWrites, 0);
        },
      );

      test('non-sensitive text takes the stock clipboard path', () async {
        // Non-secrets keep normal sync / history so routine workflows (copy
        // a filename, paste into another app) still benefit from Win+V,
        // Handoff, etc.
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

        TerminalClipboard.copyText('hello world');
        await Future<void>.delayed(Duration.zero);

        expect(fakeSecure.writes, isEmpty);
        expect(lastWrite, 'hello world');
      });
    });
  });
}

/// Captures every `setText` call so the sensitivity-routing test can
/// assert routing without needing the real FRB-backed
/// `lfs_os_security::secure_clipboard::set_secure_text` runtime.
class _RecordingSecureClipboard implements SecureClipboard {
  final writes = <String>[];

  @override
  Future<bool> setText(String text) async {
    writes.add(text);
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
