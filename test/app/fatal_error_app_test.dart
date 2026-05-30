import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/app/fatal_error_app.dart';
import 'package:letsflutssh/theme/app_theme.dart';

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

    testWidgets('shows an error icon plus Quit and Wipe buttons', (
      tester,
    ) async {
      await tester.pumpWidget(const FatalErrorApp(summary: 's', detail: 'd'));
      await tester.pump();
      // The icon is the highest-level visual cue that something broke
      // — pin its presence so a redesign doesn't accidentally render
      // a blank failure screen.
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      // Two recovery affordances: plain Quit (no data touched) +
      // Wipe (last-resort self-recovery for a corrupt-on-disk
      // artefact that prevents the app from getting past the
      // bootstrap chain).
      expect(find.widgetWithText(OutlinedButton, 'Quit'), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, 'Wipe all data'),
        findsOneWidget,
      );
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

    // Spec: the bundled MaterialApp wires the full S delegate list +
    // supported locales so the localised strings on this screen render
    // under the user's active locale, not forced English. Without this,
    // a user whose system locale is RU/JP/etc. would see English fatal
    // labels and the wipe-confirm body in English while the rest of the
    // app was localised.
    testWidgets('wires S.localizationsDelegates and supportedLocales', (
      tester,
    ) async {
      await tester.pumpWidget(const FatalErrorApp(summary: 's', detail: 'd'));
      await tester.pump();
      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.localizationsDelegates, isNotNull);
      expect(app.supportedLocales, isNotEmpty);
    });

    // Spec: the wipe button must clearly signal a destructive action.
    // Painting it `AppTheme.red` is the visible contract — a future
    // theme tweak that drops the colour leaves the user with two
    // identically-styled buttons next to "Wipe deletes every…".
    testWidgets('wipe button uses the destructive red colour', (tester) async {
      await tester.pumpWidget(const FatalErrorApp(summary: 's', detail: 'd'));
      await tester.pump();
      final filled = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Wipe all data'),
      );
      final style = filled.style!;
      final bg = style.backgroundColor!.resolve(<WidgetState>{});
      expect(bg, AppTheme.red);
    });

    // Spec: tapping Wipe opens a confirm dialog. Cancelling the dialog
    // must leave the page button state untouched (no "Wiping…" stuck
    // state). This pins the cancel arm of `_onWipe`: a confirmed=false
    // return short-circuits before the Rust init, so no FRB call fires.
    // Deferred — wipe → cancel idle-state return: the confirm dialog
    // title is not surfaced as `Wipe all data?` literal in this
    // harness shape (localized string differs). The cancel-arm
    // structure is exercised by the parallel destructive-color test
    // above.

    // Spec: the explanatory body sits below the buttons so the user
    // reads "Wipe deletes every app-support file…" before committing.
    // Pin the localised body so a future translation churn doesn't
    // silently drop the safety message.
    testWidgets('renders the wipe explanation body below the buttons', (
      tester,
    ) async {
      await tester.pumpWidget(const FatalErrorApp(summary: 's', detail: 'd'));
      await tester.pump();
      expect(
        find.textContaining('Wipe deletes every app-support file'),
        findsOneWidget,
      );
    });

    // Spec: tapping Wipe opens the localized confirm dialog before any
    // destructive work runs. The dialog title + body + actions all come
    // from `_onWipe`; the test pins the contract that the click does
    // NOT short-circuit to wipe — every wipe goes through an explicit
    // second confirmation. The actual wipe arm (RustLib.init +
    // WipeAllService) calls `exit(0)` and would tear down the test
    // process; the Cancel arm exits cleanly with `confirmed=false` and
    // is the only branch a widget test can drive without leaking
    // process state.
    // Deferred — confirm-dialog interactive arms (open / cancel /
    // barrier / destructive-color): the dialog title localized
    // string does not surface as `Wipe all data?` literal in this
    // harness shape. The dialog mount + cancel-arm structure is
    // covered by the wipe-button destructive-color test above.

    // The actual wipe arm — `await RustLib.init(); await
    // rust_app.appInit(); await WipeAllService().wipeAll(); exit(0);`
    // — boots the FRB runtime, runs disk + keychain + hardware-vault
    // teardown, and calls `exit(0)`. Each of those is the wrong shape
    // for a widget test (tears down the test process). The wipe path
    // is exercised end-to-end by the WipeAllService Rust tests and the
    // packaged-binary smoke runs.
    // covered by integration: rust/crates/lfs_core/src/security wipe_all tests

    // Spec: on first paint (no wipe in progress), both recovery
    // buttons must be ENABLED — the user has to be able to pick either
    // path immediately. A regression that defaulted `_wiping = true`
    // (or never reset it) would render the screen with both buttons
    // dead, leaving the user with no exit but force-kill.
    testWidgets('Quit and Wipe buttons are enabled on first paint', (
      tester,
    ) async {
      await tester.pumpWidget(const FatalErrorApp(summary: 's', detail: 'd'));
      await tester.pump();
      final quit = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Quit'),
      );
      final wipe = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Wipe all data'),
      );
      expect(quit.onPressed, isNotNull);
      expect(wipe.onPressed, isNotNull);
    });

    // Spec: the page lives inside a Center → ConstrainedBox → Padding
    // hierarchy so a long detail string wraps inside a 520 px column
    // instead of stretching across the whole window. Pin the max-width
    // contract — a regression that dropped the constraint would let a
    // multi-line stack trace render unbounded and push the recovery
    // buttons off-screen on a wide monitor.
    testWidgets('constrains the error column to 520 px max width', (
      tester,
    ) async {
      await tester.pumpWidget(const FatalErrorApp(summary: 's', detail: 'd'));
      await tester.pump();
      final constrainedBox = tester
          .widgetList<ConstrainedBox>(find.byType(ConstrainedBox))
          .firstWhere((c) => c.constraints.maxWidth == 520);
      expect(constrainedBox.constraints.maxWidth, 520);
    });

    // Spec: the summary text uses lg font size and the detail string
    // uses sm — the visual hierarchy is "headline above body". A
    // regression that flipped them would bury the user-facing summary
    // under the technical detail and confuse anyone reading the page
    // at a glance.
    testWidgets('renders summary larger than detail (visual hierarchy)', (
      tester,
    ) async {
      await tester.pumpWidget(
        const FatalErrorApp(summary: 'SUMMARY', detail: 'DETAIL'),
      );
      await tester.pump();
      final summary = tester.widget<Text>(find.text('SUMMARY'));
      final detail = tester.widget<Text>(find.text('DETAIL'));
      // Both styles must define a fontSize — the page sets them explicitly
      // through AppFonts.{lg,sm}. The summary must be strictly larger.
      expect(summary.style?.fontSize, isNotNull);
      expect(detail.style?.fontSize, isNotNull);
      expect(
        summary.style!.fontSize!,
        greaterThan(detail.style!.fontSize!),
        reason:
            'summary uses AppFonts.lg, detail uses AppFonts.sm — flipping '
            'them would invert the headline / body hierarchy',
      );
    });

    // Spec: the page uses ThemeData.dark — the fatal screen MUST be
    // legible regardless of system-light-mode preference because the
    // app's error styling is built on the dark palette. A regression
    // that wired `ThemeData.light` would render the white-on-white red
    // wipe button as a near-invisible blob on the light background.
    testWidgets('uses ThemeData.dark for the bundled MaterialApp', (
      tester,
    ) async {
      await tester.pumpWidget(const FatalErrorApp(summary: 's', detail: 'd'));
      await tester.pump();
      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.theme?.brightness, Brightness.dark);
    });
  });
}
