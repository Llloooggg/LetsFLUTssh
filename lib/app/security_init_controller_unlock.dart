part of 'security_init_controller.dart';

/// Per-tier unlock flows + the L2 / L3 dialog scaffolding. Lives as
/// an extension on [SecurityInitController] so the methods reach the
/// private `_dialogs` / `_credentialsWereReset` / `_injectDatabase`
/// fields without exposing them publicly; `part of` joins the file
/// into the same library so library-private names stay reachable.
///
/// Contract: every flow either resolves the unlock (Rust-side
/// SecretStore stages the DB key, listener runs the post-unlock
/// cascade) or routes through the plaintext fallback via
/// [SecurityInitController._injectDatabase] so the app still launches
/// when the configured tier's vault is unreachable.
extension _UnlockFlows on SecurityInitController {
  Future<void> _unlockParanoid(MasterPasswordManager manager) async {
    if (!isMounted()) return;
    // Multi-attempt dialog: every submit fires a paired
    // `UnlockRequested` / `UnlockSucceeded`-or-`UnlockFailed`
    // through the `tier_unlock_paranoid` orchestrator (driven from
    // `manager.unlockAttempt`). Listener arms with `onlyUnlocked:
    // true` so per-attempt `Locked` events from wrong-password
    // retries don't resolve the wait; the dismiss-without-submit
    // branch resolves it via `cancelPending`.
    final listener = ref.read(tierUnlockedListenerProvider)..start();
    final unlockDone = listener.awaitNextUnlock(onlyUnlocked: true);
    final dialogResult = await _dialogs.showMasterPasswordUnlock(manager);
    if (dialogResult == true) {
      final result = await unlockDone.timeout(
        const Duration(seconds: 5),
        onTimeout: () => TierUnlockOutcome.failed,
      );
      if (result == TierUnlockOutcome.unlocked) {
        AppLogger.instance.log('Master password unlocked', name: 'App');
        return;
      }
      AppLogger.instance.log(
        'Paranoid dialog returned success but listener resolved $result',
        name: 'App',
        level: LogLevel.warn,
      );
    } else {
      listener.cancelPending();
      try {
        rust_orch.tierUnlockParanoidCancel();
      } catch (e) {
        AppLogger.instance.log(
          'tier_unlock_paranoid_cancel FRB unreachable: $e',
          name: 'TierMachine',
          level: LogLevel.warn,
        );
      }
    }
    _credentialsWereReset = true;
    await _injectDatabase();
    AppLogger.instance.log(
      'Master password reset — credentials cleared',
      name: 'App',
    );
  }

  Future<void> _unlockKeychain() async {
    // Production routes through `tier_unlock_orchestrator::unlock_keychain`
    // + `TierUnlockedListener`: orchestrator stages the keychain
    // key under `tier.unlock.key`, listener takes it + runs the
    // post-unlock cascade (caches, securityStateProvider, Rust DB,
    // tier persist). Plaintext fallback covers both the orchestrator-
    // returned PluginError (keychain entry missing) and the FRB-
    // unreachable case (flutter_test).
    try {
      final listener = ref.read(tierUnlockedListenerProvider)..start();
      final unlockDone = listener.awaitNextUnlock();
      final outcome = await rust_orch.tierUnlockKeychain();
      if (outcome is rust_orch.DbUnlockOutcome_Staged) {
        final result = await unlockDone.timeout(
          const Duration(seconds: 5),
          onTimeout: () => TierUnlockOutcome.failed,
        );
        if (result == TierUnlockOutcome.unlocked) {
          AppLogger.instance.log('Keychain key loaded (tier=L1)', name: 'App');
          return;
        }
        AppLogger.instance.log(
          'Keychain listener returned $result after Staged — '
          'falling through to plaintext fallback',
          name: 'App',
          level: LogLevel.warn,
        );
      }
      listener.cancelPending();
    } catch (e) {
      AppLogger.instance.log(
        'tier_unlock_keychain FRB unreachable: $e',
        name: 'App',
        level: LogLevel.warn,
      );
    }
    _credentialsWereReset = true;
    await _injectDatabase();
    AppLogger.instance.log(
      'L1 configured but keychain entry missing — plaintext fallback',
      name: 'App',
      level: LogLevel.warn,
    );
  }

