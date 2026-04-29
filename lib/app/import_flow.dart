import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/import/import_service.dart';
import '../core/progress/progress_reporter.dart';
import '../src/rust/api/archive.dart' as rust_archive;
import '../core/session/qr_decoded_source.dart';
import '../features/settings/export_import.dart';
import '../l10n/app_localizations.dart';
import '../providers/config_provider.dart';
import '../providers/key_provider.dart';
import '../providers/session_provider.dart';
import '../providers/snippet_provider.dart';
import '../providers/tag_provider.dart';
import '../utils/format.dart';
import '../utils/logger.dart';
import '../widgets/app_dialog.dart';
import '../widgets/lfs_import_dialog.dart';
import '../widgets/link_import_preview_dialog.dart';
import '../widgets/toast.dart';
import 'navigator_key.dart';

/// Apply the QR deep-link / paste-link payload to the user's stores.
///
/// Dispatches on the [QrDecodedSource] variant:
///   * Rust source — staged handle id consumed by `applyOpenedHandle`,
///     bytes never crossed the FRB boundary outwards.
///   * Dart source — legacy fallback, applies via `applyResultViaRust`
///     against the Dart-walked `ExportPayloadData` tree.
///
/// Both paths show the same `LinkImportPreviewDialog` and route the
/// post-import toast through `addPostFrameCallback` (the deeplink
/// pump may fire before a `BuildContext` with a Toast surface is
/// mounted).
Future<void> handleQrImport(WidgetRef ref, QrDecodedSource source) async {
  final ctx = navigatorKey.currentContext;
  if (ctx == null || !ctx.mounted) return;
  final choice = await LinkImportPreviewDialog.show(ctx, source: source);
  if (choice == null) return;

  try {
    final summary = await _applyRustQrSource(
      ref: ref,
      rust: source.rust,
      choice: choice,
    );

    AppLogger.instance.log(
      'QR import complete: ${summary.sessions} session(s), '
      '${summary.managerKeys} key(s), '
      '${summary.tags} tag(s), '
      '${summary.snippets} snippet(s)',
      name: 'App',
    );

    // Context may have been torn down during the import await — re-read
    // off the global navigator key so we don't paint onto a disposed tree.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final postCtx = navigatorKey.currentContext;
      if (postCtx != null && postCtx.mounted) {
        Toast.show(
          postCtx,
          message: formatImportSummary(S.of(postCtx), summary),
          level: ToastLevel.success,
        );
      }
    });
  } catch (e) {
    AppLogger.instance.log('QR import failed: $e', name: 'App', error: e);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final postCtx = navigatorKey.currentContext;
      if (postCtx != null && postCtx.mounted) {
        Toast.show(
          postCtx,
          message: S.of(postCtx).importFailed(localizeError(S.of(postCtx), e)),
          level: ToastLevel.error,
        );
      }
    });
  }
}

/// Apply a Rust-staged QR handle. The bytes never crossed the FRB
/// boundary outwards — `applyOpenedHandle` consumes the handle in
/// the same sqlite transaction as `.lfs` imports, and the staged
/// `config_json` is read back from the apply result for restore.
Future<ImportSummary> _applyRustQrSource({
  required WidgetRef ref,
  required rust_archive.DbImportOpenResult rust,
  required LinkImportPreviewResult choice,
}) async {
  final apply = await applyOpenedHandle(
    handleId: rust.handleId,
    mode: choice.mode,
    applySessions: choice.options.includeSessions,
    applyKeys: choice.options.includeManagerKeys,
    applyTags: choice.options.includeTags,
    applySnippets: choice.options.includeSnippets,
    applyKnownHosts: choice.options.includeKnownHosts,
    refreshAfterImport: () => _refreshStores(ref),
  );
  // Config restore stays Dart-side — `lfs_core::archive::apply`
  // leaves `config.json` to the caller. Security tier setup is
  // per-machine and never travels.
  final cfg = choice.options.includeConfig
      ? decodeConfigFromApply(apply)
      : null;
  if (cfg != null) {
    ref
        .read(configProvider.notifier)
        .update((current) => cfg.copyWithSecurity(security: current.security));
  }
  _invalidateImportProviders(ref);
  return _summaryFromApply(apply, cfg != null);
}

/// Public helper for callers that already have a [QrDecodedSource]
/// + a user-confirmed [LinkImportPreviewResult] (paste-import-link
/// flow on Settings, where the dialog is shown by the screen and
/// the apply is dispatched separately).
Future<void> handleQrImportSource({
  required BuildContext context,
  required WidgetRef ref,
  required QrDecodedSource source,
  required LinkImportPreviewResult choice,
}) async {
  try {
    final summary = await _applyRustQrSource(
      ref: ref,
      rust: source.rust,
      choice: choice,
    );
    if (!context.mounted) return;
    Toast.show(
      context,
      message: formatImportSummary(S.of(context), summary),
      level: ToastLevel.success,
    );
  } catch (e) {
    AppLogger.instance.log('QR import failed: $e', name: 'App', error: e);
    if (!context.mounted) return;
    Toast.show(
      context,
      message: S.of(context).importFailed(localizeError(S.of(context), e)),
      level: ToastLevel.error,
    );
  }
}

