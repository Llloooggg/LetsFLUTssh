import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../../utils/logger.dart';

/// Callback required by flutter_foreground_task — runs in isolate.
/// We don't need periodic work (russh handles SSH-level keep-alive
/// pings), so the handler is a no-op that just keeps the service
/// alive.
@pragma('vm:entry-point')
void _startCallback() {
  FlutterForegroundTask.setTaskHandler(_KeepAliveHandler());
}

class _KeepAliveHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isAppTerminated) async {}
}

/// Abstracts platform service calls so [ForegroundServiceManager] can be tested
/// without a real Android foreground service.
abstract class ForegroundServiceBinding {
  Future<bool> startService(int count);
  Future<void> updateNotification(int count);
  Future<void> stopService();
  void initService();
  bool get isSupported;
}

/// Real implementation that talks to [FlutterForegroundTask].
class _RealBinding implements ForegroundServiceBinding {
  @override
  bool get isSupported => Platform.isAndroid;

  @override
  void initService() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'ssh_foreground_service',
        channelName: 'SSH Connection',
        channelDescription: 'Keeps SSH connections alive in the background.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
        showWhen: false,
        enableVibration: false,
        playSound: false,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  @override
  Future<bool> startService(int count) async {
    final result = await FlutterForegroundTask.startService(
      serviceId: 100,
      notificationTitle: 'SSH active',
      notificationText: notificationText(count),
      serviceTypes: [ForegroundServiceTypes.dataSync],
      callback: _startCallback,
    );
    return result is ServiceRequestSuccess;
  }

  @override
  Future<void> updateNotification(int count) async {
    await FlutterForegroundTask.updateService(
      notificationTitle: 'SSH active',
      notificationText: notificationText(count),
    );
  }

  @override
  Future<void> stopService() async {
    await FlutterForegroundTask.stopService();
  }
}

/// Notification text shared between binding and tests.
String notificationText(int count) =>
    '$count active connection${count == 1 ? '' : 's'}';

/// Manages Android foreground service lifecycle tied to active SSH connections.
///
/// Call [onConnectionCountChanged] whenever the number of active connections
/// changes. The service starts when count goes from 0→1 and stops when it
/// drops back to 0.
///
/// On non-Android platforms this class is a no-op (unless a test binding
/// is injected).
class ForegroundServiceManager {
  final ForegroundServiceBinding _binding;
  bool _running = false;
  bool _initialized = false;

  bool get isRunning => _running;

  @visibleForTesting
  bool get isInitialized => _initialized;

  ForegroundServiceManager({
    @visibleForTesting ForegroundServiceBinding? binding,
  }) : _binding = binding ?? _RealBinding();

  /// Initialize the foreground task options. Call once at app startup.
  void init() {
    if (!_binding.isSupported) return;
    _initialized = true;
    _binding.initService();
    AppLogger.instance.log(
      'Foreground service initialized',
      name: 'ForegroundService',
    );
  }

  /// Update notification and start/stop service based on active count.
  Future<void> onConnectionCountChanged(int activeCount) async {
    if (!_binding.isSupported || !_initialized) return;

    if (activeCount > 0 && !_running) {
      AppLogger.instance.log(
        'Connection count 0 -> $activeCount, starting service',
        name: 'ForegroundService',
      );
      await _start(activeCount);
    } else if (activeCount > 0 && _running) {
      await _updateNotification(activeCount);
    } else if (activeCount == 0 && _running) {
      AppLogger.instance.log(
        'Connection count -> 0, stopping service',
        name: 'ForegroundService',
      );
      await _stop();
    }
  }

  Future<void> _start(int count) async {
    final ok = await _binding.startService(count);
    if (ok) {
      _running = true;
      AppLogger.instance.log(
        'Foreground service started ($count connection(s))',
        name: 'ForegroundService',
      );
    } else {
      AppLogger.instance.log(
        'Foreground service start failed',
        name: 'ForegroundService',
      );
    }
  }

  Future<void> _updateNotification(int count) async {
    await _binding.updateNotification(count);
    AppLogger.instance.log(
      'Notification updated: $count connection(s)',
      name: 'ForegroundService',
    );
  }

  Future<void> _stop() async {
    await _binding.stopService();
    _running = false;
    AppLogger.instance.log(
      'Foreground service stopped',
      name: 'ForegroundService',
    );
  }

  /// Stop the service if running. Call on app dispose.
  Future<void> dispose() async {
    if (_running) await _stop();
  }
}
