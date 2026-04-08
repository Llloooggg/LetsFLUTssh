import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/connection/connection.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/features/tabs/tab_model.dart';
import 'package:letsflutssh/features/workspace/panel_tab_bar.dart';
import 'package:letsflutssh/theme/app_theme.dart';
import '''package:letsflutssh/l10n/app_localizations.dart''';

void main() {
  TabEntry makeTab({
    required String id,
    String label = 'Server',
    TabKind kind = TabKind.terminal,
    SSHConnectionState connState = SSHConnectionState.connected,
  }) {
    return TabEntry(
      id: id,
      label: label,
      connection: Connection(
        id: 'conn-$id',
        label: label,
        sshConfig: const SSHConfig(
          server: ServerAddress(host: '10.0.0.1', user: 'root'),
        ),
        state: connState,
      ),
      kind: kind,
    );
  }

  Widget buildBar({
    List<TabEntry>? tabs,
    int activeIndex = 0,
    bool isFocusedPanel = true,
    ValueChanged<int>? onSelect,
    ValueChanged<String>? onClose,
    void Function(int, int)? onReorder,
    void Function(TabDragData data, int index)? onAcceptCrossPanel,
    void Function(String tabId, int index, Offset position)? onContextMenu,
    double width = 600,
  }) {
    final tabList = tabs ?? [makeTab(id: 'tab-0')];
    return MaterialApp(
      localizationsDelegates: S.localizationsDelegates,
      supportedLocales: S.supportedLocales,
      theme: AppTheme.dark(),
      home: Scaffold(
        body: SizedBox(
          width: width,
          height: AppTheme.barHeightSm,
          child: PanelTabBar(
            panelId: 'panel-0',
            tabs: tabList,
            activeIndex: activeIndex,
            isFocusedPanel: isFocusedPanel,
            onSelect: onSelect ?? (_) {},
            onClose: onClose ?? (_) {},
            onReorder: onReorder ?? (_, _) {},
            onAcceptCrossPanel: onAcceptCrossPanel ?? (_, _) {},
            onContextMenu: onContextMenu ?? (_, _, _) {},
          ),
        ),
      ),
    );
  }

  group('PanelTabBar — rendering', () {
    testWidgets('renders a single tab with label', (tester) async {
      await tester.pumpWidget(
        buildBar(
          tabs: [makeTab(id: 't1', label: 'MyServer')],
        ),
      );

      expect(find.text('MyServer'), findsOneWidget);
    });

    testWidgets('renders multiple tabs', (tester) async {
      final tabs = [
        makeTab(id: 't1', label: 'Server A'),
        makeTab(id: 't2', label: 'Server B'),
        makeTab(id: 't3', label: 'Server C'),
      ];
      await tester.pumpWidget(buildBar(tabs: tabs));

      expect(find.text('Server A'), findsOneWidget);
      expect(find.text('Server B'), findsOneWidget);
      expect(find.text('Server C'), findsOneWidget);
    });

    testWidgets('renders terminal icon for terminal tab', (tester) async {
      await tester.pumpWidget(
        buildBar(
          tabs: [makeTab(id: 't1', kind: TabKind.terminal)],
        ),
      );

      expect(find.byIcon(Icons.terminal), findsOneWidget);
    });

    testWidgets('renders folder icon for sftp tab', (tester) async {
      await tester.pumpWidget(
        buildBar(
          tabs: [makeTab(id: 't1', kind: TabKind.sftp)],
        ),
      );

      expect(find.byIcon(Icons.folder), findsOneWidget);
    });

    testWidgets('active tab has accent top border', (tester) async {
      await tester.pumpWidget(
        buildBar(
          tabs: [
            makeTab(id: 't1', label: 'Active'),
            makeTab(id: 't2', label: 'Inactive'),
          ],
          activeIndex: 0,
        ),
      );

      // Active tab has a 2px accent colored box at the top.
      final coloredBoxes = tester.widgetList<ColoredBox>(
        find.byType(ColoredBox),
      );
      final accentBoxes = coloredBoxes
          .where((b) => b.color == AppTheme.accent)
          .toList();
      expect(accentBoxes, isNotEmpty);
    });

    testWidgets('empty tabs list renders without error', (tester) async {
      await tester.pumpWidget(buildBar(tabs: []));
      // No tabs, no error.
      expect(tester.takeException(), isNull);
    });
  });

  group('PanelTabBar — callbacks', () {
    testWidgets('tapping a tab calls onSelect with correct index', (
      tester,
    ) async {
      int? selectedIndex;
      await tester.pumpWidget(
        buildBar(
          tabs: [
            makeTab(id: 't1', label: 'First'),
            makeTab(id: 't2', label: 'Second'),
          ],
          activeIndex: 0,
          onSelect: (i) => selectedIndex = i,
        ),
      );

      await tester.tap(find.text('Second'));
      expect(selectedIndex, 1);
    });

    testWidgets('close button calls onClose with tab id', (tester) async {
      String? closedTabId;
      final tabs = [makeTab(id: 'tab-close-me', label: 'ToClose')];
      await tester.pumpWidget(
        buildBar(tabs: tabs, activeIndex: 0, onClose: (id) => closedTabId = id),
      );

      // Hover over the tab to reveal the close button.
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      await gesture.moveTo(tester.getCenter(find.text('ToClose')));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.close));
      expect(closedTabId, 'tab-close-me');
    });

    testWidgets('right-click calls onContextMenu', (tester) async {
      String? menuTabId;
      int? menuIndex;
      await tester.pumpWidget(
        buildBar(
          tabs: [makeTab(id: 'ctx-tab', label: 'RightClick')],
          activeIndex: 0,
          onContextMenu: (tabId, index, _) {
            menuTabId = tabId;
            menuIndex = index;
          },
        ),
      );

      // Secondary tap (right-click) on the tab label.
      await tester.tap(find.text('RightClick'), buttons: kSecondaryButton);
      expect(menuTabId, 'ctx-tab');
      expect(menuIndex, 0);
    });
  });

  group('PanelTabBar — connection state dot', () {
    testWidgets('connected tab shows green dot', (tester) async {
      await tester.pumpWidget(
        buildBar(
          tabs: [makeTab(id: 't1', connState: SSHConnectionState.connected)],
        ),
      );

      // The dot is a 5x5 Container with BoxDecoration circle.
      final dotContainers = tester.widgetList<Container>(
        find.byType(Container),
      );
      final dots = dotContainers.where((c) {
        final dec = c.decoration;
        if (dec is BoxDecoration && dec.shape == BoxShape.circle) return true;
        return false;
      }).toList();
      expect(dots, isNotEmpty);
      final dotDec = dots.first.decoration as BoxDecoration;
      expect(dotDec.color, AppTheme.connected);
    });

    testWidgets('disconnected tab shows faint dot', (tester) async {
      await tester.pumpWidget(
        buildBar(
          tabs: [makeTab(id: 't1', connState: SSHConnectionState.disconnected)],
        ),
      );

      final dotContainers = tester.widgetList<Container>(
        find.byType(Container),
      );
      final dots = dotContainers.where((c) {
        final dec = c.decoration;
        if (dec is BoxDecoration && dec.shape == BoxShape.circle) return true;
        return false;
      }).toList();
      expect(dots, isNotEmpty);
      final dotDec = dots.first.decoration as BoxDecoration;
      expect(dotDec.color, AppTheme.fgFaint);
    });

    testWidgets('connecting tab shows connecting color dot', (tester) async {
      await tester.pumpWidget(
        buildBar(
          tabs: [makeTab(id: 't1', connState: SSHConnectionState.connecting)],
        ),
      );

      final dotContainers = tester.widgetList<Container>(
        find.byType(Container),
      );
      final dots = dotContainers.where((c) {
        final dec = c.decoration;
        if (dec is BoxDecoration && dec.shape == BoxShape.circle) return true;
        return false;
      }).toList();
      expect(dots, isNotEmpty);
      final dotDec = dots.first.decoration as BoxDecoration;
      expect(dotDec.color, AppTheme.connecting);
    });
  });

  group('PanelTabBar — tab width clamping', () {
    testWidgets('tabs clamp to max 180px width', (tester) async {
      // Single tab at 600px wide container → natural = 600 → clamped to 180.
      await tester.pumpWidget(buildBar(tabs: [makeTab(id: 't1')], width: 600));

      // The tab item SizedBox should be clamped to 180.
      final tabSizedBoxes = tester.widgetList<SizedBox>(find.byType(SizedBox));
      final tabWidth = tabSizedBoxes.where((s) => s.width == 180.0).toList();
      expect(tabWidth, isNotEmpty);
    });

    testWidgets('many tabs shrink to min 80px width', (tester) async {
      // 10 tabs at 600px → natural = 60 → clamped to 80.
      final tabs = List.generate(
        10,
        (i) => makeTab(id: 'tab-$i', label: 'S$i'),
      );
      await tester.pumpWidget(buildBar(tabs: tabs, width: 600));

      final tabSizedBoxes = tester.widgetList<SizedBox>(find.byType(SizedBox));
      final minWidthBoxes = tabSizedBoxes
          .where((s) => s.width == 80.0)
          .toList();
      expect(minWidthBoxes.length, 10);
    });
  });

  group('PanelTabBar — hover behavior', () {
    testWidgets('close button hidden on inactive non-hovered tab', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildBar(
          tabs: [
            makeTab(id: 't1', label: 'First'),
            makeTab(id: 't2', label: 'Second'),
          ],
          activeIndex: 0,
        ),
      );

      // Without hovering, no close buttons are shown on any tab.
      expect(find.byIcon(Icons.close), findsNothing);

      // Hover over active tab — close button appears only for it.
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      await gesture.moveTo(tester.getCenter(find.text('First')));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.close), findsOneWidget);
    });
  });

  group('PanelTabBar — tooltip', () {
    testWidgets('each tab has a tooltip with its label', (tester) async {
      await tester.pumpWidget(
        buildBar(
          tabs: [makeTab(id: 't1', label: 'MyServer')],
        ),
      );

      final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
      expect(tooltip.message, 'MyServer');
    });
  });

  group('TabDragData', () {
    test('stores tab and sourcePanelId', () {
      final tab = makeTab(id: 'drag-tab', label: 'Dragged');
      final data = TabDragData(tab: tab, sourcePanelId: 'panel-A');

      expect(data.tab.id, 'drag-tab');
      expect(data.sourcePanelId, 'panel-A');
    });
  });

  group('PanelTabBar — icon colors', () {
    testWidgets('active terminal tab icon is blue', (tester) async {
      await tester.pumpWidget(
        buildBar(
          tabs: [makeTab(id: 't1', kind: TabKind.terminal)],
          activeIndex: 0,
        ),
      );

      final icon = tester.widget<Icon>(find.byIcon(Icons.terminal));
      expect(icon.color, AppTheme.blue);
    });

    testWidgets('active sftp tab icon is yellow', (tester) async {
      await tester.pumpWidget(
        buildBar(
          tabs: [makeTab(id: 't1', kind: TabKind.sftp)],
          activeIndex: 0,
        ),
      );

      final icon = tester.widget<Icon>(find.byIcon(Icons.folder));
      expect(icon.color, AppTheme.yellow);
    });

    testWidgets('inactive tab icon is faint', (tester) async {
      await tester.pumpWidget(
        buildBar(
          tabs: [
            makeTab(id: 't1', label: 'Active'),
            makeTab(id: 't2', label: 'Inactive', kind: TabKind.terminal),
          ],
          activeIndex: 0,
        ),
      );

      // There are two terminal icons; the inactive one should be faint.
      final icons = tester.widgetList<Icon>(find.byIcon(Icons.terminal));
      final inactiveIcon = icons.last;
      expect(inactiveIcon.color, AppTheme.fgFaint);
    });
  });

  group('PanelTabBar — tab background', () {
    testWidgets('active tab background is bg2', (tester) async {
      await tester.pumpWidget(
        buildBar(
          tabs: [
            makeTab(id: 't1', label: 'Active'),
            makeTab(id: 't2', label: 'Inactive'),
          ],
          activeIndex: 0,
        ),
      );

      // Find containers with bg2 color (active tab) and bg1 (inactive).
      final containers = tester.widgetList<Container>(find.byType(Container));
      final bg2Containers = containers
          .where((c) => c.color == AppTheme.bg2)
          .toList();
      final bg1Containers = containers
          .where((c) => c.color == AppTheme.bg1)
          .toList();
      expect(bg2Containers, isNotEmpty, reason: 'Active tab uses bg2');
      expect(bg1Containers, isNotEmpty, reason: 'Inactive tab uses bg1');
    });
  });

  group('PanelTabBar — text styles', () {
    testWidgets('active tab text uses fg color', (tester) async {
      await tester.pumpWidget(
        buildBar(
          tabs: [
            makeTab(id: 't1', label: 'ActiveTab'),
            makeTab(id: 't2', label: 'InactiveTab'),
          ],
          activeIndex: 0,
        ),
      );

      final activeText = tester.widget<Text>(find.text('ActiveTab'));
      expect(activeText.style?.color, AppTheme.fg);
    });

    testWidgets('inactive tab text uses fgDim color', (tester) async {
      await tester.pumpWidget(
        buildBar(
          tabs: [
            makeTab(id: 't1', label: 'ActiveTab'),
            makeTab(id: 't2', label: 'InactiveTab'),
          ],
          activeIndex: 0,
        ),
      );

      final inactiveText = tester.widget<Text>(find.text('InactiveTab'));
      expect(inactiveText.style?.color, AppTheme.fgDim);
    });
  });

  group('PanelTabBar — scroll behavior', () {
    testWidgets('horizontal scroll on pointer signal scrolls tabs', (
      tester,
    ) async {
      // Many tabs to force scrollable content.
      final tabs = List.generate(
        20,
        (i) => makeTab(id: 'tab-$i', label: 'Server $i'),
      );
      await tester.pumpWidget(buildBar(tabs: tabs, width: 400));

      final scrollable = find.byType(SingleChildScrollView);
      expect(scrollable, findsOneWidget);

      // Dispatch a pointer scroll event over the tab bar area.
      final center = tester.getCenter(scrollable);
      final testPointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(testPointer.hover(center));
      await tester.sendEventToBinding(testPointer.scroll(const Offset(0, 50)));
      await tester.pump();

      // The scroll controller should have moved from 0.
      final scrollWidget = tester.widget<SingleChildScrollView>(scrollable);
      final controller = scrollWidget.controller;
      expect(controller, isNotNull);
      expect(controller!.offset, greaterThan(0));
    });

    testWidgets('scroll clamps to zero at start', (tester) async {
      final tabs = List.generate(
        20,
        (i) => makeTab(id: 'tab-$i', label: 'Server $i'),
      );
      await tester.pumpWidget(buildBar(tabs: tabs, width: 400));

      final scrollable = find.byType(SingleChildScrollView);
      final center = tester.getCenter(scrollable);
      final testPointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(testPointer.hover(center));
      // Scroll up (negative), should clamp to 0.
      await tester.sendEventToBinding(
        testPointer.scroll(const Offset(0, -100)),
      );
      await tester.pump();

      final scrollWidget = tester.widget<SingleChildScrollView>(scrollable);
      expect(scrollWidget.controller!.offset, 0);
    });
  });

  group('PanelTabBar — trailing drop zone', () {
    testWidgets('trailing drop zone renders after all tabs', (tester) async {
      await tester.pumpWidget(
        buildBar(
          tabs: [makeTab(id: 't1', label: 'OnlyTab')],
          width: 600,
        ),
      );

      // DragTarget widgets: one for the tab + one for the trailing zone.
      final dragTargets = find.byType(DragTarget<TabDragData>);
      expect(dragTargets, findsNWidgets(2));
    });
  });

  group('PanelTabBar — selecting non-active tab', () {
    testWidgets('selecting second tab in multi-tab bar', (tester) async {
      int? selectedIndex;
      final tabs = [
        makeTab(id: 't1', label: 'First'),
        makeTab(id: 't2', label: 'Second'),
        makeTab(id: 't3', label: 'Third'),
      ];
      await tester.pumpWidget(
        buildBar(
          tabs: tabs,
          activeIndex: 0,
          onSelect: (i) => selectedIndex = i,
        ),
      );

      await tester.tap(find.text('Third'));
      expect(selectedIndex, 2);
    });
  });

  group('PanelTabBar — close on different tabs', () {
    testWidgets('close button calls onClose for hovered non-active tab', (
      tester,
    ) async {
      String? closedId;
      final tabs = [
        makeTab(id: 't1', label: 'First'),
        makeTab(id: 't2', label: 'Second'),
      ];
      await tester.pumpWidget(
        buildBar(tabs: tabs, activeIndex: 0, onClose: (id) => closedId = id),
      );

      // Hover over the non-active tab to reveal close button.
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      await gesture.moveTo(tester.getCenter(find.text('Second')));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.close));
      expect(closedId, 't2');
    });
  });

  group('PanelTabBar — right-click context menu on specific tab', () {
    testWidgets('right-click on second tab returns correct index', (
      tester,
    ) async {
      String? menuTabId;
      int? menuIndex;
      final tabs = [
        makeTab(id: 't1', label: 'First'),
        makeTab(id: 't2', label: 'Second'),
        makeTab(id: 't3', label: 'Third'),
      ];
      await tester.pumpWidget(
        buildBar(
          tabs: tabs,
          activeIndex: 0,
          onContextMenu: (tabId, index, _) {
            menuTabId = tabId;
            menuIndex = index;
          },
        ),
      );

      await tester.tap(find.text('Third'), buttons: kSecondaryButton);
      expect(menuTabId, 't3');
      expect(menuIndex, 2);
    });
  });

  group('PanelTabBar — active tab has no accent bar for inactive', () {
    testWidgets('inactive tab does not have accent colored box', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildBar(
          tabs: [
            makeTab(id: 't1', label: 'Active'),
            makeTab(id: 't2', label: 'Inactive'),
          ],
          activeIndex: 0,
        ),
      );

      // Only one accent top bar should exist (for the active tab).
      final coloredBoxes = tester.widgetList<ColoredBox>(
        find.byType(ColoredBox),
      );
      final accentBoxes = coloredBoxes
          .where((b) => b.color == AppTheme.accent)
          .toList();
      expect(accentBoxes.length, 1);
    });
  });

  group('PanelTabBar — unfocused panel', () {
    testWidgets('renders correctly when isFocusedPanel is false', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildBar(
          tabs: [makeTab(id: 't1', label: 'Unfocused')],
          isFocusedPanel: false,
        ),
      );

      expect(find.text('Unfocused'), findsOneWidget);
    });
  });

  group('PanelTabBar — multiple tooltips', () {
    testWidgets('each tab in multi-tab bar has correct tooltip', (
      tester,
    ) async {
      final tabs = [
        makeTab(id: 't1', label: 'Alpha'),
        makeTab(id: 't2', label: 'Beta'),
      ];
      await tester.pumpWidget(buildBar(tabs: tabs));

      final tooltips = tester.widgetList<Tooltip>(find.byType(Tooltip));
      final messages = tooltips.map((t) => t.message).toList();
      expect(messages, contains('Alpha'));
      expect(messages, contains('Beta'));
    });
  });

  group('PanelTabBar — tab natural width between min and max', () {
    testWidgets('tabs use natural width when between 80 and 180', (
      tester,
    ) async {
      // 3 tabs at 360px → natural = 120 → between 80 and 180.
      final tabs = [
        makeTab(id: 't1', label: 'A'),
        makeTab(id: 't2', label: 'B'),
        makeTab(id: 't3', label: 'C'),
      ];
      await tester.pumpWidget(buildBar(tabs: tabs, width: 360));

      final tabSizedBoxes = tester.widgetList<SizedBox>(find.byType(SizedBox));
      final naturalWidthBoxes = tabSizedBoxes
          .where((s) => s.width == 120.0)
          .toList();
      expect(naturalWidthBoxes.length, 3);
    });
  });

  group('PanelTabBar — DragTarget keys', () {
    testWidgets('each tab drag target has a ValueKey', (tester) async {
      final tabs = [
        makeTab(id: 't1', label: 'A'),
        makeTab(id: 't2', label: 'B'),
      ];
      await tester.pumpWidget(buildBar(tabs: tabs));

      expect(find.byKey(const ValueKey('drop_t1')), findsOneWidget);
      expect(find.byKey(const ValueKey('drop_t2')), findsOneWidget);
    });
  });
}
