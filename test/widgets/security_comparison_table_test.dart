import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/widgets/security/security_comparison_table.dart';

import '../helpers/frb_bootstrap.dart';

Widget _wrap(Widget child, {Locale locale = const Locale('en')}) {
  return MaterialApp(
    locale: locale,
    supportedLocales: S.supportedLocales,
    localizationsDelegates: const [
      S.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () => SecurityComparisonTable.show(context),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  // SecurityComparisonTable calls `evaluate()` per cell, which routes
  // through `lfs_core::threat_vocabulary` — bootstrap FRB so the
  // table can build.
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(requireFrbLoaded);

  group('SecurityComparisonTable', () {
    testWidgets('renders all 7 column headers (en)', (tester) async {
      await tester.pumpWidget(_wrap(const SizedBox()));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final context = tester.element(find.byType(SecurityComparisonTable));
      final l10n = S.of(context);

      // Every column header must appear at least once (DataTable on wide
      // layout, section headings on transposed mobile layout — the test
      // runs on desktop-like MediaQuery so expect DataTable). The
      // standalone "T2" column is gone — Hardware tier is always
      // password-gated, so the comparison matrix carries only the
      // password-bearing T2 variants.
      expect(find.text(l10n.colT0), findsOneWidget);
      expect(find.text(l10n.colT1), findsOneWidget);
      expect(find.text(l10n.colT1Password), findsOneWidget);
      expect(find.text(l10n.colT1PasswordBiometric), findsOneWidget);
      expect(find.text(l10n.colT2Password), findsOneWidget);
      expect(find.text(l10n.colT2PasswordBiometric), findsOneWidget);
      expect(find.text(l10n.colParanoid), findsOneWidget);

      expect(
        find.text(l10n.securityComparisonTableThreatColumn),
        findsOneWidget,
      );
    });

    testWidgets('legend is present with every marker description', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const SizedBox()));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final context = tester.element(find.byType(SecurityComparisonTable));
      final l10n = S.of(context);

      expect(find.text(l10n.legendProtects), findsOneWidget);
      expect(find.text(l10n.legendDoesNotProtect), findsOneWidget);
    });

    testWidgets('title + close action render', (tester) async {
      await tester.pumpWidget(_wrap(const SizedBox()));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final context = tester.element(find.byType(SecurityComparisonTable));
      final l10n = S.of(context);

      expect(find.text(l10n.compareAllTiers), findsWidgets);
      expect(find.text(l10n.close), findsWidgets);
    });
  });
}
