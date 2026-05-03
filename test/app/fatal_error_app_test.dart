import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/app/fatal_error_app.dart';

void main() {
  group('FatalErrorApp', () {
    testWidgets('renders the supplied summary and detail strings', (
      tester,
    ) async {
      await tester.pumpWidget(
        const FatalErrorApp(
          summary: 'Bundled core failed to load',
          detail: 'liblfs_frb.so missing — reinstall the app',
        ),
      );
      await tester.pump();
      expect(find.text('Bundled core failed to load'), findsOneWidget);
      expect(
        find.text('liblfs_frb.so missing — reinstall the app'),
        findsOneWidget,
      );
    });

    testWidgets('shows an error icon and a Quit button', (tester) async {
      await tester.pumpWidget(const FatalErrorApp(summary: 's', detail: 'd'));
      await tester.pump();
      // The icon is the highest-level visual cue that something broke
      // — pin its presence so a redesign doesn't accidentally render
      // a blank failure screen.
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Quit'), findsOneWidget);
    });

    testWidgets('runs without a parent ProviderScope or theme registry', (
      tester,
    ) async {
      // Documented contract: this widget exists to render *before* the
      // provider scope + widget registry resolve. Mounting it
      // standalone (no ProviderScope, no MaterialApp ancestor — the
      // widget is itself the root MaterialApp) must not throw.
      await tester.pumpWidget(const FatalErrorApp(summary: 's', detail: 'd'));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('hides the debug banner on the bundled MaterialApp', (
      tester,
    ) async {
      await tester.pumpWidget(const FatalErrorApp(summary: 's', detail: 'd'));
      await tester.pump();
      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.debugShowCheckedModeBanner, isFalse);
    });
  });
}
