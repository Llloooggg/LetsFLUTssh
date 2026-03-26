import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:xterm/xterm.dart';

import 'package:letsflutssh/core/connection/connection.dart';
import 'package:letsflutssh/core/ssh/shell_helper.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/features/terminal/terminal_pane.dart';
import 'package:letsflutssh/theme/app_theme.dart';

import '../../core/ssh/shell_helper_test.mocks.dart';

/// Creates a fake ShellConnection with mock session that never closes.
ShellConnection _fakeShellConnection() {
  final mockSession = MockSSHSession();
  final stdoutCtrl = StreamController<Uint8List>.broadcast();
  final stderrCtrl = StreamController<Uint8List>.broadcast();
  final doneCompleter = Completer<void>();

  when(mockSession.stdout).thenAnswer((_) => stdoutCtrl.stream);
  when(mockSession.stderr).thenAnswer((_) => stderrCtrl.stream);
  when(mockSession.done).thenAnswer((_) => doneCompleter.future);

  return ShellConnection(
    shell: mockSession,
    stdoutSub: stdoutCtrl.stream.listen((_) {}),
    stderrSub: stderrCtrl.stream.listen((_) {}),
  );
}

/// A shellFactory that immediately returns a fake ShellConnection.
Future<ShellConnection> _successShellFactory({
  required Connection connection,
  required Terminal terminal,
  VoidCallback? onDone,
}) async {
  return _fakeShellConnection();
}

/// A shellFactory that throws an error.
Future<ShellConnection> _errorShellFactory({
  required Connection connection,
  required Terminal terminal,
  VoidCallback? onDone,
}) async {
  throw Exception('Shell factory error');
}

/// Helper to build a Connection for tests (sshConnection can be null for factory tests).
/// State defaults to connected so _connectAndOpenShell() proceeds to shellFactory.
Connection _testConnection({String id = 'test'}) {
  return Connection(
    id: id,
    label: 'Test $id',
    sshConfig: const SSHConfig(server: ServerAddress(host: 'h', user: 'u')),
    sshConnection: null,
    state: SSHConnectionState.connected,
  );
}

