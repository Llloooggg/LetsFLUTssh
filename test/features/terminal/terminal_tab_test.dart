import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/connection/connection.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/features/terminal/terminal_pane.dart';
import 'package:letsflutssh/features/terminal/terminal_tab.dart';
import 'package:letsflutssh/features/terminal/tiling_view.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/providers/config_provider.dart';
import 'package:letsflutssh/providers/connection_provider.dart';
import 'package:letsflutssh/providers/connections_notifier.dart';
import 'package:letsflutssh/providers/focused_pane_provider.dart';

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

Connection _makeConnectingConnection({String id = 'tab-conn'}) {
  return Connection(
    id: id,
    label: 'tab',
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
}) {
  return ProviderContainer(
    overrides: [
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

  // The interactive split / close / focus paths go through
  // `TerminalPane.onClose`, which is only non-null when the tree has
  // multiple panes. Driving a split requires a user-visible context
  // menu interaction inside a live pane (the pane's right-click path)
  // and a connected Rust session.
  // covered by integration: splitting / closing panes requires the live
  // pane context menu and a real session.
}
