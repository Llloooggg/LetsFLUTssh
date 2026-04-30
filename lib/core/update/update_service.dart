import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../src/rust/api/bus.dart' as rust_bus;
import '../../src/rust/api/crypto.dart' as rust_crypto;
import '../../src/rust/api/update_http.dart' as rust_update_http;
import '../../src/rust/api/update_metadata.dart' as rust_update;
import '../../src/rust/api/update_signing.dart' as rust_update_signing;
import '../../utils/logger.dart';
import '../bus/app_bus.dart';

/// Callback shape for the optional native macOS `.dmg` installer. Kept
/// as a typedef at the core layer so `UpdateService` can invoke the
/// installer without importing `lib/platform/macos/` — the UI wiring
/// point (main.dart / update_provider) adapts the concrete
/// `MacosInstaller` into this callback.
///
/// Returns `true` when the installer has fully swapped the bundle and
/// relaunched; `false` to request a fallback to the legacy
/// `open <dmg>` Finder reveal (e.g. bundle parent isn't writable).
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

/// Callback type for downloading a file with progress reporting.
typedef FileDownloader =
    Future<void> Function(
      Uri url,
      String savePath,
      void Function(int received, int total)? onProgress,
    );

/// Phases a [UpdateService.downloadAsset] call walks through after
/// the HTTP download completes. Separating [verifying] from the HTTP
/// phase lets the UI swap "Downloading 100%" for an indeterminate
/// "Verifying…" caption while SHA256 hashing and the manifest +
/// signature fetch + Ed25519 check run — those steps can take tens
/// of seconds on a 50 MB installer and the old state reported
/// "Downloading 100%" the whole time, reading as a freeze to users.
enum UpdateDownloadPhase {
  /// HTTP bytes still streaming; [UpdateService] emits `onProgress`
  /// ticks. The UI shows a determinate progress bar.
  downloading,

  /// Bytes are on disk; SHA256 verification, manifest fetch and
  /// Ed25519 signature checks are in flight. No progress ticks —
  /// the UI should render an indeterminate bar.
  verifying,
}

/// Callback type for running a process — injectable for testing.
typedef ProcessRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);

