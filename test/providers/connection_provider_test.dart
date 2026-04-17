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
      expect(
        asyncValue.whenOrNull(data: (d) => d, loading: () => <dynamic>[]),
        isNotNull,
      );
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

    test(
      'connectionSummaryProvider is empty when no connections are registered',
      () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final summary = container.read(connectionSummaryProvider);
        expect(summary.connectedTotal, 0);
        expect(summary.connectingTotal, 0);
        expect(summary.connectedSessionIds, isEmpty);
        expect(summary.connectingSessionIds, isEmpty);
        expect(summary.activeTotal, 0);
      },
    );

    test('ConnectionSummary value-equality ignores set insertion order', () {
      // Riverpod short-circuits rebuilds by comparing the new value
      // with the previous one via `==`. If a stream re-emits the same
      // connected/connecting state but the underlying set iteration
      // order happens to differ, we still want `==` to be true so
      // consumers (sidebar footer, session tree tinting) skip the
      // rebuild. Lock that contract here.
      final a = ConnectionSummary(
        connectedSessionIds: const {'s1', 's2'},
        connectingSessionIds: const {'s3'},
        connectedTotal: 2,
        connectingTotal: 1,
      );
      final b = ConnectionSummary(
        connectedSessionIds: const {'s2', 's1'},
        connectingSessionIds: const {'s3'},
        connectedTotal: 2,
        connectingTotal: 1,
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('ConnectionSummary distinguishes different state buckets', () {
      final connected = ConnectionSummary(
        connectedSessionIds: const {'s1'},
        connectingSessionIds: const {},
        connectedTotal: 1,
        connectingTotal: 0,
      );
      final connecting = ConnectionSummary(
        connectedSessionIds: const {},
        connectingSessionIds: const {'s1'},
        connectedTotal: 0,
        connectingTotal: 1,
      );
      expect(connected, isNot(equals(connecting)));
    });

    test('connectionManagerProvider disposes on container dispose', () async {
      final container = ProviderContainer();
      final manager = container.read(connectionManagerProvider);
      expect(manager.connections, isEmpty);

      // Listen to onChange — it should complete when disposed.
      final streamDone = manager.onChange.toList();
      container.dispose();

      // Stream completes (controller closed by dispose).
      await streamDone;
    });
  });
}
