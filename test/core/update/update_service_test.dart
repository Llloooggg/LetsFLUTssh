import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/update/update_service.dart';

/// Minimal GitHub release JSON for testing.
Map<String, dynamic> _releaseJson({
  String tagName = 'v2.0.0',
  String htmlUrl = 'https://github.com/Llloooggg/LetsFLUTssh/releases/tag/v2.0.0',
  String? body = 'Release notes here',
  List<Map<String, dynamic>>? assets,
}) {
  return {
    'tag_name': tagName,
    'html_url': htmlUrl,
    'body': body,
    'assets': assets ??
        [
          {
            'name': 'letsflutssh-2.0.0-linux-x64.AppImage',
            'browser_download_url':
                'https://github.com/download/letsflutssh-2.0.0-linux-x64.AppImage',
          },
          {
            'name': 'letsflutssh-2.0.0-windows-x64-setup.exe',
            'browser_download_url':
                'https://github.com/download/letsflutssh-2.0.0-windows-x64-setup.exe',
          },
          {
            'name': 'letsflutssh-2.0.0-macos-universal.dmg',
            'browser_download_url':
                'https://github.com/download/letsflutssh-2.0.0-macos-universal.dmg',
          },
          {
            'name': 'letsflutssh-2.0.0-android-arm64.apk',
            'browser_download_url':
                'https://github.com/download/letsflutssh-2.0.0-android-arm64.apk',
          },
        ],
  };
}