  Future<void> _unlockKeychainWithPassword() async {
    final gate = ref.read(keychainPasswordGateProvider);
    if (!await gate.isConfigured()) {
      _credentialsWereReset = true;
      await _injectDatabase();
      AppLogger.instance.log(
        'L2 configured but gate state missing — plaintext fallback',
        name: 'App',
        level: LogLevel.warn,
      );
      return;
    }
    // Multi-attempt dialog routes through the orchestrator + listener
    // pair. Listener arms with `onlyUnlocked: true` so per-attempt
    // `UnlockFailed` → `Locked` events from the wrong-password retry
    // loop don't resolve the wait — the dialog handles the retry UI
    // and the dismiss/reset path resolves explicitly via
    // `cancelPending`.
    final listener = ref.read(tierUnlockedListenerProvider)..start();
    final unlockDone = listener.awaitNextUnlock(onlyUnlocked: true);
    var biometricAttempted = false;
    final vault = ref.read(biometricKeyVaultProvider);
    final bio = ref.read(biometricAuthProvider);
    if (await vault.isStored() && await bio.isAvailable()) {
      biometricAttempted = true;
      final ok = await _tryBiometricCommit(SecurityTier.keychainWithPassword);
      if (ok) {
        final result = await unlockDone.timeout(
          const Duration(seconds: 5),
          onTimeout: () => TierUnlockOutcome.failed,
        );
        if (result == TierUnlockOutcome.unlocked) {
          AppLogger.instance.log(
            'L2 keychain+password unlocked via biometrics',
            name: 'App',
          );
          return;
        }
        AppLogger.instance.log(
          'L2 biometric staged but listener returned $result — '
          'falling through to dialog',
          name: 'App',
          level: LogLevel.warn,
        );
      }
    }
    final dialogResult = await _showL2UnlockDialog(
      gate,
      autoTriggerBiometric: !biometricAttempted,
    );
    if (dialogResult == true) {
      final result = await unlockDone.timeout(
        const Duration(seconds: 5),
        onTimeout: () => TierUnlockOutcome.failed,
      );
      if (result == TierUnlockOutcome.unlocked) {
        AppLogger.instance.log('L2 keychain+password unlocked', name: 'App');
        return;
      }
      AppLogger.instance.log(
        'L2 dialog returned success but listener resolved $result — '
        'falling back to plaintext',
        name: 'App',
        level: LogLevel.warn,
      );
    } else {
      listener.cancelPending();
      // Dialog dismissed / reset / unrecoverable error. Fire the
      // cancel cascade so any half-state Unlocking transition
      // unwinds; idempotent on an already-Locked machine.
      try {
        rust_orch.tierUnlockKeychainWithPasswordCancel();
      } catch (e) {
        AppLogger.instance.log(
          'tier_unlock_keychain_with_password_cancel FRB unreachable: $e',
          name: 'TierMachine',
          level: LogLevel.warn,
        );
      }
    }
    await _injectDatabase();
    AppLogger.instance.log(
      'L2 reset — plaintext fallback',
      name: 'App',
      level: LogLevel.warn,
    );
  }

  Future<bool?> _showL2UnlockDialog(
    KeychainPasswordGate gate, {
    bool autoTriggerBiometric = true,
  }) async {
    final limiter = await gate.rateLimiter();
    if (!isMounted()) return null;
    return _showL2DialogSync(
      limiter,
      autoTriggerBiometric: autoTriggerBiometric,
    );
  }

  Future<bool?> _showL2DialogSync(
    PasswordRateLimiter? limiter, {
    bool autoTriggerBiometric = true,
  }) {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return Future.value(null);
    final l10n = S.of(ctx);
    return _dialogs.showTierSecretUnlock(
      ctx: ctx,
      labels: TierSecretUnlockLabels(
        title: l10n.l2UnlockTitle,
        hint: l10n.l2UnlockHint,
        inputLabel: l10n.password,
        wrongSecretLabel: l10n.l2WrongPassword,
      ),
      rateLimiter: limiter,
      verify: (password) async {
        // Routes through the `tier_unlock_keychain_with_password`
        // orchestrator: gate verify + keychain key read in one FRB
        // hop, bytes staged in the SecretStore, cascade emitted.
        // FRB-unreachable contexts (flutter_test) surface as
        // `TierUnlockAttempt.error` so the dialog closes + the
        // caller routes through the plaintext fallback in
        // `_unlockKeychainWithPassword`.
        try {
          final outcome = await rust_orch.tierUnlockKeychainWithPassword(
            password: password,
          );
          return mapUnlockOutcome(outcome);
        } catch (e) {
          AppLogger.instance.log(
            'tier_unlock_keychain_with_password FRB unreachable: $e',
            name: 'App',
            level: LogLevel.warn,
          );
          return TierUnlockAttempt.error;
        }
      },
      biometricUnlock: () =>
          _tryBiometricCommit(SecurityTier.keychainWithPassword),
      autoTriggerBiometric: autoTriggerBiometric,
      onReset: () async {
        await WipeAllService(
          credentialCacheEvict: ref
              .read(sessionCredentialCacheProvider)
              .evictAll,
        ).wipeAll();
        _credentialsWereReset = true;
        requestSecurityReinit(ref);
      },
    );
  }

