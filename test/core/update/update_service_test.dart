import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:letsflutssh/core/update/update_service.dart';

/// Minimal GitHub release JSON for testing.
Map<String, dynamic> _releaseJson({
  String tagName = 'v2.0.0',
  String htmlUrl =
      'https://github.com/Llloooggg/LetsFLUTssh/releases/tag/v2.0.0',
  String? body = 'Release notes here',
  List<Map<String, dynamic>>? assets,
}) {
  return {
    'tag_name': tagName,
    'html_url': htmlUrl,
    'body': body,
    'assets':
        assets ??
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
      final url = UpdateService.assetUrlForPlatform([
        {
          'name': 'some-other-file.zip',
          'browser_download_url': 'https://example.com/file.zip',
        },
      ], platformOverride: 'linux');
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
      final url = UpdateService.assetUrlForPlatform([
        'not a map',
        42,
        null,
      ], platformOverride: 'linux');
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
      final digest = UpdateService.digestForPlatform([
        {
          'name': 'file-linux-x64.AppImage',
          'browser_download_url': 'https://example.com/file',
        },
      ], platformOverride: 'linux');
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
      final digest = UpdateService.digestForPlatform([
        {'name': 'file-linux-x64.AppImage', 'digest': 'md5:abc123'},
      ], platformOverride: 'linux');
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

      final changelog = UpdateService.buildCumulativeChangelog(
        releases,
        '1.0.0',
      );
      expect(changelog, contains('## v3.0.0'));
      expect(changelog, contains('Three'));
      expect(changelog, contains('## v2.0.0'));
      expect(changelog, contains('Two'));
      expect(changelog, isNot(contains('## v1.0.0')));
      expect(changelog, isNot(contains('One')));
    });

    test('returns null when no newer versions', () {
      final releases = [_releaseJson(tagName: 'v1.0.0', body: 'One')];

      final changelog = UpdateService.buildCumulativeChangelog(
        releases,
        '1.0.0',
      );
      expect(changelog, isNull);
    });

    test('skips releases with empty body', () {
      final releases = [
        _releaseJson(tagName: 'v2.0.0', body: ''),
        _releaseJson(tagName: 'v1.5.0', body: 'Notes'),
      ];

      final changelog = UpdateService.buildCumulativeChangelog(
        releases,
        '1.0.0',
      );
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
      final service = UpdateService(fetch: (_) async => '[]');

      final info = await service.checkForUpdate('1.0.0');
      expect(info.hasUpdate, isFalse);
      expect(info.latestVersion, '1.0.0');
    });

    test('handles missing tag_name gracefully', () async {
      final service = UpdateService(
        fetch: (_) async => _releasesArray([
          {'html_url': 'https://github.com/releases', 'assets': <dynamic>[]},
        ]),
      );

      final info = await service.checkForUpdate('1.0.0');
      expect(info.latestVersion, '');
      expect(info.hasUpdate, isFalse);
    });

    test('handles missing html_url with fallback', () async {
      final service = UpdateService(
        fetch: (_) async => _releasesArray([
          {'tag_name': 'v2.0.0', 'assets': <dynamic>[]},
        ]),
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
      final service = UpdateService(fetch: (_) async => 'not json');

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
  // UpdateService.isTrustedReleaseAssetUri
  // ===========================================================================
  group('UpdateService.isTrustedReleaseAssetUri', () {
    test('allows https github.com', () {
      expect(
        UpdateService.isTrustedReleaseAssetUri(
          Uri.parse(
            'https://github.com/Llloooggg/LetsFLUTssh/releases/download/v1/a.AppImage',
          ),
        ),
        isTrue,
      );
    });

    test('allows https *.githubusercontent.com', () {
      expect(
        UpdateService.isTrustedReleaseAssetUri(
          Uri.parse('https://objects.githubusercontent.com/abc'),
        ),
        isTrue,
      );
    });

    test('rejects http', () {
      expect(
        UpdateService.isTrustedReleaseAssetUri(
          Uri.parse('http://github.com/x'),
        ),
        isFalse,
      );
    });

    test('rejects non-GitHub host', () {
      expect(
        UpdateService.isTrustedReleaseAssetUri(
          Uri.parse('https://example.com/file'),
        ),
        isFalse,
      );
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
          'https://github.com/Llloooggg/LetsFLUTssh/releases/download/v2.0.0/letsflutssh-2.0.0-linux-x64.AppImage',
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
          'https://github.com/Llloooggg/LetsFLUTssh/releases/download/v1/file.AppImage',
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
            'https://github.com/Llloooggg/LetsFLUTssh/releases/download/v1/file.AppImage',
            tempDir.path,
            expectedDigest: 'wrong_hash_value',
          ),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('SHA256 mismatch'),
            ),
          ),
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
          'https://github.com/Llloooggg/LetsFLUTssh/releases/download/v1/file.AppImage',
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
          'https://github.com/Llloooggg/LetsFLUTssh/releases/download/v1/file.AppImage',
          '/tmp/test',
        ),
        throwsA(isA<HttpException>()),
      );
    });

    test('rejects untrusted download URL before downloader runs', () async {
      final service = UpdateService(download: (_, _, _) async {});
      expect(
        () => service.downloadAsset(
          'https://evil.example/asset.AppImage',
          '/tmp',
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Untrusted'),
          ),
        ),
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
        expect(
          hash,
          '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824',
        );
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test('computes correct SHA256 for empty file', () async {
      final tempDir = await Directory.systemTemp.createTemp('sha256_test_');
      try {
        final file = File(p.join(tempDir.path, 'empty.bin'));
        await file.writeAsBytes([]);
        final hash = await UpdateService.computeFileSha256(file.path);
        // SHA256 of empty content = e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
        expect(
          hash,
          'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
        );
      } finally {
        await tempDir.delete(recursive: true);
      }
    });
  });

  // ===========================================================================
  // UpdateInfo.compareVersions — additional edge cases
  // ===========================================================================
  group('UpdateInfo.compareVersions (edge cases)', () {
    test('both have v prefix', () {
      expect(UpdateInfo.compareVersions('v2.0.0', 'v1.0.0'), greaterThan(0));
    });

    test('extra version components are ignored', () {
      // _parseVersion only takes first 3 components
      expect(UpdateInfo.compareVersions('1.2.3.4', '1.2.3'), 0);
    });

    test('empty string treated as 0.0.0', () {
      expect(UpdateInfo.compareVersions('', '0.0.0'), 0);
    });

    test('v-only string treated as 0.0.0', () {
      expect(UpdateInfo.compareVersions('v', '0.0.0'), 0);
    });

    test('partial non-numeric components default to zero', () {
      expect(UpdateInfo.compareVersions('1.abc.3', '1.0.3'), 0);
    });
  });

  // ===========================================================================
  // UpdateInfo equality — remaining field differences
  // ===========================================================================
  group('UpdateInfo equality (additional fields)', () {
    test('different currentVersion makes unequal', () {
      const a = UpdateInfo(
        latestVersion: '2.0.0',
        currentVersion: '1.0.0',
        releaseUrl: 'url',
      );
      const b = UpdateInfo(
        latestVersion: '2.0.0',
        currentVersion: '1.5.0',
        releaseUrl: 'url',
      );
      expect(a, isNot(equals(b)));
    });

    test('different releaseUrl makes unequal', () {
      const a = UpdateInfo(
        latestVersion: '2.0.0',
        currentVersion: '1.0.0',
        releaseUrl: 'url-a',
      );
      const b = UpdateInfo(
        latestVersion: '2.0.0',
        currentVersion: '1.0.0',
        releaseUrl: 'url-b',
      );
      expect(a, isNot(equals(b)));
    });

    test('different changelog makes unequal', () {
      const a = UpdateInfo(
        latestVersion: '2.0.0',
        currentVersion: '1.0.0',
        releaseUrl: 'url',
        changelog: 'notes-a',
      );
      const b = UpdateInfo(
        latestVersion: '2.0.0',
        currentVersion: '1.0.0',
        releaseUrl: 'url',
        changelog: 'notes-b',
      );
      expect(a, isNot(equals(b)));
    });

    test('null optional fields are equal', () {
      const a = UpdateInfo(
        latestVersion: '2.0.0',
        currentVersion: '1.0.0',
        releaseUrl: 'url',
      );
      const b = UpdateInfo(
        latestVersion: '2.0.0',
        currentVersion: '1.0.0',
        releaseUrl: 'url',
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });
  });

  // ===========================================================================
  // UpdateService.isTrustedReleaseAssetUri — additional edge cases
  // ===========================================================================
  group('UpdateService.isTrustedReleaseAssetUri (edge cases)', () {
    test('rejects URI with empty host', () {
      expect(
        UpdateService.isTrustedReleaseAssetUri(Uri.parse('https:///path')),
        isFalse,
      );
    });

    test('rejects ftp scheme', () {
      expect(
        UpdateService.isTrustedReleaseAssetUri(
          Uri.parse('ftp://github.com/file'),
        ),
        isFalse,
      );
    });

    test(
      'rejects github.com subdomain that is not *.githubusercontent.com',
      () {
        expect(
          UpdateService.isTrustedReleaseAssetUri(
            Uri.parse('https://evil-github.com/file'),
          ),
          isFalse,
        );
      },
    );

    test('allows sub-subdomain of githubusercontent.com', () {
      expect(
        UpdateService.isTrustedReleaseAssetUri(
          Uri.parse('https://a.b.githubusercontent.com/file'),
        ),
        isTrue,
      );
    });
  });

  // ===========================================================================
  // UpdateService.digestForPlatform — additional edge cases
  // ===========================================================================
  group('UpdateService.digestForPlatform (edge cases)', () {
    test('skips non-map entries in assets list', () {
      final digest = UpdateService.digestForPlatform([
        'not a map',
        42,
        null,
      ], platformOverride: 'linux');
      expect(digest, isNull);
    });

    test('returns null for asset with missing name field', () {
      final digest = UpdateService.digestForPlatform([
        <String, dynamic>{
          'browser_download_url': 'https://example.com/f',
          'digest': 'sha256:abc',
        },
      ], platformOverride: 'linux');
      expect(digest, isNull);
    });

    test('extracts digest for macos platform', () {
      final digest = UpdateService.digestForPlatform([
        {'name': 'app-macos-universal.dmg', 'digest': 'sha256:macdigest123'},
      ], platformOverride: 'macos');
      expect(digest, 'macdigest123');
    });

    test('extracts digest for android platform', () {
      final digest = UpdateService.digestForPlatform([
        {'name': 'app-android-arm64.apk', 'digest': 'sha256:androiddigest'},
      ], platformOverride: 'android');
      expect(digest, 'androiddigest');
    });

    test('returns null when digest field is null', () {
      final digest = UpdateService.digestForPlatform([
        {'name': 'file-linux-x64.AppImage', 'digest': null},
      ], platformOverride: 'linux');
      expect(digest, isNull);
    });
  });

  // ===========================================================================
  // UpdateService.buildCumulativeChangelog — additional edge cases
  // ===========================================================================
  group('UpdateService.buildCumulativeChangelog (edge cases)', () {
    test('skips non-map entries in releases list', () {
      final changelog = UpdateService.buildCumulativeChangelog([
        'not a map',
        _releaseJson(tagName: 'v2.0.0', body: 'Good notes'),
      ], '1.0.0');
      expect(changelog, contains('Good notes'));
    });

    test('skips releases with null body', () {
      final changelog = UpdateService.buildCumulativeChangelog([
        _releaseJson(tagName: 'v2.0.0', body: null),
      ], '1.0.0');
      expect(changelog, isNull);
    });

    test('skips releases with whitespace-only body', () {
      final changelog = UpdateService.buildCumulativeChangelog([
        _releaseJson(tagName: 'v2.0.0', body: '   \n  '),
      ], '1.0.0');
      expect(changelog, isNull);
    });

    test('handles release with missing tag_name', () {
      // Missing tag_name defaults to empty string which compares as 0.0.0
      // so it would be <= currentVersion of 1.0.0, causing a break
      final changelog = UpdateService.buildCumulativeChangelog([
        <String, dynamic>{'body': 'Notes'},
      ], '1.0.0');
      expect(changelog, isNull);
    });
  });

  // ===========================================================================
  // UpdateService.checkForUpdate — additional edge cases
  // ===========================================================================
  group('UpdateService.checkForUpdate (edge cases)', () {
    test('handles unexpected JSON type (number)', () async {
      final service = UpdateService(fetch: (_) async => '42');

      final info = await service.checkForUpdate('1.0.0');
      expect(info.hasUpdate, isFalse);
      expect(info.latestVersion, '1.0.0');
    });

    test('handles unexpected JSON type (string)', () async {
      final service = UpdateService(fetch: (_) async => '"hello"');

      final info = await service.checkForUpdate('1.0.0');
      expect(info.hasUpdate, isFalse);
      expect(info.latestVersion, '1.0.0');
    });

    test('handles release with null assets list', () async {
      final service = UpdateService(
        fetch: (_) async => _releasesArray([
          {
            'tag_name': 'v2.0.0',
            'html_url': 'https://github.com/releases/v2.0.0',
          },
        ]),
      );

      final info = await service.checkForUpdate('1.0.0');
      expect(info.hasUpdate, isTrue);
      expect(info.assetUrl, isNull);
      expect(info.assetDigest, isNull);
    });

    test('handles tag_name without v prefix', () async {
      final service = UpdateService(
        fetch: (_) async => _releasesArray([
          {
            'tag_name': '3.0.0',
            'html_url': 'https://github.com/releases/3.0.0',
            'assets': <dynamic>[],
          },
        ]),
      );

      final info = await service.checkForUpdate('1.0.0');
      expect(info.hasUpdate, isTrue);
      expect(info.latestVersion, '3.0.0');
    });
  });

  // ===========================================================================
  // UpdateService.downloadAsset — additional edge cases
  // ===========================================================================
  group('UpdateService.downloadAsset (edge cases)', () {
    test('rejects http (non-https) download URL', () async {
      final service = UpdateService(download: (_, _, _) async {});
      expect(
        () => service.downloadAsset(
          'http://github.com/Llloooggg/LetsFLUTssh/releases/download/v1/file.AppImage',
          '/tmp',
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Untrusted'),
          ),
        ),
      );
    });

    test('handles download without progress callback', () async {
      final tempDir = await Directory.systemTemp.createTemp('update_test_');
      try {
        final service = UpdateService(
          download: (uri, savePath, onProgress) async {
            await File(savePath).writeAsString('content');
            // onProgress is null, should not be called
          },
        );

        final path = await service.downloadAsset(
          'https://github.com/Llloooggg/LetsFLUTssh/releases/download/v1/file.AppImage',
          tempDir.path,
        );

        expect(await File(path).exists(), isTrue);
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test(
      'SHA256 mismatch still surfaces when cleanup delete also fails',
      // Spec (update_service.downloadAsset L237-252): on digest mismatch we
      // attempt to delete the downloaded file so a partial/tampered artifact
      // cannot be mistaken for a good install. If delete itself fails (file
      // already gone, read-only dir, etc.) we must still throw the SHA256
      // mismatch StateError — cleanup is best-effort and must not mask the
      // primary security failure. The delete failure is logged, not
      // re-thrown.
      () async {
        // Trick to make File.delete throw: downloader writes the file, then
        // strips write permission from the parent dir so the delete call
        // raises EACCES. POSIX-only; Windows ACLs work differently, skip it
        // there since this project's CI is Linux.
        if (!Platform.isLinux && !Platform.isMacOS) {
          markTestSkipped('requires POSIX chmod to block directory writes');
          return;
        }

        final tempDir = await Directory.systemTemp.createTemp('update_test_');
        try {
          final service = UpdateService(
            download: (_, savePath, _) async {
              await File(savePath).writeAsString('content');
              await Process.run('chmod', ['a-w', tempDir.path]);
            },
          );

          await expectLater(
            service.downloadAsset(
              'https://github.com/Llloooggg/LetsFLUTssh/releases/download/v1/file.AppImage',
              tempDir.path,
              expectedDigest: 'unreachable_digest',
            ),
            throwsA(
              isA<StateError>().having(
                (e) => e.message,
                'message',
                contains('SHA256 mismatch'),
              ),
            ),
          );
        } finally {
          // Restore perms so the tempDir can be deleted on teardown.
          await Process.run('chmod', ['u+w', tempDir.path]);
          await tempDir.delete(recursive: true);
        }
      },
    );
  });

  // ===========================================================================
  // UpdateService.assetUrlForPlatform — additional edge cases
  // ===========================================================================
  group('UpdateService.assetUrlForPlatform (edge cases)', () {
    test('returns null when asset has no browser_download_url', () {
      final url = UpdateService.assetUrlForPlatform([
        {
          'name': 'letsflutssh-2.0.0-linux-x64.AppImage',
          // no browser_download_url key
        },
      ], platformOverride: 'linux');
      expect(url, isNull);
    });

    test('matches first matching asset when multiple match', () {
      final url = UpdateService.assetUrlForPlatform([
        {
          'name': 'a-linux-x64.AppImage',
          'browser_download_url': 'https://github.com/first',
        },
        {
          'name': 'b-linux-x64.AppImage',
          'browser_download_url': 'https://github.com/second',
        },
      ], platformOverride: 'linux');
      expect(url, 'https://github.com/first');
    });

    test('asset with empty name does not match', () {
      final url = UpdateService.assetUrlForPlatform([
        {'name': '', 'browser_download_url': 'https://github.com/empty'},
      ], platformOverride: 'linux');
      expect(url, isNull);
    });
  });

  // ===========================================================================
  // UpdateService.openFile (platform injected via constructor)
  // ===========================================================================
  //
  // Spec (derived from update_service.openFile source): pick a host-specific
  // "open this file" command from the platform string, pass the path, and
  // return whether the process exited cleanly. Windows additionally refuses
  // paths carrying shell metacharacters because cmd /c start would interpret
  // them. Unsupported platforms (e.g. 'android', 'unknown') must refuse
  // without spawning a process.
  group('UpdateService.openFile', () {
    test('linux opens via xdg-open and returns true on exit 0', () async {
      String? capturedExe;
      List<String>? capturedArgs;
      final service = UpdateService(
        platform: 'linux',
        runProcess: (exe, args) async {
          capturedExe = exe;
          capturedArgs = args;
          return ProcessResult(0, 0, '', '');
        },
      );

      final ok = await service.openFile('/tmp/test.AppImage');

      expect(ok, isTrue);
      expect(capturedExe, 'xdg-open');
      expect(capturedArgs, ['/tmp/test.AppImage']);
    });

    test('macos opens via /usr/bin/open and returns true on exit 0', () async {
      String? capturedExe;
      List<String>? capturedArgs;
      final service = UpdateService(
        platform: 'macos',
        runProcess: (exe, args) async {
          capturedExe = exe;
          capturedArgs = args;
          return ProcessResult(0, 0, '', '');
        },
      );

      final ok = await service.openFile('/Applications/App.dmg');

      expect(ok, isTrue);
      expect(capturedExe, 'open');
      expect(capturedArgs, ['/Applications/App.dmg']);
    });

    test('windows opens via cmd /c start with empty title slot', () async {
      // The empty string between `start` and `path` is the window title
      // placeholder — mandatory when the path is quoted, and a common source
      // of bugs when people omit it. Test asserts the exact arg vector.
      String? capturedExe;
      List<String>? capturedArgs;
      final service = UpdateService(
        platform: 'windows',
        runProcess: (exe, args) async {
          capturedExe = exe;
          capturedArgs = args;
          return ProcessResult(0, 0, '', '');
        },
      );

      final ok = await service.openFile(r'C:\Users\me\setup.exe');

      expect(ok, isTrue);
      expect(capturedExe, 'cmd');
      expect(capturedArgs, ['/c', 'start', '', r'C:\Users\me\setup.exe']);
    });

    test('non-zero exit propagates as false on each host platform', () async {
      for (final platform in ['linux', 'macos', 'windows']) {
        final service = UpdateService(
          platform: platform,
          runProcess: (_, _) async => ProcessResult(0, 1, '', 'err'),
        );

        expect(
          await service.openFile('/tmp/x.bin'),
          isFalse,
          reason: '$platform should surface non-zero exit as false',
        );
      }
    });

    test(
      'unsupported platform refuses without calling the process runner',
      // Spec: on platforms we don't ship self-update for (iOS, fuchsia,
      // anything not in _selfUpdatablePlatforms) openFile must short-circuit
      // to false — spawning `xdg-open` on an iPhone would be pure crash bait.
      () async {
        var processCalled = false;
        final service = UpdateService(
          platform: 'ios',
          runProcess: (_, _) async {
            processCalled = true;
            return ProcessResult(0, 0, '', '');
          },
        );

        final ok = await service.openFile('/tmp/anything');

        expect(ok, isFalse);
        expect(processCalled, isFalse);
      },
    );

    test(
      'windows refuses path with shell metacharacter before spawning cmd',
      // Spec: `cmd /c start` parses `&`, `|`, `<`, `>`, `^`, `%` as shell
      // metacharacters, so a path containing any of them would either fail
      // loudly or — worse — execute something unintended. openFile must
      // reject such paths up front and never spawn cmd.
      () async {
        var processCalled = false;
        final service = UpdateService(
          platform: 'windows',
          runProcess: (_, _) async {
            processCalled = true;
            return ProcessResult(0, 0, '', '');
          },
        );

        for (final ch in const ['&', '|', '<', '>', '^', '%']) {
          final ok = await service.openFile('C:\\tmp\\bad${ch}name.exe');
          expect(
            ok,
            isFalse,
            reason: 'path with "$ch" should be refused without spawning cmd',
          );
        }
        expect(processCalled, isFalse);
      },
    );

    test(
      'windows with safe path still spawns cmd (regression guard)',
      () async {
        // Paranoid check that the metacharacter filter isn't over-matching and
        // blocking paths that contain hyphens, dots, underscores, or spaces —
        // real Windows paths routinely carry these.
        var processCalled = false;
        final service = UpdateService(
          platform: 'windows',
          runProcess: (_, _) async {
            processCalled = true;
            return ProcessResult(0, 0, '', '');
          },
        );

        for (final path in const [
          r'C:\Program Files\App\setup.exe',
          r'D:\files\letsflutssh-5.3.1-windows-x64-setup.exe',
          r'E:\nested_folder.name\bin.exe',
        ]) {
          expect(await service.openFile(path), isTrue);
        }
        expect(processCalled, isTrue);
      },
    );
  });

  // ===========================================================================
  // UpdateService.defaultFetch / UpdateService.defaultDownload — exercised
  // with an HttpOverrides mock so the real HttpClient branch is covered.
  // ===========================================================================
  //
  // Spec:
  //   defaultFetch(url) -> body
  //     - GETs the URL with Accept: application/vnd.github.v3+json and the
  //       LetsFLUTssh user agent.
  //     - 200 -> response body decoded as UTF-8 string.
  //     - anything else -> HttpException with the status code in its message.
  //
  //   defaultDownload(url, savePath, onProgress?) -> writes response body
  //     - Rejects an untrusted URL upfront with StateError, before opening
  //       the client (so a bug in trust detection can't be masked by the
  //       network layer).
  //     - 2xx -> body streamed to savePath, onProgress invoked on each chunk.
  //     - 3xx with Location -> follows redirect *only if the target is also
  //       a trusted GitHub asset host*; rewrites requestUri, loops.
  //     - >10 redirects -> StateError 'Too many redirects' (cycle guard).
  //     - 3xx -> untrusted target -> StateError 'Untrusted … redirect'.
  //     - Non-redirect non-200 -> HttpException with the status code.
  group('UpdateService default HTTP implementations', () {
    test(
      'defaultFetch returns UTF-8 body on 200 with expected headers',
      () async {
        final recorded = <Uri>[];
        final recordedHeaders = <String, String>{};
        final overrides = _FakeHttpOverrides((uri) {
          recorded.add(uri);
          return _FakeResponse(200, body: utf8.encode('{"tag_name":"v2"}'));
        }, onHeader: (name, value) => recordedHeaders[name] = value);

        String body = '';
        await HttpOverrides.runWithHttpOverrides(() async {
          body = await UpdateService.defaultFetch(
            Uri.parse('https://api.github.com/repos/x/releases'),
          );
        }, overrides);

        expect(body, '{"tag_name":"v2"}');
        expect(recorded.single.host, 'api.github.com');
        expect(recordedHeaders['accept'], 'application/vnd.github.v3+json');
        expect(recordedHeaders['user-agent'], contains('LetsFLUTssh'));
      },
    );

    test('defaultFetch throws HttpException on non-200 status', () async {
      final overrides = _FakeHttpOverrides(
        (_) => _FakeResponse(503, body: utf8.encode('upstream down')),
      );

      await HttpOverrides.runWithHttpOverrides(() async {
        await expectLater(
          UpdateService.defaultFetch(
            Uri.parse('https://api.github.com/repos/x/releases'),
          ),
          throwsA(
            isA<HttpException>().having(
              (e) => e.message,
              'message',
              contains('503'),
            ),
          ),
        );
      }, overrides);
    });

    test(
      'defaultDownload refuses untrusted URL without opening the client',
      // Spec: the trust check runs *before* HttpClient is instantiated, so
      // this must never even attempt a request. Guards against ever shipping
      // an update from a non-GitHub host.
      () async {
        var clientCreated = false;
        final overrides = _FakeHttpOverrides(
          (_) => _FakeResponse(200),
          onClientCreated: () => clientCreated = true,
        );

        await HttpOverrides.runWithHttpOverrides(() async {
          await expectLater(
            UpdateService.defaultDownload(
              Uri.parse('https://evil.example/asset.AppImage'),
              '/tmp/nowhere',
              null,
            ),
            throwsA(
              isA<StateError>().having(
                (e) => e.message,
                'message',
                contains('Untrusted'),
              ),
            ),
          );
        }, overrides);

        expect(clientCreated, isFalse);
      },
    );

    test(
      'defaultDownload writes body to savePath and fires onProgress per chunk',
      () async {
        final tempDir = await Directory.systemTemp.createTemp('dl_test_');
        try {
          final overrides = _FakeHttpOverrides(
            (_) => _FakeResponse(
              200,
              chunks: [utf8.encode('hello '), utf8.encode('world')],
              contentLength: 11,
            ),
          );

          final progress = <(int, int)>[];
          final savePath = p.join(tempDir.path, 'pkg.AppImage');
          await HttpOverrides.runWithHttpOverrides(() async {
            await UpdateService.defaultDownload(
              Uri.parse(
                'https://github.com/Llloooggg/LetsFLUTssh/releases/download/v2/pkg.AppImage',
              ),
              savePath,
              (received, total) => progress.add((received, total)),
            );
          }, overrides);

          expect(await File(savePath).readAsString(), 'hello world');
          expect(progress, [(6, 11), (11, 11)]);
        } finally {
          await tempDir.delete(recursive: true);
        }
      },
    );

    test(
      'defaultDownload follows a trusted redirect and writes the final body',
      () async {
        final tempDir = await Directory.systemTemp.createTemp('dl_test_');
        try {
          final responses = <_FakeResponse>[
            _FakeResponse(
              302,
              headers: {
                'location':
                    'https://objects.githubusercontent.com/final/pkg.AppImage',
              },
            ),
            _FakeResponse(200, body: utf8.encode('final body')),
          ];
          var i = 0;
          final recorded = <Uri>[];
          final overrides = _FakeHttpOverrides((uri) {
            recorded.add(uri);
            return responses[i++];
          });

          final savePath = p.join(tempDir.path, 'pkg.AppImage');
          await HttpOverrides.runWithHttpOverrides(() async {
            await UpdateService.defaultDownload(
              Uri.parse(
                'https://github.com/Llloooggg/LetsFLUTssh/releases/download/v1/pkg.AppImage',
              ),
              savePath,
              null,
            );
          }, overrides);

          expect(recorded.length, 2);
          expect(recorded[0].host, 'github.com');
          expect(recorded[1].host, 'objects.githubusercontent.com');
          expect(await File(savePath).readAsString(), 'final body');
        } finally {
          await tempDir.delete(recursive: true);
        }
      },
    );

    test(
      'defaultDownload throws StateError when redirect target is untrusted',
      // Spec: GitHub's download CDN sometimes 302s; if a bug or MITM ever
      // redirects us off-platform, we must refuse rather than happily
      // follow. Guards the integrity of the update pipeline.
      () async {
        final overrides = _FakeHttpOverrides(
          (_) => _FakeResponse(
            302,
            headers: {'location': 'https://evil.example/bait.AppImage'},
          ),
        );

        await HttpOverrides.runWithHttpOverrides(() async {
          await expectLater(
            UpdateService.defaultDownload(
              Uri.parse(
                'https://github.com/Llloooggg/LetsFLUTssh/releases/download/v1/pkg.AppImage',
              ),
              '/tmp/nowhere',
              null,
            ),
            throwsA(
              isA<StateError>().having(
                (e) => e.message,
                'message',
                contains('Untrusted update download redirect'),
              ),
            ),
          );
        }, overrides);
      },
    );

    test('defaultDownload aborts after more than 10 redirects', () async {
      // Spec: cycle guard. Hand out a trusted 302 that points back to itself
      // 11 times; the 11th attempt must raise StateError 'Too many
      // redirects' instead of looping forever.
      var count = 0;
      final overrides = _FakeHttpOverrides((_) {
        count++;
        return _FakeResponse(
          302,
          headers: {
            'location':
                'https://objects.githubusercontent.com/cycle/pkg.AppImage',
          },
        );
      });

      await HttpOverrides.runWithHttpOverrides(() async {
        await expectLater(
          UpdateService.defaultDownload(
            Uri.parse(
              'https://github.com/Llloooggg/LetsFLUTssh/releases/download/v1/pkg.AppImage',
            ),
            '/tmp/nowhere',
            null,
          ),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('Too many redirects'),
            ),
          ),
        );
      }, overrides);

      expect(count, 11);
    });

    test(
      'defaultDownload throws HttpException on non-200 non-redirect',
      () async {
        final overrides = _FakeHttpOverrides(
          (_) => _FakeResponse(404, body: utf8.encode('not found')),
        );

        await HttpOverrides.runWithHttpOverrides(() async {
          await expectLater(
            UpdateService.defaultDownload(
              Uri.parse(
                'https://github.com/Llloooggg/LetsFLUTssh/releases/download/v1/pkg.AppImage',
              ),
              '/tmp/nowhere',
              null,
            ),
            throwsA(
              isA<HttpException>().having(
                (e) => e.message,
                'message',
                contains('404'),
              ),
            ),
          );
        }, overrides);
      },
    );
  });
}

