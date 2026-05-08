import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show VoidCallback, visibleForTesting;

import '../../src/rust/api/os_security.dart' as rust_os;
import '../../utils/logger.dart';

/// Bridge between OS-level "workstation locked" / "session locked"
/// events and the in-app auto-lock path.
///
/// Idle-timer auto-lock covers the "user stopped typing" case, and
/// mobile lifecycle-paused covers "app moved to background". Neither
/// covers the case where the user locks the OS (Win+L on Windows,
/// Ctrl+Cmd+Q on macOS, i3-lock / xdg-screensaver on Linux, or
/// pressing the power button) while idle-minutes are higher than
/// zero and the user has NOT actually been idle inside our app in
/// the last idle-minutes.
///
/// Platform-level routing — every desktop OS goes through the
/// `lfs_os_security::session_lock_listener` Rust subscriber and
/// reaches Dart via FRB:
/// - **Linux**: zbus `org.freedesktop.login1.Session.Lock` signal.
/// - **Windows**: WTS session-change + `WTS_SESSION_LOCK` posted
///   from the Rust-side MessageHandler.
/// - **macOS**: `NSDistributedNotificationCenter` observer for
///   `com.apple.screenIsLocked` on the main run loop.
/// - **iOS / Android**: Flutter's lifecycle-paused hook already
///   catches lock; this class is a no-op.
class SessionLockListener {
  SessionLockListener({Stream<void>? lockEvents})
    : _injectedEvents = lockEvents {
    _liveInstances.add(this);
  }

  /// Live instances waiting for FRB readiness. The desktop subscribe
  /// path goes through `lfs_os_security::session_lock_listener` (FRB);
  /// AutoLockDetector mounts during the first runApp pass, so the
  /// initial `addListener` lands BEFORE `_initRustCoreOrFatal`. The
  /// pre-FRB attempt would throw `StateError` and emit a `SessionLockListener
  /// Rust subscribe failed` line into the log; instead, the deferred
  /// install is replayed from `_LetsFLUTsshAppState._wireFrbDependent
  /// BootstrapListeners` via [retryAllPending] once Rust is up.
  static final List<SessionLockListener> _liveInstances =
      <SessionLockListener>[];

  /// Replay the OS subscription on every cached listener whose
  /// pre-FRB attempt was deferred. Idempotent — a listener already
  /// installed (`_installed = true`) short-circuits in
  /// [_ensureInstalled].
  static void retryAllPending() {
    for (final l in List<SessionLockListener>.from(_liveInstances)) {
      l._ensureInstalled();
    }
  }

  final Stream<void>? _injectedEvents;
  final List<VoidCallback> _listeners = [];

  bool _installed = false;
  StreamSubscription<void>? _streamSub;

  /// Register a callback for OS session-lock events. Calling multiple
  /// times with different callbacks fans out to every listener.
  /// Returns a `VoidCallback` that, when called, removes the
  /// listener — use in `dispose`.
  VoidCallback addListener(VoidCallback callback) {
    _listeners.add(callback);
    _ensureInstalled();
    return () => _listeners.remove(callback);
  }

  /// Tear down the OS subscription. Idempotent.
  Future<void> dispose() async {
    final sub = _streamSub;
    _streamSub = null;
    await sub?.cancel();
    _liveInstances.remove(this);
  }

  /// Drive a lock event into the fan-out without touching the OS
  /// — test seam used by the unit suite.
  @visibleForTesting
  void debugFire() => _fanOut();

  void _ensureInstalled() {
    if (_installed) return;

    if (_injectedEvents != null) {
      _installed = true;
      _streamSub = _injectedEvents.listen((_) => _fanOut());
      return;
    }
    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      // FRB-gated. Pre-`_initRustCoreOrFatal` calls leave
      // `_installed` false on `StateError` so [retryAllPending]
      // re-attempts after the bootstrap chain promotes everything
      // else through `_wireFrbDependentBootstrapListeners`. The
      // defensive `RustLib.instance.initialized` guard the audit's
      // A11 sweep removed: the typed-catch shape is structurally
      // equivalent and aligns with the strict cold-start invariant
      // (no `RustLib.instance` reads on the cold-start path).
      try {
        _ensureRustStream();
        _installed = true;
      } on StateError {
        // Pre-FRB-init — retry on the next `retryAllPending` /
        // bootstrap promote.
      }
      return;
    }
    // iOS / Android: lifecycle-paused covers it. No subscription
    // installed.
  }

  void _ensureRustStream() {
    try {
      _streamSub = rust_os.osSecuritySessionLockSubscribe().listen(
        (_) => _fanOut(),
        onError: (Object e) {
          AppLogger.instance.log(
            'SessionLockListener Rust stream error: $e',
            name: 'SessionLockListener',
            level: LogLevel.warn,
          );
        },
      );
    } catch (e) {
      AppLogger.instance.log(
        'SessionLockListener Rust subscribe failed: $e',
        name: 'SessionLockListener',
        level: LogLevel.warn,
      );
    }
  }

  void _fanOut() {
    for (final cb in List<VoidCallback>.from(_listeners)) {
      try {
        cb();
      } catch (e) {
        AppLogger.instance.log(
          'SessionLockListener callback failed: $e',
          name: 'SessionLockListener',
        );
      }
    }
  }
}
