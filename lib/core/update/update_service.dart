import 'dart:async';
import 'dart:io';

import 'package:meta/meta.dart' show visibleForTesting;

import '../../src/rust/api/bus.dart' as rust_bus;
import '../../src/rust/api/installer.dart' as rust_installer;
import '../../src/rust/api/update_http.dart' as rust_update_http;
import '../../src/rust/api/update_metadata.dart' as rust_update;
import '../../utils/logger.dart';
import '../bus/app_bus.dart';

/// Callback shape for the optional native macOS `.dmg` installer.
/// Kept as a typedef at the core layer so `UpdateService` can
/// invoke the installer without importing `lib/platform/macos/` —
/// the UI wiring point (main.dart / update_provider) adapts the
/// FRB call `rust_macos_installer.macosInstallerInstall` into
/// this callback.
///
/// Returns `true` when the installer has fully swapped the bundle
/// and relaunched; `false` to request a fallback to the
/// `open <dmg>` Finder reveal so the user can still drag the
/// `.app` over manually (e.g. when the bundle parent isn't
/// writable, or `rsync` isn't on PATH).
typedef MacosDmgInstaller = Future<bool> Function(String dmgPath);

/// Thrown when a downloaded release artefact fails Ed25519 signature
/// verification against the pinned public keys, OR when the signed
/// manifest does not cover the downloaded asset, OR when the asset's
/// sha256 does not match the manifest entry. Covers only real
/// security events — the UI surfaces the "do not install, reinstall
/// from official releases" warning for this class specifically.
///
/// Transient fetch failures (network drop, 404 on a release still
/// being uploaded, file-read IO error) are reported through
/// [ReleaseManifestUnavailableException] instead, so the UI can
/// offer a retry rather than a tampering warning.
class InvalidReleaseSignatureException implements Exception {
  final String reason;
  const InvalidReleaseSignatureException(this.reason);

  @override
  String toString() => 'InvalidReleaseSignatureException: $reason';
}

/// Thrown when the signed release manifest cannot be fetched or read
/// for any reason that is not a security event — network timeout,
/// HTTP 404 on a release still being uploaded, DNS failure, IO error
/// while reading a partial download. The UI surfaces a plain "could
/// not reach release manifest, try again later" message for this
/// class; it is not a tampering signal.
class ReleaseManifestUnavailableException implements Exception {
  final String reason;
  const ReleaseManifestUnavailableException(this.reason);

  @override
  String toString() => 'ReleaseManifestUnavailableException: $reason';
}

/// Result of a version check against GitHub releases.
class UpdateInfo {
  final String latestVersion;
  final String currentVersion;
  final String releaseUrl;
  final String? assetUrl;
  final String? assetDigest;
  final String? changelog;

  const UpdateInfo({
    required this.latestVersion,
    required this.currentVersion,
    required this.releaseUrl,
    this.assetUrl,
    this.assetDigest,
    this.changelog,
  });

  /// True when the remote version is strictly newer.
  bool get hasUpdate => compareVersions(latestVersion, currentVersion) > 0;

