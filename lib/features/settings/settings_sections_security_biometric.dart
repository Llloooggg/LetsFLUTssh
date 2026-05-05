part of 'settings_screen.dart';

/// Biometric-modifier flow — capture the DB key on enable + apply
/// the pending toggle as part of the tier-card Apply step. Lives as
/// an extension on [_SecuritySectionState] so the helpers reach
/// `ref` / `mounted` / `_biometricEnabled` / `setState` without
/// going through a public surface; `part of` joins the file into
/// the same library so library-private names stay reachable.
extension _BiometricFlow on _SecuritySectionState {
  /// Handle the tier-card Apply when the only pending change is the
  /// biometric toggle on the currently-applied tier. Skips the
  /// tier-switch rekey entirely and runs just the biometric enable /
  /// disable step with its own password prompt (enable) or straight
  /// vault clear (disable).
  Future<void> _applyBiometricOnlyToggle(
    bool? pendingBiometric,
    SecurityTier currentTier,
  ) async {
    if (pendingBiometric == null) return;
    final l10n = S.of(context);
    Uint8List? keyToStash;
    if (pendingBiometric) {
      // Same password-prompt path as the post-tier-change biometric
      // enable — asks for the current password, verifies it against
      // the live gate, returns the derived DB key.
      keyToStash = await _captureKeyForBiometricEnable(
        currentTier,
        currentTier,
      );
      if (keyToStash == null) return; // user cancelled / wrong password
    }
    if (!mounted) return;
    final reporter = ProgressReporter(l10n.changeSecurityTierConfirm);
    AppProgressBarDialog.show(context, reporter);
    try {
      await _applyPendingBiometric(pendingBiometric, keyFromEnable: keyToStash);
      if (!mounted) return;
      Navigator.of(context).pop();
      Toast.show(
        context,
        message: l10n.changeSecurityTierDone,
        level: ToastLevel.success,
      );
      _checkState();
    } catch (e) {
      AppLogger.instance.log(
        'Biometric-only apply failed: $e',
        name: 'Settings',
        error: e,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      Toast.show(
        context,
        message: '${l10n.changeSecurityTierFailed}: $e',
        level: ToastLevel.error,
      );
    }
  }

  /// Capture the DB key for a biometric enable. When the Apply
  /// transition is between two different tiers, the NEW tier's
  /// secret (typed in the card) is the one we can derive the key
  /// from — after `_applyTierChange` runs, that's the key the
  /// tier holds. Same-tier enable (user toggled biometric without
  /// changing the tier) falls back to re-prompting the current
  /// password via [_enableBiometricDialogPrompt].
  ///
  /// Returns null when the user cancels or types the wrong password;
  /// the caller aborts the whole Apply on null.
  Future<Uint8List?> _captureKeyForBiometricEnable(
    SecurityTier current,
    SecurityTier next, {
    String? shortPassword,
    String? pin,
    String? masterPassword,
  }) async {
    // Decision lives in `security_section_logic.biometricKeySourceFor`
    // so the priority ladder (cross-tier → pullFromApplied; same-tier
    // T1+pw → keychain gate; same-tier Paranoid → master password;
    // everything else → empty sentinel) is unit-tested without a
    // pumpWidget round-trip. The dispatcher here only wires the
    // chosen source onto its prompt + read implementation.
    switch (biometricKeySourceFor(currentTier: current, nextTier: next)) {
      case BiometricKeySource.pullFromAppliedTier:
        // Returning a non-null zero-length buffer signals "wait for
        // apply, then fetch from securityStateProvider". The post-
        // apply step in `_applyPendingBiometric` replaces it with
        // the real key.
        return Uint8List(0);
      case BiometricKeySource.promptAndVerifyKeychainGate:
        return _captureKeyFromKeychainPassword();
      case BiometricKeySource.promptAndVerifyMasterPassword:
        return _captureKeyFromMasterPassword();
    }
  }

  Future<Uint8List?> _captureKeyFromKeychainPassword() async {
    final entered = await _enableBiometricDialogPrompt();
    if (entered == null || !mounted) return null;
    final gate = ref.read(keychainPasswordGateProvider);
    if (!await gate.verify(entered)) {
      if (mounted) {
        Toast.show(
          context,
          message: S.of(context).currentPasswordIncorrect,
          level: ToastLevel.error,
        );
      }
      return null;
    }
    return ref.read(secureKeyStorageProvider).readKey();
  }

  Future<Uint8List?> _captureKeyFromMasterPassword() async {
    final entered = await _enableBiometricDialogPrompt();
    if (entered == null || !mounted) return null;
    return ref.read(masterPasswordProvider).verifyAndDerive(entered);
  }

  /// Show the reusable current-password prompt shared with the
  /// "drop password" confirmation flow. Returns null when the user
  /// cancels. The backing controller is wiped and disposed on every
  /// exit path so the typed current-password does not linger on the
  /// Dart heap — `_EnableBiometricDialog` is a view; the secret
  /// belongs to this scope.
  Future<String?> _enableBiometricDialogPrompt() async {
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

  /// Apply the pending biometric toggle from the tier card. Called
  /// inside `onSelectTier` right after `_applyTierChange`, so the
  /// security state has already flipped to the target tier and the
  /// fresh DB key is in `securityStateProvider` (for tier changes)
  /// or readable via the matching gate (for same-tier toggles).
  ///
  /// [pending] is null for "no change", true for enable, false for
  /// disable. [keyFromEnable] is the sentinel from
  /// [_captureKeyForBiometricEnable]: a zero-length buffer means
  /// "read the current DB key after apply"; non-empty means "use
  /// this as the vault payload".
  Future<void> _applyPendingBiometric(
    bool? pending, {
    required Uint8List? keyFromEnable,
  }) async {
    if (pending == null) return;
    if (!pending) {
      await ref.read(biometricKeyVaultProvider).clear();
      if (!mounted) return;
      rebuild(() => _biometricEnabled = false);
      return;
    }
    // Enable path. Two flavours:
    //   * `keyFromEnable.isEmpty` — sentinel for "use the active
    //     tier's freshly-applied DB key". Routes through the
    //     SecretRef path (`storeFromActive`) so the bytes never
    //     touch the Dart heap on this call.
    //   * `keyFromEnable` non-empty — caller already derived a key
    //     Dart-side (legacy bytes path; tracked as Phase-2 follow-up
    //     for the password-derivation paths).
    final bio = ref.read(biometricAuthProvider);
    final l10n = S.of(context);
    if (!await bio.authenticate(l10n.biometricUnlockPrompt)) {
      if (mounted) {
        Toast.show(
          context,
          message: l10n.biometricUnlockCancelled,
          level: ToastLevel.warning,
        );
      }
      return;
    }
    final vault = ref.read(biometricKeyVaultProvider);
    final bool stored;
    if (keyFromEnable == null) {
      return;
    } else if (keyFromEnable.isEmpty) {
      stored = await vault.storeFromActive();
    } else {
      stored = await vault.store(keyFromEnable);
    }
    if (!mounted) return;
    if (!stored) {
      Toast.show(
        context,
        message: l10n.biometricEnableFailed,
        level: ToastLevel.error,
      );
      return;
    }
    rebuild(() => _biometricEnabled = true);
  }
}
