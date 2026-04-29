import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/password_rate_limiter.dart';
import 'package:letsflutssh/core/security/tier_unlock_attempt.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/widgets/tier_secret_unlock_dialog.dart';

Widget _wrap(Widget child) => MaterialApp(
  localizationsDelegates: S.localizationsDelegates,
  supportedLocales: S.supportedLocales,
  home: Scaffold(body: child),
);

Future<bool?> _openDialog(
  WidgetTester tester, {
  required Future<TierUnlockAttempt> Function(String) verify,
  PasswordRateLimiter? rateLimiter,
}) async {
  bool? result;
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
    testWidgets('returns true when verify reports staged', (tester) async {
      await _openDialog(tester, verify: (_) async => TierUnlockAttempt.staged);
      await tester.enterText(find.byType(TextField), 'ok');
      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();
      expect(find.text('Unlock'), findsNothing);
    });

    testWidgets('shows wrong-secret label when verify returns wrongSecret', (
      tester,
    ) async {
      await _openDialog(
        tester,
        verify: (_) async => TierUnlockAttempt.wrongSecret,
      );
      await tester.enterText(find.byType(TextField), 'bad');
      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();
      expect(find.text('wrong'), findsOneWidget);
    });

    // The two limiter-driven dialog tests retired alongside the
    // `InMemoryRateLimiter` move to FRB. Under flutter_test the
    // FRB native lib is not loaded so the Dart shim degrades to a
    // "no-op" state; the tests cannot prime a deterministic
    // cooldown. Equivalent backoff coverage lives in
    // `lfs_core::rate_limit::tests`; widget integration moves to
    // integration_test.

    testWidgets('renders the supplied labels', (tester) async {
      await _openDialog(
        tester,
        verify: (_) async => TierUnlockAttempt.wrongSecret,
      );
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
                    verify: (_) async => TierUnlockAttempt.wrongSecret,
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
      bool? result;
      String? observedSecret;
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
                    numeric: true,
                    maxLength: 4,
                  ),
                  verify: (typed) async {
                    observedSecret = typed;
                    return TierUnlockAttempt.staged;
                  },
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
      expect(observedSecret, '1234');
      expect(result, isTrue);
    });
  });
}
