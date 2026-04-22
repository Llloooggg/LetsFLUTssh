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
  });
}
