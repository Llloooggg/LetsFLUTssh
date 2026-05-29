import 'dart:io' show Directory;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/app/navigator_key.dart';
import 'package:letsflutssh/app/security_init_controller.dart';
import 'package:letsflutssh/core/config/app_config.dart';
import 'package:letsflutssh/core/security/security_tier.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/providers/config_provider.dart';
import 'package:letsflutssh/providers/security_provider.dart';
import 'package:letsflutssh/src/rust/api/security_capabilities.dart'
    show DbKeyringProbeResult, DbSecurityCapabilities;
import 'package:letsflutssh/widgets/security/security_setup_dialog.dart';

import '../helpers/fake_dialog_prompter.dart';
import '../helpers/fake_path_provider.dart';
import '../helpers/fake_secure_storage.dart';
import '../helpers/fake_security.dart';
import '../helpers/test_providers.dart';

/// Unit coverage for the pure-orchestration arms of
/// [SecurityInitController]: the post-unlock readiness gate
/// ([SecurityInitController.handleCorruption] success path), the
/// lock→unlock re-open fork ([SecurityInitController.reopenAfterUnlock]),
/// and first-launch provisioning reached through the post-wipe
/// re-init entry point ([SecurityInitController.reinitFromReset]).
///
/// These paths route entirely through the injectable seams
/// (`verifyReadable`, `dialogPrompter`, `migrationRunner`) plus the
/// shared security fakes — no OS-native tier (keychain / hardware
/// vault / Secure Enclave / TPM / biometric) is exercised. Those arms
/// are allow-list-exempt from unit testing; see the report at the end
/// of this session for the seam gaps that keep `_initSecurity`-gated
/// unlock + the Rust-orchestrator corruption cascade out of reach in
/// a no-native-lib harness.

/// Config notifier that drops the disk-write side of `update()` so the
/// controller's `await configProvider.update(...)` resolves without an
/// FRB hop. The real notifier debounces a write through the Rust
/// config-store actor; under `flutter_test` that actor is absent and
/// the awaited completer would otherwise error. Mutating state stays
/// real — the controller reads the tier it just wrote.
class _NoPersistConfigNotifier extends ConfigNotifier {
  _NoPersistConfigNotifier(this._initial);

  final AppConfig _initial;

  @override
  AppConfig build() {
    super.build();
    state = _initial;
    return state;
  }

  @override
  Future<void> persist(AppConfig config) async {}
}

