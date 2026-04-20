import 'dart:async';

import 'package:flutter/services.dart';

import '../../utils/logger.dart';
import 'secure_clipboard.dart';

/// Auto-expiring clipboard writes for password-shaped copy flows.
///
/// Session passwords, SSH-key passphrases, and API tokens all flow
/// through `Clipboard.setData` when the user taps a "Copy password"
/// button. The typical pattern in password managers is to schedule
/// an auto-wipe of the clipboard some seconds later so the secret
/// does not sit around for the next app that inspects the clipboard
/// to scoop up (terminal emulators, browsers, and some
/// systemd-journal clipboard managers all do this).
///
/// Behaviour:
///
/// - [copySecret] writes [plaintext] to the system clipboard and
///   schedules a wipe. Any previously-scheduled wipe on the same
///   [ClipboardSecret] instance is cancelled first — a second
///   "Copy" within the window does not double-wipe nor clobber the
///   new value when the first timer fires.
/// - When the timer fires it reads the clipboard, compares against
///   the value we wrote, and only wipes if they still match. If the
///   user copied something else in the meantime (typed text, a URL,
///   another app's output) we never clobber it.
/// - [cancelPendingWipe] lets the caller disarm the timer manually
///   without touching the clipboard — useful on dispose so a widget
///   tree teardown does not run a wipe against the live user
///   clipboard.
///
/// Kept decoupled from Flutter widgets so platform-agnostic tests
/// can pump the clock directly. The default `SystemClipboard` is
/// injected through `Clipboard` (Flutter's system channel); tests
/// replace it with a `MethodChannel` mock binding.
class ClipboardSecret {
  ClipboardSecret({Duration? autoWipeAfter, SecureClipboard? writer})
    : _autoWipeAfter = autoWipeAfter ?? const Duration(seconds: 30),
      _writer = writer ?? SecureClipboard();

  final Duration _autoWipeAfter;
  final SecureClipboard _writer;

  Timer? _pendingTimer;
  String? _pendingValue;

  /// Copy [plaintext] and schedule an auto-wipe after
  /// [ClipboardSecret.autoWipeAfter]. Returns once the system
  /// clipboard has accepted the write; the wipe runs
  /// asynchronously in the background.
  Future<void> copySecret(String plaintext) async {
    cancelPendingWipe();
    try {
      await _writer.setText(plaintext);
    } catch (e) {
      AppLogger.instance.log(
        'ClipboardSecret.copySecret write failed: $e',
        name: 'ClipboardSecret',
      );
      return;
    }
    _pendingValue = plaintext;
    _pendingTimer = Timer(_autoWipeAfter, _runWipe);
  }

  /// Cancel any scheduled wipe. No-op when no timer is pending.
  /// Does not touch the clipboard — call sites that need to zero
  /// out the clipboard explicitly should use [copySecret] with an
  /// empty string instead.
  void cancelPendingWipe() {
    _pendingTimer?.cancel();
    _pendingTimer = null;
    _pendingValue = null;
  }

  Future<void> _runWipe() async {
    final expected = _pendingValue;
    _pendingTimer = null;
    _pendingValue = null;
    if (expected == null) return;
    try {
      final live = await Clipboard.getData('text/plain');
      // Only wipe if the clipboard still holds the secret we wrote
      // — if the user copied something else in the meantime, leave
      // it alone. Use constant-time-ish compare on length + bytes;
      // `String ==` is fine here because this is a UX timer, not a
      // side-channel-sensitive comparison.
      if (live?.text != expected) return;
      await Clipboard.setData(const ClipboardData(text: ''));
    } catch (e) {
      AppLogger.instance.log(
        'ClipboardSecret wipe failed: $e',
        name: 'ClipboardSecret',
      );
    }
  }
}
