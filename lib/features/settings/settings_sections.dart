part of 'settings_screen.dart';

// ═══════════════════════════════════════════════════════════════════
// Settings content sections — appearance, terminal, connection,
// transfer, data (export/import/QR), updates, about
// ═══════════════════════════════════════════════════════════════════

/// Hydrate [sessions] with on-disk credentials and resolve keyId → keyData.
///
/// The incoming list comes from the in-memory session cache, which strips
/// password / keyData / passphrase to minimize their RAM footprint. Export
/// needs the full credential set, so we reload each session from the DB
/// through [SessionStore.loadWithCredentials] before composing the archive.
/// Key-ID references are then expanded to embedded `keyData` as before.
Future<List<Session>> _resolveSessionKeys(
  WidgetRef ref,
  List<Session> sessions,
) async {
  final store = ref.read(sessionStoreProvider);
  final keyStore = ref.read(keyStoreProvider);
  final resolved = <Session>[];
  for (final cached in sessions) {
    final s = await store.loadWithCredentials(cached.id) ?? cached;
    if (s.keyId.isNotEmpty) {
      final entry = await keyStore.get(s.keyId);
      if (entry != null && entry.privateKey.isNotEmpty) {
        resolved.add(
          s.copyWith(auth: s.auth.copyWith(keyData: entry.privateKey)),
        );
        continue;
      }
    }
    resolved.add(s);
  }
  return resolved;
}

/// Data section — groups export, import, QR, and data path tiles.
class _DataSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(children: [_ExportImportTile(), const _DataPathTile()]);
  }
}

class _AppearanceSection extends ConsumerWidget {
  const _AppearanceSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(configProvider.select((c) => c.locale));
    final theme = ref.watch(configProvider.select((c) => c.theme));
    final fontSize = ref.watch(configProvider.select((c) => c.fontSize));
    final uiScale = ref.watch(configProvider.select((c) => c.uiScale));
    return Column(
      children: [
        _LanguageTile(
          value: locale,
          onChanged: (v) => ref
              .read(configProvider.notifier)
              .update((c) => c.copyWith(locale: v)),
        ),
        _ThemeTile(
          value: theme,
          onChanged: (v) => ref
              .read(configProvider.notifier)
              .update(
                (c) => c.copyWith(terminal: c.terminal.copyWith(theme: v)),
              ),
        ),
        _SliderTile(
          title: S.of(context).uiScale,
          subtitle: S.of(context).uiScaleSubtitle,
          icon: Icons.aspect_ratio,
          value: uiScale,
          min: 0.5,
          max: 2.0,
          divisions: 15,
          format: (v) => '${(v * 100).round()}%',
          onChanged: (v) => ref
              .read(configProvider.notifier)
              .update((c) => c.copyWith(ui: c.ui.copyWith(uiScale: v))),
        ),
        _SliderTile(
          title: S.of(context).terminalFontSize,
          subtitle: S.of(context).terminalFontSizeSubtitle,
          icon: Icons.format_size,
          value: fontSize,
          min: 8,
          max: 24,
          divisions: 16,
          format: (v) => '${v.round()}',
          onChanged: (v) => ref
              .read(configProvider.notifier)
              .update(
                (c) => c.copyWith(terminal: c.terminal.copyWith(fontSize: v)),
              ),
        ),
      ],
    );
  }
}

class _TerminalSection extends ConsumerWidget {
  const _TerminalSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scrollback = ref.watch(configProvider.select((c) => c.scrollback));
    return _IntTile(
      title: S.of(context).scrollbackLines,
      subtitle: S.of(context).scrollbackLinesSubtitle,
      icon: Icons.history,
      value: scrollback,
      min: 100,
      max: 100000,
      onChanged: (v) => ref
          .read(configProvider.notifier)
          .update(
            (c) => c.copyWith(terminal: c.terminal.copyWith(scrollback: v)),
          ),
    );
  }
}

class _ConnectionSection extends ConsumerWidget {
  const _ConnectionSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final keepAlive = ref.watch(configProvider.select((c) => c.keepAliveSec));
    final timeout = ref.watch(configProvider.select((c) => c.sshTimeoutSec));
    final port = ref.watch(configProvider.select((c) => c.defaultPort));
    return Column(
      children: [
        _IntTile(
          title: S.of(context).keepAliveInterval,
          subtitle: S.of(context).keepAliveIntervalSubtitle,
          icon: Icons.wifi_tethering,
          value: keepAlive,
          min: 0,
          max: 300,
          onChanged: (v) => ref
              .read(configProvider.notifier)
              .update((c) => c.copyWith(ssh: c.ssh.copyWith(keepAliveSec: v))),
        ),
        _IntTile(
          title: S.of(context).sshTimeout,
          subtitle: S.of(context).sshTimeoutSubtitle,
          icon: Icons.timer_outlined,
          value: timeout,
          min: 1,
          max: 60,
          onChanged: (v) => ref
              .read(configProvider.notifier)
              .update((c) => c.copyWith(ssh: c.ssh.copyWith(sshTimeoutSec: v))),
        ),
        _IntTile(
          title: S.of(context).defaultPort,
          subtitle: S.of(context).defaultPortSubtitle,
          icon: Icons.settings_ethernet,
          value: port,
          min: 1,
          max: 65535,
          onChanged: (v) => ref
              .read(configProvider.notifier)
              .update((c) => c.copyWith(ssh: c.ssh.copyWith(defaultPort: v))),
        ),
      ],
    );
  }
}

class _SecuritySection extends ConsumerStatefulWidget {
  const _SecuritySection();

  @override
  ConsumerState<_SecuritySection> createState() => _SecuritySectionState();
}

