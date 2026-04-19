import 'package:flutter/foundation.dart';
import 'package:xterm/xterm.dart';

import '../../utils/logger.dart';

/// Registry of live xterm [Terminal] instances + a scrub hook the
/// auto-lock path calls when the user's DB key is about to be
/// cleared.
///
/// Motivation: xterm buffers the last N lines of terminal output in
/// memory per widget (`Terminal(maxLines: scrollback)`). If the
/// remote shell echoed a password, printed a secret env var, or
/// ran `ssh-add -l` with a passphrase typed in the interactive
/// prompt, that text sits in the scrollback for the rest of the
/// session. On lock the Dart-side DB key is zeroed but the
/// scrollback still holds whatever the user saw. A second user
/// who taps the lock screen and types the unlock password sees
/// the scrollback untouched — fine if it was just command output,
/// bad if the user pasted a secret into the terminal.
///
/// Widgets that own a Terminal register it here on `initState` and
/// deregister on `dispose`. `scrubAll()` walks every live entry and
/// resets its buffer. Safe to call from any thread — the terminal
/// API internally marshals to the main isolate.
class TerminalScrubber {
  TerminalScrubber._();

  static final TerminalScrubber _instance = TerminalScrubber._();
  static TerminalScrubber get instance => _instance;

  final Set<Terminal> _registered = <Terminal>{};

  /// Register a live terminal. Idempotent — registering the same
  /// instance twice is a no-op.
  void register(Terminal terminal) {
    _registered.add(terminal);
  }

  /// Deregister on widget dispose. Silently tolerates unknown
  /// instances so teardown ordering bugs do not throw.
  void unregister(Terminal terminal) {
    _registered.remove(terminal);
  }

  /// Current registered-count. Exposed for tests / diagnostics.
  int get trackedCount => _registered.length;

  /// Clear the scrollback of every tracked terminal. Called by the
  /// auto-lock path right before (or alongside) the DB-key zeroise.
  /// Best-effort — a single terminal's reset throwing must not stop
  /// the loop.
  void scrubAll() {
    // Snapshot the set so a reentrant modification (e.g. a widget
    // disposing mid-scrub) does not trip the iterator.
    final snapshot = List<Terminal>.unmodifiable(_registered);
    var failed = 0;
    for (final terminal in snapshot) {
      try {
        // xterm's public API for "empty the scrollback + viewport"
        // is `buffer.clear` + `setCursor(0, 0)`. `clear()` on the
        // terminal itself resets ANSI state which can desync the
        // live shell, so we keep the reset narrow to the buffer.
        terminal.buffer.clear();
        terminal.setCursor(0, 0);
      } catch (e) {
        failed++;
        AppLogger.instance.log(
          'TerminalScrubber: one terminal scrub failed: $e',
          name: 'TerminalScrubber',
        );
      }
    }
    if (snapshot.isNotEmpty) {
      AppLogger.instance.log(
        'TerminalScrubber: scrubbed ${snapshot.length} terminal(s), '
        'failed=$failed',
        name: 'TerminalScrubber',
      );
    }
  }

  /// Reset the registry. Tests call this between cases to isolate
  /// state; production never invokes it.
  @visibleForTesting
  void resetForTests() {
    _registered.clear();
  }
}
