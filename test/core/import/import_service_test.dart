import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/config/app_config.dart';
import 'package:letsflutssh/core/import/import_service.dart';
import 'package:letsflutssh/core/session/session.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/features/settings/export_import.dart';

void main() {
  group('ImportService', () {
    late List<Session> store;
    late List<String> deletedIds;
    late List<String> importedFolders;
    late dynamic appliedConfig;

    late ImportService service;

    setUp(() {
      store = [];
      deletedIds = [];
      importedFolders = [];
      appliedConfig = null;

      service = ImportService(
        addEmptyFolder: (f) async => importedFolders.add(f),
        addSession: (s) async => store.add(s),
        deleteSession: (id) async => deletedIds.add(id),
        getSessions: () => store,
        applyConfig: (config) => appliedConfig = config,
      );
    });

    Session makeSession(String id, String label) => Session(
      id: id,
      label: label,
      server: const ServerAddress(host: 'host', user: 'user'),
    );

    test('merge mode adds sessions', () async {
      final s1 = makeSession('1', 'A');
      final s2 = makeSession('2', 'B');

      await service.applyResult(
        ImportResult(sessions: [s1, s2], mode: ImportMode.merge),
      );

      expect(store, hasLength(2));
      expect(store[0].label, 'A');
      expect(store[1].label, 'B');
      expect(deletedIds, isEmpty);
    });

    test('merge mode skips duplicates on error', () async {
      final s1 = makeSession('1', 'A');

      final errorService = ImportService(
        addEmptyFolder: (f) async => importedFolders.add(f),
        addSession: (s) async => throw Exception('duplicate'),
        deleteSession: (id) async => deletedIds.add(id),
        getSessions: () => store,
        applyConfig: (config) => appliedConfig = config,
      );

      // Should not throw — merge mode skips errors
      await errorService.applyResult(
        ImportResult(sessions: [s1], mode: ImportMode.merge),
      );

      expect(deletedIds, isEmpty);
    });

    test('replace mode deletes existing then adds new', () async {
      final existing1 = makeSession('old1', 'Old1');
      final existing2 = makeSession('old2', 'Old2');
      store.addAll([existing1, existing2]);

      final newSession = makeSession('new1', 'New1');

      await service.applyResult(
        ImportResult(sessions: [newSession], mode: ImportMode.replace),
      );

      expect(deletedIds, ['old1', 'old2']);
      expect(store, hasLength(3)); // old ones still in list + new one added
      expect(store.last.label, 'New1');
    });

    test('replace mode tolerates deleteSession mutating the list', () async {
      final existing1 = makeSession('old1', 'Old1');
      final existing2 = makeSession('old2', 'Old2');
      store.addAll([existing1, existing2]);

      final mutatingService = ImportService(
        addEmptyFolder: (f) async => importedFolders.add(f),
        addSession: (s) async => store.add(s),
        deleteSession: (id) async {
          deletedIds.add(id);
          store.removeWhere((s) => s.id == id);
        },
        getSessions: () => store,
        applyConfig: (config) => appliedConfig = config,
      );

      final newSession = makeSession('new1', 'New1');

      await mutatingService.applyResult(
        ImportResult(sessions: [newSession], mode: ImportMode.replace),
      );

      expect(deletedIds, ['old1', 'old2']);
      expect(store, hasLength(1));
      expect(store.first.label, 'New1');
    });

    test('replace mode rethrows on add error', () async {
      final errorService = ImportService(
        addEmptyFolder: (f) async => importedFolders.add(f),
        addSession: (s) async => throw Exception('failed'),
        deleteSession: (id) async => deletedIds.add(id),
        getSessions: () => [],
        applyConfig: (config) => appliedConfig = config,
      );

      expect(
        () => errorService.applyResult(
          ImportResult(
            sessions: [makeSession('1', 'A')],
            mode: ImportMode.replace,
          ),
        ),
        throwsException,
      );
    });

    test('applies config when not null', () async {
      const config = AppConfig(terminal: TerminalConfig(fontSize: 18.0));

      await service.applyResult(
        const ImportResult(
          sessions: [],
          config: config,
          mode: ImportMode.merge,
        ),
      );

      expect(appliedConfig, isNotNull);
      expect((appliedConfig as AppConfig).fontSize, 18.0);
    });

    test('config is applied after sessions in same import', () async {
      final s1 = makeSession('1', 'A');
      const config = AppConfig(terminal: TerminalConfig(fontSize: 14.0));

      await service.applyResult(
        ImportResult(sessions: [s1], config: config, mode: ImportMode.merge),
      );

      expect(store, hasLength(1));
      expect(appliedConfig, isNotNull);
      expect((appliedConfig as AppConfig).fontSize, 14.0);
    });

    test('skips config when null', () async {
      await service.applyResult(
        const ImportResult(sessions: [], mode: ImportMode.merge),
      );

      expect(appliedConfig, isNull);
    });

    test('handles empty sessions list', () async {
      await service.applyResult(
        const ImportResult(sessions: [], mode: ImportMode.merge),
      );

      expect(store, isEmpty);
      expect(deletedIds, isEmpty);
    });

    test('handles empty sessions list in replace mode', () async {
      final existing = makeSession('old', 'Old');
      store.add(existing);

      await service.applyResult(
        const ImportResult(sessions: [], mode: ImportMode.replace),
      );

      expect(deletedIds, ['old']);
    });

    group('replace mode rollback', () {
      late List<Session> restoredSessions;
      late Set<String> restoredFolders;
      late Set<String> emptyFolders;

      setUp(() {
        restoredSessions = [];
        restoredFolders = {};
        emptyFolders = {'FolderA'};
      });

      ImportService buildRollbackService({
        required Future<void> Function(Session) onAdd,
      }) {
        return ImportService(
          addEmptyFolder: (f) async => importedFolders.add(f),
          addSession: onAdd,
          deleteSession: (id) async {
            deletedIds.add(id);
            store.removeWhere((s) => s.id == id);
          },
          getSessions: () => store,
          applyConfig: (config) => appliedConfig = config,
          getEmptyFolders: () => emptyFolders,
          restoreSnapshot: (sessions, folders) async {
            restoredSessions = sessions;
            restoredFolders = folders;
            store
              ..clear()
              ..addAll(sessions);
          },
        );
      }

      test('restores snapshot when addSession fails', () async {
        final existing = makeSession('old1', 'Old1');
        store.add(existing);

        var addCount = 0;
        final svc = buildRollbackService(
          onAdd: (s) async {
            addCount++;
            if (addCount == 2) throw Exception('disk full');
            store.add(s);
          },
        );

        final s1 = makeSession('new1', 'New1');
        final s2 = makeSession('new2', 'New2');

        await expectLater(
          () => svc.applyResult(
            ImportResult(sessions: [s1, s2], mode: ImportMode.replace),
          ),
          throwsException,
        );

        // Snapshot was restored
        expect(restoredSessions, hasLength(1));
        expect(restoredSessions.first.id, 'old1');
        expect(restoredFolders, contains('FolderA'));
      });

      test('successful replace does not trigger restore', () async {
        final existing = makeSession('old1', 'Old1');
        store.add(existing);

        final svc = buildRollbackService(onAdd: (s) async => store.add(s));

        final s1 = makeSession('new1', 'New1');
        await svc.applyResult(
          ImportResult(sessions: [s1], mode: ImportMode.replace),
        );

        expect(restoredSessions, isEmpty);
        expect(store.last.label, 'New1');
      });

      test('rollback without callbacks does not crash', () async {
        // Use the basic service (no rollback callbacks)
        final errorService = ImportService(
          addEmptyFolder: (f) async => importedFolders.add(f),
          addSession: (s) async => throw Exception('fail'),
          deleteSession: (id) async => deletedIds.add(id),
          getSessions: () => [],
          applyConfig: (config) => appliedConfig = config,
        );

        await expectLater(
          () => errorService.applyResult(
            ImportResult(
              sessions: [makeSession('1', 'A')],
              mode: ImportMode.replace,
            ),
          ),
          throwsException,
        );
      });

      test(
        'config is NOT applied when session import fails (correct behavior)',
        () async {
          final existing = makeSession('old1', 'Old1');
          store.add(existing);

          // Track the order of operations
          final operationOrder = <String>[];

          final svc = ImportService(
            addEmptyFolder: (f) async => importedFolders.add(f),
            addSession: (s) async {
              operationOrder.add('addSession:${s.id}');
              if (s.id == 'new2') throw Exception('disk full');
              store.add(s);
            },
            deleteSession: (id) async {
              operationOrder.add('deleteSession:$id');
              store.removeWhere((s) => s.id == id);
            },
            getSessions: () => store,
            applyConfig: (config) {
              operationOrder.add('applyConfig');
              appliedConfig = config;
            },
            getEmptyFolders: () => {'FolderA'},
            restoreSnapshot: (sessions, folders) async {
              operationOrder.add('restoreSnapshot');
              store
                ..clear()
                ..addAll(sessions);
            },
          );

          const config = AppConfig(terminal: TerminalConfig(fontSize: 12.0));
          final s1 = makeSession('new1', 'New1');
          final s2 = makeSession('new2', 'New2');

          await expectLater(
            () => svc.applyResult(
              ImportResult(
                sessions: [s1, s2],
                config: config,
                mode: ImportMode.replace,
              ),
            ),
            throwsException,
          );

          // Config is applied AFTER sessions succeed — so on failure it is NOT applied.
          // This is correct: config shouldn't be applied if the overall import failed.
          expect(operationOrder, isNot(contains('applyConfig')));
          expect(appliedConfig, isNull);
          // Sessions were rolled back
          expect(store, hasLength(1));
          expect(store.first.id, 'old1');
        },
      );
    });

    test('applyConfig failure does not abort import', () async {
      final s1 = makeSession('1', 'A');
      const config = AppConfig(terminal: TerminalConfig(fontSize: 18.0));

      final configErrorService = ImportService(
        addEmptyFolder: (f) async => importedFolders.add(f),
        addSession: (s) async => store.add(s),
        deleteSession: (id) async => deletedIds.add(id),
        getSessions: () => store,
        applyConfig: (_) => throw Exception('config write failed'),
      );

      // Should not throw — config failure is caught and logged
      await configErrorService.applyResult(
        ImportResult(sessions: [s1], config: config, mode: ImportMode.merge),
      );

      // Session was still imported despite config failure
      expect(store, hasLength(1));
      expect(store.first.label, 'A');
    });

    group('empty folder import', () {
      test('imports empty folders from result', () async {
        await service.applyResult(
          const ImportResult(
            sessions: [],
            emptyFolders: {'FolderA', 'FolderB'},
            mode: ImportMode.merge,
          ),
        );

        expect(importedFolders, containsAll(['FolderA', 'FolderB']));
        expect(importedFolders, hasLength(2));
      });

      test('empty folder failure in replace mode triggers rollback', () async {
        final existing = makeSession('old1', 'Old1');
        store.add(existing);

        var restored = false;
        final svc = ImportService(
          addEmptyFolder: (f) async => throw Exception('folder write failed'),
          addSession: (s) async => store.add(s),
          deleteSession: (id) async {
            deletedIds.add(id);
            store.removeWhere((s) => s.id == id);
          },
          getSessions: () => store,
          applyConfig: (config) => appliedConfig = config,
          getEmptyFolders: () => {'ExistingFolder'},
          restoreSnapshot: (sessions, folders) async {
            restored = true;
            store
              ..clear()
              ..addAll(sessions);
          },
        );

        final s1 = makeSession('new1', 'New1');

        await expectLater(
          () => svc.applyResult(
            ImportResult(
              sessions: [s1],
              emptyFolders: {'BadFolder'},
              mode: ImportMode.replace,
            ),
          ),
          throwsException,
        );

        // Rollback was triggered
        expect(restored, isTrue);
        // Original session was restored
        expect(store, hasLength(1));
        expect(store.first.id, 'old1');
      });

      test('skips folder that throws error', () async {
        final errorFolders = <String>[];
        final svc = ImportService(
          addEmptyFolder: (f) async {
            if (f == 'BadFolder') throw Exception('cannot create');
            errorFolders.add(f);
          },
          addSession: (s) async => store.add(s),
          deleteSession: (id) async => deletedIds.add(id),
          getSessions: () => store,
          applyConfig: (config) => appliedConfig = config,
        );

        // Should not throw — folder errors are caught and logged
        await svc.applyResult(
          const ImportResult(
            sessions: [],
            emptyFolders: {'GoodFolder', 'BadFolder'},
            mode: ImportMode.merge,
          ),
        );

        expect(errorFolders, contains('GoodFolder'));
        expect(errorFolders, isNot(contains('BadFolder')));
      });
    });
  });
}
