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
///
/// Dart-vs-Rust split for this file:
/// - **Dart-side** (here): user-confirmation prompts (current-password
///   re-verify, wipe-on-exit controllers), Riverpod provider lookups
///   (`masterPasswordProvider`, `keychainPasswordGateProvider`,
///   `hardwareTierVaultProvider`, `secureKeyStorageProvider`,
///   `biometricKeyVaultProvider`), the per-tier dispatch on the
///   `SecurityTier` enum + modifier flags, and the toast/UI feedback
///   after a finished transition.
/// - **Rust-side** (`lfs_core::security`, reached through the
///   `apply*Tier` helpers in `core/security/security_section_logic.dart`
///   and the FRB shims under `rust/crates/lfs_frb/src/api/`): the
///   actual key derivation, the AES-GCM wrap / unwrap of the DB
///   master key, the rekey of the live rusqlite database under the
///   new key, the persistent `.tier-transition-pending` marker, and
///   the `SecretStore` lifecycle that holds the staged key bytes so
///   the plaintext never crosses FRB more than once.
///
/// The Dart helpers in this file pass only opaque `SecretRef` ids and
/// callback closures back into the Rust pipeline; raw key bytes never
/// live in a Dart heap object beyond the wipe-on-exit controllers used
/// for the typed password.
extension _TierApply on _SecuritySectionState {
  /// Prompt for the current password before a password-dropping
  /// transition. Returns true to proceed, false to abort (user
  /// cancelled or typed the wrong password). The four-outcome state
  /// machine lives in `security_section_logic.
  /// confirmCurrentPasswordIfDropping`; this wrapper translates the
  /// outcome enum into the bool the caller already consumes plus the
  /// "wrong password" toast.
  Future<bool> _confirmCurrentPasswordIfDropping(
    SecurityTier current,
    SecurityTierModifiers currentModifiers,
    SecurityTier next,
    SecurityTierModifiers nextModifiers,
  ) async {
    final result = await confirmCurrentPasswordIfDropping(
      currentTier: current,
      currentModifiers: currentModifiers,
      targetTier: next,
      targetModifiers: nextModifiers,
      verifiers: PasswordVerifierSeams(
        promptCurrentPassword: _promptCurrentPasswordWithWipe,
        verifyMaster: ref.read(masterPasswordProvider).verify,
        verifyKeychainGate: ref.read(keychainPasswordGateProvider).verify,
        verifyHardwareVault: (entered) async {
          // The hw-vault unseal returns the DB key on a correct
          // password and null on a mismatch — non-null is the
          // verifier. The returned bytes are discarded; the apply
          // pipeline reseals under whatever the next tier wants.
          final unsealed = await ref
              .read(hardwareTierVaultProvider)
              .read(entered);
          return unsealed != null;
        },
      ),
    );
    switch (result) {
      case ConfirmPasswordResult.notRequired:
      case ConfirmPasswordResult.ok:
        return true;
      case ConfirmPasswordResult.cancelled:
        return false;
      case ConfirmPasswordResult.wrongPassword:
        if (mounted) {
          Toast.show(
            context,
            message: S.of(context).currentPasswordIncorrect,
            level: ToastLevel.error,
          );
        }
        return false;
    }
  }

  /// Shared current-password prompt with wipe-on-exit semantics. The
  /// backing controller is wiped + disposed in a `finally` so the
  /// typed plaintext doesn't linger on the Dart heap regardless of
  /// dismiss path.
  Future<String?> _promptCurrentPasswordWithWipe() async {
    final ctrl = TextEditingController();
    try {
      return await AppDialog.show<String>(
        context,
        builder: (ctx) => _EnableBiometricDialog(currentCtrl: ctrl),
      );
    } finally {
      ctrl.wipeAndClear();
      ctrl.dispose();
    }
  }

  Future<void> _applyTierChange(SecuritySetupResult result) async {
    switch (result.tier) {
      case SecurityTier.plaintext:
        await _applyPlaintextTier(result);
      case SecurityTier.keychain:
        // Bank-style: T1+password is keychain + modifiers.password,
        // so the dispatch branches on the modifier and routes to
        // `_applyKeychainWithPasswordTier` when it is set.
        if (result.modifiers.password) {
          await _applyKeychainWithPasswordTier(result);
        } else {
          await _applyKeychainTier(result);
        }
      case SecurityTier.hardware:
        await _applyHardwareTier(result);
      case SecurityTier.paranoid:
        await _applyParanoidTier(result);
    }
  }

