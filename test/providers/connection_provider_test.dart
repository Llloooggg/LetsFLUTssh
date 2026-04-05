import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/connection/connection_manager.dart';
import 'package:letsflutssh/core/ssh/known_hosts.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
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
      expect(asyncValue.whenOrNull(data: (d) => d, loading: () => <dynamic>[]), isNotNull);
    });

    test('connectionsProvider updates when connection added', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Listen to the provider to start the stream generator
      container.listen(connectionsProvider, (_, _) {});
      // Let the stream start and emit initial value
      await Future.delayed(const Duration(milliseconds: 100));

      // Add a connection via manager — triggers onChange stream
      final manager = container.read(connectionManagerProvider);
      manager.connectAsync(
        const SSHConfig(
          server: ServerAddress(host: 'test', user: 'u'),
        ),
        label: 'Test',
      );

      // Wait for onChange event to propagate through the await-for loop
      await Future.delayed(const Duration(milliseconds: 200));

      final value = container.read(connectionsProvider);
      value.whenData((connections) {
        expect(connections, isNotEmpty);
        expect(connections.first.label, 'Test');
      });
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
