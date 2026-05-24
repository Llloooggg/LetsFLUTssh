import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/security/secure_clipboard.dart';
import '../src/rust/api/crypto.dart' as rust_crypto;
import '../src/rust/api/os_security.dart' as rust_os;
import 'sanitize.dart' show looksSensitive;

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

  /// Test seam — installed by widget tests that exercise the auto-wipe
  /// path without an FRB runtime. Production leaves this `null`; the
  /// timer body then routes through
  /// [rust_os.osSecuritySecureClipboardCompareAndClear]. Tests inject
  /// a fake that simulates "drifted" or "still ours" outcomes against
  /// an in-memory clipboard backend.
  @visibleForTesting
  static bool Function(String expectedSha256Hex)?
  debugRustCompareAndClearOverride;

  @visibleForTesting
  static void debugResetRustCompareAndClear() {
    debugRustCompareAndClearOverride = null;
  }

  /// Test seam — cancel any armed auto-wipe timer so a widget test that
  /// copies sensitive content doesn't leave a live 30 s [Timer] that
  /// trips flutter_test's "A Timer is still pending" check. Production
  /// never calls this; the timer fires on its own schedule and clears
  /// the slot.
  @visibleForTesting
  static void debugCancelPendingWipe() {
    _wipeTimer?.cancel();
    _wipeTimer = null;
    _lastSecretHash = null;
  }

  /// Test seam — replaces the SHA-256 digest used to gate the auto-wipe.
  /// Production leaves this `null` and [_hash] crosses FRB to
  /// `lfs_core::crypto::sha256_hex`. Widget tests that copy sensitive
  /// content without an FRB runtime install a pure-Dart stand-in so the
  /// arm path doesn't throw "flutter_rust_bridge has not been
  /// initialized" inside the synchronous copy call (which wedges the
  /// flutter_test harness). The digest only feeds the process-local
  /// "newer-arm-overrides" gate, so any stable function of the text is
  /// sufficient for a test.
  @visibleForTesting
  static String Function(String text)? debugHashOverride;

  @visibleForTesting
  static void debugResetHashOverride() {
    debugHashOverride = null;
  }

  /// Time to keep a copied secret on the clipboard before overwriting it.
  /// Long enough to paste it once into another window; short enough that
  /// a careless `Ctrl+V` minutes later can't surface a private key.
  static const Duration secretClipboardLifetime = Duration(seconds: 30);

  /// Pending auto-wipe timer for the most-recent secret copy. Cancelled
  /// (and replaced) on every new sensitive copy so consecutive copies
  /// don't trigger an early wipe of the latest content.
  static Timer? _wipeTimer;

  /// SHA-256 hex of the text we last wrote to the clipboard. Acts as
  /// the "newer-arm-overrides" gate — a fresh `copy` of a different
  /// secret bumps this value, and when the older timer body runs it
  /// sees the slot has changed and bails before crossing FRB. The
  /// digest itself is also the payload of the
  /// `compare_and_clear` FRB call, so the Rust side has the same
  /// reference to gate the actual read+wipe.
  static String? _lastSecretHash;

  /// Copy a text snapshot to the clipboard with sensitive-content
  /// routing + auto-wipe arming.
  ///
  /// Sensitive-looking content (PEM blocks, long base64 runs) is routed
  /// through [SecureClipboard] so it never lands in Windows clipboard
  /// history / macOS Handoff / Android 13+ toast preview / iOS Universal
  /// Clipboard. Non-sensitive text takes the stock clipboard path so normal
  /// copy/paste workflow (Win+V, cross-device sync) keeps working for
  /// non-secrets. A local 30-second auto-wipe is armed for sensitive
  /// payloads so the *current* clipboard slot is also cleared after the
  /// user has had a chance to paste once; the sync opt-out and the auto-wipe
  /// defend two different layers of the clipboard threat model and are
  /// independent.
  ///
  /// Callers capture the selection text first (off the Rust engine's
  /// `selectionText`, or synchronously at pointer-down for the read-only
  /// right-click menu) so the copy works against a stable string.
  static void copyText(String text) {
    if (text.isEmpty) return;
    if (_looksSensitive(text)) {
      // Fire-and-forget — `SecureClipboard.setText` refuses the
      // write on Rust-side failure rather than bypassing the audit
      // perimeter through Flutter's stock channel. The terminal copy
      // path keeps the fire-and-forget shape; a refusal logs at warn
      // level on the SecureClipboard tag.
      unawaited(_secureClipboard.setText(text));
    } else {
      Clipboard.setData(ClipboardData(text: text));
    }
    _maybeArmWipe(text);
  }

  /// Heuristic: looks-like-a-secret content gets a clipboard auto-wipe.
  /// Triggers on PEM-style markers and long base64 runs (the same
  /// shapes `redactSecrets` strips from logs) via the pure-Dart
  /// `looksSensitive` helper so the redactor + auto-wipe agree on
  /// what counts as "do not let this leak".
  static bool _looksSensitive(String text) => looksSensitive(text);

  /// Test-only accessor for the sensitivity heuristic.
  @visibleForTesting
  static bool debugLooksSensitive(String text) => _looksSensitive(text);

  static void _maybeArmWipe(String text) {
    if (!_looksSensitive(text)) return;
    _wipeTimer?.cancel();
    final hash = _hash(text);
    _lastSecretHash = hash;
    _wipeTimer = Timer(secretClipboardLifetime, () => _wipeIfStillOurs(hash));
  }

  static void _wipeIfStillOurs(String expectedHash) {
    // Process-local gate: a later sensitive `copy` bumps
    // `_lastSecretHash` to a different value, so an earlier timer
    // that fires after the newer arm sees its expected hash no
    // longer matches the "current" hash and bails before crossing
    // FRB. The Rust side has its own clipboard-state compare; this
    // check just avoids the FRB hop in the "we know we replaced it
    // ourselves" case.
    if (_lastSecretHash != expectedHash) {
      _wipeTimer = null;
      return;
    }
    try {
      final hook = debugRustCompareAndClearOverride;
      if (hook != null) {
        hook(expectedHash);
      } else {
        rust_os.osSecuritySecureClipboardCompareAndClear(
          expectedSha256Hex: expectedHash,
        );
      }
    } catch (_) {
      // Wipe is best-effort — the SecureClipboard tag already logs
      // FRB-side failures. Suppressing here keeps the timer body
      // from surfacing a noisy stack trace on every headless test
      // host where the system clipboard is unreachable.
    }
    _wipeTimer = null;
    _lastSecretHash = null;
  }

  static String _hash(String text) {
    final hook = debugHashOverride;
    if (hook != null) return hook(text);
    return rust_crypto.cryptoSha256Hex(bytes: utf8.encode(text));
  }
}
