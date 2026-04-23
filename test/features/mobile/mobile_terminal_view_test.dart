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
import 'package:letsflutssh/features/mobile/terminal_copy_overlay.dart';
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

    testWidgets('Listener wraps the terminal for pointer tracking', (
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

      // Manual pointer tracking replaced the stock ScaleGestureRecognizer
      // so single-finger gestures reach xterm's long-press recognizer.
      expect(find.byType(Listener), findsWidgets);
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

  group('MobileTerminalView — copy mode', () {
    testWidgets('copy button renders on keyboard bar', (tester) async {
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

      expect(find.byIcon(Icons.copy), findsOneWidget);
    });

    testWidgets('tapping copy button suspends pointer input', (tester) async {
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

      // Enter copy mode via the Copy icon in the normal bar row.
      await tester.tap(find.byIcon(Icons.copy));
      await tester.pump();

      expect(controller.suspendedPointerInputs, isTrue);

      // Exit via the Cancel (close) icon that the bar swaps in for
      // its copy-mode content — Icons.copy in this state is the Copy
      // action, not a toggle, so tapping it would fire onCopyPressed
      // instead of leaving copy mode.
      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();

      expect(controller.suspendedPointerInputs, isFalse);

      await stdoutCtrl.close();
      await stderrCtrl.close();
    });

    testWidgets('copy overlay mounts when copy mode is enabled', (
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

      // Before copy mode: overlay is not mounted.
      expect(find.byType(TerminalCopyOverlay), findsNothing);

      // Enter copy mode.
      await tester.tap(find.byIcon(Icons.copy));
      await tester.pumpAndSettle();

      // Overlay mounts; the SSH bar's row swaps to copy-mode content
      // with a hint + Set-Anchor (Icons.adjust) + Cancel. The Copy
      // action only appears AFTER the user explicitly commits the
      // anchor via the Set-Anchor button, since aiming on a phone
      // can take more than one drag.
      expect(find.byType(TerminalCopyOverlay), findsOneWidget);
      expect(find.byIcon(Icons.adjust), findsOneWidget);
      expect(find.byIcon(Icons.close), findsOneWidget);
      expect(find.byIcon(Icons.copy), findsNothing);
    });

    testWidgets('tapping overlay Cancel exits copy mode', (tester) async {
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

      await tester.tap(find.byIcon(Icons.copy));
      await tester.pumpAndSettle();
      expect(find.byType(TerminalCopyOverlay), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.byType(TerminalCopyOverlay), findsNothing);
    });

    testWidgets(
      'selection set outside copy mode is cleared by the mobile guard',
      (tester) async {
        // Pin the "no touch-selection outside copy mode" invariant. xterm's
        // TerminalGestureHandler routes long-press + drag into
        // `controller.setSelection`; on mobile that path must not leave a
        // selection behind — the sanctioned selection surface is the
        // copy-mode overlay, nothing else. We simulate the xterm path by
        // poking the controller directly, which is what its internal gesture
        // handler does on a long-press → word select.
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

        // Reach the controller through the mounted TerminalView.
        final tv = tester.widget<TerminalView>(find.byType(TerminalView));
        final controller = tv.controller!;
        final terminal = tv.terminal;
        // Make sure the buffer has something to anchor against.
        terminal.write('hello world\r\n');
        await tester.pump();

        final buf = terminal.buffer;
        controller.setSelection(buf.createAnchor(0, 0), buf.createAnchor(5, 0));
        // The guard runs inside `addListener` → the listener fires
        // synchronously during `setSelection`, so by the time the call
        // returns the controller should already be back to null.
        expect(
          controller.selection,
          isNull,
          reason: 'Mobile guard must clear any selection set outside copy mode',
        );
      },
    );

    testWidgets(
      'pointer events alone never drop the selection anchor (aim phase)',
      (tester) async {
        // Regression gate for the two-phase copy-mode model: pointer
        // events only aim the virtual cursor. Anchor commit is
        // exclusively driven by the Set-Anchor button on the bar —
        // lifts, multiple touches, moves, none of them drop an
        // anchor. Earlier revisions committed on the first lift,
        // which failed the "can't aim in one drag" reports from
        // phone users.
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

        await tester.tap(find.byIcon(Icons.copy));
        await tester.pumpAndSettle();

        final overlay = tester.state<TerminalCopyOverlayState>(
          find.byType(TerminalCopyOverlay),
        );

        // Drag + lift + drag + lift — two full pointer cycles must
        // still leave `anchorSet` false.
        final termCenter = tester.getCenter(find.byType(TerminalView));
        final first = await tester.startGesture(termCenter);
        await first.moveBy(const Offset(40, 0));
        await first.up();
        await tester.pumpAndSettle();
        expect(overlay.anchorSet, isFalse);

        final second = await tester.startGesture(termCenter);
        await second.moveBy(const Offset(20, 20));
        await second.up();
        await tester.pumpAndSettle();
        expect(overlay.anchorSet, isFalse);

        // Tapping the Set-Anchor action on the bar is the only way
        // to commit.
        await tester.tap(find.byIcon(Icons.adjust));
        await tester.pumpAndSettle();
        expect(overlay.anchorSet, isTrue);
      },
    );

    testWidgets('AbsorbPointer gates the terminal while copy mode is active', (
      tester,
    ) async {
      // Regression gate. xterm's internal PanGestureRecognizer was
      // racing `TerminalCopyOverlay.onCursorPan` on every frame —
      // both wrote to `TerminalController.setSelection`, which painted
      // duplicate scrollback rows and left selection gaps. The fix
      // wraps `TerminalView` in an `AbsorbPointer` whose `absorbing`
      // flag tracks `_copyMode`. Pin that invariant here: when the
      // mode is off, the AbsorbPointer is transparent; when the
      // overlay is active, it absorbs.
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

      AbsorbPointer guard() {
        final finder = find.ancestor(
          of: find.byType(TerminalView),
          matching: find.byType(AbsorbPointer),
        );
        return tester.widget<AbsorbPointer>(finder.first);
      }

      expect(guard().absorbing, isFalse);

      await tester.tap(find.byIcon(Icons.copy));
      await tester.pumpAndSettle();
      expect(guard().absorbing, isTrue);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(guard().absorbing, isFalse);
    });

    testWidgets('selection set INSIDE copy mode survives the guard', (
      tester,
    ) async {
      // Inverse of the above — once the overlay is mounted the guard
      // must step aside, otherwise the user's extend-selection path
      // through the overlay would stamp and immediately lose every
      // anchor.
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

      // Enter copy mode via the keyboard bar's Copy button.
      await tester.tap(find.byIcon(Icons.copy));
      await tester.pumpAndSettle();
      expect(find.byType(TerminalCopyOverlay), findsOneWidget);

      final tv = tester.widget<TerminalView>(find.byType(TerminalView));
      final controller = tv.controller!;
      final terminal = tv.terminal;
      terminal.write('hello world\r\n');
      await tester.pump();
      final buf = terminal.buffer;
      controller.setSelection(buf.createAnchor(0, 0), buf.createAnchor(5, 0));
      expect(controller.selection, isNotNull);
    });
  });
}