  Future<void> _unlockHardware() async {
    final vault = ref.read(hardwareTierVaultProvider);
    if (!await vault.isStored()) {
      _credentialsWereReset = true;
      await _injectDatabase();
      AppLogger.instance.log(
        'L3 configured but vault state missing — plaintext fallback',
        name: 'App',
        level: LogLevel.warn,
      );
      return;
    }
    final mods = ref.read(configProvider).security?.modifiers;
    final listener = ref.read(tierUnlockedListenerProvider)..start();
    final unlockDone = listener.awaitNextUnlock(onlyUnlocked: true);
    if (mods != null && !mods.password) {
      // Passwordless variant — vault was sealed without a user
      // secret. Routes through `tier_unlock_hardware(null)` which
      // fans out to the platform vault via the prompt registry +
      // stages bytes in the SecretStore. FRB-unreachable contexts
      // (flutter_test) skip straight to the plaintext fallback.
      try {
        final outcome = await rust_orch.tierUnlockHardware();
        if (outcome is rust_orch.DbUnlockOutcome_Staged) {
          final result = await unlockDone.timeout(
            const Duration(seconds: 5),
            onTimeout: () => TierUnlockOutcome.failed,
          );
          if (result == TierUnlockOutcome.unlocked) {
            AppLogger.instance.log(
              'L3 hardware-vault unlocked (passwordless)',
              name: 'App',
            );
            return;
          }
          AppLogger.instance.log(
            'L3 passwordless listener returned $result after Staged',
            name: 'App',
            level: LogLevel.warn,
          );
        }
      } catch (e) {
        AppLogger.instance.log(
          'tier_unlock_hardware (passwordless) FRB unreachable: $e',
          name: 'App',
          level: LogLevel.warn,
        );
      }
      listener.cancelPending();
      _credentialsWereReset = true;
      await _injectDatabase();
      AppLogger.instance.log(
        'L3 passwordless unseal failed — plaintext fallback',
        name: 'App',
        level: LogLevel.warn,
      );
      return;
    }
    var biometricAttempted = false;
    final vault2 = ref.read(biometricKeyVaultProvider);
    final bio = ref.read(biometricAuthProvider);
    if (await vault2.isStored() && await bio.isAvailable()) {
      biometricAttempted = true;
      final ok = await _tryBiometricCommit(SecurityTier.hardware);
      if (ok) {
        final result = await unlockDone.timeout(
          const Duration(seconds: 5),
          onTimeout: () => TierUnlockOutcome.failed,
        );
        if (result == TierUnlockOutcome.unlocked) {
          AppLogger.instance.log(
            'L3 hardware-vault unlocked via biometrics',
            name: 'App',
          );
          return;
        }
        AppLogger.instance.log(
          'L3 biometric staged but listener returned $result',
          name: 'App',
          level: LogLevel.warn,
        );
      }
    }
    final dialogResult = await _showL3UnlockDialog(
      mods,
      autoTriggerBiometric: !biometricAttempted,
    );
    if (dialogResult == true) {
      final result = await unlockDone.timeout(
        const Duration(seconds: 5),
        onTimeout: () => TierUnlockOutcome.failed,
      );
      if (result == TierUnlockOutcome.unlocked) {
        AppLogger.instance.log('L3 hardware-vault unlocked', name: 'App');
        return;
      }
      AppLogger.instance.log(
        'L3 dialog returned success but listener resolved $result',
        name: 'App',
        level: LogLevel.warn,
      );
    } else {
      listener.cancelPending();
      // Dialog dismissed / reset / unrecoverable error. Fire the
      // cancel cascade so any half-state Unlocking unwinds.
      try {
        rust_orch.tierUnlockHardwareCancel();
      } catch (e) {
        AppLogger.instance.log(
          'tier_unlock_hardware_cancel FRB unreachable: $e',
          name: 'TierMachine',
          level: LogLevel.warn,
        );
      }
    }
    await _injectDatabase();
    AppLogger.instance.log(
      'L3 reset — plaintext fallback',
      name: 'App',
      level: LogLevel.warn,
    );
  }

  Future<bool?> _showL3UnlockDialog(
    SecurityTierModifiers? mods, {
    bool autoTriggerBiometric = true,
  }) async {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return false;
    final l10n = S.of(ctx);
    final limiter = HardwareRateLimiter();
    return _dialogs.showTierSecretUnlock(
      ctx: ctx,
      labels: TierSecretUnlockLabels(
        title: l10n.l3UnlockTitle,
        hint: l10n.l3UnlockHint,
        inputLabel: l10n.pinLabel,
        wrongSecretLabel: l10n.l3WrongPin,
      ),
      rateLimiter: limiter,
      verify: (pin) async {
        // Routes through `tier_unlock_hardware(pin)` which fans
        // out to the platform vault via the prompt registry,
        // stages bytes in the SecretStore, emits the cascade.
        // FRB-unreachable contexts (flutter_test) surface as
        // `TierUnlockAttempt.error` so the dialog closes + the
        // caller routes through the plaintext fallback in
        // `_unlockHardware`.
        try {
          final outcome = await rust_orch.tierUnlockHardware(pin: pin);
          return mapUnlockOutcome(outcome);
        } catch (e) {
          AppLogger.instance.log(
            'tier_unlock_hardware FRB unreachable: $e',
            name: 'App',
            level: LogLevel.warn,
          );
          return TierUnlockAttempt.error;
        }
      },
      biometricUnlock: () => _tryBiometricCommit(SecurityTier.hardware),
      autoTriggerBiometric: autoTriggerBiometric,
      onReset: () async {
        await WipeAllService(
          credentialCacheEvict: ref
              .read(sessionCredentialCacheProvider)
              .evictAll,
        ).wipeAll();
        _credentialsWereReset = true;
        requestSecurityReinit(ref);
      },
    );
  }
}
