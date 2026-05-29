/// Real-DB integration tests for the production [SessionMutator] and
/// the [sessionsWorkspaceStreamProvider] data flow.
///
/// The unit layer (`test/providers/session_provider_test.dart`) drives
/// a [FakeSessionNotifier] that swaps out BOTH the workspace stream and
/// the mutator, so it never exercises the real FRB path: the
/// `sessions_registry_*` reload/snapshot read, the `db_sessions_*` /
/// `db_folders_*` writes, the `BusEvent::SessionsChanged` round-trip
/// that re-flows the stream, or undo/redo's `db_sessions_restore_snapshot`.
/// These tests boot an unlocked in-memory DB, drive the REAL mutator,
/// and assert against the REAL workspace snapshot the stream re-emits
/// after each Rust-published bus tick.
///
/// Tagged `frb_global_store`: the in-memory DB is process-global (one
/// Rust `AppState` shared by every parallel test isolate), and these
/// tests both wipe it between cases and assert exact snapshot contents
/// — so they can't share the parallel pass with the other FRB tests
/// that insert their own sessions. The Makefile runs each tagged file
/// in its own `flutter test` process. See dart_test.yaml.
@Tags(['frb_global_store'])
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/session/session.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/providers/session_provider.dart';
import 'package:letsflutssh/src/rust/api/app.dart' as rust_app;
import 'package:letsflutssh/src/rust/api/db.dart' as rust_db;

