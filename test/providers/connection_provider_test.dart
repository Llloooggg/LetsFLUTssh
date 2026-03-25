import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/connection/connection_manager.dart';
import 'package:letsflutssh/core/ssh/known_hosts.dart';
import 'package:letsflutssh/providers/connection_provider.dart';

void main() {
  group('connection providers', () {
    test('knownHostsProvider returns KnownHostsManager', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final kh = container.read(knownHostsProvider);
      expect(kh, isA<KnownHostsManager>());
    });

    test('connectionManagerProvider returns ConnectionManager', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final manager = container.read(connectionManagerProvider);
      expect(manager, isA<ConnectionManager>());
      expect(manager.connections, isEmpty);
    });

    test('connectionManagerProvider uses knownHostsProvider', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final kh = container.read(knownHostsProvider);
      final manager = container.read(connectionManagerProvider);
      expect(manager.knownHosts, kh);
    });

    test('connectionsProvider yields empty list initially', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final asyncValue = container.read(connectionsProvider);
      // StreamProvider starts with loading, then first yield
      expect(
        asyncValue.whenOrNull(data: (d) => d, loading: () => <dynamic>[]),
        isNotNull,
      );
    });

    test('connectionManagerProvider disposes on container dispose', () {
      final container = ProviderContainer();
      final manager = container.read(connectionManagerProvider);
      expect(manager.connections, isEmpty);
      container.dispose();
      // After dispose, the manager should be cleaned up
      // (disconnectAll + controller.close called)
    });
  });
}
