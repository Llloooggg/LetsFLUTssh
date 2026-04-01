import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/theme/app_theme.dart';
import 'package:letsflutssh/widgets/app_bordered_box.dart';

void main() {
  group('AppBorderedBox', () {
    testWidgets('uses radiusSm and borderLight by default', (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: AppBorderedBox(child: SizedBox()),
        ),
      );

      final container = tester.widget<Container>(find.byType(Container));
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.borderRadius, AppTheme.radiusSm);
      expect(decoration.border, Border.all(color: AppTheme.borderLight));
    });

    testWidgets('applies custom borderColor', (tester) async {
      const color = Color(0xFFFF0000);
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: AppBorderedBox(borderColor: color, child: SizedBox()),
        ),
      );

      final container = tester.widget<Container>(find.byType(Container));
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.border, Border.all(color: color));
    });

    testWidgets('applies custom background color', (tester) async {
      const bg = Color(0xFF00FF00);
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: AppBorderedBox(color: bg, child: SizedBox()),
        ),
      );

      final container = tester.widget<Container>(find.byType(Container));
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.color, bg);
    });

    testWidgets('applies custom borderRadius', (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: AppBorderedBox(
            borderRadius: AppTheme.radiusLg,
            child: SizedBox(),
          ),
        ),
      );

      final container = tester.widget<Container>(find.byType(Container));
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.borderRadius, AppTheme.radiusLg);
    });

    testWidgets('applies custom borderWidth', (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: AppBorderedBox(borderWidth: 2, child: SizedBox()),
        ),
      );

      final container = tester.widget<Container>(find.byType(Container));
      final decoration = container.decoration! as BoxDecoration;
      final border = decoration.border! as Border;
      expect(border.top.width, 2);
    });

    testWidgets('passes height, width, padding, alignment, constraints',
        (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: AppBorderedBox(
            height: 28,
            width: 100,
            padding: EdgeInsets.all(8),
            alignment: Alignment.center,
            constraints: BoxConstraints(maxWidth: 200),
            child: SizedBox(),
          ),
        ),
      );

      final container = tester.widget<Container>(find.byType(Container));
      // Container merges width:100 with maxWidth:200 → effective maxWidth is 100
      expect(container.constraints?.maxWidth, 100);
      expect(container.alignment, Alignment.center);
      // Container merges height/width into constraints
      expect(container.constraints?.minHeight, 28);
      expect(container.constraints?.maxHeight, 28);
    });

    testWidgets('renders child', (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: AppBorderedBox(
            child: Text('hello'),
          ),
        ),
      );

      expect(find.text('hello'), findsOneWidget);
    });
  });
}
