/// Coverage for [AppPopupSelect] — the dropdown picker every settings
/// surface (language, log level, tier wizard) consumes.
///
/// The trigger renders the current option's label; the
/// `firstWhere(... orElse: options.first)` fallback handles a
/// stale `value` that does not appear in the current `options`
/// list. The leading-icon / no-icon split is the third surface
/// branch every caller switches on.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/widgets/core/app_popup_select.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('AppPopupSelect — trigger surface', () {
    testWidgets('renders the current option label on the trigger', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          AppPopupSelect<int>(
            value: 1,
            options: const [
              AppPopupSelectOption(value: 1, label: 'One'),
              AppPopupSelectOption(value: 2, label: 'Two'),
            ],
            onChanged: (_) {},
          ),
        ),
      );
      expect(find.text('One'), findsOneWidget);
    });

    testWidgets('falls back to the first option when value matches none', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          AppPopupSelect<int>(
            value: 99, // not present in options
            options: const [
              AppPopupSelectOption(value: 1, label: 'First'),
              AppPopupSelectOption(value: 2, label: 'Second'),
            ],
            onChanged: (_) {},
          ),
        ),
      );
      // The orElse fallback in `firstWhere` resolves to options[0]
      // — the trigger renders "First" instead of crashing on
      // `Bad state: No element`.
      expect(find.text('First'), findsOneWidget);
    });

    testWidgets('leading icon renders when provided', (tester) async {
      await tester.pumpWidget(
        wrap(
          AppPopupSelect<int>(
            value: 1,
            options: const [AppPopupSelectOption(value: 1, label: 'One')],
            onChanged: (_) {},
            leadingIcon: Icons.language,
          ),
        ),
      );
      // Two icons in the trigger when the leading icon is set: the
      // leading + the trailing arrow_drop_down.
      expect(find.byIcon(Icons.language), findsOneWidget);
      expect(find.byIcon(Icons.arrow_drop_down), findsOneWidget);
    });

    testWidgets(
      'leading icon absent by default — only the down arrow renders',
      (tester) async {
        await tester.pumpWidget(
          wrap(
            AppPopupSelect<int>(
              value: 1,
              options: const [AppPopupSelectOption(value: 1, label: 'One')],
              onChanged: (_) {},
            ),
          ),
        );
        expect(find.byType(Icon), findsOneWidget);
        expect(find.byIcon(Icons.arrow_drop_down), findsOneWidget);
      },
    );
  });

  group('AppPopupSelectOption', () {
    test('default constructor leaves secondary null', () {
      const opt = AppPopupSelectOption(value: 1, label: 'A');
      expect(opt.secondary, isNull);
    });

    test('secondary is preserved when supplied', () {
      const opt = AppPopupSelectOption(
        value: 'ru',
        label: 'Русский',
        secondary: 'Russian',
      );
      expect(opt.secondary, 'Russian');
    });
  });

  group('AppPopupSelect — open + select', () {
    testWidgets('tapping the trigger opens the menu with all options', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          AppPopupSelect<int>(
            value: 1,
            options: const [
              AppPopupSelectOption(value: 1, label: 'Alpha'),
              AppPopupSelectOption(value: 2, label: 'Bravo'),
              AppPopupSelectOption(value: 3, label: 'Charlie'),
            ],
            onChanged: (_) {},
          ),
        ),
      );
      // Tap the trigger — the popup overlays the page.
      await tester.tap(find.byIcon(Icons.arrow_drop_down));
      await tester.pumpAndSettle();
      expect(find.text('Bravo'), findsOneWidget);
      expect(find.text('Charlie'), findsOneWidget);
    });

    testWidgets(
      'selecting an option in the menu fires onChanged with that value',
      (tester) async {
        int? picked;
        await tester.pumpWidget(
          wrap(
            AppPopupSelect<int>(
              value: 1,
              options: const [
                AppPopupSelectOption(value: 1, label: 'Alpha'),
                AppPopupSelectOption(value: 2, label: 'Bravo'),
              ],
              onChanged: (v) => picked = v,
            ),
          ),
        );
        await tester.tap(find.byIcon(Icons.arrow_drop_down));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Bravo'));
        await tester.pumpAndSettle();
        expect(picked, 2);
      },
    );
  });
}
