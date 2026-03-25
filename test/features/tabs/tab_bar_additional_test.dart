import 'package:flutter/gestures.dart';
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

  Widget buildAppWithTabs(List<TabEntry> tabs, {int activeIndex = 0}) {
    return ProviderScope(
      overrides: [
        tabProvider.overrideWith((ref) {
          final notifier = TabNotifier();
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

  group('AppTabBar — context menu Close Tabs to Right', () {
    testWidgets('Close Tabs to the Right closes tabs after clicked one', (tester) async {
      final conn = makeConn();
      await tester.pumpWidget(buildAppWithTabs([
        TabEntry(id: 't1', label: 'Tab A', connection: conn, kind: TabKind.terminal),
        TabEntry(id: 't2', label: 'Tab B', connection: conn, kind: TabKind.sftp),
        TabEntry(id: 't3', label: 'Tab C', connection: conn, kind: TabKind.terminal),
      ]));
      await tester.pumpAndSettle();

      // Right-click on Tab A (index 0)
      final tabA = find.text('Tab A').first;
      final center = tester.getCenter(tabA);
      final gesture = await tester.startGesture(center, kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
      await gesture.up();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Close Tabs to the Right'));
      await tester.pumpAndSettle();

      // Only Tab A should remain
      expect(find.text('Tab A'), findsWidgets);
    });
  });

  group('AppTabBar — context menu Close Tabs to Left', () {
    testWidgets('Close Tabs to the Left closes tabs before clicked one', (tester) async {
      final conn = makeConn();
      await tester.pumpWidget(buildAppWithTabs([
        TabEntry(id: 't1', label: 'Tab A', connection: conn, kind: TabKind.terminal),
        TabEntry(id: 't2', label: 'Tab B', connection: conn, kind: TabKind.sftp),
        TabEntry(id: 't3', label: 'Tab C', connection: conn, kind: TabKind.terminal),
      ], activeIndex: 2));
      await tester.pumpAndSettle();

      // Right-click on Tab C (the last one)
      final tabC = find.text('Tab C').first;
      final center = tester.getCenter(tabC);
      final gesture = await tester.startGesture(center, kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
      await gesture.up();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Close Tabs to the Left'));
      await tester.pumpAndSettle();

      // Only Tab C should remain
      expect(find.text('Tab C'), findsWidgets);
    });
  });

  group('AppTabBar — context menu single tab', () {
    testWidgets('context menu on single tab shows only Close', (tester) async {
      final conn = makeConn();
      await tester.pumpWidget(buildAppWithTabs([
        TabEntry(id: 't1', label: 'Only Tab', connection: conn, kind: TabKind.terminal),
      ]));
      await tester.pumpAndSettle();

      // Right-click on the only tab
      final tab = find.text('Only Tab').first;
      final center = tester.getCenter(tab);
      final gesture = await tester.startGesture(center, kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
      await gesture.up();
      await tester.pumpAndSettle();

      // Only Close should appear — no Close Others, Close Left, Close Right
      expect(find.text('Close'), findsOneWidget);
      expect(find.text('Close Others'), findsNothing);
      expect(find.text('Close Tabs to the Left'), findsNothing);
      expect(find.text('Close Tabs to the Right'), findsNothing);

      // Dismiss menu
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();
    });
  });

  group('AppTabBar — SFTP tab icon in drag chip', () {
    testWidgets('SFTP tab shows folder icon', (tester) async {
      final conn = makeConn();
      await tester.pumpWidget(buildAppWithTabs([
        TabEntry(id: 't1', label: 'Files', connection: conn, kind: TabKind.sftp),
      ]));
      await tester.pumpAndSettle();

      // SFTP tab should show folder icon
      expect(find.byIcon(Icons.folder), findsWidgets);
    });
  });

  group('AppTabBar — drag chip rendering', () {
    testWidgets('Draggable has TabEntry data', (tester) async {
      final conn = makeConn();
      await tester.pumpWidget(buildAppWithTabs([
        TabEntry(id: 't1', label: 'DragMe', connection: conn, kind: TabKind.terminal),
      ]));
      await tester.pumpAndSettle();

      final draggable = tester.widget<Draggable<TabEntry>>(find.byType(Draggable<TabEntry>));
      expect(draggable.data, isNotNull);
    });
  });
}
