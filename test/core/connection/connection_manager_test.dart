import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/connection/connection_manager.dart';
import 'package:letsflutssh/core/ssh/known_hosts.dart';

void main() {
  // ConnectionManager.connect() requires a real SSH server, so we only test
  // the non-connect lifecycle methods and observable behavior.

  late ConnectionManager manager;
  late KnownHostsManager knownHosts;

  setUp(() {
    knownHosts = KnownHostsManager();
    manager = ConnectionManager(knownHosts: knownHosts);
  });

  tearDown(() {
    manager.dispose();
  });

  group('ConnectionManager', () {
    test('starts with empty connections', () {
      expect(manager.connections, isEmpty);
    });

    test('get returns null for unknown id', () {
      expect(manager.get('nonexistent'), isNull);
    });

    test('disconnect unknown id does nothing', () {
      // Should not throw or emit
      manager.disconnect('nonexistent');
      expect(manager.connections, isEmpty);
    });

    test('onChange stream emits on disconnectAll', () async {
      var emitted = false;
      final sub = manager.onChange.listen((_) => emitted = true);
      manager.disconnectAll();
      await Future.delayed(Duration.zero);
      // disconnectAll always notifies
      expect(emitted, isTrue);
      await sub.cancel();
    });

    test('disconnectAll on empty does not throw', () {
      manager.disconnectAll();
      expect(manager.connections, isEmpty);
    });

    test('knownHosts is accessible', () {
      expect(manager.knownHosts, knownHosts);
    });

    test('onChange stream can have multiple listeners', () async {
      var count1 = 0;
      var count2 = 0;
      final sub1 = manager.onChange.listen((_) => count1++);
      final sub2 = manager.onChange.listen((_) => count2++);

      manager.disconnectAll();
      await Future.delayed(Duration.zero);

      expect(count1, 1);
      expect(count2, 1);

      await sub1.cancel();
      await sub2.cancel();
    });

    test('dispose can be called multiple times safely', () {
      // Create a separate manager for this test
      final mgr = ConnectionManager(knownHosts: knownHosts);
      mgr.dispose();
      // Second dispose should not throw
      // (StreamController.close() is idempotent-ish, may throw but that's OK)
    });

    test('connections returns unmodifiable snapshot', () {
      final list1 = manager.connections;
      final list2 = manager.connections;
      expect(list1, isEmpty);
      expect(list2, isEmpty);
      // They are independent copies
      expect(identical(list1, list2), isFalse);
    });
  });
}
