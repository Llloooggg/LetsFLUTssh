import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/widgets/legacy_kdf_dialog.dart';

Widget _harness(void Function(BuildContext) onPressed) {
  return MaterialApp(
    localizationsDelegates: S.localizationsDelegates,
    supportedLocales: S.supportedLocales,
    home: Scaffold(
      body: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => onPressed(context),
          child: const Text('Open'),
        ),
      ),
    ),
  );
}

void main() {
  group('LegacyKdfDialog', () {
    testWidgets('renders title, body, warning, and both actions', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness((ctx) {
          LegacyKdfDialog.show(ctx);
        }),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Security upgrade required'), findsOneWidget);
      expect(find.text('Reset & Continue'), findsOneWidget);
      expect(find.text('Quit LetsFLUTssh'), findsOneWidget);
      // Body mentions both algorithms.
      expect(find.textContaining('PBKDF2'), findsOneWidget);
      expect(find.textContaining('Argon2id'), findsOneWidget);
    });

    testWidgets('Reset & Continue returns LegacyKdfChoice.resetAndContinue', (
      tester,
    ) async {
      LegacyKdfChoice? result;
      await tester.pumpWidget(
        _harness((ctx) async {
          result = await LegacyKdfDialog.show(ctx);
        }),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Reset & Continue'));
      await tester.pumpAndSettle();

      expect(result, LegacyKdfChoice.resetAndContinue);
    });

    testWidgets('Quit LetsFLUTssh returns LegacyKdfChoice.exitApp', (
      tester,
    ) async {
      LegacyKdfChoice? result;
      await tester.pumpWidget(
        _harness((ctx) async {
          result = await LegacyKdfDialog.show(ctx);
        }),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Quit LetsFLUTssh'));
      await tester.pumpAndSettle();

      expect(result, LegacyKdfChoice.exitApp);
    });

    testWidgets('dialog is non-dismissible — barrier tap does nothing', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness((ctx) {
          LegacyKdfDialog.show(ctx);
        }),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // PopScope with canPop: false must be present — a force-breaking
      // migration notice must not be dismissible into an unusable state.
      final popScope = tester.widget<PopScope>(find.byType(PopScope).first);
      expect(popScope.canPop, isFalse);
    });
  });
}