class _SecuritySectionState extends ConsumerState<_SecuritySection> {
  bool? _masterPasswordEnabled;
  bool? _keychainAvailable;
  bool? _biometricAvailable;
  bool? _biometricEnabled;

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
    final bioResults = await Future.wait([
      bio.isAvailable(),
      bioVault.isStored(),
    ]);
    if (!mounted) return;
    setState(() {
      _biometricAvailable = bioResults[0];
      _biometricEnabled = bioResults[1];
    });
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
        // Biometric unlock — only rendered when the device actually has
        // biometric hardware. Hidden on headless/Linux so the settings
        // layout stays compact (and so our existing tests that tap by
        // absolute offset still land on the right widgets).
        if (_biometricAvailable == true)
          _Toggle(
            label: l10n.biometricUnlockTitle,
            subtitle: l10n.biometricUnlockSubtitle,
            icon: Icons.fingerprint,
            value: _biometricEnabled == true,
            onChanged: secState.level == SecurityLevel.masterPassword
                ? (v) => _toggleBiometricUnlock(context, v)
                : null,
          ),
        // Auto-lock — only meaningful in masterPassword mode, since lock
        // zeroes the DB key and relies on the MP prompt (or biometrics)
        // to restore it. In plaintext/keychain there is no secret to
        // re-prove, so the row is hidden.
        if (secState.level == SecurityLevel.masterPassword) _AutoLockTile(),
      ],
    );
  }

  Future<void> _toggleBiometricUnlock(BuildContext context, bool enable) async {
    final l10n = S.of(context);
    if (enable) {
      // Enabling: ask the user for their master password so we can cache the
      // DB key in the biometric-gated vault. Without a fresh prompt there's
      // nothing to cache — the live key in SecurityState is the same bytes,
      // but requiring the password here matches user expectation and rejects
      // accidental taps.
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
      final ok = await bio.authenticate(l10n.biometricUnlockPrompt);
      if (!ok) return;
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
    } else {
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
  }

  String _keychainStatusLabel(S l10n) {
    if (_keychainAvailable == true) {
      return l10n.keychainAvailable(_keychainName);
    }
    if (_keychainAvailable == false) {
      return l10n.keychainNotAvailable;
    }
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

  static String get _keychainName {
    if (Platform.isMacOS || Platform.isIOS) return 'Keychain';
    if (Platform.isWindows) return 'Credential Manager';
    if (Platform.isAndroid) return 'EncryptedSharedPreferences';
    return 'libsecret';
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

class _TransferSection extends ConsumerWidget {
  const _TransferSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workers = ref.watch(configProvider.select((c) => c.transferWorkers));
    final maxHistory = ref.watch(configProvider.select((c) => c.maxHistory));
    final showFolderSizes = ref.watch(
      configProvider.select((c) => c.showFolderSizes),
    );
    return Column(
      children: [
        _IntTile(
          title: S.of(context).parallelWorkers,
          subtitle: S.of(context).parallelWorkersSubtitle,
          icon: Icons.multiple_stop,
          value: workers,
          min: 1,
          max: 10,
          onChanged: (v) => ref
              .read(configProvider.notifier)
              .update((c) => c.copyWith(transferWorkers: v)),
        ),
        _IntTile(
          title: S.of(context).maxHistory,
          subtitle: S.of(context).maxHistorySubtitle,
          icon: Icons.manage_history,
          value: maxHistory,
          min: 10,
          max: 5000,
          onChanged: (v) => ref
              .read(configProvider.notifier)
              .update((c) => c.copyWith(maxHistory: v)),
        ),
        _Toggle(
          label: S.of(context).calculateFolderSizes,
          subtitle: S.of(context).calculateFolderSizesSubtitle,
          icon: Icons.folder_open,
          value: showFolderSizes,
          onChanged: (v) => ref
              .read(configProvider.notifier)
              .update((c) => c.copyWith(ui: c.ui.copyWith(showFolderSizes: v))),
        ),
      ],
    );
  }
}

class _ExportImportTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        _ActionTile(
          icon: Icons.upload_file,
          title: S.of(context).exportArchive,
          subtitle: S.of(context).exportArchiveSubtitle,
          onTap: () => _showExportDialog(context, ref),
        ),
        const _QrExportTile(),
        _ActionTile(
          icon: Icons.download,
          title: S.of(context).importArchive,
          subtitle: S.of(context).importArchiveSubtitle,
          onTap: () => _showImportDialog(context, ref),
        ),
        _ActionTile(
          icon: Icons.link,
          title: S.of(context).importFromLink,
          subtitle: S.of(context).importFromLinkSubtitle,
          onTap: () => _showPasteImportLink(context, ref),
        ),
        _ActionTile(
          icon: Icons.folder_shared_outlined,
          title: S.of(context).importFromSshDir,
          subtitle: S.of(context).importFromSshDirSubtitle,
          onTap: () => _showSshDirImportDialog(context, ref),
        ),
      ],
    );
  }

  Future<void> _showPasteImportLink(BuildContext context, WidgetRef ref) async {
    final data = await PasteImportLinkDialog.show(context);
    if (data == null || !context.mounted) return;
    await _applyFilteredImport(
      context,
      ref,
      ImportResult(
        sessions: data.sessions,
        emptyFolders: data.emptyFolders,
        managerKeys: data.managerKeys,
        tags: data.tags,
        sessionTags: data.sessionTags,
        folderTags: data.folderTags,
        snippets: data.snippets,
        sessionSnippets: data.sessionSnippets,
        config: data.config,
        mode: ImportMode.merge,
        knownHostsContent: data.knownHostsContent,
        includeTags: data.tags.isNotEmpty,
        includeSnippets: data.snippets.isNotEmpty,
        includeKnownHosts: data.knownHostsContent != null,
      ),
    );
  }

  Future<void> _showSshDirImportDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    try {
      final sshDir = p.join(plat.homeDirectory, '.ssh');
      final configPath = p.join(sshDir, 'config');
      final keyStore = ref.read(keyStoreProvider);

      // Scan keys regardless of config presence — user may want to import
      // just the standalone keys.
      final scannedKeys = SshDirKeyScanner().scan(sshDir);

      // Parse config if present. Missing file = no hosts, dialog still shows
      // the keys section.
      OpenSshConfigImportPreview? preview;
      final date = DateTime.now().toIso8601String().split('T').first;
      final folderLabel = S.of(context).sshConfigImportFolderName(date);
      final configFile = File(configPath);
      if (await configFile.exists()) {
        final content = await configFile.readAsString();
        preview = OpenSshConfigImporter().buildPreview(
          configContent: content,
          folderLabel: folderLabel,
          keyLabelSuffix: date,
        );
      }
      if (!context.mounted) return;

      // Nothing to show at all — surface a warning and bail.
      if (scannedKeys.isEmpty && (preview?.result.sessions.isEmpty ?? true)) {
        Toast.show(
          context,
          message: S.of(context).fileNotFound(sshDir),
          level: ToastLevel.warning,
        );
        return;
      }

      final existing = await keyStore.loadAll();
      final existingFingerprints = existing.values
          .map((e) => KeyStore.privateKeyFingerprint(e.privateKey))
          .toSet();
      final existingSessionAddresses = ref
          .read(sessionProvider)
          .map(sshDirSessionAddress)
          .toSet();
      if (!context.mounted) return;

      final filtered = await SshDirImportDialog.show(
        context,
        source: SshDirImportSource(
          hostsPreview: preview,
          keys: scannedKeys,
          existingKeyFingerprints: existingFingerprints,
          existingSessionAddresses: existingSessionAddresses,
          folderLabel: folderLabel,
        ),
        onPickConfigFile: () => _pickConfigFile(sshDir, folderLabel, date),
        onPickKeyFiles: () => _pickKeyFiles(sshDir),
      );
      if (filtered == null || !context.mounted) return;
      if (filtered.sessions.isEmpty && filtered.managerKeys.isEmpty) return;

      await _applyFilteredImport(context, ref, filtered);
    } catch (e) {
      AppLogger.instance.log(
        'SSH dir import failed: $e',
        name: 'Settings',
        error: e,
      );
      if (context.mounted) {
        Toast.show(
          context,
          message: S.of(context).importFailed(localizeError(S.of(context), e)),
          level: ToastLevel.error,
        );
      }
    }
  }

  /// File-picker that lets the user select an extra OpenSSH config file and
  /// returns its parsed hosts. [initialDir] seeds the native dialog at
  /// `~/.ssh` on desktop; mobile platforms ignore it and use the system
  /// default. Returns null on cancel / read error.
  Future<PickedConfigResult?> _pickConfigFile(
    String initialDir,
    String folderLabel,
    String keyLabelSuffix,
  ) async {
    final result = await FilePicker.pickFiles(
      initialDirectory: initialDir,
      type: FileType.any,
    );
    final path = result?.files.single.path;
    if (path == null) return null;
    try {
      final content = await File(path).readAsString();
      final preview = OpenSshConfigImporter().buildPreview(
        configContent: content,
        folderLabel: folderLabel,
        keyLabelSuffix: keyLabelSuffix,
      );
      return PickedConfigResult(
        sessions: preview.result.sessions,
        managerKeys: preview.result.managerKeys,
        hostsWithMissingKeys: preview.hostsWithMissingKeys,
      );
    } catch (e) {
      AppLogger.instance.log(
        'Failed to parse picked SSH config: $e',
        name: 'Settings',
        error: e,
      );
      return null;
    }
  }

  /// File-picker for extra SSH private keys. Multi-select; files that don't
  /// look like a PEM private key are silently dropped. Returns null on cancel.
  Future<List<ScannedKey>?> _pickKeyFiles(String initialDir) async {
    final result = await FilePicker.pickFiles(
      initialDirectory: initialDir,
      type: FileType.any,
      allowMultiple: true,
    );
    if (result == null) return null;
    final picked = <ScannedKey>[];
    for (final f in result.files) {
      final path = f.path;
      if (path == null) continue;
      final pem = KeyFileHelper.tryReadPemKey(path);
      if (pem == null) continue;
      picked.add(
        ScannedKey(
          path: path,
          pem: pem,
          suggestedLabel: p.basenameWithoutExtension(path),
        ),
      );
    }
    return picked;
  }

  Future<void> _showExportDialog(BuildContext context, WidgetRef ref) async {
    final sessions = ref.read(sessionProvider);
    final store = ref.read(sessionStoreProvider);

    // Load counts for export dialog
    final keyStore = ref.read(keyStoreProvider);
    final tagStore = ref.read(tagStoreProvider);
    final snippetStore = ref.read(snippetStoreProvider);
    final allKeys = await keyStore.loadAll();
    final allTags = await tagStore.loadAll();
    final allSnippets = await snippetStore.loadAll();
    if (!context.mounted) return;
    final managerKeys = Map<String, String>.fromEntries(
      allKeys.entries.map((e) => MapEntry(e.key, e.value.privateKey)),
    );

    final exportResult = await UnifiedExportDialog.show(
      context,
      data: UnifiedExportDialogData(
        sessions: sessions,
        emptyFolders: store.emptyFolders,
        config: ref.read(configProvider),
        knownHostsContent: ref.read(knownHostsProvider).exportToString(),
        managerKeys: managerKeys,
        managerKeyEntries: allKeys,
        tags: allTags,
        snippets: allSnippets,
      ),
      isQrMode: false,
    );

    if (exportResult == null || !context.mounted) return;

    // Show password dialog
    final passwordCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();

    try {
      final password = await AppDialog.show<String>(
        context,
        builder: (ctx) => _ExportPasswordDialog(
          passwordCtrl: passwordCtrl,
          confirmCtrl: confirmCtrl,
        ),
      );

      if (password == null || !context.mounted) return;

      final timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')
          .first;
      final outputPath = await _pickSavePath(
        context,
        'export_$timestamp.lfs',
        'lfs',
      );
      if (outputPath == null || !context.mounted) return;

      await _runExport(context, ref, password, outputPath, exportResult);
    } catch (e) {
      AppLogger.instance.log('Export failed: $e', name: 'Settings', error: e);
      if (context.mounted) {
        Toast.show(
          context,
          message: S.of(context).exportFailed(localizeError(S.of(context), e)),
          level: ToastLevel.error,
        );
      }
    } finally {
      passwordCtrl.dispose();
      confirmCtrl.dispose();
    }
  }

  Future<void> _runExport(
    BuildContext context,
    WidgetRef ref,
    String password,
    String outputPath,
    UnifiedExportResult exportResult,
  ) async {
    // Resolve keyId → keyData for actual export
    final resolvedSessions = await _resolveSessionKeys(
      ref,
      exportResult.selectedSessions,
    );

    if (!context.mounted) return;

    // Progress bar covers the collection, PBKDF2+encryption, and write steps.
    final l10n = S.of(context);
    final reporter = ProgressReporter(l10n.progressCollectingData);
    AppProgressBarDialog.show(context, reporter);
    try {
      final managerKeyEntries = await _collectManagerKeys(ref, exportResult);
      final (tags, sessionTags) = await _collectTags(ref, exportResult);
      final (snippets, sessionSnippets) = await _collectSnippets(
        ref,
        exportResult,
      );

      await ExportImport.export(
        masterPassword: password,
        outputPath: outputPath,
        progress: reporter,
        l10n: l10n,
        input: LfsExportInput(
          sessions: resolvedSessions,
          config: ref.read(configProvider),
          options: exportResult.options,
          emptyFolders: exportResult.options.includeSessions
              ? exportResult.selectedEmptyFolders
              : {},
          knownHostsContent: exportResult.options.includeKnownHosts
              ? ref.read(knownHostsProvider).exportToString()
              : null,
          managerKeyEntries: managerKeyEntries,
          tags: tags,
          sessionTags: sessionTags,
          snippets: snippets,
          sessionSnippets: sessionSnippets,
        ),
      );
      if (context.mounted) {
        Navigator.of(context).pop();
        Toast.show(
          context,
          message: S.of(context).exportedTo(outputPath),
          level: ToastLevel.success,
        );
      }
    } catch (e) {
      if (context.mounted) Navigator.of(context).pop();
      rethrow;
    } finally {
      reporter.dispose();
    }
  }

  Future<List<SshKeyEntry>> _collectManagerKeys(
    WidgetRef ref,
    UnifiedExportResult exportResult,
  ) async {
    final managerKeyEntries = <SshKeyEntry>[];
    if (!exportResult.options.hasManagerKeys) return managerKeyEntries;
    final keyStore = ref.read(keyStoreProvider);
    final allKeys = await keyStore.loadAll();
    if (exportResult.options.includeAllManagerKeys) {
      managerKeyEntries.addAll(allKeys.values);
    } else {
      final usedKeyIds = exportResult.selectedSessions
          .where((s) => s.keyId.isNotEmpty)
          .map((s) => s.keyId)
          .toSet();
      managerKeyEntries.addAll(
        allKeys.entries
            .where((e) => usedKeyIds.contains(e.key))
            .map((e) => e.value),
      );
    }
    return managerKeyEntries;
  }

  Future<(List<Tag>, List<ExportLink>)> _collectTags(
    WidgetRef ref,
    UnifiedExportResult exportResult,
  ) async {
    final tagStore = ref.read(tagStoreProvider);
    final tags = exportResult.options.includeTags
        ? await tagStore.loadAll()
        : <Tag>[];
    final sessionTags = <ExportLink>[];
    if (tags.isEmpty) return (tags, sessionTags);
    for (final s in exportResult.selectedSessions) {
      final sTags = await tagStore.getForSession(s.id);
      for (final t in sTags) {
        sessionTags.add(ExportLink(sessionId: s.id, targetId: t.id));
      }
    }
    return (tags, sessionTags);
  }

  Future<(List<Snippet>, List<ExportLink>)> _collectSnippets(
    WidgetRef ref,
    UnifiedExportResult exportResult,
  ) async {
    final snippetStore = ref.read(snippetStoreProvider);
    final snippets = exportResult.options.includeSnippets
        ? await snippetStore.loadAll()
        : <Snippet>[];
    final sessionSnippets = <ExportLink>[];
    if (snippets.isEmpty) return (snippets, sessionSnippets);
    for (final s in exportResult.selectedSessions) {
      final sSnippets = await snippetStore.loadForSession(s.id);
      for (final sn in sSnippets) {
        sessionSnippets.add(ExportLink(sessionId: s.id, targetId: sn.id));
      }
    }
    return (snippets, sessionSnippets);
  }

  /// Opens a save-file picker.
  ///
  /// * Desktop — native save dialog (`FilePicker.saveFile`).
  /// * Android with `MANAGE_EXTERNAL_STORAGE` — in-app directory picker
  ///   that walks the filesystem via `dart:io`.  Using SAF here is the
  ///   bug we're fixing: `ACTION_OPEN_DOCUMENT_TREE` asks the user for
  ///   per-folder consent on every export even when all-files access is
  ///   already granted.
  /// * Android without all-files access, iOS — standard SAF-backed
  ///   `FilePicker.getDirectoryPath` (unavoidable: no other way to reach
  ///   user-visible folders when the app is scoped-storage-only).
  Future<String?> _pickSavePath(
    BuildContext context,
    String defaultName,
    String extension,
  ) async {
    final title = S.of(context).chooseSaveLocation;
    final initDir = await _defaultDirectory();
    if (plat.isDesktopPlatform) {
      return FilePicker.saveFile(
        dialogTitle: title,
        fileName: defaultName,
        initialDirectory: initDir,
        type: FileType.custom,
        allowedExtensions: [extension],
      );
    }
    if (Platform.isAndroid) {
      final granted = await requestAndroidStoragePermission();
      if (granted) {
        if (!context.mounted) return null;
        final dir = await LocalDirectoryPicker.show(
          context,
          title: title,
          initialPath: initDir ?? '/storage/emulated/0',
        );
        if (dir == null) return null;
        return p.join(dir, defaultName);
      }
    }
    // iOS or Android without all-files access — fall back to SAF picker.
    // SAF can throw (e.g. the system picker crashes or the OEM skin blocks it
    // entirely). Surface a localized toast instead of bubbling up a raw
    // `PlatformException`, and log so we have diagnostics on OEMs that ship
    // broken pickers.
    String? dir;
    try {
      dir = await FilePicker.getDirectoryPath(
        dialogTitle: title,
        initialDirectory: initDir,
      );
    } catch (e) {
      AppLogger.instance.log(
        'SAF getDirectoryPath failed: $e',
        name: 'Export',
        error: e,
      );
      if (context.mounted) {
        Toast.show(
          context,
          message: S.of(context).errExportPickerUnavailable,
          level: ToastLevel.error,
        );
      }
      return null;
    }
    if (dir == null) return null;
    return p.join(dir, defaultName);
  }

  Future<String?> _pickLfsFile(BuildContext context) async {
    final title = S.of(context).pathToLfsFile;
    final initDir = await _defaultDirectory();
    final result = await FilePicker.pickFiles(
      dialogTitle: title,
      initialDirectory: initDir,
      type: FileType.custom,
      allowedExtensions: ['lfs'],
    );
    return result?.files.single.path;
  }

  Future<void> _showImportDialog(BuildContext context, WidgetRef ref) async {
    final path = await _pickLfsFile(context);
    if (path == null || !context.mounted) return;

    final passwordCtrl = TextEditingController();
    try {
      final password = await AppDialog.show<String>(
        context,
        builder: (ctx) => _ImportPasswordDialog(passwordCtrl: passwordCtrl),
      );
      if (password == null || !context.mounted) return;

      // Decrypt once — reuse for both preview and import to avoid running
      // the expensive PBKDF2 key derivation (600k iterations) twice.
      final l10n = S.of(context);
      final reporter = ProgressReporter(l10n.progressReadingArchive);
      AppProgressBarDialog.show(context, reporter);
      var progressShown = true;
      final ImportResult fullImport;
      try {
        fullImport = await ExportImport.import_(
          filePath: path,
          masterPassword: password,
          mode: ImportMode.merge, // placeholder — user picks mode in preview
          options: const ExportOptions(
            includeSessions: true,
            includeConfig: true,
            includeKnownHosts: true,
            includeAllManagerKeys: true,
            includeTags: true,
            includeSnippets: true,
          ),
          progress: reporter,
          l10n: l10n,
        );
      } finally {
        if (progressShown && context.mounted) {
          Navigator.of(context).pop();
          progressShown = false;
        }
        reporter.dispose();
      }
      if (!context.mounted) return;

      final preview = LfsPreview(
        sessions: fullImport.sessions,
        hasConfig: fullImport.config != null,
        hasKnownHosts:
            fullImport.knownHostsContent != null &&
            fullImport.knownHostsContent!.isNotEmpty,
        emptyFolders: fullImport.emptyFolders,
        managerKeyCount: fullImport.managerKeys.length,
        tagCount: fullImport.tags.length,
        snippetCount: fullImport.snippets.length,
      );

      final importConfig = await LfsImportPreviewDialog.show(
        context,
        filePath: path,
        preview: preview,
      );
      if (importConfig == null || !context.mounted) return;

      final filteredResult = fullImport.filtered(
        importConfig.options,
        importConfig.mode,
      );
      await _applyFilteredImport(context, ref, filteredResult);
    } catch (e) {
      AppLogger.instance.log('Import failed: $e', name: 'Settings', error: e);
      if (context.mounted) {
        Toast.show(
          context,
          message: S.of(context).importFailed(localizeError(S.of(context), e)),
          level: ToastLevel.error,
        );
      }
    } finally {
      passwordCtrl.dispose();
    }
  }

  /// Apply an already-decrypted [ImportResult] to state.
  ///
  /// Called after the archive has been decrypted once (for preview) and
  /// filtered by the user's data-type selections.
  Future<void> _applyFilteredImport(
    BuildContext context,
    WidgetRef ref,
    ImportResult importResult,
  ) async {
    final l10n = S.of(context);
    final reporter = ProgressReporter(l10n.progressWorking);
    AppProgressBarDialog.show(context, reporter);
    var progressShown = true;
    try {
      final store = ref.read(sessionStoreProvider);
      final keyStore = ref.read(keyStoreProvider);
      final tagStore = ref.read(tagStoreProvider);
      final snippetStore = ref.read(snippetStoreProvider);
      final knownHostsMgr = ref.read(knownHostsProvider);
      final importService = ImportService(
        addSession: (s) => ref.read(sessionProvider.notifier).add(s),
        addEmptyFolder: (f) =>
            ref.read(sessionProvider.notifier).addEmptyFolder(f),
        deleteSession: (id) => ref.read(sessionProvider.notifier).delete(id),
        getSessions: () => ref.read(sessionProvider),
        applyConfig: (config) =>
            ref.read(configProvider.notifier).update((_) => config),
        saveManagerKey: (entry) => keyStore.importForMerge(entry),
        saveTag: (tag) async {
          await tagStore.add(tag);
          return tag.id;
        },
        tagSession: tagStore.tagSession,
        tagFolder: (folderId, tagId) => tagStore.tagFolder(folderId, tagId),
        saveSnippet: (snippet) async {
          await snippetStore.add(snippet);
          return snippet.id;
        },
        linkSnippetToSession: snippetStore.linkToSession,
        getEmptyFolders: () => store.emptyFolders,
        restoreSnapshot: (sessions, folders) =>
            store.restoreSnapshot(sessions, folders),
        existingTagIds: () async =>
            (await tagStore.loadAll()).map((t) => t.id).toSet(),
        existingSnippetIds: () async =>
            (await snippetStore.loadAll()).map((s) => s.id).toSet(),
        getCurrentConfig: () => ref.read(configProvider),
        loadAllTags: () => tagStore.loadAll(),
        deleteAllTags: () => tagStore.deleteAll(),
        loadAllSnippets: () => snippetStore.loadAll(),
        deleteAllSnippets: () => snippetStore.deleteAll(),
        exportKnownHosts: () async => knownHostsMgr.exportToString(),
        clearKnownHosts: () => knownHostsMgr.clearAll(),
        importKnownHosts: (content) async {
          await knownHostsMgr.importFromString(content);
        },
        runInTransaction: store.database == null
            ? null
            : <T>(body) => store.database!.transaction(body),
      );
      final summary = await importService.applyResult(
        importResult,
        progress: reporter,
        l10n: l10n,
      );

      if (context.mounted) {
        Navigator.of(context).pop();
        progressShown = false;
        Toast.show(
          context,
          message: formatImportSummary(S.of(context), summary),
          level: ToastLevel.success,
        );
      }
    } catch (e) {
      AppLogger.instance.log('Import failed: $e', name: 'Settings', error: e);
      if (progressShown && context.mounted) {
        Navigator.of(context).pop();
        progressShown = false;
      }
      if (context.mounted) {
        Toast.show(
          context,
          message: S.of(context).importFailed(localizeError(S.of(context), e)),
          level: ToastLevel.error,
        );
      }
    } finally {
      if (progressShown && context.mounted) {
        Navigator.of(context).pop();
      }
      reporter.dispose();
    }
  }
}

