import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/theme/app_theme.dart';
import 'package:letsflutssh/widgets/app_button.dart';

void main() {
  Widget wrap(Widget child) {
    return MaterialApp(
      localizationsDelegates: S.localizationsDelegates,
      supportedLocales: S.supportedLocales,
      theme: AppTheme.dark(),
      home: Scaffold(body: Center(child: child)),
    );
  }

  group('AppButton — child selection', () {
    testWidgets('loading: true swaps leading icon for a spinner', (
      tester,
    ) async {
      // The loading branch must keep the label visible and replace the
      // leading icon slot with a CircularProgressIndicator — the
      // Material `.icon(icon: CircularProgressIndicator)` pattern users
      // are used to. Regression gate for the extracted `_buildChild`
      // branch after the S3776 complexity refactor.
      await tester.pumpWidget(
        wrap(
          AppButton.primary(
            label: 'Checking',
            icon: Icons.refresh,
            loading: true,
            onTap: () {},
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Checking'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byIcon(Icons.refresh), findsNothing);
    });

    testWidgets('icon: non-null renders the icon next to the label', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          AppButton.secondary(
            label: 'Refresh',
            icon: Icons.refresh,
            onTap: () {},
          ),
        ),
      );
      expect(find.byIcon(Icons.refresh), findsOneWidget);
      expect(find.text('Refresh'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('no icon, no loading — only the label', (tester) async {
      await tester.pumpWidget(
        wrap(AppButton.secondary(label: 'Plain', onTap: () {})),
      );
      expect(find.text('Plain'), findsOneWidget);
      expect(find.byIcon(Icons.refresh), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('loading: true disables taps even with onTap set', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        wrap(
          AppButton.primary(label: 'Busy', loading: true, onTap: () => taps++),
        ),
      );
      await tester.tap(find.text('Busy'), warnIfMissed: false);
      await tester.pump();
      expect(taps, 0);
    });

    testWidgets('enabled: false disables taps', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        wrap(
          AppButton.primary(label: 'Off', enabled: false, onTap: () => taps++),
        ),
      );
      await tester.tap(find.text('Off'), warnIfMissed: false);
      await tester.pump();
      expect(taps, 0);
    });

    testWidgets('dense: true renders at the compact min-height slot', (
      tester,
    ) async {
      // Can't assert on the Container's painted height directly — the
      // button grows with padding + text intrinsic. Check the
      // BoxConstraints' minHeight instead, which is the only value the
      // refactored `_resolveHeight` drives.
      await tester.pumpWidget(
        wrap(AppButton.secondary(label: 'Dense', dense: true, onTap: () {})),
      );
      final container = tester.widgetList<Container>(find.byType(Container));
      final match = container.where(
        (c) => c.constraints?.minHeight == AppTheme.controlHeightXs,
      );
      expect(match, isNotEmpty);
    });

    testWidgets('fullWidth: true wraps in a SizedBox expanding the row', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          SizedBox(
            width: 320,
            child: AppButton.primary(
              label: 'Wide',
              fullWidth: true,
              onTap: () {},
            ),
          ),
        ),
      );
      // Outer SizedBox should report the host width.
      final width = tester.getSize(find.text('Wide')).width;
      expect(width, greaterThan(0));
      expect(
        find.byWidgetPredicate(
          (w) => w is SizedBox && w.width == double.infinity,
        ),
        findsWidgets,
      );
    });
  });

  group('AppButton — factories', () {
    testWidgets('cancel variant pulls its label from AppLocalizations', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(AppButton.cancel(onTap: () {})));
      expect(find.text('Cancel'), findsOneWidget);
    });
  });
}
