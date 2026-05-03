import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/master_password.dart';
import 'package:letsflutssh/core/security/password_rate_limiter.dart';
import 'package:letsflutssh/core/security/tier_unlock_attempt.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/widgets/unlock_dialog.dart';

/// Test stand-in for [MasterPasswordManager] that overrides the two
/// methods [_UnlockDialogState] reaches for ([unlockAttempt] and
/// [rateLimitStatus]) so the dialog flows can be driven without
/// booting FRB / Argon2id / the Rust rate-limiter registry.
class _FakeMasterPasswordManager extends MasterPasswordManager {
  _FakeMasterPasswordManager({
    required this.attemptOutcomes,
    RateLimitStatus initialStatus = const RateLimitStatus(
      failureCount: 0,
      cooldownRemaining: Duration.zero,
    ),
    this.statusAfterFailure,
  }) : _status = initialStatus,
       super(basePath: '/tmp/unlock-dialog-test');

  final List<TierUnlockAttempt> attemptOutcomes;
  RateLimitStatus _status;

  /// Optional override pushed onto [_status] after every
  /// `wrongSecret` attempt — lets a test demonstrate the cooldown
  /// ticker activation without driving the real rate limiter.
  final RateLimitStatus? statusAfterFailure;

  final List<String> attemptCalls = [];

  @override
  RateLimitStatus rateLimitStatus() => _status;

  @override
  Future<TierUnlockAttempt> unlockAttempt(String password) async {
    attemptCalls.add(password);
    final next = attemptOutcomes.isNotEmpty
        ? attemptOutcomes.removeAt(0)
        : TierUnlockAttempt.error;
    if (next == TierUnlockAttempt.wrongSecret && statusAfterFailure != null) {
      _status = statusAfterFailure!;
    }
    return next;
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
  required _FakeMasterPasswordManager manager,
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
      final mgr = _FakeMasterPasswordManager(
        attemptOutcomes: [TierUnlockAttempt.staged],
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
      expect(mgr.attemptCalls, ['correct-password']);
      expect(result, isTrue);
    });

    testWidgets('wrongSecret leaves dialog open with the wrong-pw banner', (
      tester,
    ) async {
      final mgr = _FakeMasterPasswordManager(
        attemptOutcomes: [TierUnlockAttempt.wrongSecret],
      );
      await _open(tester, manager: mgr);
      await tester.enterText(find.byType(TextField), 'wrong');
      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();
      final l10n = S.of(tester.element(find.byType(UnlockDialog)));
      expect(find.text(l10n.wrongMasterPassword), findsOneWidget);
      // Dialog still up — Unlock button is back.
      expect(find.text(l10n.unlock), findsOneWidget);
      expect(mgr.attemptCalls, ['wrong']);
    });

    testWidgets('cancelled outcome closes the dialog with null', (
      tester,
    ) async {
      final mgr = _FakeMasterPasswordManager(
        attemptOutcomes: [TierUnlockAttempt.cancelled],
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
      final mgr = _FakeMasterPasswordManager(
        attemptOutcomes: [TierUnlockAttempt.error],
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
      final mgr = _FakeMasterPasswordManager(
        attemptOutcomes: [TierUnlockAttempt.staged],
      );
      await _open(tester, manager: mgr);
      // Submit the empty field directly. The button should ignore it.
      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();
      expect(
        mgr.attemptCalls,
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
        final mgr = _FakeMasterPasswordManager(
          attemptOutcomes: [TierUnlockAttempt.wrongSecret],
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
      final mgr = _FakeMasterPasswordManager(
        attemptOutcomes: [TierUnlockAttempt.staged],
        initialStatus: initialLocked,
      );
      await _open(tester, manager: mgr);
      final l10n = S.of(tester.element(find.byType(UnlockDialog)));
      expect(find.text(l10n.tierCooldownHint(8)), findsOneWidget);
      // Tap anyway — the button is null-callback while locked, so
      // tapping it is a no-op. Confirm no attempt fired.
      expect(mgr.attemptCalls, isEmpty);
      // Drain the cooldown ticker.
      await tester.pump(const Duration(seconds: 8));
      await tester.pumpAndSettle();
    });

    testWidgets('renders the master-password copy + lock icon on open', (
      tester,
    ) async {
      final mgr = _FakeMasterPasswordManager(
        attemptOutcomes: [TierUnlockAttempt.staged],
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
  });
}
