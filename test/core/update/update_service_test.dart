import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
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
            'digest': 'sha256:abcdef1234567890',
          },
          {
            'name': 'letsflutssh-2.0.0-windows-x64-setup.exe',
            'browser_download_url':
                'https://github.com/download/letsflutssh-2.0.0-windows-x64-setup.exe',
            'digest': 'sha256:1234567890abcdef',
          },
          {
            'name': 'letsflutssh-2.0.0-macos-universal.dmg',
            'browser_download_url':
                'https://github.com/download/letsflutssh-2.0.0-macos-universal.dmg',
            'digest': 'sha256:fedcba0987654321',
          },
          {
            'name': 'letsflutssh-2.0.0-android-arm64.apk',
            'browser_download_url':
                'https://github.com/download/letsflutssh-2.0.0-android-arm64.apk',
            'digest': 'sha256:9876543210fedcba',
          },
        ],
  };
}

/// Wraps a release in an array (GitHub /releases endpoint format).
String _releasesArray(List<Map<String, dynamic>> releases) =>
    jsonEncode(releases);

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
        assetDigest: 'abc123',
        changelog: 'notes',
      );
      const b = UpdateInfo(
        latestVersion: '2.0.0',
        currentVersion: '1.0.0',
        releaseUrl: 'url',
        assetUrl: 'asset',
        assetDigest: 'abc123',
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

    test('different assetDigest makes unequal', () {
      const a = UpdateInfo(
        latestVersion: '2.0.0',
        currentVersion: '1.0.0',
        releaseUrl: 'url',
        assetDigest: 'abc',
      );
      const b = UpdateInfo(
        latestVersion: '2.0.0',
        currentVersion: '1.0.0',
        releaseUrl: 'url',
        assetDigest: 'def',
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
  // UpdateService.digestForPlatform
  // ===========================================================================
  group('UpdateService.digestForPlatform', () {
    final assets = _releaseJson()['assets'] as List<dynamic>;

    test('extracts sha256 digest for linux', () {
      final digest = UpdateService.digestForPlatform(
        assets,
        platformOverride: 'linux',
      );
      expect(digest, 'abcdef1234567890');
    });

    test('extracts sha256 digest for windows', () {
      final digest = UpdateService.digestForPlatform(
        assets,
        platformOverride: 'windows',
      );
      expect(digest, '1234567890abcdef');
    });

    test('returns null when no digest field', () {
      final digest = UpdateService.digestForPlatform(
        [
          {
            'name': 'file-linux-x64.AppImage',
            'browser_download_url': 'https://example.com/file',
          },
        ],
        platformOverride: 'linux',
      );
      expect(digest, isNull);
    });

    test('returns null for unknown platform', () {
      final digest = UpdateService.digestForPlatform(
        assets,
        platformOverride: 'unknown',
      );
      expect(digest, isNull);
    });

    test('ignores non-sha256 digest prefix', () {
      final digest = UpdateService.digestForPlatform(
        [
          {
            'name': 'file-linux-x64.AppImage',
            'digest': 'md5:abc123',
          },
        ],
        platformOverride: 'linux',
      );
      expect(digest, isNull);
    });
  });

  // ===========================================================================
  // UpdateService.buildCumulativeChangelog
  // ===========================================================================
  group('UpdateService.buildCumulativeChangelog', () {
    test('includes all versions newer than current', () {
      final releases = [
        _releaseJson(tagName: 'v3.0.0', body: 'Three'),
        _releaseJson(tagName: 'v2.0.0', body: 'Two'),
        _releaseJson(tagName: 'v1.0.0', body: 'One'),
      ];

      final changelog = UpdateService.buildCumulativeChangelog(releases, '1.0.0');
      expect(changelog, contains('## v3.0.0'));
      expect(changelog, contains('Three'));
      expect(changelog, contains('## v2.0.0'));
      expect(changelog, contains('Two'));
      expect(changelog, isNot(contains('## v1.0.0')));
      expect(changelog, isNot(contains('One')));
    });

    test('returns null when no newer versions', () {
      final releases = [
        _releaseJson(tagName: 'v1.0.0', body: 'One'),
      ];

      final changelog = UpdateService.buildCumulativeChangelog(releases, '1.0.0');
      expect(changelog, isNull);
    });

    test('skips releases with empty body', () {
      final releases = [
        _releaseJson(tagName: 'v2.0.0', body: ''),
        _releaseJson(tagName: 'v1.5.0', body: 'Notes'),
      ];

      final changelog = UpdateService.buildCumulativeChangelog(releases, '1.0.0');
      expect(changelog, isNot(contains('v2.0.0')));
      expect(changelog, contains('v1.5.0'));
      expect(changelog, contains('Notes'));
    });

    test('returns null for empty releases', () {
      final changelog = UpdateService.buildCumulativeChangelog([], '1.0.0');
      expect(changelog, isNull);
    });
  });

  // ===========================================================================
  // UpdateService.checkForUpdate (with injected fetcher)
  // ===========================================================================
  group('UpdateService.checkForUpdate', () {
    test('returns UpdateInfo with hasUpdate true when newer version', () async {
      final service = UpdateService(
        fetch: (_) async => _releasesArray([_releaseJson(tagName: 'v2.0.0')]),
      );

      final info = await service.checkForUpdate('1.0.0');
      expect(info.hasUpdate, isTrue);
      expect(info.latestVersion, '2.0.0');
      expect(info.currentVersion, '1.0.0');
      expect(info.releaseUrl, contains('github.com'));
      expect(info.changelog, contains('Release notes here'));
    });

    test('returns hasUpdate false when same version', () async {
      final service = UpdateService(
        fetch: (_) async => _releasesArray([_releaseJson(tagName: 'v1.0.0')]),
      );

      final info = await service.checkForUpdate('1.0.0');
      expect(info.hasUpdate, isFalse);
    });

    test('returns hasUpdate false when older remote version', () async {
      final service = UpdateService(
        fetch: (_) async => _releasesArray([_releaseJson(tagName: 'v0.9.0')]),
      );

      final info = await service.checkForUpdate('1.0.0');
      expect(info.hasUpdate, isFalse);
    });

    test('handles single object (legacy /latest format)', () async {
      final service = UpdateService(
        fetch: (_) async => jsonEncode(_releaseJson(tagName: 'v2.0.0')),
      );

      final info = await service.checkForUpdate('1.0.0');
      expect(info.hasUpdate, isTrue);
      expect(info.latestVersion, '2.0.0');
    });

    test('handles empty releases array', () async {
      final service = UpdateService(
        fetch: (_) async => '[]',
      );

      final info = await service.checkForUpdate('1.0.0');
      expect(info.hasUpdate, isFalse);
      expect(info.latestVersion, '1.0.0');
    });

    test('handles missing tag_name gracefully', () async {
      final service = UpdateService(
        fetch: (_) async => _releasesArray([{
          'html_url': 'https://github.com/releases',
          'assets': <dynamic>[],
        }]),
      );

      final info = await service.checkForUpdate('1.0.0');
      expect(info.latestVersion, '');
      expect(info.hasUpdate, isFalse);
    });

    test('handles missing html_url with fallback', () async {
      final service = UpdateService(
        fetch: (_) async => _releasesArray([{
          'tag_name': 'v2.0.0',
          'assets': <dynamic>[],
        }]),
      );

      final info = await service.checkForUpdate('1.0.0');
      expect(info.releaseUrl, contains('github.com'));
      expect(info.releaseUrl, contains('releases/latest'));
    });

    test('handles null changelog', () async {
      final service = UpdateService(
        fetch: (_) async => _releasesArray([_releaseJson(body: null)]),
      );

      final info = await service.checkForUpdate('1.0.0');
      expect(info.changelog, isNull);
    });

    test('extracts asset digest', () async {
      final service = UpdateService(
        fetch: (_) async => _releasesArray([_releaseJson()]),
      );

      final info = await service.checkForUpdate('1.0.0');
      if (Platform.isLinux) {
        expect(info.assetDigest, 'abcdef1234567890');
      }
    });

    test('builds cumulative changelog across multiple releases', () async {
      final service = UpdateService(
        fetch: (_) async => _releasesArray([
          _releaseJson(tagName: 'v3.0.0', body: 'Version three notes'),
          _releaseJson(tagName: 'v2.0.0', body: 'Version two notes'),
          _releaseJson(tagName: 'v1.0.0', body: 'Version one notes'),
        ]),
      );

      final info = await service.checkForUpdate('1.0.0');
      expect(info.changelog, contains('v3.0.0'));
      expect(info.changelog, contains('Version three notes'));
      expect(info.changelog, contains('v2.0.0'));
      expect(info.changelog, contains('Version two notes'));
      expect(info.changelog, isNot(contains('v1.0.0')));
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
        fetch: (_) async => _releasesArray([_releaseJson()]),
      );

      final info = await service.checkForUpdate('1.0.0');
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

    test('verifies SHA256 digest on success', () async {
      final tempDir = await Directory.systemTemp.createTemp('update_test_');
      try {
        const content = 'test file content';
        final service = UpdateService(
          download: (_, savePath, _) async {
            await File(savePath).writeAsString(content);
          },
        );

        // Compute expected hash
        final expectedHash = await (() async {
          final tmpFile = File(p.join(tempDir.path, 'tmp'));
          await tmpFile.writeAsString(content);
          return UpdateService.computeFileSha256(tmpFile.path);
        })();

        final path = await service.downloadAsset(
          'https://example.com/file.AppImage',
          tempDir.path,
          expectedDigest: expectedHash,
        );

        expect(await File(path).exists(), isTrue);
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test('throws and deletes file on SHA256 mismatch', () async {
      final tempDir = await Directory.systemTemp.createTemp('update_test_');
      try {
        final service = UpdateService(
          download: (_, savePath, _) async {
            final f = File(savePath);
            await f.parent.create(recursive: true);
            await f.writeAsString('tampered content');
          },
        );

        await expectLater(
          service.downloadAsset(
            'https://example.com/file.AppImage',
            tempDir.path,
            expectedDigest: 'wrong_hash_value',
          ),
          throwsA(isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('SHA256 mismatch'),
          )),
        );

        // File should be deleted after mismatch
        expect(
          await File(p.join(tempDir.path, 'file.AppImage')).exists(),
          isFalse,
        );
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test('skips verification when no digest provided', () async {
      final tempDir = await Directory.systemTemp.createTemp('update_test_');
      try {
        final service = UpdateService(
          download: (_, savePath, _) async {
            await File(savePath).writeAsString('content');
          },
        );

        final path = await service.downloadAsset(
          'https://example.com/file.AppImage',
          tempDir.path,
          // no expectedDigest
        );

        expect(await File(path).exists(), isTrue);
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

  // ===========================================================================
  // UpdateService.computeFileSha256
  // ===========================================================================
  group('UpdateService.computeFileSha256', () {
    test('computes correct SHA256 for known content', () async {
      final tempDir = await Directory.systemTemp.createTemp('sha256_test_');
      try {
        final file = File(p.join(tempDir.path, 'test.bin'));
        await file.writeAsString('hello');
        final hash = await UpdateService.computeFileSha256(file.path);
        // SHA256 of "hello" = 2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824
        expect(hash, '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824');
      } finally {
        await tempDir.delete(recursive: true);
      }
    });
  });
}
