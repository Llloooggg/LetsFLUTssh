part of 'security_init_controller.dart';

/// First-launch wizard flows — choose a tier, run the matching
/// orchestrator dispatch + listener, fall back to the pure-Dart
/// pipeline when the FRB layer is unreachable (flutter_test). Lives
/// as an extension on [SecurityInitController] so the methods reach
/// the private `_dialogs` / `_injectDatabase` / `isMounted` slots
/// without exposing them publicly; `part of` joins the file into
/// the same library so library-private names stay reachable.
extension _FirstLaunchFlows on SecurityInitController {
  Future<void> _firstLaunchSetup(
    MasterPasswordManager manager,
    SecureKeyStorage keyStorage,
  ) async {
    if (!isMounted()) return;
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;

    var caps = await ref.read(securityCapabilitiesProvider.future);
    if (!isMounted()) return;

    if (plat.isMacosPlatform &&
        !caps.keychainAvailable &&
        caps.hardwareProbeCode == 'macosSigningIdentityMissing') {
      final updatedCaps = await _offerMacosSelfSign(caps);
      if (!isMounted()) return;
      caps = updatedCaps;
    }

    if (caps.keychainAvailable) {
      final ok = await _autoSetupKeychain(keyStorage);
      if (ok) {
        _queueFirstLaunchBanner(caps);
        return;
      }
      AppLogger.instance.log(
        'First launch: keychain probe said available but write failed — '
        'retrying through the manual wizard with T1 greyed out',
        name: 'App',
        level: LogLevel.warn,
      );
      caps = caps.copyWith(keychainAvailable: false);
    }

    final fallbackCtx = navigatorKey.currentContext;
    if (fallbackCtx == null || !fallbackCtx.mounted) return;
    final result = await _dialogs.showFirstLaunchWizard(fallbackCtx);
    if (!isMounted()) return;
    await _applyFirstLaunchWizardResult(
      result: result,
      manager: manager,
      keyStorage: keyStorage,
    );
  }

  Future<SecurityCapabilities> _offerMacosSelfSign(
    SecurityCapabilities caps,
  ) async {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return caps;
    final l10n = S.of(ctx);
    final accepted = await AppDialog.show<bool>(
      ctx,
      barrierDismissible: false,
      builder: (d) => AppDialog(
        title: l10n.securityMacosOfferTitle,
        dismissible: false,
        content: Text(
          l10n.securityMacosOfferBody,
          style: TextStyle(fontSize: AppFonts.md, color: AppTheme.fg),
        ),
        actions: [
          AppButton.secondary(
            label: l10n.securityMacosOfferDecline,
            onTap: () => Navigator.pop(d, false),
          ),
          AppButton.primary(
            label: l10n.securityMacosOfferAccept,
            icon: Icons.vpn_key,
            onTap: () => Navigator.pop(d, true),
          ),
        ],
      ),
    );
    if (accepted != true) {
      return caps.copyWith(
        keychainAvailable: false,
        hardwareVaultAvailable: false,
      );
    }
    try {
      final svc = ref.read(resignServiceProvider);
      await svc.ensureIdentity();
      final bundle = Directory(
        Platform.resolvedExecutable,
      ).parent.parent.parent;
      await svc.resignBundle(appBundle: bundle);
      await ref
          .read(configProvider.notifier)
          .update((c) => c.copyWithSecurity(securityProbeCache: null));
      ref.invalidate(securityCapabilitiesProvider);
      return await ref.read(securityCapabilitiesProvider.future);
    } catch (e) {
      AppLogger.instance.log(
        'macOS self-sign offer: failed to re-sign — falling back to reduced wizard',
        name: 'App',
        error: e,
      );
      return caps.copyWith(
        keychainAvailable: false,
        hardwareVaultAvailable: false,
      );
    }
  }

  Future<void> _applyFirstLaunchWizardResult({
    required SecuritySetupResult result,
    required MasterPasswordManager manager,
    required SecureKeyStorage keyStorage,
  }) async {
    switch (result.tier) {
      case SecurityTier.paranoid:
        await _firstLaunchParanoid(result, manager);
      case SecurityTier.hardware:
        await _firstLaunchHardware(result.takePin(), result.modifiers);
      case SecurityTier.keychainWithPassword:
        await _firstLaunchKeychainWithPassword(
          keyStorage: keyStorage,
          shortPassword: result.takeShortPassword(),
          modifiers: result.modifiers,
        );
      case SecurityTier.keychain:
        await _firstLaunchKeychain(result, keyStorage);
      case SecurityTier.plaintext:
        final ok = await _runFirstLaunchOrchestrator(
          tier: SecurityTier.plaintext,
          dispatch: () async {
            rust_orch.tierFirstLaunchPlaintext();
            return true;
          },
        );
        if (!ok) {
          // Orchestrator unreachable — fall back to direct inject.
          await _injectDatabase();
        }
        AppLogger.instance.log(
          'First launch: plaintext mode (L0)',
          name: 'App',
        );
    }
  }

