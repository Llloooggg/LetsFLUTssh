import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/features/tools/tools_dialog.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/theme/app_theme.dart';
import 'package:letsflutssh/utils/platform.dart' as plat;

void main() {
  setUp(() {
    plat.debugMobilePlatformOverride = false;
    plat.debugDesktopPlatformOverride = true;
  });

  tearDown(() {
    plat.debugMobilePlatformOverride = null;
    plat.debugDesktopPlatformOverride = null;
  });

  /// Pin a realistic desktop viewport for every test in this file. The
  /// Tools dialog (and its embedded managers) are sized for real desktop
  /// windows; the default 800x600 test viewport is narrower than any
  /// real Tools invocation and triggers overflow in the managers'
  /// multi-column tables.
  void useDesktopViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Widget buildApp() {
    return ProviderScope(
      child: MaterialApp(
        localizationsDelegates: S.localizationsDelegates,
        supportedLocales: S.supportedLocales,
        theme: AppTheme.dark(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => ToolsDialog.show(context),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('renders sidebar with SSH Keys, Snippets, Tags', (tester) async {
    useDesktopViewport(tester);
    await tester.pumpWidget(buildApp());
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('SSH Keys'), findsOneWidget);
    expect(find.text('Snippets'), findsOneWidget);
    expect(find.text('Tags'), findsOneWidget);
  });

  testWidgets('header shows Tools title', (tester) async {
    useDesktopViewport(tester);
    await tester.pumpWidget(buildApp());
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Tools'), findsOneWidget);
  });

  testWidgets('SSH Keys panel shown by default', (tester) async {
    useDesktopViewport(tester);
    await tester.pumpWidget(buildApp());
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    // Key manager panel shows key-related content
    expect(find.text('No keys'), findsOneWidget);
  });

  testWidgets('tapping Snippets switches to snippet panel', (tester) async {
    useDesktopViewport(tester);
    await tester.pumpWidget(buildApp());
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Snippets'));
    await tester.pumpAndSettle();

    expect(find.text('No snippets'), findsOneWidget);
  });

  testWidgets('tapping Tags switches to tag panel', (tester) async {
    useDesktopViewport(tester);
    await tester.pumpWidget(buildApp());
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Tags'));
    await tester.pumpAndSettle();

    expect(find.text('No tags'), findsOneWidget);
  });

  testWidgets('close button dismisses dialog', (tester) async {
    useDesktopViewport(tester);
    await tester.pumpWidget(buildApp());
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Tools'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(find.text('Tools'), findsNothing);
  });

  testWidgets(
    'desktop dialog matches the settings-modal gutter (same 7.5% each side)',
    (tester) async {
      // Shared formula is owned by AppTheme.desktopModalInsetPadding.
      useDesktopViewport(tester);
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      final dialogRect = tester.getRect(
        find
            .descendant(
              of: find.byType(Dialog),
              matching: find.byType(Material),
            )
            .first,
      );
      // 7.5% of 1600 = 120 per side → modal width ≈ 1360.
      expect(
        dialogRect.width,
        inInclusiveRange(1350, 1370),
        reason:
            'Tools modal width must match Settings modal width on a 1600-wide viewport',
      );
      expect(
        dialogRect.left,
        inInclusiveRange(115, 125),
        reason: 'Tools left inset must match Settings left inset',
      );
    },
  );
}
