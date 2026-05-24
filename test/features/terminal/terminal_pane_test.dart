import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/connection/connection.dart';
import 'package:letsflutssh/providers/connections_notifier.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/features/terminal/terminal_pane.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/providers/connection_provider.dart';

import '../../helpers/frb_bootstrap.dart';

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

Widget _host(
  Connection conn,
  ProviderContainer container, {
  bool isActiveTab = true,
  bool isFocused = false,
}) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      localizationsDelegates: S.localizationsDelegates,
      supportedLocales: S.supportedLocales,
      home: Scaffold(
        body: TerminalPane(
          connection: conn,
          isActiveTab: isActiveTab,
          isFocused: isFocused,
        ),
      ),
    ),
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
}