void main() {
  // ===========================================================================
  // UpdateInfo.compareVersions
  // ===========================================================================
  group('UpdateInfo.compareVersions', () {
    test('equal versions return 0', () {
      expect(UpdateInfo.compareVersions('1.0.0', '1.0.0'), 0);
    });

    test('newer major returns positive', () {
      expect(UpdateInfo.compareVersions('2.0.0', '1.0.0'), greaterThan(0));
    });

    test('older major returns negative', () {
      expect(UpdateInfo.compareVersions('1.0.0', '2.0.0'), lessThan(0));
    });

    test('newer minor returns positive', () {
      expect(UpdateInfo.compareVersions('1.2.0', '1.1.0'), greaterThan(0));
    });

    test('newer patch returns positive', () {
      expect(UpdateInfo.compareVersions('1.0.2', '1.0.1'), greaterThan(0));
    });

    test('strips v prefix', () {
      expect(UpdateInfo.compareVersions('v1.5.0', '1.5.0'), 0);
    });

    test('handles missing patch component', () {
      expect(UpdateInfo.compareVersions('1.5', '1.5.0'), 0);
    });

    test('handles single component', () {
      expect(UpdateInfo.compareVersions('2', '1.9.9'), greaterThan(0));
    });

    test('handles non-numeric gracefully', () {
      // non-numeric parts parse as 0
      expect(UpdateInfo.compareVersions('abc', '0.0.0'), 0);
    });
  });

  // ===========================================================================
  // UpdateInfo.hasUpdate
  // ===========================================================================
  group('UpdateInfo.hasUpdate', () {
    test('returns true when latest is newer', () {
      const info = UpdateInfo(
        latestVersion: '2.0.0',
        currentVersion: '1.0.0',
        releaseUrl: '',
      );
      expect(info.hasUpdate, isTrue);
    });

    test('returns false when versions are equal', () {
      const info = UpdateInfo(
        latestVersion: '1.0.0',
        currentVersion: '1.0.0',
        releaseUrl: '',
      );
      expect(info.hasUpdate, isFalse);
    });

    test('returns false when current is newer', () {
      const info = UpdateInfo(
        latestVersion: '1.0.0',
        currentVersion: '2.0.0',
        releaseUrl: '',
      );
      expect(info.hasUpdate, isFalse);
    });
  });

  // ===========================================================================
  // UpdateInfo equality
  // ===========================================================================
  group('UpdateInfo equality', () {
    test('equal instances are equal', () {
      const a = UpdateInfo(
        latestVersion: '2.0.0',
        currentVersion: '1.0.0',
        releaseUrl: 'url',
        assetUrl: 'asset',
        changelog: 'notes',
      );
      const b = UpdateInfo(
        latestVersion: '2.0.0',
        currentVersion: '1.0.0',
        releaseUrl: 'url',
        assetUrl: 'asset',
        changelog: 'notes',
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('different latestVersion makes unequal', () {
      const a = UpdateInfo(
        latestVersion: '2.0.0',
        currentVersion: '1.0.0',
        releaseUrl: 'url',
      );
      const b = UpdateInfo(
        latestVersion: '3.0.0',
        currentVersion: '1.0.0',
        releaseUrl: 'url',
      );
      expect(a, isNot(equals(b)));
    });

    test('different assetUrl makes unequal', () {
      const a = UpdateInfo(
        latestVersion: '2.0.0',
        currentVersion: '1.0.0',
        releaseUrl: 'url',
        assetUrl: 'a',
      );
      const b = UpdateInfo(
        latestVersion: '2.0.0',
        currentVersion: '1.0.0',
        releaseUrl: 'url',
        assetUrl: 'b',
      );
      expect(a, isNot(equals(b)));
    });

    test('identical returns true', () {
      const info = UpdateInfo(
        latestVersion: '1.0.0',
        currentVersion: '1.0.0',
        releaseUrl: '',
      );
      expect(info == info, isTrue);
    });

    test('not equal to different type', () {
      const info = UpdateInfo(
        latestVersion: '1.0.0',
        currentVersion: '1.0.0',
        releaseUrl: '',
      );
      expect(info == Object(), isFalse);
    });
  });

  // ===========================================================================
  // UpdateService.assetUrlForPlatform
  // ===========================================================================
  group('UpdateService.assetUrlForPlatform', () {
    final assets = _releaseJson()['assets'] as List<dynamic>;

    test('selects AppImage for linux', () {
      final url = UpdateService.assetUrlForPlatform(
        assets,
        platformOverride: 'linux',
      );
      expect(url, contains('AppImage'));
    });

    test('selects setup.exe for windows', () {
      final url = UpdateService.assetUrlForPlatform(
        assets,
        platformOverride: 'windows',
      );
      expect(url, contains('setup.exe'));
    });

    test('selects dmg for macos', () {
      final url = UpdateService.assetUrlForPlatform(
        assets,
        platformOverride: 'macos',
      );
      expect(url, contains('.dmg'));
    });

    test('selects arm64 apk for android', () {
      final url = UpdateService.assetUrlForPlatform(
        assets,
        platformOverride: 'android',
      );
      expect(url, contains('arm64.apk'));
    });

    test('returns null for unknown platform', () {
      final url = UpdateService.assetUrlForPlatform(
        assets,
        platformOverride: 'unknown',
      );
      expect(url, isNull);
    });

    test('returns null for iOS (no self-update)', () {
      final url = UpdateService.assetUrlForPlatform(
        assets,
        platformOverride: 'ios',
      );
      expect(url, isNull);
    });

    test('returns null when no matching asset', () {
      final url = UpdateService.assetUrlForPlatform(
        [
          {
            'name': 'some-other-file.zip',
            'browser_download_url': 'https://example.com/file.zip',
          },
        ],
        platformOverride: 'linux',
      );
      expect(url, isNull);
    });

    test('returns null for empty assets list', () {
      final url = UpdateService.assetUrlForPlatform(
        [],
        platformOverride: 'linux',
      );
      expect(url, isNull);
    });

    test('skips non-map entries in assets', () {
      final url = UpdateService.assetUrlForPlatform(
        ['not a map', 42, null],
        platformOverride: 'linux',
      );
      expect(url, isNull);
    });
  });

  // ===========================================================================
  // UpdateService.checkForUpdate (with injected fetcher)
  // ===========================================================================
  group('UpdateService.checkForUpdate', () {
    test('returns UpdateInfo with hasUpdate true when newer version', () async {
      final service = UpdateService(
        fetch: (_) async => jsonEncode(_releaseJson(tagName: 'v2.0.0')),
      );

      final info = await service.checkForUpdate('1.0.0');
      expect(info.hasUpdate, isTrue);
      expect(info.latestVersion, '2.0.0');
      expect(info.currentVersion, '1.0.0');
      expect(info.releaseUrl, contains('github.com'));
      expect(info.changelog, 'Release notes here');
    });

    test('returns hasUpdate false when same version', () async {
      final service = UpdateService(
        fetch: (_) async => jsonEncode(_releaseJson(tagName: 'v1.0.0')),
      );

      final info = await service.checkForUpdate('1.0.0');
      expect(info.hasUpdate, isFalse);
    });

    test('returns hasUpdate false when older remote version', () async {
      final service = UpdateService(
        fetch: (_) async => jsonEncode(_releaseJson(tagName: 'v0.9.0')),
      );

      final info = await service.checkForUpdate('1.0.0');
      expect(info.hasUpdate, isFalse);
    });

    test('handles missing tag_name gracefully', () async {
      final service = UpdateService(
        fetch: (_) async => jsonEncode({
          'html_url': 'https://github.com/releases',
          'assets': <dynamic>[],
        }),
      );

      final info = await service.checkForUpdate('1.0.0');
      expect(info.latestVersion, '');
      expect(info.hasUpdate, isFalse);
    });

    test('handles missing html_url with fallback', () async {
      final service = UpdateService(
        fetch: (_) async => jsonEncode({
          'tag_name': 'v2.0.0',
          'assets': <dynamic>[],
        }),
      );

      final info = await service.checkForUpdate('1.0.0');
      expect(info.releaseUrl, contains('github.com'));
      expect(info.releaseUrl, contains('releases/latest'));
    });

    test('handles null changelog', () async {
      final service = UpdateService(
        fetch: (_) async => jsonEncode(_releaseJson(body: null)),
      );

      final info = await service.checkForUpdate('1.0.0');
      expect(info.changelog, isNull);
    });

    test('propagates fetch errors', () async {
      final service = UpdateService(
        fetch: (_) async => throw const HttpException('Network error'),
      );

      expect(
        () => service.checkForUpdate('1.0.0'),
        throwsA(isA<HttpException>()),
      );
    });

    test('propagates JSON parse errors', () async {
      final service = UpdateService(
        fetch: (_) async => 'not json',
      );

      expect(
        () => service.checkForUpdate('1.0.0'),
        throwsA(isA<FormatException>()),
      );
    });

    test('selects asset for current platform', () async {
      final service = UpdateService(
        fetch: (_) async => jsonEncode(_releaseJson()),
      );

      final info = await service.checkForUpdate('1.0.0');
      // On the test platform (Linux in CI or whatever), we should get a URL
      // or null if the platform is not in the asset list
      if (Platform.isLinux) {
        expect(info.assetUrl, contains('AppImage'));
      } else if (Platform.isWindows) {
        expect(info.assetUrl, contains('setup.exe'));
      } else if (Platform.isMacOS) {
        expect(info.assetUrl, contains('.dmg'));
      }
    });
  });

  // ===========================================================================
  // UpdateService.downloadAsset (with injected downloader)
  // ===========================================================================
  group('UpdateService.downloadAsset', () {
    test('downloads file to target directory', () async {
      final tempDir = await Directory.systemTemp.createTemp('update_test_');
      try {
        final progressValues = <double>[];
        final service = UpdateService(
          download: (uri, savePath, onProgress) async {
            await File(savePath).writeAsString('fake binary');
            onProgress?.call(50, 100);
            onProgress?.call(100, 100);
          },
        );

        final path = await service.downloadAsset(
          'https://example.com/letsflutssh-2.0.0-linux-x64.AppImage',
          tempDir.path,
          onProgress: (received, total) {
            progressValues.add(received / total);
          },
        );

        expect(path, contains('letsflutssh-2.0.0-linux-x64.AppImage'));
        expect(await File(path).exists(), isTrue);
        expect(progressValues, [0.5, 1.0]);
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test('propagates download errors', () async {
      final service = UpdateService(
        download: (_, _, _) async =>
            throw const HttpException('Download failed'),
      );

      expect(
        () => service.downloadAsset(
          'https://example.com/file.AppImage',
          '/tmp/test',
        ),
        throwsA(isA<HttpException>()),
      );
    });
  });
}
