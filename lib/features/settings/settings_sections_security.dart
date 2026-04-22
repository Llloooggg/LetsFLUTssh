part of 'settings_screen.dart';

class _SecuritySection extends ConsumerStatefulWidget {
  const _SecuritySection();

  @override
  ConsumerState<_SecuritySection> createState() => _SecuritySectionState();
}

class _SecuritySectionState extends ConsumerState<_SecuritySection> {
  BiometricAvailability _biometricUnavailable;
  bool? _biometricEnabled;
  bool _biometricProbed = false;
  // True while the "Re-check tier support" button is awaiting fresh
  // capability + probe results. Swaps the refresh icon for a small
  // spinner and disables the tap target so the user gets visible
  // feedback that the probe is running (Android / Windows TPM
  // round-trips take hundreds of ms; without a spinner the button
  // feels dead).
  bool _recheckingTiers = false;

  @override
  void initState() {
    super.initState();
    _checkState();
  }

  Future<void> _checkState() async {
    // Biometric probes (slower, platform-dependent) drive the toggle
    // state; kept async off the first paint so an idle D-Bus call
    // never blocks the Settings open.
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

  /// Translate a platform [BiometricUnavailableReason] into a
  /// localised tooltip string, or null if the device is biometric-
  /// capable. Extracted from [_biometricDisabledReason] so the
  /// tier-card spec can check it as the highest-priority tooltip
  /// without falling through the rest of the priority chain.
  String? _biometricPlatformReason(S l10n) {
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
        return null;
    }
  }

  // _biometricDisabledReason + _biometricToggleEnabled used to
  // render the biometric row inside `_activeTierExtras`. After the
  // row moved into every T1 / T2 tier card's modifier section via
  // `BiometricModifierSpec`, `_biometricSpecFor` owns the full
  // priority ladder (platform unavailable → tier unavailable →
  // tier not current → password missing) and the two helpers are
  // no longer called from the widget tree. Kept here as dead-code
  // placeholders would only confuse future readers, so removed.
  //
  // The platform-reason extraction lives on `_biometricPlatformReason`
  // above; that is the only caller-facing helper left.
  /// Localized explanation for why the biometric toggle is disabled —
  /// null means "either fully enabled, or still probing". Three layers
  /// after the bank-style modifier shape:
  ///  * platform / hardware reason from [BiometricAuth.availability]
  ///  * "enable a password first" — biometric is a shortcut for
  ///    entering the password; if the tier does not already hold a
  ///    password (Paranoid always does; T1/T2 only when
  ///    `mods.password == true`), there is nothing to shortcut.

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

  /// Build one tier card pre-wired to onSelectTier. Factored out so
  /// the four stacked cards in the ladder share the same callback +
  /// current-tier / modifiers lookup without re-spelling the three
  /// shared params each time.
  Widget _buildTierCard({
    required SecurityTier tier,
    required SecurityTier currentLevel,
    required SecurityTierModifiers currentModifiers,
    required bool available,
    required String? unavailableReason,
    required S l10n,
  }) {
    final isCurrent =
        tier == currentLevel ||
        (tier == SecurityTier.keychain &&
            currentLevel == SecurityTier.keychainWithPassword);
    return ExpandableTierCard(
      tier: tier,
      currentTier: currentLevel,
      currentModifiers: currentModifiers,
      tierAvailable: available,
      unavailableReason: unavailableReason,
      initiallyExpanded: isCurrent,
      onSelect: onSelectTier,
      activeTierExtras: null,
      biometricSpec: _biometricSpecFor(
        tier: tier,
        currentLevel: currentLevel,
        currentModifiers: currentModifiers,
        tierAvailable: available,
        tierUnavailableReason: unavailableReason,
        l10n: l10n,
      ),
      autoLockRow: _autoLockRowFor(
        tier: tier,
        currentLevel: currentLevel,
        currentModifiers: currentModifiers,
        tierAvailable: available,
        tierUnavailableReason: unavailableReason,
        l10n: l10n,
      ),
    );
  }

