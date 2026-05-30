import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/connection/connection.dart';
import 'package:letsflutssh/core/session/session.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/features/terminal/terminal_pane.dart';
import 'package:letsflutssh/features/terminal/terminal_tab.dart';
import 'package:letsflutssh/features/terminal/tiling_view.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/providers/config_provider.dart';
import 'package:letsflutssh/providers/connection_provider.dart';
import 'package:letsflutssh/providers/connections_notifier.dart';
import 'package:letsflutssh/providers/focused_pane_provider.dart';

import '../../helpers/fake_session_notifier.dart';
import '../../helpers/frb_bootstrap.dart';
import '../../helpers/test_notifiers.dart';

/// Static stand-in for [ConnectionsNotifier]. The tab's [reconnect] path
/// calls `manager.reconnect(...)` on the real notifier, which runs the
/// full FRB cascade; the stub records the call without touching FRB so
/// the test can assert the delegation contract.
class _RecordingConnectionsNotifier extends ConnectionsNotifier {
  _RecordingConnectionsNotifier(this._conns);
  final List<Connection> _conns;
  final List<({String id, SSHConfig? config})> reconnectCalls = [];

  @override
  List<Connection> build() => _conns;

  @override
  List<Connection> get connections => _conns;

  @override
  void reconnect(String id, {SSHConfig? updatedConfig}) {
    reconnectCalls.add((id: id, config: updatedConfig));
  }
}

Connection _makeConnectingConnection({
  String id = 'tab-conn',
  String? sessionId,
}) {
  return Connection(
    id: id,
    label: 'tab',
    sessionId: sessionId,
    sshConfig: const SSHConfig(
      server: ServerAddress(host: '127.0.0.1', port: 22, user: 'u'),
      auth: SshAuth(),
    ),
    state: SSHConnectionState.connecting,
  );
}

Widget _host(
  Connection conn,
  ProviderContainer container, {
  String tabId = 'tab-1',
  bool isActive = true,
  ReconnectFactory? reconnectFactory,
  Key? tabKey,
}) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      localizationsDelegates: S.localizationsDelegates,
      supportedLocales: S.supportedLocales,
      home: Scaffold(
        body: TerminalTab(
          key: tabKey,
          tabId: tabId,
          connection: conn,
          isActive: isActive,
          reconnectFactory: reconnectFactory,
        ),
      ),
    ),
  );
}

ProviderContainer _container(
  Connection conn, {
  _RecordingConnectionsNotifier? manager,
  FakeSessionNotifier? sessions,
}) {
  return ProviderContainer(
    overrides: [
      if (sessions != null) ...sessions.overrides(),
      connectionsProvider.overrideWith(
        () => manager ?? _RecordingConnectionsNotifier([conn]),
      ),
      configProvider.overrideWith(TestConfigNotifier.new),
    ],
  );
}

