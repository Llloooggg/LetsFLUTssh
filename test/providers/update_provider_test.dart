import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/update/update_service.dart';
import 'package:letsflutssh/providers/update_provider.dart';
import 'package:letsflutssh/providers/version_provider.dart';
import 'package:letsflutssh/src/rust/api/app.dart' as rust_app;
import 'package:letsflutssh/src/rust/api/config.dart' as rust_config;

import '../helpers/frb_bootstrap.dart';

/// Stub UpdateService that resolves immediately with fixed results.
class _StubUpdateService extends UpdateService {
  final UpdateInfo Function(String version) onCheck;
  final String? downloadedPath;
  final Object? downloadError;

  _StubUpdateService({
    required this.onCheck,
    this.downloadedPath,
    this.downloadError,
  });

  @override
  Future<UpdateInfo> checkForUpdate(String currentVersion) async {
    return onCheck(currentVersion);
  }

  @override
  Future<String> downloadAsset(
    String url,
    String targetDir, {
    String? expectedDigest,
    void Function(int received, int total)? onProgress,
    void Function(UpdateDownloadPhase phase)? onPhase,
  }) async {
    if (downloadError != null) throw downloadError!;
    onPhase?.call(UpdateDownloadPhase.downloading);
    onProgress?.call(50, 100);
    onProgress?.call(100, 100);
    onPhase?.call(UpdateDownloadPhase.verifying);
    return downloadedPath!;
  }

  @override
  Future<bool> openFile(String path) async => false;
}

/// Build a container with an injected stub UpdateService and a fixed version.
ProviderContainer _makeContainer({
  required UpdateService service,
  String version = '1.0.0',
}) {
  final container = ProviderContainer(
    overrides: [updateServiceProvider.overrideWithValue(service)],
  );
  container.read(appVersionProvider.notifier).state = version;
  return container;
}

void _mockPathProvider(String path) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => path,
      );
}

void _clearPathProviderMock() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        null,
      );
}

