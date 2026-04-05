import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:pointycastle/digests/sha256.dart';

import '../../utils/logger.dart';

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

  /// Compare two semver strings. Returns positive if [a] > [b].
  static int compareVersions(String a, String b) {
    final pa = _parseVersion(a);
    final pb = _parseVersion(b);
    for (var i = 0; i < 3; i++) {
      final diff = pa[i] - pb[i];
      if (diff != 0) return diff;
    }
    return 0;
  }

  static List<int> _parseVersion(String v) {
    final cleaned = v.startsWith('v') ? v.substring(1) : v;
    final parts = cleaned.split('.');
    return List.generate(3, (i) {
      if (i < parts.length) return int.tryParse(parts[i]) ?? 0;
      return 0;
    });
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

  UpdateService({HttpFetcher? fetch, FileDownloader? download})
    : _fetch = fetch ?? defaultFetch,
      _download = download ?? defaultDownload;

  /// True if [uri] uses HTTPS and a host GitHub uses for release assets
  /// (same-origin policy for [browser_download_url] and redirect targets).
  static bool isTrustedReleaseAssetUri(Uri uri) {
    if (uri.scheme != 'https') return false;
    final host = uri.host;
    if (host.isEmpty) return false;
    return host == 'github.com' || host.endsWith('.githubusercontent.com');
  }

  /// Query GitHub for the latest release and compare with [currentVersion].
  ///
  /// Fetches all recent releases to build a cumulative changelog covering
  /// every version between [currentVersion] and the latest.
  Future<UpdateInfo> checkForUpdate(String currentVersion) async {
    AppLogger.instance.log('Checking for updates...', name: 'UpdateService');
    final body = await _fetch(apiUri);
    final releases = jsonDecode(body);

    // Support both array (releases list) and single object (legacy /latest)
    final List<dynamic> releaseList;
    if (releases is List) {
      releaseList = releases;
    } else if (releases is Map<String, dynamic>) {
      releaseList = [releases];
    } else {
      releaseList = [];
    }

    if (releaseList.isEmpty) {
      return UpdateInfo(
        latestVersion: currentVersion,
        currentVersion: currentVersion,
        releaseUrl: 'https://github.com/$repo/releases/latest',
      );
    }

    final latest = releaseList.first as Map<String, dynamic>;
    final tagName = latest['tag_name'] as String? ?? '';
    final version = tagName.startsWith('v') ? tagName.substring(1) : tagName;
    final releaseUrl =
        latest['html_url'] as String? ??
        'https://github.com/$repo/releases/latest';
    final assets = latest['assets'] as List<dynamic>? ?? [];

    final assetUrl = assetUrlForPlatform(assets);
    final assetDigest = digestForPlatform(assets);
    final changelog = buildCumulativeChangelog(releaseList, currentVersion);

    final info = UpdateInfo(
      latestVersion: version,
      currentVersion: currentVersion,
      releaseUrl: releaseUrl,
      assetUrl: assetUrl,
      assetDigest: assetDigest,
      changelog: changelog,
    );

    AppLogger.instance.log(
      'Update check: current=$currentVersion, latest=$version, hasUpdate=${info.hasUpdate}',
      name: 'UpdateService',
    );
    return info;
  }

  /// Build changelog from all releases between current version and latest.
  static String? buildCumulativeChangelog(
    List<dynamic> releases,
    String currentVersion,
  ) {
    final buf = StringBuffer();
    for (final release in releases) {
      if (release is! Map<String, dynamic>) continue;
      final tag = release['tag_name'] as String? ?? '';
      final ver = tag.startsWith('v') ? tag.substring(1) : tag;
      if (UpdateInfo.compareVersions(ver, currentVersion) <= 0) break;
      final body = release['body'] as String?;
      if (body != null && body.trim().isNotEmpty) {
        if (buf.isNotEmpty) buf.writeln();
        buf.writeln('## $tag');
        buf.writeln(body.trim());
      }
    }
    final result = buf.toString().trim();
    return result.isEmpty ? null : result;
  }

  /// Extract SHA256 digest for the platform-matching asset.
  static String? digestForPlatform(
    List<dynamic> assets, {
    String? platformOverride,
  }) {
    final platform = platformOverride ?? _currentPlatform();
    final suffix = _assetSuffix(platform);
    if (suffix == null) return null;
    for (final asset in assets) {
      if (asset is! Map<String, dynamic>) continue;
      final name = asset['name'] as String? ?? '';
      if (name.endsWith(suffix)) {
        final digest = asset['digest'] as String?;
        if (digest != null && digest.startsWith('sha256:')) {
          return digest.substring(7);
        }
        return null;
      }
    }
    return null;
  }

  /// Download the asset at [url] into [targetDir], returning the saved path.
  ///
  /// If [expectedDigest] is provided, verifies the SHA256 hash of the
  /// downloaded file and deletes it if verification fails.
  Future<String> downloadAsset(
    String url,
    String targetDir, {
    String? expectedDigest,
    void Function(int received, int total)? onProgress,
  }) async {
    final uri = Uri.parse(url);
    if (!isTrustedReleaseAssetUri(uri)) {
      throw StateError('Untrusted update download URL: $uri');
    }
    final fileName = uri.pathSegments.last;
    final savePath = p.join(targetDir, fileName);
    AppLogger.instance.log('Downloading $fileName...', name: 'UpdateService');
    await _download(uri, savePath, onProgress);

    if (expectedDigest != null) {
      AppLogger.instance.log('Verifying SHA256...', name: 'UpdateService');
      final actual = await computeFileSha256(savePath);
      if (actual != expectedDigest) {
        try {
          await File(savePath).delete();
        } catch (_) {}
        throw StateError(
          'SHA256 mismatch: expected $expectedDigest, got $actual',
        );
      }
      AppLogger.instance.log('SHA256 verified', name: 'UpdateService');
    }

    AppLogger.instance.log('Downloaded to $savePath', name: 'UpdateService');
    return savePath;
  }

  /// Compute SHA256 hex digest of a file.
  static Future<String> computeFileSha256(String path) async {
    final bytes = await File(path).readAsBytes();
    final hash = SHA256Digest().process(Uint8List.fromList(bytes));
    return hash.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Pick the right asset for the current platform from the release assets.
  static String? assetUrlForPlatform(
    List<dynamic> assets, {
    String? platformOverride,
  }) {
    final platform = platformOverride ?? _currentPlatform();
    final suffix = _assetSuffix(platform);
    if (suffix == null) return null;

    for (final asset in assets) {
      if (asset is! Map<String, dynamic>) continue;
      final name = asset['name'] as String? ?? '';
      if (name.endsWith(suffix)) {
        return asset['browser_download_url'] as String?;
      }
    }
    return null;
  }

  static String _currentPlatform() {
    if (Platform.isLinux) return 'linux';
    if (Platform.isWindows) return 'windows';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isAndroid) return 'android';
    return 'unknown';
  }

  /// Map platform to expected asset filename suffix.
  static String? _assetSuffix(String platform) {
    switch (platform) {
      case 'linux':
        return '-linux-x64.AppImage';
      case 'windows':
        return '-windows-x64-setup.exe';
      case 'macos':
        return '-macos-universal.dmg';
      case 'android':
        return '-android-arm64.apk';
      default:
        return null; // iOS — no self-update
    }
  }

  /// Open a downloaded file using the platform's default handler.
  Future<bool> openFile(String path) async {
    ProcessResult result;
    if (Platform.isLinux) {
      result = await Process.run('xdg-open', [path]);
    } else if (Platform.isMacOS) {
      result = await Process.run('open', [path]);
    } else if (Platform.isWindows) {
      result = await Process.run('cmd', ['/c', 'start', '', path]);
    } else {
      return false;
    }
    return result.exitCode == 0;
  }

  // ---------------------------------------------------------------------------
  // Default HTTP implementations (dart:io)
  // ---------------------------------------------------------------------------

  static Future<String> defaultFetch(Uri url) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(url);
      request.headers.set('Accept', 'application/vnd.github.v3+json');
      request.headers.set('User-Agent', 'LetsFLUTssh-UpdateChecker');
      final response = await request.close();
      if (response.statusCode != 200) {
        throw HttpException(
          'GitHub API returned ${response.statusCode}',
          uri: url,
        );
      }
      return await response.transform(utf8.decoder).join();
    } finally {
      client.close();
    }
  }

  static Future<void> defaultDownload(
    Uri url,
    String savePath,
    void Function(int received, int total)? onProgress,
  ) async {
    if (!isTrustedReleaseAssetUri(url)) {
      throw StateError('Untrusted update download URL: $url');
    }

    final client = HttpClient();
    try {
      var requestUri = url;
      while (true) {
        final request = await client.getUrl(requestUri);
        request.headers.set('User-Agent', 'LetsFLUTssh-UpdateChecker');
        final response = await request.close();

        final redirect = await _handleRedirect(requestUri, response);
        if (redirect != null) {
          requestUri = redirect;
          continue;
        }

        if (response.statusCode != 200) {
          throw HttpException(
            'Download failed with status ${response.statusCode}',
            uri: requestUri,
          );
        }

        await _writeToFile(response, savePath, onProgress);
        return;
      }
    } finally {
      client.close();
    }
  }

  static Future<Uri?> _handleRedirect(
    Uri requestUri,
    HttpClientResponse response,
  ) async {
    if (response.statusCode < 300 || response.statusCode >= 400) return null;
    final location = response.headers.value('location');
    if (location == null) return null;
    await response.drain<void>();
    final next = requestUri.resolve(location);
    if (!isTrustedReleaseAssetUri(next)) {
      throw StateError('Untrusted update download redirect: $next');
    }
    return next;
  }

  static Future<void> _writeToFile(
    HttpClientResponse response,
    String savePath,
    void Function(int received, int total)? onProgress,
  ) async {
    final total = response.contentLength;
    var received = 0;
    final file = File(savePath);
    await file.parent.create(recursive: true);
    final sink = file.openWrite();
    try {
      await for (final chunk in response) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
    } finally {
      await sink.close();
    }
  }
}
