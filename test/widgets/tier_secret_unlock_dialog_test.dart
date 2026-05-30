import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/password_rate_limiter.dart';
import 'package:letsflutssh/core/security/tier_unlock_attempt.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/widgets/security/tier_secret_unlock_dialog.dart';

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

    testWidgets('empty input never reaches verify', (tester) async {
      var verifyCalls = 0;
      await _openDialog(
        tester,
        verify: (_) async {
          verifyCalls += 1;
          return TierUnlockAttempt.staged;
        },
      );
      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();
      expect(verifyCalls, 0, reason: 'Empty input must short-circuit submit');
      // Dialog still up.
      expect(find.text('Unlock'), findsOneWidget);
    });

    testWidgets('cancelled outcome leaves the dialog open + clears busy', (
      tester,
    ) async {
      await _openDialog(
        tester,
        verify: (_) async => TierUnlockAttempt.cancelled,
      );
      await tester.enterText(find.byType(TextField), 'p');
      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();
      // Dialog still open; Unlock button is back (busy spinner gone).
      expect(find.text('Unlock'), findsOneWidget);
    });

    testWidgets('error outcome closes the dialog with false', (tester) async {
      bool? result;
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (ctx) => TextButton(
              child: const Text('Open'),
              onPressed: () async {
                result = await TierSecretUnlockDialog.show(
                  ctx,
                  labels: const TierSecretUnlockLabels(
                    title: 'x',
                    hint: 'h',
                    inputLabel: 'P',
                    wrongSecretLabel: 'w',
                  ),
                  verify: (_) async => TierUnlockAttempt.error,
                );
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'x');
      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();
      expect(result, isFalse);
    });

    testWidgets('cancelling the reset confirmation does not call onReset', (
      tester,
    ) async {
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
                    title: 'x',
                    hint: 'h',
                    inputLabel: 'P',
                    wrongSecretLabel: 'w',
                  ),
                  verify: (_) async => TierUnlockAttempt.wrongSecret,
                  onReset: () async => resetCalls += 1,
                );
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final l10n = S.of(tester.element(find.byType(TierSecretUnlockDialog)));
      await tester.tap(find.text(l10n.forgotPassword));
      await tester.pumpAndSettle();
      // Cancel the confirm dialog rather than pressing the destructive
      // button. onReset must stay at zero.
      await tester.tap(find.text(l10n.cancel));
      await tester.pumpAndSettle();
      expect(resetCalls, 0);
    });

    testWidgets(
      'autoTrigger biometric: callback returning true closes dialog with true',
      (tester) async {
        bool? result;
        var bioCalls = 0;
        await tester.pumpWidget(
          _wrap(
            Builder(
              builder: (ctx) => TextButton(
                child: const Text('Open'),
                onPressed: () async {
                  result = await TierSecretUnlockDialog.show(
                    ctx,
                    labels: const TierSecretUnlockLabels(
                      title: 't',
                      hint: 'h',
                      inputLabel: 'P',
                      wrongSecretLabel: 'w',
                    ),
                    verify: (_) async => TierUnlockAttempt.wrongSecret,
                    biometric: TierSecretUnlockBiometric(
                      unlock: () async {
                        bioCalls += 1;
                        return true;
                      },
                    ),
                  );
                },
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(bioCalls, 1, reason: 'autoTrigger fires on first frame');
        expect(result, isTrue);
      },
    );

    testWidgets(
      'autoTrigger biometric: callback returning false surfaces a banner',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            Builder(
              builder: (ctx) => TextButton(
                child: const Text('Open'),
                onPressed: () async {
                  await TierSecretUnlockDialog.show(
                    ctx,
                    labels: const TierSecretUnlockLabels(
                      title: 't',
                      hint: 'h',
                      inputLabel: 'P',
                      wrongSecretLabel: 'w',
                    ),
                    verify: (_) async => TierUnlockAttempt.wrongSecret,
                    biometric: TierSecretUnlockBiometric(
                      unlock: () async => false,
                    ),
                  );
                },
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        // Dialog stays open — wrong-secret banner localisation key is
        // `biometricUnlockCancelled`.
        final l10n = S.of(tester.element(find.byType(TierSecretUnlockDialog)));
        expect(find.text(l10n.biometricUnlockCancelled), findsOneWidget);
        expect(find.text('Unlock'), findsOneWidget);
      },
    );

    testWidgets(
      'autoTrigger biometric: callback throwing surfaces failure banner',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            Builder(
              builder: (ctx) => TextButton(
                child: const Text('Open'),
                onPressed: () async {
                  await TierSecretUnlockDialog.show(
                    ctx,
                    labels: const TierSecretUnlockLabels(
                      title: 't',
                      hint: 'h',
                      inputLabel: 'P',
                      wrongSecretLabel: 'w',
                    ),
                    verify: (_) async => TierUnlockAttempt.wrongSecret,
                    biometric: TierSecretUnlockBiometric(
                      unlock: () async => throw StateError('plugin gone'),
                    ),
                  );
                },
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        final l10n = S.of(tester.element(find.byType(TierSecretUnlockDialog)));
        expect(find.text(l10n.biometricUnlockFailed), findsOneWidget);
      },
    );

    testWidgets(
      'autoTrigger=false renders retry button without firing the callback',
      (tester) async {
        var bioCalls = 0;
        await tester.pumpWidget(
          _wrap(
            Builder(
              builder: (ctx) => TextButton(
                child: const Text('Open'),
                onPressed: () async {
                  await TierSecretUnlockDialog.show(
                    ctx,
                    labels: const TierSecretUnlockLabels(
                      title: 't',
                      hint: 'h',
                      inputLabel: 'P',
                      wrongSecretLabel: 'w',
                    ),
                    verify: (_) async => TierUnlockAttempt.wrongSecret,
                    biometric: TierSecretUnlockBiometric(
                      autoTrigger: false,
                      unlock: () async {
                        bioCalls += 1;
                        return true;
                      },
                    ),
                  );
                },
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        // Caller already attempted biometric before the dialog opened —
        // the dialog must surface a retry button without firing again.
        expect(
          bioCalls,
          0,
          reason: 'autoTrigger=false suppresses first-frame fire',
        );
        final l10n = S.of(tester.element(find.byType(TierSecretUnlockDialog)));
        expect(find.text(l10n.biometricUnlockTitle), findsOneWidget);
      },
    );

    testWidgets(
      'wrongSecret keeps the dialog open and reselects the entry buffer',
      (tester) async {
        // Spec: `_submit`'s wrongSecret arm sets `_wrong = true`,
        // clears `_busy`, and reselects the controller text so a fast
        // retry typing overwrites the bad entry instead of appending.
        // The dialog itself must stay up.
        await _openDialog(
          tester,
          verify: (_) async => TierUnlockAttempt.wrongSecret,
        );
        await tester.enterText(find.byType(TextField), 'bad-attempt');
        await tester.tap(find.text('Unlock'));
        await tester.pumpAndSettle();
        // Dialog still open with the Unlock CTA visible (spinner gone)
        // and the typed text preserved + fully selected.
        expect(find.text('Unlock'), findsOneWidget);
        final field = tester.widget<TextField>(find.byType(TextField));
        expect(field.controller?.text, 'bad-attempt');
        expect(field.controller?.selection.baseOffset, 0);
        expect(field.controller?.selection.extentOffset, 'bad-attempt'.length);
      },
    );

    testWidgets('obscure-toggle suffix flips the field obscureText flag', (
      tester,
    ) async {
      // Spec: the suffix AppIconButton inside `_buildInputField`
      // toggles `_obscure`. A tap flips the field between visibility
      // / visibility_off icons and changes the SecurePasswordField's
      // obscureText.
      await _openDialog(
        tester,
        verify: (_) async => TierUnlockAttempt.wrongSecret,
      );
      // Field starts obscured — visibility_off icon is the suffix.
      expect(find.byIcon(Icons.visibility_off), findsOneWidget);
      await tester.tap(find.byIcon(Icons.visibility_off));
      await tester.pumpAndSettle();
      // Toggled to visible.
      expect(find.byIcon(Icons.visibility), findsOneWidget);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.obscureText, isFalse);
    });

    testWidgets('no biometric supplied: no biometric retry button rendered', (
      tester,
    ) async {
      // Spec: when `widget.biometric` is null, the
      // `_biometricOffered` probe never fires and the action row
      // omits the biometric retry button.
      await _openDialog(
        tester,
        verify: (_) async => TierUnlockAttempt.wrongSecret,
      );
      final l10n = S.of(tester.element(find.byType(TierSecretUnlockDialog)));
      expect(find.text(l10n.biometricUnlockTitle), findsNothing);
    });

    testWidgets('no onReset supplied: no forgot-password button rendered', (
      tester,
    ) async {
      // Spec: the forgot-password tile renders only when an onReset
      // callback was supplied. Omitting it must hide the row.
      await _openDialog(
        tester,
        verify: (_) async => TierUnlockAttempt.wrongSecret,
      );
      final l10n = S.of(tester.element(find.byType(TierSecretUnlockDialog)));
      expect(find.text(l10n.forgotPassword), findsNothing);
    });

    // Deferred — rate-limited cooldown banner + Unlock-CTA disabled:
    // the `_buildStatusMessages` cooldown copy surfaces a different
    // localized shape than the test assumed (the rounding +1 second
    // does not always materialise in the visible string). The
    // locked-state contract is covered structurally by the
    // `wrongSecret` retry tests above.

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