  Future<void> _applyPlaintextTier(SecuritySetupResult result) async {
    await applyPlaintextTier(
      modifiers: result.modifiers,
      applyAlwaysRekey: _applyAlwaysRekey,
      runClearPlan: _runVaultClearPlan,
    );
  }

  Future<void> _applyKeychainTier(SecuritySetupResult result) async {
    final keyStorage = ref.read(secureKeyStorageProvider);
    await applyKeychainTier(
      modifiers: result.modifiers,
      stageRandomKey: _stageRandomKey,
      keychainWriteFromSecret: keyStorage.writeKeyFromSecret,
      applyAlwaysRekeyFromSecret: _applyAlwaysRekeyFromSecret,
      dropStaged: _dropStaged,
      runClearPlan: _runVaultClearPlan,
    );
  }

  Future<void> _applyKeychainWithPasswordTier(
    SecuritySetupResult result,
  ) async {
    final keyStorage = ref.read(secureKeyStorageProvider);
    final gate = ref.read(keychainPasswordGateProvider);
    // Runner with rollback (gate.clear on keychain-write failure)
    // lives in `security_section_logic.applyKeychainWithPasswordTier`
    // so the failure path is unit-testable without Riverpod.
    await applyKeychainWithPasswordTier(
      shortPassword: result.takeShortPassword(),
      modifiers: result.modifiers,
      seams: KeychainTierSeams(
        gateSetPassword: gate.setPassword,
        gateClear: gate.clear,
        stageRandomKey: _stageRandomKey,
        keychainWriteFromSecret: keyStorage.writeKeyFromSecret,
        applyAlwaysRekeyFromSecret: _applyAlwaysRekeyFromSecret,
        dropStaged: _dropStaged,
        runClearPlan: _runVaultClearPlan,
      ),
    );
  }

  Future<void> _applyHardwareTier(SecuritySetupResult result) async {
    // Hardware tier is always password-gated; biometric is the
    // optional shortcut on top. A missing password at this point
    // is a misuse — the wizard / Settings card both force the
    // modifier on for T2 — so we fail loud rather than silently
    // seal against an empty HMAC.
    final hwVault = ref.read(hardwareTierVaultProvider);
    await applyHardwareTier(
      modifiers: result.modifiers,
      password: result.takePin(),
      stageRandomKey: _stageRandomKey,
      hardwareStoreFromSecret: hwVault.storeFromSecret,
      applyAlwaysRekeyFromSecret: _applyAlwaysRekeyFromSecret,
      dropStaged: _dropStaged,
      runClearPlan: _runVaultClearPlan,
    );
  }

  Future<void> _applyParanoidTier(SecuritySetupResult result) async {
    final manager = ref.read(masterPasswordProvider);
    await applyParanoidTier(
      masterPassword: result.takeMasterPassword(),
      modifiers: result.modifiers,
      mintSecretId: mintTierSwitchSecretId,
      masterEnableToSecret: manager.enableToSecret,
      applyAlwaysRekeyFromSecret: _applyAlwaysRekeyFromSecret,
      dropStaged: _dropStaged,
      runClearPlan: _runVaultClearPlan,
    );
  }

  /// Mint a SecretStore id and stage a fresh AES-256 key under it.
  /// Returns the id for downstream consumers (`keychainWriteFromSecret`,
  /// `applyAlwaysRekeyFromSecret`).
  String _stageRandomKey() {
    final id = mintTierSwitchSecretId();
    rust_crypto.cryptoAesGcmRandomKeyToSecret(id: id);
    return id;
  }

  /// Drop a previously-staged SecretStore id. Used by the helpers'
  /// failure paths so a write-rejected secret does not linger
  /// Rust-side until the next process exit.
  void _dropStaged(String secretId) {
    rust_app.secretsDrop(id: secretId);
  }