/// Show the LFS archive import dialog for [filePath] and apply the
/// chosen mode on confirm.
///
/// Classification happens before the prompt so SAF-picked non-LFS
/// content (e.g. `.apk` with an LFS extension filter Android
/// ignored) is rejected up front, and unencrypted plain-ZIP exports
/// skip the password prompt.
///
/// The archive opens via `dbImportOpen` Rust-side; the staged handle
/// is consumed by the apply step on success or dropped on cancel /
/// failure. Plaintext payload (session passwords, key PEM) never
/// crosses the FRB boundary outwards.
Future<void> showLfsImportDialog(
  BuildContext context,
  WidgetRef ref,
  String filePath,
) async {
  AppLogger.instance.log(
    'LFS import started: ${filePath.split('/').last}',
    name: 'App',
  );
  final kind = ExportImport.probeArchive(filePath);
  if (kind == LfsArchiveKind.notLfs) {
    Toast.show(
      context,
      message: S.of(context).errLfsNotArchive,
      level: ToastLevel.error,
    );
    return;
  }
  final result = await LfsImportDialog.show(
    context,
    filePath: filePath,
    isEncrypted: kind == LfsArchiveKind.encryptedLfs,
  );
  if (result == null || !context.mounted) return;

  // Show progress bar while Argon2id + decryption run in isolate and
  // the subsequent per-store writes stream step counts back to the UI.
  final l10n = S.of(context);
  final progress = ProgressReporter(l10n.progressReadingArchive);
  AppProgressBarDialog.show(context, progress);
  var progressShown = true;
  String? handleId;

  try {
    progress.phase(l10n.progressDecrypting);
    final opened = await rust_archive.dbImportOpen(
      path: filePath,
      password: result.password,
    );
    handleId = opened.handleId;

    final apply = await applyOpenedHandle(
      handleId: handleId,
      mode: result.mode,
      applySessions: true,
      applyKeys: true,
      applyTags: true,
      applySnippets: true,
      applyKnownHosts: opened.preview.hasKnownHosts,
      refreshAfterImport: () => _refreshStores(ref),
    );
    handleId = null; // consumed by apply on success
    final restoredConfig = decodeConfigFromApply(apply);
    if (restoredConfig != null) {
      ref.read(configProvider.notifier).update((_) => restoredConfig);
    }
    _invalidateImportProviders(ref);
    final summary = _summaryFromApply(apply, restoredConfig != null);

    AppLogger.instance.log(
      'LFS import success: ${summary.sessions} session(s)',
      name: 'App',
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
    AppLogger.instance.log('LFS import failed: $e', name: 'App', error: e);
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
    if (handleId != null) {
      try {
        await rust_archive.dbImportDrop(handleId: handleId);
      } catch (_) {}
    }
    if (progressShown && context.mounted) {
      Navigator.of(context).pop();
    }
    progress.dispose();
  }
}

/// Refresh cached FutureProviders after a QR / LFS / paste-link import
/// so the UI picks up newly imported keys, tags, and snippets without
/// an app restart.
void _invalidateImportProviders(WidgetRef ref) {
  ref.invalidate(sshKeysProvider);
  ref.invalidate(tagsProvider);
  ref.invalidate(snippetsProvider);
}

/// Reload the in-memory caches the UI binds to. Rust apply
/// writes directly through the DB — the Dart-side caches need
/// a `load()` to pick up the new rows.
Future<void> _refreshStores(WidgetRef ref) async {
  await ref.read(sessionProvider.notifier).load();
  await ref.read(tagStoreProvider).loadAll();
  await ref.read(snippetStoreProvider).loadAll();
}

/// Build a Dart-side `ImportSummary` from the Rust `DbApplyResult`.
/// `configApplied` mirrors the Dart-side config-restore branch since
/// the Rust apply leaves `config.json` to the caller.
ImportSummary _summaryFromApply(
  rust_archive.DbApplyResult apply,
  bool configApplied, {
  int skippedSessions = 0,
}) {
  return ImportSummary(
    sessions: apply.sessionsApplied.toInt(),
    folders: apply.foldersApplied.toInt(),
    managerKeys: apply.keysApplied.toInt(),
    tags: apply.tagsApplied.toInt(),
    snippets: apply.snippetsApplied.toInt(),
    configApplied: configApplied,
    knownHostsApplied: apply.knownHostsApplied > 0,
    skippedSessions: skippedSessions,
    skippedLinks: 0,
  );
}
