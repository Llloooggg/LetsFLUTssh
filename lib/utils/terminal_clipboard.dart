import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';

import '../core/security/secure_clipboard.dart';

/// Shared clipboard operations for terminal views (desktop + mobile).
class TerminalClipboard {
  TerminalClipboard._();

  /// Injected for tests — production reads the default platform-channel
  /// wiring. Swap via [debugSetSecureClipboard] in widget tests.
  static SecureClipboard _secureClipboard = SecureClipboard();

  @visibleForTesting
  static void debugSetSecureClipboard(SecureClipboard c) {
    _secureClipboard = c;
  }

  @visibleForTesting
  static void debugResetSecureClipboard() {
    _secureClipboard = SecureClipboard();
  }

  /// Time to keep a copied secret on the clipboard before overwriting it.
  /// Long enough to paste it once into another window; short enough that
  /// a careless `Ctrl+V` minutes later can't surface a private key.
  static const Duration secretClipboardLifetime = Duration(seconds: 30);

  /// Pending auto-wipe timer for the most-recent secret copy. Cancelled
  /// (and replaced) on every new sensitive copy so consecutive copies
  /// don't trigger an early wipe of the latest content.
  static Timer? _wipeTimer;

  /// The exact text we last wrote to the clipboard, so the wipe only
  /// clears it when the user has not since copied something else
  /// (e.g. a regular terminal selection from another app).
  static String? _lastSecretWritten;

  /// Copy the current selection text to clipboard and clear selection.
  /// Sensitive-looking content (PEM blocks, long base64 runs) is
  /// routed through [SecureClipboard] so it never lands in Windows
  /// clipboard history / macOS Handoff / Android 13+ toast preview /
  /// iOS Universal Clipboard. Non-sensitive selections take the stock
  /// clipboard path so normal copy/paste workflow (Win+V, cross-
  /// device sync) keeps working for non-secrets.
  ///
  /// In both cases a local 30-second auto-wipe is armed for sensitive
  /// payloads so the *current* clipboard slot is also cleared after
  /// the user has had a chance to paste once; the sync opt-out and
  /// the auto-wipe defend two different layers of the clipboard
  /// threat model and are independent.
  static void copy(Terminal terminal, TerminalController controller) {
    final selection = controller.selection;
    if (selection == null) return;
    final text = terminal.buffer.getText(selection);
    if (_looksSensitive(text)) {
      // Fire-and-forget — `SecureClipboard.setText` falls back to the
      // stock clipboard on Linux / missing-plugin so a copy action
      // always succeeds visibly on the user's side.
      unawaited(_secureClipboard.setText(text));
    } else {
      Clipboard.setData(ClipboardData(text: text));
    }
    controller.clearSelection();
    _maybeArmWipe(text);
  }

  /// Paste clipboard text into terminal.
  static Future<void> paste(Terminal terminal) async {
    final data = await Clipboard.getData('text/plain');
    if (data?.text != null && data!.text!.isNotEmpty) {
      terminal.textInput(data.text!);
    }
  }

  /// Heuristic: looks-like-a-secret content gets a clipboard auto-wipe.
  /// Currently triggers on PEM-style markers and long base64 runs (the
  /// same shapes `redactSecrets` strips from logs).
  static bool _looksSensitive(String text) {
    if (text.contains('-----BEGIN') && text.contains('PRIVATE KEY')) {
      return true;
    }
    return RegExp(r'[A-Za-z0-9+/=]{200,}').hasMatch(text);
  }

  /// Test-only accessor for the sensitivity heuristic.
  @visibleForTesting
  static bool debugLooksSensitive(String text) => _looksSensitive(text);

  static void _maybeArmWipe(String text) {
    if (!_looksSensitive(text)) return;
    _wipeTimer?.cancel();
    _lastSecretWritten = text;
    _wipeTimer = Timer(secretClipboardLifetime, () => _wipeIfStillOurs(text));
  }

  static Future<void> _wipeIfStillOurs(String expected) async {
    final current = await Clipboard.getData('text/plain');
    // Only wipe if the clipboard still holds *our* secret. If the user
    // (or another app) has copied something else in the meantime, leave
    // it alone.
    if (current?.text == expected && _lastSecretWritten == expected) {
      await Clipboard.setData(const ClipboardData(text: ''));
    }
    _wipeTimer = null;
    _lastSecretWritten = null;
  }
}
