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
import 'package:letsflutssh/core/session/session.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
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

  // ── Idempotent no-op branches ────────────────────────────────────
  //
  // The `reconnect` / `disconnect` paths short-circuit when the id is
  // not in `_connections`. Both surfaces are reached from the UI (a
  // user tap on a stale tab, a hot-reload reflowing the tree) so the
  // early-return guards are spec, not defensive cruft.

  group('reconnect / disconnect short-circuit on unknown id', () {
    test(
      'reconnect with an id the notifier never tracked is a silent no-op',
      () {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final notifier = container.read(connectionsProvider.notifier);
        // Spec: the early `if (conn == null) return;` keeps the workspace
        // from crashing when a stray tab dispatches reconnect on a tab id
        // the notifier already forgot about.
        expect(() => notifier.reconnect('never-tracked'), returnsNormally);
        expect(notifier.connections, isEmpty);
      },
    );

    test(
      'disconnect with an id the notifier never tracked is a silent no-op',
      () {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final notifier = container.read(connectionsProvider.notifier);
        // Spec: the same early-return shape exists on disconnect — the
        // workspace's "Close" button on a stale row must not panic the
        // notifier when it fires after the row has already been removed
        // by a `ConnectionRemoved` bus event.
        expect(() => notifier.disconnect('never-tracked'), returnsNormally);
        expect(notifier.connections, isEmpty);
      },
    );

    test('reconnect with updatedConfig on unknown id stays a no-op', () {
      // The two-arg overload routes through the same early-return. A
      // user editing a stale session row + hitting Save & Connect after
      // an external close must not surface a NoSuchMethodError or leak
      // the updated config into the notifier's map.
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(connectionsProvider.notifier);
      const updated = SSHConfig(
        server: ServerAddress(host: 'h', user: 'u'),
      );
      expect(
        () => notifier.reconnect('gone', updatedConfig: updated),
        returnsNormally,
      );
      expect(notifier.connections, isEmpty);
    });
  });

  // ── revisionFor baseline ─────────────────────────────────────────

  group('revisionFor', () {
    test('returns 0 for any id the notifier has never bumped', () {
      // Spec: the per-id revision is the change-detection oracle for
      // `connectionRevisionProvider(id)`; consumers reading the
      // provider before any bus event for that id get a deterministic
      // baseline. Two distinct unknown ids return the same baseline.
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(connectionsProvider.notifier);
      expect(notifier.revisionFor('a'), 0);
      expect(notifier.revisionFor('b'), 0);
    });

    test('repeated reads stay at 0 — no implicit bump on read', () {
      // Spec: `revisionFor` is a pure lookup. Reading it must not
      // mutate the counter or every consumer would self-bump.
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(connectionsProvider.notifier);
      expect(notifier.revisionFor('x'), 0);
      expect(notifier.revisionFor('x'), 0);
      expect(notifier.revisionFor('x'), 0);
    });
  });

  // ── WebDAV / S3 immediate-return shape ───────────────────────────
  //
  // `connectWebDavAsync` / `connectS3Async` return the Connection
  // synchronously in `connecting` state with the kind tag set; the
  // unawaited `_doWebDavConnect` / `_doS3Connect` futures run async.
  // The Rust DB calls inside those futures throw `StateError("db not
  // initialized")` in the test harness — but the synchronous shape
  // is observable BEFORE that throw lands, so the public contract
  // ("workspace gets a tab in `connecting` state immediately") still
  // gets a unit-test assertion.

  group('connectWebDavAsync immediate-return shape', () {
    test(
      'returns a Connection tagged kind=webdav in connecting state',
      () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final notifier = container.read(connectionsProvider.notifier);
        final session = Session(
          id: 'wd-1',
          label: 'My WebDAV',
          kind: SessionKind.webdav,
          server: const ServerAddress(host: 'dav.example.com', user: 'alice'),
          auth: const SessionAuth(authType: AuthType.password),
        );
        // Spec: the WebDAV connect surface mirrors the SSH one — sync
        // return of a Connection in `connecting`, kind stamped before
        // the unawaited DB resolve runs. The workspace tab strip can
        // therefore render the WebDAV row on the same frame as the
        // user click.
        final conn = notifier.connectWebDavAsync(session);
        expect(conn.kind, SessionKind.webdav);
        expect(conn.state, SSHConnectionState.connecting);
        expect(conn.id, isNotEmpty);
        expect(conn.label, 'My WebDAV');
        expect(conn.sessionId, 'wd-1');
        expect(notifier.get(conn.id), same(conn));

        // Drain the in-flight DB resolve before the container disposes —
        // without a real DB the future settles into `disconnected` via
        // the `db not initialized` StateError caught inside
        // `_doWebDavConnect`.
        await conn.waitUntilReady().timeout(const Duration(seconds: 15));
      },
    );

    test(
      'label falls back to the host when the session label is empty',
      () async {
        // Spec: `connectWebDavAsync` uses `session.label.isEmpty ?
        // session.host : session.label` so a label-less import row
        // still surfaces a meaningful workspace tab title.
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final notifier = container.read(connectionsProvider.notifier);
        final session = Session(
          id: 'wd-2',
          label: '',
          kind: SessionKind.webdav,
          server: const ServerAddress(host: 'dav.example.com', user: 'alice'),
          auth: const SessionAuth(authType: AuthType.password),
        );
        final conn = notifier.connectWebDavAsync(session);
        expect(conn.label, 'dav.example.com');

        await conn.waitUntilReady().timeout(const Duration(seconds: 15));
      },
    );
  });

  group('connectS3Async immediate-return shape', () {
    test('returns a Connection tagged kind=s3 in connecting state', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(connectionsProvider.notifier);
      final session = Session(
        id: 's3-1',
        label: 'Logs Bucket',
        kind: SessionKind.s3,
        server: const ServerAddress(host: 's3.amazonaws.com', user: 'AKIA'),
        auth: const SessionAuth(authType: AuthType.password),
      );
      // Spec: same as WebDAV — the workspace tab shows a "connecting"
      // S3 row on the same frame as the user click; kind stays s3 so
      // the file-browser dispatcher knows to read `s3InitialDir` later.
      final conn = notifier.connectS3Async(session);
      expect(conn.kind, SessionKind.s3);
      expect(conn.state, SSHConnectionState.connecting);
      expect(conn.id, isNotEmpty);
      expect(conn.label, 'Logs Bucket');
      expect(conn.sessionId, 's3-1');
      expect(notifier.get(conn.id), same(conn));

      await conn.waitUntilReady().timeout(const Duration(seconds: 15));
    });

    test(
      'label falls back to the host when the session label is empty',
      () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final notifier = container.read(connectionsProvider.notifier);
        final session = Session(
          id: 's3-2',
          label: '',
          kind: SessionKind.s3,
          server: const ServerAddress(host: 's3.amazonaws.com', user: 'AKIA'),
          auth: const SessionAuth(authType: AuthType.password),
        );
        final conn = notifier.connectS3Async(session);
        expect(conn.label, 's3.amazonaws.com');

        await conn.waitUntilReady().timeout(const Duration(seconds: 15));
      },
    );
  });

  group('deferred to integration', () {
    test(
      'reconnect with a tracked id tears the transport down and re-dispatches',
      () {},
      skip:
          'covered by integration: needs a russh fixture so the live transport '
          'adopts; the unit harness has no transport to tear down. Verified by '
          'test/integration/session_connect_test.dart.',
    );

    test(
      'a successful _doWebDavConnect / _doS3Connect transitions state to connected',
      () {},
      skip:
          'covered by integration: needs a live WebDAV / S3 fixture so the '
          'Rust connect future resolves with a real handle; the unit harness '
          'throws `db not initialized` on the synchronous DB row resolve.',
    );

    test(
      '_handleBusEvent fans bus topics into per-id revision bumps + list rebuilds',
      () {},
      skip:
          'covered by integration: the Notifier subscribes to AppBus on '
          'build(); driving a bus event needs the Rust bus actor running, '
          'which the unit harness skips via the StateError fallback. '
          'Verified by test/integration/session_connect_test.dart.',
    );
  });
}
