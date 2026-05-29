import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/connection/connection.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/core/ssh/transport/ssh_transport.dart';
import 'package:letsflutssh/features/terminal/pane_recording_registry.dart';
import 'package:letsflutssh/features/terminal/terminal_pane.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/providers/config_provider.dart';
import 'package:letsflutssh/providers/connection_provider.dart';
import 'package:letsflutssh/providers/connections_notifier.dart';
import 'package:letsflutssh/src/rust/api/terminal.dart' as rust_terminal;
import 'package:letsflutssh/widgets/terminal/connection_progress.dart';

import '../../helpers/frb_bootstrap.dart';
import '../../helpers/test_notifiers.dart';

/// Static stand-in for [ConnectionsNotifier]. Keeps the test out of the
/// FRB bus, the credential cache, and the connect cascade — the pane
/// only reads the notifier through `notifyStateChanged()`, which the
/// disposed branch never reaches.
class _StubConnectionManager extends ConnectionsNotifier {
  _StubConnectionManager(this._conns);
  final List<Connection> _conns;

  @override
  List<Connection> build() => _conns;

  @override
  List<Connection> get connections => _conns;
}

Connection _makeConnectingConnection() {
  return Connection(
    id: 'test-conn',
    label: 'test',
    sshConfig: const SSHConfig(
      server: ServerAddress(host: '127.0.0.1', port: 22, user: 'u'),
      auth: SshAuth(),
    ),
    state: SSHConnectionState.connecting,
  );
}

/// Pre-`disconnected` connection with optional [connectionError]. The pane's
/// `_connectAndOpenShell` fast-paths through `waitUntilReady` (no-op for
/// non-connecting state) straight into `_onConnectFailed`, which paints the
/// localized error block.
Connection _makeDisconnectedConnection({String? errorDetail}) {
  return Connection(
    id: 'test-conn-disconnected',
    label: 'test',
    sshConfig: const SSHConfig(
      server: ServerAddress(host: '127.0.0.1', port: 22, user: 'u'),
      auth: SshAuth(),
    ),
    state: SSHConnectionState.disconnected,
    connectionError: errorDetail,
  );
}

/// Connected connection whose transport is already adopted — `_openSessionAndAttach`
/// is the only branch reachable from `_connectAndOpenShell`.
Connection _makeConnectedConnection(SshTransport transport) {
  final conn = Connection(
    id: 'test-conn-connected',
    label: 'test',
    sshConfig: const SSHConfig(
      server: ServerAddress(host: '127.0.0.1', port: 22, user: 'u'),
      auth: SshAuth(),
    ),
    state: SSHConnectionState.connected,
  );
  conn.transport = transport;
  conn.markTransportAdopted();
  return conn;
}

/// Stand-in for [SshTransport] whose `openTerminalSession` always throws. Any
/// other method routes through `noSuchMethod` so a stray call surfaces loudly
/// rather than silently no-opping. Mirrors the pattern in
/// `test/features/mobile/mobile_terminal_view_test.dart`.
class _ThrowingOpenSessionTransport implements SshTransport {
  _ThrowingOpenSessionTransport(this._error);
  final Object _error;

  @override
  bool get isConnected => true;

  @override
  Future<rust_terminal.TerminalSession> openTerminalSession({
    required int cols,
    required int rows,
    required int scrollback,
    required rust_terminal.TerminalPalette palette,
  }) async => throw _error;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    '${invocation.memberName} not used by this test',
  );
}

Widget _host(
  Connection conn,
  ProviderContainer container, {
  bool isActiveTab = true,
  bool isFocused = false,
  String? paneId,
  String? tabId,
  Key? paneKey,
}) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      localizationsDelegates: S.localizationsDelegates,
      supportedLocales: S.supportedLocales,
      home: Scaffold(
        body: TerminalPane(
          key: paneKey,
          connection: conn,
          isActiveTab: isActiveTab,
          isFocused: isFocused,
          paneId: paneId,
          tabId: tabId,
        ),
      ),
    ),
  );
}

/// Container preset that overrides every provider the pane touches before
/// the session opens: `connectionsProvider` (for `notifyStateChanged`) and
/// `configProvider` (for `scrollback` / `fontSize` reads and zoom mutations).
ProviderContainer _container(Connection conn) {
  return ProviderContainer(
    overrides: [
      connectionsProvider.overrideWith(() => _StubConnectionManager([conn])),
      configProvider.overrideWith(TestConfigNotifier.new),
    ],
  );
}

/// True when the pane's owned [FocusNode] (debugLabel `TerminalPane`)
/// currently holds primary keyboard focus.
bool _paneHasFocus(WidgetTester tester) =>
    tester.binding.focusManager.primaryFocus?.debugLabel == 'TerminalPane';

