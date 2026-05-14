import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/clipboard_secret.dart';
import 'package:letsflutssh/core/security/secure_clipboard.dart';
import 'package:letsflutssh/src/rust/api/crypto.dart' as rust_crypto;

import '../../helpers/frb_bootstrap.dart';

/// In-memory clipboard backend driven through the `SecureClipboard`
/// + `ClipboardSecret` test seams. Production routes both the write
/// and the compare-and-clear through Rust; the seams let widget tests
/// exercise the auto-wipe contract end-to-end without an FRB runtime
/// touching the host clipboard.
class _FakeBackend {
  String? text;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // `ClipboardSecret.copySecret` hashes the plaintext via the
  // FRB-backed `cryptoSha256Hex`. The seam in the production
  // `ClipboardSecret.debugRustCompareAndClearOverride` slot below
  // re-hashes the in-memory clipboard contents through the same
  // helper, so both sides of the wipe gate share one digest format.
  setUpAll(requireFrbLoaded);

  late _FakeBackend backend;

  setUp(() {
    backend = _FakeBackend();
    SecureClipboard.debugRustWriterOverride = (text) {
      backend.text = text;
    };
    ClipboardSecret.debugRustCompareAndClearOverride = (expectedSha256Hex) {
      // Simulates the Rust-side compare-and-clear orchestrator:
      // read the current clipboard, hash it, and clear only when
      // the digest matches what the timer staged. Production runs
      // the equivalent dance in `lfs_os_security::secure_clipboard`.
      final current = backend.text;
      if (current == null || current.isEmpty) return false;
      final liveHex = rust_crypto.cryptoSha256Hex(bytes: utf8.encode(current));
      if (liveHex != expectedSha256Hex) return false;
      backend.text = '';
      return true;
    };
  });

  tearDown(() {
    SecureClipboard.debugResetRustWriter();
    ClipboardSecret.debugResetRustCompareAndClear();
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
