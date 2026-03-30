import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../core/update/update_service.dart';
import 'version_provider.dart';
import '../utils/logger.dart';

/// Possible states of the update workflow.
enum UpdateStatus {
  idle,
  checking,
  upToDate,
  updateAvailable,
  downloading,
  downloaded,
  error,
}

/// Immutable snapshot of the current update state.
class UpdateState {
  final UpdateStatus status;
  final UpdateInfo? info;
  final double progress;
  final String? downloadedPath;
  final String? error;

  const UpdateState({
    this.status = UpdateStatus.idle,
    this.info,
    this.progress = 0,
    this.downloadedPath,
    this.error,
  });

  UpdateState copyWith({
    UpdateStatus? status,
    UpdateInfo? info,
    double? progress,
    String? downloadedPath,
    String? error,
  }) {
    return UpdateState(
      status: status ?? this.status,
      info: info ?? this.info,
      progress: progress ?? this.progress,
      downloadedPath: downloadedPath ?? this.downloadedPath,
      error: error ?? this.error,
    );
  }
}

/// Provider for the [UpdateService] instance (injectable for tests).
final updateServiceProvider = Provider<UpdateService>((ref) {
  return UpdateService();
});

/// Provider that manages the update check / download lifecycle.
final updateProvider =
    NotifierProvider<UpdateNotifier, UpdateState>(UpdateNotifier.new);

class UpdateNotifier extends Notifier<UpdateState> {
  @override
  UpdateState build() => const UpdateState();

  UpdateService get _service => ref.read(updateServiceProvider);

  /// Check GitHub for a newer release.
  Future<void> check() async {
    if (state.status == UpdateStatus.checking ||
        state.status == UpdateStatus.downloading) {
      return; // already in progress
    }
    state = const UpdateState(status: UpdateStatus.checking);
    try {
      final version = ref.read(appVersionProvider);
      final info = await _service.checkForUpdate(version);
      state = UpdateState(
        status: info.hasUpdate
            ? UpdateStatus.updateAvailable
            : UpdateStatus.upToDate,
        info: info,
      );
    } catch (e) {
      AppLogger.instance
          .log('Update check failed: $e', name: 'UpdateProvider', error: e);
      state = UpdateState(
        status: UpdateStatus.error,
        error: e.toString(),
      );
    }
  }

  /// Download the asset for the current platform.
  ///
  /// If [autoInstall] is true, automatically opens the installer after a
  /// successful download (used by the startup update dialog so that
  /// "Download & Install" actually installs without a second tap).
  Future<void> download({bool autoInstall = false}) async {
    final info = state.info;
    if (info == null || info.assetUrl == null) return;
    if (state.status == UpdateStatus.downloading) return;

    state = state.copyWith(status: UpdateStatus.downloading, progress: 0);
    try {
      final dir = await getApplicationSupportDirectory();
      final path = await _service.downloadAsset(
        info.assetUrl!,
        dir.path,
        expectedDigest: info.assetDigest,
        onProgress: (received, total) {
          if (total > 0) {
            state = state.copyWith(progress: received / total);
          }
        },
      );
      state = state.copyWith(
        status: UpdateStatus.downloaded,
        downloadedPath: path,
        progress: 1,
      );
      if (autoInstall) {
        await install();
      }
    } catch (e) {
      AppLogger.instance
          .log('Download failed: $e', name: 'UpdateProvider', error: e);
      state = state.copyWith(
        status: UpdateStatus.error,
        error: 'Download failed: $e',
      );
    }
  }

  /// Open the downloaded installer file.
  Future<bool> install() async {
    final path = state.downloadedPath;
    if (path == null) return false;
    final ok = await UpdateService.openFile(path);
    if (ok) {
      // Clean up after a short delay so the OS has time to read the file
      Future.delayed(const Duration(seconds: 5), () => _cleanupFile(path));
    }
    return ok;
  }

  Future<void> _cleanupFile(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
        AppLogger.instance.log('Cleaned up: $path', name: 'UpdateProvider');
      }
    } catch (e) {
      AppLogger.instance.log('Cleanup failed: $e', name: 'UpdateProvider');
    }
  }
}
