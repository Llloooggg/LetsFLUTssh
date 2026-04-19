import 'dart:io' show Platform;

import 'package:flutter/services.dart';

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
/// Platform-level listeners fire on OS lock:
/// - **Windows**: `WM_WTSSESSION_CHANGE` + `WTS_SESSION_LOCK`
///   subscription on the main window. Native side picks it up and
///   posts "session-lock" to the `com.letsflutssh/session_lock`
///   channel.
/// - **macOS**: `NSDistributedNotificationCenter` observer for
///   `com.apple.screenIsLocked`, posted on the same channel.
/// - **Linux**: D-Bus subscription to `org.freedesktop.login1`
///   `Lock` signal via the existing `dbus` dependency. Native
///   side posts to the channel.
/// - **iOS / Android**: the existing lifecycle-paused hook already
///   catches lock; this channel is a no-op.
///
/// Dart side is a single subscription helper — the widget tree
/// registers one callback (`onSessionLocked`) from
/// `AutoLockDetector.initState` and unregisters in `dispose`.
class SessionLockListener {
  SessionLockListener({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const _channelName = 'com.letsflutssh/session_lock';

  final MethodChannel _channel;
  final List<VoidCallback> _listeners = [];

  bool _installed = false;

  /// Register a callback for OS session-lock events. Calling multiple
  /// times with different callbacks fans out to every listener.
  /// Returns a `VoidCallback` that, when called, removes the
  /// listener — use in `dispose`.
  VoidCallback addListener(VoidCallback callback) {
    _listeners.add(callback);
    _ensureInstalled();
    return () => _listeners.remove(callback);
  }

  void _ensureInstalled() {
    if (_installed) return;
    _installed = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'sessionLocked') {
        // Fire listeners synchronously on the channel's isolate.
        // Callbacks are lightweight (route into `lockNow()`); no
        // microtask yield needed.
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
      return null;
    });
    // Ask the native side to start observing if the platform has a
    // handler. Missing channel (platforms without a native
    // implementation) is ignored.
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      _channel.invokeMethod<void>('start').catchError((e) {
        AppLogger.instance.log(
          'SessionLockListener start failed: $e',
          name: 'SessionLockListener',
        );
      });
    }
  }
}
