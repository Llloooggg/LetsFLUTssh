import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '''package:letsflutssh/l10n/app_localizations.dart''';
import 'package:letsflutssh/theme/app_theme.dart';
import 'package:letsflutssh/widgets/app_shell.dart';

void main() {
  Widget buildApp(Widget child, {double width = 800, double height = 600}) {
    return MaterialApp(
      localizationsDelegates: S.localizationsDelegates,
      supportedLocales: S.supportedLocales,
      theme: AppTheme.dark(),
      home: SizedBox(width: width, height: height, child: child),
    );
  }

  AppShell buildShell({
    Widget? toolbar,
    double toolbarHeight = 34,
    Widget? sidebar,
    double initialSidebarWidth = 220,
    double minSidebarWidth = 140,
    double maxSidebarWidth = 400,
    bool sidebarOpen = true,
    bool useDrawer = false,
    double drawerWidth = 280,
    Widget? body,
    Widget? statusBar,
  }) {
    return AppShell(
      toolbar: toolbar ?? const Text('toolbar'),
      toolbarHeight: toolbarHeight,
      sidebar: sidebar,
      initialSidebarWidth: initialSidebarWidth,
      minSidebarWidth: minSidebarWidth,
      maxSidebarWidth: maxSidebarWidth,
      sidebarOpen: sidebarOpen,
      useDrawer: useDrawer,
      drawerWidth: drawerWidth,
      body: body ?? const Text('body'),
      statusBar: statusBar,
    );
  }

  group('AppShell', () {
    testWidgets('renders toolbar, body, and sidebar', (tester) async {
      await tester.pumpWidget(
        buildApp(
          buildShell(toolbar: const Text('my-toolbar'), sidebar: const Text('my-sidebar'), body: const Text('my-body')),
        ),
      );

      expect(find.text('my-toolbar'), findsOneWidget);
      expect(find.text('my-sidebar'), findsOneWidget);
      expect(find.text('my-body'), findsOneWidget);
    });

    testWidgets('toolbar has correct height and decoration', (tester) async {
      await tester.pumpWidget(buildApp(buildShell(toolbarHeight: 40)));

      final containers = tester.widgetList<Container>(find.byType(Container));
      final toolbar = containers.firstWhere(
        (c) => c.constraints?.maxHeight == 40 && c.constraints?.minHeight == 40,
        orElse: () => containers.firstWhere((c) {
          final box = c.decoration as BoxDecoration?;
          return box?.border != null &&
              box?.color != null &&
              (c.constraints?.maxHeight == 40 || tester.getSize(find.byWidget(c)).height == 40);
        }),
      );
      expect(toolbar, isNotNull);
    });

    testWidgets('hides sidebar when sidebarOpen is false', (tester) async {
      await tester.pumpWidget(buildApp(buildShell(sidebar: const Text('sidebar-content'), sidebarOpen: false)));

      expect(find.text('sidebar-content'), findsNothing);
    });

    testWidgets('shows sidebar when sidebarOpen is true', (tester) async {
      await tester.pumpWidget(buildApp(buildShell(sidebar: const Text('sidebar-content'), sidebarOpen: true)));

      expect(find.text('sidebar-content'), findsOneWidget);
    });

    testWidgets('renders status bar when provided', (tester) async {
      await tester.pumpWidget(buildApp(buildShell(statusBar: const Text('my-status'))));

      expect(find.text('my-status'), findsOneWidget);
    });

    testWidgets('no status bar when null', (tester) async {
      await tester.pumpWidget(buildApp(buildShell(statusBar: null)));
      // body is present, no status bar
      expect(find.text('body'), findsOneWidget);
    });

    testWidgets('no sidebar rendered when sidebar is null', (tester) async {
      await tester.pumpWidget(buildApp(buildShell(sidebar: null)));

      // No resize cursor present
      expect(
        find.byWidgetPredicate((w) => w is MouseRegion && w.cursor == SystemMouseCursors.resizeColumn),
        findsNothing,
      );
      expect(find.text('body'), findsOneWidget);
    });

    testWidgets('sidebar has initial width', (tester) async {
      await tester.pumpWidget(
        buildApp(buildShell(sidebar: const SizedBox.expand(key: Key('sb')), initialSidebarWidth: 200)),
      );

      final sbBox = tester.getSize(find.byKey(const Key('sb')));
      expect(sbBox.width, 200);
    });

    testWidgets('sidebar can be resized by dragging divider', (tester) async {
      await tester.pumpWidget(
        buildApp(
          buildShell(
            sidebar: const SizedBox.expand(key: Key('sb')),
            initialSidebarWidth: 200,
            minSidebarWidth: 100,
            maxSidebarWidth: 300,
          ),
        ),
      );

      // Find the resize divider (3px wide Container inside GestureDetector)
      final divider = find.byWidgetPredicate((w) => w is MouseRegion && w.cursor == SystemMouseCursors.resizeColumn);
      expect(divider, findsOneWidget);

      // Drag right by 50 px
      await tester.drag(divider, const Offset(50, 0));
      await tester.pumpAndSettle();

      final sbBox = tester.getSize(find.byKey(const Key('sb')));
      expect(sbBox.width, 250);
    });

    testWidgets('sidebar resize clamps to min', (tester) async {
      await tester.pumpWidget(
        buildApp(
          buildShell(
            sidebar: const SizedBox.expand(key: Key('sb')),
            initialSidebarWidth: 200,
            minSidebarWidth: 150,
            maxSidebarWidth: 300,
          ),
        ),
      );

      final divider = find.byWidgetPredicate((w) => w is MouseRegion && w.cursor == SystemMouseCursors.resizeColumn);

      // Drag left way past minimum
      await tester.drag(divider, const Offset(-200, 0));
      await tester.pumpAndSettle();

      final sbBox = tester.getSize(find.byKey(const Key('sb')));
      expect(sbBox.width, 150);
    });

    testWidgets('sidebar resize clamps to max', (tester) async {
      await tester.pumpWidget(
        buildApp(
          buildShell(
            sidebar: const SizedBox.expand(key: Key('sb')),
            initialSidebarWidth: 200,
            minSidebarWidth: 100,
            maxSidebarWidth: 250,
          ),
        ),
      );

      final divider = find.byWidgetPredicate((w) => w is MouseRegion && w.cursor == SystemMouseCursors.resizeColumn);

      // Drag right past maximum
      await tester.drag(divider, const Offset(200, 0));
      await tester.pumpAndSettle();

      final sbBox = tester.getSize(find.byKey(const Key('sb')));
      expect(sbBox.width, 250);
    });

    testWidgets('drawer mode renders Drawer instead of inline sidebar', (tester) async {
      await tester.pumpWidget(buildApp(buildShell(sidebar: const Text('drawer-sidebar'), useDrawer: true)));

      // Sidebar not visible inline
      expect(find.text('drawer-sidebar'), findsNothing);

      // Open the drawer
      final scaffoldState = tester.firstState<ScaffoldState>(find.byType(Scaffold));
      scaffoldState.openDrawer();
      await tester.pumpAndSettle();

      expect(find.text('drawer-sidebar'), findsOneWidget);
    });

    testWidgets('drawer mode ignores sidebarOpen flag', (tester) async {
      await tester.pumpWidget(
        buildApp(buildShell(sidebar: const Text('drawer-sidebar'), useDrawer: true, sidebarOpen: true)),
      );

      // Sidebar not visible inline even with sidebarOpen true
      expect(find.text('drawer-sidebar'), findsNothing);
    });

    testWidgets('exposes sidebarWidth via state', (tester) async {
      final key = GlobalKey<AppShellState>();
      await tester.pumpWidget(
        buildApp(
          AppShell(
            key: key,
            toolbar: const Text('t'),
            sidebar: const SizedBox.expand(),
            initialSidebarWidth: 180,
            body: const Text('b'),
          ),
        ),
      );

      expect(key.currentState!.sidebarWidth, 180);
    });
  });
}