void main() {
  // `TerminalTab` mounts a `TilingView` → `TerminalPane`, which opens a
  // real Rust `TerminalReplay` to render the connect-progress view. The
  // native FRB library must therefore be available, mirroring the
  // sibling `terminal_pane_test.dart`.
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(requireFrbLoaded);

  testWidgets(
    'tab mounts with a single TilingView wrapping the supplied connection — '
    'the initial leaf is wired through `paneConnections`',
    (tester) async {
      // Spec: a freshly-created `TerminalTab` produces exactly one leaf
      // whose connection is the one the tab was constructed with. The
      // leaf id (random uuid) is unknown to the test, so we assert the
      // shape: one `TilingView`, one `TerminalPane`, both wrapping the
      // expected connection.
      final conn = _makeConnectingConnection();
      addTearDown(conn.dispose);
      final container = _container(conn);
      addTearDown(container.dispose);

      await tester.pumpWidget(_host(conn, container));
      await tester.pump();

      expect(find.byType(TilingView), findsOneWidget);
      expect(find.byType(TerminalPane), findsOneWidget);

      final pane = tester.widget<TerminalPane>(find.byType(TerminalPane));
      expect(
        identical(pane.connection, conn),
        isTrue,
        reason:
            'The initial leaf must bind to the connection the tab was '
            'constructed with — the tab seeds `_paneConnections[leaf.id]` '
            'in `initState`.',
      );
    },
  );

  testWidgets('after the first frame, the focused pane id is published to '
      '`focusedPaneProvider(tabId)` so cross-subtree consumers can read it', (
    tester,
  ) async {
    // Spec: `initState` schedules a post-frame callback that writes the
    // initial leaf id into the family-keyed provider; without it, the
    // workspace's record button (in a sibling subtree) cannot find the
    // pane it should toggle recording on.
    const tabId = 'tab-with-focus';
    final conn = _makeConnectingConnection();
    addTearDown(conn.dispose);
    final container = _container(conn);
    addTearDown(container.dispose);

    await tester.pumpWidget(_host(conn, container, tabId: tabId));
    // First pump mounts; the post-frame callback queues the provider
    // write. A second pump drains the microtask queue so the read
    // observes the new value.
    await tester.pump();
    await tester.pump();

    final focused = container.read(focusedPaneProvider(tabId));
    expect(
      focused,
      isNotNull,
      reason:
          'The post-frame callback in `initState` must publish the '
          'initial leaf id to the focused-pane family provider for the '
          'tab so the workspace connection bar finds the right pane.',
    );
  });

  testWidgets(
    'reconnect() with an injected factory resets the pane tree to a single '
    'leaf and routes through the factory instead of the real notifier',
    (tester) async {
      // Spec: a non-null `reconnectFactory` bypasses `ConnectionsNotifier`
      // entirely — the factory runs, the pane tree resets, and the
      // notifier's `reconnect` is never called. The factory's existence
      // is the test seam that lets us drive the reconnect cascade without
      // a real SSH connect.
      final conn = _makeConnectingConnection();
      addTearDown(conn.dispose);
      final manager = _RecordingConnectionsNotifier([conn]);
      final container = _container(conn, manager: manager);
      addTearDown(container.dispose);

      var factoryCalls = 0;
      Future<void> factory(Connection c) async {
        factoryCalls++;
      }

      final tabKey = GlobalKey<TerminalTabState>();
      await tester.pumpWidget(
        _host(conn, container, tabKey: tabKey, reconnectFactory: factory),
      );
      await tester.pump();

      tabKey.currentState!.reconnect();
      await tester.pumpAndSettle();

      expect(
        factoryCalls,
        1,
        reason:
            'The injected factory must run exactly once per reconnect, '
            'replacing the real SSH cascade.',
      );
      expect(
        manager.reconnectCalls,
        isEmpty,
        reason:
            'A non-null `reconnectFactory` must short-circuit the path that '
            'delegates to `ConnectionsNotifier.reconnect` — otherwise tests '
            'cannot avoid the FRB cascade.',
      );
      // Tree reset to a single leaf — exactly one pane after reconnect.
      expect(find.byType(TerminalPane), findsOneWidget);
    },
  );

  testWidgets('reconnect() without a factory delegates to '
      '`ConnectionsNotifier.reconnect` with the connection id', (tester) async {
    // Spec: without the factory seam, the tab calls
    // `manager.reconnect(connection.id, ...)`. The recorded call lets
    // us assert the id-passing contract — `_refreshConfig` may pass
    // `updatedConfig: null` (no session in store), which is fine.
    final conn = _makeConnectingConnection();
    addTearDown(conn.dispose);
    final manager = _RecordingConnectionsNotifier([conn]);
    final container = _container(conn, manager: manager);
    addTearDown(container.dispose);

    final tabKey = GlobalKey<TerminalTabState>();
    await tester.pumpWidget(_host(conn, container, tabKey: tabKey));
    await tester.pump();

    tabKey.currentState!.reconnect();
    await tester.pump();

    expect(manager.reconnectCalls, hasLength(1));
    expect(manager.reconnectCalls.single.id, conn.id);
  });

  testWidgets(
    'reconnect() resets the pane tree even when the factory branch is taken — '
    'after reconnect the previously focused leaf id is no longer valid',
    (tester) async {
      // Spec: `reconnect` builds a fresh `LeafNode` and writes its id to
      // both `_focusedPaneId` and the focused-pane provider, so any prior
      // leaf id is gone. We don't know the new id (uuid) but we can
      // assert the provider got rewritten (the new id is non-null and
      // the tree still renders exactly one pane).
      const tabId = 'tab-reset';
      final conn = _makeConnectingConnection();
      addTearDown(conn.dispose);
      final manager = _RecordingConnectionsNotifier([conn]);
      final container = _container(conn, manager: manager);
      addTearDown(container.dispose);

      Future<void> factory(Connection c) async {}

      final tabKey = GlobalKey<TerminalTabState>();
      await tester.pumpWidget(
        _host(
          conn,
          container,
          tabId: tabId,
          tabKey: tabKey,
          reconnectFactory: factory,
        ),
      );
      await tester.pump();
      await tester.pump();
      final beforeId = container.read(focusedPaneProvider(tabId));
      expect(beforeId, isNotNull);

      tabKey.currentState!.reconnect();
      await tester.pumpAndSettle();

      final afterId = container.read(focusedPaneProvider(tabId));
      expect(
        afterId,
        isNotNull,
        reason: 'Reconnect must publish a non-null leaf id, not clear it.',
      );
      expect(
        afterId,
        isNot(equals(beforeId)),
        reason:
            'Reconnect builds a fresh `LeafNode` — its id must differ from '
            'the prior leaf so the new TerminalPane subscribes to the '
            'reset connection from a clean mount.',
      );
      expect(find.byType(TerminalPane), findsOneWidget);
    },
  );

  testWidgets(
    'reconnect() with a throwing factory still completes the connection '
    'ready future so awaiters are not parked forever',
    (tester) async {
      // Spec: `_runReconnectFactory` wraps the factory call in a
      // try/catch/finally — the finally branch calls `conn.completeReady`
      // unconditionally so even a factory that throws (e.g. transient
      // network glitch) does not deadlock callers awaiting
      // `conn.waitUntilReady`.
      final conn = _makeConnectingConnection();
      // Reset the connection's ready completer before the test so the
      // assertion checks the new completer the reconnect path mints.
      conn.resetForReconnect();
      addTearDown(conn.dispose);
      final manager = _RecordingConnectionsNotifier([conn]);
      final container = _container(conn, manager: manager);
      addTearDown(container.dispose);

      Future<void> factory(Connection c) async {
        throw Exception('factory blew up');
      }

      final tabKey = GlobalKey<TerminalTabState>();
      await tester.pumpWidget(
        _host(conn, container, tabKey: tabKey, reconnectFactory: factory),
      );
      await tester.pump();

      tabKey.currentState!.reconnect();
      // Drain the factory's microtask queue + the finally block.
      await tester.pumpAndSettle();

      // `ready` resolves once the connect attempt finishes (success or
      // failure). A thrown factory must still drive the resolution.
      var resolved = false;
      unawaited(conn.ready.then((_) => resolved = true));
      await tester.pump();
      expect(
        resolved,
        isTrue,
        reason:
            'The finally branch in `_runReconnectFactory` must complete '
            'the ready future on factory failure so consumers do not park '
            'on `waitUntilReady` forever.',
      );
      expect(conn.state, SSHConnectionState.disconnected);
      expect(conn.connectionError, isNotNull);
    },
  );

  testWidgets(
    'tab forwards its `isActive` flag straight through to the TilingView so '
    'the underlying pane sees the correct foreground state',
    (tester) async {
      // Spec: `isActive` is the contract that drives keyboard-focus
      // re-grab on tab switch — `TerminalTab` only passes it through;
      // the test pins the wiring so a refactor cannot silently flip it.
      final conn = _makeConnectingConnection();
      addTearDown(conn.dispose);
      final container = _container(conn);
      addTearDown(container.dispose);

      await tester.pumpWidget(_host(conn, container, isActive: false));
      await tester.pump();

      final tiling = tester.widget<TilingView>(find.byType(TilingView));
      expect(
        tiling.isActiveTab,
        isFalse,
        reason:
            'A backgrounded tab must propagate `isActive: false` down to '
            'the tiling view so the underlying pane drops keyboard focus.',
      );
    },
  );

  testWidgets(
    'flipping `isActive` on widget update is forwarded straight through to '
    'the TilingView — the tab must re-render with the new foreground flag',
    (tester) async {
      // Spec: parent rebuilds with `isActive: true → false` (user
      // switched away from this tab); the tab is a pass-through and
      // must propagate the new flag without resetting its tree or
      // dropping the focused-pane id. Pins `build()` reads from
      // `widget.isActive` rather than a stale field captured at
      // initState time.
      const tabId = 'tab-flip';
      final conn = _makeConnectingConnection();
      addTearDown(conn.dispose);
      final container = _container(conn);
      addTearDown(container.dispose);

      await tester.pumpWidget(_host(conn, container, tabId: tabId));
      await tester.pump();
      await tester.pump();

      expect(
        tester.widget<TilingView>(find.byType(TilingView)).isActiveTab,
        isTrue,
      );
      final beforeId = container.read(focusedPaneProvider(tabId));

      // Rebuild with the same key/conn but a new `isActive` flag.
      await tester.pumpWidget(
        _host(conn, container, tabId: tabId, isActive: false),
      );
      await tester.pump();

      expect(
        tester.widget<TilingView>(find.byType(TilingView)).isActiveTab,
        isFalse,
        reason:
            'A widget rebuild that flips `isActive` must propagate the new '
            'value down to the TilingView on the next build.',
      );
      // Focused-pane id is unchanged — the rebuild is a flag flip, not
      // a remount, so the leaf id the workspace bar tracks persists.
      expect(
        container.read(focusedPaneProvider(tabId)),
        equals(beforeId),
        reason:
            'A flag-only rebuild must not rotate the leaf id — the '
            'focused-pane provider must keep pointing at the same pane.',
      );
    },
  );

  testWidgets(
    'reconnect() called twice in a row runs the factory twice and the second '
    'call re-resets the tree to a fresh single-leaf root',
    (tester) async {
      // Spec: each `reconnect()` mints a fresh `LeafNode` and routes
      // through the factory once. Two back-to-back calls must each
      // produce their own factory invocation and end with exactly one
      // leaf — no leaks of the prior leaf, no skipped factory runs.
      const tabId = 'tab-double-reconnect';
      final conn = _makeConnectingConnection();
      addTearDown(conn.dispose);
      final manager = _RecordingConnectionsNotifier([conn]);
      final container = _container(conn, manager: manager);
      addTearDown(container.dispose);

      var factoryCalls = 0;
      Future<void> factory(Connection c) async {
        factoryCalls++;
      }

      final tabKey = GlobalKey<TerminalTabState>();
      await tester.pumpWidget(
        _host(
          conn,
          container,
          tabId: tabId,
          tabKey: tabKey,
          reconnectFactory: factory,
        ),
      );
      await tester.pump();
      await tester.pump();
      final firstLeafId = container.read(focusedPaneProvider(tabId));

      tabKey.currentState!.reconnect();
      await tester.pumpAndSettle();
      final secondLeafId = container.read(focusedPaneProvider(tabId));

      tabKey.currentState!.reconnect();
      await tester.pumpAndSettle();
      final thirdLeafId = container.read(focusedPaneProvider(tabId));

      expect(
        factoryCalls,
        2,
        reason:
            'Each reconnect call must invoke the factory exactly once — '
            'no de-duplication, no skipped runs.',
      );
      expect(secondLeafId, isNot(equals(firstLeafId)));
      expect(thirdLeafId, isNot(equals(secondLeafId)));
      expect(find.byType(TerminalPane), findsOneWidget);
    },
  );

  testWidgets(
    'tab unmounted mid-reconnect: the pending factory future resolves on the '
    'connection without crashing the disposed state — the finally branch in '
    '_runReconnectFactory must complete the ready future even when the host '
    'widget is gone',
    (tester) async {
      // Spec: `_runReconnectFactory` is a `Future<void>` that the tab
      // fires-and-forgets. If the tab disposes before the factory
      // resolves, the finally branch still has to call
      // `conn.completeReady()` so external awaiters of `conn.ready`
      // unblock. The widget's own `mounted` guard is internal — the
      // contract is "ready resolves on factory completion regardless
      // of host widget lifecycle".
      final conn = _makeConnectingConnection();
      conn.resetForReconnect();
      // The host widget below is unmounted mid-test; the connection
      // outlives it, so dispose explicitly at the end.
      addTearDown(conn.dispose);
      final manager = _RecordingConnectionsNotifier([conn]);
      final container = _container(conn, manager: manager);
      addTearDown(container.dispose);

      final completer = Completer<void>();
      Future<void> factory(Connection c) async {
        await completer.future;
      }

      final tabKey = GlobalKey<TerminalTabState>();
      await tester.pumpWidget(
        _host(conn, container, tabKey: tabKey, reconnectFactory: factory),
      );
      await tester.pump();

      tabKey.currentState!.reconnect();
      // Factory is parked on the completer; pump once so the state
      // machine reaches the await.
      await tester.pump();

      // Unmount the tab while the factory is still pending. Pumping a
      // bare SizedBox tears down the entire MaterialApp / Scaffold
      // subtree.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      // Release the parked factory — finally branch runs on a now-
      // disposed widget. The contract is: no crash, ready resolves.
      completer.complete();
      await tester.pump();
      await tester.pump();

      var resolved = false;
      unawaited(conn.ready.then((_) => resolved = true));
      await tester.pump();
      expect(
        resolved,
        isTrue,
        reason:
            'The finally branch in `_runReconnectFactory` must complete '
            'the connection ready future even when the host widget has '
            'been unmounted mid-flight.',
      );
      expect(conn.state, SSHConnectionState.connected);
    },
  );

  testWidgets(
    'reconnect() with sessionId but no matching session in the workspace '
    'falls back to the cached SSHConfig — no FRB call, no crash',
    (tester) async {
      // Spec: `_refreshConfig` looks the connection's `sessionId` up
      // in the session workspace. When `indexWhere` returns -1 (no
      // matching session), the branch logs and returns
      // `widget.connection.sshConfig` unchanged. With an empty
      // workspace this branch is the only reachable one — the
      // reconnect must still complete normally and the factory must
      // still observe the cached SSHConfig the tab was constructed
      // with (no clobber from a stale store read).
      const cachedHost = '10.0.0.5';
      final conn = Connection(
        id: 'conn-stale-session',
        label: 'tab',
        sessionId: 'session-not-in-store',
        sshConfig: const SSHConfig(
          server: ServerAddress(host: cachedHost, port: 22, user: 'u'),
          auth: SshAuth(),
        ),
        state: SSHConnectionState.connecting,
      );
      addTearDown(conn.dispose);
      final sessions = FakeSessionNotifier(sessions: const <Session>[]);
      addTearDown(sessions.dispose);
      final manager = _RecordingConnectionsNotifier([conn]);
      final container = _container(conn, manager: manager, sessions: sessions);
      addTearDown(container.dispose);

      SSHConfig? observed;
      Future<void> factory(Connection c) async {
        observed = c.sshConfig;
      }

      final tabKey = GlobalKey<TerminalTabState>();
      await tester.pumpWidget(
        _host(conn, container, tabKey: tabKey, reconnectFactory: factory),
      );
      await tester.pump();

      tabKey.currentState!.reconnect();
      await tester.pumpAndSettle();

      // Stale-session branch hands the factory the cached SSHConfig.
      expect(
        observed?.server.host,
        cachedHost,
        reason:
            'When the session id is not in the workspace, _refreshConfig '
            'must fall back to the cached SSHConfig on the connection.',
      );
    },
  );

  testWidgets(
    'reconnect() with sessionId matching a workspace session adopts the '
    'fresh SSHConfig — the connection picks up edits the user made in '
    'the session editor',
    (tester) async {
      // Spec: `_refreshConfig` projects the matching `Session` back
      // through `toSSHConfig()` and assigns the result to
      // `widget.connection.sshConfig` before the reconnect factory
      // runs. This is how an edit to the saved session (e.g.
      // different host or user) takes effect on the next reconnect
      // without re-creating the Connection.
      const stalHost = '127.0.0.1';
      const freshHost = '192.0.2.99';
      const freshUser = 'rotated-user';
      const sessionId = 'session-fresh';
      final conn = Connection(
        id: 'conn-fresh-session',
        label: 'tab',
        sessionId: sessionId,
        sshConfig: const SSHConfig(
          server: ServerAddress(host: stalHost, port: 22, user: 'u'),
          auth: SshAuth(),
        ),
        state: SSHConnectionState.connecting,
      );
      addTearDown(conn.dispose);

      final freshSession = Session(
        id: sessionId,
        label: 'fresh',
        server: const ServerAddress(host: freshHost, port: 22, user: freshUser),
      );
      final sessions = FakeSessionNotifier(sessions: [freshSession]);
      addTearDown(sessions.dispose);
      final manager = _RecordingConnectionsNotifier([conn]);
      final container = _container(conn, manager: manager, sessions: sessions);
      addTearDown(container.dispose);

      SSHConfig? observed;
      Future<void> factory(Connection c) async {
        observed = c.sshConfig;
      }

      final tabKey = GlobalKey<TerminalTabState>();
      await tester.pumpWidget(
        _host(conn, container, tabKey: tabKey, reconnectFactory: factory),
      );
      await tester.pump();

      tabKey.currentState!.reconnect();
      await tester.pumpAndSettle();

      // Fresh session projected through toSSHConfig must overwrite
      // the stale host/user the connection was constructed with.
      expect(
        observed?.server.host,
        freshHost,
        reason:
            '_refreshConfig must adopt the matching session\'s host on '
            'reconnect so user edits actually take effect.',
      );
      expect(observed?.server.user, freshUser);
      // The mutation is observable on the Connection itself too —
      // `_refreshConfig` writes back to `widget.connection.sshConfig`
      // so the reconnect factory and post-reconnect Connection state
      // see the same fresh values.
      expect(conn.sshConfig.server.host, freshHost);
    },
  );

  testWidgets(
    'reconnect() without an injected factory carries the refreshed config '
    'into ConnectionsNotifier.reconnect via `updatedConfig:`',
    (tester) async {
      // Spec: the non-factory branch hands the fresh config to the
      // notifier as `updatedConfig:`. Pinning the contract guards
      // against a refactor that drops the parameter — the notifier
      // would then reconnect against a stale cached config and a
      // saved-session edit (host rename) would silently no-op until
      // the user disconnected first.
      const sessionId = 'session-bare';
      const freshHost = '198.51.100.7';
      final conn = Connection(
        id: 'conn-bare',
        label: 'tab',
        sessionId: sessionId,
        sshConfig: const SSHConfig(
          server: ServerAddress(host: '127.0.0.1', port: 22, user: 'u'),
          auth: SshAuth(),
        ),
        state: SSHConnectionState.connecting,
      );
      addTearDown(conn.dispose);
      final freshSession = Session(
        id: sessionId,
        label: 'fresh',
        server: const ServerAddress(host: freshHost, port: 22, user: 'u'),
      );
      final sessions = FakeSessionNotifier(sessions: [freshSession]);
      addTearDown(sessions.dispose);
      final manager = _RecordingConnectionsNotifier([conn]);
      final container = _container(conn, manager: manager, sessions: sessions);
      addTearDown(container.dispose);

      final tabKey = GlobalKey<TerminalTabState>();
      await tester.pumpWidget(_host(conn, container, tabKey: tabKey));
      await tester.pump();

      tabKey.currentState!.reconnect();
      await tester.pump();

      expect(manager.reconnectCalls, hasLength(1));
      expect(
        manager.reconnectCalls.single.config?.server.host,
        freshHost,
        reason:
            'No-factory delegation must thread the refreshed SSHConfig '
            'through `updatedConfig:` so the notifier reconnects against '
            'the current saved-session values.',
      );
    },
  );

  // The interactive split / close / focus paths go through
  // `TerminalPane.onClose`, which is only non-null when the tree has
  // multiple panes. Driving a split requires a user-visible context
  // menu interaction inside a live pane (the pane's right-click path)
  // and a connected Rust session.
  // covered by integration: splitting / closing panes requires the live
  // pane context menu and a real session.
}
