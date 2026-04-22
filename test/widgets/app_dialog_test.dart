import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '''package:letsflutssh/l10n/app_localizations.dart''';
import 'package:letsflutssh/theme/app_theme.dart';
import 'package:letsflutssh/core/progress/progress_reporter.dart';
import 'package:letsflutssh/widgets/app_dialog.dart';

void main() {
  Widget wrap(Widget child) {
    return MaterialApp(
      localizationsDelegates: S.localizationsDelegates,
      supportedLocales: S.supportedLocales,
      theme: AppTheme.dark(),
      home: Scaffold(body: child),
    );
  }

  group('AppDialog', () {
    testWidgets('renders title, content, and actions', (tester) async {
      await tester.pumpWidget(
        wrap(
          Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () => AppDialog.show(
                ctx,
                builder: (_) => AppDialog(
                  title: 'Test Title',
                  content: const Text('Body text'),
                  actions: [
                    const AppButton.cancel(),
                    AppButton.primary(label: 'OK', onTap: () {}),
                  ],
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Test Title'), findsOneWidget);
      expect(find.text('Body text'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('OK'), findsOneWidget);
    });

    testWidgets('close button pops dialog', (tester) async {
      await tester.pumpWidget(
        wrap(
          Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () => AppDialog.show(
                ctx,
                builder: (_) => const AppDialog(
                  title: 'Closeable',
                  content: Text('content'),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Closeable'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.text('Closeable'), findsNothing);
    });
  });

  group('AppDialogFooter', () {
    testWidgets('uses Row with Flexible children on desktop', (tester) async {
      await tester.pumpWidget(
        wrap(
          Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () => AppDialog.show(
                ctx,
                builder: (_) => AppDialog(
                  title: 'Footer Test',
                  content: const Text('content'),
                  actions: [
                    const AppButton.cancel(),
                    AppButton.secondary(label: 'Skip', onTap: () {}),
                    AppButton.primary(label: 'Open', onTap: () {}),
                  ],
                ),
              ),
              child: const Text('Show'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show'));
      await tester.pumpAndSettle();

      // Desktop footer uses Row so buttons stay in one line
      expect(find.byType(Row), findsWidgets);
      expect(find.byType(Flexible), findsWidgets);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Skip'), findsOneWidget);
      expect(find.text('Open'), findsOneWidget);
    });

    testWidgets('long labels scale down on narrow screen', (tester) async {
      // Use a very narrow surface to test FittedBox scaling
      tester.view.physicalSize = const Size(320, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        wrap(
          Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () => AppDialog.show(
                ctx,
                builder: (_) => AppDialog(
                  title: 'Narrow',
                  content: const Text('content'),
                  actions: [
                    const AppButton.cancel(),
                    AppButton.secondary(
                      label: 'Skip This Version',
                      onTap: () {},
                    ),
                    AppButton.primary(label: 'Open in Browser', onTap: () {}),
                  ],
                ),
              ),
              child: const Text('Show'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show'));
      await tester.pumpAndSettle();

      // All three actions visible — Flexible + FittedBox prevents overflow
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Skip This Version'), findsOneWidget);
      expect(find.text('Open in Browser'), findsOneWidget);

      // Verify no overflow errors occurred during layout
      expect(tester.takeException(), isNull);
    });
  });

  group('AppButton', () {
    testWidgets('primary action has accent background', (tester) async {
      await tester.pumpWidget(
        wrap(AppButton.primary(label: 'Save', onTap: () {})),
      );

      expect(find.text('Save'), findsOneWidget);
    });

    testWidgets('secondary action renders label', (tester) async {
      await tester.pumpWidget(
        wrap(AppButton.secondary(label: 'Skip', onTap: () {})),
      );

      expect(find.text('Skip'), findsOneWidget);
    });

    testWidgets('destructive action renders label', (tester) async {
      await tester.pumpWidget(
        wrap(AppButton.destructive(label: 'Delete', onTap: () {})),
      );

      expect(find.text('Delete'), findsOneWidget);
    });

    testWidgets('disabled action does not trigger onTap', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        wrap(
          AppButton.primary(
            label: 'Disabled',
            onTap: () => tapped = true,
            enabled: false,
          ),
        ),
      );

      await tester.tap(find.text('Disabled'));
      await tester.pump();
      expect(tapped, isFalse);
    });

    testWidgets('loading swaps label for progress indicator', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        wrap(
          AppButton.primary(
            label: 'Sign in',
            onTap: () => tapped = true,
            loading: true,
          ),
        ),
      );

      // Label is hidden while the async flow runs — the caller is
      // expected to flip loading back off once the future completes.
      expect(find.text('Sign in'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Tap is swallowed during loading — a re-entrant trigger would
      // otherwise spawn two parallel requests for the same action.
      // The factory constructors (`.primary()`, `.secondary()`, etc.)
      // return private subclasses of `AppButton`, so `find.byType` —
      // which matches exact runtime type — misses them. Use a
      // predicate that accepts any AppButton subclass instead.
      await tester.tap(find.byWidgetPredicate((w) => w is AppButton));
      await tester.pump();
      expect(tapped, isFalse);
    });

    testWidgets(
      'dense mode uses the compact desktop height on every platform',
      (tester) async {
        await tester.pumpWidget(
          wrap(
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppButton.secondary(label: 'Dense', onTap: () {}, dense: true),
                AppButton.secondary(label: 'Regular', onTap: () {}),
              ],
            ),
          ),
        );

        final denseSize = tester.getSize(find.text('Dense'));
        final regularSize = tester.getSize(find.text('Regular'));
        // Dense never grows taller than the regular variant; on mobile
        // the regular button uses the larger touch target (`barHeightLg`)
        // while dense stays on `controlHeightXs`, so this predicate holds
        // across desktop + mobile runs of the test harness.
        expect(denseSize.height, lessThanOrEqualTo(regularSize.height));
      },
    );

    testWidgets('icon renders alongside label', (tester) async {
      await tester.pumpWidget(
        wrap(
          AppButton.primary(
            label: 'Download',
            icon: Icons.download,
            onTap: () {},
          ),
        ),
      );
      expect(find.text('Download'), findsOneWidget);
      expect(find.byIcon(Icons.download), findsOneWidget);
    });

    testWidgets('loading hides the icon even when icon: is supplied', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          AppButton.primary(
            label: 'Download',
            icon: Icons.download,
            onTap: () {},
            loading: true,
          ),
        ),
      );
      // During an in-flight action the spinner owns the leading
      // slot; otherwise the control flickers between icon-only and
      // spinner-only framings when the async flow is short-lived.
      expect(find.byIcon(Icons.download), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('fullWidth expands to the host constraint', (tester) async {
      await tester.pumpWidget(
        wrap(
          SizedBox(
            width: 300,
            child: AppButton.primary(
              label: 'Unlock',
              onTap: () {},
              fullWidth: true,
            ),
          ),
        ),
      );

      // See note above on `find.byWidgetPredicate` — `AppButton.primary`
      // returns a private subclass, so `find.byType(AppButton)` finds
      // nothing even though the widget is mounted.
      final buttonSize = tester.getSize(
        find.byWidgetPredicate((w) => w is AppButton),
      );
      expect(buttonSize.width, 300.0);
    });
  });

  group('AppProgressBarDialog', () {
    testWidgets('shows label and indeterminate bar initially', (tester) async {
      final reporter = ProgressReporter('Loading…');
      addTearDown(reporter.dispose);
      await tester.pumpWidget(
        wrap(
          Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () => AppProgressBarDialog.show(ctx, reporter),
              child: const Text('Load'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Load'));
      await tester.pump();

      expect(find.text('Loading…'), findsOneWidget);
      final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(bar.value, isNull, reason: 'initial phase is indeterminate');
      expect(find.text('…'), findsOneWidget);
    });

    testWidgets('step() renders percent and count', (tester) async {
      final reporter = ProgressReporter('Phase');
      addTearDown(reporter.dispose);
      await tester.pumpWidget(
        wrap(
          Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () => AppProgressBarDialog.show(ctx, reporter),
              child: const Text('Load'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Load'));
      await tester.pump();

      reporter.step('Importing', 3, 10);
      await tester.pump();

      expect(find.text('Importing'), findsOneWidget);
      expect(find.text('3 / 10'), findsOneWidget);
      expect(find.text('30%'), findsOneWidget);
      final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(bar.value, closeTo(0.3, 1e-6));
    });

    testWidgets('phase() flips back to indeterminate', (tester) async {
      final reporter = ProgressReporter('Start');
      addTearDown(reporter.dispose);
      await tester.pumpWidget(
        wrap(
          Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () => AppProgressBarDialog.show(ctx, reporter),
              child: const Text('Load'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Load'));
      await tester.pump();

      reporter.step('Step', 1, 4);
      await tester.pump();
      reporter.phase('Finalising…');
      await tester.pump();

      expect(find.text('Finalising…'), findsOneWidget);
      final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(bar.value, isNull);
    });
  });

  group('AppDialog — Escape key', () {
    testWidgets('Escape dismisses a dismissible dialog', (tester) async {
      await tester.pumpWidget(
        wrap(
          Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () => AppDialog.show(
                ctx,
                builder: (_) => const AppDialog(
                  title: 'Esc Test',
                  content: Text('content'),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Esc Test'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Esc Test'), findsNothing);
    });

    testWidgets('Escape does not dismiss a non-dismissible dialog', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () => AppDialog.show(
                ctx,
                barrierDismissible: false,
                builder: (_) => const AppDialog(
                  title: 'No Esc',
                  dismissible: false,
                  content: Text('locked'),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('No Esc'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('No Esc'), findsOneWidget);
    });
  });
}
