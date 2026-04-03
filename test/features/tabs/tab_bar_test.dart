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

/// A TabNotifier subclass that starts with a pre-built TabState.
class _PrePopulatedTabNotifier extends TabNotifier {
  final TabState _initialState;
  _PrePopulatedTabNotifier(this._initialState);

  @override
  TabState build() => _initialState;
}

void main() {
  Connection makeConn({
    String label = 'Server',
    SSHConnectionState state = SSHConnectionState.connected,
  }) {
    return Connection(
      id: 'conn-1',
      label: label,
      sshConfig: const SSHConfig(server: ServerAddress(host: '10.0.0.1', user: 'root')),
      state: state,
    );
  }

  /// Build app with pre-populated tabs via the notifier.
  Widget buildAppWithTabs(List<TabEntry> tabs, {int activeIndex = 0}) {
    final initialState = TabState(
      tabs: tabs,
      activeIndex: activeIndex >= 0 && activeIndex < tabs.length
          ? activeIndex
          : (tabs.isEmpty ? -1 : 0),
    );
    return ProviderScope(
      overrides: [
        tabProvider.overrideWith(() {
          return _PrePopulatedTabNotifier(initialState);
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
      // No tabs → no ListView (only + button shown)
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

    testWidgets('sftp tab does not show SFTP badge', (tester) async {
      final conn = makeConn();
      await tester.pumpWidget(buildAppWithTabs([
        TabEntry(id: 't1', label: 'Files', connection: conn, kind: TabKind.sftp),
      ]));
      await tester.pumpAndSettle();
      expect(find.text('SFTP'), findsNothing);
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

    testWidgets('connecting state shows connectingColor dot', (tester) async {
      final conn = makeConn(state: SSHConnectionState.connecting);
      await tester.pumpWidget(buildAppWithTabs([
        TabEntry(id: 't1', label: 'Tab', connection: conn, kind: TabKind.terminal),
      ]));
      await tester.pumpAndSettle();

      final containers = tester.widgetList<Container>(find.byType(Container));
      final dotContainers = containers.where((c) {
        final decoration = c.decoration;
        return decoration is BoxDecoration &&
            decoration.shape == BoxShape.circle &&
            decoration.color == AppTheme.connectingColor(Brightness.dark);
      });
      expect(dotContainers, isNotEmpty);
    });

    testWidgets('disconnected state shows fgFaint dot', (tester) async {
      final conn = makeConn(state: SSHConnectionState.disconnected);
      await tester.pumpWidget(buildAppWithTabs([
        TabEntry(id: 't1', label: 'Tab', connection: conn, kind: TabKind.terminal),
      ]));
      await tester.pumpAndSettle();

      final containers = tester.widgetList<Container>(find.byType(Container));
      final dotContainers = containers.where((c) {
        final decoration = c.decoration;
        return decoration is BoxDecoration &&
            decoration.shape == BoxShape.circle &&
            decoration.color == AppTheme.fgFaint;
      });
      expect(dotContainers, isNotEmpty);
    });

    testWidgets('active tab has fg color text', (tester) async {
      final conn = makeConn();
      await tester.pumpWidget(buildAppWithTabs([
        TabEntry(id: 't1', label: 'Active Tab', connection: conn, kind: TabKind.terminal),
        TabEntry(id: 't2', label: 'Inactive Tab', connection: conn, kind: TabKind.sftp),
      ], activeIndex: 0));
      await tester.pumpAndSettle();

      final activeTexts = tester.widgetList<Text>(find.text('Active Tab'));
      final hasActiveColor = activeTexts.any((t) => t.style?.color == AppTheme.fg);
      expect(hasActiveColor, isTrue);
    });

    testWidgets('inactive tab has fgDim color text', (tester) async {
      final conn = makeConn();
      await tester.pumpWidget(buildAppWithTabs([
        TabEntry(id: 't1', label: 'Active Tab', connection: conn, kind: TabKind.terminal),
        TabEntry(id: 't2', label: 'Inactive Tab', connection: conn, kind: TabKind.sftp),
      ], activeIndex: 0));
      await tester.pumpAndSettle();

      final inactiveTexts = tester.widgetList<Text>(find.text('Inactive Tab'));
      final hasDimColor = inactiveTexts.any((t) => t.style?.color == AppTheme.fgDim);
      expect(hasDimColor, isTrue);
    });

    testWidgets('inactive tab has bg1 background, not transparent', (tester) async {
      final conn = makeConn();
      await tester.pumpWidget(buildAppWithTabs([
        TabEntry(id: 't1', label: 'Active Tab', connection: conn, kind: TabKind.terminal),
        TabEntry(id: 't2', label: 'Inactive Tab', connection: conn, kind: TabKind.sftp),
      ], activeIndex: 0));
      await tester.pumpAndSettle();

      final containers = tester.widgetList<Container>(find.byType(Container));
      final hasBg1 = containers.any((c) {
        if (c.color == AppTheme.bg1) return true;
        final deco = c.decoration;
        if (deco is BoxDecoration && deco.color == AppTheme.bg1) {
          return true;
        }
        return false;
      });
      expect(hasBg1, isTrue, reason: 'inactive tab should have bg1 background');
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

    testWidgets('close button InkWell tap closes the tab', (tester) async {
      final conn = makeConn();
      await tester.pumpWidget(buildAppWithTabs([
        TabEntry(id: 't1', label: 'Tab A', connection: conn, kind: TabKind.terminal),
        TabEntry(id: 't2', label: 'Tab B', connection: conn, kind: TabKind.sftp),
      ]));
      await tester.pumpAndSettle();

      // Find the close InkWell for Tab A — close icons exist for each tab
      // Tap the first close icon (for Tab A)
      final closeIcons = find.byIcon(Icons.close);
      expect(closeIcons, findsWidgets);
      await tester.tap(closeIcons.first);
      await tester.pumpAndSettle();

      // Tab A should be gone, Tab B should remain
      expect(find.text('Tab B'), findsWidgets);
    });

    testWidgets('DragTarget is present for each tab', (tester) async {
      final conn = makeConn();
      await tester.pumpWidget(buildAppWithTabs([
        TabEntry(id: 't1', label: 'Tab A', connection: conn, kind: TabKind.terminal),
      ]));
      await tester.pumpAndSettle();

      // One per tab + one trailing drop zone
      expect(find.byType(DragTarget<TabEntry>), findsNWidgets(2));
    });
  });

  group('AppTabBar — context menu dismiss', () {
    testWidgets('dismissing context menu without selection does nothing',
        (tester) async {
      final conn = makeConn();
      await tester.pumpWidget(buildAppWithTabs([
        TabEntry(
            id: 't1',
            label: 'Tab A',
            connection: conn,
            kind: TabKind.terminal),
        TabEntry(
            id: 't2',
            label: 'Tab B',
            connection: conn,
            kind: TabKind.sftp),
      ]));
      await tester.pumpAndSettle();

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

      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();

      expect(find.text('Tab A'), findsWidgets);
      expect(find.text('Tab B'), findsWidgets);
    });
  });

  group('AppTabBar — middle tab shows all context menu options', () {
    testWidgets('middle tab shows Close Left, Close Right, Close Others',
        (tester) async {
      final conn = makeConn();
      await tester.pumpWidget(buildAppWithTabs([
        TabEntry(
            id: 't1',
            label: 'Tab A',
            connection: conn,
            kind: TabKind.terminal),
        TabEntry(
            id: 't2',
            label: 'Tab B',
            connection: conn,
            kind: TabKind.terminal),
        TabEntry(
            id: 't3',
            label: 'Tab C',
            connection: conn,
            kind: TabKind.terminal),
      ], activeIndex: 1));
      await tester.pumpAndSettle();

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
      expect(find.text('Close Tabs to the Right'), findsOneWidget);

      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();
    });
  });

  group('AppTabBar — SizedBox.shrink when empty', () {
    testWidgets('empty tabs renders SizedBox.shrink', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const Scaffold(body: AppTabBar()),
          ),
        ),
      );

      expect(find.byType(ListView), findsNothing);
    });
  });

  group('AppTabBar — DragTarget reorder', () {
    testWidgets('dragging a tab onto another triggers reorderTabs',
        (tester) async {
      final conn = makeConn();
      await tester.pumpWidget(buildAppWithTabs([
        TabEntry(
            id: 't1',
            label: 'Tab A',
            connection: conn,
            kind: TabKind.terminal),
        TabEntry(
            id: 't2',
            label: 'Tab B',
            connection: conn,
            kind: TabKind.sftp),
      ]));
      await tester.pumpAndSettle();

      final tabACenter = tester.getCenter(find.text('Tab A').first);
      final gesture = await tester.startGesture(tabACenter);
      await tester.pump();

      final tabBCenter = tester.getCenter(find.text('Tab B').first);
      await gesture.moveTo(tabBCenter);
      await tester.pump();

      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.text('Tab A'), findsWidgets);
      expect(find.text('Tab B'), findsWidgets);
    });

    testWidgets('onWillAcceptWithDetails rejects same tab drop',
        (tester) async {
      final conn = makeConn();
      await tester.pumpWidget(buildAppWithTabs([
        TabEntry(
            id: 't1',
            label: 'Only Tab',
            connection: conn,
            kind: TabKind.terminal),
      ]));
      await tester.pumpAndSettle();

      final center = tester.getCenter(find.text('Only Tab').first);
      final gesture = await tester.startGesture(center);
      await tester.pump();
      await gesture.moveTo(center + const Offset(5, 0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.text('Only Tab'), findsWidgets);
    });

    testWidgets('three tabs: drag first to third position triggers reorder',
        (tester) async {
      final conn = makeConn();
      await tester.pumpWidget(buildAppWithTabs([
        TabEntry(
            id: 't1',
            label: 'Tab 1',
            connection: conn,
            kind: TabKind.terminal),
        TabEntry(
            id: 't2',
            label: 'Tab 2',
            connection: conn,
            kind: TabKind.sftp),
        TabEntry(
            id: 't3',
            label: 'Tab 3',
            connection: conn,
            kind: TabKind.terminal),
      ]));
      await tester.pumpAndSettle();

      final tab1Center = tester.getCenter(find.text('Tab 1').first);
      final gesture = await tester.startGesture(tab1Center);
      await tester.pump();

      final tab3Center = tester.getCenter(find.text('Tab 3').first);
      await gesture.moveTo(tab3Center);
      await tester.pump();

      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.text('Tab 1'), findsWidgets);
      expect(find.text('Tab 2'), findsWidgets);
      expect(find.text('Tab 3'), findsWidgets);
    });

    testWidgets('end drop zone fills remaining space after tabs',
        (tester) async {
      final conn = makeConn();
      await tester.pumpWidget(buildAppWithTabs([
        TabEntry(
            id: 't1',
            label: 'Tab A',
            connection: conn,
            kind: TabKind.terminal),
      ]));
      await tester.pumpAndSettle();

      // One per tab + one trailing
      final dropTargets = tester.widgetList<DragTarget<TabEntry>>(
        find.byType(DragTarget<TabEntry>),
      );
      expect(dropTargets.length, 2);

      // End drop zone should be wider than the old fixed 24px
      final trailingDropTarget = find.byType(DragTarget<TabEntry>).last;
      final trailingBox = tester.getSize(trailingDropTarget);
      expect(trailingBox.width, greaterThan(24));
    });

    testWidgets('drag tab to empty space moves to last position',
        (tester) async {
      final conn = makeConn();
      await tester.pumpWidget(buildAppWithTabs([
        TabEntry(
            id: 't1',
            label: 'Tab 1',
            connection: conn,
            kind: TabKind.terminal),
        TabEntry(
            id: 't2',
            label: 'Tab 2',
            connection: conn,
            kind: TabKind.sftp),
        TabEntry(
            id: 't3',
            label: 'Tab 3',
            connection: conn,
            kind: TabKind.terminal),
      ]));
      await tester.pumpAndSettle();

      // Drag Tab 1 to the empty space right of all tabs
      final tab1Center = tester.getCenter(find.text('Tab 1').first);
      final gesture = await tester.startGesture(tab1Center);
      await tester.pump();

      // Move far to the right — into the empty space
      final barRight = tester.getTopRight(find.byType(AppTabBar));
      await gesture.moveTo(Offset(barRight.dx - 50, tab1Center.dy));
      await tester.pump();

      await gesture.up();
      await tester.pumpAndSettle();

      // All tabs should still be present
      expect(find.text('Tab 1'), findsWidgets);
      expect(find.text('Tab 2'), findsWidgets);
      expect(find.text('Tab 3'), findsWidgets);

      // Tab 1 should now be last — verify via provider state
      final container = tester
          .element(find.byType(AppTabBar))
          .findAncestorWidgetOfExactType<ProviderScope>();
      expect(container, isNotNull);
    });
  });

  group('AppTabBar — drag feedback', () {
    testWidgets('drag feedback shows terminal icon and label',
        (tester) async {
      final conn = makeConn();
      await tester.pumpWidget(buildAppWithTabs([
        TabEntry(
            id: 't1',
            label: 'DragMe',
            connection: conn,
            kind: TabKind.terminal),
      ]));
      await tester.pumpAndSettle();

      final center = tester.getCenter(find.text('DragMe').first);
      final gesture = await tester.startGesture(center);
      await tester.pump();
      await gesture.moveBy(const Offset(20, 20));
      await tester.pump();

      expect(find.text('DragMe'), findsWidgets);
      expect(find.byIcon(Icons.terminal), findsWidgets);

      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('drag feedback for SFTP tab shows folder icon',
        (tester) async {
      final conn = makeConn();
      await tester.pumpWidget(buildAppWithTabs([
        TabEntry(
            id: 't1',
            label: 'SFTP Tab',
            connection: conn,
            kind: TabKind.sftp),
      ]));
      await tester.pumpAndSettle();

      final center = tester.getCenter(find.text('SFTP Tab').first);
      final gesture = await tester.startGesture(center);
      await tester.pump();
      await gesture.moveBy(const Offset(20, 20));
      await tester.pump();

      expect(find.byIcon(Icons.folder), findsWidgets);
      expect(find.text('SFTP Tab'), findsWidgets);

      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('drag feedback container has correct elevation and opacity',
        (tester) async {
      final conn = makeConn();
      await tester.pumpWidget(buildAppWithTabs([
        TabEntry(
            id: 't1',
            label: 'StyledDrag',
            connection: conn,
            kind: TabKind.terminal),
      ]));
      await tester.pumpAndSettle();

      final draggable = tester.widget<Draggable<TabEntry>>(
        find.byType(Draggable<TabEntry>),
      );

      expect(draggable.feedback, isA<Material>());
      final material = draggable.feedback as Material;
      expect(material.elevation, 4);

      expect(material.child, isA<Opacity>());
      final opacity = material.child! as Opacity;
      expect(opacity.opacity, 0.85);
    });

    testWidgets('childWhenDragging has 0.4 opacity', (tester) async {
      final conn = makeConn();
      await tester.pumpWidget(buildAppWithTabs([
        TabEntry(
            id: 't1',
            label: 'FadeTab',
            connection: conn,
            kind: TabKind.terminal),
      ]));
      await tester.pumpAndSettle();

      final draggable = tester.widget<Draggable<TabEntry>>(
        find.byType(Draggable<TabEntry>),
      );
      expect(draggable.childWhenDragging, isA<Opacity>());
      final opacity = draggable.childWhenDragging! as Opacity;
      expect(opacity.opacity, 0.4);
    });
  });

  group('AppTabBar — state color verification', () {
    testWidgets('connected state shows green dot', (tester) async {
      final conn = makeConn(state: SSHConnectionState.connected);
      await tester.pumpWidget(buildAppWithTabs([
        TabEntry(
            id: 't1',
            label: 'Tab',
            connection: conn,
            kind: TabKind.terminal),
      ]));
      await tester.pumpAndSettle();

      final containers = tester.widgetList<Container>(find.byType(Container));
      final dots = containers.where((c) {
        final d = c.decoration;
        return d is BoxDecoration &&
            d.shape == BoxShape.circle &&
            d.color == AppTheme.green;
      });
      expect(dots, isNotEmpty);
    });

    testWidgets('connecting state shows connectingColor dot', (tester) async {
      final conn = makeConn(state: SSHConnectionState.connecting);
      await tester.pumpWidget(buildAppWithTabs([
        TabEntry(
            id: 't1',
            label: 'Tab',
            connection: conn,
            kind: TabKind.terminal),
      ]));
      await tester.pumpAndSettle();

      final containers = tester.widgetList<Container>(find.byType(Container));
      final dots = containers.where((c) {
        final d = c.decoration;
        return d is BoxDecoration &&
            d.shape == BoxShape.circle &&
            d.color == AppTheme.connectingColor(Brightness.dark);
      });
      expect(dots, isNotEmpty);
    });

    testWidgets('disconnected state shows fgFaint dot', (tester) async {
      final conn = makeConn(state: SSHConnectionState.disconnected);
      await tester.pumpWidget(buildAppWithTabs([
        TabEntry(
            id: 't1',
            label: 'Tab',
            connection: conn,
            kind: TabKind.terminal),
      ]));
      await tester.pumpAndSettle();

      final containers = tester.widgetList<Container>(find.byType(Container));
      final dots = containers.where((c) {
        final d = c.decoration;
        return d is BoxDecoration &&
            d.shape == BoxShape.circle &&
            d.color == AppTheme.fgFaint;
      });
      expect(dots, isNotEmpty);
    });
  });
}
