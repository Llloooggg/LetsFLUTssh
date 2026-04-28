part of 'settings_screen.dart';

// ═══════════════════════════════════════════════════════════════════
// Settings content sections — appearance, terminal, connection,
// transfer, data (export/import/QR), updates, about
// ═══════════════════════════════════════════════════════════════════

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
    final source = await PasteImportLinkDialog.show(context);
    if (source == null || !context.mounted) return;
    final choice = await LinkImportPreviewDialog.show(context, source: source);
    if (choice == null || !context.mounted) return;
    await handleQrImportSource(
      context: context,
      ref: ref,
      source: source,
      choice: choice,
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

      // Capture localized strings BEFORE the first async hop. The
      // PPK-aware key scanner now awaits FRB; resolving `S.of(context)`
      // afterwards would be using a possibly-defunct context.
      final date = DateTime.now().toIso8601String().split('T').first;
      final folderLabel = S.of(context).sshConfigImportFolderName(date);

      // Scan keys regardless of config presence — user may want to import
      // just the standalone keys.
      final scannedKeys = await SshDirKeyScanner().scan(sshDir);

      // Parse config if present. Missing file = no hosts, dialog still shows
      // the keys section.
      OpenSshConfigImportPreview? preview;
      final configFile = File(configPath);
      if (await configFile.exists()) {
        final content = await configFile.readAsString();
        preview = await OpenSshConfigImporter().buildPreview(
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

      // Metadata-only listing — Rust pre-computes the SHA-256 of
      // each row's private PEM so the dedup set can be built
      // without ever pulling the bytes through the FRB boundary.
      final existing = await keyStore.loadAllMetadata();
      final existingFingerprints = existing.values
          .map((e) => e.privateFingerprint)
          .where((fp) => fp.isNotEmpty)
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
      final preview = await OpenSshConfigImporter().buildPreview(
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
      final pem = await KeyFileHelper.tryReadPemKey(path);
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
    // Progress bar covers the Rust orchestrator + write step. The
    // orchestrator reads sessions / keys / tags / snippets / known-hosts
    // straight from `lfs_core.db` so plaintext credentials never round-
    // trip through the Dart heap during export. Dart only passes the
    // pre-serialised `config.json` payload (file-based, not in the DB).
    final l10n = S.of(context);
    final reporter = ProgressReporter(l10n.progressCollectingData);
    AppProgressBarDialog.show(context, reporter);
    try {
      final selectedIds = exportResult.selectedSessions
          .map((s) => s.id)
          .toList();
      final emptyFolders = exportResult.options.includeSessions
          ? exportResult.selectedEmptyFolders.toList()
          : <String>[];
      final config = ref.read(configProvider);
      await ExportImport.exportViaRust(
        masterPassword: password,
        outputPath: outputPath,
        options: exportResult.options,
        selectedSessionIds: selectedIds,
        selectedEmptyFolders: emptyFolders,
        config: exportResult.options.includeConfig ? config : null,
        progress: reporter,
        l10n: l10n,
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
    String? handleId;
    try {
      final password = await _askImportPassword(context, kind, passwordCtrl);
      if (password == null || !context.mounted) return;

      final opened = await _openArchive(context, path, password);
      if (opened == null || !context.mounted) return;
      handleId = opened.handleId;

      final importConfig = await LfsImportPreviewDialog.show(
        context,
        filePath: path,
        preview: LfsPreview.fromRust(opened.preview),
      );
      if (importConfig == null) {
        // User cancelled — drop the staged handle so the registry
        // does not accumulate orphans.
        await _safeDropHandle(handleId);
        handleId = null;
        return;
      }
      if (!context.mounted) {
        await _safeDropHandle(handleId);
        handleId = null;
        return;
      }

      await _applyOpenedHandle(
        context,
        ref,
        handleId,
        importConfig.options,
        importConfig.mode,
      );
      // Apply consumes the handle on success.
      handleId = null;
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
      if (handleId != null) {
        await _safeDropHandle(handleId);
      }
      passwordCtrl.wipeAndClear();
      passwordCtrl.dispose();
    }
  }

  /// Ask for the archive's master password. Skips the prompt entirely for
  /// an unencrypted archive — the Rust reader treats an empty password as
  /// the no-encryption branch. Returns null on cancel.
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

  /// Open the archive Rust-side via `dbImportOpen`. Returns null when the
  /// host widget unmounts during the await — the staged handle is dropped
  /// before returning so the registry does not accumulate orphans.
  Future<rust_archive.DbImportOpenResult?> _openArchive(
    BuildContext context,
    String path,
    String password,
  ) async {
    final l10n = S.of(context);
    final reporter = ProgressReporter(l10n.progressReadingArchive);
    AppProgressBarDialog.show(context, reporter);
    var progressShown = true;
    try {
      reporter.phase(l10n.progressDecrypting);
      final result = await rust_archive.dbImportOpen(
        path: path,
        password: password,
      );
      if (!context.mounted) {
        await _safeDropHandle(result.handleId);
        return null;
      }
      return result;
    } finally {
      if (progressShown && context.mounted) {
        Navigator.of(context).pop();
        progressShown = false;
      }
      reporter.dispose();
    }
  }

  Future<void> _safeDropHandle(String handleId) async {
    try {
      await rust_archive.dbImportDrop(handleId: handleId);
    } catch (_) {
      // Best-effort cleanup — registry mismatch is harmless.
    }
  }

  /// Apply an already-staged Rust handle through the apply driver.
  /// Mirrors what `applyResultViaRust` does for the QR / paste-link
  /// flows but skips the Dart-side staging round-trip.
  Future<void> _applyOpenedHandle(
    BuildContext context,
    WidgetRef ref,
    String handleId,
    ExportOptions options,
    ImportMode mode,
  ) async {
    final l10n = S.of(context);
    final reporter = ProgressReporter(l10n.progressWorking);
    AppProgressBarDialog.show(context, reporter);
    var progressShown = true;
    try {
      final apply = await applyOpenedHandle(
        handleId: handleId,
        mode: mode,
        applySessions: options.includeSessions,
        applyKeys: options.includeManagerKeys,
        applyTags: options.includeTags,
        applySnippets: options.includeSnippets,
        applyKnownHosts: options.includeKnownHosts,
        refreshAfterImport: () async {
          await ref.read(sessionStoreProvider).load();
          await ref.read(tagStoreProvider).loadAll();
          await ref.read(snippetStoreProvider).loadAll();
        },
      );
      // Config restore (file IO, not a DB write) stays Dart-side.
      // Security tier setup is per-machine and never travels — keep
      // the local value, merge the rest.
      final cfg = options.includeConfig ? decodeConfigFromApply(apply) : null;
      if (cfg != null) {
        ref
            .read(configProvider.notifier)
            .update(
              (current) => cfg.copyWithSecurity(security: current.security),
            );
      }
      ref.invalidate(sshKeysProvider);
      ref.invalidate(tagsProvider);
      ref.invalidate(snippetsProvider);

      if (context.mounted) {
        Navigator.of(context).pop();
        progressShown = false;
        Toast.show(
          context,
          message: formatImportSummary(
            S.of(context),
            ImportSummary(
              sessions: apply.sessionsApplied.toInt(),
              folders: apply.foldersApplied.toInt(),
              managerKeys: apply.keysApplied.toInt(),
              tags: apply.tagsApplied.toInt(),
              snippets: apply.snippetsApplied.toInt(),
              configApplied: cfg != null,
              knownHostsApplied: apply.knownHostsApplied > 0,
              skippedSessions: 0,
              skippedLinks: 0,
            ),
          ),
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

  /// Apply a Dart-built [ImportResult] (QR / paste-link / SSH dir
  /// imports) through the Rust apply driver. The `.lfs` archive
  /// flow uses [_applyOpenedHandle] instead so the staged handle
  /// from `dbImportOpen` is consumed without a round-trip through
  /// a Dart `ImportResult` tree.
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
      final apply = await applyResultViaRust(
        importResult,
        refreshAfterImport: () async {
          await ref.read(sessionStoreProvider).load();
          await ref.read(tagStoreProvider).loadAll();
          await ref.read(snippetStoreProvider).loadAll();
        },
      );
      final cfg = importResult.config;
      if (cfg != null) {
        ref
            .read(configProvider.notifier)
            .update(
              (current) => cfg.copyWithSecurity(security: current.security),
            );
      }
      ref.invalidate(sshKeysProvider);
      ref.invalidate(tagsProvider);
      ref.invalidate(snippetsProvider);

      if (context.mounted) {
        Navigator.of(context).pop();
        progressShown = false;
        Toast.show(
          context,
          message: formatImportSummary(
            S.of(context),
            ImportSummary(
              sessions: apply.sessionsApplied.toInt(),
              folders: apply.foldersApplied.toInt(),
              managerKeys: apply.keysApplied.toInt(),
              tags: apply.tagsApplied.toInt(),
              snippets: apply.snippetsApplied.toInt(),
              configApplied: cfg != null,
              knownHostsApplied: apply.knownHostsApplied > 0,
              skippedSessions: importResult.skippedSessions,
              skippedLinks: 0,
            ),
          ),
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

    // Hand the encode off to the Rust orchestrator — sessions /
    // manager keys / tags / snippets / known-hosts come straight
    // from `lfs_core.db`, dedup runs Rust-side, and only the
    // deflated + base64url-encoded ASCII payload returns to Dart
    // for the QR widget. Plaintext credentials never round-trip
    // through the Dart heap during encode.
    final selectedIds = exportResult.selectedSessions.map((s) => s.id).toList();
    final emptyFolders = exportResult.selectedEmptyFolders.toList();
    final cfg = exportResult.options.includeConfig
        ? ref.read(configProvider)
        : null;
    final payload = await rust_archive.dbExportQrPayload(
      input: rust_archive.DbQrExportInput(
        options: rust_archive.DbQrExportOptions(
          includeSessions: exportResult.options.includeSessions,
          includeConfig: exportResult.options.includeConfig && cfg != null,
          includeKnownHosts: exportResult.options.includeKnownHosts,
          includePasswords: exportResult.options.includePasswords,
          includeEmbeddedKeys: exportResult.options.includeEmbeddedKeys,
          includeManagerKeys: exportResult.options.includeManagerKeys,
          includeAllManagerKeys: exportResult.options.includeAllManagerKeys,
          includeTags: exportResult.options.includeTags,
          includeSnippets: exportResult.options.includeSnippets,
        ),
        selectedSessionIds: selectedIds,
        selectedEmptyFolders: emptyFolders,
        configJson: cfg != null ? jsonEncode(cfg.toJson()) : null,
      ),
    );

    final deepLink = wrapInDeepLink(payload);
    // Selected ids = exported session count (the encoder writes one
    // entry per id). Avoids round-tripping the encoded blob back
    // through the Dart decoder just to count.
    final sessionCount = selectedIds.length;
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
