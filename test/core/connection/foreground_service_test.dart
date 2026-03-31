import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/connection/foreground_service.dart';

/// Records all calls to the foreground service binding for verification.
class FakeBinding implements ForegroundServiceBinding {
  bool initCalled = false;
  final startCounts = <int>[];
  final updateCounts = <int>[];
  int stopCount = 0;
  bool startSucceeds = true;

  @override
  bool get isSupported => true;

  @override
  void initService() => initCalled = true;

  @override
  Future<bool> startService(int count) async {
    startCounts.add(count);
    return startSucceeds;
  }

  @override
  Future<void> updateNotification(int count) async {
    updateCounts.add(count);
  }

  @override
  Future<void> stopService() async {
    stopCount++;
  }
}

/// Binding that reports isSupported = false (simulates non-Android).
class UnsupportedBinding extends FakeBinding {
  @override
  bool get isSupported => false;
}

void main() {
  group('ForegroundServiceManager', () {
    late FakeBinding binding;
    late ForegroundServiceManager manager;

    setUp(() {
      binding = FakeBinding();
      manager = ForegroundServiceManager(binding: binding);
    });

    test('starts in non-running, non-initialized state', () {
      expect(manager.isRunning, isFalse);
      expect(manager.isInitialized, isFalse);
    });

    test('init calls binding.initService and sets initialized', () {
      manager.init();
      expect(binding.initCalled, isTrue);
      expect(manager.isInitialized, isTrue);
    });

    test('starts service when count goes from 0 to positive', () async {
      manager.init();
      await manager.onConnectionCountChanged(1);
      expect(manager.isRunning, isTrue);
      expect(binding.startCounts, [1]);
    });

    test('updates notification when count changes while running', () async {
      manager.init();
      await manager.onConnectionCountChanged(1);
      await manager.onConnectionCountChanged(2);
      expect(binding.updateCounts, [2]);
      expect(manager.isRunning, isTrue);
    });

    test('stops service when count drops to 0', () async {
      manager.init();
      await manager.onConnectionCountChanged(1);
      await manager.onConnectionCountChanged(0);
      expect(manager.isRunning, isFalse);
      expect(binding.stopCount, 1);
    });

    test('does not start again after stop until count > 0', () async {
      manager.init();
      await manager.onConnectionCountChanged(1);
      await manager.onConnectionCountChanged(0);
      expect(manager.isRunning, isFalse);

      await manager.onConnectionCountChanged(3);
      expect(manager.isRunning, isTrue);
      expect(binding.startCounts, [1, 3]);
    });

    test('does nothing when count is 0 and not running', () async {
      manager.init();
      await manager.onConnectionCountChanged(0);
      expect(manager.isRunning, isFalse);
      expect(binding.startCounts, isEmpty);
      expect(binding.stopCount, 0);
    });

    test('does not start if not initialized', () async {
      await manager.onConnectionCountChanged(1);
      expect(manager.isRunning, isFalse);
      expect(binding.startCounts, isEmpty);
    });

    test('handles start failure gracefully', () async {
      binding.startSucceeds = false;
      manager.init();
      await manager.onConnectionCountChanged(1);
      expect(manager.isRunning, isFalse);
    });

    test('full lifecycle: start → update → update → stop', () async {
      manager.init();
      await manager.onConnectionCountChanged(1);
      expect(manager.isRunning, isTrue);

      await manager.onConnectionCountChanged(2);
      await manager.onConnectionCountChanged(3);
      expect(binding.updateCounts, [2, 3]);

      await manager.onConnectionCountChanged(0);
      expect(manager.isRunning, isFalse);
      expect(binding.stopCount, 1);
    });

    test('dispose stops running service', () async {
      manager.init();
      await manager.onConnectionCountChanged(1);
      expect(manager.isRunning, isTrue);

      await manager.dispose();
      expect(manager.isRunning, isFalse);
      expect(binding.stopCount, 1);
    });

    test('dispose is safe when not running', () async {
      manager.init();
      await manager.dispose();
      expect(binding.stopCount, 0);
    });

    test('multiple dispose calls do not double-stop', () async {
      manager.init();
      await manager.onConnectionCountChanged(1);
      await manager.dispose();
      await manager.dispose();
      expect(binding.stopCount, 1);
    });

    test('rapid count changes handled correctly', () async {
      manager.init();
      await manager.onConnectionCountChanged(1);
      await manager.onConnectionCountChanged(5);
      await manager.onConnectionCountChanged(2);
      await manager.onConnectionCountChanged(0);
      await manager.onConnectionCountChanged(1);

      expect(binding.startCounts, [1, 1]); // started twice
      expect(binding.updateCounts, [5, 2]); // updated twice
      expect(binding.stopCount, 1); // stopped once
      expect(manager.isRunning, isTrue);
    });
  });

  group('ForegroundServiceManager (unsupported platform)', () {
    late UnsupportedBinding binding;
    late ForegroundServiceManager manager;

    setUp(() {
      binding = UnsupportedBinding();
      manager = ForegroundServiceManager(binding: binding);
    });

    test('init is no-op on unsupported platform', () {
      manager.init();
      expect(binding.initCalled, isFalse);
      expect(manager.isInitialized, isFalse);
    });

    test('onConnectionCountChanged is no-op on unsupported platform', () async {
      manager.init();
      await manager.onConnectionCountChanged(5);
      expect(manager.isRunning, isFalse);
      expect(binding.startCounts, isEmpty);
    });
  });

  group('notificationText', () {
    test('singular for 1 connection', () {
      expect(notificationText(1), '1 active connection');
    });

    test('plural for 0 connections', () {
      expect(notificationText(0), '0 active connections');
    });

    test('plural for multiple connections', () {
      expect(notificationText(3), '3 active connections');
    });
  });
}
