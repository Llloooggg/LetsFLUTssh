import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/security/lock_state.dart';
import '../core/security/security_level.dart';
import '../providers/auto_lock_provider.dart';
import '../providers/connection_provider.dart';
import '../providers/security_provider.dart';
import '../utils/logger.dart';

/// Wraps the app body and locks the app after `autoLockMinutesProvider`
/// minutes of user inactivity when security level is `masterPassword`.
///
/// What "lock" means:
///   * The global [lockStateProvider] flips to `true`; the root widget
///     swaps the UI for a lock screen that blocks interaction until the
///     user re-authenticates (master password or biometrics). **Always**
///     fires when the timer expires.
///   * The in-memory DB key is zeroed via
///     `securityStateProvider.clearEncryption()` — but **only when no
///     SSH/SFTP sessions are active**. The session count comes from
///     [connectionManagerProvider]. The reasoning: clearing the key kills
///     any future DB read but keeps the live SSH connections alive (they
///     run in dartssh2 isolates with their own state); however, the user
///     will likely want to interact with those sessions, and the moment
///     they tap to bring up SFTP for one we'd hit a locked DB. Easier UX
///     to just keep the key warm until everything is idle. Re-evaluation
///     happens on the next idle tick / lifecycle event, so the DB does
///     eventually get re-locked once the user finishes.
///
/// Triggers:
///   * Idle timer (user inactivity past the configured timeout).
///   * OS lifecycle going to `paused` / `inactive` / `hidden` — same as
///     the user actively switching away. The lock fires immediately so
///     the screen is already overlaid by the time the OS lock screen
///     dismisses. (Same gating: DB only re-locked if no live sessions.)
///
/// What it does NOT do:
///   * Close the drift database file handle. SQLite3MultipleCiphers still
///     has the cipher key in its internal page-cipher runtime state, so
///     DB reads continue to work until the app is restarted. Closing and
///     re-opening the DB would require coordinating with every open SSH
///     session, which is the trade-off the session-count gate above is
///     specifically designed to avoid.
///
/// Activity tracking: any pointer, keyboard, or focus event resets the
/// timer. Two mouse moves per second is enough to keep it alive.
class AutoLockDetector extends ConsumerStatefulWidget {
  final Widget child;

  const AutoLockDetector({super.key, required this.child});

  @override
  ConsumerState<AutoLockDetector> createState() => _AutoLockDetectorState();
}

class _AutoLockDetectorState extends ConsumerState<AutoLockDetector>
    with WidgetsBindingObserver {
  Timer? _timer;
  Duration _timeout = Duration.zero;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Lock on backgrounding (paused / inactive / hidden) only when the
    // user has opted in to auto-lock at all — i.e. the timer is not
    // "Off". Locking unconditionally on every window focus change was
    // the #1 user complaint: "блокировка срабатывает, если свернуть
    // приложение" even with the timer off. The session-count gate
    // inside [_triggerLock] still protects active SSH/SFTP sessions.
    if (state != AppLifecycleState.paused &&
        state != AppLifecycleState.inactive &&
        state != AppLifecycleState.hidden) {
      return;
    }
    final level = ref.read(securityStateProvider).level;
    if (level != SecurityLevel.masterPassword) return;
    final minutes = ref.read(autoLockMinutesProvider);
    if (minutes <= 0) return;
    _triggerLock();
  }

  @override
  Widget build(BuildContext context) {
    // React to config + security-level changes synchronously so the timer
    // is (re)armed the moment the user toggles auto-lock or switches
    // modes. Using ref.listen keeps the build cheap.
    ref.listen(autoLockMinutesProvider, (_, _) => _rearm());
    ref.listen(
      securityStateProvider.select((s) => s.level),
      (_, _) => _rearm(),
    );
    final minutes = ref.read(autoLockMinutesProvider);
    final level = ref.read(securityStateProvider).level;
    _syncTimer(minutes, level);

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _resetTimer(),
      onPointerMove: (_) => _resetTimer(),
      onPointerHover: (_) => _resetTimer(),
      onPointerSignal: (_) => _resetTimer(),
      child: Focus(
        canRequestFocus: false,
        onKeyEvent: (node, event) {
          _resetTimer();
          return KeyEventResult.ignored;
        },
        child: widget.child,
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  void _rearm() {
    final minutes = ref.read(autoLockMinutesProvider);
    final level = ref.read(securityStateProvider).level;
    _syncTimer(minutes, level);
  }

  void _syncTimer(int minutes, SecurityLevel level) {
    final enabled = minutes > 0 && level == SecurityLevel.masterPassword;
    if (!enabled) {
      _timer?.cancel();
      _timer = null;
      _timeout = Duration.zero;
      return;
    }
    final next = Duration(minutes: minutes);
    if (next == _timeout && _timer != null) return;
    _timeout = next;
    _resetTimer();
  }

  void _resetTimer() {
    if (_timeout == Duration.zero) return;
    _timer?.cancel();
    _timer = Timer(_timeout, _triggerLock);
  }

  void _triggerLock() {
    final locked = ref.read(lockStateProvider);
    if (locked) return;
    final activeSessions = ref.read(connectionManagerProvider).connections;
    final hasSessions = activeSessions.isNotEmpty;
    AppLogger.instance.log(
      'Auto-lock triggered (idle=${_timeout.inMinutes}m, '
      'activeSessions=${activeSessions.length}, '
      'clearKey=${!hasSessions})',
      name: 'AutoLock',
    );
    // Always overlay the lock screen — that's the user-visible "locked" state.
    ref.read(lockStateProvider.notifier).lock();
    // Only clear the in-memory DB key when no SSH sessions are running.
    // With live sessions, keep the key warm so the user can immediately
    // interact with their connections after unlocking. The next idle
    // tick / lifecycle event re-evaluates and eventually re-locks the DB.
    if (!hasSessions) {
      ref.read(securityStateProvider.notifier).clearEncryption();
    }
  }
}
