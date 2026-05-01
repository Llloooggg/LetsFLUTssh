import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/connection/connections_notifier.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/providers/connection_provider.dart';
import 'package:letsflutssh/providers/known_hosts_provider.dart';

void main() {
  group('connection providers', () {
    test('knownHostsProvider exposes a KnownHostsNotifier', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(knownHostsProvider.notifier);
      expect(notifier, isA<KnownHostsNotifier>());
      expect(notifier.entries, isEmpty);
    });

    test('connectionsProvider exposes a ConnectionsNotifier', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(connectionsProvider.notifier);
      expect(notifier, isA<ConnectionsNotifier>());
      expect(notifier.connections, isEmpty);
    });

    test('connectionsProvider yields empty list initially', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      // NotifierProvider returns the list directly — no AsyncValue
      // wrapping. The Notifier's build() seeds the state from the
      // empty `_connections` map.
      expect(container.read(connectionsProvider), isEmpty);
    });

    test(
      'connectionsProvider updates when connection added',
      () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        // Listen to start the build cycle.
        container.listen(connectionsProvider, (_, _) {});
        await Future.delayed(const Duration(milliseconds: 100));

        // Add a connection via the notifier — the connectAsync side
        // effect calls `_notify()` which rebuilds state.
        final notifier = container.read(connectionsProvider.notifier);
        notifier.connectAsync(
          const SSHConfig(
            server: ServerAddress(host: 'test', user: 'u'),
          ),
          label: 'Test',
        );

        await Future.delayed(const Duration(milliseconds: 200));

        final connections = container.read(connectionsProvider);
        expect(connections, isNotEmpty);
        expect(connections.first.label, 'Test');
      },
      // requireFrbLoaded alone isn't enough — connectAsync also
      // calls `connectionPrepareAuth` which needs the Rust DB
      // initialised + SecretStore staging. Re-enabling here would
      // need a `db_init` call against a tempdir + SecretStore probe-
      // key seed before the connect. Move to integration_test/ when
      // that scaffolding lands. Investigated 2026-05; the original
      // "no FRB native lib" rationale was incomplete.
      skip:
          'connectAsync needs db_init + SecretStore staging in addition '
          'to FRB; integration_test/ is the right home.',
    );

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
      const a = ConnectionSummary(
        connectedSessionIds: {'s1', 's2'},
        connectingSessionIds: {'s3'},
        connectedTotal: 2,
        connectingTotal: 1,
      );
      const b = ConnectionSummary(
        connectedSessionIds: {'s2', 's1'},
        connectingSessionIds: {'s3'},
        connectedTotal: 2,
        connectingTotal: 1,
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('ConnectionSummary distinguishes different state buckets', () {
      const connected = ConnectionSummary(
        connectedSessionIds: {'s1'},
        connectingSessionIds: {},
        connectedTotal: 1,
        connectingTotal: 0,
      );
      const connecting = ConnectionSummary(
        connectedSessionIds: {},
        connectingSessionIds: {'s1'},
        connectedTotal: 0,
        connectingTotal: 1,
      );
      expect(connected, isNot(equals(connecting)));
    });
  });
}
