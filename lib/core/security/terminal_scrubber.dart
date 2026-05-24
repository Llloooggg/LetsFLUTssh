import 'package:meta/meta.dart' show visibleForTesting;

import '../../utils/logger.dart';

/// Registry of scrub callbacks the auto-lock + wipe paths invoke
/// when the user's DB key is about to be cleared.
///
/// Motivation: the terminal engine buffers the last N lines of output
/// in memory per pane (the scrollback). If the remote shell
/// echoed a password, printed a secret env var, or ran a command
/// that spelled out credentials, that text sits in the scrollback
/// for the rest of the session. On lock the Dart-side DB key is
/// zeroed but the scrollback still holds whatever the user saw. A
/// second user who taps the lock screen and types the unlock
/// password sees the scrollback untouched — fine if it was just
/// command output, bad if the user pasted a secret into the
/// terminal.
///
/// Each terminal pane registers a [VoidCallback] on `initState`
/// that clears its own scrollback (over FRB to the Rust engine) and
/// deregisters on `dispose`. `scrubAll()` walks every live callback.
/// Decoupled from the terminal widget so `core/` stays
/// UI-package-free; the buffer reset lives in the calling widget that
/// owns the session handle.
typedef TerminalScrubFn = void Function();

class TerminalScrubber {
  TerminalScrubber._();

  static final TerminalScrubber _instance = TerminalScrubber._();
  static TerminalScrubber get instance => _instance;

  final Set<TerminalScrubFn> _registered = <TerminalScrubFn>{};

  /// Register a live terminal's scrub callback. Idempotent —
  /// registering the same closure twice is a no-op.
  void register(TerminalScrubFn fn) {
    _registered.add(fn);
  }

  /// Deregister on widget dispose. Silently tolerates unknown
  /// closures so teardown ordering bugs do not throw.
  void unregister(TerminalScrubFn fn) {
    _registered.remove(fn);
  }

  /// Current registered-count. Exposed for tests / diagnostics.
  int get trackedCount => _registered.length;

  /// Invoke every registered scrub callback. Called by the
  /// auto-lock path right before (or alongside) the DB-key
  /// zeroise. Best-effort — a single callback throwing must not
  /// stop the loop.
  void scrubAll() {
    // Snapshot the set so a reentrant modification (e.g. a widget
    // disposing mid-scrub) does not trip the iterator.
    final snapshot = List<TerminalScrubFn>.unmodifiable(_registered);
    var failed = 0;
    for (final fn in snapshot) {
      try {
        fn();
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
