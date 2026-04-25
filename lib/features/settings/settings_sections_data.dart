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

class _DataSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        _ExportImportTile(),
        const SizedBox(height: 12),
        // Storage / destructive group kept under its own header so
        // the Data Location info tile + Reset All Data button do not
        // read as part of the Export / Import flow directly above.
        _SectionHeader(title: S.of(context).dataStorageSection),
        const _DataPathTile(),
        const _RecordingsTile(),
        const _ResetAllDataTile(),
      ],
    );
  }
}

/// Destructive "reset everything" entry. Lives in the Data section
/// because the action wipes the on-disk database, credential store,
/// keychain entries, hw-vault sealed blobs, and logs — the union of
/// "every piece of data this install holds". The Security section
/// used to carry this tile (since it also resets tier state) but
/// the scope is broader than security tier config; Data is the
/// natural home for "manage my data" destructive options, next to
/// Export / Import.
///
/// Stateful wrapper instead of an inline `_ActionTile` so the
/// confirm-dialog + `WipeAllService` + reinit-signal flow can use
/// `ref` and `mounted` without leaking `BuildContext` across async
/// gaps.
class _ResetAllDataTile extends ConsumerStatefulWidget {
  const _ResetAllDataTile();

  @override
  ConsumerState<_ResetAllDataTile> createState() => _ResetAllDataTileState();
}

class _ResetAllDataTileState extends ConsumerState<_ResetAllDataTile> {
  @override
  Widget build(BuildContext context) {
    final l10n = S.of(context);
    return _ActionTile(
      icon: Icons.delete_forever_outlined,
      title: l10n.resetAllDataTitle,
      subtitle: l10n.resetAllDataSubtitle,
      destructive: true,
      onTap: _run,
    );
  }

