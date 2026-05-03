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
    final notifier = ref.read(sessionProvider.notifier);

    // Load counts for export dialog. The export orchestrator pulls
    // bytes directly from `letsflutssh.db` Rust-side; the dialog
    // carries the SshKeyEntry map only so the QR / .lfs size
    // estimators can measure deflate-encoded payload bytes.
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

    // The Rust encoder returns the raw deflated+base64url payload; the
    // `letsflutssh://import?d=` prefix is a one-line wrap so we keep it
    // inline here rather than ferry a one-call helper.
    final deepLink = 'letsflutssh://import?d=$payload';
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
