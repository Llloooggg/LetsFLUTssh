import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/password_rate_limiter.dart';
import 'package:letsflutssh/core/security/tier_unlock_attempt.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/widgets/core/app_dialog.dart';
import 'package:letsflutssh/widgets/security/unlock_dialog.dart';

import '../helpers/fake_security.dart';

/// Fake [MasterPasswordManager] whose `unlockAttempt` blocks on an
/// externally-completable future so the test can observe the busy
/// branch of `_unlock` between the `setState(_busy = true)` and the
/// terminal response. The queued-outcomes path in
/// [FakeMasterPasswordManager] returns immediately, leaving no
/// observable window to pump the busy-branch widgets.
class _SlowFakeManager extends FakeMasterPasswordManager {
  _SlowFakeManager(this._pending);

  final Future<TierUnlockAttempt> _pending;

  @override
  Future<TierUnlockAttempt> unlockAttempt(Uint8List password) async {
    unlockAttemptCalls.add(password);
    return _pending;
  }
}

Widget _wrap(Widget child) => ProviderScope(
  child: MaterialApp(
    localizationsDelegates: S.localizationsDelegates,
    supportedLocales: S.supportedLocales,
    home: Scaffold(body: child),
  ),
);

Future<bool?> _open(
  WidgetTester tester, {
  required FakeMasterPasswordManager manager,
}) async {
  bool? result;
  await tester.pumpWidget(
    _wrap(
      Builder(
        builder: (ctx) => TextButton(
          child: const Text('Open'),
          onPressed: () async {
            result = await UnlockDialog.show(ctx, manager: manager);
          },
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UnlockDialog — unlock path', () {
    testWidgets('staged outcome closes the dialog with true', (tester) async {
      final mgr = FakeMasterPasswordManager(
        unlockOutcomes: [TierUnlockAttempt.staged],
      );
      bool? result;
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (ctx) => TextButton(
              child: const Text('Open'),
              onPressed: () async {
                result = await UnlockDialog.show(ctx, manager: mgr);
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'correct-password');
      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();
      expect(mgr.unlockAttemptCalls.map(utf8.decode).toList(), [
        'correct-password',
      ]);
      expect(result, isTrue);
    });

    testWidgets('wrongSecret leaves dialog open with the wrong-pw banner', (
      tester,
    ) async {
      final mgr = FakeMasterPasswordManager(
        unlockOutcomes: [TierUnlockAttempt.wrongSecret],
      );
      await _open(tester, manager: mgr);
      await tester.enterText(find.byType(TextField), 'wrong');
      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();
      final l10n = S.of(tester.element(find.byType(UnlockDialog)));
      expect(find.text(l10n.wrongMasterPassword), findsOneWidget);
      // Dialog still up — Unlock button is back.
      expect(find.text(l10n.unlock), findsOneWidget);
      expect(mgr.unlockAttemptCalls.map(utf8.decode).toList(), ['wrong']);
    });

    testWidgets('cancelled outcome closes the dialog with null', (
      tester,
    ) async {
      final mgr = FakeMasterPasswordManager(
        unlockOutcomes: [TierUnlockAttempt.cancelled],
      );
      bool? result;
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (ctx) => TextButton(
              child: const Text('Open'),
              onPressed: () async {
                result = await UnlockDialog.show(ctx, manager: mgr);
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'whatever');
      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();
      // null sentinel: caller routes through plaintext / corruption.
      expect(result, isNull);
    });

    testWidgets('error outcome closes the dialog with null', (tester) async {
      final mgr = FakeMasterPasswordManager(
        unlockOutcomes: [TierUnlockAttempt.error],
      );
      bool? result;
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (ctx) => TextButton(
              child: const Text('Open'),
              onPressed: () async {
                result = await UnlockDialog.show(ctx, manager: mgr);
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
      expect(result, isNull);
    });

    testWidgets('empty password short-circuits — manager never sees it', (
      tester,
    ) async {
      final mgr = FakeMasterPasswordManager(
        unlockOutcomes: [TierUnlockAttempt.staged],
      );
      await _open(tester, manager: mgr);
      // Submit the empty field directly. The button should ignore it.
      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();
      expect(
        mgr.unlockAttemptCalls,
        isEmpty,
        reason: 'Empty password is the early-return branch in _unlock',
      );
    });

    testWidgets(
      'wrongSecret with newly-locked rate limiter surfaces cooldown banner',
      (tester) async {
        // Failure status with a 5-second cooldown — drives the
        // post-attempt setState that activates the ticker.
        const lockedAfter = RateLimitStatus(
          failureCount: 5,
          cooldownRemaining: Duration(seconds: 5),
        );
        final mgr = FakeMasterPasswordManager(
          unlockOutcomes: [TierUnlockAttempt.wrongSecret],
          statusAfterFailure: lockedAfter,
        );
        await _open(tester, manager: mgr);
        await tester.enterText(find.byType(TextField), 'bad');
        await tester.tap(find.text('Unlock'));
        await tester.pump();
        await tester.pump();
        final l10n = S.of(tester.element(find.byType(UnlockDialog)));
        // Cooldown banner uses tierCooldownHint(seconds + 1).
        expect(find.text(l10n.tierCooldownHint(6)), findsOneWidget);
        // Drain the ticker (1-second periodic) so flutter_test's
        // pending-timer invariant doesn't trip at end of test.
        await tester.pump(const Duration(seconds: 6));
        await tester.pumpAndSettle();
      },
    );

    testWidgets('initial cooldown shown on open does not call manager', (
      tester,
    ) async {
      const initialLocked = RateLimitStatus(
        failureCount: 3,
        cooldownRemaining: Duration(seconds: 7),
      );
      final mgr = FakeMasterPasswordManager(
        unlockOutcomes: [TierUnlockAttempt.staged],
        initialStatus: initialLocked,
      );
      await _open(tester, manager: mgr);
      final l10n = S.of(tester.element(find.byType(UnlockDialog)));
      expect(find.text(l10n.tierCooldownHint(8)), findsOneWidget);
      // Tap anyway — the button is null-callback while locked, so
      // tapping it is a no-op. Confirm no attempt fired.
      expect(mgr.unlockAttemptCalls, isEmpty);
      // Drain the cooldown ticker.
      await tester.pump(const Duration(seconds: 8));
      await tester.pumpAndSettle();
    });

    testWidgets('renders the master-password copy + lock icon on open', (
      tester,
    ) async {
      final mgr = FakeMasterPasswordManager(
        unlockOutcomes: [TierUnlockAttempt.staged],
      );
      await _open(tester, manager: mgr);
      final l10n = S.of(tester.element(find.byType(UnlockDialog)));
      expect(find.text(l10n.masterPassword), findsOneWidget);
      expect(find.text(l10n.enterMasterPassword), findsOneWidget);
      expect(find.byIcon(Icons.lock), findsOneWidget);
      // The Unlock button + Forgot password link are both rendered
      // when not busy.
      expect(find.text(l10n.unlock), findsOneWidget);
      expect(find.text(l10n.forgotPassword), findsOneWidget);
    });

    testWidgets(
      'tapping the visibility suffix flips the obscure state on the password '
      'field',
      (tester) async {
        // Spec: the suffix `AppIconButton` toggles `_obscure`. When
        // visible it renders the `visibility` icon and the underlying
        // `SecurePasswordField` clears its `obscureText`; tapping
        // again restores `visibility_off` + obscured input.
        final mgr = FakeMasterPasswordManager(
          unlockOutcomes: [TierUnlockAttempt.staged],
        );
        await _open(tester, manager: mgr);
        // Initial state — `visibility_off` rendered because text is
        // hidden by default.
        expect(find.byIcon(Icons.visibility_off), findsOneWidget);
        expect(find.byIcon(Icons.visibility), findsNothing);
        await tester.tap(find.byIcon(Icons.visibility_off));
        await tester.pumpAndSettle();
        // After the flip — eye icon swaps to the inverse glyph.
        expect(find.byIcon(Icons.visibility), findsOneWidget);
        expect(find.byIcon(Icons.visibility_off), findsNothing);
        // No unlock fired — the suffix never triggers a submit.
        expect(mgr.unlockAttemptCalls, isEmpty);
      },
    );

    testWidgets(
      'submitting the password field via the keyboard action invokes the '
      'unlock path the same as tapping the Unlock button',
      (tester) async {
        // Spec: `SecurePasswordField.onSubmitted` wires through to
        // `_unlock`. The dialog must accept Enter / IME submit as an
        // alternative to tapping the primary button.
        final mgr = FakeMasterPasswordManager(
          unlockOutcomes: [TierUnlockAttempt.staged],
        );
        bool? result;
        await tester.pumpWidget(
          _wrap(
            Builder(
              builder: (ctx) => TextButton(
                child: const Text('Open'),
                onPressed: () async {
                  result = await UnlockDialog.show(ctx, manager: mgr);
                },
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'submit-via-enter');
        // Fire the editing-action callback that backs Enter on the
        // soft / hardware keyboard.
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        expect(result, isTrue);
        expect(mgr.unlockAttemptCalls.map(utf8.decode).toList(), [
          'submit-via-enter',
        ]);
      },
    );

    testWidgets(
      'cooldown ticker stops once the rate-limit status flips back to '
      'unlocked between ticks',
      (tester) async {
        // Spec: `_startCooldownTicker` polls `manager.rateLimitStatus()`
        // every second and tears itself down once `!next.isLocked`.
        // Drive a 5-second cooldown, then mutate the fake's status to
        // unlocked between ticks and pump forward — the ticker should
        // cancel itself and the locked banner should disappear.
        const lockedAfter = RateLimitStatus(
          failureCount: 5,
          cooldownRemaining: Duration(seconds: 3),
        );
        final mgr = FakeMasterPasswordManager(
          unlockOutcomes: [TierUnlockAttempt.wrongSecret],
          statusAfterFailure: lockedAfter,
        );
        await _open(tester, manager: mgr);
        await tester.enterText(find.byType(TextField), 'bad');
        await tester.tap(find.text('Unlock'));
        await tester.pump();
        await tester.pump();
        final l10n = S.of(tester.element(find.byType(UnlockDialog)));
        // Banner up while the cooldown is engaged.
        expect(find.text(l10n.tierCooldownHint(4)), findsOneWidget);
        // Flip the fake back to unlocked, then advance one tick.
        mgr.setStatus(
          const RateLimitStatus(
            failureCount: 0,
            cooldownRemaining: Duration.zero,
          ),
        );
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpAndSettle();
        // Banner gone — ticker observed the unlocked status and
        // cancelled itself.
        expect(find.text(l10n.tierCooldownHint(4)), findsNothing);
      },
    );

    testWidgets(
      'busy state renders the deriving-key indicator and disables the form',
      (tester) async {
        // Spec: while `_busy` is true the dialog hides the primary
        // Unlock button + Forgot link in favour of the spinner + the
        // `derivingKey` copy. Drive that branch with a slow manager
        // whose `unlockAttempt` future hangs until we explicitly
        // complete it, so the test can pump between the setState that
        // flips `_busy` and the response that flips it back.
        final completer = Completer<TierUnlockAttempt>();
        final mgr = _SlowFakeManager(completer.future);
        await _open(tester, manager: mgr);
        await tester.enterText(find.byType(TextField), 'pw');
        await tester.tap(find.text('Unlock'));
        // First pump runs `_unlock` synchronously up to the await,
        // setting `_busy = true`; the next pump rebuilds with the
        // busy branch.
        await tester.pump();
        final l10n = S.of(tester.element(find.byType(UnlockDialog)));
        expect(find.text(l10n.derivingKey), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        // Primary button + forgot link both gone while busy.
        expect(find.text(l10n.unlock), findsNothing);
        expect(find.text(l10n.forgotPassword), findsNothing);
        // Release the hanging unlock attempt so the test can settle
        // without leaking the future.
        completer.complete(TierUnlockAttempt.staged);
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'tapping "Forgot password?" opens the typed-name reset confirmation; '
      'dismissing it returns to the unlock dialog without wiping',
      (tester) async {
        // Spec: forgot-password routes through the same typed-name
        // confirmation as Settings → Reset All Data. Confirming
        // (typing "LetsFLUTssh") triggers WipeAllService; cancelling
        // the confirmation returns to the unlock dialog untouched and
        // the manager.unlockAttempt counter must NOT tick — the
        // unlock dialog is still up so the user can keep trying the
        // password.
        final mgr = FakeMasterPasswordManager(
          unlockOutcomes: [TierUnlockAttempt.staged],
        );
        await _open(tester, manager: mgr);
        final l10n = S.of(tester.element(find.byType(UnlockDialog)));
        await tester.tap(find.text(l10n.forgotPassword));
        await tester.pumpAndSettle();
        // The confirmation dialog should be visible with its title.
        expect(find.text(l10n.resetAllDataConfirmTitle), findsOneWidget);
        // Dismiss via the Cancel button on the confirmation dialog.
        await tester.tap(find.text(l10n.cancel));
        await tester.pumpAndSettle();
        // Back on the unlock dialog — Unlock button is rendered again,
        // confirmation title is gone, manager was never invoked.
        expect(find.text(l10n.unlock), findsOneWidget);
        expect(find.text(l10n.resetAllDataConfirmTitle), findsNothing);
        expect(mgr.unlockAttemptCalls, isEmpty);
      },
    );

    testWidgets('forgot-password typed-name gate: the destructive action stays '
        'disabled until the user types the magic phrase verbatim', (
      tester,
    ) async {
      // Spec: `TypedNameConfirmDialog` enables the destructive
      // Confirm action only when the typed text exactly matches the
      // magic phrase `LetsFLUTssh`. Typing a near-miss leaves the
      // action disabled and tapping it is a no-op (Dialog stays up
      // and the unlock dialog never wipes). Pin "disabled when text
      // doesn't match" by inspecting the AppButton's enabled flag
      // — more reliable than a tap-and-not-pop probe because the
      // disabled button swallows the gesture.
      final mgr = FakeMasterPasswordManager(
        unlockOutcomes: [TierUnlockAttempt.staged],
      );
      await _open(tester, manager: mgr);
      final l10n = S.of(tester.element(find.byType(UnlockDialog)));
      await tester.tap(find.text(l10n.forgotPassword));
      await tester.pumpAndSettle();

      // Type a near-miss into the phrase field — same length,
      // off by one character.
      await tester.enterText(find.byType(TextField).last, 'LetsFLUTssH');
      await tester.pumpAndSettle();

      // The destructive confirm action is in the dialog footer.
      // `AppButton.destructive(enabled: _matches)` — `_matches` is
      // false for a non-exact entry, so the action button's
      // `onTap` collapses to null (the disabled-state branch in
      // AppButton).
      final confirmBtn = tester.widget<AppButton>(
        find.ancestor(
          of: find.text(l10n.resetAllDataConfirmAction),
          matching: find.byWidgetPredicate((w) => w is AppButton),
        ),
      );
      expect(
        confirmBtn.enabled,
        isFalse,
        reason: 'near-miss text leaves _matches=false',
      );
      // The unlock manager has not been invoked, and the wipe has
      // not started. Cancel out and confirm the unlock dialog is
      // back up so the test exits cleanly without a half-finished
      // FRB wipe.
      await tester.tap(find.text(l10n.cancel));
      await tester.pumpAndSettle();
      expect(find.text(l10n.unlock), findsOneWidget);
      expect(mgr.unlockAttemptCalls, isEmpty);
    });

    testWidgets(
      'forgot-password typed-name gate: the destructive action enables '
      'once the magic phrase matches verbatim',
      (tester) async {
        // Spec mirror of the above: the same controller, fed the
        // exact magic phrase, must flip `_matches` to true and arm
        // the destructive action. We pin the enabled flag and back
        // out via Cancel so the actual wipe (which routes through
        // `WipeAllService` → real FRB recovery cascade) does NOT
        // fire inside the unit-test process.
        final mgr = FakeMasterPasswordManager(
          unlockOutcomes: [TierUnlockAttempt.staged],
        );
        await _open(tester, manager: mgr);
        final l10n = S.of(tester.element(find.byType(UnlockDialog)));
        await tester.tap(find.text(l10n.forgotPassword));
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField).last, 'LetsFLUTssh');
        await tester.pumpAndSettle();

        // The destructive confirm action's enabled flag is the
        // observable shape of `_matches`. Pin it directly so a future
        // refactor that breaks the gate doesn't silently slide
        // through.
        final confirmBtn = tester.widget<AppButton>(
          find.ancestor(
            of: find.text(l10n.resetAllDataConfirmAction),
            matching: find.byWidgetPredicate((w) => w is AppButton),
          ),
        );
        expect(
          confirmBtn.enabled,
          isTrue,
          reason: 'verbatim match flips _matches=true',
        );

        // Cancel out before tapping the now-armed destructive action,
        // otherwise the wipe fires inside the unit-test process.
        await tester.tap(find.text(l10n.cancel));
        await tester.pumpAndSettle();
        expect(find.text(l10n.unlock), findsOneWidget);
      },
    );

    testWidgets(
      'Unlock primary button has a null onTap while the cooldown is engaged so '
      'the AppButton renders in its disabled-state branch',
      (tester) async {
        // Spec: the build branch `_cooldown.isLocked ? null : _unlock`
        // wires the primary button's onTap to null when the limiter is
        // locked. The button is `AppButton.primary(... onTap: ...)` —
        // a null onTap collapses through the AppButton disabled-state
        // branch. Pin the wiring directly so a future refactor that
        // drops the gate cannot silently re-enable submits during a
        // cooldown window.
        const initialLocked = RateLimitStatus(
          failureCount: 4,
          cooldownRemaining: Duration(seconds: 10),
        );
        final mgr = FakeMasterPasswordManager(
          unlockOutcomes: [TierUnlockAttempt.staged],
          initialStatus: initialLocked,
        );
        await _open(tester, manager: mgr);
        final l10n = S.of(tester.element(find.byType(UnlockDialog)));
        final unlockBtn = tester.widget<AppButton>(
          find.ancestor(
            of: find.text(l10n.unlock),
            matching: find.byWidgetPredicate((w) => w is AppButton),
          ),
        );
        expect(
          unlockBtn.onTap,
          isNull,
          reason:
              'A locked rate-limit status must collapse the primary '
              'button\'s onTap to null so submits are gated until the '
              'cooldown expires.',
        );
        // Drain the cooldown ticker so flutter_test does not trip the
        // pending-timer invariant on tear-down.
        await tester.pump(const Duration(seconds: 11));
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'a wrongSecret attempt that does not engage the cooldown leaves the '
      'Unlock button armed for an immediate retry — the dialog stays open '
      'and the wrong-password banner explains the failure',
      (tester) async {
        // Spec: a single wrong attempt with no rate-limit lock must
        // surface the wrong-password banner AND keep the Unlock button
        // tappable. This is the user-visible retry-on-typo loop. We
        // already cover the "banner shows" half; here we pin "button
        // remains armed" — non-null onTap, and a second attempt actually
        // reaches the manager.
        final mgr = FakeMasterPasswordManager(
          unlockOutcomes: [
            TierUnlockAttempt.wrongSecret,
            TierUnlockAttempt.staged,
          ],
        );
        bool? result;
        await tester.pumpWidget(
          _wrap(
            Builder(
              builder: (ctx) => TextButton(
                child: const Text('Open'),
                onPressed: () async {
                  result = await UnlockDialog.show(ctx, manager: mgr);
                },
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'first-typo');
        await tester.tap(find.text('Unlock'));
        await tester.pumpAndSettle();

        final l10n = S.of(tester.element(find.byType(UnlockDialog)));
        // Wrong-password banner present, no cooldown banner — limiter
        // stayed unlocked.
        expect(find.text(l10n.wrongMasterPassword), findsOneWidget);
        final unlockBtn = tester.widget<AppButton>(
          find.ancestor(
            of: find.text(l10n.unlock),
            matching: find.byWidgetPredicate((w) => w is AppButton),
          ),
        );
        expect(
          unlockBtn.onTap,
          isNotNull,
          reason:
              'A wrong attempt with no engaged cooldown must leave the '
              'primary button armed for an immediate retry.',
        );

        // Spec mirror: a second attempt actually flows through.
        await tester.enterText(find.byType(TextField), 'right-on-retry');
        await tester.tap(find.text('Unlock'));
        await tester.pumpAndSettle();
        expect(result, isTrue);
        expect(mgr.unlockAttemptCalls, hasLength(2));
      },
    );

    // covered by integration: full forgot-password wipe completion exercises
    // WipeAllService → real FRB recovery cascade + sessionCredentialCacheProvider
    // + configProvider.update. Unit-driving the magic-phrase confirm into the
    // armed destructive action would invoke the real wipe inside the test
    // process. The typed-name gate (enabled/disabled flag) is pinned by the
    // two tests above; the wipe-then-pop tail is integration-only.
  });
}
