import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';

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
/// Platform-level routing:
/// - **Linux**: `lfs_os_security::session_lock_listener::subscribe`
///   (zbus → `org.freedesktop.login1.Session.Lock` signal). FRB
///   Stream forwards events into the Dart-side fan-out.
/// - **Windows**: `WM_WTSSESSION_CHANGE` + `WTS_SESSION_LOCK` on
///   the main Flutter window's `MessageHandler`. Native side posts
///   "sessionLocked" to the `com.letsflutssh/session_lock`
///   MethodChannel. Kept Dart-bound because the WTS subscription
///   is HWND-scoped.
/// - **macOS**: `NSDistributedNotificationCenter` observer for
///   `com.apple.screenIsLocked` on the main run loop. Same channel
///   as Windows. Kept Dart-bound because the observer needs the
///   Cocoa run loop the Flutter app already pumps.
/// - **iOS / Android**: Flutter's lifecycle-paused hook already
///   catches lock; this class is a no-op.
class SessionLockListener {
  SessionLockListener({MethodChannel? channel, Stream<void>? lockEvents})
    : _channel = channel ?? const MethodChannel(_channelName),
      _injectedEvents = lockEvents;

  static const _channelName = 'com.letsflutssh/session_lock';

  final MethodChannel _channel;
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
  }

  /// Drive a lock event into the fan-out without touching the OS
  /// — test seam used by the unit suite.
  @visibleForTesting
  void debugFire() => _fanOut();

  void _ensureInstalled() {
    if (_installed) return;
    _installed = true;

    if (_injectedEvents != null) {
      _streamSub = _injectedEvents.listen((_) => _fanOut());
      return;
    }
    if (Platform.isLinux) {
      _ensureRustStream();
      return;
    }
    if (Platform.isWindows || Platform.isMacOS) {
      _ensureNativeChannel();
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
          );
        },
      );
    } catch (e) {
      AppLogger.instance.log(
        'SessionLockListener Rust subscribe failed: $e',
        name: 'SessionLockListener',
      );
    }
  }

  void _ensureNativeChannel() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'sessionLocked') {
        _fanOut();
      }
      return null;
    });
    _channel.invokeMethod<void>('start').catchError((Object e) {
      AppLogger.instance.log(
        'SessionLockListener start failed: $e',
        name: 'SessionLockListener',
      );
    });
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