  Future<void> _firstLaunchParanoid(
    SecuritySetupResult result,
    MasterPasswordManager manager,
  ) async {
    final password = result.takeMasterPassword();
    if (password == null) {
      await _injectDatabase();
      return;
    }
    final ok = await _runFirstLaunchOrchestrator(
      tier: SecurityTier.paranoid,
      modifiers: result.modifiers,
      dispatch: () async {
        final outcome = await rust_orch.tierFirstLaunchParanoid(
          password: password,
        );
        return outcome is rust_orch.DbUnlockOutcome_Staged;
      },
    );
    if (ok) {
      AppLogger.instance.log(
        'First launch: master password (Paranoid) enabled',
        name: 'App',
      );
      return;
    }
    // Orchestrator unreachable / staging failed — fall back to the
    // pure-Dart manager.enable path so flutter_test contexts (no FRB
    // native lib) still resolve.
    final key = await manager.enable(password);
    await _injectDatabase(
      key: key,
      level: SecurityTier.paranoid,
      modifiers: result.modifiers,
    );
    AppLogger.instance.log(
      'First launch: master password (Paranoid) enabled (fallback)',
      name: 'App',
    );
  }

  Future<void> _firstLaunchKeychain(
    SecuritySetupResult result,
    SecureKeyStorage keyStorage,
  ) async {
    if (!result.keychainAvailable) {
      await _injectDatabase();
      return;
    }
    final ok = await _runFirstLaunchOrchestrator(
      tier: SecurityTier.keychain,
      modifiers: result.modifiers,
      dispatch: () async {
        final outcome = await rust_orch.tierFirstLaunchKeychain();
        return outcome is rust_orch.DbUnlockOutcome_Staged;
      },
    );
    if (ok) {
      AppLogger.instance.log(
        'First launch: keychain encryption enabled',
        name: 'App',
      );
      return;
    }
    // Orchestrator unreachable / write failed — fall back to direct
    // Dart pipeline so flutter_test contexts still resolve.
    final key = rust_crypto.cryptoAesGcmRandomKey();
    final stored = await keyStorage.writeKey(key);
    if (stored) {
      await _injectDatabase(
        key: key,
        level: SecurityTier.keychain,
        modifiers: result.modifiers,
      );
      AppLogger.instance.log(
        'First launch: keychain encryption enabled (fallback)',
        name: 'App',
      );
    } else {
      await _injectDatabase();
      AppLogger.instance.log(
        'First launch: keychain write failed, falling back to plaintext',
        name: 'App',
        level: LogLevel.warn,
      );
    }
  }

  Future<bool> _autoSetupKeychain(SecureKeyStorage keyStorage) async {
    final ok = await _runFirstLaunchOrchestrator(
      tier: SecurityTier.keychain,
      dispatch: () async {
        final outcome = await rust_orch.tierFirstLaunchKeychain();
        return outcome is rust_orch.DbUnlockOutcome_Staged;
      },
    );
    if (ok) {
      AppLogger.instance.log(
        'First launch: auto-selected T1 (keychain)',
        name: 'App',
      );
      return true;
    }
    // Orchestrator unreachable / write failed — fall back to direct
    // Dart pipeline.
    final key = rust_crypto.cryptoAesGcmRandomKey();
    final stored = await keyStorage.writeKey(key);
    if (stored) {
      await _injectDatabase(key: key, level: SecurityTier.keychain);
      AppLogger.instance.log(
        'First launch: auto-selected T1 (keychain, fallback)',
        name: 'App',
      );
      return true;
    }
    AppLogger.instance.log(
      'First launch: auto-select T1 keychain write rejected — '
      'leaving DB uninitialised for the wizard fallback',
      name: 'App',
      level: LogLevel.warn,
    );
    return false;
  }

