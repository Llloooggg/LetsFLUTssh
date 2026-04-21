import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/widgets/app_info_button.dart';
import 'package:letsflutssh/widgets/app_info_dialog.dart';

Widget _wrap(Widget child) => MaterialApp(
  localizationsDelegates: S.localizationsDelegates,
  supportedLocales: S.supportedLocales,
  home: Scaffold(body: child),
);

void main() {
  group('AppInfoDialog', () {
    testWidgets(
      'renders protects + does-not-protect bullets and dismisses on OK',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            Builder(
              builder: (ctx) => TextButton(
                onPressed: () => AppInfoDialog.show(
                  ctx,
                  title: 'Hardware tier',
                  protectsAgainst: const [
                    'Key extraction from disk',
                    'Repeated PIN guessing',
                  ],
                  doesNotProtectAgainst: const [
                    'OS kernel compromise',
                    'Weak TPM firmware CVE',
                  ],
                  extraNotes: 'Requires TPM2 or Secure Enclave.',
                ),
                child: const Text('open'),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        expect(find.text('Hardware tier'), findsOneWidget);
        expect(find.text('Key extraction from disk'), findsOneWidget);
        expect(find.text('OS kernel compromise'), findsOneWidget);
        expect(find.text('Requires TPM2 or Secure Enclave.'), findsOneWidget);
        // Localised section headers from app_en.arb.
        expect(find.text('Protects against'), findsOneWidget);
        expect(find.text('Does not protect against'), findsOneWidget);

        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
        expect(find.text('Hardware tier'), findsNothing);
      },
    );

    testWidgets('omits a section when its bullet list is empty', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (ctx) => TextButton(
              onPressed: () => AppInfoDialog.show(
                ctx,
                title: 'Plaintext',
                protectsAgainst: const [],
                doesNotProtectAgainst: const ['Anyone with filesystem access'],
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Protects against'), findsNothing);
      expect(find.text('Does not protect against'), findsOneWidget);
    });
  });

  group('AppInfoButton', () {
    testWidgets('tapping the info button opens the dialog', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const AppInfoButton(
            title: 'Demo',
            protectsAgainst: ['A'],
            doesNotProtectAgainst: ['B'],
          ),
        ),
      );
      await tester.tap(find.byType(AppInfoButton));
      await tester.pumpAndSettle();
      expect(find.text('Demo'), findsOneWidget);
      expect(find.text('A'), findsOneWidget);
      expect(find.text('B'), findsOneWidget);
    });
  });
}
