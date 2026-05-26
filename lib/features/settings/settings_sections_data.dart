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
        const SizedBox(height: AppSpacing.md),
        // Storage / destructive group kept under its own header so
        // the Data Location info tile + Reset All Data button do not
        // read as part of the Export / Import flow directly above.
        _SectionHeader(title: S.of(context).dataStorageSection),
        const _DataPathTile(),
        const _RecordingsStorageTile(),
        const _ResetAllDataTile(),
      ],
    );
  }
}

/// Recordings storage usage + cap + clear-all entry inside the Data
/// section. Reads usage on demand from `recorder_storage_used`,
/// persists the cap through `recorder_set_storage_cap` (which also
/// triggers an immediate eviction sweep Rust-side), and the
/// destructive Clear-all action goes through `recorder_clear_all_recordings`.
///
/// Stateful so the post-confirm async flow can guard `mounted` and
/// fan out the Rust call without leaking `BuildContext` across an
/// `await`. Cap presets cover the realistic Recordings-folder span
/// (100 MiB → 5 GiB) — finer-grained values gain nothing for a
/// background-eviction setting, and a free-form numeric field would
/// let users disable the sweep via a careless zero.
class _RecordingsStorageTile extends ConsumerStatefulWidget {
  const _RecordingsStorageTile();

  @override
  ConsumerState<_RecordingsStorageTile> createState() =>
      _RecordingsStorageTileState();
}

