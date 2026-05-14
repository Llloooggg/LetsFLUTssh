import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../src/rust/api/crypto.dart' as rust_crypto;
import '../../src/rust/api/os_security.dart' as rust_os;
import '../../utils/logger.dart';
import 'secure_clipboard.dart';

/// Auto-expiring clipboard writes for password-shaped copy flows.
///
/// Session passwords, SSH-key passphrases, and API tokens all flow
/// through [SecureClipboard.setText] when the user taps a "Copy
/// password" button. The typical pattern in password managers is to
/// schedule an auto-wipe of the clipboard some seconds later so the
/// secret does not sit around for the next app that inspects the
/// clipboard to scoop up (terminal emulators, browsers, and some
/// systemd-journal clipboard managers all do this).
///
/// Behaviour:
///
/// - [copySecret] writes [plaintext] to the system clipboard and
///   schedules a wipe. Any previously-scheduled wipe on the same
///   [ClipboardSecret] instance is cancelled first — a second
///   "Copy" within the window does not double-wipe nor clobber the
///   new value when the first timer fires.
/// - When the timer fires the wipe path calls into
///   `lfs_os_security::secure_clipboard::compare_and_clear`. The Rust
///   side reads the clipboard, hashes it, compares against the
///   SHA-256 hex digest we staged, and writes an empty string through
///   the same audit perimeter as the original write (so a wiped slot
///   still carries Win+V opt-out, NSPasteboard transient/concealed
///   markers, UIPasteboard `localOnly`, Android `EXTRA_IS_SENSITIVE`).
///   If the user copied something else in the meantime we never
///   clobber it — the digest comparison fails and the clear is
///   skipped.
/// - [cancelPendingWipe] lets the caller disarm the timer manually
///   without touching the clipboard — useful on dispose so a widget
///   tree teardown does not run a wipe against the live user
///   clipboard.
///
/// Plaintext never sits on the Dart heap past the FRB write. Only the
/// SHA-256 hex digest is held between `copySecret` and the timer
/// firing; the digest is one-way, so a stale 30-second reference to a
/// freshly-copied PEM is not material that an attacker reading the
/// heap dump could weaponise.
class ClipboardSecret {
  ClipboardSecret({Duration? autoWipeAfter, SecureClipboard? writer})
    : _autoWipeAfter = autoWipeAfter ?? const Duration(seconds: 30),
      _writer = writer ?? SecureClipboard();

  final Duration _autoWipeAfter;
  final SecureClipboard _writer;

  /// Test seam — installed by widget tests that exercise the
  /// compare-and-clear path without an FRB runtime. Production
  /// leaves this `null`; the timer body then routes through
  /// [rust_os.osSecuritySecureClipboardCompareAndClear]. Tests
  /// inject a fake that simulates "drifted" or "still ours" outcomes
  /// against an in-memory clipboard backend. The hook receives the
  /// staged digest and returns the bool the production FRB call
  /// would have returned (`true` when the clear ran, `false` when
  /// the clipboard drifted).
  @visibleForTesting
  static bool Function(String expectedSha256Hex)?
  debugRustCompareAndClearOverride;

  /// Reset the compare-and-clear seam to the FRB-backed production
  /// path. Pair with `tearDown` after every test that installs an
  /// override.
  @visibleForTesting
  static void debugResetRustCompareAndClear() {
    debugRustCompareAndClearOverride = null;
  }

  Timer? _pendingTimer;
  String? _pendingHash;

  /// Copy [plaintext] and schedule an auto-wipe after the
  /// configured window. Returns once the system clipboard has
  /// accepted the write; the wipe runs asynchronously in the
  /// background.
  ///
  /// Returns `false` when the cloud-clipboard refusal gate in
  /// [SecureClipboard.setText] declined the write (cloud-syncing
  /// platforms whose secure path failed). Callers surface the
  /// failure via toast — auto-wipe is NOT scheduled because the
  /// payload never landed on the pasteboard.
  Future<bool> copySecret(String plaintext) async {
    cancelPendingWipe();
    final bool landed;
    try {
      landed = await _writer.setText(plaintext);
    } catch (e) {
      AppLogger.instance.log(
        'ClipboardSecret.copySecret write failed: $e',
        name: 'ClipboardSecret',
      );
      return false;
    }
    if (!landed) return false;
    _pendingHash = rust_crypto.cryptoSha256Hex(bytes: utf8.encode(plaintext));
    _pendingTimer = Timer(_autoWipeAfter, _runWipe);
    return true;
  }

  /// Cancel any scheduled wipe. No-op when no timer is pending.
  /// Does not touch the clipboard — call sites that need to zero
  /// out the clipboard explicitly should use [copySecret] with an
  /// empty string instead.
  void cancelPendingWipe() {
    _pendingTimer?.cancel();
    _pendingTimer = null;
    _pendingHash = null;
  }

  void _runWipe() {
    final expected = _pendingHash;
    _pendingTimer = null;
    _pendingHash = null;
    if (expected == null) return;
    try {
      final hook = debugRustCompareAndClearOverride;
      if (hook != null) {
        hook(expected);
      } else {
        rust_os.osSecuritySecureClipboardCompareAndClear(
          expectedSha256Hex: expected,
        );
      }
    } catch (e) {
      AppLogger.instance.log(
        'ClipboardSecret wipe failed: $e',
        name: 'ClipboardSecret',
      );
    }
  }
}
