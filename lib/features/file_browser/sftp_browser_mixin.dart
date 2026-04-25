import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/connection/connection.dart';
import '../../core/connection/connection_step.dart';
import '../../core/sftp/sftp_models.dart';
import '../../core/transfer/conflict_resolver.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/transfer_provider.dart';
import '../../utils/format.dart' show localizeError;
import '../../utils/logger.dart';
import '../../widgets/connection_progress.dart';
import '../../widgets/file_conflict_dialog.dart';
import 'sftp_initializer.dart';
import 'transfer_helpers.dart';

/// Shared SFTP browser logic used by both desktop [FileBrowserTab] and
/// mobile [MobileFileBrowser].
///
/// Provides common [initSftp], [uploadMany], and [downloadMany]
/// implementations. Concrete classes must provide the abstract getters
/// for their widget-specific fields and override [onSftpReady] to
/// apply platform-specific state.
mixin SftpBrowserMixin<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  /// The SSH connection this browser operates on.
  Connection get sftpConnection;

  /// Optional factory for testing — bypasses real SSH/SFTP.
  Future<SFTPInitResult> Function(Connection)? get sftpInitFactory;

  /// Key for the progress widget that displays connection steps.
  GlobalKey<ConnectionProgressState> get progressKey;

  /// Current SFTP init result (null until initialization completes).
  SFTPInitResult? get sftpResult;
  set sftpResult(SFTPInitResult? value);

  /// Whether SFTP initialization is in progress.
  bool get sftpInitializing;
  set sftpInitializing(bool value);

  /// Error message if initialization failed.
  String? get sftpError;
  set sftpError(String? value);

  /// Called after successful SFTP initialization.
  /// Override to apply platform-specific state (e.g. storagePermissionDenied).
  void onSftpReady(SFTPInitResult result) {}

  /// Initialize the SFTP connection — waits for SSH handshake, then opens
  /// the SFTP subsystem.
  Future<void> initSftp() async {
    final conn = sftpConnection;
    await conn.waitUntilReady();

    if (!conn.isConnected) {
      if (mounted) {
        final l10n = S.of(context);
        final error = conn.connectionError != null
            ? localizeError(l10n, conn.connectionError!)
            : l10n.errConnectionFailed;
        progressKey.currentState?.writeError(error);
        setState(() {
          sftpError = error;
          sftpInitializing = false;
        });
      }
      return;
    }

    progressKey.currentState?.addStep(
      const ConnectionStep(
        phase: ConnectionPhase.openChannel,
        status: StepStatus.inProgress,
      ),
    );

    try {
      final result = sftpInitFactory != null
          ? await sftpInitFactory!(conn)
          : await SFTPInitializer.init(conn);
      sftpResult = result;
      if (mounted) {
        onSftpReady(result);
        setState(() => sftpInitializing = false);
      }
    } catch (e) {
      AppLogger.instance.log(
        'SFTP init failed: $e',
        name: 'SftpBrowser',
        error: e,
      );
      progressKey.currentState?.addStep(
        ConnectionStep(
          phase: ConnectionPhase.openChannel,
          status: StepStatus.failed,
          detail: e.toString(),
        ),
      );
      if (mounted) {
        final l10n = S.of(context);
        setState(() {
          sftpError = l10n.errSftpInitFailed(localizeError(l10n, e));
          sftpInitializing = false;
        });
      }
    }
  }

  /// Enqueue a single upload from local to remote.
  void upload(FileEntry entry) => uploadMany([entry]);

  /// Enqueue a single download from remote to local.
  void download(FileEntry entry) => downloadMany([entry]);

  /// Enqueue uploads for [entries] from local to remote.
  ///
  /// When a destination already exists, prompts the user. A single
  /// [BatchConflictResolver] is shared across the batch so the
  /// "apply to all remaining" choice sticks for this call.
  Future<void> uploadMany(List<FileEntry> entries) async {
    final sftp = sftpResult?.filesystem;
    final remote = sftpResult?.remoteCtrl;
    if (sftp == null || remote == null || entries.isEmpty) return;
    final loc = S.of(context);
    final resolver = _buildResolver(showApplyToAll: entries.length > 1);

    for (final entry in entries) {
      if (resolver.isCancelled) break;
      if (!mounted) return;
      await TransferHelpers.enqueueUpload(
        manager: ref.read(transferManagerProvider),
        sftp: sftp,
        entry: entry,
        remoteDirPath: remote.currentPath,
        remoteCtrl: remote,
        loc: loc,
        conflictResolver: resolver,
      );
    }
  }

  /// Enqueue downloads for [entries] from remote to local.
  Future<void> downloadMany(List<FileEntry> entries) async {
    final sftp = sftpResult?.filesystem;
    final local = sftpResult?.localCtrl;
    if (sftp == null || local == null || entries.isEmpty) return;
    final loc = S.of(context);
    final resolver = _buildResolver(showApplyToAll: entries.length > 1);

    for (final entry in entries) {
      if (resolver.isCancelled) break;
      if (!mounted) return;
      await TransferHelpers.enqueueDownload(
        manager: ref.read(transferManagerProvider),
        sftp: sftp,
        entry: entry,
        localDirPath: local.currentPath,
        localCtrl: local,
        loc: loc,
        conflictResolver: resolver,
      );
    }
  }

  BatchConflictResolver _buildResolver({required bool showApplyToAll}) {
    return BatchConflictResolver((path, {bool isRemote = false}) async {
      if (!mounted) return const ConflictDecision(ConflictAction.cancel);
      return FileConflictDialog.show(
        context,
        targetPath: path,
        isRemoteTarget: isRemote,
        showApplyToAll: showApplyToAll,
      );
    });
  }
}
