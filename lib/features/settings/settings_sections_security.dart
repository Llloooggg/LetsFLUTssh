part of 'settings_screen.dart';

class _SecuritySection extends ConsumerStatefulWidget {
  const _SecuritySection();

  @override
  ConsumerState<_SecuritySection> createState() => _SecuritySectionState();
}

class _SecuritySectionState extends ConsumerState<_SecuritySection> {
  bool? _masterPasswordEnabled;
  bool? _keychainAvailable;
  BiometricAvailability _biometricUnavailable;
  bool? _biometricEnabled;
  bool _biometricProbed = false;

  @override
  void initState() {
    super.initState();
    _checkState();
  }

  Future<void> _checkState() async {
    // Master password + keychain probes first — _manageMasterPassword()
    // branches on _masterPasswordEnabled and the wrong branch opens the
    // "Set password" dialog instead of "Manage options". Biometric probes
    // (slower, platform-dependent) are kept off this critical path and
    // published in a second setState below.
    final manager = ref.read(masterPasswordProvider);
    final keyStorage = ref.read(secureKeyStorageProvider);
    final coreResults = await Future.wait([
      manager.isEnabled(),
      keyStorage.isAvailable(),
    ]);
    if (!mounted) return;
    setState(() {
      _masterPasswordEnabled = coreResults[0];
      _keychainAvailable = coreResults[1];
    });

    final bio = ref.read(biometricAuthProvider);
    final bioVault = ref.read(biometricKeyVaultProvider);
    final availability = await bio.availability();
    final stored = await bioVault.isStored();
    if (!mounted) return;
    setState(() {
      _biometricUnavailable = availability;
      _biometricEnabled = stored;
      _biometricProbed = true;
    });
  }

  /// Localized explanation for why the biometric toggle is disabled —
  /// null means "either fully enabled, or still probing". Caller pairs
  /// this with [_biometricEnabledFor] to decide. Two layers:
  ///  * platform/hardware reason from [BiometricAuth.availability]
  ///  * "you need a master password first" when the app is not in
  ///    master-password mode (biometry caches the MP-derived key, so
  ///    without an MP there is no key to cache)
  String? _biometricDisabledReason(S l10n, SecurityLevel level) {
    if (!_biometricProbed) return null;
    switch (_biometricUnavailable) {
      case BiometricUnavailableReason.platformUnsupported:
      case BiometricUnavailableReason.noSensor:
        return l10n.biometricSensorNotAvailable;
      case BiometricUnavailableReason.notEnrolled:
        return l10n.biometricNotEnrolled;
      case null:
        break;
    }
    if (level != SecurityLevel.masterPassword) {
      return l10n.biometricRequiresMasterPassword;
    }
    return null;
  }

  /// Whether the biometric toggle can be flipped. Returns false during
  /// the initial probe so the toggle doesn't momentarily look live.
  bool _biometricToggleEnabled(SecurityLevel level) {
    if (!_biometricProbed) return false;
    if (_biometricUnavailable != null) return false;
    return level == SecurityLevel.masterPassword;
  }

  String? _autoLockDisabledReason(S l10n, SecurityLevel level) {
    if (level == SecurityLevel.masterPassword) return null;
    return l10n.autoLockRequiresMasterPassword;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = S.of(context);
    final secState = ref.watch(securityStateProvider);

    return Column(
      children: [
        // Security level info.
        _InfoTile(
          icon: Icons.shield,
          title: l10n.securityLevel,
          value: _securityLevelLabel(l10n, secState.level),
        ),
        // Keychain status.
        _InfoTile(
          icon: Icons.key,
          title: l10n.keychainStatus,
          value: _keychainStatusLabel(l10n),
        ),
        // Manage master password — single tile.
        _ActionTile(
          icon: _masterPasswordEnabled == true ? Icons.lock : Icons.lock_open,
          title: l10n.manageMasterPassword,
          subtitle: l10n.manageMasterPasswordSubtitle,
          onTap: () => _manageMasterPassword(context),
        ),
        // Single keychain toggle — its label and behaviour flip with the
        // current security level instead of two separate enable/disable
        // rows. Greyed out when the platform has no keychain available or
        // when the current mode is masterPassword (in which case the user
        // changes mode through the master-password manager instead).
        _Toggle(
          label: l10n.useKeychain,
          subtitle: l10n.useKeychainSubtitle,
          icon: Icons.enhanced_encryption,
          value: secState.level == SecurityLevel.keychain,
          onChanged:
              _keychainAvailable == true &&
                  secState.level != SecurityLevel.masterPassword
              ? (v) => v ? _enableKeychain(context) : _disableKeychain(context)
              : null,
        ),
        // Biometric unlock — always rendered so the user can see that
        // the option exists and why it cannot be flipped right now.
        // When disabled the [_Toggle] shows a tooltip + toast with the
        // reason (no sensor, nothing enrolled, or no master password
        // set yet) instead of silently disappearing.
        _Toggle(
          label: l10n.biometricUnlockTitle,
          subtitle: l10n.biometricUnlockSubtitle,
          icon: Icons.fingerprint,
          value: _biometricEnabled == true,
          onChanged: _biometricToggleEnabled(secState.level)
              ? (v) => _toggleBiometricUnlock(context, v)
              : null,
          disabledReason: _biometricDisabledReason(l10n, secState.level),
        ),
        // Auto-lock — meaningful only when a master password is set,
        // but still rendered in every mode with a disabled look +
        // reason so the user doesn't wonder where it went after
        // disabling master-password mode.
        _AutoLockTile(
          disabledReason: _autoLockDisabledReason(l10n, secState.level),
        ),
      ],
    );
  }

