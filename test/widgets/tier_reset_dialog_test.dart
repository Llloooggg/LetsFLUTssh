import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/widgets/tier_reset_dialog.dart';

Widget _wrap(Widget child) => MaterialApp(
  localizationsDelegates: S.localizationsDelegates,
  supportedLocales: S.supportedLocales,
  home: Scaffold(body: child),
);

Widget _host(void Function(TierResetChoice) onResult) => _wrap(
  Builder(
    builder: (ctx) => TextButton(
      onPressed: () async {
        onResult(await TierResetDialog.show(ctx));
      },
      child: const Text('Open'),
    ),
  ),
);

void main() {
  group('TierResetDialog', () {
    testWidgets('renders title, body, and warning', (tester) async {
      await tester.pumpWidget(_host((_) {}));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final l10n = S.of(tester.element(find.byType(TierResetDialog)));
      expect(find.text(l10n.tierResetTitle), findsOneWidget);
      expect(find.text(l10n.tierResetBody), findsOneWidget);
      expect(find.text(l10n.tierResetWarning), findsOneWidget);
    });

    testWidgets('Exit button pops with exitApp', (tester) async {
      TierResetChoice? result;
      await tester.pumpWidget(_host((r) => result = r));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final l10n = S.of(tester.element(find.byType(TierResetDialog)));
      await tester.tap(find.text(l10n.tierResetExit));
      await tester.pumpAndSettle();
      expect(result, TierResetChoice.exitApp);
    });

    testWidgets('Destructive reset button pops with resetAndSetupFresh', (
      tester,
    ) async {
      TierResetChoice? result;
      await tester.pumpWidget(_host((r) => result = r));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final l10n = S.of(tester.element(find.byType(TierResetDialog)));
      await tester.tap(find.text(l10n.tierResetResetContinue));
      await tester.pumpAndSettle();
      expect(result, TierResetChoice.resetAndSetupFresh);
    });

    testWidgets('barrier dismiss is disabled (non-dismissible)', (
      tester,
    ) async {
      await tester.pumpWidget(_host((_) {}));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      // Tap outside the dialog — the dialog must stay up.
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.byType(TierResetDialog), findsOneWidget);
    });
  });
}
