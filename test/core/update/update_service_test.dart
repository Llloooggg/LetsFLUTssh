import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:letsflutssh/core/update/update_service.dart';

import '../../helpers/frb_bootstrap.dart';

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
  TestWidgetsFlutterBinding.ensureInitialized();
  // UpdateInfo.compareVersions routes through
  // `lfs_core::update_metadata::compare_versions` — bootstrap FRB
  // so the canonical Rust semver compare runs.
  setUpAll(requireFrbLoaded);

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
  // UpdateService.checkForUpdate (with injected fetcher)
  // ===========================================================================
  group('UpdateService.checkForUpdate', () {
    test('returns UpdateInfo with hasUpdate true when newer version', () async {
      final service = UpdateService(
        verifyArtifact: UpdateService.skipSignatureVerification,
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
        verifyArtifact: UpdateService.skipSignatureVerification,
        fetch: (_) async => _releasesArray([_releaseJson(tagName: 'v1.0.0')]),
      );

      final info = await service.checkForUpdate('1.0.0');
      expect(info.hasUpdate, isFalse);
    });

    test('returns hasUpdate false when older remote version', () async {
      final service = UpdateService(
        verifyArtifact: UpdateService.skipSignatureVerification,
        fetch: (_) async => _releasesArray([_releaseJson(tagName: 'v0.9.0')]),
      );

      final info = await service.checkForUpdate('1.0.0');
      expect(info.hasUpdate, isFalse);
    });

    test('handles single object (legacy /latest format)', () async {
      final service = UpdateService(
        verifyArtifact: UpdateService.skipSignatureVerification,
        fetch: (_) async => jsonEncode(_releaseJson(tagName: 'v2.0.0')),
      );

      final info = await service.checkForUpdate('1.0.0');
      expect(info.hasUpdate, isTrue);
      expect(info.latestVersion, '2.0.0');
    });

    test('handles empty releases array', () async {
      final service = UpdateService(
        verifyArtifact: UpdateService.skipSignatureVerification,
        fetch: (_) async => '[]',
      );

      final info = await service.checkForUpdate('1.0.0');
      expect(info.hasUpdate, isFalse);
      expect(info.latestVersion, '1.0.0');
    });

    test('handles missing tag_name gracefully', () async {
      final service = UpdateService(
        verifyArtifact: UpdateService.skipSignatureVerification,
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
        verifyArtifact: UpdateService.skipSignatureVerification,
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
        verifyArtifact: UpdateService.skipSignatureVerification,
        fetch: (_) async => _releasesArray([_releaseJson(body: null)]),
      );

      final info = await service.checkForUpdate('1.0.0');
      expect(info.changelog, isNull);
    });

    test('extracts asset digest', () async {
      final service = UpdateService(
        verifyArtifact: UpdateService.skipSignatureVerification,
        fetch: (_) async => _releasesArray([_releaseJson()]),
      );

      final info = await service.checkForUpdate('1.0.0');
      if (Platform.isLinux) {
        expect(info.assetDigest, 'abcdef1234567890');
      }
    });

    test('builds cumulative changelog across multiple releases', () async {
      final service = UpdateService(
        verifyArtifact: UpdateService.skipSignatureVerification,
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
        verifyArtifact: UpdateService.skipSignatureVerification,
        fetch: (_) async => throw const HttpException('Network error'),
      );

      expect(
        () => service.checkForUpdate('1.0.0'),
        throwsA(isA<HttpException>()),
      );
    });

    test('propagates JSON parse errors', () async {
      final service = UpdateService(
        verifyArtifact: UpdateService.skipSignatureVerification,
        fetch: (_) async => 'not json',
      );

      expect(
        () => service.checkForUpdate('1.0.0'),
        throwsA(isA<FormatException>()),
      );
    });

    test('selects asset for current platform', () async {
      final service = UpdateService(
        verifyArtifact: UpdateService.skipSignatureVerification,
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
          verifyArtifact: UpdateService.skipSignatureVerification,
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
          verifyArtifact: UpdateService.skipSignatureVerification,
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
          verifyArtifact: UpdateService.skipSignatureVerification,
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
          verifyArtifact: UpdateService.skipSignatureVerification,
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
        verifyArtifact: UpdateService.skipSignatureVerification,
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
      final service = UpdateService(
        verifyArtifact: UpdateService.skipSignatureVerification,
        download: (_, _, _) async {},
      );
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

    test(
      'rejects + deletes binary when the injected verifier throws InvalidReleaseSignatureException',
      () async {
        final tempDir = await Directory.systemTemp.createTemp('rel_sig_test_');
        try {
          final service = UpdateService(
            download: (_, savePath, _) async {
              await File(savePath).writeAsString('fake binary');
            },
            verifyArtifact:
                ({
                  required assetUri,
                  required assetPath,
                  required targetDir,
                  required download,
                }) async {
                  throw const InvalidReleaseSignatureException(
                    'forced for test',
                  );
                },
          );

          await expectLater(
            service.downloadAsset(
              'https://github.com/Llloooggg/LetsFLUTssh/releases/download/v1/file.AppImage',
              tempDir.path,
            ),
            throwsA(isA<InvalidReleaseSignatureException>()),
          );
          // Binary must be deleted on signature failure.
          expect(
            await File(p.join(tempDir.path, 'file.AppImage')).exists(),
            isFalse,
          );
        } finally {
          await tempDir.delete(recursive: true);
        }
      },
    );
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
  // UpdateService.checkForUpdate — additional edge cases
  // ===========================================================================
  group('UpdateService.checkForUpdate (edge cases)', () {
    test('handles unexpected JSON type (number)', () async {
      final service = UpdateService(
        verifyArtifact: UpdateService.skipSignatureVerification,
        fetch: (_) async => '42',
      );

      final info = await service.checkForUpdate('1.0.0');
      expect(info.hasUpdate, isFalse);
      expect(info.latestVersion, '1.0.0');
    });

    test('handles unexpected JSON type (string)', () async {
      final service = UpdateService(
        verifyArtifact: UpdateService.skipSignatureVerification,
        fetch: (_) async => '"hello"',
      );

      final info = await service.checkForUpdate('1.0.0');
      expect(info.hasUpdate, isFalse);
      expect(info.latestVersion, '1.0.0');
    });

    test('handles release with null assets list', () async {
      final service = UpdateService(
        verifyArtifact: UpdateService.skipSignatureVerification,
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
        verifyArtifact: UpdateService.skipSignatureVerification,
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
      final service = UpdateService(
        verifyArtifact: UpdateService.skipSignatureVerification,
        download: (_, _, _) async {},
      );
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
          verifyArtifact: UpdateService.skipSignatureVerification,
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
            verifyArtifact: UpdateService.skipSignatureVerification,
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
        verifyArtifact: UpdateService.skipSignatureVerification,
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
        verifyArtifact: UpdateService.skipSignatureVerification,
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
        verifyArtifact: UpdateService.skipSignatureVerification,
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
          verifyArtifact: UpdateService.skipSignatureVerification,
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
          verifyArtifact: UpdateService.skipSignatureVerification,
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
          verifyArtifact: UpdateService.skipSignatureVerification,
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
          verifyArtifact: UpdateService.skipSignatureVerification,
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
  // UpdateService.defaultFetch / UpdateService.defaultDownload —
  // production now routes through `lfs_core::update_http` (rustls +
  // system CAs + trusted-host gate); the HTTP-level semantics (200 /
  // non-200 / redirect handling / per-chunk progress / 10-redirect
  // cap) are covered Rust-side in `lfs_core::update_http::tests` and
  // end-to-end in integration_test against a real server. The only
  // assertion left here is the URL-trust fail-fast — a pure Dart
  // guard that fires before either the Dart wrapper body or the FRB
  // call to `update_http::download_to_file` runs.
  // ===========================================================================
  group('UpdateService default HTTP implementations', () {
    test(
      'defaultDownload refuses untrusted URL before any HTTP attempt',
      // Spec: the trust check runs synchronously at the top of
      // [UpdateService.defaultDownload] before either the Dart guard
      // body or the FRB call to `lfs_core::update_http::download_to_file`
      // runs. Guards against ever shipping an update from a non-GitHub
      // host. Throw is the contract — the throw itself proves no
      // network attempt was made because the rest of the function never
      // executes after StateError raises.
      () async {
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
      },
    );
  });

  // ===========================================================================
  // Manifest-signature flow (the production [_defaultVerifyArtifact]
  // decomposes into two pure pieces: version parsing + manifest parsing).
  // We unit-test each directly; the full end-to-end path is exercised
  // through the wider update flow + Rust unit tests under
  // `lfs_core::update_signing::tests` (pinned-key verify, fail-closed
  // wrong-length, all-zero signature) and the public verifier contract.
  // ===========================================================================
  group('UpdateService.parseAssetVersion', () {
    test('captures the semver from a canonical release asset filename', () {
      expect(
        UpdateService.parseAssetVersion('letsflutssh-5.9.0-linux-x64.tar.gz'),
        '5.9.0',
      );
      expect(
        UpdateService.parseAssetVersion(
          'letsflutssh-10.12.3-windows-x64-setup.exe',
        ),
        '10.12.3',
      );
    });

    test(
      'returns null for names that do not start with the product prefix',
      () {
        // Spec: we only accept names produced by our own release workflow.
        // An upstream-typoed `letsflutssh_5.9.0-*` (underscore), a bare
        // version, or a different product name must not silently pass —
        // the whole manifest flow keys off this capture.
        expect(
          UpdateService.parseAssetVersion('letsflutssh_5.9.0.tar.gz'),
          isNull,
        );
        expect(
          UpdateService.parseAssetVersion('5.9.0-linux-x64.tar.gz'),
          isNull,
        );
        expect(
          UpdateService.parseAssetVersion('other-5.9.0-linux.tar.gz'),
          isNull,
        );
      },
    );

    test('returns null for a pre-release or non-dotted version string', () {
      // Our bump script only produces three-part semver — any other
      // shape is a sign something went wrong upstream, better to
      // fail-closed than match a surprise.
      expect(
        UpdateService.parseAssetVersion('letsflutssh-5.9-linux-x64.tar.gz'),
        isNull,
      );
      expect(
        UpdateService.parseAssetVersion(
          'letsflutssh-5.9.0-rc1-linux-x64.tar.gz',
        ),
        '5.9.0',
        reason:
            'the leading three-digit dotted version still captures — '
            'anything after the third segment is part of the platform '
            'suffix and not our concern here',
      );
    });
  });

  group('UpdateService.parseSha256Manifest', () {
    test('parses the text-mode (double-space) sha256sum format', () {
      // Spec: workflow pipes `sha256sum <file>` output into the
      // manifest; GNU coreutils uses `<hash>  <name>` (two spaces)
      // by default. Verify we accept exactly that.
      const content =
          'a3f5e8d2c91b1234567890abcdef1234567890abcdef1234567890abcdef1234  '
          'letsflutssh-5.9.0-linux-x64.tar.gz\n'
          'b7d1f2e9a45cabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcd  '
          'letsflutssh-5.9.0-linux-amd64.deb\n';
      final m = UpdateService.parseSha256Manifest(content);
      expect(m.length, 2);
      expect(m['letsflutssh-5.9.0-linux-x64.tar.gz'], startsWith('a3f5'));
      expect(m['letsflutssh-5.9.0-linux-amd64.deb'], startsWith('b7d1'));
    });

    test('accepts binary-mode (asterisk-prefixed) filename field', () {
      // `sha256sum -b` emits `<hash> *<name>`. Be lenient so a
      // workflow tweak that switches modes doesn't silently break
      // the verifier.
      final hash = 'a' * 64;
      final m = UpdateService.parseSha256Manifest(
        '$hash *letsflutssh-5.9.0-linux-x64.tar.gz\n',
      );
      expect(m['letsflutssh-5.9.0-linux-x64.tar.gz'], hash);
    });

    test('ignores blank lines and comments', () {
      // Spec: the manifest format stays forward-compatible with
      // human-readable annotations — a future workflow tweak that
      // adds a header comment should not break the parser.
      final hash = 'b' * 64;
      final m = UpdateService.parseSha256Manifest('''
# Release manifest — letsflutssh 5.9.0

$hash  letsflutssh-5.9.0-linux-x64.tar.gz

''');
      expect(m.length, 1);
      expect(m['letsflutssh-5.9.0-linux-x64.tar.gz'], hash);
    });

    test(
      'rejects malformed lines (short hash, missing whitespace, empty name)',
      () {
        // Silent skip over malformed lines — defensive parse so a
        // single stray byte doesn't poison the whole manifest.
        final m = UpdateService.parseSha256Manifest('''
short-hash  letsflutssh-5.9.0-linux-x64.tar.gz
${'c' * 64}
${'d' * 64}  ''');
        expect(
          m,
          isEmpty,
          reason:
              'no valid entry — short hash is length-checked out, two '
              'malformed lines carry no whitespace-bound name',
        );
      },
    );

    test('later duplicate entry overrides earlier — last write wins', () {
      // Spec: a duplicate in a signed manifest means the release
      // manifest is malformed, but the verifier still has to pick
      // one value. Last-write-wins matches how `sha256sum -c` walks
      // the file top-to-bottom — whichever entry is checked last is
      // the effective one.
      final hashA = 'a' * 64;
      final hashB = 'b' * 64;
      final m = UpdateService.parseSha256Manifest(
        '$hashA  letsflutssh-5.9.0-linux-x64.tar.gz\n'
        '$hashB  letsflutssh-5.9.0-linux-x64.tar.gz\n',
      );
      expect(m['letsflutssh-5.9.0-linux-x64.tar.gz'], hashB);
    });
  });

  group('InvalidReleaseSignatureException.toString', () {
    test('surfaces both the exception type and the reason string', () {
      // Settings renders the toString in a security-styled toast when
      // no locale string applies yet — a refactor that dropped the
      // type prefix would erase the "this is a signature problem"
      // signal and leave only the bare reason.
      const ex = InvalidReleaseSignatureException(
        'Manifest signature did not verify against the pinned public key',
      );
      final msg = ex.toString();
      expect(msg, startsWith('InvalidReleaseSignatureException:'));
      expect(msg, contains('Manifest signature'));
      expect(msg, contains('pinned public key'));
    });

    test('empty reason still produces a non-empty message', () {
      const ex = InvalidReleaseSignatureException('');
      expect(ex.toString(), startsWith('InvalidReleaseSignatureException:'));
    });
  });
}
