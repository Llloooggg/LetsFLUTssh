import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:letsflutssh/core/connection/connection.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/features/terminal/terminal_tab.dart';
import 'package:letsflutssh/features/terminal/split_node.dart';
import 'package:letsflutssh/theme/app_theme.dart';

import '../../core/ssh/shell_helper_test.mocks.dart';

void main() {
  group('TerminalTab — connected state with tiling', () {
    Connection makeConnectedConn(MockSSHConnection mockSsh, MockSSHSession mockSession) {
      final stdoutCtrl = StreamController<Uint8List>.broadcast();
      final stderrCtrl = StreamController<Uint8List>.broadcast();
      final doneCompleter = Completer<void>();

      when(mockSsh.isConnected).thenReturn(true);
      when(mockSsh.openShell(any, any)).thenAnswer((_) async => mockSession);
      when(mockSession.stdout).thenAnswer((_) => stdoutCtrl.stream);
      when(mockSession.stderr).thenAnswer((_) => stderrCtrl.stream);
      when(mockSession.done).thenAnswer((_) => doneCompleter.future);

      return Connection(
        id: 'conn-tiling',
        label: 'TilingServer',
        sshConfig: const SSHConfig(host: 'h', user: 'u'),
        sshConnection: mockSsh,
        state: SSHConnectionState.connected,
      );
    }

    testWidgets('renders TilingView when connected', (tester) async {
      final mockSsh = MockSSHConnection();
      final mockSession = MockSSHSession();
      final conn = makeConnectedConn(mockSsh, mockSession);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: TerminalTab(
              tabId: 'tab-tiling',
              connection: conn,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Should render terminal (no error or loading)
      expect(find.byIcon(Icons.error_outline), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });

  group('TerminalTab — reconnect failure with sshConnection null', () {
    testWidgets('reconnect with null sshConnection shows Reconnect failed', (tester) async {
      final conn = Connection(
        id: 'reconnect-null',
        label: 'Test',
        sshConfig: const SSHConfig(host: 'h', user: 'u'),
        sshConnection: null,
        state: SSHConnectionState.disconnected,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: TerminalTab(
              tabId: 'tab-rn2',
              connection: conn,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Not connected'), findsOneWidget);

      await tester.tap(find.text('Reconnect'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Reconnect failed'), findsOneWidget);
    });
  });

  group('TerminalTab — error state UI details', () {
    testWidgets('error state uses disconnected color', (tester) async {
      final conn = Connection(
        id: 'err-color',
        label: 'Test',
        sshConfig: const SSHConfig(host: 'h', user: 'u'),
        sshConnection: null,
        state: SSHConnectionState.disconnected,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: TerminalTab(tabId: 'tab-err', connection: conn),
          ),
        ),
      );
      await tester.pump();

      final icon = tester.widget<Icon>(find.byIcon(Icons.error_outline));
      expect(icon.color, AppTheme.disconnected);
      expect(icon.size, 48);
    });

    testWidgets('Reconnect button has refresh icon', (tester) async {
      final conn = Connection(
        id: 'btn-icon',
        label: 'Test',
        sshConfig: const SSHConfig(host: 'h', user: 'u'),
        sshConnection: null,
        state: SSHConnectionState.disconnected,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: TerminalTab(tabId: 'tab-btn', connection: conn),
          ),
        ),
      );
      await tester.pump();

      expect(find.byIcon(Icons.refresh), findsOneWidget);
      expect(find.byIcon(Icons.close), findsOneWidget);
    });

    testWidgets('Close button calls onDisconnected', (tester) async {
      var called = false;
      final conn = Connection(
        id: 'close-cb',
        label: 'Test',
        sshConfig: const SSHConfig(host: 'h', user: 'u'),
        sshConnection: null,
        state: SSHConnectionState.disconnected,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: TerminalTab(
              tabId: 'tab-close',
              connection: conn,
              onDisconnected: () => called = true,
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Close'));
      await tester.pump();
      expect(called, isTrue);
    });
  });

  group('SplitNode — model tests', () {
    test('LeafNode generates unique id', () {
      final a = LeafNode();
      final b = LeafNode();
      expect(a.id, isNot(b.id));
    });

    test('LeafNode with explicit id', () {
      final leaf = LeafNode(id: 'custom-id');
      expect(leaf.id, 'custom-id');
    });

    test('BranchNode holds direction and children', () {
      final a = LeafNode();
      final b = LeafNode();
      final branch = BranchNode(
        direction: SplitDirection.vertical,
        first: a,
        second: b,
      );
      expect(branch.direction, SplitDirection.vertical);
      expect(branch.ratio, 0.5);
    });

    test('collectLeafIds returns all leaf ids', () {
      final a = LeafNode(id: 'a');
      final b = LeafNode(id: 'b');
      final c = LeafNode(id: 'c');
      final tree = BranchNode(
        direction: SplitDirection.vertical,
        first: a,
        second: BranchNode(
          direction: SplitDirection.horizontal,
          first: b,
          second: c,
        ),
      );

      final ids = collectLeafIds(tree);
      expect(ids, containsAll(['a', 'b', 'c']));
      expect(ids.length, 3);
    });

    test('replaceNode replaces leaf with branch', () {
      final a = LeafNode(id: 'a');
      final replacement = BranchNode(
        direction: SplitDirection.vertical,
        first: LeafNode(id: 'new1'),
        second: LeafNode(id: 'a'),
      );
      final result = replaceNode(a, 'a', replacement);
      expect(result, isA<BranchNode>());
    });

    test('removeNode returns null when removing root leaf', () {
      final root = LeafNode(id: 'only');
      final result = removeNode(root, 'only');
      expect(result, isNull);
    });

    test('removeNode removes from branch', () {
      final a = LeafNode(id: 'a');
      final b = LeafNode(id: 'b');
      final root = BranchNode(
        direction: SplitDirection.vertical,
        first: a,
        second: b,
      );
      final result = removeNode(root, 'a');
      expect(result, isA<LeafNode>());
      expect((result as LeafNode).id, 'b');
    });

    test('removeNode in nested tree', () {
      final a = LeafNode(id: 'a');
      final b = LeafNode(id: 'b');
      final c = LeafNode(id: 'c');
      final root = BranchNode(
        direction: SplitDirection.vertical,
        first: a,
        second: BranchNode(
          direction: SplitDirection.horizontal,
          first: b,
          second: c,
        ),
      );
      final result = removeNode(root, 'b');
      expect(result, isA<BranchNode>());
      final ids = collectLeafIds(result!);
      expect(ids, containsAll(['a', 'c']));
      expect(ids.length, 2);
    });
  });
}