  /// Build the auto-lock row for a tier card, or null to hide it.
  /// Shares the same priority ladder as [_biometricSpecFor] so the
  /// two rows always agree on what "tier-gated" means:
  ///
  ///   * T0 — auto-lock is meaningless without a user secret to
  ///     gate; row hidden.
  ///   * T1 / T2 / Paranoid — row always rendered inside the
  ///     expandable. Disabled reason in priority order:
  ///       1. Tier unavailable on this host → tier reason.
  ///       2. Tier not the currently-applied one → "select this
  ///          tier first".
  ///       3. Current tier but no password → "password required".
  ///     Paranoid always carries a password so the third gate never
  ///     fires there.
  Widget? _autoLockRowFor({
    required SecurityTier tier,
    required SecurityTier currentLevel,
    required SecurityTierModifiers currentModifiers,
    required bool tierAvailable,
    required String? tierUnavailableReason,
    required S l10n,
  }) {
    if (tier == SecurityTier.plaintext) return null;
    final isCurrent =
        tier == currentLevel ||
        (tier == SecurityTier.keychain &&
            currentLevel == SecurityTier.keychainWithPassword);
    // Same priority order as the biometric row (see
    // `_biometricSpecFor`), minus the platform-unavailable layer —
    // auto-lock is a software-only feature, always supported by
    // the runtime. "Tier available but not current" wins over
    // "tier unavailable" so the user first sees the actionable
    // hint (select this tier) before the reason the tier is out
    // of reach.
    String? reason;
    if (tierAvailable && !isCurrent) {
      reason = l10n.autoLockRequiresActiveTier;
    } else if (!tierAvailable) {
      reason = tierUnavailableReason;
    } else {
      reason = _autoLockDisabledReason(l10n, currentLevel, currentModifiers);
    }
    return _AutoLockTile(disabledReason: reason);
  }

  /// Build the biometric-modifier spec for a tier card, or null
  /// when the row should be hidden entirely:
  ///
  ///   * T0 — no secret to gate, row hidden.
  ///   * Paranoid — "no OS trust" tier; biometric would route the
  ///     DB key through an OS-backed vault and undermine the
  ///     premise. Row hidden.
  ///   * T1 / T2 — row always rendered. `enabled` flips only when
  ///     the tier is the currently-applied one, the password
  ///     modifier is active, the device has biometric hardware +
  ///     enrolled, and the first probe has completed. Disabled
  ///     cases carry a tooltip explaining *why* the toggle cannot
  ///     flip — "select this tier first", "password required",
  ///     platform-level reason (no sensor, not enrolled, system
  ///     service missing).
  BiometricModifierSpec? _biometricSpecFor({
    required SecurityTier tier,
    required SecurityTier currentLevel,
    required SecurityTierModifiers currentModifiers,
    required bool tierAvailable,
    required String? tierUnavailableReason,
    required S l10n,
  }) {
    if (tier != SecurityTier.keychain && tier != SecurityTier.hardware) {
      return null;
    }
    final isCurrent =
        tier == currentLevel ||
        (tier == SecurityTier.keychain &&
            currentLevel == SecurityTier.keychainWithPassword);

    // Priority 1: biometric platform unavailable. Never let a
    // "select tier first" tooltip mask the fact that the device
    // can't do biometric at all — a user configuring a tier +
    // password only to find out biometric is unreachable at the
    // last step is exactly the churn this priority ordering
    // prevents.
    final platformReason = _biometricPlatformReason(l10n);
    if (platformReason != null) {
      return BiometricModifierSpec(
        enabled: false,
        value: _biometricEnabled == true,
        onChanged: (_) {},
        disabledReason: platformReason,
      );
    }

    // Priority 2: tier available but not currently applied. Short
    // "select this tier first" prompt — the tier's actual
    // availability reason (when applicable) lives on the next
    // priority step below so the user first sees the "how to
    // unlock this" action hint before the "why the tier is out
    // of reach" explanation.
    if (tierAvailable && !isCurrent) {
      return BiometricModifierSpec(
        enabled: false,
        value: _biometricEnabled == true,
        onChanged: (_) {},
        disabledReason: l10n.biometricRequiresActiveTier,
      );
    }

    // Priority 3: tier not available on this host. Re-use the
    // tier's own reason string — same message as the yellow pill
    // on the tier card keeps the UI coherent.
    if (!tierAvailable) {
      return BiometricModifierSpec(
        enabled: false,
        value: _biometricEnabled == true,
        onChanged: (_) {},
        disabledReason: tierUnavailableReason,
      );
    }

    // Priority 4: current tier but password modifier off.
    final hasPassword =
        currentLevel == SecurityTier.paranoid ||
        currentLevel == SecurityTier.keychainWithPassword ||
        currentModifiers.password;
    if (!hasPassword) {
      return BiometricModifierSpec(
        enabled: false,
        value: _biometricEnabled == true,
        onChanged: (_) {},
        disabledReason: l10n.biometricRequiresPassword,
      );
    }

    // All preconditions satisfied — toggle flips via the existing
    // BiometricPrompt + vault-stash flow.
    return BiometricModifierSpec(
      enabled: _biometricProbed,
      value: _biometricEnabled == true,
      onChanged: (v) => _toggleBiometricUnlock(context, v),
      disabledReason: null,
    );
  }

