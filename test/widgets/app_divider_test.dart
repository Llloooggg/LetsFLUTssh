import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/theme/app_theme.dart';
import 'package:letsflutssh/widgets/app_divider.dart';

void main() {
  group('AppDivider', () {
    testWidgets('default is full-width with height 1', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: AppDivider())),
      );

      final divider = tester.widget<Divider>(find.byType(Divider));
      expect(divider.height, 1);
      expect(divider.thickness, 1);
      expect(divider.indent, 0);
      expect(divider.endIndent, 0);
    });

    testWidgets('uses AppTheme.border color by default', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: AppDivider())),
      );

      final divider = tester.widget<Divider>(find.byType(Divider));
      expect(divider.color, AppTheme.border);
    });

    testWidgets('.indented() has 8px indent on each side', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: AppDivider.indented())),
      );

      final divider = tester.widget<Divider>(find.byType(Divider));
      expect(divider.indent, 8);
      expect(divider.endIndent, 8);
    });

    testWidgets('custom color overrides default', (tester) async {
      const custom = Color(0xFFFF0000);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: AppDivider(color: custom)),
        ),
      );

      final divider = tester.widget<Divider>(find.byType(Divider));
      expect(divider.color, custom);
    });

    testWidgets('custom indent and endIndent', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: AppDivider(indent: 16, endIndent: 4)),
        ),
      );

      final divider = tester.widget<Divider>(find.byType(Divider));
      expect(divider.indent, 16);
      expect(divider.endIndent, 4);
    });

    testWidgets('.indented() with custom color', (tester) async {
      const custom = Color(0xFF00FF00);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: AppDivider.indented(color: custom)),
        ),
      );

      final divider = tester.widget<Divider>(find.byType(Divider));
      expect(divider.indent, 8);
      expect(divider.endIndent, 8);
      expect(divider.color, custom);
    });
  });
}
