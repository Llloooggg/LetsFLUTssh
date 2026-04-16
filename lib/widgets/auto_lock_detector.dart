import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/security/lock_state.dart';
import '../core/security/security_level.dart';
import '../providers/auto_lock_provider.dart';
import '../providers/security_provider.dart';
import '../utils/logger.dart';

/// Wraps the app body and locks the app after `autoLockMinutesProvider`
/// minutes of user inactivity when security level is `masterPassword`.
///
/// What "lock" means:
///   * The in-memory DB key is zeroed via `securityStateProvider.clearEncryption()`
///     (the native-locked [SecretBuffer] is disposed → zeroed → munlock → free).
///   * The global [lockStateProvider] flips to `true`; the root widget
///     swaps the UI for a lock screen that blocks interaction until the
///     user re-authenticates (master password or biometrics).
///
/// What it does NOT do (yet):
///   * Close the drift database. SQLite3MultipleCiphers still has the key
///     in its internal page-cipher state, so DB reads continue to work
///     until the app is restarted. This is a known trade-off — closing
///     and re-opening the DB requires coordinating with every open SSH /
///     SFTP session, which is out of this change's scope.
///
/// Activity tracking: any pointer, keyboard, or focus event resets the
/// timer. Two mouse moves per second is enough to keep it alive.
class AutoLockDetector extends ConsumerStatefulWidget {
  final Widget child;

  const AutoLockDetector({super.key, required this.child});

  @override
  ConsumerState<AutoLockDetector> createState() => _AutoLockDetectorState();
}

class _AutoLockDetectorState extends ConsumerState<AutoLockDetector> {
  Timer? _timer;
  Duration _timeout = Duration.zero;

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
    AppLogger.instance.log(
      'Auto-lock triggered after ${_timeout.inMinutes}m idle',
      name: 'AutoLock',
    );
    ref.read(securityStateProvider.notifier).clearEncryption();
    ref.read(lockStateProvider.notifier).lock();
  }
}
