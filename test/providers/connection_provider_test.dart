import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/connection/connection.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/providers/connections_notifier.dart';
import 'package:letsflutssh/providers/connection_provider.dart';

void main() {
  group('connection providers', () {
    test('knownHostsProvider yields an empty map before the stream emits', () {
      final container = ProviderContainer(
        overrides: [
          // The live `knownHostsStreamProvider` reads through FRB.
          // flutter_test has no native bridge — override with a
          // never-emitting stream so the derived sync Provider falls
          // back to its `const {}` default deterministically.
          knownHostsStreamProvider.overrideWith(
            (_) => const Stream<Map<String, String>>.empty(),
          ),
        ],
      );
      addTearDown(container.dispose);
      expect(container.read(knownHostsProvider), isEmpty);
    });

    test('connectionActiveCountProvider seeds 0 before any event', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      // The listen-based forwarder seeds 0 synchronously and subscribes
      // to the connection bus topic; with no native bridge the bus
      // never emits, so the stream stays at the seed. (The count-update
      // path needs a real `ConnectionActiveCountChanged`, exercised by
      // the connection integration suite.)
      container.listen(
        connectionActiveCountProvider,
        (_, _) {},
        fireImmediately: true,
      );
      expect(await container.read(connectionActiveCountProvider.future), 0);
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

    test('connectionRevisionProvider returns 0 for unknown ids', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      // Per-id revision is 0 until the first bus event for that id;
      // consumers reading the provider before any state transition
      // get a deterministic baseline rather than null.
      expect(container.read(connectionRevisionProvider('never-seen')), 0);
    });

    test('connectionByIdProvider returns null for an unknown id', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      // The family is the fine-grained surface — looking up an id
      // the notifier doesn't track must collapse to null cleanly so
      // a row can render the empty state without an exception.
      expect(container.read(connectionByIdProvider('never-seen')), isNull);
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

    test('connectionSummaryProvider buckets connected / connecting sessions '
        'and includes their session ids', () {
      // Drive the projection with a seeded `List<Connection>` via the
      // [StaticConnectionsNotifier] override seam. This exercises the
      // `if (c.isConnected) { … sid != null }` branch (line 245) and
      // the `else if (c.isConnecting) { … sid != null }` branch
      // (line 249) without needing a real bus subscription.
      final connectedWithSid = Connection(
        id: 'c1',
        label: 'A',
        sshConfig: const SSHConfig(
          server: ServerAddress(host: 'h1', user: 'u'),
        ),
        sessionId: 's1',
        state: SSHConnectionState.connected,
      );
      final connectedNoSid = Connection(
        id: 'c2',
        label: 'Quick',
        sshConfig: const SSHConfig(
          server: ServerAddress(host: 'h2', user: 'u'),
        ),
        state: SSHConnectionState.connected,
      );
      final connectingWithSid = Connection(
        id: 'c3',
        label: 'B',
        sshConfig: const SSHConfig(
          server: ServerAddress(host: 'h3', user: 'u'),
        ),
        sessionId: 's3',
        state: SSHConnectionState.connecting,
      );
      final disconnected = Connection(
        id: 'c4',
        label: 'C',
        sshConfig: const SSHConfig(
          server: ServerAddress(host: 'h4', user: 'u'),
        ),
        sessionId: 's4',
        state: SSHConnectionState.disconnected,
      );

      final container = ProviderContainer(
        overrides: [
          connectionsProvider.overrideWith(
            () => StaticConnectionsNotifier([
              connectedWithSid,
              connectedNoSid,
              connectingWithSid,
              disconnected,
            ]),
          ),
        ],
      );
      addTearDown(container.dispose);

      final summary = container.read(connectionSummaryProvider);
      // Connected bucket — both `c1` (sid s1) and `c2` (no sid) count
      // toward `connectedTotal`, but only s1 lands in the id set.
      expect(summary.connectedTotal, 2);
      expect(summary.connectedSessionIds, {'s1'});
      // Connecting bucket — `c3` contributes a sid; the disconnected
      // entry is dropped from both totals.
      expect(summary.connectingTotal, 1);
      expect(summary.connectingSessionIds, {'s3'});
      expect(summary.activeTotal, 3);
    });
  });
}
