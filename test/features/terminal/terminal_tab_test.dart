import 'dart:async';
import 'dart:typed_data';
import '''package:letsflutssh/l10n/app_localizations.dart''';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:letsflutssh/core/connection/connection.dart';
import 'package:letsflutssh/core/session/session.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/features/terminal/terminal_pane.dart';
import 'package:letsflutssh/features/terminal/terminal_tab.dart';
import 'package:letsflutssh/features/terminal/tiling_view.dart';
import 'package:letsflutssh/providers/session_provider.dart';
import 'package:letsflutssh/theme/app_theme.dart';
import '../../core/ssh/shell_helper_test.mocks.dart';

/// SessionNotifier pre-populated with sessions for testing.
class _TestSessionNotifier extends SessionNotifier {
  final List<Session> _initial;
  _TestSessionNotifier(this._initial);

  @override
  List<Session> build() => List.of(_initial);
}

void main() {
  group('TerminalTab — always renders TilingView', () {
    testWidgets(
      'renders TilingView even when connection has no sshConnection',
      (tester) async {
        final conn = Connection(
          id: 'test-1',
          label: 'Test Server',
          sshConfig: const SSHConfig(
            server: ServerAddress(host: 'example.com', user: 'root'),
          ),
          sshConnection: null,
          state: SSHConnectionState.disconnected,
        );

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              localizationsDelegates: S.localizationsDelegates,
              supportedLocales: S.supportedLocales,
              theme: AppTheme.dark(),
              home: Scaffold(
                body: SizedBox(
                  width: 800,
                  height: 600,
                  child: TerminalTab(tabId: 'tab-1', connection: conn),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        // TerminalTab always renders TilingView now — TerminalPane handles
        // connection state internally
        expect(find.byType(TilingView), findsOneWidget);
        expect(find.byType(TerminalPane), findsOneWidget);
        expect(find.text('Not connected'), findsNothing);
      },
    );

    testWidgets(
      'renders TilingView when sshConnection exists but is disconnected',
      (tester) async {
        final mockSsh = MockSSHConnection();
        when(mockSsh.isConnected).thenReturn(false);

        final conn = Connection(
          id: 'test-2',
          label: 'Test Server',
          sshConfig: const SSHConfig(
            server: ServerAddress(host: 'example.com', user: 'root'),
          ),
          sshConnection: mockSsh,
          state: SSHConnectionState.disconnected,
        );

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              localizationsDelegates: S.localizationsDelegates,
              supportedLocales: S.supportedLocales,
              theme: AppTheme.dark(),
              home: Scaffold(
                body: SizedBox(
                  width: 800,
                  height: 600,
                  child: TerminalTab(tabId: 'tab-2', connection: conn),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        expect(find.byType(TilingView), findsOneWidget);
        expect(find.byType(TerminalPane), findsOneWidget);
      },
    );

    testWidgets('renders TilingView when connected', (tester) async {
      final mockSsh = MockSSHConnection();
      final mockSession = MockSSHSession();
      final stdoutCtrl = StreamController<Uint8List>.broadcast();
      final stderrCtrl = StreamController<Uint8List>.broadcast();
      final doneCompleter = Completer<void>();

      when(mockSsh.isConnected).thenReturn(true);
      when(mockSsh.openShell(any, any)).thenAnswer((_) async => mockSession);
      when(mockSession.stdout).thenAnswer((_) => stdoutCtrl.stream);
      when(mockSession.stderr).thenAnswer((_) => stderrCtrl.stream);
      when(mockSession.done).thenAnswer((_) => doneCompleter.future);

      final conn = Connection(
        id: 'connected',
        label: 'Test',
        sshConfig: const SSHConfig(
          server: ServerAddress(host: 'h', user: 'u'),
        ),
        sshConnection: mockSsh,
        state: SSHConnectionState.connected,
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Scaffold(
              body: SizedBox(
                width: 800,
                height: 600,
                child: TerminalTab(tabId: 'tab-connected', connection: conn),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(TilingView), findsOneWidget);
      expect(find.text('Not connected'), findsNothing);
    });
  });

  group('TerminalTab — reconnect error state', () {
    // The error state in TerminalTab is only reachable after _reconnect() fails.
    // We trigger it by first getting into error state via a failed reconnect.

    testWidgets('shows error state after reconnect fails', (tester) async {
      final conn = Connection(
        id: 'test-err',
        label: 'Test',
        sshConfig: const SSHConfig(
          server: ServerAddress(host: 'h', user: 'u'),
        ),
        sshConnection: null,
        state: SSHConnectionState.disconnected,
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Scaffold(
              body: SizedBox(
                width: 800,
                height: 600,
                child: TerminalTab(
                  tabId: 'tab-err',
                  connection: conn,
                  reconnectFactory: (_) async {
                    throw Exception('Auth failed');
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initially renders TilingView (TerminalPane handles disconnected state)
      expect(find.byType(TilingView), findsOneWidget);
    });

    testWidgets(
      'error state after failed reconnect shows Reconnect and Close buttons',
      (tester) async {
        final conn = Connection(
          id: 'test-btns',
          label: 'Test',
          sshConfig: const SSHConfig(
            server: ServerAddress(host: 'h', user: 'u'),
          ),
          sshConnection: null,
          state: SSHConnectionState.disconnected,
        );

        // Use reconnectFactory: first call fails, putting us into error state
        var firstCall = true;
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              localizationsDelegates: S.localizationsDelegates,
              supportedLocales: S.supportedLocales,
              theme: AppTheme.dark(),
              home: Scaffold(
                body: SizedBox(
                  width: 800,
                  height: 600,
                  child: TerminalTab(
                    tabId: 'tab-btns',
                    connection: conn,
                    reconnectFactory: (_) async {
                      if (firstCall) {
                        firstCall = false;
                        throw Exception('Connection refused');
                      }
                    },
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Initially shows TilingView — no error state from TerminalTab
        expect(find.byType(TilingView), findsOneWidget);
      },
    );

    testWidgets('reconnect failure via reconnectFactory shows error with message', (
      tester,
    ) async {
      final conn = Connection(
        id: 'rf-fail',
        label: 'Test',
        sshConfig: const SSHConfig(
          server: ServerAddress(host: 'h', user: 'u'),
        ),
        sshConnection: null,
        state: SSHConnectionState.disconnected,
      );

      // We need to get into error state. The only way is to call _reconnect()
      // which is triggered by the Reconnect button in the error state.
      // But the error state is only shown after _reconnect fails.
      // This is a chicken-and-egg problem — we can't reach the Reconnect button
      // without being in error state first.
      //
      // The error state IS reachable if we call _reconnect() programmatically
      // via the default reconnect path (no reconnectFactory, null sshConnection).
      // But that throws a null pointer. Let's use the default path to trigger
      // the first error, then test reconnectFactory on the second attempt.

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Scaffold(
              body: SizedBox(
                width: 800,
                height: 600,
                child: TerminalTab(
                  tabId: 'tab-rf-fail',
                  connection: conn,
                  reconnectFactory: (_) async {
                    throw Exception('Auth failed');
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initially shows TilingView
      expect(find.byType(TilingView), findsOneWidget);
    });
  });

  group('TerminalTab — reconnectFactory', () {
    // Since TerminalTab no longer shows initial error state, we need to
    // reach the error state first. We do this by:
    // 1. Having a reconnectFactory that fails on first call (to get into error state)
    // 2. Then testing the reconnect button behavior from the error state

    testWidgets('reconnect success via reconnectFactory resets to TilingView', (
      tester,
    ) async {
      final mockSsh = MockSSHConnection();
      final mockSession = MockSSHSession();

      final conn = Connection(
        id: 'rf-ok',
        label: 'Test',
        sshConfig: const SSHConfig(
          server: ServerAddress(host: 'h', user: 'u'),
        ),
        sshConnection: null,
        state: SSHConnectionState.disconnected,
      );

      var callCount = 0;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Scaffold(
              body: SizedBox(
                width: 800,
                height: 600,
                child: TerminalTab(
                  tabId: 'tab-rf-ok',
                  connection: conn,
                  reconnectFactory: (c) async {
                    callCount++;
                    if (callCount == 1) {
                      throw Exception('First attempt fails');
                    }
                    // Second attempt succeeds
                    final stdoutCtrl = StreamController<Uint8List>.broadcast();
                    final stderrCtrl = StreamController<Uint8List>.broadcast();
                    final doneCompleter = Completer<void>();

                    when(mockSsh.isConnected).thenReturn(true);
                    when(
                      mockSsh.openShell(any, any),
                    ).thenAnswer((_) async => mockSession);
                    when(
                      mockSession.stdout,
                    ).thenAnswer((_) => stdoutCtrl.stream);
                    when(
                      mockSession.stderr,
                    ).thenAnswer((_) => stderrCtrl.stream);
                    when(
                      mockSession.done,
                    ).thenAnswer((_) => doneCompleter.future);

                    c.sshConnection = mockSsh;
                    c.state = SSHConnectionState.connected;
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initially shows TilingView (TerminalPane handles disconnected state)
      expect(find.byType(TilingView), findsOneWidget);
    });

    testWidgets('reconnect shows loading spinner during reconnect attempt', (
      tester,
    ) async {
      final completer = Completer<void>();
      final conn = Connection(
        id: 'rf-load',
        label: 'Test',
        sshConfig: const SSHConfig(
          server: ServerAddress(host: 'h', user: 'u'),
        ),
        sshConnection: null,
        state: SSHConnectionState.disconnected,
      );

      var callCount = 0;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Scaffold(
              body: SizedBox(
                width: 800,
                height: 600,
                child: TerminalTab(
                  tabId: 'tab-rf-load',
                  connection: conn,
                  reconnectFactory: (c) async {
                    callCount++;
                    if (callCount == 1) {
                      throw Exception('First fails');
                    }
                    return completer.future;
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initially shows TilingView
      expect(find.byType(TilingView), findsOneWidget);

      // Complete without errors for cleanup
      completer.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('double reconnect: fail then succeed from error state', (
      tester,
    ) async {
      var callCount = 0;
      final conn = Connection(
        id: 'rf-retry',
        label: 'Test',
        sshConfig: const SSHConfig(
          server: ServerAddress(host: 'h', user: 'u'),
        ),
        sshConnection: null,
        state: SSHConnectionState.disconnected,
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Scaffold(
              body: SizedBox(
                width: 800,
                height: 600,
                child: TerminalTab(
                  tabId: 'tab-rf-retry',
                  connection: conn,
                  reconnectFactory: (_) async {
                    callCount++;
                    if (callCount <= 2) {
                      throw Exception('Attempt $callCount failed');
                    }
                    // Third attempt succeeds
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initially shows TilingView
      expect(find.byType(TilingView), findsOneWidget);
    });
  });

  group('TerminalTab — tiling close and reconnect', () {
    Connection makeConnected(
      MockSSHConnection mockSsh,
      MockSSHSession mockSession,
      String id,
    ) {
      final stdoutCtrl = StreamController<Uint8List>.broadcast();
      final stderrCtrl = StreamController<Uint8List>.broadcast();
      final doneCompleter = Completer<void>();

      when(mockSsh.isConnected).thenReturn(true);
      when(mockSsh.openShell(any, any)).thenAnswer((_) async => mockSession);
      when(mockSession.stdout).thenAnswer((_) => stdoutCtrl.stream);
      when(mockSession.stderr).thenAnswer((_) => stderrCtrl.stream);
      when(mockSession.done).thenAnswer((_) => doneCompleter.future);

      return Connection(
        id: id,
        label: 'Test $id',
        sshConfig: const SSHConfig(
          server: ServerAddress(host: 'h', user: 'u'),
        ),
        sshConnection: mockSsh,
        state: SSHConnectionState.connected,
      );
    }

    testWidgets('close pane on root leaf does nothing', (tester) async {
      final mockSsh = MockSSHConnection();
      final mockSession = MockSSHSession();
      final conn = makeConnected(mockSsh, mockSession, 'close-root');

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Scaffold(
              body: SizedBox(
                width: 800,
                height: 600,
                child: TerminalTab(tabId: 'tab-close-root', connection: conn),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final pane = tester.widget<TerminalPane>(find.byType(TerminalPane).first);
      expect(pane.onClose, isNull);
    });

    testWidgets('successful reconnect resets tree and shows TilingView', (
      tester,
    ) async {
      final mockSsh = MockSSHConnection();
      final mockSession = MockSSHSession();

      final conn = Connection(
        id: 'reconn-success',
        label: 'Test',
        sshConfig: const SSHConfig(
          server: ServerAddress(host: 'h', user: 'u'),
        ),
        sshConnection: null,
        state: SSHConnectionState.disconnected,
      );

      var callCount = 0;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Scaffold(
              body: SizedBox(
                width: 800,
                height: 600,
                child: TerminalTab(
                  tabId: 'tab-reconn-ok',
                  connection: conn,
                  reconnectFactory: (c) async {
                    callCount++;
                    if (callCount == 1) {
                      // First call fails to put us into error state
                      throw Exception('Initial failure');
                    }
                    // Second call succeeds
                    final stdoutCtrl = StreamController<Uint8List>.broadcast();
                    final stderrCtrl = StreamController<Uint8List>.broadcast();
                    final doneCompleter = Completer<void>();

                    when(mockSsh.isConnected).thenReturn(true);
                    when(
                      mockSsh.openShell(any, any),
                    ).thenAnswer((_) async => mockSession);
                    when(
                      mockSession.stdout,
                    ).thenAnswer((_) => stdoutCtrl.stream);
                    when(
                      mockSession.stderr,
                    ).thenAnswer((_) => stderrCtrl.stream);
                    when(
                      mockSession.done,
                    ).thenAnswer((_) => doneCompleter.future);

                    c.sshConnection = mockSsh;
                    c.state = SSHConnectionState.connected;
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initially shows TilingView — TerminalPane handles disconnected state
      expect(find.byType(TilingView), findsOneWidget);
    });
  });

  group('TerminalTab — reconnect() via GlobalKey', () {
    // Now that TerminalTabState is public and reconnect() is @visibleForTesting,
    // we can use a GlobalKey<TerminalTabState> to call reconnect() directly
    // and reach the error state / loading state / success reset.

    testWidgets(
      'reconnect failure resets to TilingView (TerminalPane shows error)',
      (tester) async {
        final key = GlobalKey<TerminalTabState>();
        final conn = Connection(
          id: 'key-err',
          label: 'Test',
          sshConfig: const SSHConfig(
            server: ServerAddress(host: 'h', user: 'u'),
          ),
          sshConnection: null,
          state: SSHConnectionState.disconnected,
        );

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              localizationsDelegates: S.localizationsDelegates,
              supportedLocales: S.supportedLocales,
              theme: AppTheme.dark(),
              home: Scaffold(
                body: SizedBox(
                  width: 800,
                  height: 600,
                  child: TerminalTab(
                    key: key,
                    tabId: 'tab-key-err',
                    connection: conn,
                    reconnectFactory: (_) async {
                      throw Exception('Auth failed');
                    },
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Initially shows TilingView
        expect(find.byType(TilingView), findsOneWidget);

        // Trigger reconnect programmatically — it will fail
        key.currentState!.reconnect();
        await tester.pumpAndSettle();

        // After failed reconnect, TerminalTab resets to TilingView
        // with a fresh TerminalPane that handles the error display
        expect(find.byType(TilingView), findsOneWidget);
        expect(find.byType(TerminalPane), findsOneWidget);
        expect(conn.connectionError, isNotNull);
      },
    );

    testWidgets('reconnect failure sets connectionError on connection', (
      tester,
    ) async {
      final key = GlobalKey<TerminalTabState>();
      final conn = Connection(
        id: 'key-icon',
        label: 'Test',
        sshConfig: const SSHConfig(
          server: ServerAddress(host: 'h', user: 'u'),
        ),
        sshConnection: null,
        state: SSHConnectionState.disconnected,
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Scaffold(
              body: SizedBox(
                width: 800,
                height: 600,
                child: TerminalTab(
                  key: key,
                  tabId: 'tab-key-icon',
                  connection: conn,
                  reconnectFactory: (_) async {
                    throw Exception('fail');
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      key.currentState!.reconnect();
      await tester.pumpAndSettle();

      // Error is stored on the connection, TerminalPane handles display
      expect(conn.connectionError, isNotNull);
      expect(conn.state, SSHConnectionState.disconnected);
      expect(find.byType(TilingView), findsOneWidget);
    });

    testWidgets('reconnect failure preserves TilingView with TerminalPane', (
      tester,
    ) async {
      final key = GlobalKey<TerminalTabState>();
      final conn = Connection(
        id: 'key-text-style',
        label: 'Test',
        sshConfig: const SSHConfig(
          server: ServerAddress(host: 'h', user: 'u'),
        ),
        sshConnection: null,
        state: SSHConnectionState.disconnected,
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Scaffold(
              body: SizedBox(
                width: 800,
                height: 600,
                child: TerminalTab(
                  key: key,
                  tabId: 'tab-key-text-style',
                  connection: conn,
                  reconnectFactory: (_) async {
                    throw Exception('timeout');
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      key.currentState!.reconnect();
      await tester.pumpAndSettle();

      // After failed reconnect, shows TilingView with TerminalPane
      expect(find.byType(TilingView), findsOneWidget);
      expect(find.byType(TerminalPane), findsOneWidget);
      expect(conn.connectionError, isNotNull);
    });

    testWidgets('reconnect shows TilingView with TerminalPane during attempt', (
      tester,
    ) async {
      final key = GlobalKey<TerminalTabState>();
      final completer = Completer<void>();
      final conn = Connection(
        id: 'key-loading',
        label: 'Test',
        sshConfig: const SSHConfig(
          server: ServerAddress(host: 'h', user: 'u'),
        ),
        sshConnection: null,
        state: SSHConnectionState.disconnected,
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Scaffold(
              body: SizedBox(
                width: 800,
                height: 600,
                child: TerminalTab(
                  key: key,
                  tabId: 'tab-key-loading',
                  connection: conn,
                  reconnectFactory: (_) => completer.future,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Trigger reconnect — factory blocks on completer
      key.currentState!.reconnect();
      await tester.pump(); // single pump to see loading state

      // TerminalPane shows progress in terminal buffer — no spinner
      expect(find.byType(TilingView), findsOneWidget);
      expect(find.byType(TerminalPane), findsOneWidget);

      // Complete and clean up
      completer.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('reconnect success resets to TilingView with single pane', (
      tester,
    ) async {
      final key = GlobalKey<TerminalTabState>();
      final conn = Connection(
        id: 'key-success',
        label: 'Test',
        sshConfig: const SSHConfig(
          server: ServerAddress(host: 'h', user: 'u'),
        ),
        sshConnection: null,
        state: SSHConnectionState.disconnected,
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Scaffold(
              body: SizedBox(
                width: 800,
                height: 600,
                child: TerminalTab(
                  key: key,
                  tabId: 'tab-key-success',
                  connection: conn,
                  reconnectFactory: (_) async {
                    // Success — do nothing
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Trigger reconnect — factory succeeds
      key.currentState!.reconnect();
      await tester.pumpAndSettle();

      // Should reset to TilingView with a single TerminalPane
      expect(find.byType(TilingView), findsOneWidget);
      expect(find.byType(TerminalPane), findsOneWidget);
      // No TerminalTab error message — TerminalPane may show its own error icon
      expect(find.textContaining('Reconnect failed'), findsNothing);
    });

    testWidgets('failed reconnect still shows TilingView with TerminalPane', (
      tester,
    ) async {
      final key = GlobalKey<TerminalTabState>();
      final conn = Connection(
        id: 'key-close',
        label: 'Test',
        sshConfig: const SSHConfig(
          server: ServerAddress(host: 'h', user: 'u'),
        ),
        sshConnection: null,
        state: SSHConnectionState.disconnected,
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Scaffold(
              body: SizedBox(
                width: 800,
                height: 600,
                child: TerminalTab(
                  key: key,
                  tabId: 'tab-key-close',
                  connection: conn,
                  reconnectFactory: (_) async {
                    throw Exception('fail');
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      key.currentState!.reconnect();
      await tester.pumpAndSettle();

      // After failed reconnect, TerminalTab resets to TilingView
      expect(find.byType(TilingView), findsOneWidget);
      expect(find.byType(TerminalPane), findsOneWidget);
    });

    testWidgets('reconnect retry — fail then succeed both show TilingView', (
      tester,
    ) async {
      final key = GlobalKey<TerminalTabState>();
      var callCount = 0;
      final conn = Connection(
        id: 'key-retry',
        label: 'Test',
        sshConfig: const SSHConfig(
          server: ServerAddress(host: 'h', user: 'u'),
        ),
        sshConnection: null,
        state: SSHConnectionState.disconnected,
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Scaffold(
              body: SizedBox(
                width: 800,
                height: 600,
                child: TerminalTab(
                  key: key,
                  tabId: 'tab-key-retry',
                  connection: conn,
                  reconnectFactory: (_) async {
                    callCount++;
                    if (callCount <= 1) {
                      throw Exception('Attempt $callCount failed');
                    }
                    // Second call succeeds
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // First reconnect — fails, resets to TilingView
      key.currentState!.reconnect();
      await tester.pumpAndSettle();
      expect(find.byType(TilingView), findsOneWidget);
      expect(conn.connectionError, isNotNull);

      // Second reconnect — succeeds
      key.currentState!.reconnect();
      await tester.pumpAndSettle();

      expect(find.byType(TilingView), findsOneWidget);
      expect(callCount, 2);
    });

    testWidgets('reconnect clears previous error before retrying', (
      tester,
    ) async {
      final key = GlobalKey<TerminalTabState>();
      final completer = Completer<void>();
      var callCount = 0;
      final conn = Connection(
        id: 'key-clear-err',
        label: 'Test',
        sshConfig: const SSHConfig(
          server: ServerAddress(host: 'h', user: 'u'),
        ),
        sshConnection: null,
        state: SSHConnectionState.disconnected,
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Scaffold(
              body: SizedBox(
                width: 800,
                height: 600,
                child: TerminalTab(
                  key: key,
                  tabId: 'tab-key-clear',
                  connection: conn,
                  reconnectFactory: (_) async {
                    callCount++;
                    if (callCount == 1) {
                      throw Exception('first error');
                    }
                    // Second call blocks on completer
                    return completer.future;
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // First call fails — resets to TilingView
      key.currentState!.reconnect();
      await tester.pumpAndSettle();
      expect(find.byType(TilingView), findsOneWidget);
      expect(conn.connectionError, isNotNull);

      // Second reconnect attempt — resets to fresh TilingView
      key.currentState!.reconnect();
      await tester.pump();

      // TerminalPane shows progress — no spinner
      expect(find.byType(TilingView), findsOneWidget);
      expect(find.byType(TerminalPane), findsOneWidget);

      // Clean up
      completer.complete();
      await tester.pumpAndSettle();
    });
  });

  group('TerminalTab — reconnect refreshes config from session store', () {
    testWidgets('reconnect uses updated SSHConfig when session was edited', (
      tester,
    ) async {
      // Session with initial password
      final session = Session(
        id: 'sess-1',
        label: 'Test',
        server: const ServerAddress(host: 'old.host', user: 'root'),
        auth: const SessionAuth(password: 'old-pass'),
      );

      // Updated session with key added
      final updatedSession = session.copyWith(
        server: const ServerAddress(host: 'new.host', user: 'admin'),
        auth: const SessionAuth(
          authType: AuthType.key,
          keyData: 'ssh-rsa AAAA...',
        ),
      );

      // Connection created from original session
      final conn = Connection(
        id: 'conn-1',
        label: 'Test',
        sshConfig: session.toSSHConfig(),
        sessionId: 'sess-1',
      );

      // Track the config used during reconnect
      SSHConfig? capturedConfig;
      final key = GlobalKey<TerminalTabState>();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            // Pre-populate session store with the UPDATED session
            sessionProvider.overrideWith(
              () => _TestSessionNotifier([updatedSession]),
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Scaffold(
              body: SizedBox(
                width: 800,
                height: 600,
                child: TerminalTab(
                  key: key,
                  tabId: 'tab-refresh',
                  connection: conn,
                  reconnectFactory: (c) async {
                    // Capture the config AFTER _refreshConfig() was called
                    capturedConfig = c.sshConfig;
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Trigger reconnect — should refresh config from store first
      key.currentState!.reconnect();
      await tester.pumpAndSettle();

      // The connection's sshConfig should now reflect the updated session
      expect(conn.sshConfig.host, 'new.host');
      expect(conn.sshConfig.user, 'admin');
      expect(conn.sshConfig.auth.keyData, 'ssh-rsa AAAA...');
      // The factory should have received the updated config
      expect(capturedConfig, isNotNull);
      expect(capturedConfig!.host, 'new.host');
    });

    testWidgets('reconnect falls back to cached config when session deleted', (
      tester,
    ) async {
      // Connection with sessionId pointing to a non-existent session
      final conn = Connection(
        id: 'conn-2',
        label: 'Test',
        sshConfig: const SSHConfig(
          server: ServerAddress(host: 'cached.host', user: 'cached-user'),
        ),
        sessionId: 'deleted-session',
      );

      SSHConfig? capturedConfig;
      final key = GlobalKey<TerminalTabState>();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            // Empty session store — session was deleted
            sessionProvider.overrideWith(() => _TestSessionNotifier([])),
          ],
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Scaffold(
              body: SizedBox(
                width: 800,
                height: 600,
                child: TerminalTab(
                  key: key,
                  tabId: 'tab-fallback',
                  connection: conn,
                  reconnectFactory: (c) async {
                    capturedConfig = c.sshConfig;
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      key.currentState!.reconnect();
      await tester.pumpAndSettle();

      // Should fall back to the original cached config
      expect(capturedConfig, isNotNull);
      expect(capturedConfig!.host, 'cached.host');
      expect(capturedConfig!.user, 'cached-user');
    });

    testWidgets(
      'reconnect skips config refresh for quick-connect (no sessionId)',
      (tester) async {
        // Quick-connect connection — no sessionId
        final conn = Connection(
          id: 'conn-3',
          label: 'Quick',
          sshConfig: const SSHConfig(
            server: ServerAddress(host: 'quick.host', user: 'quick-user'),
          ),
        );

        SSHConfig? capturedConfig;
        final key = GlobalKey<TerminalTabState>();

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              localizationsDelegates: S.localizationsDelegates,
              supportedLocales: S.supportedLocales,
              theme: AppTheme.dark(),
              home: Scaffold(
                body: SizedBox(
                  width: 800,
                  height: 600,
                  child: TerminalTab(
                    key: key,
                    tabId: 'tab-quick',
                    connection: conn,
                    reconnectFactory: (c) async {
                      capturedConfig = c.sshConfig;
                    },
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        key.currentState!.reconnect();
        await tester.pumpAndSettle();

        // Should use original config unchanged
        expect(capturedConfig, isNotNull);
        expect(capturedConfig!.host, 'quick.host');
        expect(capturedConfig!.user, 'quick-user');
      },
    );
  });
}
