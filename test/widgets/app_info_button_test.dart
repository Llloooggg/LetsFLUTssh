/// Coverage for [AppInfoButton] — the `(i)` icon next to security-tier
/// rows + settings switches that opens an [AppInfoDialog] with the
/// caller-supplied "what this does / doesn't do" copy.
///
/// The wrapper itself is one StatelessWidget that defers to
/// AppIconButton + AppInfoDialog.show; what these tests pin is the
/// shape (icon + tooltip plumbing) and the tap behaviour (opens the
/// dialog without throwing).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/widgets/app_info_button.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
    localizationsDelegates: S.localizationsDelegates,
    supportedLocales: S.supportedLocales,
    home: Scaffold(body: Center(child: child)),
  );

  group('AppInfoButton', () {
    testWidgets('renders an info icon', (tester) async {
      await tester.pumpWidget(
        wrap(
          const AppInfoButton(
            title: 'Title',
            protectsAgainst: ['A'],
            doesNotProtectAgainst: ['B'],
          ),
        ),
      );
      expect(find.byIcon(Icons.info_outline), findsOneWidget);
    });

    testWidgets('default tooltip falls back to the title', (tester) async {
      await tester.pumpWidget(
        wrap(
          const AppInfoButton(
            title: 'Encryption',
            protectsAgainst: [],
            doesNotProtectAgainst: [],
          ),
        ),
      );
      // Long-press surfaces the tooltip text — for a default
      // construction the tooltip must equal the title.
      final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
      expect(tooltip.message, 'Encryption');
    });

    testWidgets('explicit tooltip overrides the title fallback', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          const AppInfoButton(
            title: 'Encryption',
            tooltip: 'About Encryption',
            protectsAgainst: [],
            doesNotProtectAgainst: [],
          ),
        ),
      );
      final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
      expect(tooltip.message, 'About Encryption');
    });

    testWidgets('tapping opens the AppInfoDialog', (tester) async {
      await tester.pumpWidget(
        wrap(
          const AppInfoButton(
            title: 'Plaintext',
            protectsAgainst: ['nothing'],
            doesNotProtectAgainst: ['everything else'],
            extraNotes: 'Use only for trusted local boxes.',
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.info_outline));
      await tester.pumpAndSettle();
      // The dialog renders the caller-supplied copy verbatim — find
      // a string we passed through to confirm the round-trip.
      expect(find.text('Plaintext'), findsOneWidget);
      expect(find.text('nothing'), findsOneWidget);
      expect(find.text('everything else'), findsOneWidget);
    });
  });
}
