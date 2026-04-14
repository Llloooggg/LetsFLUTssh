part of 'settings_screen.dart';

// ═══════════════════════════════════════════════════════════════════
// Settings content sections — appearance, terminal, connection,
// transfer, data (export/import/QR), updates, about
// ═══════════════════════════════════════════════════════════════════

/// Resolve keyId → keyData for sessions that reference the key store.
/// Returns new list with resolved sessions (original list unchanged).
Future<List<Session>> _resolveSessionKeys(
  WidgetRef ref,
  List<Session> sessions,
) async {
  final keyStore = ref.read(keyStoreProvider);
  final resolved = <Session>[];
  for (final s in sessions) {
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
    return Column(
      children: [
        _ExportImportTile(),
        const _QrExportTile(),
        const _DataPathTile(),
      ],
    );
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
          value: keepAlive,
          min: 0,
          max: 300,
          onChanged: (v) => ref
              .read(configProvider.notifier)
              .update((c) => c.copyWith(ssh: c.ssh.copyWith(keepAliveSec: v))),
        ),
        _IntTile(
          title: S.of(context).sshTimeout,
          value: timeout,
          min: 1,
          max: 60,
          onChanged: (v) => ref
              .read(configProvider.notifier)
              .update((c) => c.copyWith(ssh: c.ssh.copyWith(sshTimeoutSec: v))),
        ),
        _IntTile(
          title: S.of(context).defaultPort,
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

class _SshKeysSection extends ConsumerWidget {
  const _SshKeysSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        _ActionTile(
          icon: Icons.vpn_key,
          title: S.of(context).sshKeys,
          subtitle: S.of(context).sshKeysSubtitle,
          onTap: () => KeyManagerDialog.show(context),
        ),
        _ActionTile(
          icon: Icons.code,
          title: S.of(context).snippets,
          subtitle: S.of(context).snippetsSubtitle,
          onTap: () => SnippetManagerDialog.show(context),
        ),
        _ActionTile(
          icon: Icons.label_outline,
          title: S.of(context).tags,
          subtitle: S.of(context).tagsSubtitle,
          onTap: () => TagManagerDialog.show(context),
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

  @override
  void initState() {
    super.initState();
    _checkState();
  }

  Future<void> _checkState() async {
    final manager = ref.read(masterPasswordProvider);
    final keyStorage = ref.read(secureKeyStorageProvider);
    final results = await Future.wait([
      manager.isEnabled(),
      keyStorage.isAvailable(),
    ]);
    if (mounted) {
      setState(() {
        _masterPasswordEnabled = results[0];
        _keychainAvailable = results[1];
      });
    }
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
        if (_keychainAvailable == true &&
            secState.level == SecurityLevel.plaintext)
          _ActionTile(
            icon: Icons.enhanced_encryption,
            title: l10n.enableKeychain,
            subtitle: l10n.enableKeychainSubtitle,
            onTap: () => _enableKeychain(context),
          ),
        // Known Hosts — only on mobile (desktop has it in Tools dialog).
        if (plat.isMobilePlatform)
          _ActionTile(
            icon: Icons.verified_user,
            title: l10n.knownHosts,
            subtitle: l10n.knownHostsSubtitle,
            onTap: () => KnownHostsManagerDialog.show(context),
          ),
      ],
    );
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

      AppProgressDialog.show(context);
      try {
        await _enableMasterPassword(password);
        if (context.mounted) {
          Navigator.of(context).pop(); // close progress
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
      }
    } catch (e) {
      AppLogger.instance.log(
        'Set master password failed: $e',
        name: 'Security',
        error: e,
      );
      if (context.mounted) {
        Toast.show(context, message: e.toString(), level: ToastLevel.error);
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

      AppProgressDialog.show(context);
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
        Toast.show(context, message: e.toString(), level: ToastLevel.error);
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

      AppProgressDialog.show(context);
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
        Toast.show(context, message: e.toString(), level: ToastLevel.error);
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
      AppProgressDialog.show(context);
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
      }
    } catch (e) {
      AppLogger.instance.log(
        'Enable keychain failed: $e',
        name: 'Security',
        error: e,
      );
      if (context.mounted) {
        Toast.show(context, message: e.toString(), level: ToastLevel.error);
      }
    }
  }

  /// Re-encrypt the database and update global security state.
  ///
  /// With drift, encryption is at the DB file level — no per-store re-encryption.
  /// TODO: Implement PRAGMA rekey for live re-encryption.
  Future<void> _reEncryptAll(Uint8List? key, SecurityLevel level) async {
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
          value: workers,
          min: 1,
          max: 10,
          onChanged: (v) => ref
              .read(configProvider.notifier)
              .update((c) => c.copyWith(transferWorkers: v)),
        ),
        _IntTile(
          title: S.of(context).maxHistory,
          value: maxHistory,
          min: 10,
          max: 5000,
          onChanged: (v) => ref
              .read(configProvider.notifier)
              .update((c) => c.copyWith(maxHistory: v)),
        ),
        _Toggle(
          label: S.of(context).calculateFolderSizes,
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
          title: S.of(context).exportData,
          subtitle: S.of(context).exportDataSubtitle,
          onTap: () => _showExportDialog(context, ref),
        ),
        _ActionTile(
          icon: Icons.download,
          title: S.of(context).importData,
          subtitle: S.of(context).importDataSubtitle,
          onTap: () => _showImportDialog(context, ref),
        ),
      ],
    );
  }

  Future<void> _showExportDialog(BuildContext context, WidgetRef ref) async {
    final sessions = ref.read(sessionProvider);
    final store = ref.read(sessionStoreProvider);
    final l10n = S.of(context);

    // Load all manager keys for size calculation (before resolving sessions)
    final keyStore = ref.read(keyStoreProvider);
    final allKeys = await keyStore.loadAll();
    if (!context.mounted) return;
    final managerKeys = Map<String, String>.fromEntries(
      allKeys.entries.map((e) => MapEntry(e.key, e.value.privateKey)),
    );

    // Show export dialog with original sessions (keyId preserved, not resolved)
    // Sessions are resolved later during actual export to include manager keys
    final exportResult = await UnifiedExportDialog.show(
      context,
      sessions: sessions,
      emptyFolders: store.emptyFolders,
      config: ref.read(configProvider),
      knownHostsContent: ref.read(knownHostsProvider).exportToString(),
      isQrMode: false,
      knownHostsLabel: l10n.knownHosts,
      managerKeys: managerKeys,
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
          message: S.of(context).exportFailed(e.toString()),
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

    // Show progress indicator while PBKDF2 + encryption runs in isolate
    AppProgressDialog.show(context);
    try {
      await ExportImport.export(
        masterPassword: password,
        sessions: resolvedSessions,
        config: ref.read(configProvider),
        outputPath: outputPath,
        options: exportResult.options,
        emptyFolders: exportResult.options.includeSessions
            ? exportResult.selectedEmptyFolders
            : {},
        knownHostsContent: exportResult.options.includeKnownHosts
            ? ref.read(knownHostsProvider).exportToString()
            : null,
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
    }
  }

  /// Opens a save-file picker. Desktop uses native save dialog,
  /// mobile uses directory picker + default filename.
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
    // Mobile: pick directory, append default filename
    final dir = await FilePicker.getDirectoryPath(
      dialogTitle: title,
      initialDirectory: initDir,
    );
    if (dir == null) return null;
    return p.join(dir, defaultName);
  }

  Future<void> _showImportDialog(BuildContext context, WidgetRef ref) async {
    // Pick file
    final title = S.of(context).pathToLfsFile;
    final initDir = await _defaultDirectory();
    final result = await FilePicker.pickFiles(
      dialogTitle: title,
      initialDirectory: initDir,
      type: FileType.custom,
      allowedExtensions: ['lfs'],
    );
    final path = result?.files.single.path;
    if (path == null || !context.mounted) return;

    // Preview archive
    final passwordCtrl = TextEditingController();

    try {
      // Get password first
      final password = await AppDialog.show<String>(
        context,
        builder: (ctx) => _ImportPasswordDialog(passwordCtrl: passwordCtrl),
      );

      if (password == null || !context.mounted) return;

      // Decrypt once — reuse for both preview and import to avoid running
      // the expensive PBKDF2 key derivation (600k iterations) twice.
      AppProgressDialog.show(context);
      final fullImport = await ExportImport.import_(
        filePath: path,
        masterPassword: password,
        mode: ImportMode.merge, // placeholder — user picks mode in preview
        options: const ExportOptions(
          includeSessions: true,
          includeConfig: true,
          includeKnownHosts: true,
        ),
      );
      if (!context.mounted) return;
      Navigator.of(context).pop(); // close progress

      final preview = LfsPreview(
        sessions: fullImport.sessions,
        hasConfig: fullImport.config != null,
        hasKnownHosts:
            fullImport.knownHostsContent != null &&
            fullImport.knownHostsContent!.isNotEmpty,
        emptyFolders: fullImport.emptyFolders,
      );

      final importConfig = await LfsImportPreviewDialog.show(
        context,
        filePath: path,
        preview: preview,
      );

      if (importConfig == null || !context.mounted) return;

      // Filter the already-decrypted data by user's choices
      final filteredResult = ImportResult(
        sessions: importConfig.options.includeSessions
            ? fullImport.sessions
            : [],
        emptyFolders: importConfig.options.includeSessions
            ? fullImport.emptyFolders
            : {},
        config: importConfig.options.includeConfig ? fullImport.config : null,
        mode: importConfig.mode,
        knownHostsContent: importConfig.options.includeKnownHosts
            ? fullImport.knownHostsContent
            : null,
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
    try {
      final store = ref.read(sessionStoreProvider);
      final importService = ImportService(
        addSession: (s) => ref.read(sessionProvider.notifier).add(s),
        addEmptyFolder: (f) =>
            ref.read(sessionProvider.notifier).addEmptyFolder(f),
        deleteSession: (id) => ref.read(sessionProvider.notifier).delete(id),
        getSessions: () => ref.read(sessionProvider),
        applyConfig: (config) =>
            ref.read(configProvider.notifier).update((_) => config),
        getEmptyFolders: () => store.emptyFolders,
        restoreSnapshot: (sessions, folders) =>
            store.restoreSnapshot(sessions, folders),
      );
      await importService.applyResult(importResult);

      // Import known hosts via the manager (handles encryption).
      if (importResult.knownHostsContent != null) {
        try {
          final knownHosts = ref.read(knownHostsProvider);
          await knownHosts.importFromString(importResult.knownHostsContent!);
        } catch (e) {
          AppLogger.instance.log(
            'Failed to import known_hosts from LFS: $e',
            name: 'Settings',
            error: e,
          );
          // Continue — known_hosts failure shouldn't fail entire import
        }
      }

      if (context.mounted) {
        Toast.show(
          context,
          message: S.of(context).importedSessions(importResult.sessions.length),
          level: ToastLevel.success,
        );
      }
    } catch (e) {
      AppLogger.instance.log('Import failed: $e', name: 'Settings', error: e);
      if (context.mounted) {
        Toast.show(
          context,
          message: S.of(context).importFailed(localizeError(S.of(context), e)),
          level: ToastLevel.error,
        );
      }
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
        return ListTile(
          leading: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              value: updateState.progress > 0 ? updateState.progress : null,
              strokeWidth: 2,
            ),
          ),
          title: Text(
            S
                .of(context)
                .downloadingPercent((updateState.progress * 100).toInt()),
          ),
          contentPadding: EdgeInsets.zero,
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
      title: S.of(context).shareViaQrCode,
      subtitle: S.of(context).shareViaQrSubtitle,
      onTap: () => _showQrExport(context, ref),
    );
  }

  Future<void> _showQrExport(BuildContext context, WidgetRef ref) async {
    final sessions = ref.read(sessionProvider);
    if (sessions.isEmpty) {
      Toast.show(
        context,
        message: S.of(context).noSessionsToExport,
        level: ToastLevel.warning,
      );
      return;
    }
    final store = ref.read(sessionStoreProvider);
    final l10n = S.of(context);

    // Load all manager keys for size calculation (before resolving sessions)
    final keyStore = ref.read(keyStoreProvider);
    final allKeys = await keyStore.loadAll();
    if (!context.mounted) return;
    final managerKeys = Map<String, String>.fromEntries(
      allKeys.entries.map((e) => MapEntry(e.key, e.value.privateKey)),
    );

    // Use unified export dialog with original sessions (keyId preserved)
    final exportResult = await UnifiedExportDialog.show(
      context,
      sessions: sessions,
      emptyFolders: store.emptyFolders,
      config: ref.read(configProvider),
      knownHostsContent: ref.read(knownHostsProvider).exportToString(),
      isQrMode: true,
      knownHostsLabel: l10n.knownHosts,
      managerKeys: managerKeys,
    );

    if (exportResult == null || !context.mounted) return;

    // Resolve keyId → keyData after dialog closes, for QR generation
    final resolvedSessions = await _resolveSessionKeys(
      ref,
      exportResult.selectedSessions,
    );
    if (!context.mounted) return;

    // Generate QR payload
    final payload = encodeExportPayload(
      resolvedSessions,
      emptyFolders: exportResult.selectedEmptyFolders,
      options: exportResult.options,
      config: exportResult.options.includeConfig
          ? ref.read(configProvider)
          : null,
      knownHostsContent: exportResult.options.includeKnownHosts
          ? ref.read(knownHostsProvider).exportToString()
          : null,
    );

    final deepLink = wrapInDeepLink(payload);
    final data = decodeImportUri(Uri.parse(deepLink));
    final sessionCount = data?.sessions.length ?? 0;
    await QrDisplayScreen.show(
      context,
      data: deepLink,
      sessionCount: sessionCount,
    );
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
