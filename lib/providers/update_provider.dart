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
      await _cleanupStaleDownloads(dir.path, info.assetUrl!);
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
    final ok = await _service.openFile(path);
    if (ok) {
      // Clean up after a short delay so the OS has time to read the file
      Future.delayed(const Duration(seconds: 5), () => _cleanupFile(path));
    }
    return ok;
  }

  /// Delete previously downloaded update files in [dir] before starting a
  /// fresh download. Matches any file whose name ends with the same suffix
  /// as the incoming [assetUrl] (e.g. `-windows-x64-setup.exe`).
  Future<void> _cleanupStaleDownloads(String dir, String assetUrl) async {
    try {
      final fileName = Uri.parse(assetUrl).pathSegments.last;
      // Extract the platform suffix: everything after the version segment.
      // e.g. "letsflutssh-1.9.0-windows-x64-setup.exe" → "-windows-x64-setup.exe"
      // The first dash separates name from version; the second separates
      // version from platform — we want from the second dash onward.
      final firstDash = fileName.indexOf('-');
      if (firstDash < 0) return;
      final secondDash = fileName.indexOf('-', firstDash + 1);
      if (secondDash < 0) return;
      final suffix = fileName.substring(secondDash);

      final directory = Directory(dir);
      if (!await directory.exists()) return;
      await for (final entity in directory.list()) {
        if (entity is File && entity.path.endsWith(suffix)) {
          try {
            await entity.delete();
            AppLogger.instance.log(
              'Removed stale download: ${entity.path}',
              name: 'UpdateProvider',
            );
          } catch (e) {
            AppLogger.instance.log(
              'Failed to remove stale download: $e',
              name: 'UpdateProvider',
            );
          }
        }
      }
    } catch (e) {
      AppLogger.instance.log(
        'Stale download cleanup error: $e',
        name: 'UpdateProvider',
      );
    }
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
