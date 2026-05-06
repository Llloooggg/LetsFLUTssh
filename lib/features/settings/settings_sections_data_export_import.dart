part of 'settings_screen.dart';

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
      final keyStore = ref.read(sshKeysProvider.notifier);

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
    final notifier = ref.read(sessionProvider.notifier);

    // Load counts for export dialog. Same pattern as the QR
    // export tile — bytes live in `managerKeyEntries` for the
    // dialog's lifetime; the duplicate `Map<String, String>` was
    // dropped from the dialog data.
    final keyStore = ref.read(sshKeysProvider.notifier);
    final allKeys = await keyStore.loadAll();
    final allTags = await ref.read(tagsProvider.notifier).loadAll();
    final allSnippets = await ref.read(snippetsProvider.notifier).loadAll();
    if (!context.mounted) return;

    final knownHostsContent = await ref
        .read(knownHostsProvider.notifier)
        .exportToString();
    if (!context.mounted) return;

    final exportResult = await UnifiedExportDialog.show(
      context,
      data: UnifiedExportDialogData(
        sessions: sessions,
        emptyFolders: notifier.emptyFolders,
        config: ref.read(configProvider),
        knownHostsContent: knownHostsContent,
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
    // straight from `letsflutssh.db` so plaintext credentials never round-
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
    final kind = await ExportImport.probeArchive(path);
    if (!context.mounted) return;
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
          await ref.read(sessionProvider.notifier).load();
          await ref.read(tagsProvider.notifier).loadAll();
          await ref.read(snippetsProvider.notifier).loadAll();
        },
      );
      if (apply.rolledBack) {
        throw ImportRolledBackException(List<String>.from(apply.errors));
      }
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
          await ref.read(sessionProvider.notifier).load();
          await ref.read(tagsProvider.notifier).loadAll();
          await ref.read(snippetsProvider.notifier).loadAll();
        },
      );
      if (apply.rolledBack) {
        throw ImportRolledBackException(List<String>.from(apply.errors));
      }
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
