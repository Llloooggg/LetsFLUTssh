import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/bus/app_bus.dart';
import '../../core/connection/connection.dart';
import '../../core/connection/connection_step.dart';
import '../../core/sftp/sftp_models.dart';
import '../../core/transfer/conflict_resolver.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/transfer_provider.dart';
import '../../src/rust/api/bus.dart' as rust_bus;
import '../../src/rust/api/transfer.dart' as rust_transfer;
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

  /// Live bus subscription that drives post-completion pane
  /// refreshes — see [`_subscribeTransferBus`] for the contract.
  StreamSubscription<rust_bus.BusEvent>? _transferBusSub;

  /// Initialize the SFTP connection — waits for SSH handshake, then opens
  /// the SFTP subsystem.
  Future<void> initSftp() async {
    final conn = sftpConnection;
    await conn.waitUntilReady();
    // `state == connected` flips before [Connection._adoptSession]
    // assigns the russh handle to `transport`; wait for the adopt
    // to settle so the SFTP open below sees a non-null transport.
    if (conn.isConnecting || conn.isConnected) {
      await conn.transportReady;
    }

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
        _subscribeTransferBus();
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

  /// Subscribe to the transfer bus once SFTP init has succeeded.
  /// On every terminal-state event (`Completed` / `Failed` /
  /// `Cancelled`) for a task targeting THIS connection, refresh
  /// the matching pane controller so the destination shows the
  /// new file immediately. Replaces the prior `_refreshAfterDelay`
  /// shape in `TransferHelpers` which fired 250 ms after **enqueue**
  /// — for any real upload (network + remote disk) the actual PUT
  /// landed long after that timer, and the pane stayed stale until
  /// the user hit F5 manually. The bus event fires the moment the
  /// Rust worker flips state, so refresh races the user's eye
  /// instead of an arbitrary delay.
  ///
  /// `ref.onDispose` ties the subscription lifetime to the host
  /// widget so a tab close cancels the listener cleanly. FRB-
  /// unreachable contexts (flutter_test without the native lib)
  /// land in the catch and silently skip the subscription — pane
  /// refresh only matters under a real bus.
  void _subscribeTransferBus() {
    if (_transferBusSub != null) return;
    try {
      _transferBusSub = AppBus.instance
          .subscribe(rust_bus.BusTopic.transfer)
          .listen((event) {
            if (event is rust_bus.BusEvent_TransferTaskState) {
              final s = event.state;
              if (s == rust_bus.BusTaskState.completed ||
                  s == rust_bus.BusTaskState.failed ||
                  s == rust_bus.BusTaskState.cancelled) {
                unawaited(_refreshAfterTransferTerminal(event.id));
              }
            }
          });
      // Cancellation lives on `disposeSftpBrowser` — host classes
      // (`FileBrowserTab`, `MobileFileBrowser`) must call it from
      // their own `dispose`. `WidgetRef` doesn't expose `onDispose`
      // (that's a provider-side API), so the mixin relies on the
      // host's lifecycle hook to drop the subscription.
    } on StateError catch (e) {
      AppLogger.instance.log(
        'SftpBrowser transfer-bus subscribe skipped (FRB not ready): $e',
        name: 'SftpBrowser',
      );
    }
  }

  /// Look up the just-finished task's snapshot and refresh the
  /// destination pane. Upload → remote pane; Download → local
  /// pane. `sessionId` filter keeps a noisy concurrent transfer
  /// on a sibling tab from refreshing our panes.
  Future<void> _refreshAfterTransferTerminal(String taskId) async {
    try {
      final snapshots = await rust_transfer.transferSnapshotAll();
      rust_transfer.DbTransferSnapshot? task;
      for (final snap in snapshots) {
        if (snap.id == taskId) {
          task = snap;
          break;
        }
      }
      if (task == null || task.sessionId != sftpConnection.id) return;
      if (!mounted) return;
      final result = sftpResult;
      if (result == null) return;
      if (task.kind == rust_transfer.DbTransferKind.upload) {
        result.remoteCtrl.refresh();
      } else {
        result.localCtrl.refresh();
      }
    } catch (e) {
      AppLogger.instance.log(
        'SftpBrowser pane refresh after transfer failed: $e',
        name: 'SftpBrowser',
        level: LogLevel.warn,
      );
    }
  }

  /// Cancel the transfer-bus subscription started in
  /// [`_subscribeTransferBus`]. Host classes call this from their
  /// own `dispose` — the mixin can't hook into the widget's
  /// lifecycle directly because `WidgetRef.onDispose` doesn't
  /// exist (provider-side API only).
  void disposeSftpBrowser() {
    unawaited(_transferBusSub?.cancel());
    _transferBusSub = null;
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
    final remote = sftpResult?.remoteCtrl;
    if (remote == null || entries.isEmpty) return;
    // `remote.fs` is the kind-appropriate `FileSystem` impl — SFTP
    // (`RemoteFS` wrapping `RustSftpFs`), WebDAV (`WebDavFileSystem`),
    // or S3 (`S3FileSystem`). Previously this gated on the
    // SFTP-typed `sftpResult.filesystem` which was null for non-SSH,
    // so drag-drop uploads to a WebDAV / S3 pane silently no-op'd —
    // the user-reported "0 reaction" symptom. The transfer queue
    // dispatches by `ProviderRegistry` on the Rust side, so this
    // call lands on the right backend regardless of kind.
    final resolver = buildConflictResolver(showApplyToAll: entries.length > 1);
    try {
      for (final entry in entries) {
        if (resolver.isCancelled) break;
        if (!mounted) return;
        await TransferHelpers.enqueueUpload(
          manager: ref.read(transfersProvider.notifier),
          remoteFs: remote.fs,
          connectionId: sftpConnection.id,
          entry: entry,
          remoteDirPath: remote.currentPath,
          remoteCtrl: remote,
          conflictResolver: resolver,
        );
      }
    } finally {
      // Drop the Rust-side handle so the per-batch entry doesn't
      // leak into the BatchStateRegistry across the app lifetime.
      resolver.dispose();
    }
  }

  /// Enqueue downloads for [entries] from remote to local.
  Future<void> downloadMany(List<FileEntry> entries) async {
    final remote = sftpResult?.remoteCtrl;
    final local = sftpResult?.localCtrl;
    if (remote == null || local == null || entries.isEmpty) return;
    final resolver = buildConflictResolver(showApplyToAll: entries.length > 1);
    try {
      for (final entry in entries) {
        if (resolver.isCancelled) break;
        if (!mounted) return;
        await TransferHelpers.enqueueDownload(
          manager: ref.read(transfersProvider.notifier),
          remoteFs: remote.fs,
          connectionId: sftpConnection.id,
          entry: entry,
          localDirPath: local.currentPath,
          localCtrl: local,
          conflictResolver: resolver,
        );
      }
    } finally {
      resolver.dispose();
    }
  }

  BatchConflictResolver buildConflictResolver({required bool showApplyToAll}) {
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
