part of 'settings_screen.dart';

/// Outcome of the pre-Apply biometric capture step. Lives as a sealed
/// enum so the post-Apply caller can pattern-match without re-running
/// the source decision: cancelled aborts the whole Apply,
/// pullFromActiveAfterApply waits for the tier-switch rekey to
/// publish the live key into [kActiveDbKeySecretId], stagedInSecretStore
/// signals the capture stashed the bytes Rust-side under the named
/// transient slot.
enum _BiometricKeyCaptureKind {
  cancelled,
  pullFromActiveAfterApply,
  stagedInSecretStore,
}

class _BiometricKeyCapture {
  const _BiometricKeyCapture._(this.kind, this.secretId);

  final _BiometricKeyCaptureKind kind;
  final String? secretId;

  static const cancelled = _BiometricKeyCapture._(
    _BiometricKeyCaptureKind.cancelled,
    null,
  );
  static const pullFromActiveAfterApply = _BiometricKeyCapture._(
    _BiometricKeyCaptureKind.pullFromActiveAfterApply,
    null,
  );
  static const stagedInSecretStore = _BiometricKeyCapture._(
    _BiometricKeyCaptureKind.stagedInSecretStore,
    kBiometricEnableStagingSecretId,
  );
}

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
    var capture = _BiometricKeyCapture.cancelled;
    if (pendingBiometric) {
      // Same password-prompt path as the post-tier-change biometric
      // enable — asks for the current password, verifies it against
      // the live gate, stages the derived DB key in the SecretStore
      // under `kBiometricEnableStagingSecretId`. Bytes never cross
      // the FRB boundary on this path.
      capture = await _captureKeyForBiometricEnable(currentTier, currentTier);
      if (capture.kind == _BiometricKeyCaptureKind.cancelled) return;
    }
    if (!mounted) return;
    final reporter = ProgressReporter(l10n.changeSecurityTierConfirm);
    AppProgressBarDialog.show(context, reporter);
    try {
      await _applyPendingBiometric(pendingBiometric, capture: capture);
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
  /// Bytes never materialise on the Dart heap — the SecretRef
  /// capture variants stage the derived / read key into the
  /// SecretStore under `kBiometricEnableStagingSecretId` and the
  /// post-Apply step calls `BiometricKeyVault.storeFromSecret(...)`
  /// against that slot.
  Future<_BiometricKeyCapture> _captureKeyForBiometricEnable(
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
        return _BiometricKeyCapture.pullFromActiveAfterApply;
      case BiometricKeySource.promptAndVerifyKeychainGate:
        return _captureKeyFromKeychainPassword();
      case BiometricKeySource.promptAndVerifyMasterPassword:
        return _captureKeyFromMasterPassword();
    }
  }

  Future<_BiometricKeyCapture> _captureKeyFromKeychainPassword() async {
    final entered = await _enableBiometricDialogPrompt();
    if (entered == null || !mounted) return _BiometricKeyCapture.cancelled;
    final gate = ref.read(keychainPasswordGateProvider);
    final passwordBytes = Uint8List.fromList(utf8.encode(entered));
    if (!await gate.verify(passwordBytes)) {
      if (mounted) {
        Toast.show(
          context,
          message: S.of(context).currentPasswordIncorrect,
          level: ToastLevel.error,
        );
      }
      return _BiometricKeyCapture.cancelled;
    }
    final ok = await ref
        .read(secureKeyStorageProvider)
        .readKeyToSecret(kBiometricEnableStagingSecretId);
    if (!ok) return _BiometricKeyCapture.cancelled;
    return _BiometricKeyCapture.stagedInSecretStore;
  }

  Future<_BiometricKeyCapture> _captureKeyFromMasterPassword() async {
    final entered = await _enableBiometricDialogPrompt();
    if (entered == null || !mounted) return _BiometricKeyCapture.cancelled;
    final passwordBytes = Uint8List.fromList(utf8.encode(entered));
    final ok = await ref
        .read(masterPasswordProvider)
        .verifyAndDeriveToSecret(
          passwordBytes,
          kBiometricEnableStagingSecretId,
        );
    if (!ok) {
      if (mounted) {
        Toast.show(
          context,
          message: S.of(context).currentPasswordIncorrect,
          level: ToastLevel.error,
        );
      }
      return _BiometricKeyCapture.cancelled;
    }
    return _BiometricKeyCapture.stagedInSecretStore;
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
  /// fresh DB key is in `kActiveDbKeySecretId` (cross-tier path) or
  /// staged under `kBiometricEnableStagingSecretId` from the
  /// pre-Apply password-prompt capture (same-tier toggle path).
  ///
  /// [pending] is null for "no change", true for enable, false for
  /// disable. [capture] discriminates which SecretStore slot the
  /// vault should seal from; bytes never cross the FRB boundary on
  /// either branch.
  Future<void> _applyPendingBiometric(
    bool? pending, {
    required _BiometricKeyCapture capture,
  }) async {
    if (pending == null) return;
    if (!pending) {
      await ref.read(biometricKeyVaultProvider).clear();
      if (!mounted) return;
      rebuild(() => _biometricEnabled = false);
      return;
    }
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
    switch (capture.kind) {
      case _BiometricKeyCaptureKind.cancelled:
        return;
      case _BiometricKeyCaptureKind.pullFromActiveAfterApply:
        stored = await vault.storeFromActive();
        break;
      case _BiometricKeyCaptureKind.stagedInSecretStore:
        try {
          stored = await vault.storeFromSecret(capture.secretId!);
        } finally {
          // Drop the transient even on failure so a stale entry
          // never lingers across user retries.
          rust_app.secretsDrop(id: capture.secretId!);
        }
        break;
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
