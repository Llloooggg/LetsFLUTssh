import 'dart:async' show Timer, unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/security/lock_state.dart';
import '../core/security/security_tier.dart';
import '../core/security/session_lock_listener.dart';
import '../core/security/terminal_scrubber.dart';
import '../providers/auto_lock_provider.dart';
import '../providers/config_provider.dart';
import '../providers/security_provider.dart';
import '../providers/session_provider.dart';
import '../utils/logger.dart';

/// Wraps the app body and locks the app after `autoLockMinutesProvider`
/// minutes of user inactivity when a user-typed secret is configured.
///
/// What "lock" means:
///   * The global [lockStateProvider] flips to `true`; the root widget
///     swaps the UI for a lock screen that blocks interaction until the
///     user re-authenticates (master password or biometrics).
///   * The in-memory DB key is **always** zeroed via
///     `securityStateProvider.clearEncryption()` — regardless of whether
///     active SSH sessions are present. Previously the wipe was gated
///     on `activeSessions.isEmpty` to keep SFTP reachable, which meant
///     RAM forensics of a locked app could still recover the DB key as
///     long as one session was connected — flattening T1+password and
///     T2+password in the threat matrix. The gate is removed; live
///     session reconnect is satisfied instead by
///     `SessionCredentialCache` (per-session page-locked auth envelope
///     that survives the lock), so the encrypted store can close
///     without losing the "reconnect after unlock" UX.
///   * The drift / MC handle is closed so the C-layer page
///     cipher cache is also zeroed. `main._injectDatabase` opens a
///     fresh handle after unlock under the re-derived key.
///
/// Triggers:
///   * Idle timer (user inactivity past the configured timeout).
///   * OS lifecycle going to `paused` / `inactive` / `hidden` — same as
///     the user actively switching away. The lock fires immediately so
///     the screen is already overlaid by the time the OS lock screen
///     dismisses.
///   * OS session-lock signal (Win+L / Ctrl+Cmd+Q / GNOME screensaver)
///     via [SessionLockListener].
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
  final SessionLockListener _sessionLockListener = SessionLockListener();
  VoidCallback? _sessionLockDispose;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Bind the OS session-lock signal into the same lock path as the
    // idle timer + lifecycle-paused hook. When the user locks the
    // workstation (Win+L / Ctrl+Cmd+Q / GNOME screensaver etc) we
    // fire lockNow immediately regardless of how much idle time
    // has accumulated.
    _sessionLockDispose = _sessionLockListener.addListener(() {
      if (!mounted) return;
      if (!_hasTypedSecret()) return;
      AppLogger.instance.log(
        'OS session-lock signal received; firing auto-lock',
        name: 'AutoLock',
      );
      _triggerLock();
    });
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
    if (!_hasTypedSecret()) return;
    final minutes = ref.read(autoLockMinutesProvider);
    if (minutes <= 0) return;
    _triggerLock();
  }

  /// True when the active tier has a user-typed secret (either
  /// Paranoid, or any tier with the password modifier on). Auto-lock
  /// is meaningful only on these tiers — a tier without a typed
  /// secret has nothing to re-prompt for after the lock.
  bool _hasTypedSecret() {
    final level = ref.read(securityStateProvider).level;
    if (level == SecurityTier.paranoid) return true;
    if (level == SecurityTier.keychainWithPassword) return true;
    final modifiers =
        ref.read(configProvider).security?.modifiers ??
        SecurityTierModifiers.defaults;
    return modifiers.password;
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
    _sessionLockDispose?.call();
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  void _rearm() {
    final minutes = ref.read(autoLockMinutesProvider);
    final level = ref.read(securityStateProvider).level;
    _syncTimer(minutes, level);
  }

  void _syncTimer(int minutes, SecurityTier level) {
    final enabled = minutes > 0 && _hasTypedSecret();
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
    AppLogger.instance.log(
      'Auto-lock triggered (idle=${_timeout.inMinutes}m, '
      'keyWiped=true, dbClosed=true)',
      name: 'AutoLock',
    );
    // Always overlay the lock screen — that's the user-visible "locked" state.
    ref.read(lockStateProvider.notifier).lock();
    // Scrub terminal scrollbacks BEFORE the user sees the lock
    // overlay. A password the user pasted into a terminal, or a
    // secret the remote shell echoed back, sits in xterm's
    // scrollback buffer long after the viewport scrolls past it —
    // a second person who taps the lock screen can scroll up and
    // read it. Clearing the scrollback is cheap even when no
    // terminals are registered (empty-set iteration).
    TerminalScrubber.instance.scrubAll();
    // Unconditionally zero the in-memory DB key and close the
    // drift / MC handle. Live SSH sessions stay reconnectable
    // because `SessionCredentialCache` (populated on connect, kept
    // alive across the lock) holds each session's auth envelope in
    // page-locked memory outside the DB. The next idle tick / unlock
    // re-opens the DB via `main._injectDatabase` under the freshly
    // re-derived key.
    ref.read(securityStateProvider.notifier).clearEncryption();
    // Fire-and-forget — UI must not block on a close.
    unawaited(ref.read(sessionStoreProvider).closeDatabase());
  }
}