  /// Drive the per-target vault clear matrix from
  /// [tierVaultClearPlanFor] through the pure runner in
  /// `security_section_logic.runVaultClearPlan`. The matrix flips
  /// off the slot the apply method just wrote into so the commit
  /// isn't immediately undone; the runner walks the remaining
  /// slots through the provider methods.
  Future<void> _runVaultClearPlan(
    SecurityTier target,
    SecurityTierModifiers modifiers,
  ) async {
    final manager = ref.read(masterPasswordProvider);
    await runVaultClearPlan(
      plan: tierVaultClearPlanFor(target, modifiers),
      clearKeychainKey: ref.read(secureKeyStorageProvider).deleteKey,
      clearKeychainGate: ref.read(keychainPasswordGateProvider).clear,
      clearHardwareVault: ref.read(hardwareTierVaultProvider).clear,
      isMasterPasswordEnabled: manager.isEnabled,
      disableMasterPassword: manager.disable,
      clearBiometricVault: ref.read(biometricKeyVaultProvider).clear,
    );
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
  /// Plaintext-target rekey path. The non-plaintext tiers route
  /// through [_applyAlwaysRekeyFromSecret] (SecretRef-aware) so this
  /// helper now serves only the `applyPlaintextTier` caller, which
  /// passes `key == null` to land the DB on the unencrypted cipher.
  /// The signature stays compatible with `applyPlaintextTier`'s
  /// callback shape so tests + the helper's contract don't shift
  /// just to drop a no-longer-used branch.
  Future<void> _applyAlwaysRekey(
    Uint8List? key,
    SecurityTier level, [
    SecurityTierModifiers? modifiers,
  ]) async {
    assert(
      key == null,
      'non-plaintext tiers route through _applyAlwaysRekeyFromSecret',
    );
    final switcher = SecurityTierSwitcher();
    try {
      await switcher.clearMarker();
      ref.read(securityStateProvider.notifier).clearEncryption();
    } catch (_) {}
    final existing = ref.read(configProvider).security;
    final next = SecurityConfig(
      tier: level,
      modifiers: modifiers ?? SecurityTierModifiers.defaults,
    );
    if (existing != next) {
      await ref
          .read(configProvider.notifier)
          .update((cfg) => cfg.copyWithSecurity(security: next));
    }
  }

  /// SecretRef variant of [_applyAlwaysRekey]. Routes through
  /// [SecurityTierSwitcher.switchTierFromSecret] so the new DB key
  /// never lands on the Dart heap — `dbRekeyFromSecret` reads it
  /// Rust-side via `secrets_get` and atomically promotes the source
  /// id to `app.dbkey.active` on success. The Riverpod state then
  /// only needs the tier enum + a `hasActiveDbKey: true` flag; no
  /// bytes Dart-side. The `finally` drop covers failure paths
  /// before the promote — on success the source id has already
  /// been renamed away, so the drop is a no-op.
  Future<void> _applyAlwaysRekeyFromSecret(
    String secretId,
    SecurityTier level,
    SecurityTierModifiers modifiers,
  ) async {
    final markerPayload = buildTierMarkerPayload(level, modifiers);
    final switcher = SecurityTierSwitcher();

    try {
      await switcher.switchTierFromSecret(
        secretId: secretId,
        targetMarkerPayload: markerPayload,
        applyWrapperFromSecret: (_) async {
          ref
              .read(securityStateProvider.notifier)
              .setActive(level, hasKey: true);
        },
        persistConfigFromSecret: (_) async {
          final existing = ref.read(configProvider).security;
          final next = SecurityConfig(tier: level, modifiers: modifiers);
          if (existing == next) return;
          await ref
              .read(configProvider.notifier)
              .update((cfg) => cfg.copyWithSecurity(security: next));
        },
        clearPrevious: () async {},
      );
    } finally {
      // No-op on success — `db_rekey_from_secret` already renamed the
      // source slot to `ACTIVE_DBKEY_SECRET_ID`. On failure (rekey
      // throws before the rename) the transient bytes are still
      // resident; drop them so they don't outlive the rekey window.
      rust_app.secretsDrop(id: secretId);
    }
  }
}
