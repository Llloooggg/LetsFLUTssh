import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../../utils/logger.dart';

/// Callback required by flutter_foreground_task — runs in isolate.
/// We don't need periodic work (dartssh2 keepalive handles pings),
/// so the handler is a no-op that just keeps the service alive.
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

/// Manages Android foreground service lifecycle tied to active SSH connections.
///
/// Call [onConnectionCountChanged] whenever the number of active connections
/// changes. The service starts when count goes from 0→1 and stops when it
/// drops back to 0.
///
/// On non-Android platforms this class is a no-op.
class ForegroundServiceManager {
  bool _running = false;
  bool _initialized = false;

  bool get isRunning => _running;

  /// Initialize the foreground task options. Call once at app startup.
  void init() {
    if (!Platform.isAndroid) return;
    _initialized = true;
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
    AppLogger.instance.log(
      'Foreground service initialized',
      name: 'ForegroundService',
    );
  }

  /// Update notification and start/stop service based on active count.
  Future<void> onConnectionCountChanged(int activeCount) async {
    if (!Platform.isAndroid || !_initialized) return;

    if (activeCount > 0 && !_running) {
      await _start(activeCount);
    } else if (activeCount > 0 && _running) {
      await _updateNotification(activeCount);
    } else if (activeCount == 0 && _running) {
      await _stop();
    }
  }

  Future<void> _start(int count) async {
    final result = await FlutterForegroundTask.startService(
      serviceId: 100,
      notificationTitle: 'SSH active',
      notificationText: _notificationText(count),
      serviceTypes: [ForegroundServiceTypes.dataSync],
      callback: _startCallback,
    );
    if (result is ServiceRequestSuccess) {
      _running = true;
      AppLogger.instance.log(
        'Foreground service started ($count connection(s))',
        name: 'ForegroundService',
      );
    } else {
      AppLogger.instance.log(
        'Foreground service start failed: $result',
        name: 'ForegroundService',
      );
    }
  }

  Future<void> _updateNotification(int count) async {
    await FlutterForegroundTask.updateService(
      notificationTitle: 'SSH active',
      notificationText: _notificationText(count),
    );
  }

  Future<void> _stop() async {
    await FlutterForegroundTask.stopService();
    _running = false;
    AppLogger.instance.log(
      'Foreground service stopped',
      name: 'ForegroundService',
    );
  }

  String _notificationText(int count) =>
      '$count active connection${count == 1 ? '' : 's'}';

  /// Stop the service if running. Call on app dispose.
  Future<void> dispose() async {
    if (_running) await _stop();
  }
}