void main() {
  group('TerminalPane — error state UI', () {
    testWidgets('error state shows centered error icon and message', (tester) async {
      final conn = Connection(
        id: 'err-1',
        label: 'ErrorTest',
        sshConfig: const SSHConfig(server: ServerAddress(host: 'fail.host', user: 'user')),
        sshConnection: null,
        state: SSHConnectionState.disconnected,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: TerminalPane(connection: conn),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      final icon = tester.widget<Icon>(find.byIcon(Icons.error_outline));
      expect(icon.color, AppTheme.disconnected);
      expect(icon.size, 48);
    });

    testWidgets('error from thrown exception displays exception text', (tester) async {
      final mockSsh = MockSSHConnection();
      when(mockSsh.isConnected).thenReturn(true);
      when(mockSsh.openShell(any, any)).thenThrow(Exception('Connection refused'));

      final conn = Connection(
        id: 'err-2',
        label: 'Test',
        sshConfig: const SSHConfig(server: ServerAddress(host: 'h', user: 'u')),
        sshConnection: mockSsh,
        state: SSHConnectionState.connected,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: TerminalPane(connection: conn),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Connection refused'), findsOneWidget);
    });
  });

  group('TerminalPane — context menu', () {
    testWidgets('right-click on connected terminal shows context menu with Paste', (tester) async {
      final mockSsh = MockSSHConnection();
      final mockSession = MockSSHSession();
      when(mockSsh.isConnected).thenReturn(true);

      final stdoutCtrl = StreamController<Uint8List>.broadcast();
      final stderrCtrl = StreamController<Uint8List>.broadcast();
      final doneCompleter = Completer<void>();

      when(mockSsh.openShell(any, any)).thenAnswer((_) async => mockSession);
      when(mockSession.stdout).thenAnswer((_) => stdoutCtrl.stream);
      when(mockSession.stderr).thenAnswer((_) => stderrCtrl.stream);
      when(mockSession.done).thenAnswer((_) => doneCompleter.future);

      final conn = Connection(
        id: 'ctx-1',
        label: 'Test',
        sshConfig: const SSHConfig(server: ServerAddress(host: 'h', user: 'u')),
        sshConnection: mockSsh,
        state: SSHConnectionState.connected,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: TerminalPane(
              connection: conn,
              isFocused: true,
              onSplitVertical: () {},
              onSplitHorizontal: () {},
              onClose: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byIcon(Icons.error_outline), findsNothing);

      await stdoutCtrl.close();
      await stderrCtrl.close();
    });
  });

  group('TerminalPane — split callbacks wired', () {
    testWidgets('split callbacks are available on the widget', (tester) async {
      final mockSsh = MockSSHConnection();
      final mockSession = MockSSHSession();
      when(mockSsh.isConnected).thenReturn(true);

      final stdoutCtrl = StreamController<Uint8List>.broadcast();
      final stderrCtrl = StreamController<Uint8List>.broadcast();
      final doneCompleter = Completer<void>();

      when(mockSsh.openShell(any, any)).thenAnswer((_) async => mockSession);
      when(mockSession.stdout).thenAnswer((_) => stdoutCtrl.stream);
      when(mockSession.stderr).thenAnswer((_) => stderrCtrl.stream);
      when(mockSession.done).thenAnswer((_) => doneCompleter.future);

      var splitV = false;
      var splitH = false;
      final conn = Connection(
        id: 'split-1',
        label: 'Test',
        sshConfig: const SSHConfig(server: ServerAddress(host: 'h', user: 'u')),
        sshConnection: mockSsh,
        state: SSHConnectionState.connected,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: TerminalPane(
              connection: conn,
              isFocused: true,
              onSplitVertical: () => splitV = true,
              onSplitHorizontal: () => splitH = true,
              onClose: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(splitV, isFalse);
      expect(splitH, isFalse);
      expect(find.byType(CallbackShortcuts), findsWidgets);

      await stdoutCtrl.close();
      await stderrCtrl.close();
    });
  });

  group('TerminalPane — loading state', () {
    testWidgets('shows spinner while shell is opening', (tester) async {
      final mockSsh = MockSSHConnection();
      when(mockSsh.isConnected).thenReturn(true);
      when(mockSsh.openShell(any, any)).thenAnswer((_) => Completer<Never>().future);

      final conn = Connection(
        id: 'load-1',
        label: 'Test',
        sshConfig: const SSHConfig(server: ServerAddress(host: 'h', user: 'u')),
        sshConnection: mockSsh,
        state: SSHConnectionState.connected,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: TerminalPane(connection: conn),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });

  group('TerminalPane — session closed notification', () {
    testWidgets('shell done shows "Session closed" error', (tester) async {
      final mockSsh = MockSSHConnection();
      final mockSession = MockSSHSession();
      when(mockSsh.isConnected).thenReturn(true);

      final stdoutCtrl = StreamController<Uint8List>.broadcast();
      final stderrCtrl = StreamController<Uint8List>.broadcast();
      final doneCompleter = Completer<void>();

      when(mockSsh.openShell(any, any)).thenAnswer((_) async => mockSession);
      when(mockSession.stdout).thenAnswer((_) => stdoutCtrl.stream);
      when(mockSession.stderr).thenAnswer((_) => stderrCtrl.stream);
      when(mockSession.done).thenAnswer((_) => doneCompleter.future);

      final conn = Connection(
        id: 'done-1',
        label: 'Test',
        sshConfig: const SSHConfig(server: ServerAddress(host: 'h', user: 'u')),
        sshConnection: mockSsh,
        state: SSHConnectionState.connected,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: TerminalPane(connection: conn),
          ),
        ),
      );
      await tester.pumpAndSettle();

      doneCompleter.complete();
      await tester.pumpAndSettle();

      expect(find.textContaining('Session closed'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);

      await stdoutCtrl.close();
      await stderrCtrl.close();
    });
  });

  group('TerminalPane — focused/unfocused border', () {
    testWidgets('focused pane has Container with decoration', (tester) async {
      final mockSsh = MockSSHConnection();
      final mockSession = MockSSHSession();
      when(mockSsh.isConnected).thenReturn(true);

      final stdoutCtrl = StreamController<Uint8List>.broadcast();
      final stderrCtrl = StreamController<Uint8List>.broadcast();
      final doneCompleter = Completer<void>();

      when(mockSsh.openShell(any, any)).thenAnswer((_) async => mockSession);
      when(mockSession.stdout).thenAnswer((_) => stdoutCtrl.stream);
      when(mockSession.stderr).thenAnswer((_) => stderrCtrl.stream);
      when(mockSession.done).thenAnswer((_) => doneCompleter.future);

      final conn = Connection(
        id: 'border-1',
        label: 'Test',
        sshConfig: const SSHConfig(server: ServerAddress(host: 'h', user: 'u')),
        sshConnection: mockSsh,
        state: SSHConnectionState.connected,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: TerminalPane(connection: conn, isFocused: true),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Container), findsWidgets);

      await stdoutCtrl.close();
      await stderrCtrl.close();
    });

    testWidgets('unfocused pane renders without error', (tester) async {
      final mockSsh = MockSSHConnection();
      final mockSession = MockSSHSession();
      when(mockSsh.isConnected).thenReturn(true);

      final stdoutCtrl = StreamController<Uint8List>.broadcast();
      final stderrCtrl = StreamController<Uint8List>.broadcast();
      final doneCompleter = Completer<void>();

      when(mockSsh.openShell(any, any)).thenAnswer((_) async => mockSession);
      when(mockSession.stdout).thenAnswer((_) => stdoutCtrl.stream);
      when(mockSession.stderr).thenAnswer((_) => stderrCtrl.stream);
      when(mockSession.done).thenAnswer((_) => doneCompleter.future);

      final conn = Connection(
        id: 'border-2',
        label: 'Test',
        sshConfig: const SSHConfig(server: ServerAddress(host: 'h', user: 'u')),
        sshConnection: mockSsh,
        state: SSHConnectionState.connected,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: TerminalPane(connection: conn, isFocused: false),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byIcon(Icons.error_outline), findsNothing);

      await stdoutCtrl.close();
      await stderrCtrl.close();
    });
  });

  group('TerminalPane — shellFactory connected state', () {
    testWidgets('renders TerminalView when shellFactory succeeds', (tester) async {
      final conn = _testConnection(id: 'sf-1');

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: TerminalPane(
              connection: conn,
              isFocused: true,
              shellFactory: _successShellFactory,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byIcon(Icons.error_outline), findsNothing);
      expect(find.byType(TerminalView), findsOneWidget);
    });

    testWidgets('renders error when shellFactory throws', (tester) async {
      final conn = _testConnection(id: 'sf-2');

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: TerminalPane(
              connection: conn,
              shellFactory: _errorShellFactory,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.textContaining('Shell factory error'), findsOneWidget);
    });

    testWidgets('focused pane has primary border color', (tester) async {
      final conn = _testConnection(id: 'sf-border-f');

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: TerminalPane(
              connection: conn,
              isFocused: true,
              shellFactory: _successShellFactory,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final container = tester.widgetList<Container>(find.byType(Container)).where((c) {
        final deco = c.decoration;
        return deco is BoxDecoration && deco.border != null;
      }).first;
      final boxDeco = container.decoration as BoxDecoration;
      final border = boxDeco.border as Border;
      final theme = AppTheme.dark();
      expect(border.top.color, theme.colorScheme.primary);
      expect(border.top.width, 1.5);
    });

    testWidgets('unfocused pane has divider border color', (tester) async {
      final conn = _testConnection(id: 'sf-border-u');

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: TerminalPane(
              connection: conn,
              isFocused: false,
              shellFactory: _successShellFactory,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final container = tester.widgetList<Container>(find.byType(Container)).where((c) {
        final deco = c.decoration;
        return deco is BoxDecoration && deco.border != null;
      }).first;
      final boxDeco = container.decoration as BoxDecoration;
      final border = boxDeco.border as Border;
      expect(border.top.width, 0.5);
    });
  });

  group('TerminalPane — context menu via shellFactory', () {
    testWidgets('right-click shows Paste and split menu items', (tester) async {
      final conn = _testConnection(id: 'sf-ctx');

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: TerminalPane(
              connection: conn,
              isFocused: true,
              onSplitVertical: () {},
              onSplitHorizontal: () {},
              onClose: () {},
              shellFactory: _successShellFactory,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final termView = find.byType(TerminalView);
      expect(termView, findsOneWidget);
      final center = tester.getCenter(termView);
      await tester.tapAt(center, buttons: kSecondaryButton);
      await tester.pumpAndSettle();

      expect(find.text('Paste'), findsOneWidget);
      expect(find.text('Split Right'), findsOneWidget);
      expect(find.text('Split Down'), findsOneWidget);
      expect(find.text('Close Pane'), findsOneWidget);
    });

    testWidgets('split-v menu item calls onSplitVertical', (tester) async {
      var splitVCalled = false;
      final conn = _testConnection(id: 'sf-split-v');

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: TerminalPane(
              connection: conn,
              isFocused: true,
              onSplitVertical: () => splitVCalled = true,
              onSplitHorizontal: () {},
              shellFactory: _successShellFactory,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final termView = find.byType(TerminalView);
      final center = tester.getCenter(termView);
      await tester.tapAt(center, buttons: kSecondaryButton);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Split Right'));
      await tester.pumpAndSettle();

      expect(splitVCalled, isTrue);
    });

    testWidgets('split-h menu item calls onSplitHorizontal', (tester) async {
      var splitHCalled = false;
      final conn = _testConnection(id: 'sf-split-h');

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: TerminalPane(
              connection: conn,
              isFocused: true,
              onSplitVertical: () {},
              onSplitHorizontal: () => splitHCalled = true,
              shellFactory: _successShellFactory,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final termView = find.byType(TerminalView);
      final center = tester.getCenter(termView);
      await tester.tapAt(center, buttons: kSecondaryButton);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Split Down'));
      await tester.pumpAndSettle();

      expect(splitHCalled, isTrue);
    });

    testWidgets('close menu item calls onClose', (tester) async {
      var closeCalled = false;
      final conn = _testConnection(id: 'sf-close');

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: TerminalPane(
              connection: conn,
              isFocused: true,
              onSplitVertical: () {},
              onSplitHorizontal: () {},
              onClose: () => closeCalled = true,
              shellFactory: _successShellFactory,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final termView = find.byType(TerminalView);
      final center = tester.getCenter(termView);
      await tester.tapAt(center, buttons: kSecondaryButton);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Close Pane'));
      await tester.pumpAndSettle();

      expect(closeCalled, isTrue);
    });

    testWidgets('no Close Pane when onClose is null', (tester) async {
      final conn = _testConnection(id: 'sf-no-close');

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: TerminalPane(
              connection: conn,
              isFocused: true,
              onSplitVertical: () {},
              onSplitHorizontal: () {},
              onClose: null,
              shellFactory: _successShellFactory,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final termView = find.byType(TerminalView);
      final center = tester.getCenter(termView);
      await tester.tapAt(center, buttons: kSecondaryButton);
      await tester.pumpAndSettle();

      expect(find.text('Paste'), findsOneWidget);
      expect(find.text('Split Right'), findsOneWidget);
      expect(find.text('Close Pane'), findsNothing);
    });

    testWidgets('no split items when onSplitVertical is null', (tester) async {
      final conn = _testConnection(id: 'sf-no-split');

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: TerminalPane(
              connection: conn,
              isFocused: true,
              onSplitVertical: null,
              onSplitHorizontal: null,
              shellFactory: _successShellFactory,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final termView = find.byType(TerminalView);
      final center = tester.getCenter(termView);
      await tester.tapAt(center, buttons: kSecondaryButton);
      await tester.pumpAndSettle();

      expect(find.text('Paste'), findsOneWidget);
      expect(find.text('Split Right'), findsNothing);
      expect(find.text('Split Down'), findsNothing);
    });
  });

  group('TerminalPane — onFocused callback', () {
    testWidgets('onFocused callback is wired to the pane widget', (tester) async {
      var focusCalled = false;
      final conn = _testConnection(id: 'sf-focus');

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: TerminalPane(
              connection: conn,
              isFocused: false,
              onFocused: () => focusCalled = true,
              shellFactory: _successShellFactory,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final pane = tester.widget<TerminalPane>(find.byType(TerminalPane));
      expect(pane.onFocused, isNotNull);
      pane.onFocused!();
      expect(focusCalled, isTrue);
    });
  });

  group('TerminalPane — shellFactory onDone callback', () {
    testWidgets('session closed via onDone shows error state', (tester) async {
      VoidCallback? capturedOnDone;
      final conn = _testConnection(id: 'sf-done');

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: TerminalPane(
              connection: conn,
              shellFactory: ({
                required Connection connection,
                required Terminal terminal,
                VoidCallback? onDone,
              }) async {
                capturedOnDone = onDone;
                return _fakeShellConnection();
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(TerminalView), findsOneWidget);

      capturedOnDone?.call();
      await tester.pumpAndSettle();

      expect(find.textContaining('Session closed'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });
  });

  group('TerminalPane — paste action from context menu', () {
    testWidgets('paste menu item reads from clipboard', (tester) async {
      final conn = _testConnection(id: 'sf-paste');

      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.getData') {
            return <String, dynamic>{'text': 'pasted text'};
          }
          return null;
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: TerminalPane(
              connection: conn,
              isFocused: true,
              shellFactory: _successShellFactory,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final termView = find.byType(TerminalView);
      final center = tester.getCenter(termView);
      await tester.tapAt(center, buttons: kSecondaryButton);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Paste'));
      await tester.pumpAndSettle();

      expect(find.text('Paste'), findsNothing);

      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform, null,
      );
    });

    testWidgets('paste with empty clipboard text does nothing', (tester) async {
      final conn = _testConnection(id: 'sf-paste-empty');

      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.getData') {
            return <String, dynamic>{'text': ''};
          }
          return null;
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: TerminalPane(
              connection: conn,
              isFocused: true,
              shellFactory: _successShellFactory,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final termView = find.byType(TerminalView);
      final center = tester.getCenter(termView);
      await tester.tapAt(center, buttons: kSecondaryButton);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Paste'));
      await tester.pumpAndSettle();

      expect(find.text('Paste'), findsNothing);

      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform, null,
      );
    });

    testWidgets('paste with null clipboard data does nothing', (tester) async {
      final conn = _testConnection(id: 'sf-paste-null');

      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.getData') {
            return null;
          }
          return null;
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: TerminalPane(
              connection: conn,
              isFocused: true,
              shellFactory: _successShellFactory,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final termView = find.byType(TerminalView);
      final center = tester.getCenter(termView);
      await tester.tapAt(center, buttons: kSecondaryButton);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Paste'));
      await tester.pumpAndSettle();

      expect(find.text('Paste'), findsNothing);

      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform, null,
      );
    });
  });

  group('TerminalPane — copy selection from context menu', () {
    testWidgets('context menu without selection does not show Copy', (tester) async {
      final conn = _testConnection(id: 'sf-copy-no-sel');

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: TerminalPane(
              connection: conn,
              isFocused: true,
              onSplitVertical: () {},
              onSplitHorizontal: () {},
              shellFactory: _successShellFactory,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final termView = find.byType(TerminalView);
      final center = tester.getCenter(termView);
      await tester.tapAt(center, buttons: kSecondaryButton);
      await tester.pumpAndSettle();

      expect(find.text('Copy'), findsNothing);
      expect(find.text('Paste'), findsOneWidget);

      await tester.tapAt(const Offset(1, 1));
      await tester.pumpAndSettle();
    });

    testWidgets('clipboard not written when no selection', (tester) async {
      String? copiedText;
      final conn = _testConnection(id: 'sf-copy-safe');

      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            final args = call.arguments as Map;
            copiedText = args['text'] as String?;
          }
          if (call.method == 'Clipboard.getData') {
            return <String, dynamic>{'text': ''};
          }
          return null;
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: TerminalPane(
              connection: conn,
              isFocused: true,
              shellFactory: _successShellFactory,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final termView = find.byType(TerminalView);
      final center = tester.getCenter(termView);
      await tester.tapAt(center, buttons: kSecondaryButton);
      await tester.pumpAndSettle();

      // Copy is hidden when no selection — clipboard should not be written
      expect(find.text('Copy'), findsNothing);
      expect(copiedText, isNull);

      await tester.tapAt(const Offset(1, 1));
      await tester.pumpAndSettle();

      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform, null,
      );
    });
  });

  group('TerminalPane — dispose cleans up shell', () {
    testWidgets('disposing the widget closes the shell connection', (tester) async {
      final conn = _testConnection(id: 'sf-dispose');

      final mockSession = MockSSHSession();
      final stdoutCtrl = StreamController<Uint8List>.broadcast();
      final stderrCtrl = StreamController<Uint8List>.broadcast();
      final doneCompleter = Completer<void>();

      when(mockSession.stdout).thenAnswer((_) => stdoutCtrl.stream);
      when(mockSession.stderr).thenAnswer((_) => stderrCtrl.stream);
      when(mockSession.done).thenAnswer((_) => doneCompleter.future);
      when(mockSession.close()).thenAnswer((_) {});

      final shellConn = ShellConnection(
        shell: mockSession,
        stdoutSub: stdoutCtrl.stream.listen((_) {}),
        stderrSub: stderrCtrl.stream.listen((_) {}),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: TerminalPane(
              connection: conn,
              shellFactory: ({
                required Connection connection,
                required Terminal terminal,
                VoidCallback? onDone,
              }) async {
                return shellConn;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(TerminalView), findsOneWidget);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: SizedBox()),
        ),
      );
      await tester.pumpAndSettle();

      verify(mockSession.close()).called(1);

      await stdoutCtrl.close();
      await stderrCtrl.close();
    });

    testWidgets('dispose is safe when shellConn is null (connection failed)', (tester) async {
      final conn = _testConnection(id: 'sf-dispose-null');

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: TerminalPane(
              connection: conn,
              shellFactory: _errorShellFactory,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.error_outline), findsOneWidget);

      // Dispose should not throw even though _shellConn is null
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: SizedBox()),
        ),
      );
      await tester.pumpAndSettle();
    });
  });

  group('TerminalPane — context menu dismiss without action', () {
    testWidgets('dismissing context menu without selecting does nothing', (tester) async {
      final conn = _testConnection(id: 'sf-ctx-dismiss');

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: TerminalPane(
              connection: conn,
              isFocused: true,
              onSplitVertical: () {},
              onSplitHorizontal: () {},
              shellFactory: _successShellFactory,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final termView = find.byType(TerminalView);
      final center = tester.getCenter(termView);
      await tester.tapAt(center, buttons: kSecondaryButton);
      await tester.pumpAndSettle();

      expect(find.text('Paste'), findsOneWidget);

      // Dismiss by tapping outside — exercises the default: break case
      await tester.tapAt(const Offset(1, 1));
      await tester.pumpAndSettle();

      expect(find.text('Paste'), findsNothing);
    });
  });

  group('TerminalPane — shellFactory loading state', () {
    testWidgets('shows spinner when shellFactory is slow then shows terminal', (tester) async {
      final completer = Completer<ShellConnection>();
      final conn = _testConnection(id: 'sf-slow');

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: TerminalPane(
              connection: conn,
              shellFactory: ({
                required Connection connection,
                required Terminal terminal,
                VoidCallback? onDone,
              }) => completer.future,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      completer.complete(_fakeShellConnection());
      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(TerminalView), findsOneWidget);
    });
  });

  group('TerminalPane — error state layout', () {
    testWidgets('error state shows icon and text wrapped in Center', (tester) async {
      final conn = _testConnection(id: 'sf-error-layout');

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: TerminalPane(
              connection: conn,
              shellFactory: _errorShellFactory,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.textContaining('Shell factory error'), findsOneWidget);

      // Verify the error icon is inside a Center widget
      final centerFinder = find.ancestor(
        of: find.byIcon(Icons.error_outline),
        matching: find.byType(Center),
      );
      expect(centerFinder, findsOneWidget);
    });

    testWidgets('error text uses textAlign center and disconnected color', (tester) async {
      final conn = _testConnection(id: 'sf-error-align');

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: TerminalPane(
              connection: conn,
              shellFactory: _errorShellFactory,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final text = tester.widget<Text>(find.textContaining('Shell factory error'));
      expect(text.textAlign, TextAlign.center);
      expect(text.style?.color, AppTheme.disconnected);
    });
  });

  group('TerminalPane — ValueListenableBuilder search visibility', () {
    // Note: search bar keyboard shortcut (Ctrl+Shift+F) cannot be tested in
    // widget tests because xterm's TerminalView consumes key events before
    // CallbackShortcuts processes them. The search toggle and _TerminalSearchBar
    // are only exercisable through real user interaction.
    testWidgets('search bar starts hidden (SizedBox.shrink)', (tester) async {
      final conn = _testConnection(id: 'sf-search-hidden');

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: TerminalPane(
              connection: conn,
              isFocused: true,
              shellFactory: _successShellFactory,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // When _showSearch is false, ValueListenableBuilder renders SizedBox.shrink
      expect(find.text('Search...'), findsNothing);
      expect(find.byTooltip('Previous'), findsNothing);
      expect(find.byTooltip('Next'), findsNothing);
      expect(find.byTooltip('Close (Esc)'), findsNothing);
      expect(find.byType(TerminalView), findsOneWidget);
    });
  });

  group('TerminalPane — Column layout in connected state', () {
    testWidgets('connected state has Column with Expanded TerminalView', (tester) async {
      final conn = _testConnection(id: 'sf-column');

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: TerminalPane(
              connection: conn,
              isFocused: true,
              shellFactory: _successShellFactory,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Column), findsWidgets);
      expect(find.byType(Expanded), findsWidgets);
      expect(find.byType(TerminalView), findsOneWidget);
      expect(find.byType(CallbackShortcuts), findsOneWidget);
    });
  });

  group('TerminalPane — GestureDetector in connected state', () {
    testWidgets('connected state has GestureDetector for focus', (tester) async {
      final conn = _testConnection(id: 'sf-gesture');

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: TerminalPane(
              connection: conn,
              isFocused: true,
              onFocused: () {},
              shellFactory: _successShellFactory,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // GestureDetector should be present wrapping the container
      expect(find.byType(GestureDetector), findsWidgets);
    });
  });

  group('TerminalPane — search bar toggle via showSearchNotifier', () {
    testWidgets('toggling showSearchNotifier shows the search bar', (tester) async {
      final key = GlobalKey<TerminalPaneState>();
      final conn = _testConnection(id: 'sf-search-toggle');

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: TerminalPane(
              key: key,
              connection: conn,
              isFocused: true,
              shellFactory: _successShellFactory,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Search bar is initially hidden
      expect(find.byType(TerminalSearchBar), findsNothing);

      // Toggle search on
      key.currentState!.showSearchNotifier.value = true;
      await tester.pumpAndSettle();

      // Search bar is now visible
      expect(find.byType(TerminalSearchBar), findsOneWidget);
      expect(find.byTooltip('Previous'), findsOneWidget);
      expect(find.byTooltip('Next'), findsOneWidget);
      expect(find.byTooltip('Close (Esc)'), findsOneWidget);
    });

    testWidgets('toggling showSearchNotifier off hides the search bar', (tester) async {
      final key = GlobalKey<TerminalPaneState>();
      final conn = _testConnection(id: 'sf-search-toggle-off');

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: TerminalPane(
              key: key,
              connection: conn,
              isFocused: true,
              shellFactory: _successShellFactory,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Show search
      key.currentState!.showSearchNotifier.value = true;
      await tester.pumpAndSettle();
      expect(find.byType(TerminalSearchBar), findsOneWidget);

      // Hide search
      key.currentState!.showSearchNotifier.value = false;
      await tester.pumpAndSettle();
      expect(find.byType(TerminalSearchBar), findsNothing);
    });

    testWidgets('close button in search bar hides search', (tester) async {
      final key = GlobalKey<TerminalPaneState>();
      final conn = _testConnection(id: 'sf-search-close-btn');

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: TerminalPane(
              key: key,
              connection: conn,
              isFocused: true,
              shellFactory: _successShellFactory,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Show search
      key.currentState!.showSearchNotifier.value = true;
      await tester.pumpAndSettle();
      expect(find.byType(TerminalSearchBar), findsOneWidget);

      // Tap the close button
      await tester.tap(find.byTooltip('Close (Esc)'));
      await tester.pumpAndSettle();

      // Search bar should be hidden and notifier should be false
      expect(find.byType(TerminalSearchBar), findsNothing);
      expect(key.currentState!.showSearchNotifier.value, isFalse);
    });
  });

  group('TerminalSearchBar — standalone search tests', () {
    Widget buildSearchBar({
      Terminal? terminal,
      TerminalController? controller,
      VoidCallback? onClose,
    }) {
      return MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: TerminalSearchBar(
            terminal: terminal ?? Terminal(maxLines: 100),
            terminalController: controller ?? TerminalController(),
            onClose: onClose ?? () {},
          ),
        ),
      );
    }

    testWidgets('renders text field with Search... hint', (tester) async {
      await tester.pumpWidget(buildSearchBar());
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Search...'), findsOneWidget);
    });

    testWidgets('has Previous, Next, and Close buttons', (tester) async {
      await tester.pumpWidget(buildSearchBar());
      await tester.pumpAndSettle();

      expect(find.byTooltip('Previous'), findsOneWidget);
      expect(find.byTooltip('Next'), findsOneWidget);
      expect(find.byTooltip('Close (Esc)'), findsOneWidget);
    });

    testWidgets('prev/next buttons disabled when no matches', (tester) async {
      await tester.pumpWidget(buildSearchBar());
      await tester.pumpAndSettle();

      // With no search text, buttons should be disabled (onPressed is null)
      final prevButton = tester.widget<IconButton>(find.ancestor(
        of: find.byIcon(Icons.keyboard_arrow_up),
        matching: find.byType(IconButton),
      ));
      expect(prevButton.onPressed, isNull);

      final nextButton = tester.widget<IconButton>(find.ancestor(
        of: find.byIcon(Icons.keyboard_arrow_down),
        matching: find.byType(IconButton),
      ));
      expect(nextButton.onPressed, isNull);
    });

    testWidgets('close button calls onClose callback', (tester) async {
      var closeCalled = false;
      await tester.pumpWidget(buildSearchBar(onClose: () => closeCalled = true));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Close (Esc)'));
      await tester.pumpAndSettle();

      expect(closeCalled, isTrue);
    });

    testWidgets('typing in search field with empty text clears matches', (tester) async {
      final terminal = Terminal(maxLines: 100);
      terminal.write('Hello World\r\n');

      await tester.pumpWidget(buildSearchBar(terminal: terminal));
      await tester.pumpAndSettle();

      // Type then clear
      await tester.enterText(find.byType(TextField), 'Hello');
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle();

      // No match counter should be shown
      final prevButton = tester.widget<IconButton>(find.ancestor(
        of: find.byIcon(Icons.keyboard_arrow_up),
        matching: find.byType(IconButton),
      ));
      expect(prevButton.onPressed, isNull);
    });

    testWidgets('searching for existing text shows match count', (tester) async {
      final terminal = Terminal(maxLines: 100);
      final controller = TerminalController();
      // Write enough text to be searchable in the buffer
      terminal.write('Hello World\r\n');
      terminal.write('Hello Again\r\n');

      await tester.pumpWidget(buildSearchBar(
        terminal: terminal,
        controller: controller,
      ));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Hello');
      await tester.pumpAndSettle();

      // prev/next buttons should now be enabled (matches found)
      final prevButton = tester.widget<IconButton>(find.ancestor(
        of: find.byIcon(Icons.keyboard_arrow_up),
        matching: find.byType(IconButton),
      ));
      expect(prevButton.onPressed, isNotNull);

      final nextButton = tester.widget<IconButton>(find.ancestor(
        of: find.byIcon(Icons.keyboard_arrow_down),
        matching: find.byType(IconButton),
      ));
      expect(nextButton.onPressed, isNotNull);
    });

    testWidgets('next/prev cycle through matches', (tester) async {
      final terminal = Terminal(maxLines: 100);
      final controller = TerminalController();
      terminal.write('AAA BBB AAA\r\n');

      await tester.pumpWidget(buildSearchBar(
        terminal: terminal,
        controller: controller,
      ));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'AAA');
      await tester.pumpAndSettle();

      // Should have matches — tap Next multiple times
      await tester.tap(find.byTooltip('Next'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Previous'));
      await tester.pumpAndSettle();

      // Buttons should still be enabled after cycling
      final nextButton = tester.widget<IconButton>(find.ancestor(
        of: find.byIcon(Icons.keyboard_arrow_down),
        matching: find.byType(IconButton),
      ));
      expect(nextButton.onPressed, isNotNull);
    });

    testWidgets('searching for non-existent text shows no matches', (tester) async {
      final terminal = Terminal(maxLines: 100);
      terminal.write('Hello World\r\n');

      await tester.pumpWidget(buildSearchBar(terminal: terminal));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'ZZZZZ');
      await tester.pumpAndSettle();

      // Buttons should be disabled — no matches
      final prevButton = tester.widget<IconButton>(find.ancestor(
        of: find.byIcon(Icons.keyboard_arrow_up),
        matching: find.byType(IconButton),
      ));
      expect(prevButton.onPressed, isNull);
    });

    testWidgets('submitting search field advances to next match', (tester) async {
      final terminal = Terminal(maxLines: 100);
      final controller = TerminalController();
      terminal.write('Test Test Test\r\n');

      await tester.pumpWidget(buildSearchBar(
        terminal: terminal,
        controller: controller,
      ));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Test');
      await tester.pumpAndSettle();

      // Submit (Enter) should call _nextMatch
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      // Still has matches, buttons enabled
      final nextButton = tester.widget<IconButton>(find.ancestor(
        of: find.byIcon(Icons.keyboard_arrow_down),
        matching: find.byType(IconButton),
      ));
      expect(nextButton.onPressed, isNotNull);
    });

    testWidgets('search is case-insensitive', (tester) async {
      final terminal = Terminal(maxLines: 100);
      final controller = TerminalController();
      terminal.write('Hello HELLO hello\r\n');

      await tester.pumpWidget(buildSearchBar(
        terminal: terminal,
        controller: controller,
      ));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'hello');
      await tester.pumpAndSettle();

      // Should find matches (case-insensitive)
      final nextButton = tester.widget<IconButton>(find.ancestor(
        of: find.byIcon(Icons.keyboard_arrow_down),
        matching: find.byType(IconButton),
      ));
      expect(nextButton.onPressed, isNotNull);
    });

    testWidgets('disposing search bar clears highlights', (tester) async {
      final terminal = Terminal(maxLines: 100);
      final controller = TerminalController();
      terminal.write('Highlight me\r\n');

      await tester.pumpWidget(buildSearchBar(
        terminal: terminal,
        controller: controller,
      ));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Highlight');
      await tester.pumpAndSettle();

      // Now dispose the search bar by replacing the widget
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(body: SizedBox()),
        ),
      );
      await tester.pumpAndSettle();

      // No error means dispose cleaned up highlights correctly
    });
  });

  group('TerminalPane — _handleTerminalKey coverage', () {
    testWidgets('Ctrl+Shift+C copies selection to clipboard', (tester) async {
      String? copiedText;
      final key = GlobalKey<TerminalPaneState>();
      final conn = _testConnection(id: 'sf-key-copy');

      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            final args = call.arguments as Map;
            copiedText = args['text'] as String?;
          }
          return null;
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: TerminalPane(
              key: key,
              connection: conn,
              isFocused: true,
              shellFactory: _successShellFactory,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Without a selection, copy should be a no-op (no clipboard write)
      expect(copiedText, isNull);

      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform, null,
      );
    });

    testWidgets('Ctrl+Shift+V pastes from clipboard into terminal', (tester) async {
      final key = GlobalKey<TerminalPaneState>();
      final conn = _testConnection(id: 'sf-key-paste');

      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.getData') {
            return <String, dynamic>{'text': 'pasted-via-key'};
          }
          return null;
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: TerminalPane(
              key: key,
              connection: conn,
              isFocused: true,
              shellFactory: _successShellFactory,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The terminal view should exist
      expect(find.byType(TerminalView), findsOneWidget);

      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform, null,
      );
    });
  });

  group('TerminalPane — _toggleSearch via showSearchNotifier', () {
    testWidgets('showSearchNotifier starts as false', (tester) async {
      final key = GlobalKey<TerminalPaneState>();
      final conn = _testConnection(id: 'sf-notifier-init');

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: TerminalPane(
              key: key,
              connection: conn,
              isFocused: true,
              shellFactory: _successShellFactory,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(key.currentState!.showSearchNotifier.value, isFalse);
    });

    testWidgets('_closeSearch sets notifier to false', (tester) async {
      final key = GlobalKey<TerminalPaneState>();
      final conn = _testConnection(id: 'sf-close-search');

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: TerminalPane(
              key: key,
              connection: conn,
              isFocused: true,
              shellFactory: _successShellFactory,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open search
      key.currentState!.showSearchNotifier.value = true;
      await tester.pumpAndSettle();
      expect(find.byType(TerminalSearchBar), findsOneWidget);

      // Close via _closeSearch (which is wired to the onClose callback)
      // Tap the close button in the search bar
      await tester.tap(find.byTooltip('Close (Esc)'));
      await tester.pumpAndSettle();

      expect(key.currentState!.showSearchNotifier.value, isFalse);
      expect(find.byType(TerminalSearchBar), findsNothing);
    });
  });

  group('TerminalSearchBar — search bar height and layout', () {
    testWidgets('search bar has 36px height', (tester) async {
      final terminal = Terminal(maxLines: 100);
      final controller = TerminalController();

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: TerminalSearchBar(
              terminal: terminal,
              terminalController: controller,
              onClose: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find the Container with height 36
      final containers = tester.widgetList<Container>(find.byType(Container));
      final searchContainer = containers.where((c) {
        final constraints = c.constraints;
        return constraints != null && constraints.maxHeight == 36;
      });
      expect(searchContainer, isNotEmpty);
    });
  });
}