  Future<void> _toggleBiometricUnlock(BuildContext context, bool enable) async {
    if (enable) {
      await _enableBiometricUnlock(context);
    } else {
      await _disableBiometricUnlock(context);
    }
  }

  /// Cache the DB key in the biometric-gated vault. Requires a fresh
  /// master-password prompt so an accidental toggle tap can't silently
  /// enable biometric access; the live key in SecurityState is the same
  /// bytes we'd store, but forcing re-entry matches user expectation.
  Future<void> _enableBiometricUnlock(BuildContext context) async {
    final l10n = S.of(context);
    final currentCtrl = TextEditingController();
    final password = await AppDialog.show<String>(
      context,
      builder: (ctx) => _EnableBiometricDialog(currentCtrl: currentCtrl),
    );
    if (password == null || !context.mounted) return;

    final manager = ref.read(masterPasswordProvider);
    if (!await manager.verify(password)) {
      if (context.mounted) {
        Toast.show(
          context,
          message: S.of(context).currentPasswordIncorrect,
          level: ToastLevel.error,
        );
      }
      return;
    }

    final bio = ref.read(biometricAuthProvider);
    if (!await bio.authenticate(l10n.biometricUnlockPrompt)) {
      // Cancel / lockout / biometricOnly-without-enrollment all land
      // here as a silent `false` from local_auth. Surface a toast so
      // the user knows why the toggle didn't flip — the prior code
      // returned quietly and looked like the tap did nothing.
      if (context.mounted) {
        Toast.show(
          context,
          message: l10n.biometricUnlockCancelled,
          level: ToastLevel.warning,
        );
      }
      return;
    }

    final key = await manager.deriveKey(password);
    final vault = ref.read(biometricKeyVaultProvider);
    final stored = await vault.store(key);
    if (!mounted) return;

    if (!stored) {
      if (context.mounted) {
        Toast.show(
          context,
          message: l10n.biometricEnableFailed,
          level: ToastLevel.error,
        );
      }
      return;
    }

    setState(() => _biometricEnabled = true);
    if (context.mounted) {
      Toast.show(
        context,
        message: l10n.biometricEnabled,
        level: ToastLevel.success,
      );
    }
  }

  Future<void> _disableBiometricUnlock(BuildContext context) async {
    final l10n = S.of(context);
    await ref.read(biometricKeyVaultProvider).clear();
    if (!mounted) return;
    setState(() => _biometricEnabled = false);
    if (context.mounted) {
      Toast.show(
        context,
        message: l10n.biometricDisabled,
        level: ToastLevel.success,
      );
    }
  }

  String _keychainStatusLabel(S l10n) {
    if (_keychainAvailable == true) return l10n.keychainAvailable;
    if (_keychainAvailable == false) return l10n.keychainNotAvailable;
    return '...';
  }

  String _securityLevelLabel(S l10n, SecurityLevel level) {
    switch (level) {
      case SecurityLevel.plaintext:
        return l10n.securityLevelPlaintext;
      case SecurityLevel.keychain:
        return l10n.securityLevelKeychain;
      case SecurityLevel.masterPassword:
        return l10n.securityLevelMasterPassword;
    }
  }