  /// Pre-write the SecurityConfig so the listener's
  /// `_persistSecurityTier` no-ops (existing modifiers match), arm
  /// the listener, dispatch the first-launch orchestrator, await
  /// the cascade. Returns true on success, false on orchestrator
  /// failure / FRB unreachable so the caller takes the Dart-side
  /// fallback.
  Future<bool> _runFirstLaunchOrchestrator({
    required SecurityTier tier,
    SecurityTierModifiers? modifiers,
    required Future<bool> Function() dispatch,
  }) async {
    final resolved = modifiers ?? SecurityTierModifiers.defaults;
    final cfg = SecurityConfig(tier: tier, modifiers: resolved);
    await ref
        .read(configProvider.notifier)
        .update((c) => c.copyWithSecurity(security: cfg));
    final listener = ref.read(tierUnlockedListenerProvider)..start();
    final unlockDone = listener.awaitNextUnlock();
    bool staged;
    try {
      staged = await dispatch();
    } catch (e) {
      listener.cancelPending();
      AppLogger.instance.log(
        'First launch orchestrator FRB unreachable for $tier: $e',
        name: 'App',
        level: LogLevel.warn,
      );
      return false;
    }
    if (!staged) {
      listener.cancelPending();
      AppLogger.instance.log(
        'First launch orchestrator returned non-staged for $tier',
        name: 'App',
        level: LogLevel.warn,
      );
      return false;
    }
    final result = await unlockDone.timeout(
      const Duration(seconds: 5),
      onTimeout: () => TierUnlockOutcome.failed,
    );
    if (result == TierUnlockOutcome.unlocked) return true;
    AppLogger.instance.log(
      'First launch listener returned $result after Staged for $tier',
      name: 'App',
      level: LogLevel.warn,
    );
    return false;
  }

  void _queueFirstLaunchBanner(SecurityCapabilities caps) {
    ref
        .read(firstLaunchBannerProvider.notifier)
        .set(
          FirstLaunchBannerData(
            activeTier: SecurityTier.keychain,
            hardwareUpgradeAvailable: caps.hardwareVaultAvailable,
            hardwareUnavailableReason: caps.hardwareVaultAvailable
                ? null
                : defaultHardwareUnavailableReason(),
          ),
        );
  }

  Future<void> _firstLaunchKeychainWithPassword({
    required SecureKeyStorage keyStorage,
    required String? shortPassword,
    SecurityTierModifiers? modifiers,
  }) async {
    if (shortPassword == null || shortPassword.isEmpty) {
      await _injectDatabase();
      return;
    }
    final ok = await _runFirstLaunchOrchestrator(
      tier: SecurityTier.keychainWithPassword,
      modifiers: modifiers,
      dispatch: () async {
        final outcome = await rust_orch.tierFirstLaunchKeychainWithPassword(
          password: shortPassword,
        );
        return outcome is rust_orch.DbUnlockOutcome_Staged;
      },
    );
    if (ok) {
      AppLogger.instance.log(
        'First launch: keychain+password (L2) enabled',
        name: 'App',
      );
      return;
    }
    // Orchestrator unreachable / staging failed — fall back to the
    // pure-Dart pipeline so flutter_test contexts still resolve.
    final gate = ref.read(keychainPasswordGateProvider);
    await gate.setPassword(shortPassword);
    final key = rust_crypto.cryptoAesGcmRandomKey();
    final stored = await keyStorage.writeKey(key);
    if (stored) {
      await _injectDatabase(
        key: key,
        level: SecurityTier.keychainWithPassword,
        modifiers: modifiers,
      );
      AppLogger.instance.log(
        'First launch: keychain+password (L2) enabled (fallback)',
        name: 'App',
      );
      return;
    }
    await gate.clear();
    await _injectDatabase();
    AppLogger.instance.log(
      'First launch: L2 keychain write failed — plaintext fallback',
      name: 'App',
      level: LogLevel.warn,
    );
  }

  Future<void> _firstLaunchHardware(
    String? pin, [
    SecurityTierModifiers? modifiers,
  ]) async {
    final ok = await _runFirstLaunchOrchestrator(
      tier: SecurityTier.hardware,
      modifiers: modifiers,
      dispatch: () async {
        final outcome = await rust_orch.tierFirstLaunchHardware(pin: pin);
        return outcome is rust_orch.DbUnlockOutcome_Staged;
      },
    );
    if (ok) {
      AppLogger.instance.log(
        'First launch: hardware vault (L3) sealed',
        name: 'App',
      );
      return;
    }
    // Orchestrator unreachable / staging failed — fall back to the
    // pure-Dart pipeline so flutter_test contexts (no FRB native
    // lib) still resolve.
    final vault = ref.read(hardwareTierVaultProvider);
    final key = rust_crypto.cryptoAesGcmRandomKey();
    final stored = await vault.store(dbKey: key, pin: pin);
    if (stored) {
      await _injectDatabase(
        key: key,
        level: SecurityTier.hardware,
        modifiers: modifiers,
      );
      AppLogger.instance.log(
        'First launch: hardware vault (L3) sealed (fallback)',
        name: 'App',
      );
      return;
    }
    await _injectDatabase();
    AppLogger.instance.log(
      'First launch: hardware-vault seal failed — plaintext fallback',
      name: 'App',
      level: LogLevel.warn,
    );
  }
}
