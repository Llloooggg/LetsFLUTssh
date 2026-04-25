import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/features/terminal/broadcast_controller.dart';

void main() {
  group('BroadcastController', () {
    late BroadcastController controller;

    setUp(() {
      controller = BroadcastController('tab1');
    });

    test('starts inactive with no driver and no receivers', () {
      expect(controller.isActive, isFalse);
      expect(controller.driverId, isNull);
      expect(controller.receiverIds, isEmpty);
    });

    test('isActive requires both a driver and at least one other receiver', () {
      controller.setDriver('a');
      expect(controller.isActive, isFalse);
      controller.toggleReceiver('a');
      expect(
        controller.isActive,
        isFalse,
        reason: 'pane that is both driver and "receiver" is filtered',
      );
      controller.toggleReceiver('b');
      expect(controller.isActive, isTrue);
    });

    test('promoting a receiver to driver clears its receiver row', () {
      controller.toggleReceiver('a');
      controller.setDriver('a');
      expect(controller.isReceiver('a'), isFalse);
      expect(controller.isDriver('a'), isTrue);
    });

    test('broadcastFrom fans bytes to all receivers except origin', () {
      final received = <String, List<int>>{};
      void registerSink(String id) {
        controller.registerSink(id, (bytes) {
          received.putIfAbsent(id, () => []).addAll(bytes);
        });
      }

      registerSink('drv');
      registerSink('a');
      registerSink('b');
      controller.setDriver('drv');
      controller.toggleReceiver('a');
      controller.toggleReceiver('b');

      controller.broadcastFrom('drv', Uint8List.fromList([0x41, 0x42]));

      expect(received['a'], [0x41, 0x42]);
      expect(received['b'], [0x41, 0x42]);
      expect(received.containsKey('drv'), isFalse);
    });

    test('broadcastFrom is a no-op when origin is not the driver', () {
      var calls = 0;
      controller.registerSink('a', (_) => calls++);
      controller.setDriver('drv');
      controller.toggleReceiver('a');

      controller.broadcastFrom('imposter', Uint8List.fromList([0]));
      expect(calls, 0);
    });

    test('broadcastFrom is a no-op when no receivers are wired', () {
      var calls = 0;
      controller.registerSink('drv', (_) => calls++);
      controller.setDriver('drv');

      controller.broadcastFrom('drv', Uint8List.fromList([0]));
      expect(calls, 0);
    });

    test('a throwing receiver does not block the rest', () {
      final delivered = <String, int>{};
      controller.registerSink('a', (_) => throw StateError('broken'));
      controller.registerSink('b', (bytes) => delivered['b'] = bytes.length);
      controller.setDriver('drv');
      controller.toggleReceiver('a');
      controller.toggleReceiver('b');

      controller.broadcastFrom('drv', Uint8List.fromList([1, 2, 3]));
      expect(delivered['b'], 3);
    });

    test('unregisterSink drops the registration and any role assignment', () {
      controller.registerSink('a', (_) {});
      controller.setDriver('a');
      expect(controller.isDriver('a'), isTrue);

      controller.unregisterSink('a');
      expect(controller.isDriver('a'), isFalse);
      expect(controller.driverId, isNull);
    });

    test('clearAll resets driver + every receiver', () {
      controller.setDriver('a');
      controller.toggleReceiver('b');
      controller.toggleReceiver('c');
      controller.clearAll();
      expect(controller.driverId, isNull);
      expect(controller.receiverIds, isEmpty);
    });

    test('listeners fire on every state change', () {
      var notified = 0;
      controller.addListener(() => notified++);

      controller.setDriver('a');
      controller.toggleReceiver('b');
      controller.toggleReceiver('b');
      controller.clearAll();

      expect(notified, 4);
    });
  });
}
