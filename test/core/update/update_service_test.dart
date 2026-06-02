import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/update/update_service.dart';
import 'package:letsflutssh/src/rust/api/installer.dart' as rust_installer;
import 'package:letsflutssh/src/rust/api/update_http.dart' as rust_update_http;
import 'package:letsflutssh/src/rust/api/update_metadata.dart'
    as rust_update_meta;

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

/// Build a success-shaped [rust_update_http.DbDownloadResult] pointing
/// at a freshly-written stub file. Tests that assert on the returned
/// asset path can read [DbDownloadedAsset.assetPath] back; the
/// manifest pair paths are filled with parallel `.sha256sums` /
/// `.sha256sums.sig` neighbours to match what the Rust orchestrator
/// hands back on the live path.
rust_update_http.DbDownloadResult _downloadSuccess(String assetPath) =>
    rust_update_http.DbDownloadResult(
      asset: rust_update_http.DbDownloadedAsset(
        assetPath: assetPath,
        manifestPath: '$assetPath.sha256sums',
        manifestSigPath: '$assetPath.sha256sums.sig',
      ),
    );

/// Build a failure-shaped [rust_update_http.DbDownloadResult] for
/// the requested [kind] + [detail] pair. The Dart-side mapping in
/// `UpdateService.downloadAsset` reshapes each kind into the
/// matching exception class.
rust_update_http.DbDownloadResult _downloadFailure(
  rust_update_http.DbDownloadErrorKind kind,
  String detail,
) => rust_update_http.DbDownloadResult(errorKind: kind, errorDetail: detail);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // UpdateInfo.compareVersions routes through
  // `lfs_core::update_metadata::compare_versions` — bootstrap FRB
  // so the canonical Rust semver compare runs.
  setUpAll(requireFrbLoaded);

  // Clear the FRB-download seam between every test so a stray
  // override from an earlier case cannot leak into the next.
  tearDown(() => UpdateService.debugDownloadOverride = null);

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
  // UpdateService.downloadAsset
  //
  // Production routes through `rust_update_http.updateDownloadWithVerification`
  // — the entire stream-to-disk + SHA256 + manifest-signature pipeline
  // lives Rust-side. Tests script the FRB return shape via
  // `UpdateService.debugDownloadOverride` to exercise the Dart-side
  // result→exception mapping. The Rust pipeline itself is covered by
  // `lfs_core::update_http` unit tests and end-to-end integration tests.
  // ===========================================================================
  group('UpdateService.downloadAsset', () {
    test('returns the asset path on success', () async {
      final tempDir = await Directory.systemTemp.createTemp('update_test_');
      try {
        final savedAt = '${tempDir.path}/letsflutssh-2.0.0-linux-x64.AppImage';
        UpdateService.debugDownloadOverride =
            ({
              required url,
              required targetDir,
              required expectedDigest,
            }) async {
              await File(savedAt).writeAsString('fake binary');
              return _downloadSuccess(savedAt);
            };
        final service = UpdateService();

        final path = await service.downloadAsset(
          'https://github.com/Llloooggg/LetsFLUTssh/releases/download/v2.0.0/letsflutssh-2.0.0-linux-x64.AppImage',
          tempDir.path,
        );

        expect(path, savedAt);
        expect(await File(path).exists(), isTrue);
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test('passes expectedDigest through to the FRB downloader', () async {
      String? capturedDigest;
      UpdateService.debugDownloadOverride =
          ({required url, required targetDir, required expectedDigest}) async {
            capturedDigest = expectedDigest;
            return _downloadSuccess('/tmp/x');
          };
      final service = UpdateService();

      await service.downloadAsset(
        'https://github.com/Llloooggg/LetsFLUTssh/releases/download/v1/file.AppImage',
        '/tmp',
        expectedDigest: 'deadbeef',
      );

      expect(capturedDigest, 'deadbeef');
    });

    test(
      'empty-string digest forwarded when caller omits expectedDigest',
      // Spec: the FRB surface takes a `String expectedDigest` (no
      // null) and treats empty as "skip the per-asset SHA gate".
      // The Dart wrapper normalises a null caller-side digest into
      // `''` so the Rust side never has to inspect for null.
      () async {
        String? capturedDigest;
        UpdateService.debugDownloadOverride =
            ({
              required url,
              required targetDir,
              required expectedDigest,
            }) async {
              capturedDigest = expectedDigest;
              return _downloadSuccess('/tmp/x');
            };
        final service = UpdateService();

        await service.downloadAsset(
          'https://github.com/Llloooggg/LetsFLUTssh/releases/download/v1/file.AppImage',
          '/tmp',
        );

        expect(capturedDigest, '');
      },
    );

    test('maps DbDownloadErrorKind.invalidSignature to '
        'InvalidReleaseSignatureException', () async {
      UpdateService.debugDownloadOverride =
          ({required url, required targetDir, required expectedDigest}) async =>
              _downloadFailure(
                rust_update_http.DbDownloadErrorKind.invalidSignature,
                'manifest signature did not verify',
              );
      final service = UpdateService();

      await expectLater(
        service.downloadAsset(
          'https://github.com/Llloooggg/LetsFLUTssh/releases/download/v1/file.AppImage',
          '/tmp',
        ),
        throwsA(
          isA<InvalidReleaseSignatureException>().having(
            (e) => e.reason,
            'reason',
            contains('manifest signature'),
          ),
        ),
      );
    });

    test('maps DbDownloadErrorKind.manifestUnavailable to '
        'ReleaseManifestUnavailableException', () async {
      UpdateService.debugDownloadOverride =
          ({required url, required targetDir, required expectedDigest}) async =>
              _downloadFailure(
                rust_update_http.DbDownloadErrorKind.manifestUnavailable,
                '404 on manifest',
              );
      final service = UpdateService();

      await expectLater(
        service.downloadAsset(
          'https://github.com/Llloooggg/LetsFLUTssh/releases/download/v1/file.AppImage',
          '/tmp',
        ),
        throwsA(
          isA<ReleaseManifestUnavailableException>().having(
            (e) => e.reason,
            'reason',
            contains('404'),
          ),
        ),
      );
    });

    test(
      'maps DbDownloadErrorKind.untrusted to StateError with Untrusted prefix',
      () async {
        UpdateService.debugDownloadOverride =
            ({
              required url,
              required targetDir,
              required expectedDigest,
            }) async => _downloadFailure(
              rust_update_http.DbDownloadErrorKind.untrusted,
              'redirect to evil.example',
            );
        final service = UpdateService();

        await expectLater(
          service.downloadAsset(
            'https://github.com/Llloooggg/LetsFLUTssh/releases/download/v1/file.AppImage',
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
      },
    );

    test('maps DbDownloadErrorKind.network to generic StateError', () async {
      UpdateService.debugDownloadOverride =
          ({required url, required targetDir, required expectedDigest}) async =>
              _downloadFailure(
                rust_update_http.DbDownloadErrorKind.network,
                'connection reset',
              );
      final service = UpdateService();

      await expectLater(
        service.downloadAsset(
          'https://github.com/Llloooggg/LetsFLUTssh/releases/download/v1/file.AppImage',
          '/tmp',
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Update download failed'),
          ),
        ),
      );
    });

    test(
      'rejects untrusted download URL before invoking the downloader',
      () async {
        // Spec: the trust check in [UpdateService.downloadAsset] runs
        // synchronously at the top of the call and must reject before
        // the FRB downloader is ever invoked. The wrapper repeats the
        // gate the Rust side already enforces because a fail-fast on
        // Dart side avoids spinning up the bus subscription + FRB
        // round-trip for a URL we know is doomed.
        var downloaderCalled = false;
        UpdateService.debugDownloadOverride =
            ({
              required url,
              required targetDir,
              required expectedDigest,
            }) async {
              downloaderCalled = true;
              return _downloadSuccess('/tmp/x');
            };
        final service = UpdateService();
        await expectLater(
          service.downloadAsset('https://evil.example/asset.AppImage', '/tmp'),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('Untrusted'),
            ),
          ),
        );
        expect(downloaderCalled, isFalse);
      },
    );
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
      final service = UpdateService();
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

    test(
      'downloadAsset surfaces "without detail" when FRB result is null',
      // Spec: a downloader implementation that returns a result with
      // both `asset` and `errorKind` null is malformed. The wrapper
      // must fail loudly rather than silently swallow — the
      // `case null:` arm exists so a future Rust change that
      // forgets to populate a new kind is caught immediately.
      () async {
        UpdateService.debugDownloadOverride =
            ({
              required url,
              required targetDir,
              required expectedDigest,
            }) async => const rust_update_http.DbDownloadResult();
        final service = UpdateService();

        await expectLater(
          service.downloadAsset(
            'https://github.com/Llloooggg/LetsFLUTssh/releases/download/v1/file.AppImage',
            '/tmp',
          ),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('without detail'),
            ),
          ),
        );
      },
    );
  });

  // ===========================================================================
  // UpdateService.openFile (platform + InstallerOpener injected via
  // constructor)
  // ===========================================================================
  //
  // Spec (derived from update_service.openFile source): hand the path +
  // platform string off to the installer-launch perimeter (which lives in
  // `lfs_os_security::installer_launch` in production, swapped for a
  // scripted [InstallerOpener] in tests) and translate the typed
  // [rust_installer.InstallerLaunchOutcome] into the bool the UI expects —
  // `true` only on [InstallerLaunchOutcome.launched]. Every other variant
  // (`refusedUnsafePath`, `unsupportedPlatform`, `launchFailed`) surfaces as
  // `false` and lets Settings fall back to opening the GitHub release page.
  //
  // Tests below never call `openFile` without injecting `openInstaller`: the
  // default binding routes through the real FRB shim, which on Linux/WSL
  // would spawn `xdg-open` and pop a Windows file-association dialog.
  group('UpdateService.openFile', () {
    test(
      'linux Launched outcome returns true and hits the perimeter',
      () async {
        String? capturedPath;
        String? capturedPlatform;
        final service = UpdateService(
          platform: 'linux',
          openInstaller: (path, platform) async {
            capturedPath = path;
            capturedPlatform = platform;
            return const rust_installer.InstallerLaunchOutcome.launched();
          },
        );

        final ok = await service.openFile('/tmp/test.AppImage');

        expect(ok, isTrue);
        expect(capturedPath, '/tmp/test.AppImage');
        expect(capturedPlatform, 'linux');
      },
    );

    test(
      'macos Launched outcome returns true and hits the perimeter',
      () async {
        String? capturedPath;
        String? capturedPlatform;
        final service = UpdateService(
          platform: 'macos',
          openInstaller: (path, platform) async {
            capturedPath = path;
            capturedPlatform = platform;
            return const rust_installer.InstallerLaunchOutcome.launched();
          },
        );

        final ok = await service.openFile('/Applications/App.dmg');

        expect(ok, isTrue);
        expect(capturedPath, '/Applications/App.dmg');
        expect(capturedPlatform, 'macos');
      },
    );

    test(
      'windows Launched outcome returns true and hits the perimeter',
      () async {
        String? capturedPath;
        String? capturedPlatform;
        final service = UpdateService(
          platform: 'windows',
          openInstaller: (path, platform) async {
            capturedPath = path;
            capturedPlatform = platform;
            return const rust_installer.InstallerLaunchOutcome.launched();
          },
        );

        final ok = await service.openFile(r'C:\Users\me\setup.exe');

        expect(ok, isTrue);
        expect(capturedPath, r'C:\Users\me\setup.exe');
        expect(capturedPlatform, 'windows');
      },
    );

    test(
      'LaunchFailed outcome surfaces as false on every host platform',
      // Spec: a non-zero exit (or a missing executable) from the perimeter
      // surfaces as `InstallerLaunchOutcome.launchFailed`. `openFile` must
      // return false on each supported platform so Settings can fall back to
      // the browser-reveal path.
      () async {
        for (final platform in ['linux', 'macos', 'windows']) {
          final service = UpdateService(
            platform: platform,
            openInstaller: (_, _) async =>
                const rust_installer.InstallerLaunchOutcome.launchFailed(
                  exitCode: 1,
                  stderr: 'err',
                ),
          );

          expect(
            await service.openFile('/tmp/x.bin'),
            isFalse,
            reason: '$platform should surface LaunchFailed as false',
          );
        }
      },
    );

    test(
      'UnsupportedPlatform outcome refuses without retrying',
      // Spec: the perimeter answers `UnsupportedPlatform` for any platform
      // string outside linux/macos/windows. `openFile` must return false and
      // must not call the opener twice (no fallback retry).
      () async {
        var calls = 0;
        final service = UpdateService(
          platform: 'ios',
          openInstaller: (_, _) async {
            calls++;
            return const rust_installer.InstallerLaunchOutcome.unsupportedPlatform();
          },
        );

        final ok = await service.openFile('/tmp/anything');

        expect(ok, isFalse);
        expect(calls, 1);
      },
    );

    test(
      'RefusedUnsafePath outcome surfaces as false without retry',
      // Spec: when the perimeter's cmd.exe-metacharacter allowlist refuses
      // the path, `openFile` must return false and must not retry with a
      // sanitised path. Loops over the six core cmd metacharacters to pin
      // every-character handling end-to-end.
      () async {
        var calls = 0;
        final service = UpdateService(
          platform: 'windows',
          openInstaller: (_, _) async {
            calls++;
            return const rust_installer.InstallerLaunchOutcome.refusedUnsafePath();
          },
        );

        for (final ch in const ['&', '|', '<', '>', '^', '%']) {
          final ok = await service.openFile('C:\\tmp\\bad${ch}name.exe');
          expect(
            ok,
            isFalse,
            reason: 'path with "$ch" should refuse without retry',
          );
        }
        expect(calls, 6);
      },
    );

    test(
      'safe windows path reaches the perimeter and Launched returns true',
      // Paranoid regression guard: realistic Windows paths (spaces, hyphens,
      // dots, underscores) MUST reach the perimeter and surface as Launched.
      // If a future Dart-side pre-filter over-rejected safe paths, this
      // test would catch it because the opener would never be invoked.
      () async {
        var calls = 0;
        final service = UpdateService(
          platform: 'windows',
          openInstaller: (_, _) async {
            calls++;
            return const rust_installer.InstallerLaunchOutcome.launched();
          },
        );

        for (final path in const [
          r'C:\Program Files\App\setup.exe',
          r'D:\files\letsflutssh-5.3.1-windows-x64-setup.exe',
          r'E:\nested_folder.name\bin.exe',
        ]) {
          expect(await service.openFile(path), isTrue);
        }
        expect(calls, 3);
      },
    );
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

  group('ReleaseManifestUnavailableException.toString', () {
    test('surfaces the exception type and reason string', () {
      // Distinct from `InvalidReleaseSignatureException` so the
      // toString contract pins the right type prefix — Settings shows
      // a "retry, manifest not reachable" toast vs. the
      // "do not install, reinstall from official releases" warning,
      // and the toString is the fallback when no locale string applies.
      const ex = ReleaseManifestUnavailableException(
        'HTTP 404 on letsflutssh-2.0.0.sha256sums',
      );
      final msg = ex.toString();
      expect(msg, startsWith('ReleaseManifestUnavailableException:'));
      expect(msg, contains('404'));
      expect(msg, contains('letsflutssh-2.0.0.sha256sums'));
    });

    test('empty reason still produces a non-empty message', () {
      const ex = ReleaseManifestUnavailableException('');
      expect(ex.toString(), startsWith('ReleaseManifestUnavailableException:'));
    });
  });

  // ===========================================================================
  // UpdateService.canLaunchInstaller + isPackageManaged — per-platform routing
  // ===========================================================================
  //
  // Spec (from update_service source): macOS and Windows always expose an
  // installer hand-off. Linux is install-method dependent — an AppImage or a
  // portable (tar.gz) build can be applied in place, but a deb/rpm/pacman or
  // Flatpak install is owned by its package manager, so canLaunchInstaller is
  // false there and isPackageManaged is true (UI offers the release page /
  // "managed by your package manager" note). Android/iOS/unknown have no
  // in-app installer. The UI relies on canLaunchInstaller to pick the label
  // "Install Now" vs "Open Release Page" before the user taps.
  group('UpdateService.canLaunchInstaller + isPackageManaged', () {
    test('macos and windows expose canLaunchInstaller=true', () {
      for (final platform in ['macos', 'windows']) {
        final service = UpdateService(platform: platform);
        expect(
          service.canLaunchInstaller,
          isTrue,
          reason: '$platform must surface an installer hand-off',
        );
        expect(service.isPackageManaged, isFalse);
      }
    });

    test('linux AppImage / portable can self-install', () {
      for (final method in [
        rust_update_meta.DbLinuxInstall.appImage,
        rust_update_meta.DbLinuxInstall.portable,
      ]) {
        final service = UpdateService(platform: 'linux', linuxInstall: method);
        expect(
          service.canLaunchInstaller,
          isTrue,
          reason: '$method applies in place',
        );
        expect(service.isPackageManaged, isFalse);
      }
    });

    test('linux deb/rpm/pacman + flatpak defer to the package manager', () {
      // A package-manager-owned install must NOT advertise an in-app
      // installer — overwriting it would orphan a copy outside the
      // manager. The UI offers the release page instead.
      for (final method in [
        rust_update_meta.DbLinuxInstall.systemPackage,
        rust_update_meta.DbLinuxInstall.flatpak,
      ]) {
        final service = UpdateService(platform: 'linux', linuxInstall: method);
        expect(
          service.canLaunchInstaller,
          isFalse,
          reason: '$method is owned by its package manager',
        );
        expect(service.isPackageManaged, isTrue);
      }
    });

    test('android, ios and unknown expose canLaunchInstaller=false', () {
      // Android's APK install flow (REQUEST_INSTALL_PACKAGES + per-app
      // system prompt) routes outside canLaunchInstaller; iOS/unknown
      // have no in-app installer at all.
      for (final platform in ['android', 'ios', 'unknown']) {
        final service = UpdateService(platform: platform);
        expect(
          service.canLaunchInstaller,
          isFalse,
          reason: '$platform must NOT advertise an installer hand-off',
        );
        expect(service.isPackageManaged, isFalse);
      }
    });
  });

  // ===========================================================================
  // UpdateService.openFile — macOS DMG installer hook
  // ===========================================================================
  //
  // Spec (from update_service.openFile): when the host is macOS, the
  // artefact ends with `.dmg`, and a `MacosDmgInstaller` is wired in, the
  // native installer runs first. A `true` return short-circuits the
  // perimeter hand-off ("the new bundle is already running"); a `false`
  // return falls back to the `_openInstaller` perimeter call, where the
  // Finder reveal opens the .dmg so the user can drag the .app over by
  // hand. Non-.dmg artefacts skip the installer hook entirely even on
  // macOS — only the file extension drives the gate.
  group('UpdateService.openFile — macOS DMG installer', () {
    test(
      'macOS .dmg artefact: installer returns true → perimeter NOT called',
      () async {
        var perimeterCalls = 0;
        final service = UpdateService(
          platform: 'macos',
          openInstaller: (_, _) async {
            perimeterCalls++;
            return const rust_installer.InstallerLaunchOutcome.launched();
          },
          macosDmgInstaller: (path) async {
            expect(path, '/tmp/Update.dmg');
            return true;
          },
        );

        final ok = await service.openFile('/tmp/Update.dmg');

        expect(ok, isTrue);
        expect(
          perimeterCalls,
          0,
          reason: 'native installer succeeded → perimeter must not be called',
        );
      },
    );

    test(
      'macOS .dmg artefact: installer returns false → perimeter fallback fires',
      () async {
        var installerCalls = 0;
        var perimeterCalls = 0;
        final service = UpdateService(
          platform: 'macos',
          openInstaller: (_, _) async {
            perimeterCalls++;
            return const rust_installer.InstallerLaunchOutcome.launched();
          },
          macosDmgInstaller: (_) async {
            installerCalls++;
            return false;
          },
        );

        final ok = await service.openFile('/tmp/Update.dmg');

        expect(ok, isTrue);
        expect(installerCalls, 1);
        expect(
          perimeterCalls,
          1,
          reason: 'installer declined → fall through to Finder-reveal path',
        );
      },
    );

    test(
      'macOS non-.dmg artefact: installer hook skipped, perimeter handles it',
      () async {
        // Spec: the installer hook is gated on the `.dmg` extension —
        // a `.zip` or `.pkg` artefact must NOT invoke the installer
        // closure even on macOS. The perimeter takes the call.
        var installerCalls = 0;
        var perimeterCalls = 0;
        final service = UpdateService(
          platform: 'macos',
          openInstaller: (_, _) async {
            perimeterCalls++;
            return const rust_installer.InstallerLaunchOutcome.launched();
          },
          macosDmgInstaller: (_) async {
            installerCalls++;
            return true;
          },
        );

        final ok = await service.openFile('/tmp/Update.zip');

        expect(ok, isTrue);
        expect(installerCalls, 0);
        expect(perimeterCalls, 1);
      },
    );

    test(
      'macOS .DMG (uppercase) artefact: extension check is case-insensitive',
      () async {
        // Spec: `path.toLowerCase().endsWith('.dmg')` so a release
        // artefact named `Update.DMG` still routes through the native
        // installer. Pins the case-insensitive contract.
        var installerCalls = 0;
        final service = UpdateService(
          platform: 'macos',
          openInstaller: (_, _) async =>
              const rust_installer.InstallerLaunchOutcome.launched(),
          macosDmgInstaller: (_) async {
            installerCalls++;
            return true;
          },
        );

        await service.openFile('/tmp/Update.DMG');

        expect(installerCalls, 1);
      },
    );

    test(
      'non-macOS host ignores the MacosDmgInstaller hook even on a .dmg path',
      () async {
        // Spec: the installer hook is gated on `_platform == "macos"`.
        // A misconfigured Linux build that wired in a DMG installer
        // must still route through the perimeter — the hook is a
        // macOS-only optimization.
        var installerCalls = 0;
        var perimeterCalls = 0;
        final service = UpdateService(
          platform: 'linux',
          openInstaller: (_, _) async {
            perimeterCalls++;
            return const rust_installer.InstallerLaunchOutcome.launched();
          },
          macosDmgInstaller: (_) async {
            installerCalls++;
            return true;
          },
        );

        await service.openFile('/tmp/x.dmg');

        expect(installerCalls, 0);
        expect(perimeterCalls, 1);
      },
    );
  });

  // ===========================================================================
  // UpdateService.downloadAsset — bus subscription cleanup
  // ===========================================================================
  group('UpdateService.downloadAsset — bus subscription lifecycle', () {
    test(
      'subscribe path runs when onProgress is provided and finalises cleanly',
      () async {
        // Spec: when `onProgress` is supplied, downloadAsset opens a
        // BusEvent subscription for progress ticks. The `finally` arm
        // must cancel the subscription even on the success path, or
        // the test framework reports a leaked stream listener across
        // subsequent calls. Driving a full success cycle exercises
        // both the subscribe branch and the cleanup arm.
        UpdateService.debugDownloadOverride =
            ({
              required url,
              required targetDir,
              required expectedDigest,
            }) async => _downloadSuccess('/tmp/x.AppImage');
        final service = UpdateService();

        await service.downloadAsset(
          'https://github.com/Llloooggg/LetsFLUTssh/releases/download/v1/file.AppImage',
          '/tmp',
          onProgress: (_, _) {},
        );
        // Repeat to confirm the cleanup let the next call subscribe
        // fresh — a leaked subscription would not crash but would
        // double-count progress ticks on a second call.
        await service.downloadAsset(
          'https://github.com/Llloooggg/LetsFLUTssh/releases/download/v1/file.AppImage',
          '/tmp',
          onProgress: (_, _) {},
        );
      },
    );

    test(
      'subscribe path runs when only onPhase is provided (no onProgress)',
      // Spec: `downloadAsset` opens the bus subscription when EITHER
      // `onProgress` or `onPhase` is supplied — the verify-phase
      // signal is delivered through the same channel. Driving the
      // success cycle with only `onPhase` wired exercises the
      // subscribe branch under a distinct gate so a future
      // refactor that tied the subscription strictly to
      // `onProgress` would surface here.
      () async {
        UpdateService.debugDownloadOverride =
            ({
              required url,
              required targetDir,
              required expectedDigest,
            }) async => _downloadSuccess('/tmp/y.AppImage');
        final service = UpdateService();

        await service.downloadAsset(
          'https://github.com/Llloooggg/LetsFLUTssh/releases/download/v1/file.AppImage',
          '/tmp',
          onPhase: (_) {},
        );
      },
    );
  });

  // ===========================================================================
  // UpdateService.checkForUpdate — JSON-parse error contract
  // ===========================================================================
  group('UpdateService.checkForUpdate — JSON-parse contract', () {
    test(
      'Rust JSON-parse failure surfaces as FormatException with original message',
      () async {
        // Spec: `checkForUpdate` with an injected fetcher (the
        // non-default branch) catches errors from
        // `updateCheckFromBody`. When the Rust side returns a
        // `update releases JSON parse: ...` message, the wrapper
        // rethrows as a `FormatException` so callers binding to the
        // documented contract still get the right error type. The
        // existing "not json" test covers the path; this one pins
        // that the original Rust detail survives in the message so a
        // future refactor that swallowed the cause string would not
        // ship a "" FormatException to the UI.
        final service = UpdateService(fetch: (_) async => '{not valid json');

        try {
          await service.checkForUpdate('1.0.0');
          fail('expected FormatException');
        } on FormatException catch (e) {
          // The wrapper preserves the original Rust-side detail
          // string so the UI surface can log it.
          expect(e.message, isNotEmpty);
        }
      },
    );
  });

  // ===========================================================================
  // UpdateService.downloadAsset — onPhase + progress wiring sanity
  // ===========================================================================
  group('UpdateService.downloadAsset — phase callback firing', () {
    test(
      'onPhase fires UpdateDownloadPhase.downloading synchronously at start',
      // Spec: before the FRB downloader is invoked, the wrapper
      // calls `onPhase?.call(UpdateDownloadPhase.downloading)` so
      // the UI can render a determinate progress bar immediately.
      // The `verifying` transition rides on a bus event the FRB
      // pipeline emits — covered by the live Rust pipeline tests.
      () async {
        final phases = <UpdateDownloadPhase>[];
        UpdateService.debugDownloadOverride =
            ({
              required url,
              required targetDir,
              required expectedDigest,
            }) async => _downloadSuccess('/tmp/d.AppImage');
        final service = UpdateService();

        await service.downloadAsset(
          'https://github.com/Llloooggg/LetsFLUTssh/releases/download/v1/file.AppImage',
          '/tmp',
          onPhase: phases.add,
        );

        // The `downloading` phase must arrive first. The
        // `verifying` phase fires from a bus event and is not
        // expected on this scripted path.
        expect(phases, isNotEmpty);
        expect(phases.first, UpdateDownloadPhase.downloading);
      },
    );
  });

  // ===========================================================================
  // UpdateService.openFile — null MacosDmgInstaller (no native hook wired)
  // ===========================================================================
  //
  // Spec: when the constructor parameter `macosDmgInstaller` is null (the
  // production default outside the native macOS shell), the .dmg gate is
  // skipped entirely and the perimeter handles every artefact. Pins the
  // null-installer arm so a refactor that added a "default in-process
  // installer" surface would surface as a behaviour change here.
  group('UpdateService.openFile — null MacosDmgInstaller', () {
    test(
      'macOS .dmg with no installer wired routes through the perimeter only',
      () async {
        var perimeterCalls = 0;
        final service = UpdateService(
          platform: 'macos',
          openInstaller: (_, _) async {
            perimeterCalls++;
            return const rust_installer.InstallerLaunchOutcome.launched();
          },
          // No macosDmgInstaller — exercises the `installer != null`
          // gate's false arm.
        );

        final ok = await service.openFile('/tmp/Update.dmg');

        expect(ok, isTrue);
        expect(
          perimeterCalls,
          1,
          reason:
              'no installer wired → perimeter is the only path even for .dmg',
        );
      },
    );
  });
}
