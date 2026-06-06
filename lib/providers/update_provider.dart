import 'dart:io' show Platform;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/update/update_service.dart';
import '../platform/android/apk_installer.dart';
import '../src/rust/api/macos_installer.dart' as rust_macos_installer;
import '../src/rust/api/update_http.dart' as rust_update;
import '../src/rust/api/update_metadata.dart' as rust_update_meta;
import 'version_provider.dart';
import '../utils/logger.dart';

/// Possible states of the update workflow.
///
/// [verifying] covers the window between "HTTP bytes are on disk"
/// and "installer ready" — SHA256 hash, manifest + signature fetch
/// and Ed25519 verification. Split out from [downloading] so the UI
/// can swap the determinate "Downloading X%" bar for an
/// indeterminate "Verifying…" bar instead of parking at 100% for
/// tens of seconds.
enum UpdateStatus {
  idle,
  checking,
  upToDate,
  updateAvailable,
  downloading,
  verifying,
  downloaded,
  error,
}

/// Immutable snapshot of the current update state.
class UpdateState {
  final UpdateStatus status;
  final UpdateInfo? info;
  final double progress;
  final String? downloadedPath;
  final Object? error;

  const UpdateState({
    this.status = UpdateStatus.idle,
    this.info,
    this.progress = 0,
    this.downloadedPath,
    this.error,
  });

  /// Sentinel for clearing nullable fields in [copyWith].
  static const _unset = Object();

  UpdateState copyWith({
    UpdateStatus? status,
    UpdateInfo? info,
    double? progress,
    Object? downloadedPath = _unset,
    Object? error = _unset,
  }) {
    return UpdateState(
      status: status ?? this.status,
      info: info ?? this.info,
      progress: progress ?? this.progress,
      downloadedPath: identical(downloadedPath, _unset)
          ? this.downloadedPath
          : downloadedPath as String?,
      error: identical(error, _unset) ? this.error : error,
    );
  }

  /// True while the updater is actively fetching or verifying the asset
  /// bytes ([UpdateStatus.downloading] or [UpdateStatus.verifying]) — the
  /// span in which the update surfaces must show progress instead of
  /// action buttons, so the primary download/install action cannot be
  /// re-triggered and Skip/Cancel cannot fire mid-flight. [downloaded] is
  /// excluded: it hands off to the installer and each surface keeps an
  /// escape (Cancel / Install Now) since [UpdateNotifier.install] leaves
  /// the status at [downloaded].
  bool get isDownloadingOrVerifying =>
      status == UpdateStatus.downloading || status == UpdateStatus.verifying;
}

/// Provider for the [UpdateService] instance (injectable for tests).
final updateServiceProvider = Provider<UpdateService>((ref) {
  // On macOS the service is wired with the Rust-side installer so a
  // downloaded `.dmg` is mounted, rsynced over the live bundle,
  // re-signed under the user's personal cert (if any), verified,
  // and atomically swapped. The callback returns `true` on success;
  // on `false` the service falls back to the `open <dmg>` Finder
  // reveal so the user can drag the .app over manually. All other
  // platforms receive the null default and use the same Finder /
  // shell-open fallback unconditionally.
  MacosDmgInstaller? installer;
  if (Platform.isMacOS) {
    installer = (dmgPath) async {
      // `Platform.resolvedExecutable` points at
      // `<bundle>/Contents/MacOS/letsflutssh`; the Rust shim
      // walks up to the `.app` root (atomic-swap target) inside
      // `bundle_root_from_macos_executable`.
      final outcome = await rust_macos_installer.macosInstallerInstall(
        dmgPath: dmgPath,
        executablePath: Platform.resolvedExecutable,
      );
      return outcome == rust_macos_installer.MacosInstallOutcome.succeeded;
    };
  }
  // Detect how a Linux build was installed (AppImage / Flatpak / system
  // package / portable) here in app context — FRB is live by now — and
  // hand it to the service as a value, so the core layer never calls
  // FRB from a constructor. `null` off Linux.
  final rust_update_meta.DbLinuxInstall? linuxInstall = Platform.isLinux
      ? rust_update_meta.updateLinuxInstallMethod()
      : null;
  // On Android, wire the apk install hand-off (system package
  // installer). Other platforms get null and use their own apply path.
  final AndroidApkInstaller? androidApkInstaller = Platform.isAndroid
      ? ApkInstaller.install
      : null;
  return UpdateService(
    macosDmgInstaller: installer,
    linuxInstall: linuxInstall,
    androidApkInstaller: androidApkInstaller,
  );
});