  // `_activeTierExtras` used to carry biometric + auto-lock rows
  // in the current tier's expandable. Both moved into the
  // per-tier-card modifier section (via `biometricSpec` +
  // `autoLockRow`) so the rows render on every T1 / T2 / Paranoid
  // card with the same disabled-reason priority ladder. No caller
  // remains, so the slot is dropped; re-adding the
  // `activeTierExtras` param on `ExpandableTierCard` stays as an
  // extension point.

  /// Public wrapper around [_applyTierChange] that accepts the
  /// card's inline modifier + input state and builds a
  /// [SecuritySetupResult] the existing pipeline already knows how
  /// to consume. Wraps the application in a progress dialog + toast.
  Future<void> onSelectTier({
    required SecurityTier tier,
    required SecurityTierModifiers modifiers,
    String? shortPassword,
    String? pin,
    String? masterPassword,
  }) async {
    final l10n = S.of(context);
    final keychainAvail = ref
        .read(securityCapabilitiesProvider)
        .maybeWhen(data: (c) => c.keychainAvailable, orElse: () => false);
    final result = SecuritySetupResult(
      tier: tier,
      modifiers: modifiers,
      shortPassword: shortPassword,
      pin: pin,
      masterPassword: masterPassword,
      keychainAvailable: keychainAvail,
    );

    final reporter = ProgressReporter(l10n.changeSecurityTierConfirm);
    if (!mounted) return;
    AppProgressBarDialog.show(context, reporter);
    try {
      await _applyTierChange(result);
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
        'Tier change failed: $e',
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

  @override
  Widget build(BuildContext context) {
    final l10n = S.of(context);
    final secState = ref.watch(securityStateProvider);
    final config = ref.watch(configProvider);
    final modifiers =
        config.security?.modifiers ?? SecurityTierModifiers.defaults;

    final caps = ref.watch(securityCapabilitiesProvider);

    // Availability is driven by the classified probe, not the
    // capabilities-provider boolean. The capabilities boolean comes
    // from the fast-path `isAvailable()` (env check + marker file);
    // the classified probe goes further — gdbus ping against
    // `org.freedesktop.secrets` for keyring, native `probeDetail`
    // method-channel call for hardware. The classified probe is the
    // signal that actually maps to "can the user click Select
    // without hitting an error" — e.g. a WSL host with WSLg has
    // D-Bus running (fast path says keychain available) but no
    // secret-service daemon (classified probe says
    // `linuxNoSecretService`), so the fast-path boolean is a lie
    // the user should never see on a tier card.
    //
    // The capabilities boolean is kept as a fallback for the
    // `AsyncValue.loading` / `.error` case so the card renders
    // optimistically while the gdbus call is still in flight.
    final hwDetail = ref.watch(hardwareProbeDetailProvider);
    final hardwareAvail = hwDetail.maybeWhen(
      data: (d) => d == HardwareProbeDetail.available,
      orElse: () => caps.maybeWhen(
        data: (c) => c.hardwareVaultAvailable,
        orElse: () => false,
      ),
    );
    final hwReason = hwDetail.maybeWhen(
      data: (d) => d == HardwareProbeDetail.available
          ? null
          : hardwareProbeDetailText(l10n, d),
      orElse: () => hardwareAvail ? null : l10n.tierHardwareUnavailable,
    );
    final kcDetail = ref.watch(keyringProbeDetailProvider);
    final keychainAvail = kcDetail.maybeWhen(
      data: (d) => d == KeyringProbeResult.available,
      orElse: () =>
          caps.maybeWhen(data: (c) => c.keychainAvailable, orElse: () => true),
    );
    final kcReason = kcDetail.maybeWhen(
      data: (d) => d == KeyringProbeResult.available
          ? null
          : keyringProbeDetailText(l10n, d),
      orElse: () => keychainAvail ? null : l10n.tierKeychainUnavailable,
    );

    return Column(
      children: [
        // Tier ladder: four ExpandableTierCards stacked T0 → T1 →
        // T2 → P. Each card:
        //   * collapsed — shows badge + title + subtitle + a
        //     "Current" pill on the active row.
        //   * expanded — shows the seven-threat split, the
        //     applicable modifier toggles (password / biometric),
        //     the input fields the tier needs (short password /
        //     PIN / master password), and a Select / Apply button.
        //   * unavailable — stays expandable so the user can still
        //     read the threat split, with a yellow reason pill
        //     under the threats and a disabled Select button.
        //
        // Select routes through onSelectTier → _applyTierChange,
        // the same atomic always-rekey pipeline the old wizard
        // invoked. No intermediate dialog — the card is the wizard.
        _buildTierCard(
          tier: SecurityTier.plaintext,
          currentLevel: secState.level,
          currentModifiers: modifiers,
          available: true,
          unavailableReason: null,
          l10n: l10n,
        ),
        _buildTierCard(
          tier: SecurityTier.keychain,
          currentLevel: secState.level,
          currentModifiers: modifiers,
          available: keychainAvail,
          unavailableReason: keychainAvail ? null : kcReason,
          l10n: l10n,
        ),
        _buildTierCard(
          tier: SecurityTier.hardware,
          currentLevel: secState.level,
          currentModifiers: modifiers,
          available: hardwareAvail,
          unavailableReason: hwReason,
          l10n: l10n,
        ),
        _buildTierCard(
          tier: SecurityTier.paranoid,
          currentLevel: secState.level,
          currentModifiers: modifiers,
          available: true,
          unavailableReason: null,
          l10n: l10n,
        ),
        const SizedBox(height: 12),
        // Biometric + auto-lock rows live inside the current tier's
        // expandable (see _activeTierExtras) — they are orthogonal
        // "settings of the current tier" and only meaningful when a
        // user secret exists on the active tier. Keeping them inside
        // the card keeps the security section to a single scannable
        // ladder; a T0 / T1-no-password user sees no dead-lettered
        // toggles in between the cards and the reset-all-data row.

        // Destructive "reset everything" moved to the Data section —
        // it wipes session data + credentials + keychain + hw-vault,
        // which belongs under "manage my data" next to Export /
        // Import. The Security section keeps only tier-config
        // controls (ladder + biometric + auto-lock).

        // Re-check button: forces a fresh capability + probe round-
        // trip when the user has just fixed the underlying issue
        // (enabled TPM in BIOS, installed tpm2-tools, ran
        // macos-resign.sh, changed biometric enrolment, etc.). The
        // probes are normally warmed once on app startup and served
        // from cache for the rest of the session, so without this
        // button the user would have to quit + relaunch after
        // fixing the host state.
        Center(
          child: TextButton.icon(
            icon: _recheckingTiers
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh, size: 16),
            label: Text(l10n.securityRecheck),
            onPressed: _recheckingTiers ? null : _rerunTierProbes,
          ),
        ),
      ],
    );
  }

  /// Invalidate the cached capability + probe snapshots and wait for
  /// the fresh values so the section rebuilds against ready data.
  /// Shows a spinner on the button while the probes run, then surfaces
  /// a toast with the outcome — "support unchanged" if every tier
  /// reports the same availability as before, "support updated" when
  /// any row flipped. Without the toast the button reads as a no-op
  /// on hosts where nothing changed between clicks.
  Future<void> _rerunTierProbes() async {
    setState(() => _recheckingTiers = true);
    // Snapshot the current answers so we can report whether the
    // re-check actually changed anything.
    final previousCaps = ref.read(securityCapabilitiesProvider);
    final previousKc = previousCaps.maybeWhen(
      data: (c) => c.keychainAvailable,
      orElse: () => false,
    );
    final previousHw = previousCaps.maybeWhen(
      data: (c) => c.hardwareVaultAvailable,
      orElse: () => false,
    );
    // Clear the persisted cache before invalidating the provider —
    // otherwise the provider's re-run would read the stale cache
    // back and skip the real probe, defeating the button. The next
    // provider read sees `null` cache → runs a fresh probe → writes
    // the new snapshot back to config.
    await ref
        .read(configProvider.notifier)
        .update((c) => c.copyWith(securityProbeCache: null));
    ref.invalidate(securityCapabilitiesProvider);
    ref.invalidate(hardwareProbeDetailProvider);
    ref.invalidate(keyringProbeDetailProvider);
    try {
      final fresh = await ref.read(securityCapabilitiesProvider.future);
      // Await the detail providers too so the Settings cards rebuild
      // with classified reasons in one frame instead of two.
      await ref.read(hardwareProbeDetailProvider.future);
      await ref.read(keyringProbeDetailProvider.future);
      if (!mounted) return;
      final changed =
          fresh.keychainAvailable != previousKc ||
          fresh.hardwareVaultAvailable != previousHw;
      Toast.show(
        context,
        message: changed
            ? S.of(context).securityRecheckUpdated
            : S.of(context).securityRecheckUnchanged,
        level: changed ? ToastLevel.success : ToastLevel.info,
      );
    } finally {
      if (mounted) setState(() => _recheckingTiers = false);
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
    // Single Argon2id pass: verify + derive at once so the enable flow
    // doesn't double the memory-hard KDF wait on mobile.
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
        // Hardware tier now accepts a passwordless seal: when the
        // wizard returns `pin == null` (user left the password
        // modifier off for T2) the vault derives an empty auth
        // value and seals under SE/TPM isolation alone. The
        // modifiers snapshot `mods.password` stays the source of
        // truth for later unlock flows, so persisting it alongside
        // the tier keeps the read side in sync.
        final key = AesGcm.generateKey();
        final sealed = await hwVault.store(dbKey: key, pin: result.pin);
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
    Widget body = Opacity(
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
                // Match project-wide animation hard-off — PopupMenu
                // owns its own controller and ignores the root
                // `MediaQuery(disableAnimations: true)`.
                popUpAnimationStyle: AnimationStyle.noAnimation,
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
    // Whole-row tooltip on the disabled state so the hover target
    // matches the biometric `_ModifierRow` above — user hovers
    // anywhere on the auto-lock line and sees the reason, not only
    // over the dropdown trigger in the right-hand column.
    if (!enabled && disabledReason != null && disabledReason!.isNotEmpty) {
      body = Tooltip(message: disabledReason!, child: body);
    }
    return body;
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
