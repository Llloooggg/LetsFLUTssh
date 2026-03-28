import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../utils/logger.dart';

/// Result of a version check against GitHub releases.
class UpdateInfo {
  final String latestVersion;
  final String currentVersion;
  final String releaseUrl;
  final String? assetUrl;
  final String? changelog;

  const UpdateInfo({
    required this.latestVersion,
    required this.currentVersion,
    required this.releaseUrl,
    this.assetUrl,
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
          changelog == other.changelog;

  @override
  int get hashCode =>
      Object.hash(latestVersion, currentVersion, releaseUrl, assetUrl, changelog);
}

/// Callback type for fetching a URL body as a string.
typedef HttpFetcher = Future<String> Function(Uri url);

/// Callback type for downloading a file with progress reporting.
typedef FileDownloader = Future<void> Function(
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
    'https://api.github.com/repos/$repo/releases/latest',
  );

  final HttpFetcher _fetch;
  final FileDownloader _download;

  UpdateService({HttpFetcher? fetch, FileDownloader? download})
      : _fetch = fetch ?? defaultFetch,
        _download = download ?? defaultDownload;

  /// Query GitHub for the latest release and compare with [currentVersion].
  Future<UpdateInfo> checkForUpdate(String currentVersion) async {
    AppLogger.instance.log('Checking for updates...', name: 'UpdateService');
    final body = await _fetch(apiUri);
    final json = jsonDecode(body) as Map<String, dynamic>;

    final tagName = json['tag_name'] as String? ?? '';
    final version = tagName.startsWith('v') ? tagName.substring(1) : tagName;
    final releaseUrl = json['html_url'] as String? ??
        'https://github.com/$repo/releases/latest';
    final changelog = json['body'] as String?;
    final assets = json['assets'] as List<dynamic>? ?? [];

    final assetUrl = assetUrlForPlatform(assets);

    final info = UpdateInfo(
      latestVersion: version,
      currentVersion: currentVersion,
      releaseUrl: releaseUrl,
      assetUrl: assetUrl,
      changelog: changelog,
    );

    AppLogger.instance.log(
      'Update check: current=$currentVersion, latest=$version, hasUpdate=${info.hasUpdate}',
      name: 'UpdateService',
    );
    return info;
  }

  /// Download the asset at [url] into [targetDir], returning the saved path.
  Future<String> downloadAsset(
    String url,
    String targetDir, {
    void Function(int received, int total)? onProgress,
  }) async {
    final uri = Uri.parse(url);
    final fileName = uri.pathSegments.last;
    final savePath = p.join(targetDir, fileName);
    AppLogger.instance.log('Downloading $fileName...', name: 'UpdateService');
    await _download(uri, savePath, onProgress);
    AppLogger.instance.log('Downloaded to $savePath', name: 'UpdateService');
    return savePath;
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
  static Future<bool> openFile(String path) async {
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
    final client = HttpClient();
    try {
      final request = await client.getUrl(url);
      request.headers.set('User-Agent', 'LetsFLUTssh-UpdateChecker');
      final response = await request.close();

      // Follow redirects (GitHub asset URLs redirect to CDN)
      if (response.statusCode >= 300 && response.statusCode < 400) {
        final location = response.headers.value('location');
        if (location != null) {
          await response.drain<void>();
          client.close();
          return defaultDownload(Uri.parse(location), savePath, onProgress);
        }
      }

      if (response.statusCode != 200) {
        throw HttpException(
          'Download failed with status ${response.statusCode}',
          uri: url,
        );
      }

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
    } finally {
      client.close();
    }
  }
}
