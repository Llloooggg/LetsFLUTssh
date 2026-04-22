import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/providers/update_provider.dart';
import 'package:letsflutssh/widgets/update_progress_indicator.dart';

Widget _wrap(Widget child) => MaterialApp(
  localizationsDelegates: S.localizationsDelegates,
  supportedLocales: S.supportedLocales,
  home: Scaffold(body: child),
);

void main() {
  group('UpdateProgressIndicator', () {
    testWidgets('downloading with zero progress renders an indeterminate bar', (
      tester,
    ) async {
      // Progress 0 must NOT paint a "0 %" solid bar — Material guidance
      // says show spinner until the first byte actually streams back,
      // so the widget passes `value: null`. A regression that painted
      // 0 % would falsely signal "stuck at 0" to the user.
      await tester.pumpWidget(
        _wrap(
          const UpdateProgressIndicator(
            state: UpdateState(status: UpdateStatus.downloading),
          ),
        ),
      );
      await tester.pump();
      final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(bar.value, isNull);
    });

    testWidgets(
      'downloading with mid-stream progress renders the exact percent',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            const UpdateProgressIndicator(
              state: UpdateState(
                status: UpdateStatus.downloading,
                progress: 0.42,
              ),
            ),
          ),
        );
        await tester.pump();
        final bar = tester.widget<LinearProgressIndicator>(
          find.byType(LinearProgressIndicator),
        );
        expect(bar.value, 0.42);
        // Caption uses l10n.downloadingPercent — just assert the rounded
        // digits are present rather than pinning the exact wording.
        expect(find.textContaining('42'), findsOneWidget);
      },
    );

    testWidgets(
      'checking status shows the checking caption without a percent',
      (tester) async {
        // "Checking" is the pre-download state — the caption must not
        // say "0 %" because the percent slot only makes sense once the
        // download phase has started. A refactor that collapsed both
        // branches into the same caption would mis-label the phase.
        await tester.pumpWidget(
          _wrap(
            const UpdateProgressIndicator(
              state: UpdateState(status: UpdateStatus.checking),
            ),
          ),
        );
        await tester.pump();
        final context = tester.element(find.byType(UpdateProgressIndicator));
        expect(find.text(S.of(context).checking), findsOneWidget);
      },
    );

    testWidgets(
      'non-downloading states still render a caption (exhaustive switch guard)',
      (tester) async {
        // The switch in _caption is exhaustive over every UpdateStatus
        // value. Walk each value and confirm the widget produces some
        // non-empty caption — the point is "no silent fall-through".
        for (final status in UpdateStatus.values) {
          await tester.pumpWidget(
            _wrap(
              UpdateProgressIndicator(
                state: UpdateState(status: status, progress: 0.5),
              ),
            ),
          );
          await tester.pump();
          final textFinder = find.descendant(
            of: find.byType(UpdateProgressIndicator),
            matching: find.byType(Text),
          );
          expect(
            textFinder,
            findsWidgets,
            reason: '$status must surface a caption',
          );
          final text = tester.widget<Text>(textFinder.first).data!;
          expect(text, isNotEmpty);
        }
      },
    );
  });
}
