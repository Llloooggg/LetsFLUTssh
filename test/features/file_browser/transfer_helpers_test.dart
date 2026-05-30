import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/sftp/file_system.dart';
import 'package:letsflutssh/core/sftp/sftp_models.dart';
import 'package:letsflutssh/core/transfer/conflict_resolver.dart';
import 'package:letsflutssh/features/file_browser/transfer_helpers.dart';
import 'package:letsflutssh/providers/transfer_provider.dart';

import '../../helpers/frb_bootstrap.dart';

/// In-memory `FileSystem` stub that records the calls
/// `TransferHelpers` makes — the regression test below pins that
/// the helpers route through the generic [`FileSystem`] surface
/// rather than the SFTP-specific [`RemoteSftpFs`] shape. Until the
/// generalisation landed, calling `TransferHelpers.enqueueUpload`
/// with a non-SFTP backend (WebDAV / S3) was impossible — the
/// signature demanded a `RemoteSftpFs` the caller couldn't
/// provide, so drag-drop / paste / transfer-button on those panes
/// no-op'd silently. The test below proves the helpers now accept
/// any `FileSystem` and reach the manager.
class _RecordingFs implements FileSystem {
  final List<String> createdDirs = [];
  // Set of paths the stub treats as "already present"; consulted
  // by [`exists`]. Empty default — `enqueueUpload` skips the
  // conflict probe when no `conflictResolver` is passed, but the
  // surface stays available for future tests that exercise it.
  final Set<String> existing;

  // ignore: unused_element_parameter
  _RecordingFs({this.existing = const {}});

  @override
  Future<String> initialDir() async => '/';

  @override
  Future<List<FileEntry>> list(String path) async => const [];

  @override
  Future<void> mkdir(String path) async => createdDirs.add(path);

  @override
  Future<void> remove(String path) async {}

  @override
  Future<void> removeDir(String path) async {}

  @override
  Future<void> rename(String oldPath, String newPath) async {}

  @override
  Future<int> dirSize(String path) async => 0;

  @override
  Future<List<FlatFileLeaf>> flatWalkFiles(String root, {int maxDepth = 100}) =>
      flatWalkViaList(this, root, maxDepth: maxDepth);

  @override
  Future<bool> exists(String path) async => existing.contains(path);

  @override
  FileSystemCapabilities get capabilities => FileSystemCapabilities.objectStore;
}

/// Captures every `enqueueUpload` / `enqueueDownload` call on the
/// notifier — the assertions below grep through this list rather
/// than driving the real Rust transfer queue.
class _CapturingTransfersNotifier extends TransfersNotifier {
  final uploads = <Map<String, Object?>>[];
  final downloads = <Map<String, Object?>>[];

  @override
  TransfersState build() {
    state = const TransfersState();
    return state;
  }

  @override
  Future<String> enqueueUpload({
    required String connectionId,
    required String name,
    required String localPath,
    required String remotePath,
    int sizeBytes = 0,
  }) async {
    uploads.add({
      'connectionId': connectionId,
      'name': name,
      'localPath': localPath,
      'remotePath': remotePath,
      'sizeBytes': sizeBytes,
    });
    return 'fake-upload-${uploads.length}';
  }

