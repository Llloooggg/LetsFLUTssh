import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/theme/app_theme.dart';
import 'package:letsflutssh/widgets/mode_button.dart';

Widget _buildApp({required bool selected, VoidCallback? onTap}) {
  return MaterialApp(
    theme: AppTheme.dark(),
    home: Scaffold(
      body: Row(
        children: [
          ModeButton(
            label: 'Merge',
            icon: Icons.merge,
            selected: selected,
            onTap: onTap ?? () {},
          ),
        ],
      ),
    ),
  );
}

void main() {
  group('ModeButton', () {
    testWidgets('renders label and icon', (tester) async {
      await tester.pumpWidget(_buildApp(selected: false));
      expect(find.text('Merge'), findsOneWidget);
      expect(find.byIcon(Icons.merge), findsOneWidget);
    });

    testWidgets('selected state uses accent color', (tester) async {
      await tester.pumpWidget(_buildApp(selected: true));
      final container = tester.widget<Container>(find.byType(Container).first);
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.color, AppTheme.accent);
    });

    testWidgets('unselected state uses bg3 color', (tester) async {
      await tester.pumpWidget(_buildApp(selected: false));
      final container = tester.widget<Container>(find.byType(Container).first);
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.color, AppTheme.bg3);
    });

    testWidgets('onTap callback fires on tap', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        _buildApp(selected: false, onTap: () => tapped = true),
      );
      await tester.tap(find.text('Merge'));
      expect(tapped, isTrue);
    });

    testWidgets('selected text uses bold weight', (tester) async {
      await tester.pumpWidget(_buildApp(selected: true));
      final text = tester.widget<Text>(find.text('Merge'));
      expect(text.style?.fontWeight, FontWeight.w600);
    });

    testWidgets('unselected text uses normal weight', (tester) async {
      await tester.pumpWidget(_buildApp(selected: false));
      final text = tester.widget<Text>(find.text('Merge'));
      expect(text.style?.fontWeight, isNull);
    });

    testWidgets('selected icon uses onAccent color', (tester) async {
      await tester.pumpWidget(_buildApp(selected: true));
      final icon = tester.widget<Icon>(find.byIcon(Icons.merge));
      expect(icon.color, AppTheme.onAccent);
    });

    testWidgets('unselected icon uses fgDim color', (tester) async {
      await tester.pumpWidget(_buildApp(selected: false));
      final icon = tester.widget<Icon>(find.byIcon(Icons.merge));
      expect(icon.color, AppTheme.fgDim);
    });

    testWidgets('uses controlHeightLg for height', (tester) async {
      await tester.pumpWidget(_buildApp(selected: false));
      final size = tester.getSize(find.byType(Container).first);
      expect(size.height, AppTheme.controlHeightLg);
    });

    testWidgets('border color differs between selected/unselected', (
      tester,
    ) async {
      await tester.pumpWidget(_buildApp(selected: true));
      final selectedContainer = tester.widget<Container>(
        find.byType(Container).first,
      );
      final selectedDec = selectedContainer.decoration! as BoxDecoration;
      final selectedBorder = selectedDec.border! as Border;

      await tester.pumpWidget(_buildApp(selected: false));
      final unselectedContainer = tester.widget<Container>(
        find.byType(Container).first,
      );
      final unselectedDec = unselectedContainer.decoration! as BoxDecoration;
      final unselectedBorder = unselectedDec.border! as Border;

      expect(selectedBorder.top.color, isNot(unselectedBorder.top.color));
    });
  });
}
