import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/connection/connection.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/features/tabs/tab_bar.dart';
import 'package:letsflutssh/features/tabs/tab_controller.dart';
import 'package:letsflutssh/features/tabs/tab_model.dart';
import 'package:letsflutssh/theme/app_theme.dart';

void main() {
  Connection makeConn({
    String label = 'Server',
    SSHConnectionState state = SSHConnectionState.connected,
  }) {
    return Connection(
      id: 'conn-1',
      label: label,
      sshConfig: const SSHConfig(host: '10.0.0.1', user: 'root'),
      state: state,
    );
  }

  /// Build app with pre-populated tabs via the notifier.
  Widget buildAppWithTabs(List<TabEntry> tabs, {int activeIndex = 0}) {
    return ProviderScope(
      overrides: [
        tabProvider.overrideWith((ref) {
          final notifier = TabNotifier();
          // Add tabs by calling the notifier methods
          for (final tab in tabs) {
            if (tab.kind == TabKind.terminal) {
              notifier.addTerminalTab(tab.connection, label: tab.label);
            } else {
              notifier.addSftpTab(tab.connection, label: tab.label);
            }
          }
          if (activeIndex >= 0 && activeIndex < tabs.length) {
            notifier.selectTab(activeIndex);
          }
          return notifier;
        }),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(body: AppTabBar()),
      ),
    );
  }

  group('AppTabBar', () {
    testWidgets('renders nothing when no tabs', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const Scaffold(body: AppTabBar()),
          ),
        ),
      );
      // Should render SizedBox.shrink
      expect(find.byType(ListView), findsNothing);
    });

    testWidgets('renders tab labels', (tester) async {
      final conn = makeConn(label: 'MyServer');
      await tester.pumpWidget(buildAppWithTabs([
        TabEntry(id: 't1', label: 'MyServer', connection: conn, kind: TabKind.terminal),
      ]));
      await tester.pumpAndSettle();
      expect(find.text('MyServer'), findsWidgets);
    });

    testWidgets('renders terminal icon for terminal tab', (tester) async {
      final conn = makeConn();
      await tester.pumpWidget(buildAppWithTabs([
        TabEntry(id: 't1', label: 'SSH', connection: conn, kind: TabKind.terminal),
      ]));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.terminal), findsWidgets);
    });

    testWidgets('renders folder icon for SFTP tab', (tester) async {
      final conn = makeConn();
      await tester.pumpWidget(buildAppWithTabs([
        TabEntry(id: 't1', label: 'SFTP', connection: conn, kind: TabKind.sftp),
      ]));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.folder), findsWidgets);
    });

    testWidgets('renders close button', (tester) async {
      final conn = makeConn();
      await tester.pumpWidget(buildAppWithTabs([
        TabEntry(id: 't1', label: 'Tab1', connection: conn, kind: TabKind.terminal),
      ]));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.close), findsWidgets);
    });

    testWidgets('renders multiple tabs', (tester) async {
      final conn = makeConn();
      await tester.pumpWidget(buildAppWithTabs([
        TabEntry(id: 't1', label: 'Tab A', connection: conn, kind: TabKind.terminal),
        TabEntry(id: 't2', label: 'Tab B', connection: conn, kind: TabKind.sftp),
      ]));
      await tester.pumpAndSettle();
      // Labels appear in Draggable feedback too, so findWidgets
      expect(find.text('Tab A'), findsWidgets);
      expect(find.text('Tab B'), findsWidgets);
    });

    testWidgets('shows state indicator dot', (tester) async {
      final conn = makeConn(state: SSHConnectionState.connected);
      await tester.pumpWidget(buildAppWithTabs([
        TabEntry(id: 't1', label: 'Tab', connection: conn, kind: TabKind.terminal),
      ]));
      await tester.pumpAndSettle();
      // The 8x8 circle indicator exists
      final containers = tester.widgetList<Container>(find.byType(Container));
      final dotContainers = containers.where((c) {
        final decoration = c.decoration;
        if (decoration is BoxDecoration) {
          return decoration.shape == BoxShape.circle;
        }
        return false;
      });
      expect(dotContainers, isNotEmpty);
    });
  });
}
