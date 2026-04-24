import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/app/navigator_key.dart';
import 'package:letsflutssh/app/security_dialogs.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/widgets/db_corrupt_dialog.dart';
import 'package:letsflutssh/widgets/tier_reset_dialog.dart';

import '../helpers/fake_security.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('security_dialogs unmounted fallbacks', () {
    // These four helpers all resolve `navigatorKey.currentContext`
    // synchronously and return a sensible "do-nothing" value when the
    // navigator is not mounted yet. Cold-boot crash + teardown races
    // hit that branch; tests pin the contract so a refactor that
    // silently started to throw on null context could be caught
    // before release.

    test(
      'showTierResetDialog returns exitApp when navigator is unmounted',
      () async {
        final result = await showTierResetDialog();
        expect(result, TierResetChoice.exitApp);
      },
    );

    test(
      'showDbCorruptDialog returns exitApp when navigator is unmounted',
      () async {
        final result = await showDbCorruptDialog();
        expect(result, DbCorruptChoice.exitApp);
      },
    );

    test('localizedBiometricReason falls back to English literal when '
        'navigator is unmounted', () {
      expect(localizedBiometricReason(), 'Unlock LetsFLUTssh');
    });

    test('showUnlockDialog returns null when navigator is unmounted', () async {
      // Returning null here is load-bearing: the paranoid unlock
      // caller treats null as "user declined / reset" and flips the
      // credentialsWereReset flag for the next launch's toast. If
      // this path accidentally awaited a real dialog on a null
      // context, cold-boot would hang on a context that never
      // mounts.
      final result = await showUnlockDialog(FakeMasterPasswordManager());
      expect(result, isNull);
    });
  });

  group('security_dialogs — mounted navigator', () {
    // The unmounted cases above cover half the contract. With the
    // global navigatorKey wired to a real MaterialApp, each helper
    // must actually forward to its dialog's .show() factory and
    // return whatever the dialog produced. Pin the happy path so a
    // refactor that accidentally short-circuited the mounted branch
    // would not slip through.

    testWidgets('localizedBiometricReason reads the localized string', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          localizationsDelegates: const <LocalizationsDelegate<Object>>[
            S.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: S.supportedLocales,
          home: const Scaffold(body: SizedBox.shrink()),
        ),
      );
      final l10n = await S.delegate.load(const Locale('en'));
      // When the navigator is mounted, the helper must go through
      // S.of(ctx) — otherwise localised prompts would never appear,
      // even though the navigator is up.
      expect(localizedBiometricReason(), l10n.biometricUnlockPrompt);
    });
  });
}
