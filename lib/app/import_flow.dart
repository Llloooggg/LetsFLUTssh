import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/import/import_service.dart';
import '../core/progress/progress_reporter.dart';
import '../src/rust/api/archive.dart' as rust_archive;
import '../core/session/qr_codec.dart';
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

/// Apply the QR deep-link payload to the user's stores.
///
/// Mirror of `.lfs` + paste-link paths: the preview dialog lets the
/// user pick what to bring in and merge vs. replace before any write
/// touches the DB. Context is resolved off [navigatorKey] — the deep-
/// link pump may fire before any `BuildContext` with a Toast surface
/// is mounted, so every post-import notification routes through
/// `addPostFrameCallback`.
Future<void> handleQrImport(WidgetRef ref, ExportPayloadData data) async {
  final ctx = navigatorKey.currentContext;
  if (ctx == null || !ctx.mounted) return;
  final choice = await LinkImportPreviewDialog.show(ctx, payload: data);
  if (choice == null) return;

  // Build the full ImportResult from the payload, then let
  // [ImportResult.filtered] drop whatever the user unchecked.
  final fullResult = ImportResult(
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
    includeTags: data.tags.isNotEmpty,
    includeSnippets: data.snippets.isNotEmpty,
    includeKnownHosts: data.knownHostsContent != null,
  );
  final importResult = fullResult.filtered(choice.options, choice.mode);

  try {
    final apply = await applyResultViaRust(
      importResult,
      refreshAfterImport: () => _refreshStores(ref),
    );
    if (importResult.config != null) {
      ref.read(configProvider.notifier).update((_) => importResult.config!);
    }
    _invalidateImportProviders(ref);
    final summary = _summaryFromApply(apply, importResult);

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

/// Show the LFS archive import dialog for [filePath] and apply the
/// chosen mode on confirm.
///
/// Classification happens before the prompt so SAF-picked non-LFS
/// content (e.g. `.apk` with an LFS extension filter Android
/// ignored) is rejected up front, and unencrypted plain-ZIP exports
/// skip the password prompt.
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

  try {
    final importResult = await ExportImport.import_(
      filePath: filePath,
      masterPassword: result.password,
      mode: result.mode,
      options: const ExportOptions(
        includeSessions: true,
        includeConfig: true,
        includeKnownHosts: true,
        includeManagerKeys: true,
        includeTags: true,
        includeSnippets: true,
      ),
      progress: progress,
      l10n: l10n,
    );

    final apply = await applyResultViaRust(
      importResult,
      refreshAfterImport: () => _refreshStores(ref),
    );
    if (importResult.config != null) {
      ref.read(configProvider.notifier).update((_) => importResult.config!);
    }
    _invalidateImportProviders(ref);
    final summary = _summaryFromApply(apply, importResult);

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
/// writes directly through the DB — the Dart-side store lists
/// (`SessionStore._sessions` etc) need a `load()` to pick up
/// the new rows.
Future<void> _refreshStores(WidgetRef ref) async {
  await ref.read(sessionStoreProvider).load();
  await ref.read(tagStoreProvider).loadAll();
  await ref.read(snippetStoreProvider).loadAll();
}

/// Build a Dart-side `ImportSummary` from the Rust `DbApplyResult`
/// + the original `ImportResult`. Counters route from Rust;
/// `configApplied` mirrors the Dart-side config restore branch
/// since the Rust apply doesn't touch `config.json`.
ImportSummary _summaryFromApply(
  rust_archive.DbApplyResult apply,
  ImportResult source,
) {
  return ImportSummary(
    sessions: apply.sessionsApplied.toInt(),
    folders: apply.foldersApplied.toInt(),
    managerKeys: apply.keysApplied.toInt(),
    tags: apply.tagsApplied.toInt(),
    snippets: apply.snippetsApplied.toInt(),
    configApplied: source.config != null,
    knownHostsApplied: apply.knownHostsApplied > 0,
    skippedSessions: source.skippedSessions,
    skippedLinks: 0,
  );
}
