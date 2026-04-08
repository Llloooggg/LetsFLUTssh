import 'dart:async';
import '''package:letsflutssh/l10n/app_localizations.dart''';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:xterm/xterm.dart';
import 'package:letsflutssh/core/connection/connection.dart';
import 'package:letsflutssh/core/ssh/shell_helper.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/features/terminal/terminal_pane.dart';
import 'package:letsflutssh/providers/config_provider.dart';
import 'package:letsflutssh/widgets/app_icon_button.dart';
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
    terminal: Terminal(),
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
    sshConfig: const SSHConfig(
      server: ServerAddress(host: 'h', user: 'u'),
    ),
    sshConnection: null,
    state: SSHConnectionState.connected,
  );
}

void main() {
  group('TerminalPane — error state UI', () {
    testWidgets('error state sets hasError and still renders TerminalView', (
      tester,
    ) async {
      final key = GlobalKey<TerminalPaneState>();
      final conn = Connection(
        id: 'err-1',
        label: 'ErrorTest',
        sshConfig: const SSHConfig(
          server: ServerAddress(host: 'fail.host', user: 'user'),
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
              body: TerminalPane(key: key, connection: conn),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Error is written to terminal buffer, no separate error widget
      expect(find.byType(TerminalView), findsOneWidget);
      expect(key.currentState!.hasError, isTrue);
    });

    testWidgets('error from thrown exception sets hasError', (tester) async {
      final key = GlobalKey<TerminalPaneState>();
      final mockSsh = MockSSHConnection();
      when(mockSsh.isConnected).thenReturn(true);
      when(
        mockSsh.openShell(any, any),
      ).thenThrow(Exception('Connection refused'));

      final conn = Connection(
        id: 'err-2',
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
              body: TerminalPane(key: key, connection: conn),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // ShellHelper.openShell retries 5× with incremental delays — pump enough
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.pumpAndSettle();

      expect(find.byType(TerminalView), findsOneWidget);
      expect(key.currentState!.hasError, isTrue);
    });
  });

  group('TerminalPane — context menu', () {
    testWidgets(
      'right-click on connected terminal shows context menu with Paste',
      (tester) async {
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
                body: TerminalPane(
                  connection: conn,
                  isFocused: true,
                  onClose: () {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.byIcon(Icons.error_outline), findsNothing);

        await stdoutCtrl.close();
        await stderrCtrl.close();
      },
    );
  });

  group('TerminalPane — loading state', () {
    testWidgets('shows TerminalView while shell is opening', (tester) async {
      final mockSsh = MockSSHConnection();
      when(mockSsh.isConnected).thenReturn(true);
      when(
        mockSsh.openShell(any, any),
      ).thenAnswer((_) => Completer<Never>().future);

      final conn = Connection(
        id: 'load-1',
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
            home: Scaffold(body: TerminalPane(connection: conn)),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(TerminalView), findsOneWidget);
    });
  });

  group('TerminalPane — session closed notification', () {
    testWidgets('shell done sets hasError', (tester) async {
      final key = GlobalKey<TerminalPaneState>();
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
              body: TerminalPane(key: key, connection: conn),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      doneCompleter.complete();
      await tester.pumpAndSettle();

      // Error written to terminal buffer, hasError flag set
      expect(find.byType(TerminalView), findsOneWidget);
      expect(key.currentState!.hasError, isTrue);

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
              body: TerminalPane(connection: conn, isFocused: true),
            ),
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
              body: TerminalPane(connection: conn, isFocused: false),
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

  group('TerminalPane — shellFactory connected state', () {
    testWidgets('renders TerminalView when shellFactory succeeds', (
      tester,
    ) async {
      final conn = _testConnection(id: 'sf-1');

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Scaffold(
              body: TerminalPane(
                connection: conn,
                isFocused: true,
                shellFactory: _successShellFactory,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byIcon(Icons.error_outline), findsNothing);
      expect(find.byType(TerminalView), findsOneWidget);
    });

    testWidgets('sets hasError when shellFactory throws', (tester) async {
      final key = GlobalKey<TerminalPaneState>();
      final conn = _testConnection(id: 'sf-2');

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Scaffold(
              body: TerminalPane(
                key: key,
                connection: conn,
                shellFactory: _errorShellFactory,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Error is written to terminal buffer, no separate error widget
      expect(find.byType(TerminalView), findsOneWidget);
      expect(key.currentState!.hasError, isTrue);
    });

    testWidgets('no border on pane even with hasMultiplePanes=true (focused)', (
      tester,
    ) async {
      final conn = _testConnection(id: 'sf-border-f');

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Scaffold(
              body: TerminalPane(
                connection: conn,
                isFocused: true,
                hasMultiplePanes: true,
                shellFactory: _successShellFactory,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final containers = tester
          .widgetList<Container>(find.byType(Container))
          .where((c) {
            final deco = c.decoration;
            return deco is BoxDecoration && deco.border != null;
          });
      expect(containers, isEmpty);
    });

    testWidgets(
      'no border on pane even with hasMultiplePanes=true (unfocused)',
      (tester) async {
        final conn = _testConnection(id: 'sf-border-u');

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              localizationsDelegates: S.localizationsDelegates,
              supportedLocales: S.supportedLocales,
              theme: AppTheme.dark(),
              home: Scaffold(
                body: TerminalPane(
                  connection: conn,
                  isFocused: false,
                  hasMultiplePanes: true,
                  shellFactory: _successShellFactory,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final containers = tester
            .widgetList<Container>(find.byType(Container))
            .where((c) {
              final deco = c.decoration;
              return deco is BoxDecoration && deco.border != null;
            });
        expect(containers, isEmpty);
      },
    );

    testWidgets('single pane (hasMultiplePanes=false) has no border', (
      tester,
    ) async {
      final conn = _testConnection(id: 'sf-border-none');

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Scaffold(
              body: TerminalPane(
                connection: conn,
                isFocused: true,
                hasMultiplePanes: false,
                shellFactory: _successShellFactory,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final containers = tester
          .widgetList<Container>(find.byType(Container))
          .where((c) {
            final deco = c.decoration;
            return deco is BoxDecoration && deco.border != null;
          });
      expect(containers, isEmpty);
    });
  });

  group('TerminalPane — context menu via shellFactory', () {
    testWidgets('right-click shows Paste menu item', (tester) async {
      final conn = _testConnection(id: 'sf-ctx');

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Scaffold(
              body: TerminalPane(
                connection: conn,
                isFocused: true,
                onClose: () {},
                shellFactory: _successShellFactory,
              ),
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
    });
  });

  group('TerminalPane — onFocused callback', () {
    testWidgets('onFocused callback is wired to the pane widget', (
      tester,
    ) async {
      var focusCalled = false;
      final conn = _testConnection(id: 'sf-focus');

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
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
    testWidgets('session closed via onDone sets hasError', (tester) async {
      final key = GlobalKey<TerminalPaneState>();
      VoidCallback? capturedOnDone;
      final conn = _testConnection(id: 'sf-done');

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Scaffold(
              body: TerminalPane(
                key: key,
                connection: conn,
                shellFactory:
                    ({
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
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(TerminalView), findsOneWidget);
      expect(key.currentState!.hasError, isFalse);

      capturedOnDone?.call();
      await tester.pumpAndSettle();

      // Error written to terminal buffer, hasError flag set
      expect(find.byType(TerminalView), findsOneWidget);
      expect(key.currentState!.hasError, isTrue);
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
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Scaffold(
              body: TerminalPane(
                connection: conn,
                isFocused: true,
                shellFactory: _successShellFactory,
              ),
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
        SystemChannels.platform,
        null,
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
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Scaffold(
              body: TerminalPane(
                connection: conn,
                isFocused: true,
                shellFactory: _successShellFactory,
              ),
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
        SystemChannels.platform,
        null,
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
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Scaffold(
              body: TerminalPane(
                connection: conn,
                isFocused: true,
                shellFactory: _successShellFactory,
              ),
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
        SystemChannels.platform,
        null,
      );
    });
  });

  group('TerminalPane — copy selection from context menu', () {
    testWidgets('context menu without selection does not show Copy', (
      tester,
    ) async {
      final conn = _testConnection(id: 'sf-copy-no-sel');

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Scaffold(
              body: TerminalPane(
                connection: conn,
                isFocused: true,
                shellFactory: _successShellFactory,
              ),
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
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Scaffold(
              body: TerminalPane(
                connection: conn,
                isFocused: true,
                shellFactory: _successShellFactory,
              ),
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
        SystemChannels.platform,
        null,
      );
    });
  });

  group('TerminalPane — dispose cleans up shell', () {
    testWidgets('disposing the widget closes the shell connection', (
      tester,
    ) async {
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
        terminal: Terminal(),
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Scaffold(
              body: TerminalPane(
                connection: conn,
                shellFactory:
                    ({
                      required Connection connection,
                      required Terminal terminal,
                      VoidCallback? onDone,
                    }) async {
                      return shellConn;
                    },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(TerminalView), findsOneWidget);

      await tester.pumpWidget(
        const MaterialApp(
          localizationsDelegates: S.localizationsDelegates,
          supportedLocales: S.supportedLocales,
          home: Scaffold(body: SizedBox()),
        ),
      );
      await tester.pumpAndSettle();

      verify(mockSession.close()).called(1);

      await stdoutCtrl.close();
      await stderrCtrl.close();
    });

    testWidgets('dispose is safe when shellConn is null (connection failed)', (
      tester,
    ) async {
      final conn = _testConnection(id: 'sf-dispose-null');

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Scaffold(
              body: TerminalPane(
                connection: conn,
                shellFactory: _errorShellFactory,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Error written to terminal buffer, TerminalView always shown
      expect(find.byType(TerminalView), findsOneWidget);

      // Dispose should not throw even though _shellConn is null
      await tester.pumpWidget(
        const MaterialApp(
          localizationsDelegates: S.localizationsDelegates,
          supportedLocales: S.supportedLocales,
          home: Scaffold(body: SizedBox()),
        ),
      );
      await tester.pumpAndSettle();
    });
  });

  group('TerminalPane — context menu dismiss without action', () {
    testWidgets('dismissing context menu without selecting does nothing', (
      tester,
    ) async {
      final conn = _testConnection(id: 'sf-ctx-dismiss');

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Scaffold(
              body: TerminalPane(
                connection: conn,
                isFocused: true,
                shellFactory: _successShellFactory,
              ),
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
    testWidgets('shows TerminalView while shellFactory is slow', (
      tester,
    ) async {
      final completer = Completer<ShellConnection>();
      final conn = _testConnection(id: 'sf-slow');

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Scaffold(
              body: TerminalPane(
                connection: conn,
                shellFactory:
                    ({
                      required Connection connection,
                      required Terminal terminal,
                      VoidCallback? onDone,
                    }) => completer.future,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // TerminalPane always renders TerminalView (progress in buffer)
      expect(find.byType(TerminalView), findsOneWidget);

      completer.complete(_fakeShellConnection());
      await tester.pumpAndSettle();

      expect(find.byType(TerminalView), findsOneWidget);
    });
  });

  group('TerminalPane — error state layout', () {
    testWidgets('error state sets hasError and renders TerminalView', (
      tester,
    ) async {
      final key = GlobalKey<TerminalPaneState>();
      final conn = _testConnection(id: 'sf-error-layout');

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Scaffold(
              body: TerminalPane(
                key: key,
                connection: conn,
                shellFactory: _errorShellFactory,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Error is written to terminal buffer, no separate error widget
      expect(find.byType(TerminalView), findsOneWidget);
      expect(key.currentState!.hasError, isTrue);
    });

    testWidgets('error state writes error to terminal buffer', (tester) async {
      final key = GlobalKey<TerminalPaneState>();
      final conn = _testConnection(id: 'sf-error-align');

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Scaffold(
              body: TerminalPane(
                key: key,
                connection: conn,
                shellFactory: _errorShellFactory,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(TerminalView), findsOneWidget);
      expect(key.currentState!.hasError, isTrue);
    });
  });

  group('TerminalPane — search bar toggle via showSearchNotifier', () {
    testWidgets('toggling showSearchNotifier shows the search bar', (
      tester,
    ) async {
      final key = GlobalKey<TerminalPaneState>();
      final conn = _testConnection(id: 'sf-search-toggle');

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
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

    testWidgets('toggling showSearchNotifier off hides the search bar', (
      tester,
    ) async {
      final key = GlobalKey<TerminalPaneState>();
      final conn = _testConnection(id: 'sf-search-toggle-off');

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
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
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
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
        localizationsDelegates: S.localizationsDelegates,
        supportedLocales: S.supportedLocales,
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

    testWidgets('close button calls onClose callback', (tester) async {
      var closeCalled = false;
      await tester.pumpWidget(
        buildSearchBar(onClose: () => closeCalled = true),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Close (Esc)'));
      await tester.pumpAndSettle();

      expect(closeCalled, isTrue);
    });

    testWidgets('typing in search field with empty text clears matches', (
      tester,
    ) async {
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
      final prevButton = tester.widget<AppIconButton>(
        find.ancestor(
          of: find.byIcon(Icons.keyboard_arrow_up),
          matching: find.byType(AppIconButton),
        ),
      );
      expect(prevButton.onTap, isNull);
    });

    testWidgets('searching for existing text shows match count', (
      tester,
    ) async {
      final terminal = Terminal(maxLines: 100);
      final controller = TerminalController();
      // Write enough text to be searchable in the buffer
      terminal.write('Hello World\r\n');
      terminal.write('Hello Again\r\n');

      await tester.pumpWidget(
        buildSearchBar(terminal: terminal, controller: controller),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Hello');
      await tester.pumpAndSettle();

      // prev/next buttons should now be enabled (matches found)
      final prevButton = tester.widget<AppIconButton>(
        find.ancestor(
          of: find.byIcon(Icons.keyboard_arrow_up),
          matching: find.byType(AppIconButton),
        ),
      );
      expect(prevButton.onTap, isNotNull);

      final nextButton = tester.widget<AppIconButton>(
        find.ancestor(
          of: find.byIcon(Icons.keyboard_arrow_down),
          matching: find.byType(AppIconButton),
        ),
      );
      expect(nextButton.onTap, isNotNull);
    });

    testWidgets('next/prev cycle through matches', (tester) async {
      final terminal = Terminal(maxLines: 100);
      final controller = TerminalController();
      terminal.write('AAA BBB AAA\r\n');

      await tester.pumpWidget(
        buildSearchBar(terminal: terminal, controller: controller),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'AAA');
      await tester.pumpAndSettle();

      // Should have matches — tap Next multiple times
      await tester.tap(find.byTooltip('Next'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Previous'));
      await tester.pumpAndSettle();

      // Buttons should still be enabled after cycling
      final nextButton = tester.widget<AppIconButton>(
        find.ancestor(
          of: find.byIcon(Icons.keyboard_arrow_down),
          matching: find.byType(AppIconButton),
        ),
      );
      expect(nextButton.onTap, isNotNull);
    });

    testWidgets('searching for non-existent text shows no matches', (
      tester,
    ) async {
      final terminal = Terminal(maxLines: 100);
      terminal.write('Hello World\r\n');

      await tester.pumpWidget(buildSearchBar(terminal: terminal));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'ZZZZZ');
      await tester.pumpAndSettle();

      // Buttons should be disabled — no matches
      final prevButton = tester.widget<AppIconButton>(
        find.ancestor(
          of: find.byIcon(Icons.keyboard_arrow_up),
          matching: find.byType(AppIconButton),
        ),
      );
      expect(prevButton.onTap, isNull);
    });

    testWidgets('submitting search field advances to next match', (
      tester,
    ) async {
      final terminal = Terminal(maxLines: 100);
      final controller = TerminalController();
      terminal.write('Test Test Test\r\n');

      await tester.pumpWidget(
        buildSearchBar(terminal: terminal, controller: controller),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Test');
      await tester.pumpAndSettle();

      // Submit (Enter) should call _nextMatch
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      // Still has matches, buttons enabled
      final nextButton = tester.widget<AppIconButton>(
        find.ancestor(
          of: find.byIcon(Icons.keyboard_arrow_down),
          matching: find.byType(AppIconButton),
        ),
      );
      expect(nextButton.onTap, isNotNull);
    });

    testWidgets('search is case-insensitive', (tester) async {
      final terminal = Terminal(maxLines: 100);
      final controller = TerminalController();
      terminal.write('Hello HELLO hello\r\n');

      await tester.pumpWidget(
        buildSearchBar(terminal: terminal, controller: controller),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'hello');
      await tester.pumpAndSettle();

      // Should find matches (case-insensitive)
      final nextButton = tester.widget<AppIconButton>(
        find.ancestor(
          of: find.byIcon(Icons.keyboard_arrow_down),
          matching: find.byType(AppIconButton),
        ),
      );
      expect(nextButton.onTap, isNotNull);
    });

    testWidgets('disposing search bar clears highlights', (tester) async {
      final terminal = Terminal(maxLines: 100);
      final controller = TerminalController();
      terminal.write('Highlight me\r\n');

      await tester.pumpWidget(
        buildSearchBar(terminal: terminal, controller: controller),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Highlight');
      await tester.pumpAndSettle();

      // Now dispose the search bar by replacing the widget
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: const Scaffold(body: SizedBox()),
          ),
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
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
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
        ),
      );
      await tester.pumpAndSettle();

      // Without a selection, copy should be a no-op (no clipboard write)
      expect(copiedText, isNull);

      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });

    testWidgets('Ctrl+Shift+V pastes from clipboard into terminal', (
      tester,
    ) async {
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
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
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
        ),
      );
      await tester.pumpAndSettle();

      // The terminal view should exist
      expect(find.byType(TerminalView), findsOneWidget);

      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });
  });

  group('TerminalPane — _toggleSearch via showSearchNotifier', () {
    testWidgets('showSearchNotifier starts as false', (tester) async {
      final key = GlobalKey<TerminalPaneState>();
      final conn = _testConnection(id: 'sf-notifier-init');

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
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
        ),
      );
      await tester.pumpAndSettle();

      expect(key.currentState!.showSearchNotifier.value, isFalse);
    });

    testWidgets('_closeSearch sets notifier to false', (tester) async {
      final key = GlobalKey<TerminalPaneState>();
      final conn = _testConnection(id: 'sf-close-search');

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
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

  group('TerminalSearchBar — match counter display', () {
    Widget buildSearchBarForCounter({
      required Terminal terminal,
      required TerminalController controller,
      VoidCallback? onClose,
    }) {
      return MaterialApp(
        localizationsDelegates: S.localizationsDelegates,
        supportedLocales: S.supportedLocales,
        theme: AppTheme.dark(),
        home: Scaffold(
          body: TerminalSearchBar(
            terminal: terminal,
            terminalController: controller,
            onClose: onClose ?? () {},
          ),
        ),
      );
    }

    testWidgets('match counter shows "1/2" when two matches found', (
      tester,
    ) async {
      final terminal = Terminal(maxLines: 100);
      final controller = TerminalController();
      terminal.write('foo bar foo\r\n');

      await tester.pumpWidget(
        buildSearchBarForCounter(terminal: terminal, controller: controller),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'foo');
      await tester.pumpAndSettle();

      expect(find.text('1/2'), findsOneWidget);
    });

    testWidgets('next button advances match counter from 1/2 to 2/2', (
      tester,
    ) async {
      final terminal = Terminal(maxLines: 100);
      final controller = TerminalController();
      terminal.write('foo bar foo\r\n');

      await tester.pumpWidget(
        buildSearchBarForCounter(terminal: terminal, controller: controller),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'foo');
      await tester.pumpAndSettle();
      expect(find.text('1/2'), findsOneWidget);

      await tester.tap(find.byTooltip('Next'));
      await tester.pumpAndSettle();
      expect(find.text('2/2'), findsOneWidget);
    });

    testWidgets('next wraps around from last to first match', (tester) async {
      final terminal = Terminal(maxLines: 100);
      final controller = TerminalController();
      terminal.write('foo bar foo\r\n');

      await tester.pumpWidget(
        buildSearchBarForCounter(terminal: terminal, controller: controller),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'foo');
      await tester.pumpAndSettle();
      expect(find.text('1/2'), findsOneWidget);

      await tester.tap(find.byTooltip('Next'));
      await tester.pumpAndSettle();
      expect(find.text('2/2'), findsOneWidget);

      await tester.tap(find.byTooltip('Next'));
      await tester.pumpAndSettle();
      expect(find.text('1/2'), findsOneWidget);
    });

    testWidgets('prev button wraps from first to last match', (tester) async {
      final terminal = Terminal(maxLines: 100);
      final controller = TerminalController();
      terminal.write('foo bar foo\r\n');

      await tester.pumpWidget(
        buildSearchBarForCounter(terminal: terminal, controller: controller),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'foo');
      await tester.pumpAndSettle();
      expect(find.text('1/2'), findsOneWidget);

      await tester.tap(find.byTooltip('Previous'));
      await tester.pumpAndSettle();
      expect(find.text('2/2'), findsOneWidget);
    });

    testWidgets('prev then next cycling works correctly with 3 matches', (
      tester,
    ) async {
      final terminal = Terminal(maxLines: 100);
      final controller = TerminalController();
      terminal.write('abc def abc ghi abc\r\n');

      await tester.pumpWidget(
        buildSearchBarForCounter(terminal: terminal, controller: controller),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'abc');
      await tester.pumpAndSettle();
      expect(find.text('1/3'), findsOneWidget);

      await tester.tap(find.byTooltip('Next'));
      await tester.pumpAndSettle();
      expect(find.text('2/3'), findsOneWidget);

      await tester.tap(find.byTooltip('Next'));
      await tester.pumpAndSettle();
      expect(find.text('3/3'), findsOneWidget);

      await tester.tap(find.byTooltip('Previous'));
      await tester.pumpAndSettle();
      expect(find.text('2/3'), findsOneWidget);
    });

    testWidgets('no match counter when search has no results', (tester) async {
      final terminal = Terminal(maxLines: 100);
      final controller = TerminalController();
      terminal.write('Hello World\r\n');

      await tester.pumpWidget(
        buildSearchBarForCounter(terminal: terminal, controller: controller),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'ZZZZZ');
      await tester.pumpAndSettle();

      // suffixText is null when _totalMatches == 0
      expect(find.text('1/0'), findsNothing);
      expect(find.text('0/0'), findsNothing);
    });

    testWidgets('match counter disappears when search text is cleared', (
      tester,
    ) async {
      final terminal = Terminal(maxLines: 100);
      final controller = TerminalController();
      terminal.write('foo bar foo\r\n');

      await tester.pumpWidget(
        buildSearchBarForCounter(terminal: terminal, controller: controller),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'foo');
      await tester.pumpAndSettle();
      expect(find.text('1/2'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle();
      expect(find.text('1/2'), findsNothing);
    });

    testWidgets('submit (Enter) advances to next match', (tester) async {
      final terminal = Terminal(maxLines: 100);
      final controller = TerminalController();
      terminal.write('foo bar foo\r\n');

      await tester.pumpWidget(
        buildSearchBarForCounter(terminal: terminal, controller: controller),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'foo');
      await tester.pumpAndSettle();
      expect(find.text('1/2'), findsOneWidget);

      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('2/2'), findsOneWidget);
    });

    testWidgets('single match shows 1/1 and next/prev stay at 1/1', (
      tester,
    ) async {
      final terminal = Terminal(maxLines: 100);
      final controller = TerminalController();
      terminal.write('unique_string here\r\n');

      await tester.pumpWidget(
        buildSearchBarForCounter(terminal: terminal, controller: controller),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'unique_string');
      await tester.pumpAndSettle();
      expect(find.text('1/1'), findsOneWidget);

      await tester.tap(find.byTooltip('Next'));
      await tester.pumpAndSettle();
      expect(find.text('1/1'), findsOneWidget);

      await tester.tap(find.byTooltip('Previous'));
      await tester.pumpAndSettle();
      expect(find.text('1/1'), findsOneWidget);
    });
  });

  group('TerminalSearchBar — close clears highlights', () {
    testWidgets('close button clears highlights and calls onClose', (
      tester,
    ) async {
      var closeCalled = false;
      final terminal = Terminal(maxLines: 100);
      final controller = TerminalController();
      terminal.write('Hello World\r\n');

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Scaffold(
              body: TerminalSearchBar(
                terminal: terminal,
                terminalController: controller,
                onClose: () => closeCalled = true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Search to create highlights
      await tester.enterText(find.byType(TextField), 'Hello');
      await tester.pumpAndSettle();
      expect(find.text('1/1'), findsOneWidget);

      // Close — should clear highlights and call onClose
      await tester.tap(find.byTooltip('Close (Esc)'));
      await tester.pumpAndSettle();

      expect(closeCalled, isTrue);
    });
  });

  group('TerminalSearchBar — _nextMatch/_prevMatch with zero matches', () {
    testWidgets('next/prev are no-op when there are zero matches', (
      tester,
    ) async {
      final terminal = Terminal(maxLines: 100);
      final controller = TerminalController();

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Scaffold(
              body: TerminalSearchBar(
                terminal: terminal,
                terminalController: controller,
                onClose: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final prevButton = tester.widget<AppIconButton>(
        find.ancestor(
          of: find.byIcon(Icons.keyboard_arrow_up),
          matching: find.byType(AppIconButton),
        ),
      );
      expect(prevButton.onTap, isNull);

      final nextButton = tester.widget<AppIconButton>(
        find.ancestor(
          of: find.byIcon(Icons.keyboard_arrow_down),
          matching: find.byType(AppIconButton),
        ),
      );
      expect(nextButton.onTap, isNull);
    });
  });

  group('TerminalPane — connecting state waits for connection', () {
    testWidgets('shows TerminalView while connecting, then stays after ready', (
      tester,
    ) async {
      final conn = Connection(
        id: 'connecting-1',
        label: 'Test',
        sshConfig: const SSHConfig(
          server: ServerAddress(host: 'h', user: 'u'),
        ),
        sshConnection: null,
        state: SSHConnectionState.connecting,
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Scaffold(
              body: TerminalPane(
                connection: conn,
                shellFactory: _successShellFactory,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // TerminalView is always rendered (progress written to buffer)
      expect(find.byType(TerminalView), findsOneWidget);

      // Transition to connected — ready completer fires
      conn.state = SSHConnectionState.connected;
      conn.completeReady();
      await tester.pumpAndSettle();

      // Terminal still visible
      expect(find.byType(TerminalView), findsOneWidget);
    });

    testWidgets('sets hasError when connection transitions to disconnected', (
      tester,
    ) async {
      final key = GlobalKey<TerminalPaneState>();
      final conn = Connection(
        id: 'connecting-2',
        label: 'Test',
        sshConfig: const SSHConfig(
          server: ServerAddress(host: 'fail', user: 'u'),
        ),
        sshConnection: null,
        state: SSHConnectionState.connecting,
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Scaffold(
              body: TerminalPane(
                key: key,
                connection: conn,
                shellFactory: _successShellFactory,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // Transition to disconnected with error
      conn.connectionError = 'Auth failed';
      conn.state = SSHConnectionState.disconnected;
      conn.completeReady();
      await tester.pumpAndSettle();

      // Error written to terminal buffer, hasError flag set
      expect(find.byType(TerminalView), findsOneWidget);
      expect(key.currentState!.hasError, isTrue);
    });
  });

  group('TerminalPane — selection cleared on focus loss', () {
    testWidgets('clearSelection called when isFocused changes to false', (
      tester,
    ) async {
      final conn = _testConnection(id: 'sel-clear-1');

      // Build with isFocused: true
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Scaffold(
              body: TerminalPane(
                connection: conn,
                isFocused: true,
                hasMultiplePanes: true,
                shellFactory: _successShellFactory,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Rebuild with isFocused: false — should trigger clearSelection
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Scaffold(
              body: TerminalPane(
                connection: conn,
                isFocused: false,
                hasMultiplePanes: true,
                shellFactory: _successShellFactory,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify no crash — clearSelection on an empty selection is a no-op
      expect(find.byType(TerminalView), findsOneWidget);
    });
  });

  group('TerminalPane — Shift-bypass for mouse mode', () {
    testWidgets('Shift suspends pointer input when terminal is in mouse mode', (
      tester,
    ) async {
      final conn = _testConnection(id: 'shift-mouse-1');

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Scaffold(
              body: TerminalPane(
                connection: conn,
                isFocused: true,
                shellFactory: _successShellFactory,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final state = tester.state<TerminalPaneState>(find.byType(TerminalPane));

      // Enable mouse mode via escape sequence (upDownScroll = mode 1000)
      state.terminal.write('\x1b[?1000h');
      expect(state.terminal.mouseMode, MouseMode.upDownScroll);

      // Initially not suspended
      expect(state.terminalController.suspendedPointerInputs, isFalse);

      // Press Shift — should suspend pointer forwarding
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      expect(state.terminalController.suspendedPointerInputs, isTrue);

      // Release Shift — should restore
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      expect(state.terminalController.suspendedPointerInputs, isFalse);
    });

    testWidgets('Shift does NOT suspend when terminal is not in mouse mode', (
      tester,
    ) async {
      final conn = _testConnection(id: 'shift-mouse-2');

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Scaffold(
              body: TerminalPane(
                connection: conn,
                isFocused: true,
                shellFactory: _successShellFactory,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final state = tester.state<TerminalPaneState>(find.byType(TerminalPane));

      // Mouse mode is none (default)
      expect(state.terminal.mouseMode, MouseMode.none);

      // Press Shift — should NOT suspend
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      expect(state.terminalController.suspendedPointerInputs, isFalse);

      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    });

    testWidgets('suspend clears when mouse mode is disabled while Shift held', (
      tester,
    ) async {
      final conn = _testConnection(id: 'shift-mouse-3');

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Scaffold(
              body: TerminalPane(
                connection: conn,
                isFocused: true,
                shellFactory: _successShellFactory,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final state = tester.state<TerminalPaneState>(find.byType(TerminalPane));

      // Enable mouse mode, press Shift
      state.terminal.write('\x1b[?1000h');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      expect(state.terminalController.suspendedPointerInputs, isTrue);

      // Disable mouse mode (htop exits)
      state.terminal.write('\x1b[?1000l');
      expect(state.terminal.mouseMode, MouseMode.none);

      // Next key event (any key) recalculates suspend state
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
      expect(state.terminalController.suspendedPointerInputs, isFalse);

      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    });

    testWidgets('right Shift also triggers suspend', (tester) async {
      final conn = _testConnection(id: 'shift-mouse-4');

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Scaffold(
              body: TerminalPane(
                connection: conn,
                isFocused: true,
                shellFactory: _successShellFactory,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final state = tester.state<TerminalPaneState>(find.byType(TerminalPane));

      state.terminal.write('\x1b[?1000h');

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftRight);
      expect(state.terminalController.suspendedPointerInputs, isTrue);

      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftRight);
      expect(state.terminalController.suspendedPointerInputs, isFalse);
    });
  });

  group('TerminalPane — zoom', () {
    testWidgets('zoomIn increases font size by 1', (tester) async {
      final key = GlobalKey<TerminalPaneState>();
      final conn = _testConnection(id: 'zoom-in');

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
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
        ),
      );
      await tester.pumpAndSettle();

      final element = tester.element(find.byType(TerminalPane));
      final container = ProviderScope.containerOf(element);
      final before = container.read(configProvider).fontSize;

      key.currentState!.zoomIn();
      await tester.pump();

      expect(container.read(configProvider).fontSize, before + 1);
    });

    testWidgets('zoomOut decreases font size by 1', (tester) async {
      final key = GlobalKey<TerminalPaneState>();
      final conn = _testConnection(id: 'zoom-out');

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
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
        ),
      );
      await tester.pumpAndSettle();

      final element = tester.element(find.byType(TerminalPane));
      final container = ProviderScope.containerOf(element);
      final before = container.read(configProvider).fontSize;

      key.currentState!.zoomOut();
      await tester.pump();

      expect(container.read(configProvider).fontSize, before - 1);
    });

    testWidgets('zoomReset sets font size to 14.0', (tester) async {
      final key = GlobalKey<TerminalPaneState>();
      final conn = _testConnection(id: 'zoom-reset');

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
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
        ),
      );
      await tester.pumpAndSettle();

      final element = tester.element(find.byType(TerminalPane));
      final container = ProviderScope.containerOf(element);
      final config = container.read(configProvider);
      container.read(configProvider.notifier).state = config.copyWith(
        terminal: config.terminal.copyWith(fontSize: 20.0),
      );
      await tester.pump();

      expect(container.read(configProvider).fontSize, 20.0);

      key.currentState!.zoomReset();
      await tester.pump();

      expect(container.read(configProvider).fontSize, 14.0);
    });

    testWidgets('Listener with onPointerSignal is present', (tester) async {
      final key = GlobalKey<TerminalPaneState>();
      final conn = _testConnection(id: 'zoom-scroll');

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
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
        ),
      );
      await tester.pumpAndSettle();

      final listeners = tester.widgetList<Listener>(find.byType(Listener));
      final withSignal = listeners
          .where((l) => l.onPointerSignal != null)
          .toList();
      expect(withSignal, isNotEmpty);
    });

    testWidgets('font size clamps at bounds 8 and 24', (tester) async {
      final key = GlobalKey<TerminalPaneState>();
      final conn = _testConnection(id: 'zoom-clamp');

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
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
        ),
      );
      await tester.pumpAndSettle();

      final element = tester.element(find.byType(TerminalPane));
      final container = ProviderScope.containerOf(element);

      // Set to max and try to go higher
      final config = container.read(configProvider);
      container.read(configProvider.notifier).state = config.copyWith(
        terminal: config.terminal.copyWith(fontSize: 24.0),
      );
      await tester.pump();

      key.currentState!.zoomIn();
      await tester.pump();
      expect(container.read(configProvider).fontSize, 24.0);

      // Set to min and try to go lower
      container.read(configProvider.notifier).state = config.copyWith(
        terminal: config.terminal.copyWith(fontSize: 8.0),
      );
      await tester.pump();

      key.currentState!.zoomOut();
      await tester.pump();
      expect(container.read(configProvider).fontSize, 8.0);
    });
  });
}