  /// Single entry point for master password management.
  ///
  /// Not set → show set dialog.
  /// Already set → show dialog with Change / Remove options.
  Future<void> _manageMasterPassword(BuildContext context) async {
    if (_masterPasswordEnabled != true) {
      await _setMasterPassword(context);
    } else {
      await _showManageOptions(context);
    }
  }

  Future<void> _showManageOptions(BuildContext context) async {
    final l10n = S.of(context);
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(l10n.manageMasterPassword),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'change'),
            child: Text(l10n.changeMasterPassword),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'remove'),
            child: Text(
              l10n.removeMasterPassword,
              style: TextStyle(color: AppTheme.red),
            ),
          ),
        ],
      ),
    );
    if (action == null || !context.mounted) return;
    if (action == 'change') {
      await _changeMasterPassword(context);
    } else {
      await _removeMasterPassword(context);
    }
  }

  Future<void> _setMasterPassword(BuildContext context) async {
    final l10n = S.of(context);
    final passwordCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();

    try {
      final password = await AppDialog.show<String>(
        context,
        builder: (ctx) => _SetMasterPasswordDialog(
          passwordCtrl: passwordCtrl,
          confirmCtrl: confirmCtrl,
        ),
      );

      if (password == null || !context.mounted) return;

      final reporter = ProgressReporter(l10n.progressReencrypting);
      AppProgressBarDialog.show(context, reporter);
      try {
        await _enableMasterPassword(password);
        if (context.mounted) {
          Navigator.of(context).pop();
          Toast.show(
            context,
            message: l10n.masterPasswordSet,
            level: ToastLevel.success,
          );
          _checkState();
        }
      } catch (e) {
        if (context.mounted) Navigator.of(context).pop();
        rethrow;
      } finally {
        reporter.dispose();
      }
    } catch (e) {
      AppLogger.instance.log(
        'Set master password failed: $e',
        name: 'Security',
        error: e,
      );
      if (context.mounted) {
        Toast.show(
          context,
          message: localizeError(S.of(context), e),
          level: ToastLevel.error,
        );
      }
    } finally {
      passwordCtrl.wipeAndClear();
      confirmCtrl.wipeAndClear();
      passwordCtrl.dispose();
      confirmCtrl.dispose();
    }
  }

  Future<void> _enableMasterPassword(String password) async {
    final manager = ref.read(masterPasswordProvider);

    // Derive new key from password.
    final newKey = await manager.enable(password);

    // Sanity check: verify the password immediately to catch crypto issues.
    final verified = await manager.verify(password);
    if (!verified) {
      await manager.disable();
      throw const MasterPasswordException(
        'Verification failed after enable — reverted',
      );
    }

    // Re-encrypt all stores with the derived key.
    await _reEncryptAll(newKey, SecurityLevel.masterPassword);

    // Delete keychain key if it was used before.
    final keyStorage = ref.read(secureKeyStorageProvider);
    await keyStorage.deleteKey();
  }

  Future<void> _changeMasterPassword(BuildContext context) async {
    final l10n = S.of(context);
    final currentCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();

    try {
      final result = await AppDialog.show<({String current, String newPw})>(
        context,
        builder: (ctx) => _ChangeMasterPasswordDialog(
          currentCtrl: currentCtrl,
          newCtrl: newCtrl,
          confirmCtrl: confirmCtrl,
        ),
      );

      if (result == null || !context.mounted) return;

      final reporter = ProgressReporter(l10n.progressReencrypting);
      AppProgressBarDialog.show(context, reporter);
      try {
        await _doChangePassword(result.current, result.newPw);
        if (context.mounted) {
          Navigator.of(context).pop();
          Toast.show(
            context,
            message: l10n.masterPasswordChanged,
            level: ToastLevel.success,
          );
        }
      } catch (e) {
        if (context.mounted) Navigator.of(context).pop();
        rethrow;
      } finally {
        reporter.dispose();
      }
    } on MasterPasswordException catch (e) {
      if (context.mounted) {
        Toast.show(context, message: e.message, level: ToastLevel.error);
      }
    } catch (e) {
      AppLogger.instance.log(
        'Change master password failed: $e',
        name: 'Security',
        error: e,
      );
      if (context.mounted) {
        Toast.show(
          context,
          message: localizeError(S.of(context), e),
          level: ToastLevel.error,
        );
      }
    } finally {
      currentCtrl.wipeAndClear();
      newCtrl.wipeAndClear();
      confirmCtrl.wipeAndClear();
      currentCtrl.dispose();
      newCtrl.dispose();
      confirmCtrl.dispose();
    }
  }

  Future<void> _doChangePassword(String oldPassword, String newPassword) async {
    final manager = ref.read(masterPasswordProvider);

    // Change password — verifies old, generates new salt + verifier.
    final newKey = await manager.changePassword(oldPassword, newPassword);

    // Re-encrypt all stores with new key.
    await _reEncryptAll(newKey, SecurityLevel.masterPassword);

    // The cached biometric key (if any) was derived from the OLD password
    // — it's now stale. Wipe it; user can re-enable biometric unlock from
    // the toggle afterwards.
    await ref.read(biometricKeyVaultProvider).clear();
    if (mounted) setState(() => _biometricEnabled = false);
  }

  Future<void> _removeMasterPassword(BuildContext context) async {
    final l10n = S.of(context);
    final passwordCtrl = TextEditingController();

    try {
      final password = await AppDialog.show<String>(
        context,
        builder: (ctx) =>
            _RemoveMasterPasswordDialog(passwordCtrl: passwordCtrl),
      );

      if (password == null || !context.mounted) return;

      final reporter = ProgressReporter(l10n.progressReencrypting);
      AppProgressBarDialog.show(context, reporter);
      try {
        await _doRemoveMasterPassword(password);
        if (context.mounted) {
          Navigator.of(context).pop();
          Toast.show(
            context,
            message: l10n.masterPasswordRemoved,
            level: ToastLevel.success,
          );
          _checkState();
        }
      } catch (e) {
        if (context.mounted) Navigator.of(context).pop();
        rethrow;
      } finally {
        reporter.dispose();
      }
    } on MasterPasswordException catch (e) {
      if (context.mounted) {
        Toast.show(context, message: e.message, level: ToastLevel.error);
      }
    } catch (e) {
      AppLogger.instance.log(
        'Remove master password failed: $e',
        name: 'Security',
        error: e,
      );
      if (context.mounted) {
        Toast.show(
          context,
          message: localizeError(S.of(context), e),
          level: ToastLevel.error,
        );
      }
    } finally {
      passwordCtrl.wipeAndClear();
      passwordCtrl.dispose();
    }
  }

  Future<void> _doRemoveMasterPassword(String password) async {
    final manager = ref.read(masterPasswordProvider);

    // Verify password first.
    final isValid = await manager.verify(password);
    if (!isValid) {
      throw const MasterPasswordException('Current password is incorrect');
    }

    // Leaving MP mode — any biometric-cached key belongs to a secret that
    // is about to stop existing. Drop it unconditionally so the user
    // cannot silently fall back to biometrics that wrap a now-invalid
    // credential.
    await ref.read(biometricKeyVaultProvider).clear();
    if (mounted) setState(() => _biometricEnabled = false);

    // Try keychain first, fall back to plaintext.
    final keyStorage = ref.read(secureKeyStorageProvider);
    final keychainAvailable = await keyStorage.isAvailable();
    if (keychainAvailable) {
      final key = AesGcm.generateKey();
      final stored = await keyStorage.writeKey(key);
      if (stored) {
        await _reEncryptAll(key, SecurityLevel.keychain);
        await manager.disable();
        return;
      }
    }

    // No keychain — fall back to plaintext.
    await _reEncryptAll(null, SecurityLevel.plaintext);
    await manager.disable();
  }

  Future<void> _enableKeychain(BuildContext context) async {
    final l10n = S.of(context);
    final keyStorage = ref.read(secureKeyStorageProvider);

    if (!context.mounted) return;

    try {
      final key = AesGcm.generateKey();
      final stored = await keyStorage.writeKey(key);
      if (!stored) {
        throw Exception('Failed to store key in keychain');
      }

      if (!context.mounted) return;
      final reporter = ProgressReporter(l10n.progressReencrypting);
      AppProgressBarDialog.show(context, reporter);
      try {
        await _reEncryptAll(key, SecurityLevel.keychain);
        if (context.mounted) {
          Navigator.of(context).pop();
          Toast.show(
            context,
            message: l10n.keychainEnabled,
            level: ToastLevel.success,
          );
          _checkState();
        }
      } catch (e) {
        if (context.mounted) Navigator.of(context).pop();
        rethrow;
      } finally {
        reporter.dispose();
      }
    } catch (e) {
      AppLogger.instance.log(
        'Enable keychain failed: $e',
        name: 'Security',
        error: e,
      );
      if (context.mounted) {
        Toast.show(
          context,
          message: localizeError(S.of(context), e),
          level: ToastLevel.error,
        );
      }
    }
  }

  Future<void> _disableKeychain(BuildContext context) async {
    final l10n = S.of(context);
    final confirmed = await AppDialog.show<bool>(
      context,
      builder: (ctx) => AppDialog(
        title: l10n.disableKeychain,
        content: Text(l10n.disableKeychainConfirm),
        actions: [
          AppDialogAction.cancel(onTap: () => Navigator.pop(ctx, false)),
          AppDialogAction.destructive(
            label: l10n.disableKeychain,
            onTap: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final keyStorage = ref.read(secureKeyStorageProvider);
    try {
      final reporter = ProgressReporter(l10n.progressReencrypting);
      AppProgressBarDialog.show(context, reporter);
      try {
        await keyStorage.deleteKey();
        await _reEncryptAll(null, SecurityLevel.plaintext);
        if (context.mounted) {
          Navigator.of(context).pop();
          Toast.show(
            context,
            message: l10n.keychainDisabled,
            level: ToastLevel.success,
          );
          _checkState();
        }
      } catch (e) {
        if (context.mounted) Navigator.of(context).pop();
        rethrow;
      } finally {
        reporter.dispose();
      }
    } catch (e) {
      AppLogger.instance.log(
        'Disable keychain failed: $e',
        name: 'Security',
        error: e,
      );
      if (context.mounted) {
        Toast.show(
          context,
          message: localizeError(S.of(context), e),
          level: ToastLevel.error,
        );
      }
    }
  }

  /// Re-encrypt the live database with a new key (or convert to plaintext
  /// when [key] is null), then update global security state.
  ///
  /// Without the `rekeyDatabase` step the DB file pages stay encrypted under
  /// the old key while `securityStateProvider` claims the new one — on the
  /// next app start the DB fails to open. The order is deliberate: run the
  /// `PRAGMA rekey` first; only flip the provider after it succeeded, so a
  /// crypto/disk failure leaves the old (working) state intact.
  Future<void> _reEncryptAll(Uint8List? key, SecurityLevel level) async {
    final store = ref.read(sessionStoreProvider);
    final db = store.database;
    if (db != null) {
      await rekeyDatabase(db, key);
    }
    if (key != null) {
      ref.read(securityStateProvider.notifier).set(level, key);
    } else {
      ref.read(securityStateProvider.notifier).clearEncryption();
    }
  }
}

class _AutoLockTile extends ConsumerWidget {
  static const _presets = [0, 5, 15, 30, 60];

  /// Non-null means the tile is disabled: chips are visibly muted,
  /// wrapped in a tooltip, and any tap surfaces the reason through a
  /// toast instead of mutating the setting.
  final String? disabledReason;

  const _AutoLockTile({this.disabledReason});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = S.of(context);
    final current = ref.watch(autoLockMinutesProvider);
    final enabled = disabledReason == null;
    final chips = Wrap(
      spacing: 6,
      children: _presets
          .map((m) => _buildChip(context, ref, l10n, m, current, enabled))
          .toList(),
    );
    return Opacity(
      opacity: enabled ? 1.0 : 0.5,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.timer_outlined, size: 16, color: AppTheme.fgDim),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.autoLockTitle,
                        style: AppFonts.inter(
                          fontSize: AppFonts.sm,
                          color: AppTheme.fg,
                        ),
                      ),
                      Text(
                        l10n.autoLockSubtitle,
                        style: AppFonts.inter(
                          fontSize: AppFonts.xs,
                          color: AppTheme.fgFaint,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            enabled ? chips : Tooltip(message: disabledReason!, child: chips),
          ],
        ),
      ),
    );
  }

  Widget _buildChip(
    BuildContext context,
    WidgetRef ref,
    S l10n,
    int minutes,
    int current,
    bool enabled,
  ) {
    final label = minutes == 0
        ? l10n.autoLockOff
        : l10n.autoLockMinutesValue(minutes);
    final selected = minutes == current;
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: AppFonts.xs,
          color: selected ? AppTheme.onAccent : AppTheme.fg,
        ),
      ),
      selected: selected,
      selectedColor: AppTheme.accent,
      onSelected: (_) {
        if (!enabled) {
          Toast.show(context, message: disabledReason!, level: ToastLevel.info);
          return;
        }
        ref.read(autoLockMinutesProvider.notifier).set(minutes);
      },
    );
  }
}
