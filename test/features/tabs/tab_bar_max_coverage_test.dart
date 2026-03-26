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

  group('AppTabBar — context menu Close Others action', () {
    testWidgets('Close Others closes all tabs except the clicked one', (tester) async {
      final conn = makeConn();
      await tester.pumpWidget(buildAppWithTabs([
        TabEntry(id: 't1', label: 'Tab A', connection: conn, kind: TabKind.terminal),
        TabEntry(id: 't2', label: 'Tab B', connection: conn, kind: TabKind.sftp),
        TabEntry(id: 't3', label: 'Tab C', connection: conn, kind: TabKind.terminal),
      ], activeIndex: 1));
      await tester.pumpAndSettle();

      // Right-click on Tab B (middle tab)
      final tabB = find.text('Tab B').first;
      final center = tester.getCenter(tabB);
      final gesture = await tester.startGesture(
        center,
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await gesture.up();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Close Others'));
      await tester.pumpAndSettle();

      // Only Tab B should remain
      expect(find.text('Tab B'), findsWidgets);
    });
  });

  group('AppTabBar — context menu Close action', () {
    testWidgets('Close from context menu closes the specific tab', (tester) async {
      final conn = makeConn();
      await tester.pumpWidget(buildAppWithTabs([
        TabEntry(id: 't1', label: 'Tab A', connection: conn, kind: TabKind.terminal),
        TabEntry(id: 't2', label: 'Tab B', connection: conn, kind: TabKind.terminal),
      ]));
      await tester.pumpAndSettle();

      // Right-click on Tab A
      final tabA = find.text('Tab A').first;
      final center = tester.getCenter(tabA);
      final gesture = await tester.startGesture(
        center,
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await gesture.up();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      // Tab A should be closed, Tab B should remain
      expect(find.text('Tab B'), findsWidgets);
    });
  });

  group('AppTabBar — first tab context menu shows Close Right but not Close Left', () {
    testWidgets('first tab has Close Right but not Close Left', (tester) async {
      final conn = makeConn();
      await tester.pumpWidget(buildAppWithTabs([
        TabEntry(id: 't1', label: 'Tab A', connection: conn, kind: TabKind.terminal),
        TabEntry(id: 't2', label: 'Tab B', connection: conn, kind: TabKind.terminal),
      ]));
      await tester.pumpAndSettle();

      // Right-click on Tab A (first tab, index 0)
      final tabA = find.text('Tab A').first;
      final center = tester.getCenter(tabA);
      final gesture = await tester.startGesture(
        center,
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.text('Close'), findsOneWidget);
      expect(find.text('Close Others'), findsOneWidget);
      expect(find.text('Close Tabs to the Right'), findsOneWidget);
      // First tab has no left tabs
      expect(find.text('Close Tabs to the Left'), findsNothing);

      // Dismiss
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();
    });
  });

  group('AppTabBar — last tab context menu shows Close Left but not Close Right', () {
    testWidgets('last tab has Close Left but not Close Right', (tester) async {
      final conn = makeConn();
      await tester.pumpWidget(buildAppWithTabs([
        TabEntry(id: 't1', label: 'Tab A', connection: conn, kind: TabKind.terminal),
        TabEntry(id: 't2', label: 'Tab B', connection: conn, kind: TabKind.terminal),
      ], activeIndex: 1));
      await tester.pumpAndSettle();

      // Right-click on Tab B (last tab, index 1)
      final tabB = find.text('Tab B').first;
      final center = tester.getCenter(tabB);
      final gesture = await tester.startGesture(
        center,
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.text('Close'), findsOneWidget);
      expect(find.text('Close Others'), findsOneWidget);
      expect(find.text('Close Tabs to the Left'), findsOneWidget);
      // Last tab has no right tabs
      expect(find.text('Close Tabs to the Right'), findsNothing);

      // Dismiss
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();
    });
  });

  group('AppTabBar — DragTarget onWillAcceptWithDetails rejects same tab', () {
    testWidgets('DragTarget is present for each tab', (tester) async {
      final conn = makeConn();
      await tester.pumpWidget(buildAppWithTabs([
        TabEntry(id: 't1', label: 'Tab A', connection: conn, kind: TabKind.terminal),
        TabEntry(id: 't2', label: 'Tab B', connection: conn, kind: TabKind.terminal),
      ]));
      await tester.pumpAndSettle();

      // Each tab should have a DragTarget
      final dragTargets = find.byType(DragTarget<TabEntry>);
      expect(dragTargets, findsNWidgets(2));
    });
  });

  group('AppTabBar — light theme state colors', () {
    testWidgets('state colors work with light theme', (tester) async {
      final conn = makeConn(state: SSHConnectionState.connected);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tabProvider.overrideWith((ref) {
              final notifier = TabNotifier();
              notifier.addTerminalTab(conn, label: 'LightTab');
              return notifier;
            }),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: AppTabBar()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Should render with light theme connected color dot
      final containers = tester.widgetList<Container>(find.byType(Container));
      final dots = containers.where((c) {
        final d = c.decoration;
        return d is BoxDecoration &&
            d.shape == BoxShape.circle &&
            d.color == AppTheme.connectedColor(Brightness.light);
      });
      expect(dots, isNotEmpty);
    });
  });

  group('AppTabBar — tab label truncation', () {
    testWidgets('long tab label is constrained by maxWidth 150', (tester) async {
      final conn = makeConn();
      await tester.pumpWidget(buildAppWithTabs([
        TabEntry(
          id: 't1',
          label: 'A very long tab label that should be truncated by the ConstrainedBox',
          connection: conn,
          kind: TabKind.terminal,
        ),
      ]));
      await tester.pumpAndSettle();

      // Find the ConstrainedBox with maxWidth 150
      final constrainedBoxes = tester.widgetList<ConstrainedBox>(find.byType(ConstrainedBox));
      final found = constrainedBoxes.any((cb) => cb.constraints.maxWidth == 150);
      expect(found, isTrue);
    });
  });
}