import '../helpers/frb_bootstrap.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await requireFrbLoaded();
    await rust_app.dbInit(path: ':memory:', key: const []);
  });

  tearDownAll(() async {
    await rust_app.dbClose();
  });

  // Each test starts from an empty workspace. The DB is process-global,
  // so without this wipe a leftover row from a prior case would skew
  // the exact-count assertions.
  setUp(() async {
    await rust_db.dbSessionsDeleteAll();
    await rust_db.dbFoldersDeleteAll();
  });

  Session makeSession({
    required String id,
    String label = 'Test',
    String folder = '',
    String host = '10.0.0.1',
    int port = 22,
    String user = 'root',
    SessionAuth auth = const SessionAuth(),
  }) {
    return Session(
      id: id,
      label: label,
      folder: folder,
      server: ServerAddress(host: host, port: port, user: user),
      auth: auth,
    );
  }

  ProviderContainer makeContainer() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    // Pin a listener so the StreamProvider stays subscribed (and its
    // AppBus subscription alive) for the whole test — `.future` alone
    // doesn't retain it.
    c.listen<AsyncValue<SessionWorkspaceSnapshot>>(
      sessionsWorkspaceStreamProvider,
      (_, _) {},
      fireImmediately: true,
    );
    return c;
  }

  /// Wait until the workspace stream emits a snapshot satisfying
  /// [predicate], or time out. Robust to the enqueue→tick gap: a
  /// stale current snapshot fails the predicate and we wait for the
  /// next `SessionsChanged`-driven emission; an already-arrived tick
  /// satisfies it immediately via `fireImmediately`.
  Future<SessionWorkspaceSnapshot> waitForSnapshot(
    ProviderContainer c,
    bool Function(SessionWorkspaceSnapshot) predicate, {
    Duration timeout = const Duration(seconds: 5),
  }) {
    final completer = Completer<SessionWorkspaceSnapshot>();
    final sub = c.listen<AsyncValue<SessionWorkspaceSnapshot>>(
      sessionsWorkspaceStreamProvider,
      (_, next) {
        if (!next.hasValue || completer.isCompleted) return;
        final value = next.value as SessionWorkspaceSnapshot;
        if (predicate(value)) completer.complete(value);
      },
      fireImmediately: true,
    );
    return completer.future.timeout(timeout).whenComplete(sub.close);
  }

  group('SessionMutator CRUD against a real DB', () {
    test('add persists a session and the stream re-emits it', () async {
      final c = makeContainer();
      await c
          .read(sessionMutatorProvider)
          .add(
            makeSession(
              id: 's1',
              label: 'Alpha',
              host: '1.2.3.4',
              user: 'admin',
            ),
          );
      final snap = await waitForSnapshot(
        c,
        (s) => s.sessions.any((x) => x.id == 's1'),
      );
      final s = snap.sessions.firstWhere((x) => x.id == 's1');
      expect(s.label, 'Alpha');
      expect(s.host, '1.2.3.4');
      expect(s.user, 'admin');
    });

    test('add rejects an invalid host before touching the DB', () async {
      final c = makeContainer();
      await expectLater(
        c.read(sessionMutatorProvider).add(makeSession(id: 'bad', host: '')),
        throwsArgumentError,
      );
    });

    test('update changes persisted fields', () async {
      final c = makeContainer();
      final mutator = c.read(sessionMutatorProvider);
      await mutator.add(makeSession(id: 's1', label: 'Original'));
      await waitForSnapshot(c, (s) => s.sessions.any((x) => x.id == 's1'));
      await mutator.update(makeSession(id: 's1', label: 'Renamed'));
      final snap = await waitForSnapshot(
        c,
        (s) => s.sessions.any((x) => x.id == 's1' && x.label == 'Renamed'),
      );
      expect(snap.sessions.single.label, 'Renamed');
    });

    test('update of an absent session throws', () async {
      final c = makeContainer();
      await waitForSnapshot(c, (_) => true);
      await expectLater(
        c.read(sessionMutatorProvider).update(makeSession(id: 'ghost')),
        throwsArgumentError,
      );
    });

    test('updatePartial stores the password secret flag', () async {
      final c = makeContainer();
      final mutator = c.read(sessionMutatorProvider);
      await mutator.add(makeSession(id: 's1'));
      await waitForSnapshot(c, (s) => s.sessions.any((x) => x.id == 's1'));
      await mutator.updatePartial(
        makeSession(
          id: 's1',
          auth: const SessionAuth(password: 'hunter2'),
        ),
        passwordDirty: true,
      );
      final snap = await waitForSnapshot(
        c,
        (s) => s.sessions.any((x) => x.id == 's1' && x.auth.hasStoredPassword),
      );
      expect(snap.sessions.single.auth.hasStoredPassword, isTrue);
    });

    test('delete removes one session, leaving the rest', () async {
      final c = makeContainer();
      final mutator = c.read(sessionMutatorProvider);
      await mutator.add(makeSession(id: 's1'));
      await mutator.add(makeSession(id: 's2'));
      await waitForSnapshot(c, (s) => s.sessions.length == 2);
      await mutator.delete('s1');
      final snap = await waitForSnapshot(c, (s) => s.sessions.length == 1);
      expect(snap.sessions.single.id, 's2');
    });

    test('deleteMultiple removes the named set', () async {
      final c = makeContainer();
      final mutator = c.read(sessionMutatorProvider);
      await mutator.add(makeSession(id: 's1'));
      await mutator.add(makeSession(id: 's2'));
      await mutator.add(makeSession(id: 's3'));
      await waitForSnapshot(c, (s) => s.sessions.length == 3);
      await mutator.deleteMultiple({'s1', 's3'});
      final snap = await waitForSnapshot(c, (s) => s.sessions.length == 1);
      expect(snap.sessions.single.id, 's2');
    });

    test('deleteAll empties sessions and folders', () async {
      final c = makeContainer();
      final mutator = c.read(sessionMutatorProvider);
      await mutator.add(makeSession(id: 's1', folder: 'Work'));
      await mutator.addEmptyFolder('Empty');
      await waitForSnapshot(
        c,
        (s) => s.sessions.isNotEmpty && s.emptyFolders.contains('Empty'),
      );
      await mutator.deleteAll();
      final snap = await waitForSnapshot(
        c,
        (s) => s.sessions.isEmpty && s.emptyFolders.isEmpty,
      );
      expect(snap.sessions, isEmpty);
      expect(snap.emptyFolders, isEmpty);
    });

    test('duplicate creates a distinct copy in the target folder', () async {
      final c = makeContainer();
      final mutator = c.read(sessionMutatorProvider);
      await mutator.add(makeSession(id: 's1', label: 'Src', folder: 'A'));
      await waitForSnapshot(c, (s) => s.sessions.any((x) => x.id == 's1'));
      final copy = await mutator.duplicate('s1', targetFolder: 'B');
      expect(copy.id, isNot('s1'));
      expect(copy.folder, 'B');
      final snap = await waitForSnapshot(c, (s) => s.sessions.length == 2);
      expect(snap.sessions.map((s) => s.folder), containsAll(['A', 'B']));
    });

    test('duplicate of an absent session throws', () async {
      final c = makeContainer();
      await waitForSnapshot(c, (_) => true);
      await expectLater(
        c.read(sessionMutatorProvider).duplicate('ghost'),
        throwsArgumentError,
      );
    });
  });

  group('SessionMutator folder operations against a real DB', () {
    test('addEmptyFolder materialises a folder with no session', () async {
      final c = makeContainer();
      await c.read(sessionMutatorProvider).addEmptyFolder('Staging');
      final snap = await waitForSnapshot(
        c,
        (s) => s.emptyFolders.contains('Staging'),
      );
      expect(snap.emptyFolders, contains('Staging'));
      expect(snap.sessions, isEmpty);
    });

    test('toggleFolderCollapsed flips the collapsed set', () async {
      final c = makeContainer();
      final mutator = c.read(sessionMutatorProvider);
      await mutator.add(makeSession(id: 's1', folder: 'Group'));
      await waitForSnapshot(c, (s) => s.folderMap.isNotEmpty);
      await mutator.toggleFolderCollapsed('Group');
      final collapsed = await waitForSnapshot(
        c,
        (s) => s.collapsedFolders.contains('Group'),
      );
      expect(collapsed.collapsedFolders, contains('Group'));
      await mutator.toggleFolderCollapsed('Group');
      final expanded = await waitForSnapshot(
        c,
        (s) => !s.collapsedFolders.contains('Group'),
      );
      expect(expanded.collapsedFolders, isNot(contains('Group')));
    });

    test('renameFolder moves the sessions under it', () async {
      final c = makeContainer();
      final mutator = c.read(sessionMutatorProvider);
      await mutator.add(makeSession(id: 's1', folder: 'Old'));
      await mutator.add(makeSession(id: 's2', folder: 'Old/Sub'));
      await waitForSnapshot(c, (s) => s.sessions.length == 2);
      await mutator.renameFolder('Old', 'New');
      final snap = await waitForSnapshot(
        c,
        (s) => s.sessions.every((x) => x.folder.startsWith('New')),
      );
      expect(snap.sessions.map((s) => s.folder).toSet(), {'New', 'New/Sub'});
    });

    test(
      'deleteFolder removes the folder and its contained sessions',
      () async {
        final c = makeContainer();
        final mutator = c.read(sessionMutatorProvider);
        await mutator.add(makeSession(id: 's1', folder: 'Doomed'));
        await mutator.add(makeSession(id: 's2', folder: 'Doomed/Deep'));
        await mutator.add(makeSession(id: 's3', folder: 'Keep'));
        await waitForSnapshot(c, (s) => s.sessions.length == 3);
        await mutator.deleteFolder('Doomed');
        final snap = await waitForSnapshot(c, (s) => s.sessions.length == 1);
        expect(snap.sessions.single.id, 's3');
      },
    );

    test('moveSession relocates one session to another folder', () async {
      final c = makeContainer();
      final mutator = c.read(sessionMutatorProvider);
      await mutator.add(makeSession(id: 's1', folder: 'From'));
      await waitForSnapshot(c, (s) => s.sessions.any((x) => x.id == 's1'));
      await mutator.moveSession('s1', 'To');
      final snap = await waitForSnapshot(
        c,
        (s) => s.sessions.any((x) => x.id == 's1' && x.folder == 'To'),
      );
      expect(snap.sessions.single.folder, 'To');
    });

    test('moveMultiple relocates several sessions at once', () async {
      final c = makeContainer();
      final mutator = c.read(sessionMutatorProvider);
      await mutator.add(makeSession(id: 's1', folder: 'From'));
      await mutator.add(makeSession(id: 's2', folder: 'From'));
      await mutator.add(makeSession(id: 's3', folder: 'Stay'));
      await waitForSnapshot(c, (s) => s.sessions.length == 3);
      await mutator.moveMultiple({'s1', 's2'}, 'Dest');
      final snap = await waitForSnapshot(
        c,
        (s) => s.sessions.where((x) => x.folder == 'Dest').length == 2,
      );
      expect(snap.sessions.firstWhere((x) => x.id == 's3').folder, 'Stay');
    });

    test('moveFolder reparents by renaming the path', () async {
      final c = makeContainer();
      final mutator = c.read(sessionMutatorProvider);
      await mutator.add(makeSession(id: 's1', folder: 'Top'));
      await waitForSnapshot(c, (s) => s.sessions.any((x) => x.id == 's1'));
      await mutator.moveFolder('Top', 'Parent');
      final snap = await waitForSnapshot(
        c,
        (s) => s.sessions.any((x) => x.folder == 'Parent/Top'),
      );
      expect(snap.sessions.single.folder, 'Parent/Top');
    });

    test('duplicateFolder deep-copies the tree under a new root', () async {
      final c = makeContainer();
      final mutator = c.read(sessionMutatorProvider);
      await mutator.add(makeSession(id: 's1', folder: 'Proj'));
      await mutator.add(makeSession(id: 's2', folder: 'Proj/Web'));
      await mutator.addEmptyFolder('Proj/Empty');
      await waitForSnapshot(
        c,
        (s) => s.sessions.length == 2 && s.emptyFolders.contains('Proj/Empty'),
      );
      await mutator.duplicateFolder('Proj', '');
      // Source name collides at root → the copy lands under "Proj (1)".
      // `duplicateFolder` has fully completed by now (every copy is in
      // the DB), so wait for the stable final snapshot — both copied
      // sessions present — not an intermediate per-copy emission.
      final snap = await waitForSnapshot(
        c,
        (s) =>
            s.sessions.where((x) => x.folder.startsWith('Proj (1)')).length ==
            2,
      );
      final copiedFolders = snap.sessions
          .where((x) => x.folder.startsWith('Proj (1)'))
          .map((x) => x.folder)
          .toSet();
      expect(copiedFolders, {'Proj (1)', 'Proj (1)/Web'});
      expect(snap.emptyFolders, contains('Proj (1)/Empty'));
    });
  });

  group('SessionMutator undo/redo against a real DB', () {
    test('undo restores a deleted session, redo deletes it again', () async {
      final c = makeContainer();
      final mutator = c.read(sessionMutatorProvider);
      await mutator.add(makeSession(id: 's1', label: 'Recoverable'));
      await waitForSnapshot(c, (s) => s.sessions.any((x) => x.id == 's1'));
      await mutator.delete('s1');
      await waitForSnapshot(c, (s) => s.sessions.isEmpty);

      expect(mutator.canUndo, isTrue);
      final undone = await mutator.undo();
      expect(undone, isTrue);
      final restored = await waitForSnapshot(
        c,
        (s) => s.sessions.any((x) => x.id == 's1'),
      );
      expect(restored.sessions.single.label, 'Recoverable');

      expect(mutator.canRedo, isTrue);
      final redone = await mutator.redo();
      expect(redone, isTrue);
      final gone = await waitForSnapshot(c, (s) => s.sessions.isEmpty);
      expect(gone.sessions, isEmpty);
    });

    test('undo with no history returns false', () async {
      final c = makeContainer();
      await waitForSnapshot(c, (_) => true);
      expect(await c.read(sessionMutatorProvider).undo(), isFalse);
    });
  });

  group('SessionMutator read accessors via the Rust registry', () {
    test(
      'folders / byFolder / countSessionsInFolder hit the registry',
      () async {
        final c = makeContainer();
        final mutator = c.read(sessionMutatorProvider);
        await mutator.add(makeSession(id: 's1', folder: 'A'));
        await mutator.add(makeSession(id: 's2', folder: 'A/Sub'));
        await mutator.add(makeSession(id: 's3', folder: 'B'));
        await waitForSnapshot(c, (s) => s.sessions.length == 3);

        expect(mutator.folders(), containsAll(['A', 'A/Sub', 'B']));
        expect(mutator.byFolder('A').map((s) => s.id), ['s1']);
        // Recursive count includes the nested "A/Sub" session.
        expect(mutator.countSessionsInFolder('A'), 2);
        expect(mutator.get('s2')?.folder, 'A/Sub');
        expect(mutator.folderIdByPath('B'), isNotNull);
      },
    );

    test('search filters sessions through the registry', () async {
      final c = makeContainer();
      final mutator = c.read(sessionMutatorProvider);
      await mutator.add(makeSession(id: 's1', label: 'prod-web', host: 'a'));
      await mutator.add(makeSession(id: 's2', label: 'dev-db', host: 'b'));
      await waitForSnapshot(c, (s) => s.sessions.length == 2);

      c.read(sessionSearchProvider.notifier).set('prod');
      final filtered = c.read(filteredSessionsProvider);
      expect(filtered.map((s) => s.id), ['s1']);
    });

    test(
      'byFolder / countSessionsInFolder return empties for a missing path',
      () async {
        final c = makeContainer();
        await waitForSnapshot(c, (_) => true);
        final mutator = c.read(sessionMutatorProvider);
        // No sessions added — the registry returns no ids for any folder.
        expect(mutator.byFolder('does-not-exist'), isEmpty);
        expect(mutator.countSessionsInFolder('does-not-exist'), 0);
      },
    );

    test('get / folderIdByPath return null for absent rows', () async {
      final c = makeContainer();
      await waitForSnapshot(c, (_) => true);
      final mutator = c.read(sessionMutatorProvider);
      expect(mutator.get('ghost'), isNull);
      expect(mutator.folderIdByPath(''), isNull);
      expect(mutator.folderIdByPath('NotThere'), isNull);
    });

    test('folders() yields an empty list with no rows', () async {
      final c = makeContainer();
      await waitForSnapshot(c, (_) => true);
      expect(c.read(sessionMutatorProvider).folders(), isEmpty);
    });
  });

  group('SessionMutator validation + no-op edge cases (real DB)', () {
    test('add rejects an out-of-range port via the validator', () async {
      final c = makeContainer();
      await waitForSnapshot(c, (_) => true);
      await expectLater(
        c.read(sessionMutatorProvider).add(makeSession(id: 'bad', port: 0)),
        throwsArgumentError,
      );
    });

    test('update rejects an invalid host before touching the DB', () async {
      final c = makeContainer();
      final mutator = c.read(sessionMutatorProvider);
      await mutator.add(makeSession(id: 's1'));
      await waitForSnapshot(c, (s) => s.sessions.any((x) => x.id == 's1'));
      await expectLater(
        mutator.update(makeSession(id: 's1', host: '')),
        throwsArgumentError,
      );
    });

    test('updatePartial rejects an absent session', () async {
      final c = makeContainer();
      await waitForSnapshot(c, (_) => true);
      await expectLater(
        c.read(sessionMutatorProvider).updatePartial(makeSession(id: 'ghost')),
        throwsArgumentError,
      );
    });

    test(
      'updatePartial stages key data + passphrase when both dirty flags set',
      () async {
        final c = makeContainer();
        final mutator = c.read(sessionMutatorProvider);
        await mutator.add(makeSession(id: 's1'));
        await waitForSnapshot(c, (s) => s.sessions.any((x) => x.id == 's1'));
        await mutator.updatePartial(
          makeSession(
            id: 's1',
            auth: const SessionAuth(
              authType: AuthType.key,
              keyData: 'PEM-BODY',
              passphrase: 'pp',
            ),
          ),
          keyDataDirty: true,
          passphraseDirty: true,
        );
        // Both `hasStoredKeyData` and `hasStoredPassphrase` flags trip
        // on the next snapshot once Rust persists the secrets and
        // republishes `SessionsChanged`.
        final snap = await waitForSnapshot(
          c,
          (s) => s.sessions.any(
            (x) =>
                x.id == 's1' &&
                x.auth.hasStoredKeyData &&
                x.auth.hasStoredPassphrase,
          ),
        );
        final row = snap.sessions.single;
        expect(row.auth.hasStoredKeyData, isTrue);
        expect(row.auth.hasStoredPassphrase, isTrue);
      },
    );

    test('moveSession on a missing id is a silent no-op', () async {
      final c = makeContainer();
      final mutator = c.read(sessionMutatorProvider);
      await mutator.add(makeSession(id: 's1', folder: 'Home'));
      await waitForSnapshot(c, (s) => s.sessions.any((x) => x.id == 's1'));
      // Run + drain — the missing id branch returns silently inside
      // `_runUndoable`, the snapshot stays unchanged.
      await mutator.moveSession('ghost', 'Elsewhere');
      final snap = c.read(sessionWorkspaceProvider);
      expect(snap.sessions.single.folder, 'Home');
    });

    test('moveMultiple with an empty id set is a no-op', () async {
      final c = makeContainer();
      final mutator = c.read(sessionMutatorProvider);
      await mutator.add(makeSession(id: 's1'));
      await waitForSnapshot(c, (s) => s.sessions.any((x) => x.id == 's1'));
      await mutator.moveMultiple(<String>{}, 'Anywhere');
      expect(c.read(sessionWorkspaceProvider).sessions.length, 1);
    });

    test('deleteMultiple with an empty id set is a no-op', () async {
      final c = makeContainer();
      final mutator = c.read(sessionMutatorProvider);
      await mutator.add(makeSession(id: 's1'));
      await waitForSnapshot(c, (s) => s.sessions.length == 1);
      await mutator.deleteMultiple(<String>{});
      expect(c.read(sessionWorkspaceProvider).sessions.length, 1);
    });

    test('addEmptyFolder ignores an empty path silently', () async {
      final c = makeContainer();
      await waitForSnapshot(c, (_) => true);
      // No state change expected; the bus would otherwise tick.
      await c.read(sessionMutatorProvider).addEmptyFolder('');
      expect(c.read(sessionWorkspaceProvider).emptyFolders, isEmpty);
    });

    test('renameFolder with empty / same / inverse args no-ops', () async {
      final c = makeContainer();
      final mutator = c.read(sessionMutatorProvider);
      await mutator.add(makeSession(id: 's1', folder: 'Same'));
      await waitForSnapshot(c, (s) => s.sessions.any((x) => x.id == 's1'));

      // All three branches inside renameFolder's no-op guard.
      await mutator.renameFolder('', 'X');
      await mutator.renameFolder('Same', '');
      await mutator.renameFolder('Same', 'Same');

      expect(c.read(sessionWorkspaceProvider).sessions.single.folder, 'Same');
    });

    test('moveFolder cycle / no-op guards short-circuit', () async {
      final c = makeContainer();
      final mutator = c.read(sessionMutatorProvider);
      await mutator.add(makeSession(id: 's1', folder: 'Top'));
      await waitForSnapshot(c, (s) => s.sessions.any((x) => x.id == 's1'));

      // Empty path → silent return.
      await mutator.moveFolder('', 'Anywhere');
      // Reparent that would yield the same path → silent return.
      await mutator.moveFolder('Top', '');
      // Cycle: target sits inside the source → silent return.
      await mutator.moveFolder('Top', 'Top/Sub');

      expect(c.read(sessionWorkspaceProvider).sessions.single.folder, 'Top');
    });

    test(
      'duplicateFolder appends "(1)" / "(2)" on name collision at the root',
      () async {
        final c = makeContainer();
        final mutator = c.read(sessionMutatorProvider);
        await mutator.add(makeSession(id: 's1', folder: 'Proj'));
        await waitForSnapshot(c, (s) => s.sessions.any((x) => x.id == 's1'));

        // First copy lands at "Proj (1)" because the source name collides.
        await mutator.duplicateFolder('Proj', '');
        await waitForSnapshot(
          c,
          (s) =>
              s.sessions.any((x) => x.folder == 'Proj (1)') ||
              s.emptyFolders.contains('Proj (1)'),
        );

        // Second copy collides with both — `_uniqueFolderNameUnder`
        // walks to "(2)".
        await mutator.duplicateFolder('Proj', '');
        await waitForSnapshot(
          c,
          (s) =>
              s.sessions.any((x) => x.folder == 'Proj (2)') ||
              s.emptyFolders.contains('Proj (2)'),
        );

        final snap = c.read(sessionWorkspaceProvider);
        final folders = {
          ...snap.sessions.map((s) => s.folder),
          ...snap.emptyFolders,
        };
        expect(folders, containsAll(['Proj', 'Proj (1)', 'Proj (2)']));
      },
    );

    test(
      'toggleFolderCollapsed on an unknown path silently does nothing',
      () async {
        final c = makeContainer();
        await waitForSnapshot(c, (_) => true);
        // No folder rows exist — the lookup returns null and the
        // FRB call is skipped, no exception escapes.
        await c.read(sessionMutatorProvider).toggleFolderCollapsed('Ghost');
        expect(c.read(sessionWorkspaceProvider).collapsedFolders, isEmpty);
      },
    );

    test(
      'undo with no history yields false; redo with none yields false',
      () async {
        final c = makeContainer();
        await waitForSnapshot(c, (_) => true);
        final mutator = c.read(sessionMutatorProvider);
        // Touching the lazy `_history` actor through both arms covers the
        // empty-stack returns from `SessionHistory.undo` / `.redo`.
        expect(await mutator.undo(), isFalse);
        expect(await mutator.redo(), isFalse);
        expect(mutator.canUndo, isFalse);
        expect(mutator.canRedo, isFalse);
      },
    );
  });

  group('Derived providers + filter helpers', () {
    test(
      'emptyFoldersProvider / collapsedFoldersProvider / sessionsByIdProvider '
      'derive from the latest snapshot',
      () async {
        final c = makeContainer();
        final mutator = c.read(sessionMutatorProvider);
        await mutator.add(makeSession(id: 's1', folder: 'Group'));
        await mutator.addEmptyFolder('SoloEmpty');
        await waitForSnapshot(
          c,
          (s) =>
              s.emptyFolders.contains('SoloEmpty') &&
              s.sessions.any((x) => x.id == 's1'),
        );

        expect(c.read(emptyFoldersProvider), contains('SoloEmpty'));
        expect(c.read(collapsedFoldersProvider), isEmpty);
        final byId = c.read(sessionsByIdProvider);
        expect(byId.keys, contains('s1'));
        expect(byId['s1']?.folder, 'Group');
      },
    );

    test(
      'filteredSessionsProvider returns the full list for an empty query',
      () async {
        final c = makeContainer();
        final mutator = c.read(sessionMutatorProvider);
        await mutator.add(makeSession(id: 's1'));
        await mutator.add(makeSession(id: 's2'));
        await waitForSnapshot(c, (s) => s.sessions.length == 2);
        // Search query left at its initial empty value — fast-path
        // returns the underlying list verbatim.
        expect(c.read(filteredSessionsProvider).length, 2);
      },
    );

    test(
      'filterSessions Dart fallback agrees with the registry path',
      () async {
        // Direct helper call — exercises the Dart projection path that
        // also serves as the registry fallback for flutter_test contexts
        // without the FRB native lib loaded.
        final list = [
          makeSession(id: 's1', label: 'prod', host: 'web', user: 'root'),
          makeSession(id: 's2', label: 'dev', host: 'db', user: 'admin'),
        ];
        // Empty query → identity.
        expect(filterSessions(list, '').length, 2);
        // Query that matches one row's host.
        final hits = filterSessions(list, 'web');
        expect(hits.length, 1);
        expect(hits.single.id, 's1');
        // Query that matches nothing.
        expect(filterSessions(list, 'nothing'), isEmpty);
      },
    );

    test(
      'filteredSessionTreeProvider rebuilds tree under empty + filtered query',
      () async {
        final c = makeContainer();
        final mutator = c.read(sessionMutatorProvider);
        await mutator.add(makeSession(id: 's1', label: 'web', folder: 'Prod'));
        await mutator.add(makeSession(id: 's2', label: 'db', folder: 'Prod'));
        await waitForSnapshot(c, (s) => s.sessions.length == 2);

        // Empty query — the tree carries both rows under the same folder.
        final fullTree = c.read(filteredSessionTreeProvider);
        expect(fullTree, isNotEmpty);

        // Narrow the search — provider re-derives.
        c.read(sessionSearchProvider.notifier).set('web');
        final filteredTree = c.read(filteredSessionTreeProvider);
        expect(filteredTree, isNotEmpty);
      },
    );
  });
}
