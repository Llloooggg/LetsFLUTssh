/// Coverage for [ConnectionsNotifier] public surface that exercises
/// without a live SSH transport.
///
/// `connectAsync` / `reconnect` / `disconnect` need a real russh
/// transport to mean anything; the integration suite
/// (`session_connect_test`, `bastion_proxyjump_test`,
/// `transfer_queue_test`, `auto_lock_detector_test`) drives those
/// through end-to-end. What lives here is the Dart-side wrapper
/// contract every UI provider reads from: empty initial state,
/// the read-side `connections` / `get()` accessors, and
/// `notifyStateChanged()` triggering a rebuild without a transport
/// in the picture.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/connection/connection.dart';
import 'package:letsflutssh/providers/connection_provider.dart';

import '../helpers/frb_bootstrap.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(requireFrbLoaded);

  group('initial state', () {
    test('connections list is empty on a fresh container', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final list = container.read(connectionsProvider);
      expect(list, isEmpty);
    });

    test('connections list is the same instance across reads', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final a = container.read(connectionsProvider);
      final b = container.read(connectionsProvider);
      // const empty list — both reads land on the same canonical
      // empty `[]` (the Notifier returns `const []` until a
      // connection lands or notifyStateChanged is triggered).
      expect(identical(a, b), isTrue);
    });
  });

  group('read-side accessors', () {
    test('notifier.connections is empty without an active connection', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(connectionsProvider.notifier);
      expect(notifier.connections, isEmpty);
    });

    test('notifier.get(unknown id) returns null', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(connectionsProvider.notifier);
      expect(notifier.get('does-not-exist'), isNull);
    });

    test('notifier.connections returns a List<Connection>', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(connectionsProvider.notifier);
      expect(notifier.connections, isA<List<Connection>>());
    });
  });

  group('notifyStateChanged', () {
    test('does not throw on an empty notifier', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(connectionsProvider.notifier);
      expect(notifier.notifyStateChanged, returnsNormally);
    });

    test('repeated calls remain safe', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(connectionsProvider.notifier);
      notifier.notifyStateChanged();
      notifier.notifyStateChanged();
      notifier.notifyStateChanged();
      // No state mutation happens (nothing to fan out from), but the
      // method must remain callable as a no-op rebuild trigger.
    });
  });

  group('container disposal', () {
    test('disposing the container does not throw', () {
      final container = ProviderContainer();
      // Force the notifier to build by reading once.
      container.read(connectionsProvider);
      // Dispose triggers the `ref.onDispose` cleanup chain
      // (_disposed flag, bus subscription cancel, _disconnectAll).
      // With no connections in the map, the chain runs as a no-op.
      expect(container.dispose, returnsNormally);
    });
  });
}
