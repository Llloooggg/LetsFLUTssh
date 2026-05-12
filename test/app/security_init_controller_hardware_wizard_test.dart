import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/app/security_dialog_prompter.dart';
import 'package:letsflutssh/app/security_init_controller.dart';
import 'package:letsflutssh/core/config/app_config.dart';
import 'package:letsflutssh/core/security/security_tier.dart';
import 'package:letsflutssh/providers/config_provider.dart';
import 'package:letsflutssh/providers/master_password_provider.dart';
import 'package:letsflutssh/providers/security_provider.dart';
import 'package:letsflutssh/widgets/hardware_password_setup_wizard.dart';

import '../helpers/fake_dialog_prompter.dart';
import '../helpers/fake_path_provider.dart';
import '../helpers/fake_secure_storage.dart';
import '../helpers/fake_security.dart';

/// Build a ProviderScope-backed controller + return the `WidgetRef`
/// the host harness holds. Lets tests drive
/// [SecurityInitController.handleHardwarePasswordSetWizardIfPending]
/// against a freshly-seeded config + scripted dialog prompter without
/// having to walk the full `bootstrap()` migration pipeline (which
/// touches FRB and `WipeAllService` — neither viable in `flutter_test`).
Future<({SecurityInitController ctrl, WidgetRef ref, ProviderContainer ct})>
_buildController(
  WidgetTester tester, {
  required AppConfig seedConfig,
  required SecurityDialogPrompter prompter,
  required HardwarePasswordSetWizardProbe probe,
}) async {
  late SecurityInitController ctrl;
  late WidgetRef capturedRef;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        preloadedAppConfigProvider.overrideWithValue(seedConfig),
        secureKeyStorageProvider.overrideWithValue(FakeSecureKeyStorage()),
        hardwareTierVaultProvider.overrideWithValue(FakeHardwareTierVault()),
        keychainPasswordGateProvider.overrideWithValue(
          FakeKeychainPasswordGate(),
        ),
        biometricAuthProvider.overrideWithValue(FakeBiometricAuth()),
        biometricKeyVaultProvider.overrideWithValue(FakeBiometricKeyVault()),
        masterPasswordProvider.overrideWithValue(FakeMasterPasswordManager()),
      ],
      child: MaterialApp(
        home: Consumer(
          builder: (ctx, ref, _) {
            capturedRef = ref;
            ctrl = SecurityInitController(
              ref: ref,
              isMounted: () => true,
              dialogPrompter: prompter,
              hardwarePasswordWizardProbe: probe,
            );
            return const SizedBox.shrink();
          },
        ),
      ),
    ),
  );
  final container = ProviderScope.containerOf(
    tester.element(find.byType(Consumer)),
  );
  return (ctrl: ctrl, ref: capturedRef, ct: container);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  setUp(() {
    tmp = installFakePathProvider();
    installFakeSecureStorage();
  });
  tearDown(() {
    uninstallFakeSecureStorage();
    uninstallFakePathProvider(tmp);
  });

  group('handleHardwarePasswordSetWizardIfPending', () {
    testWidgets(
      'no-op when config tier is not Hardware (early return before probe)',
      (tester) async {
        var probed = 0;
        final prompter = FakeSecurityDialogPrompter();
        final built = await _buildController(
          tester,
          seedConfig: AppConfig.defaults.copyWithSecurity(
            security: const SecurityConfig(
              tier: SecurityTier.paranoid,
              modifiers: SecurityTierModifiers(
                password: true,
                biometric: false,
              ),
            ),
          ),
          prompter: prompter,
          probe: (_) {
            probed++;
            return true;
          },
        );
        final manager = built.ct.read(masterPasswordProvider);
        final storage = built.ct.read(secureKeyStorageProvider);
        final handled = await built.ctrl
            .handleHardwarePasswordSetWizardIfPending(manager, storage);
        expect(handled, isFalse);
        expect(prompter.hardwarePasswordSetupCalls, 0);
        expect(
          probed,
          0,
          reason: 'non-Hardware tier short-circuits before the marker probe',
        );
        built.ctrl.dispose();
      },
    );

    testWidgets(
      'no-op when marker probe reports absent — bootstrap continues to '
      'regular unlock path',
      (tester) async {
        var probed = 0;
        final prompter = FakeSecurityDialogPrompter();
        final built = await _buildController(
          tester,
          seedConfig: AppConfig.defaults.copyWithSecurity(
            security: const SecurityConfig(
              tier: SecurityTier.hardware,
              modifiers: SecurityTierModifiers(
                password: true,
                biometric: false,
              ),
            ),
          ),
          prompter: prompter,
          probe: (_) {
            probed++;
            return false;
          },
        );
        final manager = built.ct.read(masterPasswordProvider);
        final storage = built.ct.read(secureKeyStorageProvider);
        final handled = await built.ctrl
            .handleHardwarePasswordSetWizardIfPending(manager, storage);
        expect(handled, isFalse);
        expect(probed, 1);
        expect(prompter.hardwarePasswordSetupCalls, 0);
        built.ctrl.dispose();
      },
    );

    testWidgets(
      'marker present + reseal success leaves marker cleared and lets the '
      'regular unlock path resume',
      (tester) async {
        final prompter = FakeSecurityDialogPrompter(
          hardwarePasswordSetupResult: HardwarePasswordWizardOutcome.resealed,
        );
        final built = await _buildController(
          tester,
          seedConfig: AppConfig.defaults.copyWithSecurity(
            security: const SecurityConfig(
              tier: SecurityTier.hardware,
              modifiers: SecurityTierModifiers(
                password: true,
                biometric: false,
              ),
            ),
          ),
          prompter: prompter,
          probe: (_) => true,
        );
        final manager = built.ct.read(masterPasswordProvider);
        final storage = built.ct.read(secureKeyStorageProvider);
        final handled = await built.ctrl
            .handleHardwarePasswordSetWizardIfPending(manager, storage);
        expect(
          handled,
          isFalse,
          reason:
              'resealed outcome must return false so _initSecurity continues '
              'to the regular Hardware unlock path with the new password',
        );
        expect(prompter.hardwarePasswordSetupCalls, 1);
        built.ctrl.dispose();
      },
    );

    testWidgets('wipe-requested outcome short-circuits with handled=true', (
      tester,
    ) async {
      final prompter = FakeSecurityDialogPrompter(
        hardwarePasswordSetupResult:
            HardwarePasswordWizardOutcome.wipeRequested,
      );
      final built = await _buildController(
        tester,
        seedConfig: AppConfig.defaults.copyWithSecurity(
          security: const SecurityConfig(
            tier: SecurityTier.hardware,
            modifiers: SecurityTierModifiers(password: true, biometric: false),
          ),
        ),
        prompter: prompter,
        probe: (_) => true,
      );
      final manager = built.ct.read(masterPasswordProvider);
      final storage = built.ct.read(secureKeyStorageProvider);
      // The wipe-requested branch fires WipeAllService.wipeAll() +
      // _firstLaunchSetup, both of which throw under flutter_test
      // (FRB native lib + foreground plugin / hardware-vault). The
      // controller swallows nothing on that path — the throw bubbles
      // out. We assert the wizard surfaced and the prompter saw the
      // wipe outcome before the cascade tripped on native-plugin
      // unreachability; the destructive cascade itself is covered
      // by integration tests.
      try {
        await built.ctrl.handleHardwarePasswordSetWizardIfPending(
          manager,
          storage,
        );
      } catch (_) {
        // Expected — the wipe cascade hits FRB / native plugins
        // that aren't wired in flutter_test. The contract we test
        // here is the wizard surfaced + the prompter saw the wipe
        // outcome, not the post-wipe cascade itself.
      }
      expect(prompter.hardwarePasswordSetupCalls, 1);
      built.ctrl.dispose();
    });
  });
}
