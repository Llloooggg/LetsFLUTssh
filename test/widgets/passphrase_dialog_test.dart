import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/widgets/passphrase_dialog.dart';

void main() {
  Widget buildApp({required void Function(BuildContext) onPressed}) {
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

  group('PassphraseDialog', () {
    testWidgets('shows title and host', (tester) async {
      await tester.pumpWidget(
        buildApp(
          onPressed: (ctx) {
            PassphraseDialog.show(ctx, host: 'example.com');
          },
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Passphrase Required'), findsOneWidget);
      expect(find.textContaining('example.com'), findsAtLeast(1));
    });

    testWidgets('does not show wrong passphrase on first attempt', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildApp(
          onPressed: (ctx) {
            PassphraseDialog.show(ctx, host: 'h', attempt: 1);
          },
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Wrong passphrase. Please try again.'), findsNothing);
    });

    testWidgets('shows wrong passphrase on retry attempt', (tester) async {
      await tester.pumpWidget(
        buildApp(
          onPressed: (ctx) {
            PassphraseDialog.show(ctx, host: 'h', attempt: 2);
          },
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Wrong passphrase. Please try again.'), findsOneWidget);
    });

    testWidgets('cancel returns null', (tester) async {
      PassphraseResult? result;
      var returned = false;
      await tester.pumpWidget(
        buildApp(
          onPressed: (ctx) {
            PassphraseDialog.show(ctx, host: 'h').then((v) {
              result = v;
              returned = true;
            });
          },
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(returned, isTrue);
      expect(result, isNull);
    });

    testWidgets('unlock returns passphrase with remember', (tester) async {
      PassphraseResult? result;
      await tester.pumpWidget(
        buildApp(
          onPressed: (ctx) {
            PassphraseDialog.show(ctx, host: 'h').then((v) => result = v);
          },
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'my-secret');
      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.passphrase, 'my-secret');
      expect(result!.remember, isTrue);
    });

    testWidgets('unlock with remember unchecked', (tester) async {
      PassphraseResult? result;
      await tester.pumpWidget(
        buildApp(
          onPressed: (ctx) {
            PassphraseDialog.show(ctx, host: 'h').then((v) => result = v);
          },
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Uncheck remember checkbox
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'secret');
      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.passphrase, 'secret');
      expect(result!.remember, isFalse);
    });

    testWidgets('empty passphrase does not submit', (tester) async {
      var returned = false;
      await tester.pumpWidget(
        buildApp(
          onPressed: (ctx) {
            PassphraseDialog.show(ctx, host: 'h').then((_) {
              returned = true;
            });
          },
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Tap unlock without entering text
      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();

      // Dialog should still be open
      expect(find.text('Passphrase Required'), findsOneWidget);
      expect(returned, isFalse);
    });

    testWidgets('remember checkbox label is tappable', (tester) async {
      await tester.pumpWidget(
        buildApp(
          onPressed: (ctx) {
            PassphraseDialog.show(ctx, host: 'h');
          },
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Checkbox starts checked
      final checkbox = tester.widget<Checkbox>(find.byType(Checkbox));
      expect(checkbox.value, isTrue);

      // Tap the label text to toggle
      await tester.tap(find.text('Remember for this session'));
      await tester.pumpAndSettle();

      final updated = tester.widget<Checkbox>(find.byType(Checkbox));
      expect(updated.value, isFalse);
    });

    testWidgets('visibility toggle works', (tester) async {
      await tester.pumpWidget(
        buildApp(
          onPressed: (ctx) {
            PassphraseDialog.show(ctx, host: 'h');
          },
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Initially obscured
      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.obscureText, isTrue);

      // Tap visibility toggle
      await tester.tap(find.byIcon(Icons.visibility_off));
      await tester.pumpAndSettle();

      final updated = tester.widget<TextField>(find.byType(TextField));
      expect(updated.obscureText, isFalse);
    });
  });
}
