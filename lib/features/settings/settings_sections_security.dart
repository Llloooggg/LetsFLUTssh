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
  BiometricBackingLevel? _biometricBackingLevel;

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
    final backing = await bio.backingLevel();
    if (!mounted) return;
    setState(() {
      _biometricUnavailable = availability;
      _biometricEnabled = stored;
      _biometricProbed = true;
      _biometricBackingLevel = backing;
    });
  }

  /// Localized explanation for why the biometric toggle is disabled —
  /// null means "either fully enabled, or still probing". Caller pairs
  /// this with [_biometricEnabledFor] to decide. Two layers:
  ///  * platform/hardware reason from [BiometricAuth.availability]
  ///  * "you need a master password first" when the app is not in
  ///    master-password mode (biometry caches the MP-derived key, so
  ///    without an MP there is no key to cache)
  String? _biometricDisabledReason(S l10n, SecurityTier level) {
    if (!_biometricProbed) return null;
    switch (_biometricUnavailable) {
      case BiometricUnavailableReason.platformUnsupported:
      case BiometricUnavailableReason.noSensor:
        return l10n.biometricSensorNotAvailable;
      case BiometricUnavailableReason.notEnrolled:
        return l10n.biometricNotEnrolled;
      case BiometricUnavailableReason.systemServiceMissing:
        return l10n.biometricSystemServiceMissing;
      case null:
        break;
    }
    if (level != SecurityTier.paranoid) {
      return l10n.biometricRequiresMasterPassword;
    }
    return null;
  }

  /// Subtitle shown under the biometric toggle. Appends the current
  /// backing-level label when biometrics are active so the user can
  /// tell hardware-bound storage (Secure Enclave, StrongBox, TPM2)
  /// from software-only (OS keystore). Falls back to the plain
  /// subtitle when biometrics are off or the backing level is
  /// unknown.
  String _biometricSubtitle(S l10n) {
    final base = l10n.biometricUnlockSubtitle;
    if (_biometricEnabled != true || _biometricUnavailable != null) {
      return base;
    }
    final backing = _biometricBackingLevel;
    if (backing == null) return base;
    final label = switch (backing) {
      BiometricBackingLevel.hardware => l10n.biometricBackingHardware,
      BiometricBackingLevel.software => l10n.biometricBackingSoftware,
    };
    return '$base — $label';
  }

  /// Whether the biometric toggle can be flipped. Returns false during
  /// the initial probe so the toggle doesn't momentarily look live.
  bool _biometricToggleEnabled(SecurityTier level) {
    if (!_biometricProbed) return false;
    if (_biometricUnavailable != null) return false;
    return level == SecurityTier.paranoid;
  }

  String? _autoLockDisabledReason(S l10n, SecurityTier level) {
    if (level == SecurityTier.paranoid) return null;
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
          value: secState.level == SecurityTier.keychain,
          onChanged:
              _keychainAvailable == true &&
                  secState.level != SecurityTier.paranoid
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
          subtitle: _biometricSubtitle(l10n),
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
    // Single PBKDF2: verify + derive at once so the enable flow
    // doesn't double the 600k-iteration wait on mobile.
    final key = await manager.verifyAndDerive(password);
    if (key == null) {
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

  String _securityLevelLabel(S l10n, SecurityTier level) {
    switch (level) {
      case SecurityTier.plaintext:
        return l10n.securityLevelPlaintext;
      case SecurityTier.keychain:
        return l10n.tierKeychainLabel;
      case SecurityTier.keychainWithPassword:
        return l10n.tierKeychainPassLabel;
      case SecurityTier.hardware:
        return l10n.tierHardwareLabel;
      case SecurityTier.paranoid:
        return l10n.tierParanoidLabel;
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
    await _reEncryptAll(newKey, SecurityTier.paranoid);

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
    await _reEncryptAll(newKey, SecurityTier.paranoid);

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
        await _reEncryptAll(key, SecurityTier.keychain);
        await manager.disable();
        return;
      }
    }

    // No keychain — fall back to plaintext.
    await _reEncryptAll(null, SecurityTier.plaintext);
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
        await _reEncryptAll(key, SecurityTier.keychain);
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
        await _reEncryptAll(null, SecurityTier.plaintext);
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
  /// Wraps the rekey + provider update in a `SecurityTierSwitcher`
  /// crash-recovery marker: the file is written before `PRAGMA rekey`
  /// and cleared after the provider update succeeds. If the process
  /// dies between the rekey and the provider update, the next launch
  /// sees a stale marker in main's `_initSecurity` and logs it. The
  /// order of rekey → provider update is unchanged: a crypto/disk
  /// failure still leaves the old working state intact.
  Future<void> _reEncryptAll(Uint8List? key, SecurityTier level) async {
    final store = ref.read(sessionStoreProvider);
    final db = store.database;
    final markerPayload = '{"tier":"${_tierName(level)}"}';
    // Bind the constructor-time callbacks to the current key /
    // current-db pair. A fresh switcher instance per call is fine —
    // the marker file is the authoritative state, not the instance.
    final switcher = SecurityTierSwitcher(
      keyFactory: () => key ?? Uint8List(0),
      rekey: (d, _) async => rekeyDatabase(d, key),
    );

    if (db == null) {
      // No live DB (plaintext first-launch path before the first
      // open). Nothing to rekey; just flip the provider. The marker
      // dance is still useful so a crash between state.set and the
      // follow-on caller work is visible next launch, but the
      // switcher wants a non-null DB, so we inline the minimal
      // equivalent here.
      try {
        await switcher.clearMarker();
        if (key != null) {
          ref.read(securityStateProvider.notifier).set(level, key);
        } else {
          ref.read(securityStateProvider.notifier).clearEncryption();
        }
      } catch (_) {}
      return;
    }

    await switcher.switchTier(
      db: db,
      targetMarkerPayload: markerPayload,
      applyWrapper: (_) async {
        if (key != null) {
          ref.read(securityStateProvider.notifier).set(level, key);
        } else {
          ref.read(securityStateProvider.notifier).clearEncryption();
        }
      },
      persistConfig: (_) async {
        // Tier + modifiers are mirrored into config.json by
        // main.dart's `_persistSecurityTier` when the provider
        // state flips; no additional write needed here.
      },
      clearPrevious: () async {
        // Previous-tier cleanup (biometric vault clear, keychain
        // delete, credentials.kdf remove) is handled by the
        // specific enable/disable/change/remove methods that call
        // into `_reEncryptAll`.
      },
    );
  }

  String _tierName(SecurityTier tier) {
    switch (tier) {
      case SecurityTier.plaintext:
        return 'plaintext';
      case SecurityTier.keychain:
        return 'keychain';
      case SecurityTier.keychainWithPassword:
        return 'keychain_with_password';
      case SecurityTier.hardware:
        return 'hardware';
      case SecurityTier.paranoid:
        return 'paranoid';
    }
  }
}

class _AutoLockTile extends ConsumerWidget {
  static const _presets = [0, 1, 5, 15, 30, 60];

  /// Non-null means the tile is disabled: the dropdown trigger is
  /// visibly muted, wrapped in a tooltip, and any tap surfaces the
  /// reason through a toast instead of opening the menu.
  final String? disabledReason;

  const _AutoLockTile({this.disabledReason});

  String _label(S l10n, int minutes) =>
      minutes == 0 ? l10n.autoLockOff : l10n.autoLockMinutesValue(minutes);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = S.of(context);
    final current = ref.watch(autoLockMinutesProvider);
    final enabled = disabledReason == null;
    final trigger = _buildTrigger(l10n, current);
    return Opacity(
      opacity: enabled ? 1.0 : 0.5,
      child: _SettingsRow(
        label: l10n.autoLockTitle,
        subtitle: l10n.autoLockSubtitle,
        icon: Icons.timer_outlined,
        child: enabled
            ? PopupMenuButton<int>(
                onSelected: (v) =>
                    ref.read(autoLockMinutesProvider.notifier).set(v),
                tooltip: '',
                offset: const Offset(0, AppTheme.controlHeightSm),
                constraints: const BoxConstraints(
                  minWidth: 140,
                  maxHeight: AppTheme.popupMaxHeight,
                ),
                color: AppTheme.bg2,
                shape: const RoundedRectangleBorder(
                  borderRadius: AppTheme.radiusMd,
                ),
                itemBuilder: (_) => _presets
                    .map(
                      (m) => PopupMenuItem<int>(
                        value: m,
                        child: Text(
                          _label(l10n, m),
                          style: TextStyle(
                            fontSize: AppFonts.sm,
                            color: m == current ? AppTheme.accent : AppTheme.fg,
                          ),
                        ),
                      ),
                    )
                    .toList(),
                child: trigger,
              )
            : _DisabledDropdownTrigger(reason: disabledReason!, child: trigger),
      ),
    );
  }

  Widget _buildTrigger(S l10n, int current) {
    return Container(
      height: AppTheme.controlHeightSm,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppTheme.bg3,
        borderRadius: AppTheme.radiusSm,
        border: Border.all(color: AppTheme.borderLight),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _label(l10n, current),
            style: AppFonts.inter(fontSize: AppFonts.sm, color: AppTheme.fg),
          ),
          const SizedBox(width: 4),
          Icon(Icons.arrow_drop_down, size: 18, color: AppTheme.fgDim),
        ],
      ),
    );
  }
}

/// Visual stand-in for a disabled [PopupMenuButton] trigger: hover
/// tooltip plus an info toast on tap explaining why the control is
/// frozen. Keeps the same visual box so the dropdown doesn't appear
/// to "disappear" in disabled states.
class _DisabledDropdownTrigger extends StatelessWidget {
  final String reason;
  final Widget child;

  const _DisabledDropdownTrigger({required this.reason, required this.child});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: reason,
      child: GestureDetector(
        onTap: () =>
            Toast.show(context, message: reason, level: ToastLevel.info),
        child: child,
      ),
    );
  }
}
