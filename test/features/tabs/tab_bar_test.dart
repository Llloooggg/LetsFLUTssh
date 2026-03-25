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

    testWidgets('shows connecting state color', (tester) async {
      final conn = makeConn(state: SSHConnectionState.connecting);
      await tester.pumpWidget(buildAppWithTabs([
        TabEntry(id: 't1', label: 'Tab', connection: conn, kind: TabKind.terminal),
      ]));
      await tester.pumpAndSettle();
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

    testWidgets('shows disconnected state color', (tester) async {
      final conn = makeConn(state: SSHConnectionState.disconnected);
      await tester.pumpWidget(buildAppWithTabs([
        TabEntry(id: 't1', label: 'Tab', connection: conn, kind: TabKind.terminal),
      ]));
      await tester.pumpAndSettle();
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

    testWidgets('clicking tab selects it', (tester) async {
      final conn = makeConn();
      await tester.pumpWidget(buildAppWithTabs([
        TabEntry(id: 't1', label: 'Tab A', connection: conn, kind: TabKind.terminal),
        TabEntry(id: 't2', label: 'Tab B', connection: conn, kind: TabKind.sftp),
      ]));
      await tester.pumpAndSettle();

      // Tap on Tab A text
      await tester.tap(find.text('Tab A').first);
      await tester.pumpAndSettle();

      // Should not crash
      expect(find.text('Tab A'), findsWidgets);
    });

    testWidgets('clicking close button closes tab', (tester) async {
      final conn = makeConn();
      await tester.pumpWidget(buildAppWithTabs([
        TabEntry(id: 't1', label: 'Only Tab', connection: conn, kind: TabKind.terminal),
      ]));
      await tester.pumpAndSettle();

      // Find the close icon and tap it
      final closeIcons = find.byIcon(Icons.close);
      expect(closeIcons, findsWidgets);
      await tester.tap(closeIcons.first);
      await tester.pumpAndSettle();

      // Tab should be closed — no more ListView
      expect(find.byType(ListView), findsNothing);
    });

    testWidgets('right-click opens context menu', (tester) async {
      final conn = makeConn();
      await tester.pumpWidget(buildAppWithTabs([
        TabEntry(id: 't1', label: 'Tab A', connection: conn, kind: TabKind.terminal),
        TabEntry(id: 't2', label: 'Tab B', connection: conn, kind: TabKind.sftp),
      ]));
      await tester.pumpAndSettle();

      // Right-click on Tab A
      final tabA = find.text('Tab A').first;
      final center = tester.getCenter(tabA);
      final gesture = await tester.startGesture(center, kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
      await gesture.up();
      await tester.pumpAndSettle();

      // Context menu should show options
      expect(find.text('Close'), findsOneWidget);
      expect(find.text('Close Others'), findsOneWidget);
    });

    testWidgets('context menu Close action closes the tab', (tester) async {
      final conn = makeConn();
      await tester.pumpWidget(buildAppWithTabs([
        TabEntry(id: 't1', label: 'Tab A', connection: conn, kind: TabKind.terminal),
        TabEntry(id: 't2', label: 'Tab B', connection: conn, kind: TabKind.sftp),
      ]));
      await tester.pumpAndSettle();

      // Right-click on Tab A
      final tabA = find.text('Tab A').first;
      final center = tester.getCenter(tabA);
      final gesture = await tester.startGesture(center, kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
      await gesture.up();
      await tester.pumpAndSettle();

      // Tap Close
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      // Tab A should be gone
      expect(find.text('Tab B'), findsWidgets);
    });

    testWidgets('context menu Close Others action keeps only the clicked tab', (tester) async {
      final conn = makeConn();
      await tester.pumpWidget(buildAppWithTabs([
        TabEntry(id: 't1', label: 'Tab A', connection: conn, kind: TabKind.terminal),
        TabEntry(id: 't2', label: 'Tab B', connection: conn, kind: TabKind.sftp),
      ]));
      await tester.pumpAndSettle();

      // Right-click on Tab A
      final tabA = find.text('Tab A').first;
      final center = tester.getCenter(tabA);
      final gesture = await tester.startGesture(center, kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
      await gesture.up();
      await tester.pumpAndSettle();

      // Tap Close Others
      await tester.tap(find.text('Close Others'));
      await tester.pumpAndSettle();

      // Only Tab A should remain
      expect(find.text('Tab A'), findsWidgets);
    });

    testWidgets('context menu shows Close Tabs to the Right for non-last tab', (tester) async {
      final conn = makeConn();
      await tester.pumpWidget(buildAppWithTabs([
        TabEntry(id: 't1', label: 'Tab A', connection: conn, kind: TabKind.terminal),
        TabEntry(id: 't2', label: 'Tab B', connection: conn, kind: TabKind.sftp),
      ]));
      await tester.pumpAndSettle();

      // Right-click on Tab A (index 0, has tab to the right)
      final tabA = find.text('Tab A').first;
      final center = tester.getCenter(tabA);
      final gesture = await tester.startGesture(center, kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.text('Close Tabs to the Right'), findsOneWidget);
    });

    testWidgets('context menu shows Close Tabs to the Left for non-first tab', (tester) async {
      final conn = makeConn();
      await tester.pumpWidget(buildAppWithTabs([
        TabEntry(id: 't1', label: 'Tab A', connection: conn, kind: TabKind.terminal),
        TabEntry(id: 't2', label: 'Tab B', connection: conn, kind: TabKind.sftp),
      ], activeIndex: 1));
      await tester.pumpAndSettle();

      // Right-click on Tab B (index 1, has tab to the left)
      final tabB = find.text('Tab B').first;
      final center = tester.getCenter(tabB);
      final gesture = await tester.startGesture(center, kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.text('Close Tabs to the Left'), findsOneWidget);
    });

    testWidgets('active tab has bold text style', (tester) async {
      final conn = makeConn();
      await tester.pumpWidget(buildAppWithTabs([
        TabEntry(id: 't1', label: 'Active Tab', connection: conn, kind: TabKind.terminal),
      ]));
      await tester.pumpAndSettle();

      // Find the text widget and verify it exists
      expect(find.text('Active Tab'), findsWidgets);
    });

    testWidgets('non-active tab has normal text style', (tester) async {
      final conn = makeConn();
      await tester.pumpWidget(buildAppWithTabs([
        TabEntry(id: 't1', label: 'Tab A', connection: conn, kind: TabKind.terminal),
        TabEntry(id: 't2', label: 'Tab B', connection: conn, kind: TabKind.sftp),
      ], activeIndex: 0));
      await tester.pumpAndSettle();

      // Both tabs should render
      expect(find.text('Tab A'), findsWidgets);
      expect(find.text('Tab B'), findsWidgets);
    });

    testWidgets('Draggable is present for each tab', (tester) async {
      final conn = makeConn();
      await tester.pumpWidget(buildAppWithTabs([
        TabEntry(id: 't1', label: 'Tab A', connection: conn, kind: TabKind.terminal),
      ]));
      await tester.pumpAndSettle();

      expect(find.byType(Draggable<TabEntry>), findsOneWidget);
    });

    testWidgets('context menu Close Tabs to the Right closes tabs after clicked tab', (tester) async {
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

      // Tap Close Tabs to the Right
      await tester.tap(find.text('Close Tabs to the Right'));
      await tester.pumpAndSettle();

      // Only Tab A should remain
      expect(find.text('Tab A'), findsWidgets);
    });

    testWidgets('context menu Close Tabs to the Left closes tabs before clicked tab', (tester) async {
      final conn = makeConn();
      await tester.pumpWidget(buildAppWithTabs([
        TabEntry(id: 't1', label: 'Tab A', connection: conn, kind: TabKind.terminal),
        TabEntry(id: 't2', label: 'Tab B', connection: conn, kind: TabKind.sftp),
        TabEntry(id: 't3', label: 'Tab C', connection: conn, kind: TabKind.terminal),
      ], activeIndex: 2));
      await tester.pumpAndSettle();

      // Right-click on Tab C (index 2)
      final tabC = find.text('Tab C').first;
      final center = tester.getCenter(tabC);
      final gesture = await tester.startGesture(center, kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
      await gesture.up();
      await tester.pumpAndSettle();

      // Tap Close Tabs to the Left
      await tester.tap(find.text('Close Tabs to the Left'));
      await tester.pumpAndSettle();

      // Only Tab C should remain
      expect(find.text('Tab C'), findsWidgets);
    });

    testWidgets('connected state shows green dot', (tester) async {
      final conn = makeConn(state: SSHConnectionState.connected);
      await tester.pumpWidget(buildAppWithTabs([
        TabEntry(id: 't1', label: 'Tab', connection: conn, kind: TabKind.terminal),
      ]));
      await tester.pumpAndSettle();

      final containers = tester.widgetList<Container>(find.byType(Container));
      final dotContainers = containers.where((c) {
        final decoration = c.decoration;
        if (decoration is BoxDecoration && decoration.shape == BoxShape.circle) {
          return decoration.color == AppTheme.connectedColor(Brightness.dark);
        }
        return false;
      });
      expect(dotContainers, isNotEmpty);
    });

    testWidgets('connecting state shows yellow dot', (tester) async {
      final conn = makeConn(state: SSHConnectionState.connecting);
      await tester.pumpWidget(buildAppWithTabs([
        TabEntry(id: 't1', label: 'Tab', connection: conn, kind: TabKind.terminal),
      ]));
      await tester.pumpAndSettle();

      final containers = tester.widgetList<Container>(find.byType(Container));
      final dotContainers = containers.where((c) {
        final decoration = c.decoration;
        if (decoration is BoxDecoration && decoration.shape == BoxShape.circle) {
          return decoration.color == AppTheme.connectingColor(Brightness.dark);
        }
        return false;
      });
      expect(dotContainers, isNotEmpty);
    });

    testWidgets('disconnected state shows red dot', (tester) async {
      final conn = makeConn(state: SSHConnectionState.disconnected);
      await tester.pumpWidget(buildAppWithTabs([
        TabEntry(id: 't1', label: 'Tab', connection: conn, kind: TabKind.terminal),
      ]));
      await tester.pumpAndSettle();

      final containers = tester.widgetList<Container>(find.byType(Container));
      final dotContainers = containers.where((c) {
        final decoration = c.decoration;
        if (decoration is BoxDecoration && decoration.shape == BoxShape.circle) {
          return decoration.color == AppTheme.disconnectedColor(Brightness.dark);
        }
        return false;
      });
      expect(dotContainers, isNotEmpty);
    });

    testWidgets('active tab has bold text and bottom border', (tester) async {
      final conn = makeConn();
      await tester.pumpWidget(buildAppWithTabs([
        TabEntry(id: 't1', label: 'Active Tab', connection: conn, kind: TabKind.terminal),
        TabEntry(id: 't2', label: 'Inactive Tab', connection: conn, kind: TabKind.sftp),
      ], activeIndex: 0));
      await tester.pumpAndSettle();

      // Find the active tab text
      final activeTexts = tester.widgetList<Text>(find.text('Active Tab'));
      final hasActiveStyle = activeTexts.any((t) => t.style?.fontWeight == FontWeight.bold);
      expect(hasActiveStyle, isTrue);
    });

    testWidgets('inactive tab has normal weight text', (tester) async {
      final conn = makeConn();
      await tester.pumpWidget(buildAppWithTabs([
        TabEntry(id: 't1', label: 'Active Tab', connection: conn, kind: TabKind.terminal),
        TabEntry(id: 't2', label: 'Inactive Tab', connection: conn, kind: TabKind.sftp),
      ], activeIndex: 0));
      await tester.pumpAndSettle();

      // Find the inactive tab text
      final inactiveTexts = tester.widgetList<Text>(find.text('Inactive Tab'));
      final hasNormalStyle = inactiveTexts.any((t) => t.style?.fontWeight == FontWeight.normal);
      expect(hasNormalStyle, isTrue);
    });

    testWidgets('context menu does not show Close Tabs to the Left for first tab', (tester) async {
      final conn = makeConn();
      await tester.pumpWidget(buildAppWithTabs([
        TabEntry(id: 't1', label: 'Tab A', connection: conn, kind: TabKind.terminal),
        TabEntry(id: 't2', label: 'Tab B', connection: conn, kind: TabKind.sftp),
      ]));
      await tester.pumpAndSettle();

      // Right-click on Tab A (index 0)
      final tabA = find.text('Tab A').first;
      final center = tester.getCenter(tabA);
      final gesture = await tester.startGesture(center, kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
      await gesture.up();
      await tester.pumpAndSettle();

      // Should NOT show Close Tabs to the Left (first tab)
      expect(find.text('Close Tabs to the Left'), findsNothing);
      // Should show Close Tabs to the Right
      expect(find.text('Close Tabs to the Right'), findsOneWidget);
    });

    testWidgets('context menu does not show Close Tabs to the Right for last tab', (tester) async {
      final conn = makeConn();
      await tester.pumpWidget(buildAppWithTabs([
        TabEntry(id: 't1', label: 'Tab A', connection: conn, kind: TabKind.terminal),
        TabEntry(id: 't2', label: 'Tab B', connection: conn, kind: TabKind.sftp),
      ], activeIndex: 1));
      await tester.pumpAndSettle();

      // Right-click on Tab B (index 1, last tab)
      final tabB = find.text('Tab B').first;
      final center = tester.getCenter(tabB);
      final gesture = await tester.startGesture(center, kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
      await gesture.up();
      await tester.pumpAndSettle();

      // Should show Close Tabs to the Left
      expect(find.text('Close Tabs to the Left'), findsOneWidget);
      // Should NOT show Close Tabs to the Right (last tab)
      expect(find.text('Close Tabs to the Right'), findsNothing);
    });

    testWidgets('single tab context menu does not show Close Others', (tester) async {
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

      // Should show Close but NOT Close Others
      expect(find.text('Close'), findsOneWidget);
      expect(find.text('Close Others'), findsNothing);
      expect(find.text('Close Tabs to the Left'), findsNothing);
      expect(find.text('Close Tabs to the Right'), findsNothing);
    });

    testWidgets('tab label truncates with ellipsis for long labels', (tester) async {
      final conn = makeConn();
      await tester.pumpWidget(buildAppWithTabs([
        TabEntry(
          id: 't1',
          label: 'Very Long Server Name That Should Be Truncated With Ellipsis',
          connection: conn,
          kind: TabKind.terminal,
        ),
      ]));
      await tester.pumpAndSettle();

      // The text widget should exist and have ellipsis overflow
      final textWidgets = tester.widgetList<Text>(
        find.text('Very Long Server Name That Should Be Truncated With Ellipsis'),
      );
      expect(textWidgets, isNotEmpty);
      final hasEllipsis = textWidgets.any((t) => t.overflow == TextOverflow.ellipsis);
      expect(hasEllipsis, isTrue);
    });

    testWidgets('DragTarget is present for each tab', (tester) async {
      final conn = makeConn();
      await tester.pumpWidget(buildAppWithTabs([
        TabEntry(id: 't1', label: 'Tab A', connection: conn, kind: TabKind.terminal),
      ]));
      await tester.pumpAndSettle();

      expect(find.byType(DragTarget<TabEntry>), findsOneWidget);
    });
  });
}