/// Scope the Rust-side support-dir singleton against `dir` so the
/// stale-download cleanup (which now reads through
/// `app::instance().support_dir()`) targets the per-case temp dir
/// rather than whatever the first test in the binary pinned. The
/// reset seam is `#[cfg(any(test, debug_assertions))]`-gated — only
/// reachable from test + dev builds.
void _scopeSupportDir(String dir) {
  rust_app.appResetSupportDirForTests();
  rust_config.configStoreInit(supportDir: dir);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // UpdateInfo.compareVersions routes through `lfs_core::update_metadata`
  // — bootstrap FRB.
  setUpAll(requireFrbLoaded);

  group('UpdateState', () {
    test('default status is idle', () {
      const s = UpdateState();
      expect(s.status, UpdateStatus.idle);
      expect(s.info, isNull);
      expect(s.progress, 0);
      expect(s.downloadedPath, isNull);
      expect(s.error, isNull);
    });

    test('copyWith replaces only given fields', () {
      const s = UpdateState(status: UpdateStatus.checking, progress: 0.5);
      final s2 = s.copyWith(status: UpdateStatus.downloaded);
      expect(s2.status, UpdateStatus.downloaded);
      expect(s2.progress, 0.5); // preserved
    });

    test('copyWith can clear nullable fields with explicit null', () {
      const s = UpdateState(
        status: UpdateStatus.downloaded,
        downloadedPath: '/tmp/file',
        error: 'oops',
      );
      final s2 = s.copyWith(downloadedPath: null, error: null);
      expect(s2.downloadedPath, isNull);
      expect(s2.error, isNull);
      expect(s2.status, UpdateStatus.downloaded); // preserved
    });

    test('copyWith preserves nullable fields when not specified', () {
      const s = UpdateState(
        status: UpdateStatus.error,
        downloadedPath: '/tmp/file',
        error: 'oops',
      );
      final s2 = s.copyWith(status: UpdateStatus.idle);
      expect(s2.downloadedPath, '/tmp/file');
      expect(s2.error, 'oops');
    });

    test('isDownloadingOrVerifying is true only while fetching/verifying', () {
      // Spec: the predicate gates the update surfaces' "show progress, hide
      // action buttons" span. It must cover both the byte-fetch
      // (`downloading`) and the post-download check (`verifying`) phases —
      // `verifying` was the gap that let the dialog re-expose its buttons —
      // and exclude every other status, including `downloaded` (which hands
      // off to the installer but keeps an escape affordance).
      for (final status in UpdateStatus.values) {
        final expected =
            status == UpdateStatus.downloading ||
            status == UpdateStatus.verifying;
        expect(
          UpdateState(status: status).isDownloadingOrVerifying,
          expected,
          reason: '$status should ${expected ? '' : 'not '}be in-flight',
        );
      }
    });
  });

  group('UpdateNotifier.check()', () {
    test('transitions idle → checking → upToDate when no update', () async {
      final states = <UpdateStatus>[];
      final service = _StubUpdateService(
        onCheck: (v) => UpdateInfo(
          latestVersion: v,
          currentVersion: v,
          releaseUrl: 'https://github.com',
        ),
      );
      final container = _makeContainer(service: service, version: '1.2.0');
      addTearDown(container.dispose);

      container.listen(
        updateProvider.select((s) => s.status),
        (_, next) => states.add(next),
        fireImmediately: true,
      );

      await container.read(updateProvider.notifier).check();

      expect(states, [
        UpdateStatus.idle,
        UpdateStatus.checking,
        UpdateStatus.upToDate,
      ]);
    });

    test('transitions to updateAvailable when newer version exists', () async {
      final service = _StubUpdateService(
        onCheck: (_) => const UpdateInfo(
          latestVersion: '2.0.0',
          currentVersion: '1.0.0',
          releaseUrl: 'https://github.com',
          assetUrl: 'https://example.com/app.AppImage',
        ),
      );
      final container = _makeContainer(service: service);
      addTearDown(container.dispose);

      await container.read(updateProvider.notifier).check();

      final state = container.read(updateProvider);
      expect(state.status, UpdateStatus.updateAvailable);
      expect(state.info!.hasUpdate, isTrue);
      expect(state.info!.latestVersion, '2.0.0');
    });

    test('transitions to error when check throws', () async {
      final service = _StubUpdateService(
        onCheck: (_) => throw const HttpException('API error'),
      );
      final container = _makeContainer(service: service);
      addTearDown(container.dispose);

      await container.read(updateProvider.notifier).check();

      final state = container.read(updateProvider);
      expect(state.status, UpdateStatus.error);
      expect(state.error, isNotNull);
    });

    test('ignores second call while already checking', () async {
      var callCount = 0;
      final service = _StubUpdateService(
        onCheck: (v) {
          callCount++;
          return UpdateInfo(
            latestVersion: v,
            currentVersion: v,
            releaseUrl: 'https://github.com',
          );
        },
      );
      final container = _makeContainer(service: service);
      addTearDown(container.dispose);

      // Force checking state, then call check() — should be suppressed
      container.read(updateProvider.notifier).state = const UpdateState(
        status: UpdateStatus.checking,
      );
      await container.read(updateProvider.notifier).check();

      expect(callCount, 0);
    });
  });

  group('UpdateNotifier.download()', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('upd_test_');
      _mockPathProvider(tempDir.path);
      _scopeSupportDir(tempDir.path);
    });

    tearDown(() async {
      _clearPathProviderMock();
      await tempDir.delete(recursive: true);
    });

    test('transitions to downloaded with path on success', () async {
      final service = _StubUpdateService(
        onCheck: (_) => const UpdateInfo(
          latestVersion: '2.0.0',
          currentVersion: '1.0.0',
          releaseUrl: 'https://github.com',
          assetUrl: 'https://example.com/app.AppImage',
        ),
        downloadedPath: 'app.AppImage',
      );
      final container = _makeContainer(service: service);
      addTearDown(container.dispose);

      await container.read(updateProvider.notifier).check();
      await container.read(updateProvider.notifier).download();

      final state = container.read(updateProvider);
      expect(state.status, UpdateStatus.downloaded);
      expect(state.downloadedPath, isNotNull);
      expect(state.progress, 1.0);
    });

    test('reports download progress', () async {
      final progresses = <double>[];
      final service = _StubUpdateService(
        onCheck: (_) => const UpdateInfo(
          latestVersion: '2.0.0',
          currentVersion: '1.0.0',
          releaseUrl: 'https://github.com',
          assetUrl: 'https://example.com/app.AppImage',
        ),
        downloadedPath: 'app.AppImage',
      );
      final container = _makeContainer(service: service);
      addTearDown(container.dispose);

      await container.read(updateProvider.notifier).check();

      container.listen(
        updateProvider.select((s) => s.progress),
        (_, next) => progresses.add(next),
      );

      await container.read(updateProvider.notifier).download();

      expect(progresses, contains(0.5));
      expect(progresses.last, 1.0);
    });

    test('transitions to error when download fails', () async {
      final service = _StubUpdateService(
        onCheck: (_) => const UpdateInfo(
          latestVersion: '2.0.0',
          currentVersion: '1.0.0',
          releaseUrl: 'https://github.com',
          assetUrl: 'https://example.com/app.AppImage',
        ),
        downloadError: Exception('Network error'),
      );
      final container = _makeContainer(service: service);
      addTearDown(container.dispose);

      await container.read(updateProvider.notifier).check();
      await container.read(updateProvider.notifier).download();

      final state = container.read(updateProvider);
      expect(state.status, UpdateStatus.error);
      expect(state.error.toString(), contains('Network error'));
    });
  });

  group('UpdateNotifier.download() — no platform call', () {
    test('no-op when info is null', () async {
      final service = _StubUpdateService(onCheck: (_) => throw Exception());
      final container = _makeContainer(service: service);
      addTearDown(container.dispose);

      // State is idle — info is null, returns early before path_provider call
      await container.read(updateProvider.notifier).download();

      expect(container.read(updateProvider).status, UpdateStatus.idle);
    });

    test('no-op when already downloading', () async {
      final service = _StubUpdateService(onCheck: (_) => throw Exception());
      final container = _makeContainer(service: service);
      addTearDown(container.dispose);

      container.read(updateProvider.notifier).state = const UpdateState(
        status: UpdateStatus.downloading,
        info: UpdateInfo(
          latestVersion: '2.0.0',
          currentVersion: '1.0.0',
          releaseUrl: 'https://github.com',
          assetUrl: 'https://example.com/app.AppImage',
        ),
      );
      await container.read(updateProvider.notifier).download();

      // Status unchanged — second call suppressed before path_provider call
      expect(container.read(updateProvider).status, UpdateStatus.downloading);
    });
  });

  group('UpdateNotifier.install()', () {
    test('returns false when downloadedPath is null', () async {
      final service = _StubUpdateService(onCheck: (_) => throw Exception());
      final container = _makeContainer(service: service);
      addTearDown(container.dispose);

      final result = await container.read(updateProvider.notifier).install();
      expect(result, isFalse);
    });
  });

  group('UpdateNotifier.download() — stale file cleanup', () {
    test(
      'removes previously downloaded update file before new download',
      () async {
        final dir = await Directory.systemTemp.createTemp('update_stale');
        addTearDown(() => dir.deleteSync(recursive: true));
        _mockPathProvider(dir.path);
        addTearDown(_clearPathProviderMock);
        _scopeSupportDir(dir.path);

        // Create a stale file with the same platform suffix
        final staleFile = File(
          '${dir.path}/letsflutssh-1.0.0-linux-x64.AppImage',
        );
        await staleFile.create();
        expect(await staleFile.exists(), isTrue);

        final service = _StubUpdateService(
          onCheck: (_) => const UpdateInfo(
            latestVersion: '2.0.0',
            currentVersion: '1.0.0',
            releaseUrl: 'https://github.com',
            assetUrl:
                'https://example.com/letsflutssh-2.0.0-linux-x64.AppImage',
          ),
          downloadedPath: 'letsflutssh-2.0.0-linux-x64.AppImage',
        );
        final container = _makeContainer(service: service);
        addTearDown(container.dispose);

        await container.read(updateProvider.notifier).check();
        await container.read(updateProvider.notifier).download();

        // Stale file should be deleted before the new download
        expect(await staleFile.exists(), isFalse);
      },
    );

    test('leaves files with different suffix untouched', () async {
      final dir = await Directory.systemTemp.createTemp('update_other');
      addTearDown(() => dir.deleteSync(recursive: true));
      _mockPathProvider(dir.path);
      addTearDown(_clearPathProviderMock);
      _scopeSupportDir(dir.path);

      // Create a file with a different suffix (e.g. a .dmg while we download .exe)
      final otherFile = File(
        '${dir.path}/letsflutssh-1.0.0-macos-universal.dmg',
      );
      await otherFile.create();

      final service = _StubUpdateService(
        onCheck: (_) => const UpdateInfo(
          latestVersion: '2.0.0',
          currentVersion: '1.0.0',
          releaseUrl: 'https://github.com',
          assetUrl: 'https://example.com/letsflutssh-2.0.0-linux-x64.AppImage',
        ),
        downloadedPath: 'letsflutssh-2.0.0-linux-x64.AppImage',
      );
      final container = _makeContainer(service: service);
      addTearDown(container.dispose);

      await container.read(updateProvider.notifier).check();
      await container.read(updateProvider.notifier).download();

      // Different-suffix file should not be deleted
      expect(await otherFile.exists(), isTrue);
    });
  });

  group('UpdateNotifier.download(autoInstall: true)', () {
    test('calls install after successful download', () async {
      final dir = await Directory.systemTemp.createTemp('update_auto_install');
      addTearDown(() => dir.deleteSync(recursive: true));
      _mockPathProvider(dir.path);
      addTearDown(_clearPathProviderMock);
      _scopeSupportDir(dir.path);

      final service = _StubUpdateService(
        onCheck: (_) => const UpdateInfo(
          latestVersion: '2.0.0',
          currentVersion: '1.0.0',
          releaseUrl: 'https://github.com',
          assetUrl: 'https://example.com/app.AppImage',
        ),
        downloadedPath: 'app.AppImage',
      );
      final container = _makeContainer(service: service);
      addTearDown(container.dispose);

      await container.read(updateProvider.notifier).check();
      // Should not throw even though install will fail in test env (no real file)
      await container.read(updateProvider.notifier).download(autoInstall: true);

      // State is still downloaded (install returned false, no state change)
      final state = container.read(updateProvider);
      expect(state.status, UpdateStatus.downloaded);
      expect(state.downloadedPath, isNotNull);
    });

    test('does not call install when autoInstall is false', () async {
      final dir = await Directory.systemTemp.createTemp('update_no_auto');
      addTearDown(() => dir.deleteSync(recursive: true));
      _mockPathProvider(dir.path);
      addTearDown(_clearPathProviderMock);
      _scopeSupportDir(dir.path);

      final service = _StubUpdateService(
        onCheck: (_) => const UpdateInfo(
          latestVersion: '2.0.0',
          currentVersion: '1.0.0',
          releaseUrl: 'https://github.com',
          assetUrl: 'https://example.com/app.AppImage',
        ),
        downloadedPath: 'app.AppImage',
      );
      final container = _makeContainer(service: service);
      addTearDown(container.dispose);

      await container.read(updateProvider.notifier).check();
      await container.read(updateProvider.notifier).download();

      // Default autoInstall=false — state is downloaded, install not triggered
      expect(container.read(updateProvider).status, UpdateStatus.downloaded);
    });
  });

  group('UpdateNotifier.openReleasePage', () {
    test('returns false when there is no UpdateInfo yet', () async {
      // State starts idle with `info == null`. Pressing the "Open
      // release page" button in that state must short-circuit to
      // false instead of trying to parse a null URL.
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final ok = await container
          .read(updateProvider.notifier)
          .openReleasePage();
      expect(ok, isFalse);
    });

    test('returns false when the resolved release URL is empty', () async {
      // Pre-populate the notifier with an UpdateInfo whose
      // `releaseUrl` is empty — simulates the degenerate
      // "hasUpdate but releaseUrl missing" case a malformed
      // release payload could produce.
      final container = ProviderContainer(
        overrides: [
          updateProvider.overrideWith(
            () => _SeededUpdateNotifier(
              const UpdateState(
                status: UpdateStatus.updateAvailable,
                info: UpdateInfo(
                  currentVersion: '1.0.0',
                  latestVersion: '1.1.0',
                  releaseUrl: '',
                  assetUrl: null,
                  assetDigest: null,
                  changelog: null,
                ),
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      final ok = await container
          .read(updateProvider.notifier)
          .openReleasePage();
      expect(ok, isFalse);
    });
  });

  group('UpdateNotifier.install', () {
    test('returns false when state.downloadedPath is null (guard)', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final ok = await container.read(updateProvider.notifier).install();
      expect(ok, isFalse);
    });
  });
}

/// Riverpod notifier stand-in that seeds its initial state rather than
/// running the `check → download` round-trip. Used by the openReleasePage
/// tests above so we can hit the `state.info?.releaseUrl` branches
/// without faking a full UpdateService.
class _SeededUpdateNotifier extends UpdateNotifier {
  _SeededUpdateNotifier(this._seed);
  final UpdateState _seed;

  @override
  UpdateState build() => _seed;
}
