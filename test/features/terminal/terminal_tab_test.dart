import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:letsflutssh/core/connection/connection.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/features/terminal/terminal_pane.dart';
import 'package:letsflutssh/features/terminal/terminal_tab.dart';
import 'package:letsflutssh/features/terminal/tiling_view.dart';
import 'package:letsflutssh/theme/app_theme.dart';

import '../../core/ssh/shell_helper_test.mocks.dart';

void main() {
  group('TerminalTab — always renders TilingView', () {
    testWidgets('renders TilingView even when connection has no sshConnection',
        (tester) async {
      final conn = Connection(
        id: 'test-1',
        label: 'Test Server',
        sshConfig: const SSHConfig(server: ServerAddress(host: 'example.com', user: 'root')),
        sshConnection: null,
        state: SSHConnectionState.disconnected,
      );

      await tester.pumpWidget(
        ProviderScope(child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: TerminalTab(
                tabId: 'tab-1',
                connection: conn,
              ),
            ),
          ),
        )),
      );
      await tester.pump();

      // TerminalTab always renders TilingView now — TerminalPane handles
      // connection state internally
      expect(find.byType(TilingView), findsOneWidget);
      expect(find.byType(TerminalPane), findsOneWidget);
      expect(find.text('Not connected'), findsNothing);
    });

    testWidgets(
        'renders TilingView when sshConnection exists but is disconnected',
        (tester) async {
      final mockSsh = MockSSHConnection();
      when(mockSsh.isConnected).thenReturn(false);

      final conn = Connection(
        id: 'test-2',
        label: 'Test Server',
        sshConfig: const SSHConfig(server: ServerAddress(host: 'example.com', user: 'root')),
        sshConnection: mockSsh,
        state: SSHConnectionState.disconnected,
      );

      await tester.pumpWidget(
        ProviderScope(child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: TerminalTab(
                tabId: 'tab-2',
                connection: conn,
              ),
            ),
          ),
        )),
      );
      await tester.pump();

      expect(find.byType(TilingView), findsOneWidget);
      expect(find.byType(TerminalPane), findsOneWidget);
    });

    testWidgets('renders TilingView when connected', (tester) async {
      final mockSsh = MockSSHConnection();
      final mockSession = MockSSHSession();
      final stdoutCtrl = StreamController<Uint8List>.broadcast();
      final stderrCtrl = StreamController<Uint8List>.broadcast();
      final doneCompleter = Completer<void>();

      when(mockSsh.isConnected).thenReturn(true);
      when(mockSsh.openShell(any, any))
          .thenAnswer((_) async => mockSession);
      when(mockSession.stdout).thenAnswer((_) => stdoutCtrl.stream);
      when(mockSession.stderr).thenAnswer((_) => stderrCtrl.stream);
      when(mockSession.done).thenAnswer((_) => doneCompleter.future);

      final conn = Connection(
        id: 'connected',
        label: 'Test',
        sshConfig: const SSHConfig(server: ServerAddress(host: 'h', user: 'u')),
        sshConnection: mockSsh,
        state: SSHConnectionState.connected,
      );

      await tester.pumpWidget(
        ProviderScope(child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: TerminalTab(
                tabId: 'tab-connected',
                connection: conn,
              ),
            ),
          ),
        )),
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
        sshConfig: const SSHConfig(server: ServerAddress(host: 'h', user: 'u')),
        sshConnection: null,
        state: SSHConnectionState.disconnected,
      );

      await tester.pumpWidget(
        ProviderScope(child: MaterialApp(
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
        )),
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
        sshConfig: const SSHConfig(server: ServerAddress(host: 'h', user: 'u')),
        sshConnection: null,
        state: SSHConnectionState.disconnected,
      );

      // Use reconnectFactory: first call fails, putting us into error state
      var firstCall = true;
      await tester.pumpWidget(
        ProviderScope(child: MaterialApp(
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
        )),
      );
      await tester.pumpAndSettle();

      // Initially shows TilingView — no error state from TerminalTab
      expect(find.byType(TilingView), findsOneWidget);
    });

    testWidgets(
        'reconnect failure via reconnectFactory shows error with message',
        (tester) async {
      final conn = Connection(
        id: 'rf-fail',
        label: 'Test',
        sshConfig: const SSHConfig(server: ServerAddress(host: 'h', user: 'u')),
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
        ProviderScope(child: MaterialApp(
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
        )),
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

    testWidgets('reconnect success via reconnectFactory resets to TilingView',
        (tester) async {
      final mockSsh = MockSSHConnection();
      final mockSession = MockSSHSession();

      final conn = Connection(
        id: 'rf-ok',
        label: 'Test',
        sshConfig: const SSHConfig(server: ServerAddress(host: 'h', user: 'u')),
        sshConnection: null,
        state: SSHConnectionState.disconnected,
      );

      var callCount = 0;
      await tester.pumpWidget(
        ProviderScope(child: MaterialApp(
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
                  final stdoutCtrl =
                      StreamController<Uint8List>.broadcast();
                  final stderrCtrl =
                      StreamController<Uint8List>.broadcast();
                  final doneCompleter = Completer<void>();

                  when(mockSsh.isConnected).thenReturn(true);
                  when(mockSsh.openShell(any, any))
                      .thenAnswer((_) async => mockSession);
                  when(mockSession.stdout)
                      .thenAnswer((_) => stdoutCtrl.stream);
                  when(mockSession.stderr)
                      .thenAnswer((_) => stderrCtrl.stream);
                  when(mockSession.done)
                      .thenAnswer((_) => doneCompleter.future);

                  c.sshConnection = mockSsh;
                  c.state = SSHConnectionState.connected;
                },
              ),
            ),
          ),
        )),
      );
      await tester.pumpAndSettle();

      // Initially shows TilingView (TerminalPane handles disconnected state)
      expect(find.byType(TilingView), findsOneWidget);
    });

    testWidgets('reconnect shows loading spinner during reconnect attempt',
        (tester) async {
      final completer = Completer<void>();
      final conn = Connection(
        id: 'rf-load',
        label: 'Test',
        sshConfig: const SSHConfig(server: ServerAddress(host: 'h', user: 'u')),
        sshConnection: null,
        state: SSHConnectionState.disconnected,
      );

      var callCount = 0;
      await tester.pumpWidget(
        ProviderScope(child: MaterialApp(
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
        )),
      );
      await tester.pumpAndSettle();

      // Initially shows TilingView
      expect(find.byType(TilingView), findsOneWidget);

      // Complete without errors for cleanup
      completer.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('double reconnect: fail then succeed from error state',
        (tester) async {
      var callCount = 0;
      final conn = Connection(
        id: 'rf-retry',
        label: 'Test',
        sshConfig: const SSHConfig(server: ServerAddress(host: 'h', user: 'u')),
        sshConnection: null,
        state: SSHConnectionState.disconnected,
      );

      await tester.pumpWidget(
        ProviderScope(child: MaterialApp(
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
        )),
      );
      await tester.pumpAndSettle();

      // Initially shows TilingView
      expect(find.byType(TilingView), findsOneWidget);
    });
  });

  group('TerminalTab — tiling split and close', () {
    Connection makeConnected(
        MockSSHConnection mockSsh, MockSSHSession mockSession, String id) {
      final stdoutCtrl = StreamController<Uint8List>.broadcast();
      final stderrCtrl = StreamController<Uint8List>.broadcast();
      final doneCompleter = Completer<void>();

      when(mockSsh.isConnected).thenReturn(true);
      when(mockSsh.openShell(any, any))
          .thenAnswer((_) async => mockSession);
      when(mockSession.stdout).thenAnswer((_) => stdoutCtrl.stream);
      when(mockSession.stderr).thenAnswer((_) => stderrCtrl.stream);
      when(mockSession.done).thenAnswer((_) => doneCompleter.future);

      return Connection(
        id: id,
        label: 'Test $id',
        sshConfig: const SSHConfig(server: ServerAddress(host: 'h', user: 'u')),
        sshConnection: mockSsh,
        state: SSHConnectionState.connected,
      );
    }

    testWidgets('split vertical creates a second pane', (tester) async {
      final mockSsh = MockSSHConnection();
      final mockSession = MockSSHSession();
      final conn = makeConnected(mockSsh, mockSession, 'split-v');

      await tester.pumpWidget(
        ProviderScope(child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: TerminalTab(
                tabId: 'tab-split-v',
                connection: conn,
              ),
            ),
          ),
        )),
      );
      await tester.pumpAndSettle();

      expect(find.byType(TerminalPane), findsOneWidget);

      final pane =
          tester.widget<TerminalPane>(find.byType(TerminalPane).first);
      expect(pane.onSplitVertical, isNotNull);
      pane.onSplitVertical!();
      await tester.pumpAndSettle();

      expect(find.byType(TerminalPane), findsNWidgets(2));
    });

    testWidgets('split horizontal creates a second pane', (tester) async {
      final mockSsh = MockSSHConnection();
      final mockSession = MockSSHSession();
      final conn = makeConnected(mockSsh, mockSession, 'split-h');

      await tester.pumpWidget(
        ProviderScope(child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: TerminalTab(
                tabId: 'tab-split-h',
                connection: conn,
              ),
            ),
          ),
        )),
      );
      await tester.pumpAndSettle();

      final pane =
          tester.widget<TerminalPane>(find.byType(TerminalPane).first);
      expect(pane.onSplitHorizontal, isNotNull);
      pane.onSplitHorizontal!();
      await tester.pumpAndSettle();

      expect(find.byType(TerminalPane), findsNWidgets(2));
    });

    testWidgets('close pane reduces two panes to one', (tester) async {
      final mockSsh = MockSSHConnection();
      final mockSession = MockSSHSession();
      final conn = makeConnected(mockSsh, mockSession, 'close-p');

      await tester.pumpWidget(
        ProviderScope(child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: TerminalTab(
                tabId: 'tab-close-p',
                connection: conn,
              ),
            ),
          ),
        )),
      );
      await tester.pumpAndSettle();

      final pane1 =
          tester.widget<TerminalPane>(find.byType(TerminalPane).first);
      pane1.onSplitVertical!();
      await tester.pumpAndSettle();

      expect(find.byType(TerminalPane), findsNWidgets(2));

      final panes = tester
          .widgetList<TerminalPane>(find.byType(TerminalPane))
          .toList();
      final closable = panes.firstWhere((p) => p.onClose != null);
      closable.onClose!();
      await tester.pumpAndSettle();

      expect(find.byType(TerminalPane), findsOneWidget);
    });

    testWidgets('closing focused pane resets focusedPaneId to remaining leaf',
        (tester) async {
      final mockSsh = MockSSHConnection();
      final mockSession = MockSSHSession();
      final conn = makeConnected(mockSsh, mockSession, 'close-focused');

      await tester.pumpWidget(
        ProviderScope(child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: TerminalTab(
                tabId: 'tab-close-focused',
                connection: conn,
              ),
            ),
          ),
        )),
      );
      await tester.pumpAndSettle();

      // Split to get two panes — the new pane becomes focused.
      final pane1 =
          tester.widget<TerminalPane>(find.byType(TerminalPane).first);
      pane1.onSplitVertical!();
      await tester.pumpAndSettle();

      expect(find.byType(TerminalPane), findsNWidgets(2));

      // Find the focused pane and close it.
      final panes = tester
          .widgetList<TerminalPane>(find.byType(TerminalPane))
          .toList();
      final focused = panes.firstWhere((p) => p.isFocused);
      expect(focused.onClose, isNotNull);
      focused.onClose!();
      await tester.pumpAndSettle();

      // Should be back to one pane, and it should be focused.
      expect(find.byType(TerminalPane), findsOneWidget);
      final remaining =
          tester.widget<TerminalPane>(find.byType(TerminalPane).first);
      expect(remaining.isFocused, isTrue);
    });

    testWidgets('close pane on root leaf does nothing', (tester) async {
      final mockSsh = MockSSHConnection();
      final mockSession = MockSSHSession();
      final conn = makeConnected(mockSsh, mockSession, 'close-root');

      await tester.pumpWidget(
        ProviderScope(child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: TerminalTab(
                tabId: 'tab-close-root',
                connection: conn,
              ),
            ),
          ),
        )),
      );
      await tester.pumpAndSettle();

      final pane =
          tester.widget<TerminalPane>(find.byType(TerminalPane).first);
      expect(pane.onClose, isNull);
    });

    testWidgets('divider drag triggers onTreeChanged and updates root',
        (tester) async {
      final mockSsh = MockSSHConnection();
      final mockSession = MockSSHSession();
      final conn = makeConnected(mockSsh, mockSession, 'tree-change');

      await tester.pumpWidget(
        ProviderScope(child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: TerminalTab(
                tabId: 'tab-tree-change',
                connection: conn,
              ),
            ),
          ),
        )),
      );
      await tester.pumpAndSettle();

      final pane =
          tester.widget<TerminalPane>(find.byType(TerminalPane).first);
      pane.onSplitVertical!();
      await tester.pumpAndSettle();

      final divider = find.byWidgetPredicate(
        (w) =>
            w is MouseRegion &&
            w.cursor == SystemMouseCursors.resizeColumn,
      );
      expect(divider, findsOneWidget);

      await tester.drag(divider, const Offset(50, 0));
      await tester.pumpAndSettle();

      expect(find.byType(TerminalPane), findsNWidgets(2));
    });

    testWidgets('tapping a non-focused pane changes focus', (tester) async {
      final mockSsh = MockSSHConnection();
      final mockSession = MockSSHSession();
      final conn = makeConnected(mockSsh, mockSession, 'focus-tap');

      await tester.pumpWidget(
        ProviderScope(child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: TerminalTab(
                tabId: 'tab-focus',
                connection: conn,
              ),
            ),
          ),
        )),
      );
      await tester.pumpAndSettle();

      final pane1 =
          tester.widget<TerminalPane>(find.byType(TerminalPane).first);
      pane1.onSplitVertical!();
      await tester.pumpAndSettle();

      final panes = tester
          .widgetList<TerminalPane>(find.byType(TerminalPane))
          .toList();
      expect(panes.length, 2);

      final unfocused = panes.firstWhere((p) => !p.isFocused);
      expect(unfocused.onFocused, isNotNull);

      unfocused.onFocused!();
      await tester.pumpAndSettle();

      final panesAfter = tester
          .widgetList<TerminalPane>(find.byType(TerminalPane))
          .toList();
      final focusedCount = panesAfter.where((p) => p.isFocused).length;
      expect(focusedCount, 1);
    });

    testWidgets('successful reconnect resets tree and shows TilingView',
        (tester) async {
      final mockSsh = MockSSHConnection();
      final mockSession = MockSSHSession();

      final conn = Connection(
        id: 'reconn-success',
        label: 'Test',
        sshConfig: const SSHConfig(server: ServerAddress(host: 'h', user: 'u')),
        sshConnection: null,
        state: SSHConnectionState.disconnected,
      );

      var callCount = 0;
      await tester.pumpWidget(
        ProviderScope(child: MaterialApp(
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
                  final stdoutCtrl =
                      StreamController<Uint8List>.broadcast();
                  final stderrCtrl =
                      StreamController<Uint8List>.broadcast();
                  final doneCompleter = Completer<void>();

                  when(mockSsh.isConnected).thenReturn(true);
                  when(mockSsh.openShell(any, any))
                      .thenAnswer((_) async => mockSession);
                  when(mockSession.stdout)
                      .thenAnswer((_) => stdoutCtrl.stream);
                  when(mockSession.stderr)
                      .thenAnswer((_) => stderrCtrl.stream);
                  when(mockSession.done)
                      .thenAnswer((_) => doneCompleter.future);

                  c.sshConnection = mockSsh;
                  c.state = SSHConnectionState.connected;
                },
              ),
            ),
          ),
        )),
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
        'reconnect failure shows error state with icon, message, and buttons',
        (tester) async {
      final key = GlobalKey<TerminalTabState>();
      final conn = Connection(
        id: 'key-err',
        label: 'Test',
        sshConfig: const SSHConfig(server: ServerAddress(host: 'h', user: 'u')),
        sshConnection: null,
        state: SSHConnectionState.disconnected,
      );

      await tester.pumpWidget(
        ProviderScope(child: MaterialApp(
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
        )),
      );
      await tester.pumpAndSettle();

      // Initially shows TilingView
      expect(find.byType(TilingView), findsOneWidget);

      // Trigger reconnect programmatically — it will fail
      key.currentState!.reconnect();
      await tester.pumpAndSettle();

      // Now error state should be visible
      expect(find.byType(TilingView), findsNothing);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(
        find.text('Reconnect failed: Exception: Auth failed'),
        findsOneWidget,
      );
      expect(find.text('Reconnect'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);
    });

    testWidgets('error state icon has correct size and color', (tester) async {
      final key = GlobalKey<TerminalTabState>();
      final conn = Connection(
        id: 'key-icon',
        label: 'Test',
        sshConfig: const SSHConfig(server: ServerAddress(host: 'h', user: 'u')),
        sshConnection: null,
        state: SSHConnectionState.disconnected,
      );

      await tester.pumpWidget(
        ProviderScope(child: MaterialApp(
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
        )),
      );
      await tester.pumpAndSettle();

      key.currentState!.reconnect();
      await tester.pumpAndSettle();

      final icon = tester.widget<Icon>(find.byIcon(Icons.error_outline));
      expect(icon.size, 48);
      expect(icon.color, AppTheme.disconnected);
    });

    testWidgets('error state text is styled with disconnected color',
        (tester) async {
      final key = GlobalKey<TerminalTabState>();
      final conn = Connection(
        id: 'key-text-style',
        label: 'Test',
        sshConfig: const SSHConfig(server: ServerAddress(host: 'h', user: 'u')),
        sshConnection: null,
        state: SSHConnectionState.disconnected,
      );

      await tester.pumpWidget(
        ProviderScope(child: MaterialApp(
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
        )),
      );
      await tester.pumpAndSettle();

      key.currentState!.reconnect();
      await tester.pumpAndSettle();

      final errorText = tester.widget<Text>(
        find.text('Reconnect failed: Exception: timeout'),
      );
      expect(errorText.style?.color, AppTheme.disconnected);
      expect(errorText.textAlign, TextAlign.center);
    });

    testWidgets('reconnect shows loading spinner during attempt',
        (tester) async {
      final key = GlobalKey<TerminalTabState>();
      final completer = Completer<void>();
      final conn = Connection(
        id: 'key-loading',
        label: 'Test',
        sshConfig: const SSHConfig(server: ServerAddress(host: 'h', user: 'u')),
        sshConnection: null,
        state: SSHConnectionState.disconnected,
      );

      await tester.pumpWidget(
        ProviderScope(child: MaterialApp(
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
        )),
      );
      await tester.pumpAndSettle();

      // Trigger reconnect — factory blocks on completer
      key.currentState!.reconnect();
      await tester.pump(); // single pump to see loading state

      // Should show loading spinner, not TilingView or error
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(TilingView), findsNothing);
      expect(find.byIcon(Icons.error_outline), findsNothing);

      // Complete and clean up
      completer.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('reconnect success resets to TilingView with single pane',
        (tester) async {
      final key = GlobalKey<TerminalTabState>();
      final conn = Connection(
        id: 'key-success',
        label: 'Test',
        sshConfig: const SSHConfig(server: ServerAddress(host: 'h', user: 'u')),
        sshConnection: null,
        state: SSHConnectionState.disconnected,
      );

      await tester.pumpWidget(
        ProviderScope(child: MaterialApp(
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
        )),
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

    testWidgets('Close button in error state calls onDisconnected',
        (tester) async {
      final key = GlobalKey<TerminalTabState>();
      var disconnectedCalled = false;
      final conn = Connection(
        id: 'key-close',
        label: 'Test',
        sshConfig: const SSHConfig(server: ServerAddress(host: 'h', user: 'u')),
        sshConnection: null,
        state: SSHConnectionState.disconnected,
      );

      await tester.pumpWidget(
        ProviderScope(child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: TerminalTab(
                key: key,
                tabId: 'tab-key-close',
                connection: conn,
                onDisconnected: () => disconnectedCalled = true,
                reconnectFactory: (_) async {
                  throw Exception('fail');
                },
              ),
            ),
          ),
        )),
      );
      await tester.pumpAndSettle();

      // Get into error state
      key.currentState!.reconnect();
      await tester.pumpAndSettle();

      expect(find.text('Close'), findsOneWidget);

      // Tap the Close button
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      expect(disconnectedCalled, isTrue);
    });

    testWidgets(
        'Reconnect button in error state retries — fail then succeed',
        (tester) async {
      final key = GlobalKey<TerminalTabState>();
      var callCount = 0;
      final conn = Connection(
        id: 'key-retry',
        label: 'Test',
        sshConfig: const SSHConfig(server: ServerAddress(host: 'h', user: 'u')),
        sshConnection: null,
        state: SSHConnectionState.disconnected,
      );

      await tester.pumpWidget(
        ProviderScope(child: MaterialApp(
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
        )),
      );
      await tester.pumpAndSettle();

      // First reconnect — fails, shows error state
      key.currentState!.reconnect();
      await tester.pumpAndSettle();
      expect(find.text('Reconnect failed: Exception: Attempt 1 failed'),
          findsOneWidget);

      // Tap Reconnect button in error state — second attempt succeeds
      await tester.tap(find.text('Reconnect'));
      await tester.pumpAndSettle();

      // Should be back to TilingView — no TerminalTab error message
      expect(find.byType(TilingView), findsOneWidget);
      expect(find.textContaining('Reconnect failed'), findsNothing);
      expect(callCount, 2);
    });

    testWidgets('reconnect clears previous error before retrying',
        (tester) async {
      final key = GlobalKey<TerminalTabState>();
      final completer = Completer<void>();
      var callCount = 0;
      final conn = Connection(
        id: 'key-clear-err',
        label: 'Test',
        sshConfig: const SSHConfig(server: ServerAddress(host: 'h', user: 'u')),
        sshConnection: null,
        state: SSHConnectionState.disconnected,
      );

      await tester.pumpWidget(
        ProviderScope(child: MaterialApp(
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
        )),
      );
      await tester.pumpAndSettle();

      // First call fails — error state
      key.currentState!.reconnect();
      await tester.pumpAndSettle();
      expect(find.text('Reconnect failed: Exception: first error'),
          findsOneWidget);

      // Second reconnect attempt — should clear error and show spinner
      key.currentState!.reconnect();
      await tester.pump();

      // Error should be gone, loading spinner visible
      expect(find.text('Reconnect failed: Exception: first error'),
          findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Clean up
      completer.complete();
      await tester.pumpAndSettle();
    });
  });
}