  /// Compare two semver strings via
  /// `lfs_core::update_metadata::compare_versions` — returns positive
  /// if [a] > [b].
  static int compareVersions(String a, String b) {
    final ord = rust_update.updateCompareVersions(a: a, b: b);
    return switch (ord) {
      rust_update.DbVersionOrder.less => -1,
      rust_update.DbVersionOrder.equal => 0,
      rust_update.DbVersionOrder.greater => 1,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UpdateInfo &&
          latestVersion == other.latestVersion &&
          currentVersion == other.currentVersion &&
          releaseUrl == other.releaseUrl &&
          assetUrl == other.assetUrl &&
          assetDigest == other.assetDigest &&
          changelog == other.changelog;

  @override
  int get hashCode => Object.hash(
    latestVersion,
    currentVersion,
    releaseUrl,
    assetUrl,
    assetDigest,
    changelog,
  );
}

/// Callback type for fetching a URL body as a string.
typedef HttpFetcher = Future<String> Function(Uri url);

/// Phases a [UpdateService.downloadAsset] call walks through after
/// the HTTP download completes. Separating [verifying] from the
/// HTTP phase lets the UI swap "Downloading 100%" for an
/// indeterminate "Verifying…" caption while SHA256 hashing + the
/// manifest fetch + Ed25519 check run — on a 50 MB installer
/// those steps take tens of seconds and a frozen "Downloading
/// 100%" caption reads as a hung process to the user.
enum UpdateDownloadPhase {
  /// HTTP bytes still streaming; [UpdateService] emits `onProgress`
  /// ticks. The UI shows a determinate progress bar.
  downloading,

  /// Bytes are on disk; SHA256 verification, manifest fetch and
  /// Ed25519 signature checks are in flight. No progress ticks —
  /// the UI should render an indeterminate bar.
  verifying,
}

/// Callback shape for the installer-launch hand-off — opens a
/// downloaded artefact under the host's default handler
/// (`xdg-open` on Linux, `/usr/bin/open` on macOS, `cmd /c start`
/// on Windows). Production wires this to the FRB shim
/// `rust_installer.openInstallerFile`, which routes through the
/// `lfs_os_security::installer_launch` perimeter so every
/// subprocess spawn that consumes a user-influenced path lives
/// in one audited crate. Tests inject a scripted
/// [rust_installer.InstallerLaunchOutcome] per case so the
/// branching in [UpdateService.openFile] is exercised without
/// touching a real subprocess — critical on WSL hosts where
/// `xdg-open` proxies through `wslu` to the Windows shell and
/// would surface a file-association dialog for any artefact
/// path that doesn't already have a Linux MIME handler.
typedef InstallerOpener =
    Future<rust_installer.InstallerLaunchOutcome> Function(
      String path,
      String platform,
    );

/// Signature for the FRB download+verify call routed through
/// [UpdateService.debugDownloadOverride]. Matches the named-parameter
/// shape of `rust_update_http.updateDownloadWithVerification` exactly
/// so tests can swap in a scripted [rust_update_http.DbDownloadResult]
/// per case without an FRB runtime.
typedef UpdateDownloader =
    Future<rust_update_http.DbDownloadResult> Function({
      required String url,
      required String targetDir,
      required String expectedDigest,
    });

/// Checks GitHub releases for updates and downloads assets.
///
/// HTTP operations are injected for testability — production code uses
/// the default [HttpClient]-based implementations.
class UpdateService {
  static const repo = 'Llloooggg/LetsFLUTssh';
  static final apiUri = Uri.parse(
    'https://api.github.com/repos/$repo/releases?per_page=30',
  );

  final HttpFetcher _fetch;
  final InstallerOpener _openInstaller;
  final MacosDmgInstaller? _macosDmgInstaller;

  /// Platform identifier used by [openFile] to pick the host-specific opener.
  /// Injected so tests can exercise every branch (linux / macos / windows /
  /// unsupported) without mocking `dart:io` `Platform`.
  final String _platform;

  /// How this Linux build was installed (AppImage / Flatpak / system
  /// package / portable). `null` off Linux and when the caller didn't
  /// supply it. The FRB detection (`updateLinuxInstallMethod`) is run
  /// by `updateServiceProvider` in app context and passed in here — the
  /// core layer never calls FRB from a constructor, so tests and
  /// non-Linux builds construct without an FRB runtime.
  final rust_update.DbLinuxInstall? _linuxInstall;

  UpdateService({
    HttpFetcher? fetch,
    InstallerOpener? openInstaller,
    String? platform,
    this._linuxInstall,
    this._macosDmgInstaller,
  }) : _fetch = fetch ?? defaultFetch,
       _openInstaller = openInstaller ?? _defaultOpenInstaller,
       _platform = platform ?? _hostPlatform();

  /// Default production binding for [InstallerOpener]: route the
  /// hand-off through the FRB shim so the subprocess plumbing
  /// (and the Windows allowlist) lives in
  /// `lfs_os_security::installer_launch`.
  static Future<rust_installer.InstallerLaunchOutcome> _defaultOpenInstaller(
    String path,
    String platform,
  ) => rust_installer.openInstallerFile(path: path, platform: platform);

  /// Test seam for the FRB download+verify call. Production never
  /// sets this — [downloadAsset] then routes through
  /// `rust_update_http.updateDownloadWithVerification` directly. Tests
  /// inject a closure that returns a scripted
  /// [rust_update_http.DbDownloadResult] per case (success path with
  /// [rust_update_http.DbDownloadedAsset] populated, or one of the
  /// [rust_update_http.DbDownloadErrorKind] failure shapes) so the
  /// Dart-side mapping to [InvalidReleaseSignatureException] /
  /// [ReleaseManifestUnavailableException] / [StateError] is exercised
  /// without an FRB runtime.
  ///
  /// Tests must clear this in `tearDown` so a stray override does not
  /// leak into the next case.
  @visibleForTesting
  static UpdateDownloader? debugDownloadOverride;

  /// True if [uri] uses HTTPS and a host GitHub uses for release assets
  /// (same-origin policy for [browser_download_url] and redirect targets).
  /// Routes through `lfs_core::update_metadata::is_trusted_release_asset_uri`.
  static bool isTrustedReleaseAssetUri(Uri uri) {
    try {
      return rust_update.updateIsTrustedReleaseAssetUri(uri: uri.toString());
    } catch (_) {
      if (uri.scheme != 'https') return false;
      final host = uri.host;
      if (host.isEmpty) return false;
      return host == 'github.com' || host.endsWith('.githubusercontent.com');
    }
  }

  /// Query GitHub for the latest release and compare with [currentVersion].
  ///
  /// The orchestration walk (asset suffix selection, JSON shape
  /// detection, changelog assembly) lives Rust-side in
  /// `lfs_core::update_orchestrator`. Production with the default
  /// fetcher delegates the HTTP fetch to Rust too; tests injecting a
  /// custom [HttpFetcher] keep the transport on the Dart side and
  /// hand the pre-fetched body to `update_check_from_body` so the
  /// same parser still runs.
  Future<UpdateInfo> checkForUpdate(String currentVersion) async {
    AppLogger.instance.log('Checking for updates...', name: 'UpdateService');
    final rust_update_http.DbUpdateInfo result;
    if (identical(_fetch, defaultFetch)) {
      result = await rust_update_http.updateCheck(
        currentVersion: currentVersion,
        repo: repo,
      );
    } else {
      final body = await _fetch(apiUri);
      try {
        result = await rust_update_http.updateCheckFromBody(
          body: body,
          currentVersion: currentVersion,
          repo: repo,
        );
      } catch (e) {
        // Rust surfaces JSON parse failures as
        // `io: update releases JSON parse: …`. Reshape to the
        // FormatException callers expect — the parse-error contract
        // is part of the Dart-facing surface and tests assert on it.
        final msg = e.toString();
        if (msg.contains('update releases JSON parse')) {
          throw FormatException(msg);
        }
        rethrow;
      }
    }
    final info = UpdateInfo(
      latestVersion: result.latestVersion,
      currentVersion: result.currentVersion,
      releaseUrl: result.releaseUrl,
      assetUrl: result.assetUrl,
      assetDigest: result.assetDigest,
      changelog: result.changelog,
    );
    AppLogger.instance.log(
      'Update check: current=$currentVersion, '
      'latest=${info.latestVersion}, hasUpdate=${info.hasUpdate}',
      name: 'UpdateService',
    );
    return info;
  }

  /// Download the asset at [url] into [targetDir], returning the saved path.
  ///
  /// The entire download + verify pipeline runs Rust-side in
  /// `lfs_core::update_http::download_with_verification`:
  ///
  ///   * Streams the HTTP body straight to disk while hashing each
  ///     chunk; bytes never sit in a Dart heap buffer (the previous
  ///     Dart shape called `readAsBytes()` on the finished file, an
  ///     OOM trap on multi-hundred-megabyte installers).
  ///   * **SHA-256 from the Releases JSON** — secondary,
  ///     belt-and-suspenders. Catches disk corruption and the easy
  ///     "attacker replaced only the binary but not the manifest"
  ///     case before the manifest-signature pass.
  ///   * **Manifest signature** — fetches `letsflutssh-<version>.sha256sums`
  ///     and its single `.sha256sums.sig`, verifies the signature
  ///     against the pubkey pinned in
  ///     `lfs_core::update_signing::verify_release_signature`, then
  ///     confirms the artefact's sha256 matches its manifest entry.
  ///     A MITM would need to forge an Ed25519 signature under the
  ///     embedded public key to slip past.
  ///
  /// Any failure deletes the partial download and throws. No manifest
  /// / signature → fail-closed (fresh releases MUST ship both). The
  /// failure shape maps from [rust_update_http.DbDownloadErrorKind] to
  /// the Dart-facing exception classes so the UI can pick the right
  /// toast (security warning vs retry).
  Future<String> downloadAsset(
    String url,
    String targetDir, {
    String? expectedDigest,
    void Function(int received, int total)? onProgress,
    void Function(UpdateDownloadPhase phase)? onPhase,
  }) async {
    final uri = Uri.parse(url);
    if (!isTrustedReleaseAssetUri(uri)) {
      throw StateError('Untrusted update download URL: $uri');
    }
    AppLogger.instance.log(
      'Downloading ${uri.pathSegments.last}...',
      name: 'UpdateService',
    );
    onPhase?.call(UpdateDownloadPhase.downloading);
    StreamSubscription<rust_bus.BusEvent>? sub;
    if (onProgress != null || onPhase != null) {
      sub = AppBus.instance.subscribe(rust_bus.BusTopic.update).listen((event) {
        switch (event) {
          case rust_bus.BusEvent_UpdateDownloadProgress(
                :final url,
                :final writtenBytes,
                :final totalBytes,
              )
              when url == url:
            onProgress?.call(writtenBytes.toInt(), totalBytes?.toInt() ?? 0);
          case rust_bus.BusEvent_UpdateVerifyingStarted():
            onPhase?.call(UpdateDownloadPhase.verifying);
          case _:
            break;
        }
      });
    }
    try {
      final downloader =
          debugDownloadOverride ??
          rust_update_http.updateDownloadWithVerification;
      final result = await downloader(
        url: url,
        targetDir: targetDir,
        expectedDigest: expectedDigest ?? '',
      );
      final asset = result.asset;
      if (asset != null) {
        AppLogger.instance.log(
          'Downloaded to ${asset.assetPath}',
          name: 'UpdateService',
        );
        return asset.assetPath;
      }
      final detail = result.errorDetail ?? 'unknown';
      switch (result.errorKind) {
        case rust_update_http.DbDownloadErrorKind.invalidSignature:
          throw InvalidReleaseSignatureException(detail);
        case rust_update_http.DbDownloadErrorKind.manifestUnavailable:
          throw ReleaseManifestUnavailableException(detail);
        case rust_update_http.DbDownloadErrorKind.untrusted:
          throw StateError('Untrusted update download URL: $detail');
        case rust_update_http.DbDownloadErrorKind.network:
          throw StateError('Update download failed: $detail');
        case null:
          throw StateError('Update download failed without detail');
      }
    } finally {
      await sub?.cancel();
    }
  }

  /// Platforms we ship self-updatable binaries for. Anything else (iOS,
  /// fuchsia, …) maps to `'unknown'` so the Rust orchestrator's asset
  /// picker returns null instead of binding to a random suffix.
  static const _selfUpdatablePlatforms = {
    'linux',
    'windows',
    'macos',
    'android',
  };

  static String _hostPlatform() {
    final os = Platform.operatingSystem;
    return _selfUpdatablePlatforms.contains(os) ? os : 'unknown';
  }

  /// Desktop platforms with a single, unambiguous installer the app can
  /// launch from a downloaded artefact (`.exe` via `cmd start`, `.dmg`
  /// via the atomic-swap installer / `open`). Linux is handled
  /// separately in [canLaunchInstaller] because its apply path depends
  /// on the install method, not just the OS.
  ///
  /// Android is intentionally NOT listed — the APK install flow requires
  /// REQUEST_INSTALL_PACKAGES + FileProvider + per-app system prompt
  /// that needs a separate implementation; until that lands, Android
  /// uses the browser-fallback path like iOS.
  static const _platformsWithInstaller = {'macos', 'windows'};

  /// True when [openFile] can be expected to launch a native installer
  /// flow on the host platform. UI code uses this to pick the right
  /// button label ("Install Now" vs "Open Release Page") before the
  /// user clicks — so the label always matches the action.
  ///
  /// On Linux this is method-dependent: an AppImage or a portable
  /// (tar.gz) install can be applied in place, but a `deb` / `rpm` /
  /// pacman / Flatpak install is owned by its package manager — the
  /// in-app updater steps aside there and the UI offers the release
  /// page instead (see [isPackageManaged]).
  bool get canLaunchInstaller {
    if (_platform == 'linux') {
      return _linuxInstall == rust_update.DbLinuxInstall.appImage ||
          _linuxInstall == rust_update.DbLinuxInstall.portable;
    }
    return _platformsWithInstaller.contains(_platform);
  }

  /// True when the running Linux build is owned by a system package
  /// manager (`deb` / `rpm` / pacman) or Flatpak. The in-app updater
  /// defers update delivery to that manager, so the UI surfaces a
  /// "managed by your package manager" note instead of an install
  /// button. Always false off Linux.
  bool get isPackageManaged =>
      _platform == 'linux' &&
      (_linuxInstall == rust_update.DbLinuxInstall.systemPackage ||
          _linuxInstall == rust_update.DbLinuxInstall.flatpak);

  /// Open a downloaded file using the platform's default handler.
  ///
  /// The actual subprocess hand-off lives in
  /// `lfs_os_security::installer_launch` — every spawn that
  /// consumes a user-influenced path runs through the single
  /// audited perimeter crate. Here on the Dart side we only:
  ///
  /// 1. Try the native macOS atomic-swap installer first when
  ///    the artefact is a `.dmg` and a [MacosDmgInstaller] is
  ///    wired in. A `true` return means the new bundle is
  ///    already running; a `false` return signals "fall back to
  ///    the Finder-reveal path" and we continue to step 2.
  /// 2. Hand the path + platform string off through
  ///    [_openInstaller] and translate the typed
  ///    [rust_installer.InstallerLaunchOutcome] into the Dart
  ///    bool the UI surface expects (`true` only for
  ///    [rust_installer.InstallerLaunchOutcome_Launched]).
  Future<bool> openFile(String path) async {
    if (_platform == 'macos') {
      final installer = _macosDmgInstaller;
      if (installer != null && path.toLowerCase().endsWith('.dmg')) {
        AppLogger.instance.log(
          'Attempting native macOS DMG install for: $path',
          name: 'UpdateService',
        );
        final installed = await installer(path);
        if (installed) return true;
        AppLogger.instance.log(
          'Native DMG install declined — falling back to Finder reveal',
          name: 'UpdateService',
        );
      }
    }
    AppLogger.instance.log(
      'Opening file via installer-launch perimeter ($_platform): $path',
      name: 'UpdateService',
    );
    final outcome = await _openInstaller(path, _platform);
    switch (outcome) {
      case rust_installer.InstallerLaunchOutcome_Launched():
        return true;
      case rust_installer.InstallerLaunchOutcome_RefusedUnsafePath():
        AppLogger.instance.log(
          'Refusing to open path with unsafe characters: $path',
          name: 'UpdateService',
        );
        return false;
      case rust_installer.InstallerLaunchOutcome_UnsupportedPlatform():
        AppLogger.instance.log(
          'Cannot open file: unsupported platform',
          name: 'UpdateService',
        );
        return false;
      case rust_installer.InstallerLaunchOutcome_LaunchFailed(
        :final exitCode,
        :final stderr,
      ):
        AppLogger.instance.log(
          'Installer launch failed (exit=$exitCode, stderr=$stderr)',
          name: 'UpdateService',
          level: LogLevel.warn,
        );
        return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Default HTTP implementations
  // ---------------------------------------------------------------------------

  /// Fetch a UTF-8 body via `lfs_core::update_http::fetch_text`.
  /// The Rust client uses rustls + system CAs and gates requests +
  /// redirects through the trusted-host allowlist; SPKI pinning,
  /// when re-introduced, lands as a custom
  /// `rustls::ServerCertVerifier` in the same crate.
  static Future<String> defaultFetch(Uri url) =>
      rust_update_http.updateFetchText(url: url.toString());
}
