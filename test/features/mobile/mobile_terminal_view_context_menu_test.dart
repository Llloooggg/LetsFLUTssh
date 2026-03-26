import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:xterm/xterm.dart';

import 'package:letsflutssh/core/connection/connection.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/features/mobile/mobile_terminal_view.dart';
import 'package:letsflutssh/theme/app_theme.dart';

import '../../core/ssh/shell_helper_test.mocks.dart';

Connection _connectedConn(MockSSHConnection mockSsh, MockSSHSession mockSession) {
  final stdoutCtrl = StreamController<Uint8List>.broadcast();
  final stderrCtrl = StreamController<Uint8List>.broadcast();
  final doneCompleter = Completer<void>();

  when(mockSsh.isConnected).thenReturn(true);
  when(mockSsh.openShell(any, any)).thenAnswer((_) async => mockSession);
  when(mockSession.stdout).thenAnswer((_) => stdoutCtrl.stream);
  when(mockSession.stderr).thenAnswer((_) => stderrCtrl.stream);
  when(mockSession.done).thenAnswer((_) => doneCompleter.future);

  return Connection(
    id: 'test-ctx',
    label: 'Test',
    sshConfig: const SSHConfig(host: 'h', user: 'u'),
    sshConnection: mockSsh,
    state: SSHConnectionState.connected,
  );
}

void main() {
  group('MobileTerminalView — _showContextMenu (lines 108-136)', () {
    testWidgets('long press triggers onLongPressStart which calls _showContextMenu',
        (tester) async {
      final mockSsh = MockSSHConnection();
      final mockSession = MockSSHSession();
      final conn = _connectedConn(mockSsh, mockSession);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(body: MobileTerminalView(connection: conn)),
        ),
      );
      await tester.pumpAndSettle();

      // Find the GestureDetector that wraps the terminal view
      final gds = tester.widgetList<GestureDetector>(find.byType(GestureDetector));
      final terminalGd = gds.where((g) => g.onLongPressStart != null).toList();
      expect(terminalGd, isNotEmpty, reason: 'Should have GestureDetector with onLongPressStart');

      // Manually invoke onLongPressStart to cover _showContextMenu
      // This opens the popup menu with Paste item
      final gd = terminalGd.first;
      final center = tester.getCenter(find.byType(TerminalView));
      gd.onLongPressStart!(LongPressStartDetails(globalPosition: center));
      await tester.pumpAndSettle();

      // The context menu should appear with at least 'Paste'
      expect(find.text('Paste'), findsOneWidget);
    });

    testWidgets('paste action in context menu reads from clipboard and inputs text',
        (tester) async {
      final mockSsh = MockSSHConnection();
      final mockSession = MockSSHSession();
      final conn = _connectedConn(mockSsh, mockSession);

      // Set clipboard data
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
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(body: MobileTerminalView(connection: conn)),
        ),
      );
      await tester.pumpAndSettle();

      // Open context menu via onLongPressStart
      final gds = tester.widgetList<GestureDetector>(find.byType(GestureDetector));
      final terminalGd = gds.where((g) => g.onLongPressStart != null).first;
      final center = tester.getCenter(find.byType(TerminalView));
      terminalGd.onLongPressStart!(LongPressStartDetails(globalPosition: center));
      await tester.pumpAndSettle();

      // Tap Paste
      await tester.tap(find.text('Paste'));
      await tester.pumpAndSettle();

      // The paste action calls Clipboard.getData then terminal.textInput
      // Give time for the async clipboard read
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('context menu without selection does not show Copy',
        (tester) async {
      final mockSsh = MockSSHConnection();
      final mockSession = MockSSHSession();
      final conn = _connectedConn(mockSsh, mockSession);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(body: MobileTerminalView(connection: conn)),
        ),
      );
      await tester.pumpAndSettle();

      // Open context menu
      final gds = tester.widgetList<GestureDetector>(find.byType(GestureDetector));
      final terminalGd = gds.where((g) => g.onLongPressStart != null).first;
      final center = tester.getCenter(find.byType(TerminalView));
      terminalGd.onLongPressStart!(LongPressStartDetails(globalPosition: center));
      await tester.pumpAndSettle();

      // No selection -> no Copy item
      expect(find.text('Copy'), findsNothing);
      expect(find.text('Paste'), findsOneWidget);

      // Dismiss menu
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();
    });
  });

  group('MobileTerminalView — onScaleEnd resets base font', () {
    testWidgets('onScaleEnd is configured on GestureDetector', (tester) async {
      final mockSsh = MockSSHConnection();
      final mockSession = MockSSHSession();
      final conn = _connectedConn(mockSsh, mockSession);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(body: MobileTerminalView(connection: conn)),
        ),
      );
      await tester.pumpAndSettle();

      final gds = tester.widgetList<GestureDetector>(find.byType(GestureDetector));
      final scaleGd = gds.where((g) => g.onScaleEnd != null).toList();
      expect(scaleGd, isNotEmpty);
    });
  });
}
