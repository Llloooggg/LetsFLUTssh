import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/widgets/core/app_button.dart';
import 'package:letsflutssh/widgets/import_export/paste_import_link_dialog.dart';

void main() {
  Future<void> pumpDialog(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: S.localizationsDelegates,
        supportedLocales: S.supportedLocales,
        home: Scaffold(body: PasteImportLinkDialog()),
      ),
    );
    await tester.pumpAndSettle();
  }

  AppButton importButton(WidgetTester tester) => tester.widget<AppButton>(
    find.ancestor(
      of: find.text('Import'),
      matching: find.byWidgetPredicate((w) => w is AppButton),
    ),
  );

  group('PasteImportLinkDialog — Import button gating', () {
    testWidgets('disabled while the field is empty', (tester) async {
      // Spec: nothing to decode means the primary action can only
      // produce the "invalid link" error, so it must be disabled rather
      // than tappable-then-failing.
      await pumpDialog(tester);
      expect(importButton(tester).enabled, isFalse);
    });

    testWidgets('enables once the field holds a payload', (tester) async {
      await pumpDialog(tester);
      await tester.enterText(
        find.byType(TextField),
        'letsflutssh://import?d=abc',
      );
      await tester.pump();
      expect(importButton(tester).enabled, isTrue);
    });

    testWidgets('disables again after a failed decode', (tester) async {
      // Spec: a rejected payload leaves the inline error showing; the
      // button must drop to disabled until the user edits the field,
      // so re-tapping a known-bad value is impossible. (FRB is not
      // booted in the test, so the decode call throws and is caught as
      // a null result — the same path a genuinely invalid link takes.)
      await pumpDialog(tester);
      await tester.enterText(
        find.byType(TextField),
        'letsflutssh://import?d=not-a-real-payload',
      );
      await tester.pump();
      expect(importButton(tester).enabled, isTrue);

      await tester.tap(find.text('Import'));
      await tester.pumpAndSettle();
      expect(
        find.text('Link does not contain a valid LetsFLUTssh payload'),
        findsOneWidget,
      );
      expect(importButton(tester).enabled, isFalse);

      // Editing clears the error and re-enables for the retry.
      await tester.enterText(
        find.byType(TextField),
        'letsflutssh://import?d=x',
      );
      await tester.pump();
      expect(importButton(tester).enabled, isTrue);
    });

    testWidgets('stays disabled for whitespace-only input', (tester) async {
      // Trimmed-empty is still nothing to decode — a few spaces must
      // not flip the button to enabled.
      await pumpDialog(tester);
      await tester.enterText(find.byType(TextField), '   ');
      await tester.pump();
      expect(importButton(tester).enabled, isFalse);
    });
  });
}
