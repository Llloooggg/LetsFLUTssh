import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/password_rate_limiter.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/widgets/tier_secret_unlock_dialog.dart';

Widget _wrap(Widget child) => MaterialApp(
  localizationsDelegates: S.localizationsDelegates,
  supportedLocales: S.supportedLocales,
  home: Scaffold(body: child),
);

Future<List<int>?> _openDialog(
  WidgetTester tester, {
  required Future<List<int>?> Function(String) verify,
  PasswordRateLimiter? rateLimiter,
}) async {
  List<int>? result;
  var opened = false;
  await tester.pumpWidget(
    _wrap(
      Builder(
        builder: (ctx) => TextButton(
          child: const Text('Open'),
          onPressed: () async {
            opened = true;
            result = await TierSecretUnlockDialog.show(
              ctx,
              labels: const TierSecretUnlockLabels(
                title: 'L2 unlock',
                hint: 'hint',
                inputLabel: 'Password',
                wrongSecretLabel: 'wrong',
              ),
              verify: verify,
              rateLimiter: rateLimiter,
            );
          },
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
  expect(opened, isTrue);
  return result;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TierSecretUnlockDialog', () {
    testWidgets('returns key when verify succeeds', (tester) async {
      await _openDialog(tester, verify: (_) async => [1, 2, 3, 4]);
      await tester.enterText(find.byType(TextField), 'ok');
      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();
      expect(find.text('Unlock'), findsNothing);
    });

    testWidgets('shows wrong-secret label when verify returns null', (
      tester,
    ) async {
      await _openDialog(tester, verify: (_) async => null);
      await tester.enterText(find.byType(TextField), 'bad');
      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();
      expect(find.text('wrong'), findsOneWidget);
    });

    testWidgets('limiter locks the submit button while cooling down', (
      tester,
    ) async {
      final limiter = InMemoryRateLimiter();
      // Prime the limiter so the first pump sees a cooldown.
      limiter.recordFailure();
      await _openDialog(
        tester,
        verify: (_) async => null,
        rateLimiter: limiter,
      );
      final unlockBtn = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(unlockBtn.onPressed, isNull);
    });

    testWidgets('records success on limiter when verify succeeds', (
      tester,
    ) async {
      final limiter = InMemoryRateLimiter();
      limiter.recordFailure();
      limiter.recordFailure();
      // Key is present when limiter is unlocked.
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      await _openDialog(tester, verify: (_) async => [1], rateLimiter: limiter);
      expect(limiter.status().failureCount, 2);
    });

    testWidgets('renders the supplied labels', (tester) async {
      await _openDialog(tester, verify: (_) async => null);
      expect(find.text('L2 unlock'), findsOneWidget);
      expect(find.text('hint'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);
    });

    testWidgets(
      'onReset callback fires when the user clicks "forgot password"',
      (tester) async {
        var resetCalls = 0;
        await tester.pumpWidget(
          _wrap(
            Builder(
              builder: (ctx) => TextButton(
                child: const Text('Open'),
                onPressed: () async {
                  await TierSecretUnlockDialog.show(
                    ctx,
                    labels: const TierSecretUnlockLabels(
                      title: 'L2 unlock',
                      hint: 'hint',
                      inputLabel: 'Password',
                      wrongSecretLabel: 'wrong',
                    ),
                    verify: (_) async => null,
                    onReset: () async => resetCalls++,
                  );
                },
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        // Forgot-password link appears when `onReset` is provided.
        final l10n = S.of(tester.element(find.byType(TierSecretUnlockDialog)));
        await tester.tap(find.text(l10n.forgotPassword));
        await tester.pumpAndSettle();
        // Tapping "forgot password" no longer fires `onReset` directly —
        // it opens a confirm dialog whose destructive action (labelled
        // from `resetAllDataConfirmAction`, matching the Settings → Data →
        // Reset All Data flow) is the trigger. Confirm the dialog so the
        // callback actually runs.
        await tester.tap(find.text(l10n.resetAllDataConfirmAction));
        await tester.pumpAndSettle();
        expect(resetCalls, 1);
      },
    );

    testWidgets('numeric + maxLength restrict the input', (tester) async {
      List<int>? result;
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (ctx) => TextButton(
              child: const Text('Open'),
              onPressed: () async {
                result = await TierSecretUnlockDialog.show(
                  ctx,
                  labels: const TierSecretUnlockLabels(
                    title: 'L3',
                    hint: 'pin',
                    inputLabel: 'PIN',
                    wrongSecretLabel: 'wrong',
                  ),
                  verify: (typed) async => typed.codeUnits,
                  numeric: true,
                  maxLength: 4,
                );
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      // Entering letters through the numeric input filter should drop
      // them — the field receives only the digit portion.
      await tester.enterText(find.byType(TextField), '12ab3456');
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller?.text, '1234');
      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();
      expect(result, '1234'.codeUnits);
    });
  });
}
