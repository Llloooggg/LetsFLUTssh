import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/app/security_dialogs.dart';
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
}
