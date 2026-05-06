import 'dart:convert' show utf8;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge.dart'
    show AnyhowException;

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

/// Side-effect seams for the LFS / QR / paste-link import dispatchers
/// in this file. The dispatchers are pure UI glue — every line that
/// matters (probe → open → apply → drop, plus the password / preview
/// dialog round-trips) goes through one of the six fields below, so
/// tests can drive every branch (notLfs reject, dialog cancel, open
/// throws, apply throws, config-restore on/off, handle drop on
/// failure) without booting FRB or rendering a real dialog.
///
/// Production wiring lives in [ImportFlowSeams.production]; tests
/// swap the bag via [debugSetImportFlowSeams] (clear by passing
/// `null` in `tearDown`).
@visibleForTesting
class ImportFlowSeams {
  const ImportFlowSeams({
    required this.probeArchive,
    required this.openArchive,
    required this.dropHandle,
    required this.applyHandle,
    required this.showLfsDialog,
    required this.showLinkPreviewDialog,
  });

  factory ImportFlowSeams.production() => const ImportFlowSeams(
    probeArchive: ExportImport.probeArchive,
    openArchive: openArchiveWithTypedErrors,
    dropHandle: rust_archive.dbImportDrop,
    applyHandle: applyOpenedHandle,
    showLfsDialog: LfsImportDialog.show,
    showLinkPreviewDialog: LinkImportPreviewDialog.show,
  );

  final Future<LfsArchiveKind> Function(String filePath) probeArchive;

  final Future<rust_archive.DbImportOpenResult> Function({
    required String path,
    required String password,
  })
  openArchive;

  final Future<void> Function({required String handleId}) dropHandle;

  final Future<rust_archive.DbApplyResult> Function({
    required String handleId,
    required ImportMode mode,
    required bool applySessions,
    required bool applyKeys,
    required bool applyTags,
    required bool applySnippets,
    required bool applyKnownHosts,
    Future<void> Function()? refreshAfterImport,
  })
  applyHandle;

  final Future<LfsImportDialogResult?> Function(
    BuildContext context, {
    required String filePath,
    bool isEncrypted,
  })
  showLfsDialog;

  final Future<LinkImportPreviewResult?> Function(
    BuildContext context, {
    required QrDecodedSource source,
  })
  showLinkPreviewDialog;
}

/// Wraps [rust_archive.dbImportOpen] so the Rust-side
/// `Error::ArchiveFutureVersion` (formatted as
/// `unsupported_archive_version: found=N, supported=M`) surfaces as
/// the typed [UnsupportedLfsVersionException] the import dialog
/// chain already maps to a localized message via
/// `lib/utils/format.dart`.
Future<rust_archive.DbImportOpenResult> openArchiveWithTypedErrors({
  required String path,
  required String password,
}) async {
  try {
    return await rust_archive.dbImportOpen(
      path: path,
      password: utf8.encode(password),
    );
  } on AnyhowException catch (e) {
    final parsed = _parseUnsupportedArchiveVersion(e.message);
    if (parsed != null) {
      throw UnsupportedLfsVersionException(
        found: parsed.$1,
        supported: parsed.$2,
      );
    }
    rethrow;
  }
}

/// Parse the `Error::ArchiveFutureVersion` Display format. Returns
/// `(found, supported)` when the message matches, `null` otherwise.
(int, int)? _parseUnsupportedArchiveVersion(String message) {
  final m = RegExp(
    r'unsupported_archive_version: found=(-?\d+), supported=(-?\d+)',
  ).firstMatch(message);
  if (m == null) return null;
  final found = int.tryParse(m.group(1)!);
  final supported = int.tryParse(m.group(2)!);
  if (found == null || supported == null) return null;
  return (found, supported);
}

ImportFlowSeams _seams = ImportFlowSeams.production();

/// Swap the active [ImportFlowSeams]. Pass `null` to restore the
/// production wiring. `@visibleForTesting` so a forgotten override
/// in production code trips the analyzer.
@visibleForTesting
void debugSetImportFlowSeams(ImportFlowSeams? seams) {
  _seams = seams ?? ImportFlowSeams.production();
}

/// Apply the QR deep-link / paste-link payload to the user's stores.
///
/// The [QrDecodedSource] always carries a Rust-staged handle id consumed
/// by `applyOpenedHandle` — payload bytes never cross the FRB boundary
/// outwards. The post-import toast is routed through
/// `addPostFrameCallback` because the deeplink pump may fire before a
/// `BuildContext` with a Toast surface is mounted.
Future<void> handleQrImport(WidgetRef ref, QrDecodedSource source) async {
  final ctx = navigatorKey.currentContext;
  if (ctx == null || !ctx.mounted) return;
  final choice = await _seams.showLinkPreviewDialog(ctx, source: source);
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
  final apply = await _seams.applyHandle(
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
  final kind = await _seams.probeArchive(filePath);
  if (!context.mounted) return;
  if (kind == LfsArchiveKind.notLfs) {
    Toast.show(
      context,
      message: S.of(context).errLfsNotArchive,
      level: ToastLevel.error,
    );
    return;
  }
  final result = await _seams.showLfsDialog(
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
    final opened = await _seams.openArchive(
      path: filePath,
      password: result.password,
    );
    handleId = opened.handleId;

    final apply = await _seams.applyHandle(
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
        await _seams.dropHandle(handleId: handleId);
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
  await ref.read(tagsProvider.notifier).loadAll();
  await ref.read(snippetsProvider.notifier).loadAll();
}

/// Build a Dart-side `ImportSummary` from the Rust `DbApplyResult`.
/// `configApplied` mirrors the Dart-side config-restore branch since
/// the Rust apply leaves `config.json` to the caller.
///
/// Throws [LfsImportRolledBackException] when the Rust apply driver
/// hit a per-row error in Replace mode and rolled the transaction
/// back. Replace mode is all-or-nothing: returning a "success"
/// summary against zeroed counters would lie to the user about
/// whether their pre-import data survived. The catch arms in each
/// caller surface the exception via `localizeError` ("Import failed
/// — your data has been restored").
ImportSummary _summaryFromApply(
  rust_archive.DbApplyResult apply,
  bool configApplied, {
  int skippedSessions = 0,
}) {
  if (apply.rolledBack) {
    throw LfsImportRolledBackException(
      cause: apply.errors.isEmpty ? 'rolled back' : apply.errors.join('; '),
    );
  }
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