// ===========================================================================
// HttpOverrides scaffolding — minimal mock HttpClient so tests can drive
// defaultFetch / defaultDownload without touching a real network.
// ===========================================================================

typedef _Responder = _FakeResponse Function(Uri uri);

class _FakeResponse {
  final int statusCode;
  final List<int> body;
  final List<List<int>> chunks;
  final Map<String, String> headers;
  final int contentLength;

  _FakeResponse(
    this.statusCode, {
    this.body = const [],
    List<List<int>>? chunks,
    this.headers = const {},
    int? contentLength,
  }) : chunks = chunks ?? (body.isEmpty ? const [] : [body]),
       contentLength = contentLength ?? body.length;
}

class _FakeHttpOverrides extends HttpOverrides {
  final _Responder responder;
  final void Function(String name, String value)? onHeader;
  final void Function()? onClientCreated;

  _FakeHttpOverrides(this.responder, {this.onHeader, this.onClientCreated});

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    onClientCreated?.call();
    return _FakeHttpClient(responder, onHeader);
  }
}

class _FakeHttpClient implements HttpClient {
  final _Responder responder;
  final void Function(String name, String value)? onHeader;

  _FakeHttpClient(this.responder, this.onHeader);

  @override
  Future<HttpClientRequest> getUrl(Uri url) async =>
      _FakeHttpClientRequest(url, responder(url), onHeader);

