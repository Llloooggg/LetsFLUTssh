/// Coverage for [AppDivider] — the project-wide 1px separator.
///
/// Trivial widget but pinning the height/thickness/indent contract
/// here means a refactor that drifts the visual spec is caught at
/// compile time, not at the next design review.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/widgets/app_divider.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('AppDivider', () {
    testWidgets('default constructor renders a 1px Divider', (tester) async {
      await tester.pumpWidget(wrap(const AppDivider()));
      final divider = tester.widget<Divider>(find.byType(Divider));
      expect(divider.height, 1);
      expect(divider.thickness, 1);
      expect(divider.indent, 0);
      expect(divider.endIndent, 0);
    });

    testWidgets('explicit indent + endIndent are forwarded', (tester) async {
      await tester.pumpWidget(wrap(const AppDivider(indent: 12, endIndent: 4)));
      final divider = tester.widget<Divider>(find.byType(Divider));
      expect(divider.indent, 12);
      expect(divider.endIndent, 4);
    });

    testWidgets('AppDivider.indented uses 8 / 8', (tester) async {
      await tester.pumpWidget(wrap(const AppDivider.indented()));
      final divider = tester.widget<Divider>(find.byType(Divider));
      expect(divider.indent, 8);
      expect(divider.endIndent, 8);
    });

    testWidgets('explicit color overrides the theme default', (tester) async {
      await tester.pumpWidget(wrap(const AppDivider(color: Color(0xFF123456))));
      final divider = tester.widget<Divider>(find.byType(Divider));
      expect(divider.color, const Color(0xFF123456));
    });
  });
}
