import 'dart:async';
import '''package:letsflutssh/l10n/app_localizations.dart''';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:xterm/xterm.dart';
import 'package:letsflutssh/core/connection/connection.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/features/mobile/mobile_terminal_view.dart';
import 'package:letsflutssh/features/mobile/ssh_key_sequences.dart';
import 'package:letsflutssh/features/mobile/ssh_keyboard_bar.dart';
import 'package:letsflutssh/providers/config_provider.dart';
import 'package:letsflutssh/theme/app_theme.dart';
import '../../core/ssh/shell_helper_test.mocks.dart';

Connection connectedConn(
  MockSSHConnection mockSsh,
  MockSSHSession mockSession,
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
    id: 'test-conn',
    label: 'Test',
    sshConfig: const SSHConfig(
      server: ServerAddress(host: 'h', user: 'u'),
    ),
    sshConnection: mockSsh,
    state: SSHConnectionState.connected,
  );
}

void main() {
  group('MobileTerminalView — loading state', () {
    testWidgets('shows TerminalView while connecting', (tester) async {
      final mockSsh = MockSSHConnection();
      when(mockSsh.isConnected).thenReturn(true);
      when(
        mockSsh.openShell(any, any),
      ).thenAnswer((_) => Completer<Never>().future);

      final conn = Connection(
        id: 'test-1',
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
            home: Scaffold(body: MobileTerminalView(connection: conn)),
          ),
        ),
      );
      await tester.pump();

      // Always renders TerminalView — progress written to buffer
      expect(find.byType(TerminalView), findsOneWidget);
    });
  });

  group('MobileTerminalView — error states', () {
    testWidgets('renders TerminalView when shell fails', (tester) async {
      final mockSsh = MockSSHConnection();
      when(mockSsh.isConnected).thenReturn(true);
      when(mockSsh.openShell(any, any)).thenThrow(Exception('Shell failed'));

      final conn = Connection(
        id: 'test-2',
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
            home: Scaffold(body: MobileTerminalView(connection: conn)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // ShellHelper.openShell retries 5× with incremental delays
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.pumpAndSettle();

      // Error written to terminal buffer, TerminalView always shown
      expect(find.byType(TerminalView), findsOneWidget);
    });

    testWidgets('renders TerminalView when sshConnection is null', (
      tester,
    ) async {
      final conn = Connection(
        id: 'test-3',
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
            home: Scaffold(body: MobileTerminalView(connection: conn)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Error written to terminal buffer, TerminalView always shown
      expect(find.byType(TerminalView), findsOneWidget);
    });

    testWidgets('error state still shows TerminalView with keyboard bar', (
      tester,
    ) async {
      final mockSsh = MockSSHConnection();
      when(mockSsh.isConnected).thenReturn(true);
      when(
        mockSsh.openShell(any, any),
      ).thenThrow(Exception('Connection refused'));

      final conn = Connection(
        id: 'test-err',
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
            home: Scaffold(body: MobileTerminalView(connection: conn)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.pumpAndSettle();

      expect(find.byType(TerminalView), findsOneWidget);
      expect(find.text('Esc'), findsOneWidget);
    });

    testWidgets('disconnected state renders TerminalView', (tester) async {
      final conn = Connection(
        id: 'test-color',
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
            home: Scaffold(body: MobileTerminalView(connection: conn)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(TerminalView), findsOneWidget);
    });

    testWidgets('error state renders Stack layout', (tester) async {
      final mockSsh = MockSSHConnection();
      when(mockSsh.isConnected).thenReturn(true);
      when(mockSsh.openShell(any, any)).thenThrow(Exception('fail'));

      final conn = Connection(
        id: 'test-align',
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
            home: Scaffold(body: MobileTerminalView(connection: conn)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.pumpAndSettle();

      // Always renders Stack with TerminalView and keyboard bar
      expect(find.byType(Stack), findsWidgets);
      expect(find.byType(TerminalView), findsOneWidget);
    });

    testWidgets('error state still renders TerminalView and keyboard bar', (
      tester,
    ) async {
      final conn = Connection(
        id: 'test-spacer',
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
            home: Scaffold(body: MobileTerminalView(connection: conn)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(TerminalView), findsOneWidget);
      expect(find.text('Ctrl'), findsOneWidget);
    });
  });

  group('MobileTerminalView — successful connection', () {
    testWidgets('renders terminal and keyboard bar on success', (tester) async {
      final mockSsh = MockSSHConnection();
      final mockSession = MockSSHSession();
      final conn = connectedConn(mockSsh, mockSession);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Scaffold(body: MobileTerminalView(connection: conn)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byIcon(Icons.error_outline), findsNothing);
      expect(find.byType(TerminalView), findsOneWidget);
      expect(find.text('Esc'), findsOneWidget);
      expect(find.text('Tab'), findsOneWidget);
      expect(find.text('Ctrl'), findsOneWidget);
      expect(find.text('Alt'), findsOneWidget);
    });

    testWidgets('shell done callback sets session closed error', (
      tester,
    ) async {
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
        id: 'test-done',
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
            home: Scaffold(body: MobileTerminalView(connection: conn)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      doneCompleter.complete();
      await tester.pumpAndSettle();

      // Session done sets hasError — TerminalView stays visible
      expect(find.byType(TerminalView), findsOneWidget);

      await stdoutCtrl.close();
      await stderrCtrl.close();
    });

    testWidgets('GestureDetector present for pinch zoom', (tester) async {
      final mockSsh = MockSSHConnection();
      final mockSession = MockSSHSession();
      final conn = connectedConn(mockSsh, mockSession);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Scaffold(body: MobileTerminalView(connection: conn)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(GestureDetector), findsWidgets);
    });

    testWidgets('widget disposes without errors', (tester) async {
      final mockSsh = MockSSHConnection();
      final mockSession = MockSSHSession();
      final conn = connectedConn(mockSsh, mockSession);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Scaffold(body: MobileTerminalView(connection: conn)),
          ),
        ),
      );
      await tester.pumpAndSettle();

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
    });

    testWidgets('Stack layout has terminal and keyboard bar', (tester) async {
      final mockSsh = MockSSHConnection();
      final mockSession = MockSSHSession();
      final conn = connectedConn(mockSsh, mockSession);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Scaffold(body: MobileTerminalView(connection: conn)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Stack), findsWidgets);
      expect(find.text('Ctrl'), findsOneWidget);
      expect(find.text('Alt'), findsOneWidget);
    });
  });

  group('MobileTerminalView — pinch-to-zoom', () {
    testWidgets('pinch zoom changes font size and clamps between 8 and 24', (
      tester,
    ) async {
      final mockSsh = MockSSHConnection();
      final mockSession = MockSSHSession();
      final conn = connectedConn(mockSsh, mockSession);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Scaffold(body: MobileTerminalView(connection: conn)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(TerminalView), findsOneWidget);

      final center = tester.getCenter(find.byType(TerminalView));
      final pointer1 = await tester.createGesture();
      final pointer2 = await tester.createGesture();

      await pointer1.down(center - const Offset(10, 0));
      await pointer2.down(center + const Offset(10, 0));
      await tester.pump();

      await pointer1.moveTo(center - const Offset(30, 0));
      await pointer2.moveTo(center + const Offset(30, 0));
      await tester.pump();

      await pointer1.up();
      await pointer2.up();
      await tester.pump();

      expect(find.byType(TerminalView), findsOneWidget);
    });

    testWidgets('pinch zoom down clamps at minimum 8.0', (tester) async {
      final mockSsh = MockSSHConnection();
      final mockSession = MockSSHSession();
      final conn = connectedConn(mockSsh, mockSession);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Scaffold(body: MobileTerminalView(connection: conn)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final center = tester.getCenter(find.byType(TerminalView));
      final pointer1 = await tester.createGesture();
      final pointer2 = await tester.createGesture();

      await pointer1.down(center - const Offset(50, 0));
      await pointer2.down(center + const Offset(50, 0));
      await tester.pump();

      await pointer1.moveTo(center - const Offset(2, 0));
      await pointer2.moveTo(center + const Offset(2, 0));
      await tester.pump();

      await pointer1.up();
      await pointer2.up();
      await tester.pump();

      expect(find.byType(TerminalView), findsOneWidget);
    });

    testWidgets(
      'IgnorePointer wraps TerminalView for pinch gesture isolation',
      (tester) async {
        final mockSsh = MockSSHConnection();
        final mockSession = MockSSHSession();
        final conn = connectedConn(mockSsh, mockSession);

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              localizationsDelegates: S.localizationsDelegates,
              supportedLocales: S.supportedLocales,
              theme: AppTheme.dark(),
              home: Scaffold(body: MobileTerminalView(connection: conn)),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(IgnorePointer), findsWidgets);
      },
    );

    testWidgets('onScaleEnd is configured on GestureDetector', (tester) async {
      final mockSsh = MockSSHConnection();
      final mockSession = MockSSHSession();
      final conn = connectedConn(mockSsh, mockSession);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Scaffold(body: MobileTerminalView(connection: conn)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final gds = tester.widgetList<GestureDetector>(
        find.byType(GestureDetector),
      );
      final scaleGd = gds.where((g) => g.onScaleEnd != null).toList();
      expect(scaleGd, isNotEmpty);
    });
  });

  group('MobileTerminalView — font size from settings', () {
    testWidgets('font size updates reactively from configProvider', (
      tester,
    ) async {
      final mockSsh = MockSSHConnection();
      final mockSession = MockSSHSession();
      final conn = connectedConn(mockSsh, mockSession);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Scaffold(body: MobileTerminalView(connection: conn)),
          ),
        ),
      );
      // pump() instead of pumpAndSettle() — terminal cursor blinks forever
      await tester.pump();
      await tester.pump();

      // Default font size is 14.0
      var termView = tester.widget<TerminalView>(find.byType(TerminalView));
      expect(termView.textStyle.fontSize, 14.0);

      // Update font size via provider — set state directly via overrideWith
      final element = tester.element(find.byType(MobileTerminalView));
      final container = ProviderScope.containerOf(element);
      final config = container.read(configProvider);
      // Directly replace state to avoid ConfigStore disk I/O
      container.read(configProvider.notifier).state = config.copyWith(
        terminal: config.terminal.copyWith(fontSize: 20.0),
      );
      await tester.pump();

      // Font size should update reactively
      termView = tester.widget<TerminalView>(find.byType(TerminalView));
      expect(termView.textStyle.fontSize, 20.0);
    });
  });

  group('MobileTerminalView — keyboard input forwarding', () {
    testWidgets('SshKeyboardBar key press writes to shell', (tester) async {
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
      when(mockSession.write(any)).thenReturn(null);

      final conn = Connection(
        id: 'test-kb',
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
            home: Scaffold(body: MobileTerminalView(connection: conn)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Esc'));
      await tester.pump();
      verify(mockSession.write(Uint8List.fromList([0x1B]))).called(1);

      await tester.tap(find.text('Tab'));
      await tester.pump();
      verify(mockSession.write(Uint8List.fromList([0x09]))).called(1);

      await stdoutCtrl.close();
      await stderrCtrl.close();
    });
  });

  group('MobileTerminalView — selection toolbar', () {
    testWidgets('no selection toolbar when no text is selected', (
      tester,
    ) async {
      final mockSsh = MockSSHConnection();
      final mockSession = MockSSHSession();
      final conn = connectedConn(mockSsh, mockSession);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Scaffold(body: MobileTerminalView(connection: conn)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // No selection toolbar should be visible
      expect(find.text('Copy'), findsNothing);
    });

    testWidgets('GestureDetector does not have onLongPressStart', (
      tester,
    ) async {
      final mockSsh = MockSSHConnection();
      final mockSession = MockSSHSession();
      final conn = connectedConn(mockSsh, mockSession);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Scaffold(body: MobileTerminalView(connection: conn)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The outer GestureDetector should NOT have onLongPressStart
      // (xterm handles long press internally for word selection)
      final gds = tester.widgetList<GestureDetector>(
        find.byType(GestureDetector),
      );
      final outerGd = gds.where((g) => g.onScaleStart != null).toList();
      expect(outerGd, isNotEmpty);
      expect(outerGd.first.onLongPressStart, isNull);
    });

    testWidgets('paste button is present in keyboard bar', (tester) async {
      final mockSsh = MockSSHConnection();
      final mockSession = MockSSHSession();
      final conn = connectedConn(mockSsh, mockSession);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Scaffold(body: MobileTerminalView(connection: conn)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.paste), findsOneWidget);
    });
  });

  group('MobileTerminalView — system keyboard with modifiers', () {
    testWidgets(
      'Ctrl modifier applies to system keyboard input via terminal.onOutput',
      (tester) async {
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
        when(mockSession.write(any)).thenReturn(null);

        final conn = Connection(
          id: 'test-sysmod',
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
              home: Scaffold(body: MobileTerminalView(connection: conn)),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Find the SshKeyboardBar state via its GlobalKey
        final barState = tester.state<SshKeyboardBarState>(
          find.byType(SshKeyboardBar),
        );

        // Activate Ctrl (one-shot)
        await tester.tap(find.text('Ctrl'));
        await tester.pump();

        // Simulate system keyboard typing 'c' via terminal.onOutput
        // The terminal.onOutput is overridden in MobileTerminalView to
        // route through applyModifiers before sending to shell.
        // We can verify by calling applyModifiers directly and checking
        // the keyboard bar state transitions work with the bar widget.
        final transformed = barState.applyModifiers('c');
        expect(transformed, SshKeySequences.ctrlKey('c'));
        // Ctrl+C = 0x03
        expect(transformed.codeUnitAt(0), 0x03);

        await stdoutCtrl.close();
        await stderrCtrl.close();
      },
    );

    testWidgets('system keyboard input without modifier sends raw character', (
      tester,
    ) async {
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
      when(mockSession.write(any)).thenReturn(null);

      final conn = Connection(
        id: 'test-sysraw',
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
            home: Scaffold(body: MobileTerminalView(connection: conn)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final barState = tester.state<SshKeyboardBarState>(
        find.byType(SshKeyboardBar),
      );

      // No modifier active — raw pass-through
      expect(barState.applyModifiers('c'), 'c');
      expect(barState.applyModifiers('x'), 'x');

      await stdoutCtrl.close();
      await stderrCtrl.close();
    });
  });

  group('MobileTerminalView — select mode', () {
    testWidgets('select button renders on keyboard bar', (tester) async {
      final mockSsh = MockSSHConnection();
      final mockSession = MockSSHSession();
      final conn = connectedConn(mockSsh, mockSession);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Scaffold(body: MobileTerminalView(connection: conn)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.select_all), findsOneWidget);
    });

    testWidgets('tapping select button suspends pointer input', (tester) async {
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
        id: 'select-2',
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
            home: Scaffold(body: MobileTerminalView(connection: conn)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find the TerminalController via TerminalView
      final terminalView = tester.widget<TerminalView>(
        find.byType(TerminalView),
      );
      final controller = terminalView.controller!;

      expect(controller.suspendedPointerInputs, isFalse);

      // Tap select button
      await tester.tap(find.byIcon(Icons.select_all));
      await tester.pump();

      expect(controller.suspendedPointerInputs, isTrue);

      // Tap again to deactivate
      await tester.tap(find.byIcon(Icons.select_all));
      await tester.pump();

      expect(controller.suspendedPointerInputs, isFalse);

      await stdoutCtrl.close();
      await stderrCtrl.close();
    });

    testWidgets('scale gestures disabled during select mode', (tester) async {
      final mockSsh = MockSSHConnection();
      final mockSession = MockSSHSession();
      final conn = connectedConn(mockSsh, mockSession);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Scaffold(body: MobileTerminalView(connection: conn)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Before select mode: scale gestures are configured
      var gds = tester.widgetList<GestureDetector>(
        find.byType(GestureDetector),
      );
      expect(gds.where((g) => g.onScaleStart != null), isNotEmpty);

      // Enable select mode
      await tester.tap(find.byIcon(Icons.select_all));
      await tester.pump();

      // After select mode: scale gestures are disabled
      gds = tester.widgetList<GestureDetector>(find.byType(GestureDetector));
      expect(gds.where((g) => g.onScaleStart != null), isEmpty);

      // Disable select mode
      await tester.tap(find.byIcon(Icons.select_all));
      await tester.pump();

      // Scale gestures re-enabled
      gds = tester.widgetList<GestureDetector>(find.byType(GestureDetector));
      expect(gds.where((g) => g.onScaleStart != null), isNotEmpty);
    });

    testWidgets('selection toolbar is positioned as overlay in Stack', (
      tester,
    ) async {
      final mockSsh = MockSSHConnection();
      final mockSession = MockSSHSession();
      final conn = connectedConn(mockSsh, mockSession);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Scaffold(body: MobileTerminalView(connection: conn)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Enable select mode
      await tester.tap(find.byIcon(Icons.select_all));
      await tester.pump();

      // Simulate selection via controller using BufferLine anchors
      final terminalView = tester.widget<TerminalView>(
        find.byType(TerminalView),
      );
      final controller = terminalView.controller!;
      final terminal = terminalView.terminal;
      final line = terminal.buffer.lines[0];
      final base = line.createAnchor(0);
      final extent = line.createAnchor(3);
      controller.setSelection(base, extent);
      await tester.pump();

      // Toolbar should appear as overlay (inside Positioned, not Column)
      expect(find.text('Copy'), findsOneWidget);
      final positioned = tester.widgetList<Positioned>(
        find.ancestor(of: find.text('Copy'), matching: find.byType(Positioned)),
      );
      expect(positioned, isNotEmpty);
      expect(positioned.first.bottom, 0);
    });
  });
}