/// Callback that verifies a downloaded artefact end-to-end. Production
/// fetches the release's `.sha256sums` + `.sha256sums.sig` pair,
/// verifies the manifest signature against the pinned pubkeys, then
/// checks that the downloaded artefact's sha256 matches the
/// corresponding line in the manifest.
///
/// Tests inject a no-op or a rejector to exercise the download path
/// without generating real signatures per test.
///
/// The callback owns the manifest + signature file lifecycle (download,
/// parse, delete on failure). It must throw
/// [InvalidReleaseSignatureException] on failure so the caller can
/// distinguish crypto-layer failures from generic network errors.
typedef ReleaseArtifactVerifier =
    Future<void> Function({
      required Uri assetUri,
      required String assetPath,
      required String targetDir,
      required FileDownloader download,
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
  final FileDownloader _download;
  final ProcessRunner _runProcess;
  final ReleaseArtifactVerifier _verifyArtifact;
  final MacosDmgInstaller? _macosDmgInstaller;

  /// Platform identifier used by [openFile] to pick the host-specific opener.
  /// Injected so tests can exercise every branch (linux / macos / windows /
  /// unsupported) without mocking `dart:io` `Platform`.
  final String _platform;

  UpdateService({
    HttpFetcher? fetch,
    FileDownloader? download,
    ProcessRunner? runProcess,
    ReleaseArtifactVerifier? verifyArtifact,
    String? platform,
    MacosDmgInstaller? macosDmgInstaller,
  }) : _fetch = fetch ?? defaultFetch,
       _download = download ?? defaultDownload,
       _runProcess = runProcess ?? Process.run,
       _verifyArtifact = verifyArtifact ?? _defaultVerifyArtifact,
       _platform = platform ?? _hostPlatform(),
       _macosDmgInstaller = macosDmgInstaller;

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
  /// Two independent integrity checks run against the downloaded file:
  ///
  ///   * **Manifest signature** — the release's `.sha256sums`
  ///     manifest is fetched along with its single `.sha256sums.sig`.
  ///     The signature is verified against the pubkeys pinned in
  ///     `lfs_core::update_signing::verify_release_signature`; the
  ///     artefact's own sha256 must then match
  ///     its line in the manifest. This is the authoritative defence
  ///     against GitHub response tampering — a MITM would need to forge
  ///     an Ed25519 signature under the embedded public key to slip
  ///     past.
  ///   * **SHA-256 digest from the release JSON** — secondary,
  ///     belt-and-suspenders. Catches disk corruption and the easy
  ///     "attacker replaced only the binary but not the manifest" case
  ///     before the manifest signature pass.
  ///
  /// Either failure deletes the download and throws. No manifest /
  /// signature → fail-closed (fresh releases MUST ship both).
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
    if (identical(_download, defaultDownload) &&
        identical(_verifyArtifact, _defaultVerifyArtifact)) {
      return _downloadAssetViaRust(
        url: url,
        targetDir: targetDir,
        expectedDigest: expectedDigest,
        onProgress: onProgress,
        onPhase: onPhase,
      );
    }
    return _downloadAssetDart(
      uri: uri,
      targetDir: targetDir,
      expectedDigest: expectedDigest,
      onProgress: onProgress,
      onPhase: onPhase,
    );
  }

  Future<String> _downloadAssetViaRust({
    required String url,
    required String targetDir,
    required String? expectedDigest,
    required void Function(int received, int total)? onProgress,
    required void Function(UpdateDownloadPhase phase)? onPhase,
  }) async {
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
      final result = await rust_update_http.updateDownloadWithVerification(
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

  Future<String> _downloadAssetDart({
    required Uri uri,
    required String targetDir,
    required String? expectedDigest,
    required void Function(int received, int total)? onProgress,
    required void Function(UpdateDownloadPhase phase)? onPhase,
  }) async {
    final fileName = uri.pathSegments.last;
    final savePath = p.join(targetDir, fileName);
    await _download(uri, savePath, onProgress);

    // HTTP bytes are on disk. The rest (SHA256, manifest + signature
    // fetch, Ed25519 verification) is post-download work the UI should
    // not represent as "Downloading 100%".
    onPhase?.call(UpdateDownloadPhase.verifying);

    if (expectedDigest != null) {
      AppLogger.instance.log('Verifying SHA256...', name: 'UpdateService');
      final actual = await computeFileSha256(savePath);
      if (actual != expectedDigest) {
        await _deleteQuietly(savePath);
        throw StateError(
          'SHA256 mismatch: expected $expectedDigest, got $actual',
        );
      }
      AppLogger.instance.log('SHA256 verified', name: 'UpdateService');
    }

    try {
      await _verifyArtifact(
        assetUri: uri,
        assetPath: savePath,
        targetDir: targetDir,
        download: _download,
      );
    } catch (_) {
      await _deleteQuietly(savePath);
      rethrow;
    }

    AppLogger.instance.log('Downloaded to $savePath', name: 'UpdateService');
    return savePath;
  }

  Future<void> _deleteQuietly(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (e) {
      AppLogger.instance.log(
        'Failed to delete $path: $e',
        name: 'UpdateService',
      );
    }
  }

  /// Default [ReleaseArtifactVerifier]: download the release's
  /// `.sha256sums` manifest + its single `.sha256sums.sig`, verify the
  /// signature against the pinned pubkeys, and confirm that this
  /// artefact's sha256 matches the hash the manifest pins it to.
  ///
  /// Both files are left on disk next to the binary on success so the
  /// installer step (or a curious user) can re-verify offline. On any
  /// failure they are cleaned up and an [InvalidReleaseSignatureException]
  /// is thrown.
  static Future<void> _defaultVerifyArtifact({
    required Uri assetUri,
    required String assetPath,
    required String targetDir,
    required FileDownloader download,
  }) async {
    // Parse the version out of the asset filename. Release assets are
    // always named `letsflutssh-<version>-<platform>...`; the manifest
    // is `letsflutssh-<version>.sha256sums`, published in the same
    // release directory.
    final assetName = p.basename(assetPath);
    final version = _parseAssetVersion(assetName);
    if (version == null) {
      throw InvalidReleaseSignatureException(
        'Cannot derive version from asset name: $assetName',
      );
    }

    final manifestName = 'letsflutssh-$version.sha256sums';
    final assetDir = p.posix.dirname(assetUri.path);
    final manifestUri = assetUri.replace(
      path: p.posix.join(assetDir, manifestName),
    );
    final manifestSigUri = manifestUri.replace(path: '${manifestUri.path}.sig');
    if (!isTrustedReleaseAssetUri(manifestUri) ||
        !isTrustedReleaseAssetUri(manifestSigUri)) {
      throw StateError(
        'Untrusted manifest URL pair: $manifestUri / $manifestSigUri',
      );
    }

    final manifestPath = p.join(targetDir, manifestName);
    final manifestSigPath = p.join(targetDir, '$manifestName.sig');

    AppLogger.instance.log(
      'Fetching release manifest + signature...',
      name: 'UpdateService',
    );
    try {
      await download(manifestUri, manifestPath, null);
      await download(manifestSigUri, manifestSigPath, null);
    } catch (e) {
      await _deleteFileQuietly(manifestPath);
      await _deleteFileQuietly(manifestSigPath);
      // Transient — network drop, 404 on a release still uploading,
      // DNS failure. Not a security event.
      throw ReleaseManifestUnavailableException(
        'Failed to fetch release manifest: $e',
      );
    }

    final Uint8List manifestBytes;
    final Uint8List sigBytes;
    try {
      manifestBytes = await File(manifestPath).readAsBytes();
      sigBytes = await File(manifestSigPath).readAsBytes();
    } catch (e) {
      await _deleteFileQuietly(manifestPath);
      await _deleteFileQuietly(manifestSigPath);
      // Transient — local IO error reading what we just wrote.
      throw ReleaseManifestUnavailableException(
        'Failed to read release manifest: $e',
      );
    }

    final sigOk = rust_update_signing.updateVerifyReleaseSignature(
      message: manifestBytes,
      signature: sigBytes,
    );
    if (!sigOk) {
      await _deleteFileQuietly(manifestPath);
      await _deleteFileQuietly(manifestSigPath);
      throw const InvalidReleaseSignatureException(
        'Manifest signature did not verify against the pinned public key',
      );
    }
    AppLogger.instance.log(
      'Manifest signature verified (Ed25519)',
      name: 'UpdateService',
    );

    // Signed manifest contract: find this asset's line, compare hashes.
    final manifest = parseSha256Manifest(utf8.decode(manifestBytes));
    final expectedHash = manifest[assetName];
    if (expectedHash == null) {
      await _deleteFileQuietly(manifestPath);
      await _deleteFileQuietly(manifestSigPath);
      throw InvalidReleaseSignatureException(
        'Manifest has no entry for $assetName — release is incomplete or '
        'the asset name has drifted from the manifest format',
      );
    }

    final actualHash = await computeFileSha256(assetPath);
    if (actualHash.toLowerCase() != expectedHash.toLowerCase()) {
      await _deleteFileQuietly(manifestPath);
      await _deleteFileQuietly(manifestSigPath);
      throw InvalidReleaseSignatureException(
        'SHA-256 mismatch for $assetName: manifest=$expectedHash '
        'actual=$actualHash',
      );
    }
    AppLogger.instance.log(
      'Artefact sha256 matches manifest entry',
      name: 'UpdateService',
    );
  }

  /// Extract the semver version from a release asset filename.
  ///
  /// Routes through `lfs_core::update_metadata::parse_asset_version`.
  /// Returns the captured version (e.g. `5.9.0`) or null when the name
  /// does not match the `letsflutssh-<version>-...` pattern.
  static String? _parseAssetVersion(String assetName) {
    try {
      return rust_update.updateParseAssetVersion(assetName: assetName);
    } catch (_) {
      final match = RegExp(
        r'^letsflutssh-([0-9]+\.[0-9]+\.[0-9]+)-',
      ).firstMatch(assetName);
      return match?.group(1);
    }
  }

  @visibleForTesting
  static String? parseAssetVersion(String assetName) =>
      _parseAssetVersion(assetName);

  /// Parse a `sha256sum`-format manifest into a `{name: hash}` map.
  ///
  /// Accepts both text mode (`<hash>  <name>`) and binary mode
  /// (`<hash> *<name>`). Blank lines and lines starting with `#` are
  /// ignored so the format stays forward-compatible with comments.
  ///
  /// Visible for testing — called by [_defaultVerifyArtifact] but also
  /// exercised directly by unit tests without the rest of the
  /// update-service plumbing.
  @visibleForTesting
  static Map<String, String> parseSha256Manifest(String content) {
    try {
      final entries = rust_update.updateParseSha256Manifest(content: content);
      return {for (final e in entries) e.name: e.hash};
    } catch (_) {
      return _parseSha256ManifestDart(content);
    }
  }

  static Map<String, String> _parseSha256ManifestDart(String content) {
    final result = <String, String>{};
    for (final rawLine in LineSplitter.split(content)) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final spaceIdx = line.indexOf(RegExp(r'\s'));
      if (spaceIdx <= 0) continue;
      final hash = line.substring(0, spaceIdx);
      var name = line.substring(spaceIdx).trimLeft();
      if (name.startsWith('*')) name = name.substring(1);
      if (hash.length != 64 || name.isEmpty) continue;
      result[name] = hash;
    }
    return result;
  }

  static Future<void> _deleteFileQuietly(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {
      /* best-effort */
    }
  }

  /// Test helper: a [ReleaseArtifactVerifier] that never fails. Use in
  /// tests that exercise the download path without caring about
  /// signatures.
  @visibleForTesting
  static Future<void> skipSignatureVerification({
    required Uri assetUri,
    required String assetPath,
    required String targetDir,
    required FileDownloader download,
  }) async {
    return;
  }

  /// Compute SHA256 hex digest of a file via
  /// `lfs_core::crypto::sha256_hex`.
  static Future<String> computeFileSha256(String path) async {
    final bytes = await File(path).readAsBytes();
    return rust_crypto.cryptoSha256Hex(bytes: bytes);
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

  /// Characters that must not appear in file paths passed to `cmd /c start`.
  static final _unsafePathChars = RegExp(r'[&|<>^%]');

  /// Platforms where the app can launch a platform-native installer for
  /// a downloaded artefact (AppImage / .exe / .dmg via `xdg-open` / `cmd
  /// start` / `open`). Anything outside this set must fall back to
  /// opening the GitHub release page in a browser instead.
  ///
  /// Android is intentionally NOT listed — the APK install flow requires
  /// REQUEST_INSTALL_PACKAGES + FileProvider + per-app system prompt
  /// that needs a separate implementation; until that lands, Android
  /// uses the browser-fallback path like iOS.
  static const _platformsWithInstaller = {'linux', 'macos', 'windows'};

  /// True when [openFile] can be expected to launch a native installer
  /// flow on the host platform. UI code uses this to pick the right
  /// button label ("Install Now" vs "Open Release Page") before the
  /// user clicks — so the label always matches the action.
  bool get canLaunchInstaller => _platformsWithInstaller.contains(_platform);

  /// Open a downloaded file using the platform's default handler.
  Future<bool> openFile(String path) async {
    ProcessResult result;
    if (_platform == 'linux') {
      AppLogger.instance.log(
        'Opening file with xdg-open: $path',
        name: 'UpdateService',
      );
      result = await _runProcess('xdg-open', [path]);
    } else if (_platform == 'macos') {
      // When a `MacosDmgInstaller` is wired in and the artefact is a
      // `.dmg`, try the native atomic-swap install first (hdiutil →
      // rsync → re-sign → verify → atomic rename). On a `true` return
      // the installer has already relaunched the new bundle; on
      // `false` we fall back to the legacy `open <dmg>` Finder reveal
      // so the user can still drag the .app manually if the silent
      // path is unavailable (no write permission on the install
      // parent, missing `rsync` binary, etc.). Layer-clean: the
      // callback lives at the UI wiring point; core/update doesn't
      // import from `lib/platform/`.
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
      AppLogger.instance.log(
        'Opening file with open: $path',
        name: 'UpdateService',
      );
      result = await _runProcess('open', [path]);
    } else if (_platform == 'windows') {
      if (_unsafePathChars.hasMatch(path)) {
        AppLogger.instance.log(
          'Refusing to open path with unsafe characters: $path',
          name: 'UpdateService',
        );
        return false;
      }
      AppLogger.instance.log(
        'Opening file with cmd /c start: $path',
        name: 'UpdateService',
      );
      result = await _runProcess('cmd', ['/c', 'start', '', path]);
    } else {
      AppLogger.instance.log(
        'Cannot open file: unsupported platform',
        name: 'UpdateService',
      );
      return false;
    }
    return result.exitCode == 0;
  }

  // ---------------------------------------------------------------------------
  // Default HTTP implementations (dart:io)
  // ---------------------------------------------------------------------------

  /// Fetch a UTF-8 body via `lfs_core::update_http::fetch_text`.
  /// The Rust client uses rustls + system CAs and gates requests +
  /// redirects through the trusted-host allowlist; SPKI pinning,
  /// when re-introduced, lands as a custom
  /// `rustls::ServerCertVerifier` in the same crate.
  static Future<String> defaultFetch(Uri url) =>
      rust_update_http.updateFetchText(url: url.toString());

  /// Download a release asset via
  /// `lfs_core::update_http::download_to_file`. Per-chunk progress
  /// is published onto the bus as `BusEvent::UpdateDownloadProgress`;
  /// subscribe to the `Update` topic for the duration of this
  /// download and forward ticks to [onProgress] so the UI's
  /// determinate progress bar keeps moving. Ed25519 manifest
  /// verification still runs Dart-side via `_defaultVerifyArtifact`
  /// after the download lands.
  ///
  /// The URL trust check (host allowlist + redirect-target gate)
  /// runs Rust-side too — the Dart pre-check below is defence in
  /// depth that lets the wrapper fail fast without opening an HTTP
  /// client.
  static Future<void> defaultDownload(
    Uri url,
    String savePath,
    void Function(int received, int total)? onProgress,
  ) async {
    if (!isTrustedReleaseAssetUri(url)) {
      throw StateError('Untrusted update download URL: $url');
    }
    final urlString = url.toString();
    StreamSubscription<rust_bus.BusEvent>? sub;
    try {
      if (onProgress != null) {
        sub = AppBus.instance.subscribe(rust_bus.BusTopic.update).listen((
          event,
        ) {
          if (event is rust_bus.BusEvent_UpdateDownloadProgress &&
              event.url == urlString) {
            onProgress(
              event.writtenBytes.toInt(),
              event.totalBytes?.toInt() ?? 0,
            );
          }
        });
      }
      await rust_update_http.updateDownloadToFile(
        url: urlString,
        targetPath: savePath,
      );
    } finally {
      await sub?.cancel();
    }
  }
}
