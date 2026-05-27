/// Widget tests for [TypedNameConfirmDialog] — the type-the-phrase
/// guard on catastrophic, irreversible flows. The Confirm button must
/// stay disabled until the typed text matches the magic phrase verbatim.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/widgets/core/app_button.dart';
import 'package:letsflutssh/widgets/core/typed_name_confirm_dialog.dart';

void main() {
  Future<bool? Function()> openDialog(WidgetTester tester) async {
    bool? captured;
    var done = false;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: S.localizationsDelegates,
        supportedLocales: S.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                captured = await TypedNameConfirmDialog.show(
                  context,
                  title: 'Reset everything',
                  body: const Text('This wipes all data.'),
                  magicPhrase: 'LetsFLUTssh',
                  confirmLabel: 'WIPE',
                  typePromptHint: 'Type the phrase',
                );
                done = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return () => done ? captured : null;
  }

  bool confirmEnabled(WidgetTester tester) {
    return tester
        .widget<AppButton>(
          find.byWidgetPredicate((w) => w is AppButton && w.label == 'WIPE'),
        )
        .enabled;
  }

  testWidgets('Confirm is disabled until the phrase matches verbatim', (
    tester,
  ) async {
    await openDialog(tester);
    expect(confirmEnabled(tester), isFalse);

    await tester.enterText(find.byType(TextField), 'letsflutssh'); // wrong case
    await tester.pump();
    expect(confirmEnabled(tester), isFalse);

    await tester.enterText(find.byType(TextField), 'LetsFLUTssh');
    await tester.pump();
    expect(confirmEnabled(tester), isTrue);
  });

  testWidgets('confirming after a match returns true', (tester) async {
    final result = await openDialog(tester);
    await tester.enterText(find.byType(TextField), 'LetsFLUTssh');
    await tester.pump();
    await tester.tap(find.text('WIPE'));
    await tester.pumpAndSettle();
    expect(result(), isTrue);
  });

  testWidgets('cancelling returns false even with a matching phrase', (
    tester,
  ) async {
    final result = await openDialog(tester);
    await tester.enterText(find.byType(TextField), 'LetsFLUTssh');
    await tester.pump();
    // Cancel must win even though the phrase now matches.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(result(), isFalse);
  });
}
