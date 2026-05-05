part of 'settings_screen.dart';

/// Tier-apply pipeline — single Apply tap on the Settings security
/// ladder routes through here. Lives as an extension on
/// [_SecuritySectionState] so the methods reach `ref` / `mounted` /
/// the private `_tierName` helper without exposing them publicly;
/// `part of` joins the file into the same library so library-private
/// names stay reachable.
///
/// Contract: every transition rekeys the live database under the new
/// key (or drops to plaintext when the target is T0) inside
/// [SecurityTierSwitcher] so a mid-switch crash leaves the
/// `.tier-transition-pending` marker on disk; recovery happens at
/// next launch through `main._initSecurity`.
extension _TierApply on _SecuritySectionState {
  bool _isVerifiablePasswordDrop(SecurityTier current, SecurityTier next) =>
      isVerifiablePasswordDrop(current, next);

  /// Prompt for the current password before a password-dropping
  /// transition. Returns true to proceed, false to abort (user
  /// cancelled or typed the wrong password).
  Future<bool> _confirmCurrentPasswordIfDropping(
    SecurityTier current,
    SecurityTier next,
  ) async {
    if (!_isVerifiablePasswordDrop(current, next)) return true;
    final currentCtrl = TextEditingController();
    final String? entered;
    try {
      entered = await AppDialog.show<String>(
        context,
        builder: (ctx) => _EnableBiometricDialog(currentCtrl: currentCtrl),
      );
    } finally {
      currentCtrl.wipeAndClear();
      currentCtrl.dispose();
    }
    if (entered == null) return false;
    if (!mounted) return false;
    final ok = current == SecurityTier.paranoid
        ? await ref.read(masterPasswordProvider).verify(entered)
        : await ref.read(keychainPasswordGateProvider).verify(entered);
    if (!ok) {
      if (mounted) {
        Toast.show(
          context,
          message: S.of(context).currentPasswordIncorrect,
          level: ToastLevel.error,
        );
      }
      return false;
    }
    return true;
  }

  Future<void> _applyTierChange(SecuritySetupResult result) async {
    switch (result.tier) {
      case SecurityTier.plaintext:
        await _applyPlaintextTier(result);
      case SecurityTier.keychain:
        await _applyKeychainTier(result);
      case SecurityTier.keychainWithPassword:
        await _applyKeychainWithPasswordTier(result);
      case SecurityTier.hardware:
        await _applyHardwareTier(result);
      case SecurityTier.paranoid:
        await _applyParanoidTier(result);
    }
  }

  Future<void> _applyPlaintextTier(SecuritySetupResult result) async {
    await _applyAlwaysRekey(null, SecurityTier.plaintext, result.modifiers);
    await _runVaultClearPlan(SecurityTier.plaintext);
  }

  Future<void> _applyKeychainTier(SecuritySetupResult result) async {
    final keyStorage = ref.read(secureKeyStorageProvider);
    final key = rust_crypto.cryptoAesGcmRandomKey();
    final stored = await keyStorage.writeKey(key);
    if (!stored) throw StateError('keychain write failed');
    await _applyAlwaysRekey(key, SecurityTier.keychain, result.modifiers);
    await _runVaultClearPlan(SecurityTier.keychain);
  }

  Future<void> _applyKeychainWithPasswordTier(
    SecuritySetupResult result,
  ) async {
    final short = result.takeShortPassword();
    if (short == null || short.isEmpty) {
      throw StateError('short password missing');
    }
    final keyStorage = ref.read(secureKeyStorageProvider);
    final gate = ref.read(keychainPasswordGateProvider);
    await gate.setPassword(short);
    final key = rust_crypto.cryptoAesGcmRandomKey();
    final stored = await keyStorage.writeKey(key);
    if (!stored) {
      await gate.clear();
      throw StateError('keychain write failed');
    }
    await _applyAlwaysRekey(
      key,
      SecurityTier.keychainWithPassword,
      result.modifiers,
    );
    await _runVaultClearPlan(SecurityTier.keychainWithPassword);
  }

  Future<void> _applyHardwareTier(SecuritySetupResult result) async {
    // Hardware tier now accepts a passwordless seal: when the
    // wizard returns `pin == null` (user left the password
    // modifier off for T2) the vault derives an empty auth value
    // and seals under SE/TPM isolation alone. The modifiers
    // snapshot `mods.password` stays the source of truth for
    // later unlock flows, so persisting it alongside the tier
    // keeps the read side in sync.
    final hwVault = ref.read(hardwareTierVaultProvider);
    final key = rust_crypto.cryptoAesGcmRandomKey();
    final sealed = await hwVault.store(dbKey: key, pin: result.takePin());
    if (!sealed) throw StateError('hardware seal failed');
    await _applyAlwaysRekey(key, SecurityTier.hardware, result.modifiers);
    await _runVaultClearPlan(SecurityTier.hardware);
  }

