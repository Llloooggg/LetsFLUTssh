import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/theme/app_theme.dart';
import 'package:letsflutssh/widgets/core/sidebar_nav_dialog.dart';
import 'package:letsflutssh/utils/platform.dart' as plat;

/// A panel that owns mutable state, so a rebuild-from-scratch (lost state)
/// is distinguishable from a kept-alive panel (state preserved).
class _CounterPanel extends StatefulWidget {
  const _CounterPanel(this.label);
  final String label;

  @override
  State<_CounterPanel> createState() => _CounterPanelState();
}

class _CounterPanelState extends State<_CounterPanel> {
  int _count = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text('${widget.label} body'),
        TextButton(
          onPressed: () => setState(() => _count++),
          child: Text('${widget.label} count=$_count'),
        ),
      ],
    );
  }
}

void main() {
  setUp(() {
    plat.debugMobilePlatformOverride = false;
    plat.debugDesktopPlatformOverride = true;
  });

  tearDown(() {
    plat.debugMobilePlatformOverride = null;
    plat.debugDesktopPlatformOverride = null;
  });

  void useDesktopViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Widget buildApp({
    Widget? sidebarFooter,
    Widget Function(Widget panel)? panelBuilder,
  }) {
    return MaterialApp(
      localizationsDelegates: S.localizationsDelegates,
      supportedLocales: S.supportedLocales,
      theme: AppTheme.dark(),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showDialog<void>(
                context: context,
                animationStyle: AnimationStyle.noAnimation,
                builder: (_) => SidebarNavDialog(
                  title: 'My Tools',
                  sidebarFooter: sidebarFooter,
                  panelBuilder: panelBuilder,
                  entries: [
                    SidebarNavEntry(
                      icon: Icons.vpn_key,
                      title: 'Alpha',
                      builder: () => const _CounterPanel('Alpha'),
                    ),
                    SidebarNavEntry(
                      icon: Icons.code,
                      title: 'Beta',
                      builder: () => const _CounterPanel('Beta'),
                    ),
                  ],
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> open(WidgetTester tester, {Widget? footer}) async {
    useDesktopViewport(tester);
    await tester.pumpWidget(buildApp(sidebarFooter: footer));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('renders the title and every nav-rail label', (tester) async {
    await open(tester);
    expect(find.text('My Tools'), findsOneWidget);
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
  });

  testWidgets('shows the first entry panel by default', (tester) async {
    await open(tester);
    expect(find.text('Alpha body'), findsOneWidget);
    expect(find.text('Beta body'), findsNothing);
  });

  testWidgets('unvisited panels are not built until first selected', (
    tester,
  ) async {
    await open(tester);
    // Beta has never been selected — its slot is an empty box, so the panel
    // widget (and its initState load) does not exist yet, even off-stage.
    expect(find.text('Beta body', skipOffstage: false), findsNothing);

    await tester.tap(find.text('Beta'));
    await tester.pumpAndSettle();
    expect(find.text('Beta body'), findsOneWidget);
  });

  testWidgets('a visited panel keeps its state across switches', (
    tester,
  ) async {
    await open(tester);

    // Mutate Alpha's state.
    await tester.tap(find.text('Alpha count=0'));
    await tester.pumpAndSettle();
    expect(find.text('Alpha count=1'), findsOneWidget);

    // Leave to Beta and come back.
    await tester.tap(find.text('Beta'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alpha'));
    await tester.pumpAndSettle();

    // A teardown-and-rebuild would reset the counter to 0; keep-alive means
    // it is still 1.
    expect(find.text('Alpha count=1'), findsOneWidget);
    expect(find.text('Alpha count=0'), findsNothing);
  });

  testWidgets('panelBuilder wraps each built panel', (tester) async {
    useDesktopViewport(tester);
    await tester.pumpWidget(
      buildApp(
        panelBuilder: (panel) => Column(
          children: [
            const Text('WRAPPER'),
            Expanded(child: panel),
          ],
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('WRAPPER'), findsOneWidget);
    expect(find.text('Alpha body'), findsOneWidget);
  });

  testWidgets('sidebar footer renders when provided', (tester) async {
    await open(tester, footer: const Text('FOOTER'));
    expect(find.text('FOOTER'), findsOneWidget);
  });

  testWidgets('close button dismisses the dialog', (tester) async {
    await open(tester);
    expect(find.text('My Tools'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.text('My Tools'), findsNothing);
  });
}