class _RecordingsStorageTileState
    extends ConsumerState<_RecordingsStorageTile> {
  /// Latest `recorder_storage_used()` reading; null while the first
  /// snapshot is in flight. Refreshes after cap changes + clear-all
  /// so the row reflects the actual on-disk total, not a stale
  /// pre-eviction figure.
  int? _usedBytes;

  /// Set when the last `recorder_storage_used()` call threw. The
  /// row still renders (with the cap dropdown intact) so a transient
  /// disk hiccup does not strand the user with an unusable tile.
  bool _usageReadFailed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_refreshUsage());
  }

  /// Resolve the recordings root through the canonical Rust getter
  /// — the support_dir + `recordings/` join lives one place
  /// Rust-side, so the Settings tile stays in lock-step with the
  /// recordings browser and the storage-cap sweep.
  String _resolveRoot() => rust_recorder.recorderRecordingsRoot();

  Future<void> _refreshUsage() async {
    try {
      final root = _resolveRoot();
      final used = await rust_recorder.recorderStorageUsed(
        recordingsRoot: root,
      );
      if (!mounted) return;
      setState(() {
        _usedBytes = used.toInt();
        _usageReadFailed = false;
      });
    } catch (e) {
      AppLogger.instance.log(
        'Recordings storage usage read failed',
        name: 'Recording',
        error: e,
        level: LogLevel.warn,
      );
      if (!mounted) return;
      setState(() {
        _usedBytes = null;
        _usageReadFailed = true;
      });
    }
  }

  Future<void> _onCapChanged(int newCapBytes) async {
    final l10n = S.of(context);
    try {
      final root = _resolveRoot();
      // Persist the new cap through the Rust config_store actor so
      // the next launch already sees the new value. `update` on
      // the Notifier debounces the disk write; `recorder_set_storage_cap`
      // re-reads the canonical JSON and runs the eviction sweep.
      await ref
          .read(configProvider.notifier)
          .update((c) => c.copyWith(recordingsStorageCapBytes: newCapBytes));
      final outcome = await rust_recorder.recorderSetStorageCap(
        recordingsRoot: root,
        bytes: BigInt.from(newCapBytes),
      );
      await _refreshUsage();
      if (!mounted) return;
      final reclaimed = outcome.bytesReclaimed.toInt();
      Toast.show(
        context,
        message: reclaimed > 0
            ? l10n.recordingsCapChangedReclaimed(
                rust_format.formatSizeIec(bytes: reclaimed),
              )
            : l10n.recordingsCapChangedNoChange,
        level: ToastLevel.success,
      );
    } catch (e) {
      AppLogger.instance.log(
        'Recordings cap change failed',
        name: 'Recording',
        error: e,
      );
      if (!mounted) return;
      Toast.show(
        context,
        message: localizeError(l10n, e),
        level: ToastLevel.error,
      );
    }
  }

  Future<void> _onClearAll() async {
    final l10n = S.of(context);
    final confirmed = await ConfirmDialog.show(
      context,
      title: l10n.recordingsClearAllConfirmTitle,
      content: Text(l10n.recordingsClearAllConfirmBody),
      confirmLabel: l10n.recordingsClearAllAction,
    );
    if (!confirmed || !mounted) return;
    try {
      final root = _resolveRoot();
      final removed = await rust_recorder.recorderClearAllRecordings(
        recordingsRoot: root,
      );
      await _refreshUsage();
      if (!mounted) return;
      Toast.show(
        context,
        message: l10n.recordingsClearAllResult(removed),
        level: ToastLevel.success,
      );
    } catch (e) {
      AppLogger.instance.log(
        'Recordings clear-all failed',
        name: 'Recording',
        error: e,
      );
      if (!mounted) return;
      Toast.show(
        context,
        message: localizeError(l10n, e),
        level: ToastLevel.error,
      );
    }
  }

  /// Cap presets cover the realistic span for a per-user recordings
  /// folder. A free-form numeric field would let a careless 0 slip
  /// through Rust's `AppConfig::sanitized` clamp back to the default
  /// silently — the dropdown is a closed set and avoids that footgun.
  List<AppPopupSelectOption<int>> _capOptions(S l10n) {
    const mib = 1024 * 1024;
    const gib = 1024 * 1024 * 1024;
    return [
      AppPopupSelectOption(
        value: 100 * mib,
        label: l10n.recordingsCapPreset100Mb,
      ),
      AppPopupSelectOption(
        value: 250 * mib,
        label: l10n.recordingsCapPreset250Mb,
      ),
      AppPopupSelectOption(
        value: 500 * mib,
        label: l10n.recordingsCapPreset500Mb,
      ),
      AppPopupSelectOption(value: gib, label: l10n.recordingsCapPreset1Gb),
      AppPopupSelectOption(value: 2 * gib, label: l10n.recordingsCapPreset2Gb),
      AppPopupSelectOption(value: 5 * gib, label: l10n.recordingsCapPreset5Gb),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = S.of(context);
    final cap = ref.watch(recordingsStorageCapBytesProvider);
    final used = _usedBytes;
    final String usedLabel;
    if (used == null) {
      usedLabel = _usageReadFailed ? '—' : '…';
    } else {
      usedLabel = rust_format.formatSizeIec(bytes: used);
    }
    final capLabel = rust_format.formatSizeIec(bytes: cap);

    // Resolve the dropdown value to the nearest preset so a
    // hand-edited config.json that stamped an off-preset cap still
    // displays a coherent selection without dropping the user's
    // value.
    final options = _capOptions(l10n);
    final selectedCap = options
        .map((o) => o.value)
        .reduce((a, b) => (a - cap).abs() < (b - cap).abs() ? a : b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SettingsRow(
          label: l10n.recordingsTitle,
          subtitle: '$usedLabel / $capLabel',
          icon: Icons.fiber_manual_record_outlined,
          child: AppPopupSelect<int>(
            value: selectedCap,
            options: options,
            onChanged: _onCapChanged,
            leadingIcon: Icons.sd_storage_outlined,
          ),
        ),
        _SettingsRow(
          label: l10n.recordingsCapLabel,
          subtitle: l10n.recordingsCapHint,
          icon: Icons.delete_sweep_outlined,
          child: AppButton.destructive(
            label: l10n.recordingsClearAllAction,
            onTap: _onClearAll,
          ),
        ),
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
    // Magic phrase is the literal app name (locale-invariant). Pattern
    // mirrors GitHub's "type the repo name to delete" guard — the
    // user has to physically type the name into a freshly-empty field
    // before the destructive button enables. A single accidental tap
    // of a normal Confirm button can't trigger the wipe.
    const magicPhrase = 'LetsFLUTssh';
    final confirmed = await TypedNameConfirmDialog.show(
      context,
      title: l10n.resetAllDataConfirmTitle,
      body: Text(l10n.resetAllDataConfirmBody),
      magicPhrase: magicPhrase,
      confirmLabel: l10n.resetAllDataConfirmAction,
      typePromptHint: l10n.resetAllDataConfirmTypePrompt(magicPhrase),
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
    final workspaceEmptyFolders = ref.read(emptyFoldersProvider);

    // Load counts for export dialog. The export orchestrator (and
    // the live size estimator) pulls every byte — sessions, keys,
    // tags, snippets — straight from `letsflutssh.db` Rust-side by
    // id, so the dialog never materialises manager-key PEM. Tags +
    // snippets stay Dart-side for now so the dialog can render
    // per-row checkboxes; the estimator path itself looks them up
    // from the DB regardless of what the dialog holds.
    final allTags = await ref.read(tagsProvider.notifier).loadAll();
    final allSnippets = await ref.read(snippetsProvider.notifier).loadAll();
    if (!context.mounted) return;

    final knownHostsContent = await ref
        .read(knownHostsMutatorProvider)
        .exportToString();
    if (!context.mounted) return;

    final exportResult = await UnifiedExportDialog.show(
      context,
      data: UnifiedExportDialogData(
        sessions: sessions,
        emptyFolders: workspaceEmptyFolders,
        config: ref.read(configProvider),
        knownHostsContent: knownHostsContent,
        tags: allTags,
        snippets: allSnippets,
      ),
      isQrMode: true,
    );

    if (exportResult == null || !context.mounted) return;

    // Hand the encode off to the Rust orchestrator — sessions /
    // manager keys / tags / snippets / known-hosts come straight
    // from `letsflutssh.db`, dedup runs Rust-side, and only the
    // deflated + base64url-encoded ASCII payload returns to Dart
    // for the QR widget. Plaintext credentials never round-trip
    // through the Dart heap during encode.
    final selectedIds = exportResult.selectedSessions.map((s) => s.id).toList();
    final emptyFolders = exportResult.selectedEmptyFolders.toList();
    final cfg = exportResult.options.includeConfig
        ? ref.read(configProvider)
        : null;
    // Shape mapping (FRB input + deeplink wrap + credentials flag)
    // lives in `qr_export_logic.dart` so each branch is unit-tested
    // without booting FRB or showing the dialog.
    final payload = await rust_archive.dbExportQrPayload(
      input: buildDbQrExportInput(
        options: exportResult.options,
        selectedSessionIds: selectedIds,
        selectedEmptyFolders: emptyFolders,
        cfg: cfg,
      ),
    );
    if (!context.mounted) return;
    await QrDisplayScreen.show(
      context,
      data: qrPayloadDeepLink(payload),
      sessionCount: selectedIds.length,
      containsCredentials: qrPayloadHasCredentials(exportResult.options),
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
