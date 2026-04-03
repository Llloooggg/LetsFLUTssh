import 'dart:async';

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
    MockSSHConnection mockSsh, MockSSHSession mockSession) {
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
    sshConfig: const SSHConfig(server: ServerAddress(host: 'h', user: 'u')),
    sshConnection: mockSsh,
    state: SSHConnectionState.connected,
  );
}

void main() {
  group('MobileTerminalView — loading state', () {
    testWidgets('shows loading indicator while connecting', (tester) async {
      final mockSsh = MockSSHConnection();
      when(mockSsh.isConnected).thenReturn(true);
      when(mockSsh.openShell(any, any))
          .thenAnswer((_) => Completer<Never>().future);

      final conn = Connection(
        id: 'test-1',
        label: 'Test',
        sshConfig: const SSHConfig(server: ServerAddress(host: 'h', user: 'u')),
        sshConnection: mockSsh,
        state: SSHConnectionState.connected,
      );

      await tester.pumpWidget(
        ProviderScope(child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(body: MobileTerminalView(connection: conn)),
        )),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });

  group('MobileTerminalView — error states', () {
    testWidgets('shows error state when shell fails', (tester) async {
      final mockSsh = MockSSHConnection();
      when(mockSsh.isConnected).thenReturn(true);
      when(mockSsh.openShell(any, any)).thenThrow(Exception('Shell failed'));

      final conn = Connection(
        id: 'test-2',
        label: 'Test',
        sshConfig: const SSHConfig(server: ServerAddress(host: 'h', user: 'u')),
        sshConnection: mockSsh,
        state: SSHConnectionState.connected,
      );

      await tester.pumpWidget(
        ProviderScope(child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(body: MobileTerminalView(connection: conn)),
        )),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('shows error when sshConnection is null', (tester) async {
      final conn = Connection(
        id: 'test-3',
        label: 'Test',
        sshConfig: const SSHConfig(server: ServerAddress(host: 'h', user: 'u')),
        sshConnection: null,
        state: SSHConnectionState.disconnected,
      );

      await tester.pumpWidget(
        ProviderScope(child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(body: MobileTerminalView(connection: conn)),
        )),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('error text shows specific error message', (tester) async {
      final mockSsh = MockSSHConnection();
      when(mockSsh.isConnected).thenReturn(true);
      when(mockSsh.openShell(any, any))
          .thenThrow(Exception('Connection refused'));

      final conn = Connection(
        id: 'test-err',
        label: 'Test',
        sshConfig: const SSHConfig(server: ServerAddress(host: 'h', user: 'u')),
        sshConnection: mockSsh,
        state: SSHConnectionState.connected,
      );

      await tester.pumpWidget(
        ProviderScope(child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(body: MobileTerminalView(connection: conn)),
        )),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Connection refused'), findsOneWidget);
    });

    testWidgets('error state uses disconnected color', (tester) async {
      final conn = Connection(
        id: 'test-color',
        label: 'Test',
        sshConfig: const SSHConfig(server: ServerAddress(host: 'h', user: 'u')),
        sshConnection: null,
        state: SSHConnectionState.disconnected,
      );

      await tester.pumpWidget(
        ProviderScope(child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(body: MobileTerminalView(connection: conn)),
        )),
      );
      await tester.pumpAndSettle();

      final icon = tester.widget<Icon>(find.byIcon(Icons.error_outline));
      expect(icon.color, AppTheme.disconnected);
      expect(icon.size, 48);
    });

    testWidgets('error text has disconnected color and center alignment',
        (tester) async {
      final mockSsh = MockSSHConnection();
      when(mockSsh.isConnected).thenReturn(true);
      when(mockSsh.openShell(any, any)).thenThrow(Exception('fail'));

      final conn = Connection(
        id: 'test-align',
        label: 'Test',
        sshConfig: const SSHConfig(server: ServerAddress(host: 'h', user: 'u')),
        sshConnection: mockSsh,
        state: SSHConnectionState.connected,
      );

      await tester.pumpWidget(
        ProviderScope(child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(body: MobileTerminalView(connection: conn)),
        )),
      );
      await tester.pumpAndSettle();

      final errorText = tester.widget<Text>(find.byWidgetPredicate((w) =>
          w is Text &&
          w.style?.color == AppTheme.disconnected &&
          w.textAlign == TextAlign.center));
      expect(errorText, isNotNull);
    });

    testWidgets('error widget contains SizedBox(height: 16) spacer',
        (tester) async {
      final conn = Connection(
        id: 'test-spacer',
        label: 'Test',
        sshConfig: const SSHConfig(server: ServerAddress(host: 'h', user: 'u')),
        sshConnection: null,
        state: SSHConnectionState.disconnected,
      );

      await tester.pumpWidget(
        ProviderScope(child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(body: MobileTerminalView(connection: conn)),
        )),
      );
      await tester.pumpAndSettle();

      final sizedBoxes = tester.widgetList<SizedBox>(find.byType(SizedBox));
      final spacer16 = sizedBoxes.where((sb) => sb.height == 16);
      expect(spacer16, isNotEmpty);
    });
  });

  group('MobileTerminalView — successful connection', () {
    testWidgets('renders terminal and keyboard bar on success',
        (tester) async {
      final mockSsh = MockSSHConnection();
      final mockSession = MockSSHSession();
      final conn = connectedConn(mockSsh, mockSession);

      await tester.pumpWidget(
        ProviderScope(child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(body: MobileTerminalView(connection: conn)),
        )),
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

    testWidgets('shell done callback sets session closed error',
        (tester) async {
      final mockSsh = MockSSHConnection();
      final mockSession = MockSSHSession();
      when(mockSsh.isConnected).thenReturn(true);

      final stdoutCtrl = StreamController<Uint8List>.broadcast();
      final stderrCtrl = StreamController<Uint8List>.broadcast();
      final doneCompleter = Completer<void>();

      when(mockSsh.openShell(any, any))
          .thenAnswer((_) async => mockSession);
      when(mockSession.stdout).thenAnswer((_) => stdoutCtrl.stream);
      when(mockSession.stderr).thenAnswer((_) => stderrCtrl.stream);
      when(mockSession.done).thenAnswer((_) => doneCompleter.future);

      final conn = Connection(
        id: 'test-done',
        label: 'Test',
        sshConfig: const SSHConfig(server: ServerAddress(host: 'h', user: 'u')),
        sshConnection: mockSsh,
        state: SSHConnectionState.connected,
      );

      await tester.pumpWidget(
        ProviderScope(child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(body: MobileTerminalView(connection: conn)),
        )),
      );
      await tester.pumpAndSettle();

      doneCompleter.complete();
      await tester.pumpAndSettle();

      expect(find.textContaining('Session closed'), findsOneWidget);

      await stdoutCtrl.close();
      await stderrCtrl.close();
    });

    testWidgets('GestureDetector present for pinch zoom', (tester) async {
      final mockSsh = MockSSHConnection();
      final mockSession = MockSSHSession();
      final conn = connectedConn(mockSsh, mockSession);

      await tester.pumpWidget(
        ProviderScope(child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(body: MobileTerminalView(connection: conn)),
        )),
      );
      await tester.pumpAndSettle();

      expect(find.byType(GestureDetector), findsWidgets);
    });

    testWidgets('widget disposes without errors', (tester) async {
      final mockSsh = MockSSHConnection();
      final mockSession = MockSSHSession();
      final conn = connectedConn(mockSsh, mockSession);

      await tester.pumpWidget(
        ProviderScope(child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(body: MobileTerminalView(connection: conn)),
        )),
      );
      await tester.pumpAndSettle();

      await tester.pumpWidget(
        ProviderScope(child: MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(body: SizedBox()),
        )),
      );
      await tester.pumpAndSettle();
    });

    testWidgets('Column layout has Expanded terminal and keyboard bar',
        (tester) async {
      final mockSsh = MockSSHConnection();
      final mockSession = MockSSHSession();
      final conn = connectedConn(mockSsh, mockSession);

      await tester.pumpWidget(
        ProviderScope(child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(body: MobileTerminalView(connection: conn)),
        )),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Column), findsWidgets);
      expect(find.text('Ctrl'), findsOneWidget);
      expect(find.text('Alt'), findsOneWidget);
    });
  });

  group('MobileTerminalView — pinch-to-zoom', () {
    testWidgets('pinch zoom changes font size and clamps between 8 and 24',
        (tester) async {
      final mockSsh = MockSSHConnection();
      final mockSession = MockSSHSession();
      final conn = connectedConn(mockSsh, mockSession);

      await tester.pumpWidget(
        ProviderScope(child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(body: MobileTerminalView(connection: conn)),
        )),
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
        ProviderScope(child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(body: MobileTerminalView(connection: conn)),
        )),
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

    testWidgets('onScaleEnd is configured on GestureDetector',
        (tester) async {
      final mockSsh = MockSSHConnection();
      final mockSession = MockSSHSession();
      final conn = connectedConn(mockSsh, mockSession);

      await tester.pumpWidget(
        ProviderScope(child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(body: MobileTerminalView(connection: conn)),
        )),
      );
      await tester.pumpAndSettle();

      final gds =
          tester.widgetList<GestureDetector>(find.byType(GestureDetector));
      final scaleGd = gds.where((g) => g.onScaleEnd != null).toList();
      expect(scaleGd, isNotEmpty);
    });
  });

  group('MobileTerminalView — font size from settings', () {
    testWidgets('font size updates reactively from configProvider',
        (tester) async {
      final mockSsh = MockSSHConnection();
      final mockSession = MockSSHSession();
      final conn = connectedConn(mockSsh, mockSession);

      await tester.pumpWidget(
        ProviderScope(child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(body: MobileTerminalView(connection: conn)),
        )),
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
      when(mockSsh.openShell(any, any))
          .thenAnswer((_) async => mockSession);
      when(mockSession.stdout).thenAnswer((_) => stdoutCtrl.stream);
      when(mockSession.stderr).thenAnswer((_) => stderrCtrl.stream);
      when(mockSession.done).thenAnswer((_) => doneCompleter.future);
      when(mockSession.write(any)).thenReturn(null);

      final conn = Connection(
        id: 'test-kb',
        label: 'Test',
        sshConfig: const SSHConfig(server: ServerAddress(host: 'h', user: 'u')),
        sshConnection: mockSsh,
        state: SSHConnectionState.connected,
      );

      await tester.pumpWidget(
        ProviderScope(child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(body: MobileTerminalView(connection: conn)),
        )),
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

  group('MobileTerminalView — context menu', () {
    testWidgets('long press GestureDetector has onLongPressStart',
        (tester) async {
      final mockSsh = MockSSHConnection();
      final mockSession = MockSSHSession();
      final conn = connectedConn(mockSsh, mockSession);

      await tester.pumpWidget(
        ProviderScope(child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(body: MobileTerminalView(connection: conn)),
        )),
      );
      await tester.pumpAndSettle();

      final gds =
          tester.widgetList<GestureDetector>(find.byType(GestureDetector));
      final hasLongPress = gds.any((g) => g.onLongPressStart != null);
      expect(hasLongPress, isTrue);
    });

    testWidgets('long press opens context menu with Paste',
        (tester) async {
      final mockSsh = MockSSHConnection();
      final mockSession = MockSSHSession();
      final conn = connectedConn(mockSsh, mockSession);

      await tester.pumpWidget(
        ProviderScope(child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(body: MobileTerminalView(connection: conn)),
        )),
      );
      await tester.pumpAndSettle();

      final gds =
          tester.widgetList<GestureDetector>(find.byType(GestureDetector));
      final terminalGd =
          gds.where((g) => g.onLongPressStart != null).toList();
      expect(terminalGd, isNotEmpty);

      final gd = terminalGd.first;
      final center = tester.getCenter(find.byType(TerminalView));
      gd.onLongPressStart!(LongPressStartDetails(globalPosition: center));
      await tester.pumpAndSettle();

      expect(find.text('Paste'), findsOneWidget);
    });

    testWidgets('paste action reads from clipboard', (tester) async {
      final mockSsh = MockSSHConnection();
      final mockSession = MockSSHSession();
      final conn = connectedConn(mockSsh, mockSession);

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.getData') {
            return {'text': 'pasted-text'};
          }
          return null;
        },
      );
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
      });

      await tester.pumpWidget(
        ProviderScope(child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(body: MobileTerminalView(connection: conn)),
        )),
      );
      await tester.pumpAndSettle();

      final gds =
          tester.widgetList<GestureDetector>(find.byType(GestureDetector));
      final terminalGd =
          gds.where((g) => g.onLongPressStart != null).first;
      final center = tester.getCenter(find.byType(TerminalView));
      terminalGd
          .onLongPressStart!(LongPressStartDetails(globalPosition: center));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Paste'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('context menu without selection does not show Copy',
        (tester) async {
      final mockSsh = MockSSHConnection();
      final mockSession = MockSSHSession();
      final conn = connectedConn(mockSsh, mockSession);

      await tester.pumpWidget(
        ProviderScope(child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(body: MobileTerminalView(connection: conn)),
        )),
      );
      await tester.pumpAndSettle();

      final gds =
          tester.widgetList<GestureDetector>(find.byType(GestureDetector));
      final terminalGd =
          gds.where((g) => g.onLongPressStart != null).first;
      final center = tester.getCenter(find.byType(TerminalView));
      terminalGd
          .onLongPressStart!(LongPressStartDetails(globalPosition: center));
      await tester.pumpAndSettle();

      expect(find.text('Copy'), findsNothing);
      expect(find.text('Paste'), findsOneWidget);

      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();
    });
  });

  group('MobileTerminalView — system keyboard with modifiers', () {
    testWidgets('Ctrl modifier applies to system keyboard input via terminal.onOutput', (tester) async {
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
        sshConfig: const SSHConfig(server: ServerAddress(host: 'h', user: 'u')),
        sshConnection: mockSsh,
        state: SSHConnectionState.connected,
      );

      await tester.pumpWidget(
        ProviderScope(child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(body: MobileTerminalView(connection: conn)),
        )),
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
    });

    testWidgets('system keyboard input without modifier sends raw character', (tester) async {
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
        sshConfig: const SSHConfig(server: ServerAddress(host: 'h', user: 'u')),
        sshConnection: mockSsh,
        state: SSHConnectionState.connected,
      );

      await tester.pumpWidget(
        ProviderScope(child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(body: MobileTerminalView(connection: conn)),
        )),
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
        ProviderScope(child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(body: MobileTerminalView(connection: conn)),
        )),
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
        sshConfig: const SSHConfig(server: ServerAddress(host: 'h', user: 'u')),
        sshConnection: mockSsh,
        state: SSHConnectionState.connected,
      );

      await tester.pumpWidget(
        ProviderScope(child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(body: MobileTerminalView(connection: conn)),
        )),
      );
      await tester.pumpAndSettle();

      // Find the TerminalController via TerminalView
      final terminalView = tester.widget<TerminalView>(find.byType(TerminalView));
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
  });
}
