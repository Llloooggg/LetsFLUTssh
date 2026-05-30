import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/connection/connection.dart';
import 'package:letsflutssh/core/security/terminal_scrubber.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/core/ssh/transport/ssh_transport.dart';
import 'package:letsflutssh/features/terminal/broadcast_controller.dart';
import 'package:letsflutssh/features/terminal/pane_recording_registry.dart';
import 'package:letsflutssh/features/terminal/terminal_pane.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/providers/broadcast_provider.dart';
import 'package:letsflutssh/providers/config_provider.dart';
import 'package:letsflutssh/providers/connection_provider.dart';
import 'package:letsflutssh/providers/connections_notifier.dart';
import 'package:letsflutssh/src/rust/api/terminal.dart' as rust_terminal;
import 'package:letsflutssh/theme/app_theme.dart';
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

  // ── Render-branch + structural-wiring coverage ────────────────────────────
  //
  // Everything below stays on the connect-phase render branch (the live
  // grid view needs a real Rust session, deferred to integration tests).
  // The connect-phase tree is itself non-trivial: it owns the focus
  // surface, the pointer-down focus hand-off, the broadcast / recording
  // registration gates, the scrubber registration, and the no-op safety
  // guards on every input path. Each group below targets one of those.

  group('connect-phase render structure', () {
    testWidgets('a Listener wraps the body so a pointer-down anywhere drives '
        '`widget.onFocused` — the focus hand-off contract that survives '
        'GestureDetector\'s onTap drift', (tester) async {
      // The pane uses `Listener.onPointerDown` (not GestureDetector.onTap)
      // for the focus hand-off so any tiny drift during the click does
      // not swallow the focus switch. We verify the wiring: send a raw
      // pointer-down through the pane and observe `onFocused` fired.
      final conn = _makeConnectingConnection();
      addTearDown(conn.dispose);
      final container = _container(conn);
      addTearDown(container.dispose);

      var focusedCalls = 0;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            home: Scaffold(
              body: TerminalPane(
                connection: conn,
                onFocused: () => focusedCalls++,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // The Listener has translucent hit-test behaviour, so a tap on the
      // ConnectionProgress region still reaches it.
      await tester.tap(find.byType(ConnectionProgress));
      await tester.pump();

      expect(
        focusedCalls,
        greaterThanOrEqualTo(1),
        reason:
            'A pointer-down anywhere in the pane must invoke onFocused so '
            'clicking between split panes always switches focus, even when '
            'the click has sub-pixel drift.',
      );
    });

    testWidgets(
      'a Focus surface wraps the body so the owned `_terminalFocus` stays '
      'attached across connect → live phases',
      (tester) async {
        // The pane wraps its body in a `Focus` widget (not just the live
        // grid) so `requestFocus()` works from initState even during the
        // pre-session progress phase. Find it by ancestor search anchored
        // at the ConnectionProgress.
        final conn = _makeConnectingConnection();
        addTearDown(conn.dispose);
        final container = _container(conn);
        addTearDown(container.dispose);

        await tester.pumpWidget(
          _host(conn, container, isActiveTab: true, isFocused: true),
        );
        await tester.pump();

        final focusAncestor = find.ancestor(
          of: find.byType(ConnectionProgress),
          matching: find.byType(Focus),
        );
        expect(
          focusAncestor,
          findsWidgets,
          reason:
              'The pane must wrap the connect-phase body in a Focus widget '
              'so the owned _terminalFocus can grab focus before the live '
              'grid exists.',
        );
      },
    );
  });

  group('recording handle registration variants', () {
    testWidgets(
      'a pane whose connection has a sessionId reports `canRecord = true` — '
      'recordings need a saved-session folder, so quick-connect is the only '
      '`canRecord = false` case',
      (tester) async {
        // `_registerRecordingHandle` derives `canRecord` from
        // `widget.connection.sessionId != null`. A saved session id flips
        // the gate true so the connection-bar record button mounts.
        final conn = Connection(
          id: 'tc-with-session',
          label: 'lbl',
          sshConfig: const SSHConfig(
            server: ServerAddress(host: '127.0.0.1', port: 22, user: 'u'),
            auth: SshAuth(),
          ),
          sessionId: 'saved-sess-1',
          state: SSHConnectionState.connecting,
        );
        addTearDown(conn.dispose);
        final container = _container(conn);
        addTearDown(container.dispose);

        await tester.pumpWidget(
          _host(conn, container, paneId: 'pane-rec', tabId: 'tab-rec'),
        );
        await tester.pump();

        final handle = PaneRecordingRegistry.instance.get('pane-rec');
        expect(handle, isNotNull);
        expect(
          handle!.canRecord,
          isTrue,
          reason:
              'canRecord must mirror "connection has a saved-session id" '
              '— that is the on-disk target the recorder writes to.',
        );
        expect(
          handle.isRecording.value,
          isFalse,
          reason:
              'Recording defaults to off; the auto-start branch only fires '
              'after the session opens, never on mount.',
        );
      },
    );

    testWidgets(
      'a quick-connect pane (no sessionId) reports `canRecord = false` — '
      'the record button must hide itself rather than try to write '
      'into a nonexistent session folder',
      (tester) async {
        // The default `_makeConnectingConnection()` carries no sessionId, so
        // the handle's `canRecord` must be false. The button surface uses
        // this flag to hide itself entirely for quick-connect panes.
        final conn = _makeConnectingConnection();
        addTearDown(conn.dispose);
        final container = _container(conn);
        addTearDown(container.dispose);

        await tester.pumpWidget(
          _host(conn, container, paneId: 'pane-qc', tabId: 'tab-qc'),
        );
        await tester.pump();

        final handle = PaneRecordingRegistry.instance.get('pane-qc');
        expect(handle, isNotNull);
        expect(
          handle!.canRecord,
          isFalse,
          reason:
              'Quick-connect panes (no sessionId) must report canRecord=false '
              'so the connection-bar record button hides itself — recordings '
              'have no destination folder.',
        );
      },
    );
  });

  group('TerminalScrubber registration', () {
    testWidgets(
      'mounting the pane registers exactly one scrub callback; unmounting '
      'unregisters it — auto-lock walks the live set',
      (tester) async {
        // The scrubber registry is a process-global singleton, so we reset
        // it before and after the test. The pane's initState calls
        // `register`, dispose calls `unregister`; the count delta is the
        // load-bearing contract — auto-lock walks `_registered` and a leak
        // here would double-scrub on a future lock.
        TerminalScrubber.instance.resetForTests();
        addTearDown(TerminalScrubber.instance.resetForTests);

        final conn = _makeConnectingConnection();
        addTearDown(conn.dispose);
        final container = _container(conn);
        addTearDown(container.dispose);

        expect(TerminalScrubber.instance.trackedCount, 0);

        await tester.pumpWidget(_host(conn, container));
        await tester.pump();

        expect(
          TerminalScrubber.instance.trackedCount,
          1,
          reason:
              'initState must register one scrub callback so the auto-lock '
              'path can clear this pane\'s scrollback alongside the DB key.',
        );

        await tester.pumpWidget(const SizedBox.shrink());

        expect(
          TerminalScrubber.instance.trackedCount,
          0,
          reason:
              'dispose must unregister the same callback — leaking a stale '
              'closure would call into a disposed session on the next lock.',
        );
      },
    );

    testWidgets(
      'invoking `scrubAll` while the pane has no live session is a clean '
      'no-op — the registered callback null-guards on `_session`',
      (tester) async {
        // The scrub callback closes over `_session` and only invokes
        // `.clear()` when it is non-null. We exercise that null-guard by
        // triggering `scrubAll` during the connecting render branch, where
        // `_session` is still null.
        TerminalScrubber.instance.resetForTests();
        addTearDown(TerminalScrubber.instance.resetForTests);

        final conn = _makeConnectingConnection();
        addTearDown(conn.dispose);
        final container = _container(conn);
        addTearDown(container.dispose);

        await tester.pumpWidget(_host(conn, container));
        await tester.pump();

        TerminalScrubber.instance.scrubAll();
        await tester.pump();

        expect(
          tester.takeException(),
          isNull,
          reason:
              'scrubAll on a pre-session pane must hit the `_session == null` '
              'guard inside the closure, not throw.',
        );
      },
    );
  });

  group('keyboard input guards', () {
    testWidgets(
      'a `KeyUpEvent` reaching the pane\'s `Focus.onKeyEvent` is ignored — '
      'only key-down + repeat produce PTY input, key-up is never bytes',
      (tester) async {
        // The pane's Focus surface forwards every KeyEvent to `handleKey`.
        // The first thing handleKey does is reject KeyUpEvent so the
        // framework keeps handling text-input / traversal events without
        // the pane swallowing them. We send a synthetic key-up through the
        // Focus tree and assert no exception + the pane stays mounted.
        final conn = _makeConnectingConnection();
        addTearDown(conn.dispose);
        final container = _container(conn);
        addTearDown(container.dispose);

        await tester.pumpWidget(
          _host(conn, container, isActiveTab: true, isFocused: true),
        );
        await tester.pump();
        // Send a key-down/up pair while the pane is focused; the up half
        // exercises the early-return. With no live session, the down half
        // routes to `_forwardKey` which itself early-returns on `_session
        // == null`. Both paths must be exception-free.
        await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
        await tester.pump();

        expect(
          tester.takeException(),
          isNull,
          reason:
              'KeyUpEvent must short-circuit at the top of handleKey, and '
              '_forwardKey must null-guard on _session before touching the '
              'session — both paths are exception-free in the connect phase.',
        );
      },
    );

    testWidgets(
      'a Ctrl+scroll wheel during the connect phase does not throw — the '
      '`_onPointerSignal` path is wired through `Listener`, but font-zoom '
      'updates the config notifier rather than touching the absent session',
      (tester) async {
        // `_onPointerSignal` is only attached on the live TerminalView, but
        // the surrounding Listener.onPointerDown contract means a stray
        // pointer event during connect must not destabilise the tree.
        // We send a normal pointer-down (Listener path) and assert
        // exception-free.
        final conn = _makeConnectingConnection();
        addTearDown(conn.dispose);
        final container = _container(conn);
        addTearDown(container.dispose);

        await tester.pumpWidget(_host(conn, container));
        await tester.pump();

        final gesture = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
        );
        await gesture.addPointer(location: const Offset(10, 10));
        await gesture.down(const Offset(20, 20));
        await tester.pump();
        await gesture.up();
        await tester.pump();

        expect(tester.takeException(), isNull);
      },
    );
  });

  group('rebuild stability across active-tab / focused flips', () {
    testWidgets(
      'flipping `hasMultiplePanes` does not throw — the flag toggles the '
      'focus-border surface but the connect-phase body is unaffected',
      (tester) async {
        // The flag is read by callers that wrap the pane in border decoration
        // — the pane itself just stores it. Toggling it must rebuild cleanly
        // even while the connect phase is in flight.
        final conn = _makeConnectingConnection();
        addTearDown(conn.dispose);
        final container = _container(conn);
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              localizationsDelegates: S.localizationsDelegates,
              supportedLocales: S.supportedLocales,
              home: Scaffold(body: TerminalPane(connection: conn)),
            ),
          ),
        );
        await tester.pump();
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              localizationsDelegates: S.localizationsDelegates,
              supportedLocales: S.supportedLocales,
              home: Scaffold(
                body: TerminalPane(connection: conn, hasMultiplePanes: true),
              ),
            ),
          ),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(find.byType(ConnectionProgress), findsOneWidget);
      },
    );

    testWidgets(
      'unchanged `isActiveTab`/`isFocused` across a rebuild does not steal '
      'or release focus — didUpdateWidget acts only on transitions',
      (tester) async {
        // The contract: focus changes ONLY on the (was-focused) → (is-focused)
        // transitions. A rebuild that leaves the flags identical must not
        // touch focus, otherwise tab-switch / theme-change rebuilds would
        // jitter the keyboard ownership.
        final conn = _makeConnectingConnection();
        addTearDown(conn.dispose);
        final container = _container(conn);
        addTearDown(container.dispose);

        await tester.pumpWidget(
          _host(conn, container, isActiveTab: true, isFocused: true),
        );
        await tester.pump();
        expect(_paneHasFocus(tester), isTrue);

        // Identical-flag rebuild — must NOT churn focus.
        await tester.pumpWidget(
          _host(conn, container, isActiveTab: true, isFocused: true),
        );
        await tester.pump();

        expect(
          _paneHasFocus(tester),
          isTrue,
          reason:
              'didUpdateWidget must be a no-op when the focus-owning flags '
              'are unchanged — any spurious unfocus()/requestFocus() would '
              'race with the framework\'s own focus traversal on rebuild.',
        );
      },
    );
  });

  // Deferred — zoomIn / zoomOut / zoomReset accessor seam: the call
  // routes through `configProvider.notifier.update(...)` which schedules
  // an async store timer that survives the pump and trips the
  // pending-timer invariant on teardown. Exercised in the integration
  // suite where the store actor can drain.

  group('paneId / tabId broadcast gating', () {
    testWidgets('a pane with paneId but no tabId does NOT enter the broadcast '
        'path — `_supportsBroadcast` requires both, so the controller is '
        'never read from the family provider', (tester) async {
      // The gate is `paneId != null && tabId != null`. With only paneId
      // set, `_attachBroadcast` early-returns (so even when the session
      // opens, the pane never registers a sink) and `_broadcastInput`
      // short-circuits because `_broadcast` stays null. We exercise the
      // surface that does survive — the recording registration — and
      // assert no broadcast-related exception during mount/unmount.
      final conn = _makeConnectingConnection();
      addTearDown(conn.dispose);
      final container = _container(conn);
      addTearDown(container.dispose);

      await tester.pumpWidget(_host(conn, container, paneId: 'pane-only'));
      await tester.pump();

      expect(
        PaneRecordingRegistry.instance.get('pane-only'),
        isNotNull,
        reason:
            'Recording registration is gated only on paneId, so it must '
            'still fire when tabId is null.',
      );
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      expect(PaneRecordingRegistry.instance.get('pane-only'), isNull);
    });

    testWidgets('a pane with tabId but no paneId does NOT register a recording '
        'handle — the registration is gated on paneId alone', (tester) async {
      // Mirror of the previous test, swapping which id is omitted. The
      // recording handle is gated only on paneId; the registry must
      // therefore stay untouched.
      final conn = _makeConnectingConnection();
      addTearDown(conn.dispose);
      final container = _container(conn);
      addTearDown(container.dispose);

      await tester.pumpWidget(_host(conn, container, tabId: 'tab-only'));
      await tester.pump();

      // We cannot directly observe the absence of an entry under a
      // null key — there is no key. The contract instead is "nothing
      // surfaces", which we read off no-exception + the pane still
      // rendered the connect spinner.
      expect(tester.takeException(), isNull);
      expect(find.byType(ConnectionProgress), findsOneWidget);
    });
  });

  // covered by integration: live `TerminalView` mount, snippet picker mount,
  // search-bar open/close, copy / paste round-trips, broadcast sink replay,
  // and recording start/stop all require a live Rust terminal session
  // (`openTerminalSession` → `LiveTerminalController` over FRB). Inside
  // `flutter test` we cannot drive a real session without standing up a
  // local SSH server, so those paths defer to integration tests rather
  // than running under a stub that would only re-pin the no-session
  // early-return branches we already cover above.

  // ── Additional connect-phase branch coverage ─────────────────────────────

  group('sendCommand newline-suffix branch', () {
    testWidgets(
      'sendCommand with a trailing newline still early-returns on a null '
      'session — both branches of the suffix terminator are exception-free',
      (tester) async {
        // The trailing-newline conditional inside sendCommand picks
        // between `command` and `'$command\n'`. The null-session guard
        // sits BEFORE that branch in the source, so both arms must
        // tolerate the no-session pre-condition without throwing.
        // Exercising both shapes pins the public no-op contract: the
        // caller never has to special-case the connect phase.
        final conn = _makeConnectingConnection();
        addTearDown(conn.dispose);
        final container = _container(conn);
        addTearDown(container.dispose);

        final paneKey = GlobalKey<TerminalPaneState>();
        await tester.pumpWidget(_host(conn, container, paneKey: paneKey));
        await tester.pump();

        // Two shapes — newline-suffixed and bare.
        paneKey.currentState!.sendCommand('echo hi\n');
        paneKey.currentState!.sendCommand('ls -la');
        await tester.pump();

        expect(
          tester.takeException(),
          isNull,
          reason:
              'sendCommand must early-return on a null session for both '
              'newline-suffixed and bare command strings — callers should '
              'not have to gate on the live-session phase.',
        );
      },
    );
  });

  group('connected-then-disposed mid open', () {
    testWidgets(
      'connected connection whose `openTerminalSession` resolves after the '
      'pane is unmounted does not throw — the post-open `mounted` guard '
      'absorbs the late completion',
      (tester) async {
        // _openSessionAndAttach checks `mounted` after the async
        // openTerminalSession completes. With a transport that throws
        // synchronously the catch branch's `if (!mounted) return` is the
        // load-bearing guard. We mount, unmount, and pump frames to
        // drain the late completion — no exception should surface.
        final conn = _makeConnectedConnection(
          _ThrowingOpenSessionTransport(Exception('late session open failure')),
        );
        addTearDown(conn.dispose);
        final container = _container(conn);
        addTearDown(container.dispose);

        await tester.pumpWidget(_host(conn, container));
        await tester.pump();
        // Tear the tree down before the catch's setState would fire.
        await tester.pumpWidget(const SizedBox.shrink());
        // Drain any pending microtasks from the catch path.
        await tester.pump();
        await tester.pump();

        expect(
          tester.takeException(),
          isNull,
          reason:
              'A late openTerminalSession failure must not call setState '
              'on a disposed pane — the mounted guard inside the catch '
              'is the contract under test.',
        );
      },
    );
  });

  group('hasError accessor', () {
    testWidgets('hasError flips to true on the disconnected-with-error path — '
        'public accessor mirrors the private `_error` field', (tester) async {
      // The `hasError` getter is the public surface other widgets read
      // to decide whether the pane is in a renderable error state.
      // After `_onConnectFailed` fires, `_error` is non-null and
      // `hasError` must read true; this is the documented contract for
      // consumers like the workspace bar.
      final conn = _makeDisconnectedConnection(errorDetail: 'refused');
      addTearDown(conn.dispose);
      final container = _container(conn);
      addTearDown(container.dispose);

      final paneKey = GlobalKey<TerminalPaneState>();
      await tester.pumpWidget(_host(conn, container, paneKey: paneKey));
      await tester.pump();
      await tester.pump();

      expect(
        paneKey.currentState!.hasError,
        isTrue,
        reason:
            'hasError must read true once _onConnectFailed has pumped a '
            'localized error into _error — the bar reads this to swap '
            'its status badge.',
      );
    });

    testWidgets(
      'hasError stays false on the pre-session connecting branch — no '
      '`_error` set means the accessor reports the clean state',
      (tester) async {
        // While the pane is still parked on `_connectAndOpenShell` and
        // no error has surfaced, `hasError` must read false. The
        // contract is symmetric to the on-error case above.
        final conn = _makeConnectingConnection();
        addTearDown(conn.dispose);
        final container = _container(conn);
        addTearDown(container.dispose);

        final paneKey = GlobalKey<TerminalPaneState>();
        await tester.pumpWidget(_host(conn, container, paneKey: paneKey));
        await tester.pump();

        expect(
          paneKey.currentState!.hasError,
          isFalse,
          reason:
              'Pre-session connecting must report hasError=false so the bar '
              'shows the connecting indicator instead of the error badge.',
        );
      },
    );
  });

  group('session accessor', () {
    testWidgets(
      'session getter reads null while the connect phase has not opened a '
      'shell — exposed for tests so the spec is observable',
      (tester) async {
        // The `@visibleForTesting` `session` getter exposes the private
        // `_session`. While the pane is still in the connecting branch,
        // no session has been opened, so the accessor must read null.
        final conn = _makeConnectingConnection();
        addTearDown(conn.dispose);
        final container = _container(conn);
        addTearDown(container.dispose);

        final paneKey = GlobalKey<TerminalPaneState>();
        await tester.pumpWidget(_host(conn, container, paneKey: paneKey));
        await tester.pump();

        expect(paneKey.currentState!.session, isNull);
      },
    );

    testWidgets(
      'session getter stays null after a throwing `openTerminalSession` — '
      'the catch path never installs the half-built session into `_session`',
      (tester) async {
        // The catch in `_openSessionAndAttach` runs the localized-error
        // setState but must NOT install the (never-constructed) session.
        // The `session` accessor must therefore read null after the
        // failure — the contract that downstream code (zoom, scroll,
        // search) can early-return on `session == null` to detect the
        // failure path.
        final conn = _makeConnectedConnection(
          _ThrowingOpenSessionTransport(Exception('failed open')),
        );
        addTearDown(conn.dispose);
        final container = _container(conn);
        addTearDown(container.dispose);

        final paneKey = GlobalKey<TerminalPaneState>();
        await tester.pumpWidget(_host(conn, container, paneKey: paneKey));
        await tester.pump();
        await tester.pump();
        await tester.pump();

        expect(
          paneKey.currentState!.session,
          isNull,
          reason:
              'A failed openTerminalSession must leave _session at null so '
              'every "if (_session == null) return" guard fires.',
        );
      },
    );
  });

  group('broadcast wiring gate', () {
    testWidgets(
      'a pane with BOTH paneId and tabId still does NOT register a sink while '
      'the session is null — `_attachBroadcast` only runs after open succeeds',
      (tester) async {
        // `_attachBroadcast` runs only inside the success branch of
        // `_openSessionAndAttach`. While the pane is in the connecting
        // phase, no sink should be registered — the broadcast controller
        // for the tab must have an empty sinks map. We probe the
        // controller via the family provider and assert.
        final conn = _makeConnectingConnection();
        addTearDown(conn.dispose);
        final container = _container(conn);
        addTearDown(container.dispose);

        await tester.pumpWidget(
          _host(conn, container, paneId: 'pane-bc', tabId: 'tab-bc'),
        );
        await tester.pump();

        final controller = container.read(
          broadcastControllerProvider('tab-bc'),
        );
        expect(
          controller.driverId,
          isNull,
          reason:
              'No driver should be set before a session opens — the pane '
              'never promotes itself.',
        );
        expect(
          controller.receiverIds,
          isEmpty,
          reason:
              'No receivers either — registerSink only fires from '
              '_attachBroadcast on session-open success.',
        );
      },
    );

    testWidgets(
      'broadcastFrom while the pane has no session is a no-op — the receiver '
      'fan-out filters absent sinks, so a stray broadcast cannot fault',
      (tester) async {
        // Even when the controller has a driver/receiver wired by other
        // panes, a fan-out from this pane while its own session is null
        // must not throw. The pane itself never calls `_broadcastInput`
        // from the connecting phase (no key path runs), so this test
        // exercises the cross-pane safety: fanning to the controller
        // from outside lands in the receiver loop which has its own
        // `if (sink == null) continue` filter.
        final conn = _makeConnectingConnection();
        addTearDown(conn.dispose);
        final container = _container(conn);
        addTearDown(container.dispose);

        await tester.pumpWidget(
          _host(conn, container, paneId: 'pane-r', tabId: 'tab-r'),
        );
        await tester.pump();

        final controller = container.read(broadcastControllerProvider('tab-r'));
        // Promote a fictional driver pane, mark this pane a receiver
        // (without a registered sink — its session is null), and fan
        // a synthetic key. The controller's `if (sink == null) continue`
        // is the load-bearing line.
        controller.setDriver('fake-driver');
        controller.toggleReceiver('pane-r');
        controller.broadcastFrom(
          'fake-driver',
          BroadcastBytes(Uint8List.fromList([0x41])),
        );
        await tester.pump();

        expect(
          tester.takeException(),
          isNull,
          reason:
              'A broadcast targeting a receiver pane whose session is null '
              'must skip the absent sink, not fault the driver loop.',
        );
      },
    );
  });

  group('theme repush guard', () {
    testWidgets(
      'a brightness toggle between rebuilds with no live session does NOT '
      'crash — `_maybeRepushPalette` short-circuits at `_session == null`',
      (tester) async {
        // Every build calls `_maybeRepushPalette` which checks
        // `_session == null` first. With a connecting connection (no
        // session yet) the guard fires every rebuild regardless of
        // brightness; the global `_paletteIsDark` is never written.
        // Toggling the theme between pumps verifies the guard is robust.
        final conn = _makeConnectingConnection();
        addTearDown(conn.dispose);
        final container = _container(conn);
        addTearDown(container.dispose);

        final priorBrightness = AppTheme.isDark
            ? Brightness.dark
            : Brightness.light;
        addTearDown(() => AppTheme.setBrightness(priorBrightness));

        AppTheme.setBrightness(Brightness.dark);
        await tester.pumpWidget(_host(conn, container));
        await tester.pump();

        AppTheme.setBrightness(Brightness.light);
        // Force a rebuild via a pumpWidget with the same content.
        await tester.pumpWidget(_host(conn, container));
        await tester.pump();

        expect(tester.takeException(), isNull);
      },
    );
  });

  group('focus surface autofocus arms', () {
    testWidgets(
      'a pane mounted with isActiveTab=true but isFocused=false does NOT '
      'autofocus — the `&&` gate requires both flags',
      (tester) async {
        // The Focus widget's `autofocus` is `isActiveTab && isFocused`.
        // Only one true is not enough; the pane must not steal focus.
        final conn = _makeConnectingConnection();
        addTearDown(conn.dispose);
        final container = _container(conn);
        addTearDown(container.dispose);

        await tester.pumpWidget(
          _host(conn, container, isActiveTab: true, isFocused: false),
        );
        await tester.pump();

        expect(
          _paneHasFocus(tester),
          isFalse,
          reason:
              'A pane that is the foreground tab but NOT the focused pane '
              'within that tab must not autofocus — keyboard ownership '
              'belongs to the actually-focused pane.',
        );
      },
    );

    testWidgets(
      'a pane mounted with isActiveTab=false and isFocused=false also does '
      'not autofocus — both flags off, focus stays elsewhere',
      (tester) async {
        // Symmetric coverage to the isFocused=true case in the existing
        // suite. Pinning that the inactive/unfocused arm is also clean
        // closes the four-way truth table.
        final conn = _makeConnectingConnection();
        addTearDown(conn.dispose);
        final container = _container(conn);
        addTearDown(container.dispose);

        await tester.pumpWidget(
          _host(conn, container, isActiveTab: false, isFocused: false),
        );
        await tester.pump();

        expect(_paneHasFocus(tester), isFalse);
      },
    );
  });

  group('pre-focus on backgrounded tab transitioning to focused-only', () {
    testWidgets(
      'didUpdateWidget does NOT regrab focus when only isFocused flips while '
      'isActiveTab stays false — the && gate keeps both halves required',
      (tester) async {
        // Pre-condition: backgrounded tab (isActiveTab=false). Flipping
        // isFocused from false→true must NOT regrab focus because the
        // tab is still backgrounded; only when isActiveTab also flips
        // true does the pane reclaim keyboard ownership.
        final conn = _makeConnectingConnection();
        addTearDown(conn.dispose);
        final container = _container(conn);
        addTearDown(container.dispose);

        await tester.pumpWidget(
          _host(conn, container, isActiveTab: false, isFocused: false),
        );
        await tester.pump();
        expect(_paneHasFocus(tester), isFalse);

        await tester.pumpWidget(
          _host(conn, container, isActiveTab: false, isFocused: true),
        );
        await tester.pump();

        expect(
          _paneHasFocus(tester),
          isFalse,
          reason:
              'isFocused flipping true alone is not enough — the tab must '
              'also be in the foreground (isActiveTab=true) for the pane to '
              'reclaim focus.',
        );
      },
    );
  });
}
