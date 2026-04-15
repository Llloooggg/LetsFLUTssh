import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '''package:letsflutssh/l10n/app_localizations.dart''';
import 'package:letsflutssh/theme/app_theme.dart';
import 'package:letsflutssh/widgets/app_icon_button.dart';
import 'package:letsflutssh/widgets/hover_region.dart';

void main() {
  Widget buildApp(Widget child) {
    return MaterialApp(
      localizationsDelegates: S.localizationsDelegates,
      supportedLocales: S.supportedLocales,
      theme: AppTheme.dark(),
      home: Scaffold(body: Center(child: child)),
    );
  }

  group('AppIconButton', () {
    testWidgets('renders icon', (tester) async {
      await tester.pumpWidget(
        buildApp(const AppIconButton(icon: Icons.settings)),
      );
      expect(find.byIcon(Icons.settings), findsOneWidget);
    });

    testWidgets('default sizes come from AppTheme (14 icon on desktop)', (
      tester,
    ) async {
      await tester.pumpWidget(buildApp(const AppIconButton(icon: Icons.close)));

      // Defaults now resolve at build time via AppTheme so the widget's
      // explicit size/boxSize stay null; inspect the rendered Icon for the
      // resolved value. Test runs on desktop host so expect the 14 px icon.
      final btn = tester.widget<AppIconButton>(find.byType(AppIconButton));
      expect(btn.size, isNull);
      expect(btn.boxSize, isNull);

      final icon = tester.widget<Icon>(find.byIcon(Icons.close));
      expect(icon.size, AppTheme.iconBtnIcon);
    });

    testWidgets('dense: true picks the dense AppTheme defaults', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildApp(const AppIconButton(icon: Icons.close, dense: true)),
      );

      final icon = tester.widget<Icon>(find.byIcon(Icons.close));
      expect(icon.size, AppTheme.iconBtnIconDense);
    });

    testWidgets('custom size and boxSize', (tester) async {
      await tester.pumpWidget(
        buildApp(const AppIconButton(icon: Icons.close, size: 18, boxSize: 32)),
      );

      final icon = tester.widget<Icon>(find.byIcon(Icons.close));
      expect(icon.size, 18);

      final btn = tester.widget<AppIconButton>(find.byType(AppIconButton));
      expect(btn.boxSize, 32);
    });

    testWidgets('onTap fires callback', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        buildApp(AppIconButton(icon: Icons.close, onTap: () => tapped = true)),
      );

      await tester.tap(find.byType(AppIconButton));
      expect(tapped, isTrue);
    });

    testWidgets('tooltip shows when provided', (tester) async {
      await tester.pumpWidget(
        buildApp(const AppIconButton(icon: Icons.close, tooltip: 'Close')),
      );
      expect(find.byType(Tooltip), findsOneWidget);
      final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
      expect(tooltip.message, 'Close');
    });

    testWidgets('no tooltip when not provided', (tester) async {
      await tester.pumpWidget(buildApp(const AppIconButton(icon: Icons.close)));
      expect(find.byType(Tooltip), findsNothing);
    });

    testWidgets('disabled state dims icon', (tester) async {
      await tester.pumpWidget(
        buildApp(
          const AppIconButton(icon: Icons.close), // onTap is null
        ),
      );

      final icon = tester.widget<Icon>(find.byIcon(Icons.close));
      // Disabled icon should have 30% alpha of fgDim
      expect(icon.color!.a, closeTo(0.3, 0.01));
    });

    testWidgets('enabled state uses normal icon color', (tester) async {
      await tester.pumpWidget(
        buildApp(AppIconButton(icon: Icons.close, onTap: () {})),
      );

      final icon = tester.widget<Icon>(find.byIcon(Icons.close));
      expect(icon.color, AppTheme.fgDim);
    });

    testWidgets('active state uses fg color', (tester) async {
      await tester.pumpWidget(
        buildApp(AppIconButton(icon: Icons.close, onTap: () {}, active: true)),
      );

      final icon = tester.widget<Icon>(find.byIcon(Icons.close));
      expect(icon.color, AppTheme.fg);
    });

    testWidgets('custom color overrides default', (tester) async {
      await tester.pumpWidget(
        buildApp(
          AppIconButton(icon: Icons.close, onTap: () {}, color: AppTheme.red),
        ),
      );

      final icon = tester.widget<Icon>(find.byIcon(Icons.close));
      expect(icon.color, AppTheme.red);
    });

    testWidgets('hover shows background', (tester) async {
      await tester.pumpWidget(
        buildApp(AppIconButton(icon: Icons.close, onTap: () {})),
      );

      // Before hover — transparent
      Container container() => tester.widget<Container>(
        find.descendant(
          of: find.byType(AppIconButton),
          matching: find.byType(Container),
        ),
      );
      expect(
        (container().decoration as BoxDecoration?)?.color,
        Colors.transparent,
      );

      // Hover
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(tester.getCenter(find.byType(AppIconButton)));
      await tester.pump();

      expect((container().decoration as BoxDecoration?)?.color, AppTheme.hover);
    });

    testWidgets('active state shows active background', (tester) async {
      await tester.pumpWidget(
        buildApp(AppIconButton(icon: Icons.close, onTap: () {}, active: true)),
      );

      final container = tester.widget<Container>(
        find.descendant(
          of: find.byType(AppIconButton),
          matching: find.byType(Container),
        ),
      );
      expect((container.decoration as BoxDecoration?)?.color, AppTheme.active);
    });

    testWidgets('custom hoverColor is used', (tester) async {
      final customHover = AppTheme.red.withValues(alpha: 0.2);
      await tester.pumpWidget(
        buildApp(
          AppIconButton(
            icon: Icons.close,
            onTap: () {},
            hoverColor: customHover,
          ),
        ),
      );

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(tester.getCenter(find.byType(AppIconButton)));
      await tester.pump();

      final container = tester.widget<Container>(
        find.descendant(
          of: find.byType(AppIconButton),
          matching: find.byType(Container),
        ),
      );
      expect((container.decoration as BoxDecoration?)?.color, customHover);
    });

    testWidgets('borderRadius is applied', (tester) async {
      final br = BorderRadius.circular(8);
      await tester.pumpWidget(
        buildApp(
          AppIconButton(icon: Icons.close, onTap: () {}, borderRadius: br),
        ),
      );

      final container = tester.widget<Container>(
        find.descendant(
          of: find.byType(AppIconButton),
          matching: find.byType(Container),
        ),
      );
      expect((container.decoration as BoxDecoration?)?.borderRadius, br);
    });

    testWidgets('uses HoverRegion internally', (tester) async {
      await tester.pumpWidget(buildApp(const AppIconButton(icon: Icons.close)));
      expect(
        find.descendant(
          of: find.byType(AppIconButton),
          matching: find.byType(HoverRegion),
        ),
        findsOneWidget,
      );
    });

    testWidgets('backgroundColor shows when not hovered or active', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildApp(
          AppIconButton(
            icon: Icons.settings,
            onTap: () {},
            backgroundColor: AppTheme.bg3,
          ),
        ),
      );

      final container = tester.widget<Container>(
        find.descendant(
          of: find.byType(AppIconButton),
          matching: find.byType(Container),
        ),
      );
      expect((container.decoration as BoxDecoration?)?.color, AppTheme.bg3);
    });

    testWidgets('hover overrides backgroundColor', (tester) async {
      await tester.pumpWidget(
        buildApp(
          AppIconButton(
            icon: Icons.settings,
            onTap: () {},
            backgroundColor: AppTheme.bg3,
          ),
        ),
      );

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(tester.getCenter(find.byType(AppIconButton)));
      await tester.pump();

      final container = tester.widget<Container>(
        find.descendant(
          of: find.byType(AppIconButton),
          matching: find.byType(Container),
        ),
      );
      expect((container.decoration as BoxDecoration?)?.color, AppTheme.hover);
    });

    testWidgets('active overrides backgroundColor', (tester) async {
      await tester.pumpWidget(
        buildApp(
          AppIconButton(
            icon: Icons.settings,
            onTap: () {},
            backgroundColor: AppTheme.bg3,
            active: true,
          ),
        ),
      );

      final container = tester.widget<Container>(
        find.descendant(
          of: find.byType(AppIconButton),
          matching: find.byType(Container),
        ),
      );
      expect((container.decoration as BoxDecoration?)?.color, AppTheme.active);
    });

    testWidgets('disabled button does not show hover bg', (tester) async {
      await tester.pumpWidget(
        buildApp(
          const AppIconButton(icon: Icons.close), // onTap is null = disabled
        ),
      );

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(tester.getCenter(find.byType(AppIconButton)));
      await tester.pump();

      final container = tester.widget<Container>(
        find.descendant(
          of: find.byType(AppIconButton),
          matching: find.byType(Container),
        ),
      );
      expect(
        (container.decoration as BoxDecoration?)?.color,
        Colors.transparent,
      );
    });
  });
}