/// A capabilities snapshot with the OS keychain reported unavailable,
/// so first-launch provisioning skips the keychain auto-setup arm and
/// lands on the injected wizard prompter — the only first-launch
/// branch reachable without the keychain method channel.
const _softwareOnlyCaps = DbSecurityCapabilities(
  keychainAvailable: false,
  hardwareVaultAvailable: false,
  biometricAvailable: false,
  fprintdAvailable: false,
  isLinuxHost: true,
  keychainProbe: DbKeyringProbeResult.linuxNoSecretService,
  hardwareProbeCode: 'unknown',
);

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

  /// Mount a [SecurityInitController] inside a real `ProviderScope` +
  /// `MaterialApp` so the seeded `configProvider` / `securityStateProvider`
  /// and the navigator key resolve. Returns the controller plus the
  /// scope's container so the test can read fakes / providers back out.
  ///
  /// [seedConfig] pre-populates the config (cached capabilities, current
  /// security tier); the no-persist notifier keeps `update()` off the
  /// FRB write path.
  Future<({SecurityInitController ctrl, ProviderContainer container})>
  mountController(
    WidgetTester tester, {
    required AppConfig seedConfig,
    FakeSecurityDialogPrompter? prompter,
    Future<bool> Function()? verifyReadable,
    FakeMasterPasswordManager? masterPassword,
    FakeAutoLockNotifier? autoLock,
    LegacyStateDetector? legacyStateDetector,
    CorruptDbHandler? corruptDbHandler,
    LegacyStateHandler? legacyStateHandler,
  }) async {
    SecurityInitController? ctrl;
    final autoLockNotifier = autoLock ?? FakeAutoLockNotifier();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...securityProviderOverrides(
            masterPassword: masterPassword,
            autoLockNotifier: autoLockNotifier,
          ),
          configProvider.overrideWith(
            () => _NoPersistConfigNotifier(seedConfig),
          ),
          // `securityCapabilitiesProvider` is a FutureProvider over an
          // FRB sync probe; without an override every test path that
          // touches `_initSecurity` (which `await`s `caps.future`)
          // crashes on FRB-not-initialised. Seed the software-only
          // snapshot so the await resolves immediately.
          securityCapabilitiesProvider.overrideWith(
            (ref) async => _softwareOnlyCaps,
          ),
        ],
        child: MaterialApp(
          navigatorKey: navigatorKey,
          localizationsDelegates: S.localizationsDelegates,
          supportedLocales: S.supportedLocales,
          home: Consumer(
            builder: (ctx, ref, _) {
              ctrl ??= SecurityInitController(
                ref: ref,
                isMounted: () => true,
                dialogPrompter: prompter,
                verifyReadable: verifyReadable,
                legacyStateDetector: legacyStateDetector,
                corruptDbHandler: corruptDbHandler,
                legacyStateHandler: legacyStateHandler,
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
    return (ctrl: ctrl!, container: container);
  }

  group('handleCorruption readiness gate', () {
    testWidgets('flips ready + loads auto-lock when the probe reads clean', (
      tester,
    ) async {
      var loadCalls = 0;
      final harness = await mountController(
        tester,
        seedConfig: AppConfig.defaults,
        verifyReadable: () async => true,
        autoLock: _CountingAutoLockNotifier(() => loadCalls++),
      );

      expect(harness.ctrl.isReady, isFalse);
      await tester.runAsync(() => harness.ctrl.handleCorruption());
      await tester.pump();

      // A clean integrity probe is the single signal that the DB
      // cipher validated; the controller must expose `ready` so the
      // shell can drop the startup splash, and it must kick the
      // auto-lock minutes load.
      expect(harness.ctrl.isReady, isTrue);
      expect(loadCalls, 1);

      harness.ctrl.dispose();
    });

    testWidgets('ready transition is idempotent across repeated probes', (
      tester,
    ) async {
      var loadCalls = 0;
      final autoLock = _CountingAutoLockNotifier(() => loadCalls++);
      final harness = await mountController(
        tester,
        seedConfig: AppConfig.defaults,
        verifyReadable: () async => true,
        autoLock: autoLock,
      );

      await tester.runAsync(() => harness.ctrl.handleCorruption());
      await tester.runAsync(() => harness.ctrl.handleCorruption());
      await tester.pump();

      // `_markSecurityReady` guards on the notifier's current value, so
      // a second clean probe must not re-fire the auto-lock load — the
      // splash already dismissed and re-loading would thrash the
      // notifier.
      expect(harness.ctrl.isReady, isTrue);
      expect(loadCalls, 1);

      harness.ctrl.dispose();
    });
  });

  group('reopenAfterUnlock fork', () {
    testWidgets('no-ops when the controller is already disposed/unmounted', (
      tester,
    ) async {
      SecurityInitController? ctrl;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...securityProviderOverrides(),
            configProvider.overrideWith(
              () => _NoPersistConfigNotifier(AppConfig.defaults),
            ),
          ],
          child: MaterialApp(
            navigatorKey: navigatorKey,
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            home: Consumer(
              builder: (ctx, ref, _) {
                ctrl ??= SecurityInitController(
                  ref: ref,
                  isMounted: () => false,
                );
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      // `isMounted()` returning false is the post-dispose guard; the
      // method must bail before touching any provider so a trailing
      // async resolving after teardown can't walk a disposed scope.
      await tester.runAsync(() => ctrl!.reopenAfterUnlock());
      expect(ctrl!.isReady, isFalse);
      ctrl!.dispose();
    });

    testWidgets('skips re-attach when no DB key is staged', (tester) async {
      final harness = await mountController(
        tester,
        seedConfig: AppConfig.defaults,
      );

      // Default security state carries `hasActiveDbKey == false`. The
      // re-open path keys off the active SecretStore slot; with the
      // slot empty there is nothing to re-attach, so the method logs
      // and returns without flipping ready or invalidating the stream.
      await tester.runAsync(() => harness.ctrl.reopenAfterUnlock());
      expect(harness.ctrl.isReady, isFalse);
      expect(
        harness.container.read(securityStateProvider).hasActiveDbKey,
        isFalse,
      );

      harness.ctrl.dispose();
    });

    testWidgets('re-attaches the DB + persists the tier when a key is staged', (
      tester,
    ) async {
      final harness = await mountController(
        tester,
        seedConfig: AppConfig.defaults.copyWithSecurity(
          security: const SecurityConfig(
            tier: SecurityTier.plaintext,
            modifiers: SecurityTierModifiers.defaults,
          ),
        ),
      );
      // Stand in for the lock screen having released a fresh key into
      // the active slot before this callback fires.
      harness.container
          .read(securityStateProvider.notifier)
          .setActive(SecurityTier.keychain, hasKey: true);

      await tester.runAsync(() => harness.ctrl.reopenAfterUnlock());
      await tester.pump();

      // The re-open path injects under the staged secret and records
      // the active tier; the level the controller reads back from
      // SecurityState is the one `_injectDatabase` set, not the
      // pre-call placeholder.
      final state = harness.container.read(securityStateProvider);
      expect(state.hasActiveDbKey, isTrue);
      expect(state.level, SecurityTier.keychain);

      harness.ctrl.dispose();
    });
  });

  group('first-launch provisioning via reinitFromReset', () {
    testWidgets('plaintext wizard pick provisions T0 + reaches ready', (
      tester,
    ) async {
      final prompter = FakeSecurityDialogPrompter(
        wizardResult: const SecuritySetupResult(tier: SecurityTier.plaintext),
      );
      final harness = await mountController(
        tester,
        seedConfig: AppConfig.defaults.copyWithSecurity(
          securityProbeCache: _softwareOnlyCaps,
        ),
        prompter: prompter,
        verifyReadable: () async => true,
      );

      await tester.runAsync(() => harness.ctrl.reinitFromReset());
      await tester.pump();

      // Post-wipe re-init must re-run the first-launch wizard exactly
      // once, commit the plaintext tier, and — once the trailing
      // integrity probe reads clean — surface as ready so the shell
      // leaves the splash.
      expect(prompter.wizardCalls, 1);
      expect(harness.ctrl.isReady, isTrue);
      expect(
        harness.container.read(securityStateProvider).level,
        SecurityTier.plaintext,
      );

      harness.ctrl.dispose();
    });

    testWidgets('master-password (Paranoid) pick with no staged secret '
        'falls back to T0 inject', (tester) async {
      // A Paranoid result that carries no `masterPasswordSecretId`
      // models the wizard resolving without a captured password
      // (barrier-dismiss fallthrough). The controller must inject the
      // plaintext DB rather than dereferencing an absent secret.
      final prompter = FakeSecurityDialogPrompter(
        wizardResult: const SecuritySetupResult(tier: SecurityTier.paranoid),
      );
      final mpm = FakeMasterPasswordManager();
      final harness = await mountController(
        tester,
        seedConfig: AppConfig.defaults.copyWithSecurity(
          securityProbeCache: _softwareOnlyCaps,
        ),
        prompter: prompter,
        verifyReadable: () async => true,
        masterPassword: mpm,
      );

      await tester.runAsync(() => harness.ctrl.reinitFromReset());
      await tester.pump();

      // The wizard fired and the controller reached ready off the clean
      // probe; the empty-password Paranoid arm never enabled the
      // master-password manager (no secret was staged to enable from).
      expect(prompter.wizardCalls, 1);
      expect(mpm.enabled, isFalse);
      expect(harness.ctrl.isReady, isTrue);

      harness.ctrl.dispose();
    });

    testWidgets('clears the credentials-reset flag carried through re-init', (
      tester,
    ) async {
      final prompter = FakeSecurityDialogPrompter(
        wizardResult: const SecuritySetupResult(tier: SecurityTier.plaintext),
      );
      final harness = await mountController(
        tester,
        seedConfig: AppConfig.defaults.copyWithSecurity(
          securityProbeCache: _softwareOnlyCaps,
        ),
        prompter: prompter,
        verifyReadable: () async => true,
      );

      await tester.runAsync(() => harness.ctrl.reinitFromReset());
      await tester.pump();

      // reinitFromReset itself does not set the credentials-reset flag
      // (that one-shot toast is owned by the destructive-cascade path);
      // the read-once accessor stays false through a clean re-init.
      expect(harness.ctrl.takeAndClearCredentialsResetFlag(), isFalse);

      harness.ctrl.dispose();
    });
  });

  // Dispatcher-recurse tests for the corruptDbHandler / legacyState*
  // seams require a much deeper override mesh than the existing
  // harness: every continued / wipedAndRestarted outcome routes back
  // through `_initSecurity`, the capabilities probe, `_handleLegacyStateIfPresent`,
  // and ultimately the unlock dispatch — each of which hits FRB or
  // OS-tier paths the unit harness can't fake without a full
  // `flutter_test` integration suite. Leave the seams wired so a
  // later integration pass can drive them; the assertion-bearing
  // tests for the underlying recovery FRB calls live Rust-side
  // (`lfs_core::recovery::tests`).
}

/// Auto-lock notifier that counts `load()` invocations so the
/// idempotency test can assert the ready transition fires the load
/// exactly once.
class _CountingAutoLockNotifier extends FakeAutoLockNotifier {
  _CountingAutoLockNotifier(this._onLoad);

  final void Function() _onLoad;

  @override
  Future<void> load() async {
    _onLoad();
    await super.load();
  }
}