/// Provider that manages the update check / download lifecycle.
final updateProvider = NotifierProvider<UpdateNotifier, UpdateState>(
  UpdateNotifier.new,
);

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
      AppLogger.instance.log(
        'Update check failed: $e',
        name: 'UpdateProvider',
        error: e,
      );
      state = UpdateState(status: UpdateStatus.error, error: e.toString());
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
    if (state.status == UpdateStatus.downloading ||
        state.status == UpdateStatus.verifying) {
      return;
    }

    state = state.copyWith(status: UpdateStatus.downloading, progress: 0);
    try {
      final dir = await getApplicationSupportDirectory();
      await _cleanupStaleDownloads(info.assetUrl!);
      var lastReportedPercent = -1;
      final path = await _service.downloadAsset(
        info.assetUrl!,
        dir.path,
        expectedDigest: info.assetDigest,
        onProgress: (received, total) {
          if (total > 0) {
            final percent = (received * 100 ~/ total);
            if (percent != lastReportedPercent) {
              lastReportedPercent = percent;
              state = state.copyWith(progress: received / total);
            }
          }
        },
        onPhase: (phase) {
          if (phase == UpdateDownloadPhase.verifying) {
            state = state.copyWith(status: UpdateStatus.verifying, progress: 1);
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
      AppLogger.instance.log(
        'Download failed: $e',
        name: 'UpdateProvider',
        error: e,
      );
      state = state.copyWith(status: UpdateStatus.error, error: e);
    }
  }

  /// True when the current platform can launch a native installer from
  /// a downloaded artefact. UI uses this to pick between "Install Now"
  /// and "Open Release Page" before the user clicks.
  bool get canLaunchInstaller => _service.canLaunchInstaller;

  /// True when this Linux build is owned by a system package manager or
  /// Flatpak — the in-app updater defers to that manager. UI surfaces a
  /// "managed by your package manager" note instead of an install
  /// button. Always false off Linux.
  bool get isPackageManaged => _service.isPackageManaged;

  /// Open the downloaded installer file. Returns false if the platform
  /// has no launcher wired up or if the launcher call failed; callers
  /// should then fall back to [openReleasePage].
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

  /// Open the GitHub release page in the system browser. Used both as a
  /// deliberate action on platforms without an in-app installer
  /// (`canLaunchInstaller == false`) and as a runtime fallback when
  /// [install] returns false on a supposedly-supported platform.
  Future<bool> openReleasePage() async {
    final url = state.info?.releaseUrl;
    if (url == null || url.isEmpty) return false;
    try {
      final uri = Uri.parse(url);
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      AppLogger.instance.log(
        'Failed to open release page',
        name: 'UpdateProvider',
        error: e,
      );
      return false;
    }
  }

  /// Delete previously downloaded update files in the pinned support
  /// dir before starting a fresh download. Matches any file whose name
  /// ends with the same suffix as the incoming [assetUrl] (e.g.
  /// `-windows-x64-setup.exe`). The scan root resolves Rust-side
  /// through the support-dir singleton — Dart no longer hands a path.
  Future<void> _cleanupStaleDownloads(String assetUrl) async {
    try {
      final removed = await rust_update.updateCleanupStaleDownloads(
        assetUrl: assetUrl,
      );
      if (removed > 0) {
        AppLogger.instance.log(
          'Removed $removed stale download(s)',
          name: 'UpdateProvider',
        );
      }
    } catch (e) {
      AppLogger.instance.log(
        'Stale download cleanup error: $e',
        name: 'UpdateProvider',
        level: LogLevel.warn,
      );
    }
  }

  Future<void> _cleanupFile(String path) async {
    try {
      await rust_update.updateCleanupFile(path: path);
    } catch (e) {
      AppLogger.instance.log(
        'Cleanup failed: $e',
        name: 'UpdateProvider',
        level: LogLevel.warn,
      );
    }
  }
}
