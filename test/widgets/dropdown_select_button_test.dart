import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/theme/app_theme.dart';
import 'package:letsflutssh/widgets/dropdown_select_button.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
    theme: AppTheme.dark(),
    home: Scaffold(body: child),
  );

  group('DropdownSelectButton', () {
    testWidgets('renders leading icon + label + trailing chevron', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          DropdownSelectButton(
            icon: Icons.vpn_key,
            label: 'Pick a key',
            onTap: () {},
          ),
        ),
      );
      expect(find.text('Pick a key'), findsOneWidget);
      expect(find.byIcon(Icons.vpn_key), findsOneWidget);
      expect(find.byIcon(Icons.keyboard_arrow_down), findsOneWidget);
    });

    testWidgets('omits the chevron when showChevron: false', (tester) async {
      await tester.pumpWidget(
        wrap(
          DropdownSelectButton(
            label: 'No chevron',
            showChevron: false,
            onTap: () {},
          ),
        ),
      );
      expect(find.byIcon(Icons.keyboard_arrow_down), findsNothing);
    });

    testWidgets('onTap fires on tap', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        wrap(DropdownSelectButton(label: 'Tap me', onTap: () => taps++)),
      );
      await tester.tap(find.text('Tap me'));
      await tester.pump();
      expect(taps, 1);
    });

    testWidgets('null onTap = disabled: tap is ignored', (tester) async {
      await tester.pumpWidget(
        wrap(const DropdownSelectButton(label: 'Disabled', onTap: null)),
      );
      // tap on the tile — the MouseRegion/GestureDetector chain
      // returns a basic cursor, so tapping is a no-op. Mostly a
      // regression guard: if someone ever wires an unconditional
      // onTap path this will start throwing.
      await tester.tap(find.text('Disabled'));
      await tester.pump();
      expect(find.text('Disabled'), findsOneWidget);
    });
  });
}