class _UpdateSection extends ConsumerWidget {
  const _UpdateSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final checkOnStart = ref.watch(
      configProvider.select((c) => c.checkUpdatesOnStart),
    );
    final updateState = ref.watch(updateProvider);

    return Column(
      children: [
        _Toggle(
          label: S.of(context).checkForUpdatesOnStartup,
          subtitle: S.of(context).checkForUpdatesOnStartupSubtitle,
          icon: Icons.system_update_alt,
          value: checkOnStart,
          onChanged: (v) => ref
              .read(configProvider.notifier)
              .update(
                (c) => c.copyWith(
                  behavior: c.behavior.copyWith(checkUpdatesOnStart: v),
                ),
              ),
        ),
        _buildCheckButton(context, ref, updateState),
        _buildStatusWidget(context, ref, updateState),
      ],
    );
  }

  Widget _buildCheckButton(
    BuildContext context,
    WidgetRef ref,
    UpdateState updateState,
  ) {
    final isChecking = updateState.status == UpdateStatus.checking;
    return ListTile(
      leading: isChecking
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.refresh, size: 20),
      title: Text(
        isChecking ? S.of(context).checking : S.of(context).checkForUpdates,
      ),
      contentPadding: EdgeInsets.zero,
      onTap: isChecking
          ? null
          : () async {
              await ref.read(updateProvider.notifier).check();
              if (!context.mounted) return;
              final state = ref.read(updateProvider);
              if (state.status == UpdateStatus.upToDate) {
                Toast.show(
                  context,
                  message: S.of(context).youreRunningLatest,
                  level: ToastLevel.success,
                );
              } else if (state.status == UpdateStatus.updateAvailable) {
                Toast.show(
                  context,
                  message: S
                      .of(context)
                      .versionAvailable(state.info!.latestVersion),
                  level: ToastLevel.info,
                );
              } else if (state.status == UpdateStatus.error) {
                Toast.show(
                  context,
                  message: state.error != null
                      ? S
                            .of(context)
                            .errDownloadFailed(
                              localizeError(S.of(context), state.error!),
                            )
                      : S.of(context).updateCheckFailed,
                  level: ToastLevel.error,
                );
              }
            },
    );
  }

  Widget _buildStatusWidget(
    BuildContext context,
    WidgetRef ref,
    UpdateState updateState,
  ) {
    final theme = Theme.of(context);

    switch (updateState.status) {
      case UpdateStatus.idle:
      case UpdateStatus.checking:
        return const SizedBox.shrink();

      case UpdateStatus.upToDate:
        return ListTile(
          leading: Icon(
            Icons.check_circle_outline,
            size: 20,
            color: theme.colorScheme.primary,
          ),
          title: Text(S.of(context).youreUpToDate),
          contentPadding: EdgeInsets.zero,
        );

      case UpdateStatus.updateAvailable:
        return _buildUpdateAvailable(context, ref, updateState);

      case UpdateStatus.downloading:
        // Linear progress gives the user a much clearer sense of how far
        // the download has gone than a 20-px spinner — pair it with a
        // percent-annotated caption for screen readers.
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                S
                    .of(context)
                    .downloadingPercent((updateState.progress * 100).toInt()),
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: AppTheme.radiusSm,
                child: LinearProgressIndicator(
                  value: updateState.progress > 0 ? updateState.progress : null,
                  minHeight: 6,
                ),
              ),
            ],
          ),
        );

      case UpdateStatus.downloaded:
        return _buildDownloaded(context, ref, updateState);

      case UpdateStatus.error:
        return ListTile(
          leading: Icon(
            Icons.error_outline,
            size: 20,
            color: theme.colorScheme.error,
          ),
          title: Text(S.of(context).updateCheckFailed),
          subtitle: Text(
            updateState.error != null
                ? localizeError(S.of(context), updateState.error!)
                : S.of(context).unknownError,
            style: TextStyle(
              fontSize: AppFonts.md,
              color: theme.colorScheme.error,
            ),
          ),
          contentPadding: EdgeInsets.zero,
        );
    }
  }

  Widget _buildUpdateAvailable(
    BuildContext context,
    WidgetRef ref,
    UpdateState updateState,
  ) {
    final info = updateState.info!;
    final hasAsset = info.assetUrl != null;
    final skipped = ref.watch(configProvider.select((c) => c.skippedVersion));
    final isSkipped = skipped == info.latestVersion;

    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.system_update, size: 20),
          title: Text(S.of(context).versionAvailable(info.latestVersion)),
          subtitle: Text(S.of(context).currentVersion(info.currentVersion)),
          contentPadding: EdgeInsets.zero,
        ),
        Padding(
          padding: const EdgeInsets.only(left: 8),
          child: Wrap(
            spacing: 8,
            children: [
              _ChangelogButton(changelog: info.changelog),
              if (hasAsset && plat.isDesktopPlatform)
                FilledButton.icon(
                  onPressed: () => ref.read(updateProvider.notifier).download(),
                  icon: const Icon(Icons.download, size: 18),
                  label: Text(S.of(context).downloadAndInstall),
                )
              else
                OutlinedButton.icon(
                  onPressed: () async {
                    final url = Uri.parse(info.releaseUrl);
                    if (!await launchUrl(
                      url,
                      mode: LaunchMode.externalApplication,
                    )) {
                      if (context.mounted) {
                        Clipboard.setData(ClipboardData(text: info.releaseUrl));
                        Toast.show(
                          context,
                          message: S.of(context).couldNotOpenBrowser,
                          level: ToastLevel.warning,
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: Text(S.of(context).openInBrowser),
                ),
              if (!isSkipped)
                TextButton(
                  onPressed: () => ref
                      .read(configProvider.notifier)
                      .update(
                        (c) => c.copyWith(
                          behavior: c.behavior.copyWith(
                            skippedVersion: info.latestVersion,
                          ),
                        ),
                      ),
                  child: Text(S.of(context).skipThisVersion),
                )
              else
                TextButton(
                  onPressed: () => ref
                      .read(configProvider.notifier)
                      .update(
                        (c) => c.copyWith(
                          behavior: c.behavior.copyWith(skippedVersion: null),
                        ),
                      ),
                  child: Text(S.of(context).unskip),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDownloaded(
    BuildContext context,
    WidgetRef ref,
    UpdateState updateState,
  ) {
    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.check_circle, size: 20),
          title: Text(S.of(context).downloadComplete),
          subtitle: Text(
            updateState.downloadedPath ?? '',
            style: TextStyle(fontSize: AppFonts.md),
            overflow: TextOverflow.ellipsis,
          ),
          contentPadding: EdgeInsets.zero,
        ),
        Padding(
          padding: const EdgeInsets.only(left: 8),
          child: Wrap(
            spacing: 8,
            children: [
              _ChangelogButton(changelog: updateState.info?.changelog),
              FilledButton.icon(
                onPressed: () async {
                  final ok = await ref.read(updateProvider.notifier).install();
                  if (!ok && context.mounted) {
                    Toast.show(
                      context,
                      message: S.of(context).couldNotOpenInstaller,
                      level: ToastLevel.error,
                    );
                  }
                },
                icon: const Icon(Icons.install_desktop, size: 18),
                label: Text(S.of(context).installNow),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ChangelogButton extends StatelessWidget {
  const _ChangelogButton({required this.changelog});

  final String? changelog;

  @override
  Widget build(BuildContext context) {
    if (changelog == null || changelog!.isEmpty) return const SizedBox.shrink();

    return TextButton.icon(
      onPressed: () => AppDialog.show(
        context,
        builder: (ctx) => AppDialog(
          title: S.of(ctx).releaseNotes,
          content: SingleChildScrollView(
            child: Text(
              changelog!,
              style: TextStyle(fontSize: AppFonts.md, color: AppTheme.fgDim),
            ),
          ),
          actions: [AppDialogAction.cancel(onTap: () => Navigator.pop(ctx))],
        ),
      ),
      icon: const Icon(Icons.article_outlined, size: 18),
      label: Text(S.of(context).releaseNotes),
    );
  }
}

class _AboutSection extends ConsumerWidget {
  const _AboutSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final version = ref.watch(appVersionProvider);
    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.info_outline, size: 20),
          title: Text(S.of(context).appTitle),
          subtitle: Text(S.of(context).aboutSubtitle(version)),
          contentPadding: EdgeInsets.zero,
        ),
        ListTile(
          leading: const Icon(Icons.code, size: 20),
          title: Text(S.of(context).sourceCode),
          subtitle: Text(
            _githubUrl,
            style: TextStyle(
              color: theme.colorScheme.primary,
              fontSize: AppFonts.xs,
            ),
          ),
          contentPadding: EdgeInsets.zero,
          onTap: () {
            Clipboard.setData(const ClipboardData(text: _githubUrl));
            Toast.show(
              context,
              message: S.of(context).urlCopied,
              level: ToastLevel.info,
            );
          },
        ),
      ],
    );
  }
}

class _QrExportTile extends ConsumerWidget {
  const _QrExportTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _ActionTile(
      icon: Icons.qr_code,
      title: S.of(context).exportQrCode,
      subtitle: S.of(context).exportQrCodeSubtitle,
      onTap: () => _showQrExport(context, ref),
    );
  }

  Future<void> _showQrExport(BuildContext context, WidgetRef ref) async {
    final sessions = ref.read(sessionProvider);
    final store = ref.read(sessionStoreProvider);

    // Load counts for export dialog
    final keyStore = ref.read(keyStoreProvider);
    final tagStore = ref.read(tagStoreProvider);
    final snippetStore = ref.read(snippetStoreProvider);
    final allKeys = await keyStore.loadAll();
    final allTags = await tagStore.loadAll();
    final allSnippets = await snippetStore.loadAll();
    if (!context.mounted) return;
    final managerKeys = Map<String, String>.fromEntries(
      allKeys.entries.map((e) => MapEntry(e.key, e.value.privateKey)),
    );

    final exportResult = await UnifiedExportDialog.show(
      context,
      data: UnifiedExportDialogData(
        sessions: sessions,
        emptyFolders: store.emptyFolders,
        config: ref.read(configProvider),
        knownHostsContent: ref.read(knownHostsProvider).exportToString(),
        managerKeys: managerKeys,
        managerKeyEntries: allKeys,
        tags: allTags,
        snippets: allSnippets,
      ),
      isQrMode: true,
    );

    if (exportResult == null || !context.mounted) return;

    // Resolve keyId → keyData after dialog closes
    final resolvedSessions = await _resolveSessionKeys(
      ref,
      exportResult.selectedSessions,
    );
    if (!context.mounted) return;

    // Collect tags/snippets data for QR payload
    final tags = exportResult.options.includeTags ? allTags : <Tag>[];
    final snippets = exportResult.options.includeSnippets
        ? allSnippets
        : <Snippet>[];
    final sessionTags = await _collectQrSessionTags(
      tagStore,
      exportResult.selectedSessions,
      includeTags: tags.isNotEmpty,
    );
    final sessionSnippets = await _collectQrSessionSnippets(
      snippetStore,
      exportResult.selectedSessions,
      includeSnippets: snippets.isNotEmpty,
    );

    final payload = encodeExportPayload(
      resolvedSessions,
      input: ExportPayloadInput(
        emptyFolders: exportResult.selectedEmptyFolders,
        options: exportResult.options,
        config: exportResult.options.includeConfig
            ? ref.read(configProvider)
            : null,
        knownHostsContent: exportResult.options.includeKnownHosts
            ? ref.read(knownHostsProvider).exportToString()
            : null,
        managerKeyEntries: allKeys,
        tags: tags,
        sessionTags: sessionTags,
        snippets: snippets,
        sessionSnippets: sessionSnippets,
      ),
    );

    final deepLink = wrapInDeepLink(payload);
    final data = decodeImportUri(Uri.parse(deepLink));
    final sessionCount = data?.sessions.length ?? 0;
    if (!context.mounted) return;
    await QrDisplayScreen.show(
      context,
      data: deepLink,
      sessionCount: sessionCount,
    );
  }

  Future<List<ExportLink>> _collectQrSessionTags(
    TagStore tagStore,
    List<Session> selectedSessions, {
    required bool includeTags,
  }) async {
    final sessionTags = <ExportLink>[];
    if (!includeTags) return sessionTags;
    for (final s in selectedSessions) {
      final sTags = await tagStore.getForSession(s.id);
      for (final t in sTags) {
        sessionTags.add(ExportLink(sessionId: s.id, targetId: t.id));
      }
    }
    return sessionTags;
  }

  Future<List<ExportLink>> _collectQrSessionSnippets(
    SnippetStore snippetStore,
    List<Session> selectedSessions, {
    required bool includeSnippets,
  }) async {
    final sessionSnippets = <ExportLink>[];
    if (!includeSnippets) return sessionSnippets;
    for (final s in selectedSessions) {
      final sSnippets = await snippetStore.loadForSession(s.id);
      for (final sn in sSnippets) {
        sessionSnippets.add(ExportLink(sessionId: s.id, targetId: sn.id));
      }
    }
    return sessionSnippets;
  }
}

class _DataPathTile extends StatelessWidget {
  const _DataPathTile();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Directory>(
      future: getApplicationSupportDirectory(),
      builder: (context, snapshot) {
        final path = snapshot.data?.path ?? '...';
        return _ActionTile(
          icon: Icons.folder_special,
          title: S.of(context).dataLocation,
          subtitle: path,
          onTap: () {
            Clipboard.setData(ClipboardData(text: path));
            Toast.show(
              context,
              message: S.of(context).pathCopied,
              level: ToastLevel.info,
            );
          },
        );
      },
    );
  }
}

/// Auto-lock timeout selector. Values are in minutes; 0 means disabled.
///
/// Keep the preset list short — power-of-something choices beat a numeric
/// stepper for a security-sensitive setting where wrong values (too low,
/// too high) damage UX or security. 5/15/30/60 + Off covers the common
/// expectations ("step-away-for-a-coffee" up to "lunch break").
class _AutoLockTile extends ConsumerWidget {
  static const _presets = [0, 5, 15, 30, 60];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = S.of(context);
    final current = ref.watch(
      configProvider.select((c) => c.behavior.autoLockMinutes),
    );
    return Padding(
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
          Wrap(
            spacing: 6,
            children: _presets.map((m) {
              final label = m == 0
                  ? l10n.autoLockOff
                  : l10n.autoLockMinutesValue(m);
              final selected = m == current;
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
                onSelected: (_) => ref
                    .read(configProvider.notifier)
                    .update(
                      (c) => c.copyWith(
                        behavior: c.behavior.copyWith(autoLockMinutes: m),
                      ),
                    ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