  Future<void> _applyParanoidTier(SecuritySetupResult result) async {
    final pw = result.takeMasterPassword();
    if (pw == null || pw.isEmpty) {
      throw StateError('master password missing');
    }
    final manager = ref.read(masterPasswordProvider);
    final key = await manager.enable(pw);
    await _applyAlwaysRekey(key, SecurityTier.paranoid, result.modifiers);
    await _runVaultClearPlan(SecurityTier.paranoid);
  }

  /// Drive the per-target vault clear matrix from
  /// [tierVaultClearPlanFor]. The matrix flips off the slot the
  /// apply method just wrote into so the commit isn't immediately
  /// undone, and every other vault clears verbatim.
  Future<void> _runVaultClearPlan(SecurityTier target) async {
    final plan = tierVaultClearPlanFor(target);
    if (plan.clearKeychainKey) {
      await ref.read(secureKeyStorageProvider).deleteKey();
    }
    if (plan.clearKeychainGate) {
      await ref.read(keychainPasswordGateProvider).clear();
    }
    if (plan.clearHardwareVault) {
      await ref.read(hardwareTierVaultProvider).clear();
    }
    if (plan.clearMasterPassword) {
      final manager = ref.read(masterPasswordProvider);
      if (await manager.isEnabled()) await manager.disable();
    }
    if (plan.clearBiometricVault) {
      await ref.read(biometricKeyVaultProvider).clear();
    }
  }

  /// Rekey the live database under [key] (or convert to plaintext
  /// when [key] is null) and flip `securityStateProvider` to the new
  /// [level]. Single caller: `_applyTierChange`, which runs this
  /// *after* it has already wrapped the new key into the target
  /// tier's vault — so the on-disk wrapper and the DB cipher always
  /// move together.
  ///
  /// Routes the rekey through `SecurityTierSwitcher` so a mid-switch
  /// crash leaves the `.tier-transition-pending` marker on disk; the
  /// next launch logs and clears it in `main._initSecurity` before
  /// falling through to the standard unlock path.
  Future<void> _applyAlwaysRekey(
    Uint8List? key,
    SecurityTier level, [
    SecurityTierModifiers? modifiers,
  ]) async {
    final resolvedMods = modifiers ?? SecurityTierModifiers.defaults;
    // Marker payload carries tier + modifiers so a crash-recovery
    // path can reconstruct the target config and drive the right
    // unlock prompt (password? biometric? no gate?) instead of
    // falling back to whatever the enum alone suggests. JSON shape
    // lives in `security_section_logic.buildTierMarkerPayload`.
    final markerPayload = buildTierMarkerPayload(level, resolvedMods);
    // Bind the constructor-time callback to the supplied key. The
    // tier-secret unlock dialog routes the freshly-derived key here,
    // so the override path uses the user's key (not a fresh random
    // one). A fresh switcher instance per call is fine — the marker
    // file is the authoritative state, not the instance.
    final switcher = SecurityTierSwitcher(
      keyFactory: () => key ?? Uint8List(0),
    );

    if (key == null) {
      // Plaintext target — no rekey to run, no key for the vault to
      // wrap. Just clear the marker (in case a stale one is on
      // disk) and flip the provider so consumers stop holding the
      // previous key.
      try {
        await switcher.clearMarker();
        ref.read(securityStateProvider.notifier).clearEncryption();
      } catch (_) {}
      return;
    }

    await switcher.switchTier(
      targetMarkerPayload: markerPayload,
      applyWrapper: (_) async {
        // `key != null` guaranteed by the early return above.
        ref.read(securityStateProvider.notifier).set(level, key);
      },
      persistConfig: (_) async {
        // Persist tier + modifiers atomically inside the switch so a
        // crash after rekey but before config-write does not leave
        // the DB on the new cipher with the old tier label in
        // config.json (the legacy main.dart path only persisted on
        // provider flip and dropped the modifier field).
        final existing = ref.read(configProvider).security;
        final next = SecurityConfig(tier: level, modifiers: resolvedMods);
        if (existing == next) return;
        await ref
            .read(configProvider.notifier)
            .update((cfg) => cfg.copyWithSecurity(security: next));
      },
      clearPrevious: () async {
        // Previous-tier cleanup (biometric vault clear, keychain
        // delete, credentials.kdf remove) is handled by the
        // specific enable/disable/change/remove methods that call
        // into `_applyAlwaysRekey`.
      },
    );
  }
}
