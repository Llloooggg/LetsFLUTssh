/// Coverage for [AppPickerChip] — the project's Material-free chip
/// the ProxyJump mode picker, port-forward kind picker, and similar
/// single-choice surfaces consume.
///
/// Active vs inactive switches the border + background tint;
/// expand=true wraps in an `Expanded` so chip rows can lay out at
/// equal width; expand=false hugs content. Disabled (onTap=null)
/// must not fire on tap. Each is a real layout / interaction
/// invariant a regression elsewhere would silently break.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/widgets/core/app_picker_chip.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
    home: Scaffold(body: Row(children: [child])),
  );

  group('AppPickerChip', () {
    testWidgets('renders the label', (tester) async {
      await tester.pumpWidget(
        wrap(const AppPickerChip(active: false, label: 'TCP')),
      );
      expect(find.text('TCP'), findsOneWidget);
    });

    testWidgets('expand=true wraps the chip in an Expanded', (tester) async {
      await tester.pumpWidget(
        wrap(const AppPickerChip(active: false, label: 'A')),
      );
      // Expanded is the default; the chip must sit inside one so a
      // chip row lays its children at equal width.
      expect(find.byType(Expanded), findsOneWidget);
    });

    testWidgets('expand=false skips the Expanded wrapper', (tester) async {
      await tester.pumpWidget(
        wrap(const AppPickerChip(active: false, label: 'A', expand: false)),
      );
      expect(find.byType(Expanded), findsNothing);
    });

    testWidgets('onTap fires when the chip is tapped', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        wrap(
          AppPickerChip(active: false, label: 'Tap me', onTap: () => taps++),
        ),
      );
      await tester.tap(find.text('Tap me'));
      await tester.pump();
      expect(taps, 1);
    });

    testWidgets('null onTap means tapping is a no-op', (tester) async {
      // Just verify there's no exception — `HoverRegion` should
      // gracefully no-op on a null onTap.
      await tester.pumpWidget(
        wrap(const AppPickerChip(active: false, label: 'Disabled')),
      );
      await tester.tap(find.text('Disabled'));
      await tester.pump();
    });

    testWidgets('icon shown when provided', (tester) async {
      await tester.pumpWidget(
        wrap(
          const AppPickerChip(
            active: true,
            label: 'With icon',
            icon: Icons.bolt,
          ),
        ),
      );
      final icon = tester.widget<Icon>(find.byType(Icon));
      expect(icon.icon, Icons.bolt);
    });

    testWidgets('no icon by default', (tester) async {
      await tester.pumpWidget(
        wrap(const AppPickerChip(active: false, label: 'No icon')),
      );
      expect(find.byType(Icon), findsNothing);
    });
  });
}
