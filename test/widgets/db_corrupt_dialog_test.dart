import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/widgets/db_corrupt_dialog.dart';

Widget _wrap(Widget child) => MaterialApp(
  localizationsDelegates: S.localizationsDelegates,
  supportedLocales: S.supportedLocales,
  home: Scaffold(body: child),
);

Future<DbCorruptChoice> _open(WidgetTester tester) async {
  DbCorruptChoice? captured;
  await tester.pumpWidget(
    _wrap(
      Builder(
        builder: (ctx) => TextButton(
          onPressed: () async {
            captured = await DbCorruptDialog.show(ctx);
          },
          child: const Text('Open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
  // `captured` stays null until the dialog resolves; the caller
  // drives that by tapping a button inside the test body.
  return captured ?? DbCorruptChoice.exitApp;
}

void main() {
  group('DbCorruptDialog', () {
    testWidgets('renders title, body, and warning', (tester) async {
      await _open(tester);
      final l10n = S.of(tester.element(find.byType(DbCorruptDialog)));
      expect(find.text(l10n.dbCorruptTitle), findsOneWidget);
      expect(find.text(l10n.dbCorruptBody), findsOneWidget);
      expect(find.text(l10n.dbCorruptWarning), findsOneWidget);
    });

    testWidgets('Exit button pops with exitApp', (tester) async {
      DbCorruptChoice? result;
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (ctx) => TextButton(
              onPressed: () async {
                result = await DbCorruptDialog.show(ctx);
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final l10n = S.of(tester.element(find.byType(DbCorruptDialog)));
      await tester.tap(find.text(l10n.dbCorruptExit));
      await tester.pumpAndSettle();
      expect(result, DbCorruptChoice.exitApp);
    });

    testWidgets('Try other credentials button pops with tryOtherTier', (
      tester,
    ) async {
      DbCorruptChoice? result;
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (ctx) => TextButton(
              onPressed: () async {
                result = await DbCorruptDialog.show(ctx);
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final l10n = S.of(tester.element(find.byType(DbCorruptDialog)));
      await tester.tap(find.text(l10n.dbCorruptTryOther));
      await tester.pumpAndSettle();
      expect(result, DbCorruptChoice.tryOtherTier);
    });

    testWidgets('Destructive reset button pops with resetAndSetupFresh', (
      tester,
    ) async {
      DbCorruptChoice? result;
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (ctx) => TextButton(
              onPressed: () async {
                result = await DbCorruptDialog.show(ctx);
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final l10n = S.of(tester.element(find.byType(DbCorruptDialog)));
      await tester.tap(find.text(l10n.dbCorruptResetContinue));
      await tester.pumpAndSettle();
      expect(result, DbCorruptChoice.resetAndSetupFresh);
    });
  });
}