void main() {
  // The pane renders `ConnectionProgress` while connecting, which opens a
  // real `ReplayTerminalController` (Rust `terminalReplayOpen` over FRB) in
  // `initState` — so the native library must be loaded for the pane to build.
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(requireFrbLoaded);

  testWidgets(
    'disposing the pane mid-connect does not throw — _connectAndOpenShell '
    'guards every async hop with a mounted check',
    (tester) async {
      // Regression for the case where the user dismisses a session
      // (closes the tab / pops the route) while `waitUntilReady`
      // is still awaiting the Rust actor's terminal-state event.
      // Pre-fix, `_connectAndOpenShell` reached `setState(...)`
      // after dispose and FlutterError-ed.
      final conn = _makeConnectingConnection();
      final container = ProviderContainer(
        overrides: [
          connectionsProvider.overrideWith(
            () => _StubConnectionManager([conn]),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(_host(conn, container));
      // One pump fires the postFrameCallback that kicks off
      // `_connectAndOpenShell`. The method runs synchronously up to
      // `await conn.waitUntilReady()`, then yields — the connection
      // is still in `connecting`, so the completer is pending.
      await tester.pump();

      // Dispose the pane mid-await by replacing the tree.
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            home: Scaffold(body: SizedBox.shrink()),
          ),
        ),
      );

      // Resolve the gate that `_connectAndOpenShell` is parked on.
      // Without the mounted guard the resumed continuation would now
      // call `setState` on the disposed State — FlutterError. The fix
      // checks `!mounted` immediately after the await and returns.
      conn.state = SSHConnectionState.disconnected;
      conn.completeReady();

      // Drain any microtasks the resumed continuation queues.
      await tester.pumpAndSettle();

      expect(
        tester.takeException(),
        isNull,
        reason:
            'Mid-connect dispose must not surface a FlutterError. The '
            'mounted guard after each await in _connectAndOpenShell is '
            'the contract under test.',
      );
    },
  );

  testWidgets(
    'pane disposed before transport adoption finishes is also clean — '
    'second await (`transportReady`) is guarded too',
    (tester) async {
      // The success-path branch awaits `conn.transportReady` after
      // `waitUntilReady` returned with the state still flagged as
      // connecting/connected. This test exercises that second hop:
      // we complete `waitUntilReady` first (state stays
      // `connecting`), pump a microtask so the continuation enters
      // the second await, then dispose, then resolve transport.
      final conn = _makeConnectingConnection();
      final container = ProviderContainer(
        overrides: [
          connectionsProvider.overrideWith(
            () => _StubConnectionManager([conn]),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(_host(conn, container));
      await tester.pump();

      // First gate resolves with state still `connecting` so the
      // continuation enters the `await conn.transportReady` branch.
      conn.completeReady();
      // Pump the microtask queue without advancing widget lifecycle
      // beyond what's necessary — `pump()` runs pending microtasks
      // and a single frame.
      await tester.pump();

      // Now dispose mid-second-await.
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            home: Scaffold(body: SizedBox.shrink()),
          ),
        ),
      );

      // Resolve the second gate after dispose.
      conn.state = SSHConnectionState.disconnected;
      conn.markTransportAdopted(adopted: false);

      await tester.pumpAndSettle();

      expect(
        tester.takeException(),
        isNull,
        reason:
            'Second async hop (`transportReady`) must also have a '
            'mounted guard so disposal between gates 1 and 2 is safe.',
      );
    },
  );

  testWidgets(
    'a backgrounded tab does not hold keyboard focus, and bringing it to '
    'the foreground re-grabs it — the tab-switch focus contract',
    (tester) async {
      // Switching tabs in the desktop `IndexedStack` keeps backgrounded
      // panes mounted with their in-tab `isFocused` unchanged; only
      // `isActiveTab` flips. Keyboard ownership must follow `isActiveTab`,
      // otherwise the newly-shown terminal stays unfocused until an
      // OS-level focus round-trip (clicking outside the app).
      final conn = _makeConnectingConnection();
      final container = ProviderContainer(
        overrides: [
          connectionsProvider.overrideWith(
            () => _StubConnectionManager([conn]),
          ),
        ],
      );
      addTearDown(container.dispose);

      // Mounted as the focused pane of a *backgrounded* tab.
      await tester.pumpWidget(
        _host(conn, container, isActiveTab: false, isFocused: true),
      );
      await tester.pump(); // fire the post-frame focus check
      expect(
        _paneHasFocus(tester),
        isFalse,
        reason:
            'A backgrounded tab must not autofocus on mount even when it '
            'owns the focused pane within its own tab.',
      );

      // Tab brought to the foreground — only `isActiveTab` flips.
      await tester.pumpWidget(
        _host(conn, container, isActiveTab: true, isFocused: true),
      );
      await tester.pump();
      expect(
        _paneHasFocus(tester),
        isTrue,
        reason:
            'didUpdateWidget must re-grab focus when (isActiveTab && '
            'isFocused) flips false→true, so the foreground terminal is '
            'ready to type without an extra click.',
      );

      conn.state = SSHConnectionState.disconnected;
      conn.completeReady();
      await tester.pumpAndSettle();
    },
  );

  testWidgets('sending a tab to the background drops its keyboard focus', (
    tester,
  ) async {
    final conn = _makeConnectingConnection();
    final container = ProviderContainer(
      overrides: [
        connectionsProvider.overrideWith(() => _StubConnectionManager([conn])),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      _host(conn, container, isActiveTab: true, isFocused: true),
    );
    await tester.pump();
    expect(_paneHasFocus(tester), isTrue);

    await tester.pumpWidget(
      _host(conn, container, isActiveTab: false, isFocused: true),
    );
    await tester.pump();
    expect(
      _paneHasFocus(tester),
      isFalse,
      reason:
          'When the tab leaves the foreground the pane must release focus '
          'so input never routes to a hidden terminal.',
    );

    conn.state = SSHConnectionState.disconnected;
    conn.completeReady();
    await tester.pumpAndSettle();
  });

  testWidgets(
    'disconnected connection with an explicit error detail renders the '
    'localized error block — covers `_onConnectFailed` with `connectionError`',
    (tester) async {
      // `waitUntilReady` returns immediately for non-connecting state, so
      // the post-frame callback drops straight into the `!conn.isConnected`
      // branch and `_onConnectFailed` pumps `localizeError(...)` into
      // `_error`. `_buildBody` then paints the mono error Text rather than
      // `ConnectionProgress`.
      final conn = _makeDisconnectedConnection(errorDetail: 'host unreachable');
      addTearDown(conn.dispose);
      final container = _container(conn);
      addTearDown(container.dispose);

      await tester.pumpWidget(_host(conn, container));
      // Two pumps: first mounts and schedules the post-frame callback;
      // second drains the resolved `waitUntilReady` continuation and the
      // resulting setState.
      await tester.pump();
      await tester.pump();

      // Localized error string from `localizeError` should surface in a
      // Text widget. The exact phrasing is locale-driven; assert SOMETHING
      // non-empty rendered with the error detail in it.
      final hasErrorText = tester
          .widgetList<Text>(find.byType(Text))
          .any((t) => (t.data ?? '').toLowerCase().contains('host'));
      expect(
        hasErrorText,
        isTrue,
        reason:
            'When the connection carries an explicit error detail, '
            '`_onConnectFailed` must surface it through `localizeError` '
            'instead of falling back to the generic "connection failed" '
            'string.',
      );
      expect(find.byType(ConnectionProgress), findsNothing);
    },
  );

  testWidgets('disconnected connection without an error detail falls back to '
      '`errConnectionFailed` — the other arm of `_onConnectFailed`', (
    tester,
  ) async {
    // Mirror path of the above test: same fast-path through
    // `_onConnectFailed`, but `connectionError == null` so the method
    // hands back `l10n.errConnectionFailed` instead of a localized
    // exception body.
    final conn = _makeDisconnectedConnection();
    addTearDown(conn.dispose);
    final container = _container(conn);
    addTearDown(container.dispose);

    await tester.pumpWidget(_host(conn, container));
    await tester.pump();
    await tester.pump();

    final hasErrorText = tester
        .widgetList<Text>(find.byType(Text))
        .any((t) => (t.data ?? '').trim().isNotEmpty);
    expect(
      hasErrorText,
      isTrue,
      reason:
          'Disconnected-from-the-start must paint the error block, not '
          'the connecting spinner.',
    );
    expect(find.byType(ConnectionProgress), findsNothing);
  });

  testWidgets(
    'connecting connection mounts ConnectionProgress until the session '
    'arrives — covers the `_controller == null` render branch',
    (tester) async {
      // While `state == connecting` the build path returns
      // `ConnectionProgress(...)` (the `error == null && controller ==
      // null` short-circuit). We never resolve the gate, so the view stays
      // in that branch for the test's lifetime.
      final conn = _makeConnectingConnection();
      addTearDown(conn.dispose);
      final container = _container(conn);
      addTearDown(container.dispose);

      await tester.pumpWidget(_host(conn, container));
      await tester.pump();

      expect(find.byType(ConnectionProgress), findsOneWidget);
    },
  );

  testWidgets(
    'connected transport whose `openTerminalSession` throws lands in the '
    'catch and renders the localized error — `_openSessionAndAttach` catch',
    (tester) async {
      // `_openSessionAndAttach` wraps the FRB open in `try/catch`; a
      // throwing transport drives the catch body which logs and pumps
      // `localizeError(...)` into `_error`.
      final conn = _makeConnectedConnection(
        _ThrowingOpenSessionTransport(Exception('session open failed in test')),
      );
      addTearDown(conn.dispose);
      final container = _container(conn);
      addTearDown(container.dispose);

      await tester.pumpWidget(_host(conn, container));
      // First frame mounts; the post-frame callback fires
      // `_connectAndOpenShell`, which immediately drops into
      // `_openSessionAndAttach`. Two more pumps drain the async
      // catch + setState.
      await tester.pump();
      await tester.pump();
      await tester.pump();

      final hasErrorText = tester
          .widgetList<Text>(find.byType(Text))
          .any((t) => (t.data ?? '').trim().isNotEmpty);
      expect(
        hasErrorText,
        isTrue,
        reason:
            'A throwing `openTerminalSession` must surface as a localized '
            'error in the pane, not as an unhandled FlutterError.',
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(ConnectionProgress), findsNothing);
    },
  );

  // zoom accessor test deferred — the configProvider.notifier.update
  // call inside _adjustFontSize / _zoomReset routes through the
  // store actor which doesn't settle synchronously within the test
  // pump cadence; the fontSize re-read returns the pre-mutation value.

  testWidgets(
    'sendCommand early-returns when the session is null — no exception, no '
    'broadcast side effect',
    (tester) async {
      // The pane is still in the connecting branch, so `_session == null`
      // and `sendCommand` must hit its early-return guard. The test is
      // really a smoke check for the public no-op contract: no throw, no
      // state change.
      final conn = _makeConnectingConnection();
      addTearDown(conn.dispose);
      final container = _container(conn);
      addTearDown(container.dispose);

      final paneKey = GlobalKey<TerminalPaneState>();
      await tester.pumpWidget(_host(conn, container, paneKey: paneKey));
      await tester.pump();

      paneKey.currentState!.sendCommand('echo hi');
      await tester.pump();

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'pane omits paneId → `_registerRecordingHandle` skips the registry, '
    'so unregister on dispose stays a clean no-op',
    (tester) async {
      // The handle registration is gated on `widget.paneId != null`; a
      // null paneId must therefore leave the global
      // `PaneRecordingRegistry` untouched both at mount and at dispose.
      final conn = _makeConnectingConnection();
      addTearDown(conn.dispose);
      final container = _container(conn);
      addTearDown(container.dispose);

      await tester.pumpWidget(_host(conn, container));
      await tester.pump();

      // No paneId means no entry; the lookup must return null.
      expect(PaneRecordingRegistry.instance.get('test-conn'), isNull);

      // Dispose path must also tolerate the null paneId.
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'pane with paneId registers a recording handle in `initState` and '
    'unregisters it on dispose',
    (tester) async {
      // With paneId present the `PaneRecordingRegistry.register` call
      // fires from `initState`, so a `get(paneId)` lookup returns the
      // handle. `dispose` runs the matching `unregister`, so the entry
      // is gone after teardown.
      final conn = _makeConnectingConnection();
      addTearDown(conn.dispose);
      final container = _container(conn);
      addTearDown(container.dispose);
      const paneId = 'pane-1';

      await tester.pumpWidget(
        _host(conn, container, paneId: paneId, tabId: 'tab-1'),
      );
      await tester.pump();

      expect(
        PaneRecordingRegistry.instance.get(paneId),
        isNotNull,
        reason:
            '_registerRecordingHandle must record the handle under the '
            'pane id before any frame is drawn.',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      expect(
        PaneRecordingRegistry.instance.get(paneId),
        isNull,
        reason:
            'dispose() must unregister the handle so the registry never '
            'holds entries for unmounted panes.',
      );
    },
  );

  testWidgets(
    'pane disposes cleanly when never connected — scrubber, progress sub, '
    'focus node, and registry handle all unwound without throwing',
    (tester) async {
      // The dispose path: TerminalScrubber.unregister → _progressSub.cancel
      // → broadcast unregister (null-safe) → PaneRecordingRegistry.unregister
      // → controller/session dispose (null on the never-attached path) →
      // FocusNode dispose → _isRecording dispose. We exercise it by
      // mounting then unmounting; any throw surfaces via takeException.
      final conn = _makeConnectingConnection();
      addTearDown(conn.dispose);
      final container = _container(conn);
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _host(conn, container, paneId: 'pane-x', tabId: 'tab-x'),
      );
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());

      expect(tester.takeException(), isNull);
    },
  );
}
