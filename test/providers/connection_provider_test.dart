import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/connection/connections_notifier.dart';
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
  });
}