  @override
  void close({bool force = false}) {}

  // No-op for SPKI pinning hook — production wires this through
  // CertPinning.enforce, but the fake never returns a real cert chain.
  @override
  set badCertificateCallback(
    bool Function(X509Certificate cert, String host, int port)? callback,
  ) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHttpClientRequest implements HttpClientRequest {
  @override
  final Uri uri;
  final _FakeResponse _response;
  final _FakeHeaders _headers;

  _FakeHttpClientRequest(
    this.uri,
    this._response,
    void Function(String name, String value)? onHeader,
  ) : _headers = _FakeHeaders(onHeader);

  @override
  HttpHeaders get headers => _headers;

  @override
  Future<HttpClientResponse> close() async =>
      _FakeHttpClientResponse(_response);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHeaders implements HttpHeaders {
  final void Function(String name, String value)? _onHeader;
  _FakeHeaders(this._onHeader);

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    _onHeader?.call(name.toLowerCase(), value.toString());
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHttpClientResponse extends Stream<List<int>>
    implements HttpClientResponse {
  final _FakeResponse _response;
  final _FakeResponseHeaders _headers;

  _FakeHttpClientResponse(this._response)
    : _headers = _FakeResponseHeaders(_response.headers);

  @override
  int get statusCode => _response.statusCode;

  @override
  int get contentLength => _response.contentLength;

  @override
  HttpHeaders get headers => _headers;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.fromIterable(_response.chunks).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeResponseHeaders implements HttpHeaders {
  final Map<String, String> _store;
  _FakeResponseHeaders(this._store);

  @override
  String? value(String name) => _store[name.toLowerCase()];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