  @override
  Future<String> enqueueDownload({
    required String connectionId,
    required String name,
    required String remotePath,
    required String localPath,
    int sizeBytes = 0,
  }) async {
    downloads.add({
      'connectionId': connectionId,
      'name': name,
      'remotePath': remotePath,
      'localPath': localPath,
      'sizeBytes': sizeBytes,
    });
    return 'fake-download-${downloads.length}';
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // The download-directory walk rejects unsafe SFTP-supplied entry
  // names before joining them onto the user-chosen destination. That
  // safety predicate is owned by Rust
  // (`lfs_core::path::is_safe_transfer_entry_name`, surfaced as
  // `path_is_safe_entry_name`) and is unit + property tested there —
  // it cannot run in this pure-Dart harness without Rust-lib init.
  group('TransferHelpers — generic FileSystem dispatch', () {
    test('enqueueUpload reaches the transfer manager when given a non-SFTP '
        'FileSystem (the WebDAV / S3 drag-drop path)', () async {
      final manager = _CapturingTransfersNotifier();
      final fs = _RecordingFs();
      final entry = FileEntry(
        name: 'photo.png',
        path: '/local/photo.png',
        size: 4096,
        modTime: DateTime(2026, 5, 16),
        isDir: false,
      );

      final ok = await TransferHelpers.enqueueUpload(
        manager: manager,
        remoteFs: fs,
        connectionId: 'conn-webdav-1',
        entry: entry,
        remoteDirPath: '/uploads',
        remoteCtrl: null,
      );

      expect(ok, isTrue);
      expect(manager.uploads, hasLength(1));
      expect(manager.uploads.first['connectionId'], 'conn-webdav-1');
      expect(manager.uploads.first['localPath'], '/local/photo.png');
      expect(manager.uploads.first['remotePath'], '/uploads/photo.png');
      expect(manager.uploads.first['sizeBytes'], 4096);
    });

    test(
      'enqueueDownload reaches the transfer manager with a generic '
      'FileSystem (mirrors the upload contract for the download side)',
      () async {
        final manager = _CapturingTransfersNotifier();
        final fs = _RecordingFs();
        final entry = FileEntry(
          name: 'data.csv',
          path: '/remote/data.csv',
          size: 8192,
          modTime: DateTime(2026, 5, 16),
          isDir: false,
        );

        final ok = await TransferHelpers.enqueueDownload(
          manager: manager,
          remoteFs: fs,
          connectionId: 'conn-s3-1',
          entry: entry,
          localDirPath: '/downloads',
          localCtrl: null,
        );

        expect(ok, isTrue);
        expect(manager.downloads, hasLength(1));
        expect(manager.downloads.first['connectionId'], 'conn-s3-1');
        expect(manager.downloads.first['remotePath'], '/remote/data.csv');
        expect(manager.downloads.first['sizeBytes'], 8192);
      },
    );
  });

  group('TransferHelpers — conflict resolution', () {
    // BatchConflictResolver wraps a Rust-side state registry; FRB has
    // to be loaded so the constructor + `transfer_conflict_*` shims
    // work. The conflict UI shape itself is pure Dart and lives in
    // `_resolveUploadConflict` / `_resolveDownloadConflict`.
    setUpAll(requireFrbLoaded);

    FileEntry mkEntry(String name, {int size = 100}) => FileEntry(
      name: name,
      path: '/local/$name',
      size: size,
      modTime: DateTime(2026, 5, 16),
      isDir: false,
    );

    test('upload-conflict skip → returns false, no enqueue', () async {
      // Spec: when the resolver returns skip, the helper must
      // short-circuit before touching the transfer manager. A regression
      // would silently overwrite the remote file the user chose to keep.
      final manager = _CapturingTransfersNotifier();
      final fs = _RecordingFs(existing: {'/uploads/dup.txt'});
      final resolver = BatchConflictResolver(
        (path, {bool isRemote = false}) async =>
            const ConflictDecision(ConflictAction.skip),
      );
      addTearDown(resolver.dispose);

      final ok = await TransferHelpers.enqueueUpload(
        manager: manager,
        remoteFs: fs,
        connectionId: 'conn-1',
        entry: mkEntry('dup.txt'),
        remoteDirPath: '/uploads',
        remoteCtrl: null,
        conflictResolver: resolver,
      );

      expect(ok, isFalse);
      expect(manager.uploads, isEmpty);
    });

    test('upload-conflict cancel → returns false, no enqueue', () async {
      final manager = _CapturingTransfersNotifier();
      final fs = _RecordingFs(existing: {'/uploads/dup.txt'});
      final resolver = BatchConflictResolver(
        (path, {bool isRemote = false}) async =>
            const ConflictDecision(ConflictAction.cancel),
      );
      addTearDown(resolver.dispose);

      final ok = await TransferHelpers.enqueueUpload(
        manager: manager,
        remoteFs: fs,
        connectionId: 'conn-1',
        entry: mkEntry('dup.txt'),
        remoteDirPath: '/uploads',
        remoteCtrl: null,
        conflictResolver: resolver,
      );

      expect(ok, isFalse);
      expect(manager.uploads, isEmpty);
    });

    test('upload-conflict replace → enqueue with original path', () async {
      final manager = _CapturingTransfersNotifier();
      final fs = _RecordingFs(existing: {'/uploads/dup.txt'});
      final resolver = BatchConflictResolver(
        (path, {bool isRemote = false}) async =>
            const ConflictDecision(ConflictAction.replace),
      );
      addTearDown(resolver.dispose);

      final ok = await TransferHelpers.enqueueUpload(
        manager: manager,
        remoteFs: fs,
        connectionId: 'conn-1',
        entry: mkEntry('dup.txt'),
        remoteDirPath: '/uploads',
        remoteCtrl: null,
        conflictResolver: resolver,
      );

      expect(ok, isTrue);
      expect(manager.uploads, hasLength(1));
      expect(manager.uploads.first['remotePath'], '/uploads/dup.txt');
    });

    test('upload-conflict keepBoth → enqueue with a renamed sibling', () async {
      // Spec: keepBoth walks `uniqueSiblingName` against `fs.exists` to
      // pick the next free name. The original collides; the resolver
      // chooses keepBoth; the enqueued path must NOT be the original.
      final manager = _CapturingTransfersNotifier();
      final fs = _RecordingFs(existing: {'/uploads/dup.txt'});
      final resolver = BatchConflictResolver(
        (path, {bool isRemote = false}) async =>
            const ConflictDecision(ConflictAction.keepBoth),
      );
      addTearDown(resolver.dispose);

      final ok = await TransferHelpers.enqueueUpload(
        manager: manager,
        remoteFs: fs,
        connectionId: 'conn-1',
        entry: mkEntry('dup.txt'),
        remoteDirPath: '/uploads',
        remoteCtrl: null,
        conflictResolver: resolver,
      );

      expect(ok, isTrue);
      expect(manager.uploads, hasLength(1));
      // Renamed: starts with `/uploads/dup` but is not the colliding
      // path. The exact suffix is owned by `uniqueSiblingName` and
      // tested separately.
      final remote = manager.uploads.first['remotePath']! as String;
      expect(remote, startsWith('/uploads/dup'));
      expect(remote, isNot(equals('/uploads/dup.txt')));
    });

    test('download-conflict skip on a non-existent target → still enqueues '
        '(no collision → resolver bypassed)', () async {
      // Spec: `_resolveDownloadConflict` calls `_snapshotLocal` first
      // — when the path doesn't exist (FRB returns null), the helper
      // returns the target immediately and never asks the resolver.
      // A regression that consulted the resolver for fresh-target
      // downloads would force a "skip / keep / replace" dialog the
      // user never needed to see.
      final manager = _CapturingTransfersNotifier();
      final fs = _RecordingFs();
      var resolverCalls = 0;
      final resolver = BatchConflictResolver((
        path, {
        bool isRemote = false,
      }) async {
        resolverCalls++;
        return const ConflictDecision(ConflictAction.skip);
      });
      addTearDown(resolver.dispose);

      final entry = FileEntry(
        name: 'fresh-remote.bin',
        path: '/remote/fresh-remote.bin',
        size: 256,
        modTime: DateTime(2026, 5, 16),
        isDir: false,
      );
      // Use a /tmp path that won't exist — `_snapshotLocal` returns
      // null and the helper bypasses the resolver.
      final ok = await TransferHelpers.enqueueDownload(
        manager: manager,
        remoteFs: fs,
        connectionId: 'conn-1',
        entry: entry,
        localDirPath:
            '/tmp/letsflutssh-test-${DateTime.now().microsecondsSinceEpoch}',
        localCtrl: null,
        conflictResolver: resolver,
      );

      expect(ok, isTrue);
      expect(resolverCalls, 0, reason: 'fresh local target → no prompt needed');
      expect(manager.downloads, hasLength(1));
    });

    test('upload of a non-dir entry returns true on enqueue (single-task '
        'path)', () async {
      // Spec: `enqueueUpload` returns `true` whenever it routes through
      // the single-file path and the manager accepted the task. The
      // boolean is the caller's "did anything land?" signal — the
      // drag-drop overlay uses it to decide whether to show a toast.
      final manager = _CapturingTransfersNotifier();
      final fs = _RecordingFs();
      final entry = FileEntry(
        name: 'readme.md',
        path: '/local/readme.md',
        size: 64,
        modTime: DateTime(2026, 5, 16),
        isDir: false,
      );

      final ok = await TransferHelpers.enqueueUpload(
        manager: manager,
        remoteFs: fs,
        connectionId: 'conn-1',
        entry: entry,
        remoteDirPath: '/r',
        remoteCtrl: null,
      );

      expect(ok, isTrue);
      // Default size on the captured payload matches what the entry
      // carried — `enqueueUpload` forwards `entry.size` verbatim.
      expect(manager.uploads.single['sizeBytes'], 64);
      expect(manager.uploads.single['name'], 'readme.md');
    });

    test('upload with no collision → resolver is bypassed, original path '
        'lands', () async {
      // Spec: `_resolveUploadConflict` early-returns the target when
      // `fs.exists(target)` is false, so the resolver is never
      // consulted. Surfaces a non-trivial branch: the conflict
      // resolver is wired but the path is free.
      final manager = _CapturingTransfersNotifier();
      final fs = _RecordingFs(); // empty `existing` → no collision
      var resolverCalls = 0;
      final resolver = BatchConflictResolver((
        path, {
        bool isRemote = false,
      }) async {
        resolverCalls++;
        return const ConflictDecision(ConflictAction.skip);
      });
      addTearDown(resolver.dispose);

      final ok = await TransferHelpers.enqueueUpload(
        manager: manager,
        remoteFs: fs,
        connectionId: 'conn-1',
        entry: mkEntry('fresh.txt'),
        remoteDirPath: '/uploads',
        remoteCtrl: null,
        conflictResolver: resolver,
      );

      expect(ok, isTrue);
      expect(resolverCalls, 0, reason: 'no collision → no prompt');
      expect(manager.uploads.first['remotePath'], '/uploads/fresh.txt');
    });

    test(
      'upload-conflict cached "apply to all" carries the first decision across '
      'a multi-entry batch without re-prompting',
      () async {
        // Spec: BatchConflictResolver caches the user's first
        // applyToAll decision in the Rust registry; subsequent calls
        // inside the same batch must NOT re-invoke the prompt. Pin the
        // contract that drives the "replace all" UX — re-prompting on
        // every collision after the user opted in would be the
        // user-visible regression.
        final manager = _CapturingTransfersNotifier();
        final fs = _RecordingFs(existing: {'/uploads/a.txt', '/uploads/b.txt'});
        var promptCalls = 0;
        final resolver = BatchConflictResolver((
          path, {
          bool isRemote = false,
        }) async {
          promptCalls++;
          return const ConflictDecision(
            ConflictAction.replace,
            applyToAll: true,
          );
        });
        addTearDown(resolver.dispose);

        final okA = await TransferHelpers.enqueueUpload(
          manager: manager,
          remoteFs: fs,
          connectionId: 'conn-1',
          entry: mkEntry('a.txt'),
          remoteDirPath: '/uploads',
          remoteCtrl: null,
          conflictResolver: resolver,
        );
        final okB = await TransferHelpers.enqueueUpload(
          manager: manager,
          remoteFs: fs,
          connectionId: 'conn-1',
          entry: mkEntry('b.txt'),
          remoteDirPath: '/uploads',
          remoteCtrl: null,
          conflictResolver: resolver,
        );

        expect(okA, isTrue);
        expect(okB, isTrue);
        expect(manager.uploads, hasLength(2));
        // First call prompts; second hits the cache and bypasses it.
        expect(promptCalls, 1);
      },
    );

    test(
      'cancelled resolver short-circuits every subsequent enqueueUpload — no '
      'prompt, no manager dispatch',
      () async {
        // Spec: once the user cancels the batch, `BatchConflictResolver`
        // sets the registry flag; `_resolveUploadConflict` reads it as
        // `ConflictAction.cancel` and returns null without prompting.
        // The helper short-circuits before reaching the manager.
        final manager = _CapturingTransfersNotifier();
        final fs = _RecordingFs(existing: {'/uploads/x.txt'});
        var promptCalls = 0;
        final resolver = BatchConflictResolver((
          path, {
          bool isRemote = false,
        }) async {
          promptCalls++;
          return const ConflictDecision(
            ConflictAction.cancel,
            applyToAll: true,
          );
        });
        addTearDown(resolver.dispose);

        final okFirst = await TransferHelpers.enqueueUpload(
          manager: manager,
          remoteFs: fs,
          connectionId: 'conn-1',
          entry: mkEntry('x.txt'),
          remoteDirPath: '/uploads',
          remoteCtrl: null,
          conflictResolver: resolver,
        );
        expect(okFirst, isFalse);
        expect(resolver.isCancelled, isTrue);

        // A second collision after cancel must not re-prompt and must
        // not enqueue — pinning the "batch is dead" contract.
        final okSecond = await TransferHelpers.enqueueUpload(
          manager: manager,
          remoteFs: fs,
          connectionId: 'conn-1',
          entry: mkEntry('x.txt'),
          remoteDirPath: '/uploads',
          remoteCtrl: null,
          conflictResolver: resolver,
        );
        expect(okSecond, isFalse);
        expect(promptCalls, 1, reason: 'cancel sticks — no re-prompt');
        expect(manager.uploads, isEmpty);
      },
    );

    test('download-conflict skip on an existing local file → returns false and '
        'never enqueues', () async {
      // Spec: `_resolveDownloadConflict` calls `_snapshotLocal` which
      // FRB-stats the path. When the target exists (we created the
      // file in /tmp), the resolver runs and returning skip must
      // short-circuit before the manager sees the task.
      final manager = _CapturingTransfersNotifier();
      final fs = _RecordingFs();
      final resolver = BatchConflictResolver(
        (path, {bool isRemote = false}) async =>
            const ConflictDecision(ConflictAction.skip),
      );
      addTearDown(resolver.dispose);

      // Create a real local file the snapshot probe will find. The
      // FRB symlink-stat call walks Rust's `std::fs::symlink_metadata`,
      // so a touch on disk is the cheapest way to drive the
      // "existing target" branch without faking the FRB layer.
      final tmpDir = await Directory.systemTemp.createTemp(
        'lfs-transfer-helpers-',
      );
      addTearDown(() async {
        if (await tmpDir.exists()) {
          await tmpDir.delete(recursive: true);
        }
      });
      final existingFile = File('${tmpDir.path}/collide.bin');
      await existingFile.writeAsBytes(const [1, 2, 3]);

      final entry = FileEntry(
        name: 'collide.bin',
        path: '/remote/collide.bin',
        size: 16,
        modTime: DateTime(2026, 5, 16),
        isDir: false,
      );
      final ok = await TransferHelpers.enqueueDownload(
        manager: manager,
        remoteFs: fs,
        connectionId: 'conn-1',
        entry: entry,
        localDirPath: tmpDir.path,
        localCtrl: null,
        conflictResolver: resolver,
      );

      expect(ok, isFalse);
      expect(manager.downloads, isEmpty);
    });

    test(
      'download-conflict on existing local symlink target is hard-rejected — '
      'no resolver prompt, no enqueue, the symlinked target is never '
      'overwritten via the link',
      () async {
        // Spec: `_resolveDownloadConflict` checks the snapshot's
        // isSymlink flag BEFORE invoking the resolver. The symlink
        // arm short-circuits with a logged warning and returns
        // null so the helper bails — without this, a hostile
        // pre-existing symlink at `<dst>/x` would resolve into
        // /etc and the SFTP download would silently overwrite
        // outside the user's chosen directory.
        if (Platform.isWindows) return;
        final manager = _CapturingTransfersNotifier();
        final fs = _RecordingFs();
        var resolverCalls = 0;
        final resolver = BatchConflictResolver((
          path, {
          bool isRemote = false,
        }) async {
          resolverCalls++;
          return const ConflictDecision(ConflictAction.replace);
        });
        addTearDown(resolver.dispose);

        final tmpDir = await Directory.systemTemp.createTemp(
          'lfs-transfer-helpers-symlink-',
        );
        addTearDown(() async {
          if (await tmpDir.exists()) {
            await tmpDir.delete(recursive: true);
          }
        });
        // A real symlink target outside `tmpDir` — what a hostile
        // pre-existing link could otherwise redirect the download
        // into.
        final outside = File('${tmpDir.path}/outside.bin')
          ..writeAsBytesSync(const [9, 9, 9]);
        final linkPath = '${tmpDir.path}/link.bin';
        Link(linkPath).createSync(outside.path);

        final entry = FileEntry(
          name: 'link.bin',
          path: '/remote/link.bin',
          size: 0,
          modTime: DateTime(2026, 5, 16),
          isDir: false,
        );
        final ok = await TransferHelpers.enqueueDownload(
          manager: manager,
          remoteFs: fs,
          connectionId: 'conn-1',
          entry: entry,
          localDirPath: tmpDir.path,
          localCtrl: null,
          conflictResolver: resolver,
        );

        expect(ok, isFalse);
        expect(resolverCalls, 0, reason: 'symlink check fires before prompt');
        expect(manager.downloads, isEmpty);
        // The link target file outside is untouched.
        expect(outside.readAsBytesSync(), const [9, 9, 9]);
      },
    );

    test('download-conflict replace path detects a mid-prompt target change '
        'and aborts the enqueue — the second snapshot does not match the '
        'first so the helper refuses to overwrite', () async {
      // Spec: `_resolveDownloadConflict.replace` arm re-snapshots
      // the local target after the user confirms. When size /
      // mtime / type drifted between the probe and the confirm
      // (TOCTOU race window where a different process replaced
      // the file), the helper aborts without enqueueing. Pin
      // the safety contract — a regression that skipped the
      // re-snapshot would let the download overwrite a freshly
      // written file the user did not intend to clobber.
      if (Platform.isWindows) return;
      final manager = _CapturingTransfersNotifier();
      final fs = _RecordingFs();
      final tmpDir = await Directory.systemTemp.createTemp(
        'lfs-transfer-helpers-toctou-',
      );
      addTearDown(() async {
        if (await tmpDir.exists()) {
          await tmpDir.delete(recursive: true);
        }
      });
      final existing = File('${tmpDir.path}/race.bin');
      await existing.writeAsBytes(const [1, 2, 3]);

      // The resolver mutates the file before returning Replace.
      // `_resolveDownloadConflict` re-snapshots after the resolver
      // returns; the new (larger + later-mtime) file fails the
      // `_localSnapshotsMatch` check.
      final resolver = BatchConflictResolver((
        path, {
        bool isRemote = false,
      }) async {
        // Race window — overwrite with a larger payload + bump
        // mtime so the size or mtime differ from the pre-prompt
        // snapshot.
        await existing.writeAsBytes(const [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
        // Drift the mtime explicitly — relying on writeAsBytes
        // landing in a new nanosecond grain is flaky on tmpfs.
        final later = DateTime.now().add(const Duration(seconds: 5));
        await existing.setLastModified(later);
        return const ConflictDecision(ConflictAction.replace);
      });
      addTearDown(resolver.dispose);

      final entry = FileEntry(
        name: 'race.bin',
        path: '/remote/race.bin',
        size: 16,
        modTime: DateTime(2026, 5, 16),
        isDir: false,
      );
      final ok = await TransferHelpers.enqueueDownload(
        manager: manager,
        remoteFs: fs,
        connectionId: 'conn-1',
        entry: entry,
        localDirPath: tmpDir.path,
        localCtrl: null,
        conflictResolver: resolver,
      );

      expect(ok, isFalse);
      expect(manager.downloads, isEmpty);
    });

    test('enqueueDownload with no conflictResolver forwards the original '
        'localPath untouched — no resolver = no rename even when the file '
        'exists, the caller is on the hook for the overwrite policy', () async {
      // Spec: `enqueueDownload` consults the resolver ONLY when one
      // is provided; the no-resolver branch trusts the caller's
      // path verbatim. Pinning the unconditional-overwrite contract
      // — the SCP-style "drag drop without dialog" path relies on
      // this to land bytes at the picked target without surfacing
      // a prompt. A regression that injected an implicit resolver
      // would block silent drops on collisions.
      final manager = _CapturingTransfersNotifier();
      final fs = _RecordingFs();
      final tmpDir = await Directory.systemTemp.createTemp(
        'lfs-transfer-helpers-noresolver-',
      );
      addTearDown(() async {
        if (await tmpDir.exists()) {
          await tmpDir.delete(recursive: true);
        }
      });
      // Pre-existing local file — a regression that injected a
      // resolver would short-circuit here, the no-resolver branch
      // ignores it.
      final existing = File('${tmpDir.path}/dup.bin');
      await existing.writeAsBytes(const [0, 0, 0]);

      final entry = FileEntry(
        name: 'dup.bin',
        path: '/remote/dup.bin',
        size: 16,
        modTime: DateTime(2026, 5, 16),
        isDir: false,
      );
      final ok = await TransferHelpers.enqueueDownload(
        manager: manager,
        remoteFs: fs,
        connectionId: 'conn-1',
        entry: entry,
        localDirPath: tmpDir.path,
        localCtrl: null,
        // intentionally no conflictResolver
      );

      expect(ok, isTrue);
      expect(manager.downloads, hasLength(1));
      // Original local path landed verbatim — no rename, no skip.
      expect(manager.downloads.first['localPath'], '${tmpDir.path}/dup.bin');
    });
  });
}
