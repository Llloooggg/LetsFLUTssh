import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/connection/foreground_service.dart';

void main() {
  group('ForegroundServiceManager (non-Android)', () {
    // Tests run on Linux/macOS/Windows — all methods are no-ops.

    late ForegroundServiceManager manager;

    setUp(() {
      manager = ForegroundServiceManager();
    });

    test('isRunning is false initially', () {
      expect(manager.isRunning, isFalse);
    });

    test('init is no-op on non-Android', () {
      manager.init();
      // Should not throw or change state
      expect(manager.isRunning, isFalse);
    });

    test('onConnectionCountChanged is no-op on non-Android', () async {
      manager.init();
      await manager.onConnectionCountChanged(5);
      expect(manager.isRunning, isFalse);
    });

    test('onConnectionCountChanged without init is no-op', () async {
      await manager.onConnectionCountChanged(1);
      expect(manager.isRunning, isFalse);
    });

    test('dispose is safe when not running', () async {
      await manager.dispose();
      expect(manager.isRunning, isFalse);
    });

    test('dispose after init is safe on non-Android', () async {
      manager.init();
      await manager.dispose();
      expect(manager.isRunning, isFalse);
    });

    test('multiple dispose calls are safe', () async {
      manager.init();
      await manager.dispose();
      await manager.dispose();
      expect(manager.isRunning, isFalse);
    });
  });
}
