part of 'settings_screen.dart';

class _SecuritySection extends ConsumerStatefulWidget {
  const _SecuritySection();

  @override
  ConsumerState<_SecuritySection> createState() => _SecuritySectionState();
}

class _SecuritySectionState extends ConsumerState<_SecuritySection> {
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
    // Keychain probe first — drives the keychain-status info tile.
    // Biometric probes (slower, platform-dependent) land in a second
    // setState so the first paint never blocks on an idle D-Bus call.
    final keyStorage = ref.read(secureKeyStorageProvider);
    final keychainAvailable = await keyStorage.isAvailable();
    if (!mounted) return;
    setState(() {
      _keychainAvailable = keychainAvailable;
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
  /// null means "either fully enabled, or still probing". Three layers
  /// after the bank-style modifier shape:
  ///  * platform / hardware reason from [BiometricAuth.availability]
  ///  * "enable a password first" — biometric is a shortcut for
  ///    entering the password; if the tier does not already hold a
  ///    password (Paranoid always does; T1/T2 only when
  ///    `mods.password == true`), there is nothing to shortcut.
  ///  * legacy fallback: `biometricRequiresMasterPassword` when the
  ///    new copy string has not yet landed in this locale.
  String? _biometricDisabledReason(
    S l10n,
    SecurityTier level,
    SecurityTierModifiers modifiers,
  ) {
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
    final hasPassword =
        level == SecurityTier.paranoid ||
        level == SecurityTier.keychainWithPassword ||
        modifiers.password;
    if (!hasPassword) {
      return l10n.biometricRequiresPassword;
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
  /// Enabled only when the active tier already carries a typed secret
  /// that the biometric shortcut would replace — Paranoid always,
  /// T1/T2 when the password modifier is on.
  bool _biometricToggleEnabled(
    SecurityTier level,
    SecurityTierModifiers modifiers,
  ) {
    if (!_biometricProbed) return false;
    if (_biometricUnavailable != null) return false;
    final hasPassword =
        level == SecurityTier.paranoid ||
        level == SecurityTier.keychainWithPassword ||
        modifiers.password;
    return hasPassword;
  }

  String? _autoLockDisabledReason(
    S l10n,
    SecurityTier level,
    SecurityTierModifiers modifiers,
  ) {
    final hasPassword =
        level == SecurityTier.paranoid ||
        level == SecurityTier.keychainWithPassword ||
        modifiers.password;
    if (hasPassword) return null;
    return l10n.autoLockRequiresPassword;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = S.of(context);
    final secState = ref.watch(securityStateProvider);
    final config = ref.watch(configProvider);
    final modifiers =
        config.security?.modifiers ?? SecurityTierModifiers.defaults;

    return Column(
      children: [
        // Active tier (read-only display). Subtitle reflects the new
        // bank-style modifier shape: "T1 Keychain — password, biometric".
        _InfoTile(
          icon: Icons.shield,
          title: l10n.securityLevel,
          value: _securityLevelLabel(l10n, secState.level, modifiers),
        ),
        // Keychain status — display-only; the tier wizard handles any
        // action that requires reading this value.
        _InfoTile(
          icon: Icons.key,
          title: l10n.keychainStatus,
          value: _keychainStatusLabel(l10n),
        ),
        // Compare tiers — replaces the per-tier AppInfoDialog popups
        // with the single canonical comparison-table widget. One tap
        // from Settings surfaces the full threat-coverage matrix so
        // the user can decide whether a tier change is worth it before
        // they open the wizard.
        _ActionTile(
          icon: Icons.table_chart_outlined,
          title: l10n.compareAllTiers,
          subtitle: l10n.compareAllTiersSubtitle,
          onTap: () => SecurityComparisonTable.show(context),
        ),
        // Change-tier — single entry point for every security change.
        // Opens the tier wizard (pre-marked with the current tier) and
        // routes the result through the atomic always-rekey switcher.
        _ActionTile(
          icon: Icons.shield_outlined,
          title: l10n.changeSecurityTier,
          subtitle: l10n.changeSecurityTierSubtitle,
          onTap: () => _changeSecurityTier(context),
        ),
        // Biometric unlock — orthogonal modifier. The toggle stays
        // visible on every tier so the reason it cannot be flipped is
        // legible (no sensor, nothing enrolled, or tier has no
        // password to shortcut).
        _Toggle(
          label: l10n.biometricUnlockTitle,
          subtitle: _biometricSubtitle(l10n),
          icon: Icons.fingerprint,
          value: _biometricEnabled == true,
          onChanged: _biometricToggleEnabled(secState.level, modifiers)
              ? (v) => _toggleBiometricUnlock(context, v)
              : null,
          disabledReason: _biometricDisabledReason(
            l10n,
            secState.level,
            modifiers,
          ),
        ),
        // Auto-lock — orthogonal modifier. Only meaningful when the
        // active tier holds a user-typed secret; disabled with reason
        // tooltip otherwise.
        _AutoLockTile(
          disabledReason: _autoLockDisabledReason(
            l10n,
            secState.level,
            modifiers,
          ),
        ),
        // Destructive recovery: single place to wipe every piece of
        // on-disk + keychain + hw-vault state this install holds.
        // Needed on desktop where uninstall does not purge keychain
        // entries, and as an escape hatch for forgotten Paranoid
        // master passwords.
        _ActionTile(
          icon: Icons.delete_forever_outlined,
          title: l10n.resetAllDataTitle,
          subtitle: l10n.resetAllDataSubtitle,
          onTap: () => _resetAllData(context),
        ),
      ],
    );
  }

  Future<void> _resetAllData(BuildContext context) async {
    final l10n = S.of(context);
    final confirmed = await ConfirmDialog.show(
      context,
      title: l10n.resetAllDataConfirmTitle,
      content: Text(l10n.resetAllDataConfirmBody),
      confirmLabel: l10n.resetAllDataConfirmAction,
    );
    if (!confirmed) return;
    if (!context.mounted) return;

    final reporter = ProgressReporter(l10n.resetAllDataInProgress);
    AppProgressBarDialog.show(context, reporter);
    try {
      // Close any active DB handle before we drop its file, otherwise
      // SQLite keeps a stale fd pointing at a deleted inode and the
      // next session can't open the fresh one cleanly.
      final service = WipeAllService();
      final report = await service.wipeAll();
      AppLogger.instance.log(
        'Reset all: deleted=${report.deletedFiles.length} '
        'failed=${report.failedFiles.length} '
        'keychain=${report.keychainPurged} '
        'native=${report.nativeVaultCleared} '
        'overlay=${report.biometricOverlayCleared}',
        name: 'Security',
      );
      await ref
          .read(configProvider.notifier)
          .update((c) => c.copyWith(security: null));
      if (context.mounted) {
        Navigator.of(context).pop();
        Toast.show(
          context,
          message: l10n.resetAllDataDone,
          level: ToastLevel.success,
        );
      }
    } catch (e) {
      AppLogger.instance.log(
        'Reset all data failed: $e',
        name: 'Security',
        error: e,
      );
      if (context.mounted) {
        Navigator.of(context).pop();
        Toast.show(
          context,
          message: l10n.resetAllDataFailed,
          level: ToastLevel.error,
        );
      }
    } finally {
      reporter.dispose();
    }
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

  String _securityLevelLabel(
    S l10n,
    SecurityTier level,
    SecurityTierModifiers modifiers,
  ) {
    final base = switch (level) {
      SecurityTier.plaintext => l10n.colT0,
      SecurityTier.keychain => l10n.colT1,
      SecurityTier.keychainWithPassword => l10n.colT1,
      SecurityTier.hardware => l10n.colT2,
      SecurityTier.paranoid => l10n.colParanoid,
    };
    // Paranoid carries an implicit password modifier; no suffix
    // needed for it. Plaintext has no modifiers by definition.
    if (level == SecurityTier.plaintext || level == SecurityTier.paranoid) {
      return base;
    }
    final hasPassword =
        modifiers.password || level == SecurityTier.keychainWithPassword;
    final hasBiometric = modifiers.biometric;
    if (!hasPassword && !hasBiometric) return base;
    final suffix = <String>[
      if (hasPassword) l10n.modifierPasswordLabel.toLowerCase(),
      if (hasBiometric) l10n.modifierBiometricLabel.toLowerCase(),
    ].join(', ');
    return '$base — $suffix';
  }

  /// Open the tier wizard and route the result through the atomic
  /// [SecurityTierSwitcher]. Fresh random DB key on every switch —
  /// the previous wrapper is invalidated and the DB is rekeyed in
  /// a single PRAGMA rekey, so any leaked old wrapper cannot
  /// decrypt the post-switch data.
  Future<void> _changeSecurityTier(BuildContext context) async {
    final l10n = S.of(context);
    final keyStorage = ref.read(secureKeyStorageProvider);
    final currentTier = ref.read(securityStateProvider).level;
    final result = await SecuritySetupDialog.show(
      context,
      keyStorage: keyStorage,
      hardwareVault: ref.read(hardwareTierVaultProvider),
      currentTier: currentTier,
    );
    if (!context.mounted) return;

    final reporter = ProgressReporter(l10n.changeSecurityTierConfirm);
    AppProgressBarDialog.show(context, reporter);
    try {
      await _applyTierChange(result);
      if (context.mounted) {
        Navigator.of(context).pop();
        Toast.show(
          context,
          message: l10n.changeSecurityTierDone,
          level: ToastLevel.success,
        );
        _checkState();
      }
    } catch (e) {
      AppLogger.instance.log(
        'Change security tier failed: $e',
        name: 'Security',
        error: e,
      );
      if (context.mounted) {
        Navigator.of(context).pop();
        Toast.show(
          context,
          message: l10n.changeSecurityTierFailed,
          level: ToastLevel.error,
        );
      }
    } finally {
      reporter.dispose();
    }
  }

  Future<void> _applyTierChange(SecuritySetupResult result) async {
    final keyStorage = ref.read(secureKeyStorageProvider);
    final gate = ref.read(keychainPasswordGateProvider);
    final hwVault = ref.read(hardwareTierVaultProvider);
    final manager = ref.read(masterPasswordProvider);
    final bioVault = ref.read(biometricKeyVaultProvider);

    final mods = result.modifiers;
    switch (result.tier) {
      case SecurityTier.plaintext:
        await _applyAlwaysRekey(null, SecurityTier.plaintext, mods);
        await keyStorage.deleteKey();
        await gate.clear();
        await hwVault.clear();
        if (await manager.isEnabled()) await manager.disable();
        await bioVault.clear();
      case SecurityTier.keychain:
        final key = AesGcm.generateKey();
        final stored = await keyStorage.writeKey(key);
        if (!stored) throw StateError('keychain write failed');
        await _applyAlwaysRekey(key, SecurityTier.keychain, mods);
        await gate.clear();
        await hwVault.clear();
        if (await manager.isEnabled()) await manager.disable();
        await bioVault.clear();
      case SecurityTier.keychainWithPassword:
        final short = result.shortPassword;
        if (short == null || short.isEmpty) {
          throw StateError('short password missing');
        }
        await gate.setPassword(short);
        final key = AesGcm.generateKey();
        final stored = await keyStorage.writeKey(key);
        if (!stored) {
          await gate.clear();
          throw StateError('keychain write failed');
        }
        await _applyAlwaysRekey(key, SecurityTier.keychainWithPassword, mods);
        await hwVault.clear();
        if (await manager.isEnabled()) await manager.disable();
        await bioVault.clear();
      case SecurityTier.hardware:
        final pin = result.pin;
        if (pin == null || pin.isEmpty) throw StateError('pin missing');
        final key = AesGcm.generateKey();
        final sealed = await hwVault.store(dbKey: key, pin: pin);
        if (!sealed) throw StateError('hardware seal failed');
        await _applyAlwaysRekey(key, SecurityTier.hardware, mods);
        await keyStorage.deleteKey();
        await gate.clear();
        if (await manager.isEnabled()) await manager.disable();
        await bioVault.clear();
      case SecurityTier.paranoid:
        final pw = result.masterPassword;
        if (pw == null || pw.isEmpty) {
          throw StateError('master password missing');
        }
        final key = await manager.enable(pw);
        await _applyAlwaysRekey(key, SecurityTier.paranoid, mods);
        await keyStorage.deleteKey();
        await gate.clear();
        await hwVault.clear();
        await bioVault.clear();
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
    final store = ref.read(sessionStoreProvider);
    final db = store.database;
    final resolvedMods = modifiers ?? SecurityTierModifiers.defaults;
    // Marker payload carries tier + modifiers so a crash-recovery
    // path can reconstruct the target config and drive the right
    // unlock prompt (password? biometric? no gate?) instead of
    // falling back to whatever the enum alone suggests.
    final markerPayload = jsonEncode({
      'tier': _tierName(level),
      'mods': resolvedMods.toJson(),
    });
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
            .update((cfg) => cfg.copyWith(security: next));
      },
      clearPrevious: () async {
        // Previous-tier cleanup (biometric vault clear, keychain
        // delete, credentials.kdf remove) is handled by the
        // specific enable/disable/change/remove methods that call
        // into `_applyAlwaysRekey`.
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