  Future<void> _run() async {
    final l10n = S.of(context);
    final confirmed = await ConfirmDialog.show(
      context,
      title: l10n.resetAllDataConfirmTitle,
      content: Text(l10n.resetAllDataConfirmBody),
      confirmLabel: l10n.resetAllDataConfirmAction,
    );
    if (!confirmed) return;
    if (!mounted) return;

    final reporter = ProgressReporter(l10n.resetAllDataInProgress);
    AppProgressBarDialog.show(context, reporter);
    try {
      // Close any active DB handle before we drop its file, otherwise
      // SQLite keeps a stale fd pointing at a deleted inode and the
      // next session can't open the fresh one cleanly.
      final cache = ref.read(sessionCredentialCacheProvider);
      final service = WipeAllService(credentialCacheEvict: cache.evictAll);
      final report = await service.wipeAll();
      AppLogger.instance.log(
        'Reset all: deleted=${report.deletedFiles.length} '
        'failed=${report.failedFiles.length} '
        'keychain=${report.keychainPurged} '
        'native=${report.nativeVaultCleared} '
        'overlay=${report.biometricOverlayCleared}',
        name: 'Data',
      );
      await ref
          .read(configProvider.notifier)
          .update((c) => c.copyWithSecurity(security: null));
      // Kick the app back into the first-launch provisioning path:
      // closes the (now stale) DB handle, re-runs `_firstLaunchSetup`,
      // and surfaces the one-shot toast the same way a genuine first
      // launch does. Without this the wipe leaves the app holding a
      // dropped DB key and a deleted database file; the first
      // subsequent UI action would crash on a missing handle.
      requestSecurityReinit(ref);
      if (mounted) {
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
        name: 'Data',
        error: e,
      );
      if (mounted) {
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
}

class _ExportImportTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        _SectionHeader(title: S.of(context).import_),
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
        const SizedBox(height: 8),
        _SectionHeader(title: S.of(context).export_),
        _ActionTile(
          icon: Icons.upload_file,
          title: S.of(context).exportArchive,
          subtitle: S.of(context).exportArchiveSubtitle,
          onTap: () => _showExportDialog(context, ref),
        ),
        const _QrExportTile(),
      ],
    );
  }

  Future<void> _showPasteImportLink(BuildContext context, WidgetRef ref) async {
    final data = await PasteImportLinkDialog.show(context);
    if (data == null || !context.mounted) return;
    final choice = await LinkImportPreviewDialog.show(context, payload: data);
    if (choice == null || !context.mounted) return;
    final fullImport = ImportResult(
      sessions: data.sessions,
      emptyFolders: data.emptyFolders,
      managerKeys: data.managerKeys,
      tags: data.tags,
      sessionTags: data.sessionTags,
      folderTags: data.folderTags,
      snippets: data.snippets,
      sessionSnippets: data.sessionSnippets,
      config: data.config,
      mode: choice.mode,
      knownHostsContent: data.knownHostsContent,
    );
    await _applyFilteredImport(
      context,
      ref,
      fullImport.filtered(choice.options, choice.mode),
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

      // Nothing to show at all — surface a warning and bail. Mobile
      // sandboxes usually hide ~/.ssh from us, so an empty scan there is
      // expected rather than an error: fall through to the dialog so the
      // user can still reach the "Browse…" pickers and feed it files from
      // the SAF / iOS document picker.
      if (scannedKeys.isEmpty && (preview?.result.sessions.isEmpty ?? true)) {
        if (plat.isDesktopPlatform) {
          Toast.show(
            context,
            message: S.of(context).fileNotFound(sshDir),
            level: ToastLevel.warning,
          );
          return;
        }
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

    final knownHostsContent = await ref
        .read(knownHostsProvider)
        .exportToString();
    if (!context.mounted) return;

    final exportResult = await UnifiedExportDialog.show(
      context,
      data: UnifiedExportDialogData(
        sessions: sessions,
        emptyFolders: store.emptyFolders,
        config: ref.read(configProvider),
        knownHostsContent: knownHostsContent,
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
      passwordCtrl.wipeAndClear();
      confirmCtrl.wipeAndClear();
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

    // Progress bar covers the collection, Argon2id+encryption, and write steps.
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
      final knownHostsContent = exportResult.options.includeKnownHosts
          ? await ref.read(knownHostsProvider).exportToString()
          : null;

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
          knownHostsContent: knownHostsContent,
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

    // Validate the file before anything else. On Android SAF the `.lfs`
    // extension filter is advisory (no registered MIME type), so users can
    // land on any file — including APKs, which are also ZIPs. `probeArchive`
    // rejects non-LFS content before we bother asking for a password.
    final kind = ExportImport.probeArchive(path);
    if (kind == LfsArchiveKind.notLfs) {
      Toast.show(
        context,
        message: S.of(context).errLfsNotArchive,
        level: ToastLevel.error,
      );
      return;
    }

    final passwordCtrl = TextEditingController();
    try {
      final password = await _askImportPassword(context, kind, passwordCtrl);
      if (password == null || !context.mounted) return;

      final fullImport = await _decryptForPreview(context, path, password);
      if (fullImport == null || !context.mounted) return;

      final importConfig = await LfsImportPreviewDialog.show(
        context,
        filePath: path,
        preview: _buildPreview(fullImport),
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
      passwordCtrl.wipeAndClear();
      passwordCtrl.dispose();
    }
  }

  /// Ask for the archive's master password. Skips the prompt entirely for
  /// an unencrypted archive — `ExportImport.import_` accepts an empty
  /// password in that branch. Returns null on cancel.
  Future<String?> _askImportPassword(
    BuildContext context,
    LfsArchiveKind kind,
    TextEditingController passwordCtrl,
  ) async {
    if (kind == LfsArchiveKind.unencryptedLfs) return '';
    final password = await AppDialog.show<String>(
      context,
      builder: (ctx) => _ImportPasswordDialog(passwordCtrl: passwordCtrl),
    );
    return password;
  }

  /// Decrypt the archive once so preview + final import share the Argon2id
  /// key derivation (memory-hard, too expensive to run twice).
  /// Shows a progress dialog for the duration. Returns null when the
  /// outer widget is no longer mounted after the work completes.
  Future<ImportResult?> _decryptForPreview(
    BuildContext context,
    String path,
    String password,
  ) async {
    final l10n = S.of(context);
    final reporter = ProgressReporter(l10n.progressReadingArchive);
    AppProgressBarDialog.show(context, reporter);
    var progressShown = true;
    try {
      return await ExportImport.import_(
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
  }

  LfsPreview _buildPreview(ImportResult fullImport) => LfsPreview(
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
        applyConfig: (importedConfig) => ref
            .read(configProvider.notifier)
            .update(
              // `security` describes the per-machine setup: which
              // keychain slot, which hw vault, which DB-key wrapper.
              // It must NEVER travel across machines via the archive
              // — importing on machine B should not try to unlock a
              // hardware vault that belongs to machine A's TPM. Keep
              // the local value, merge everything else.
              (current) =>
                  importedConfig.copyWithSecurity(security: current.security),
            ),
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
        exportKnownHosts: () => knownHostsMgr.exportToString(),
        clearKnownHosts: () => knownHostsMgr.clearAll(),
        importKnownHosts: (content) async {
          await knownHostsMgr.importFromString(content);
        },
        existingManagerKeyIds: () async =>
            (await keyStore.loadAll()).keys.toSet(),
        deleteManagerKey: keyStore.delete,
        runInTransaction: store.database == null
            ? null
            : <T>(body) => store.database!.transaction(body),
      );
      final summary = await importService.applyResult(
        importResult,
        progress: reporter,
        l10n: l10n,
      );
      // Refresh cached FutureProviders so newly imported keys, tags and
      // snippets appear in the UI without an app restart.
      ref.invalidate(sshKeysProvider);
      ref.invalidate(tagsProvider);
      ref.invalidate(snippetsProvider);

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

    final knownHostsContent = await ref
        .read(knownHostsProvider)
        .exportToString();
    if (!context.mounted) return;

    final exportResult = await UnifiedExportDialog.show(
      context,
      data: UnifiedExportDialogData(
        sessions: sessions,
        emptyFolders: store.emptyFolders,
        config: ref.read(configProvider),
        knownHostsContent: knownHostsContent,
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
            ? knownHostsContent
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
    // Reflect the *actual* export choice on the display screen. The QR
    // mode default is `includePasswords: true`, so a blanket reassurance
    // that the code carries no credentials would be misleading.
    final containsCredentials =
        exportResult.options.includePasswords ||
        exportResult.options.includeEmbeddedKeys ||
        exportResult.options.hasManagerKeys;
    if (!context.mounted) return;
    await QrDisplayScreen.show(
      context,
      data: deepLink,
      sessionCount: sessionCount,
      containsCredentials: containsCredentials,
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
          emphasizeSubtitle: true,
          showChevron: false,
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


/// Tile that opens the recordings browser modal. Lives in the
/// Storage subsection because recordings are filesystem artefacts
/// that share their disk-management UX with the data-location tile
/// rather than the export/import flow.
class _RecordingsTile extends StatelessWidget {
  const _RecordingsTile();

  @override
  Widget build(BuildContext context) {
    final l10n = S.of(context);
    return _ActionTile(
      icon: Icons.play_circle_outline,
      title: l10n.recordingsBrowserTitle,
      subtitle: l10n.recordingsBrowserSubtitle,
      onTap: () => RecordingsBrowser.show(context),
    );
  }
}
