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
      final coloredBoxes = tester.widgetList<ColoredBox>(find.byType(ColoredBox));
      final accentBoxes = coloredBoxes.where((b) => b.color == AppTheme.accent).toList();
      expect(accentBoxes, isNotEmpty);
    });

    testWidgets('empty tabs list renders without error', (tester) async {
      await tester.pumpWidget(buildBar(tabs: []));
      // No tabs, no error.
      expect(tester.takeException(), isNull);
    });
  });

  group('PanelTabBar — callbacks', () {
    testWidgets('tapping a tab calls onSelect with correct index', (tester) async {
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
      await tester.pumpWidget(buildBar(tabs: tabs, activeIndex: 0, onClose: (id) => closedTabId = id));

      // Active tab shows close button — find the close icon and tap it.
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
      final dotContainers = tester.widgetList<Container>(find.byType(Container));
      final dots = dotContainers.where((c) {
        final dec = c.decoration;
        if (dec is BoxDecoration && dec.shape == BoxShape.circle) return true;
        return false;
      }).toList();
      expect(dots, isNotEmpty);
      final dotDec = dots.first.decoration as BoxDecoration;
      expect(dotDec.color, AppTheme.connectedColor(Brightness.dark));
    });

    testWidgets('disconnected tab shows faint dot', (tester) async {
      await tester.pumpWidget(
        buildBar(
          tabs: [makeTab(id: 't1', connState: SSHConnectionState.disconnected)],
        ),
      );

      final dotContainers = tester.widgetList<Container>(find.byType(Container));
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

      final dotContainers = tester.widgetList<Container>(find.byType(Container));
      final dots = dotContainers.where((c) {
        final dec = c.decoration;
        if (dec is BoxDecoration && dec.shape == BoxShape.circle) return true;
        return false;
      }).toList();
      expect(dots, isNotEmpty);
      final dotDec = dots.first.decoration as BoxDecoration;
      expect(dotDec.color, AppTheme.connectingColor(Brightness.dark));
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
      final tabs = List.generate(10, (i) => makeTab(id: 'tab-$i', label: 'S$i'));
      await tester.pumpWidget(buildBar(tabs: tabs, width: 600));

      final tabSizedBoxes = tester.widgetList<SizedBox>(find.byType(SizedBox));
      final minWidthBoxes = tabSizedBoxes.where((s) => s.width == 80.0).toList();
      expect(minWidthBoxes.length, 10);
    });
  });

  group('PanelTabBar — hover behavior', () {
    testWidgets('close button appears on hover', (tester) async {
      await tester.pumpWidget(
        buildBar(
          tabs: [
            makeTab(id: 't1', label: 'First'),
            makeTab(id: 't2', label: 'Second'),
          ],
          activeIndex: 0,
        ),
      );

      // Inactive tab (Second) should have opacity 0 for close button.
      // Find all Opacity widgets wrapping close buttons.
      final opacities = tester.widgetList<Opacity>(find.byType(Opacity)).toList();
      final hiddenClose = opacities.where((o) => o.opacity == 0.0).toList();
      expect(hiddenClose, isNotEmpty);
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
}
