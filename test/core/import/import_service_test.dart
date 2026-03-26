import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/config/app_config.dart';
import 'package:letsflutssh/core/import/import_service.dart';
import 'package:letsflutssh/core/session/session.dart';
import 'package:letsflutssh/features/settings/export_import.dart';

void main() {
  group('ImportService', () {
    late List<Session> store;
    late List<String> deletedIds;
    late dynamic appliedConfig;

    late ImportService service;

    setUp(() {
      store = [];
      deletedIds = [];
      appliedConfig = null;

      service = ImportService(
        addSession: (s) async => store.add(s),
        deleteSession: (id) async => deletedIds.add(id),
        getSessions: () => store,
        applyConfig: (config) => appliedConfig = config,
      );
    });

    Session makeSession(String id, String label) => Session(
          id: id,
          label: label,
          host: 'host',
          user: 'user',
        );

    test('merge mode adds sessions', () async {
      final s1 = makeSession('1', 'A');
      final s2 = makeSession('2', 'B');

      await service.applyResult(ImportResult(
        sessions: [s1, s2],
        mode: ImportMode.merge,
      ));

      expect(store, hasLength(2));
      expect(store[0].label, 'A');
      expect(store[1].label, 'B');
      expect(deletedIds, isEmpty);
    });

    test('merge mode skips duplicates on error', () async {
      final s1 = makeSession('1', 'A');

      final errorService = ImportService(
        addSession: (s) async => throw Exception('duplicate'),
        deleteSession: (id) async => deletedIds.add(id),
        getSessions: () => store,
        applyConfig: (config) => appliedConfig = config,
      );

      // Should not throw — merge mode skips errors
      await errorService.applyResult(ImportResult(
        sessions: [s1],
        mode: ImportMode.merge,
      ));

      expect(deletedIds, isEmpty);
    });

    test('replace mode deletes existing then adds new', () async {
      final existing1 = makeSession('old1', 'Old1');
      final existing2 = makeSession('old2', 'Old2');
      store.addAll([existing1, existing2]);

      final newSession = makeSession('new1', 'New1');

      await service.applyResult(ImportResult(
        sessions: [newSession],
        mode: ImportMode.replace,
      ));

      expect(deletedIds, ['old1', 'old2']);
      expect(store, hasLength(3)); // old ones still in list + new one added
      expect(store.last.label, 'New1');
    });

    test('replace mode rethrows on add error', () async {
      final errorService = ImportService(
        addSession: (s) async => throw Exception('failed'),
        deleteSession: (id) async => deletedIds.add(id),
        getSessions: () => [],
        applyConfig: (config) => appliedConfig = config,
      );

      expect(
        () => errorService.applyResult(ImportResult(
          sessions: [makeSession('1', 'A')],
          mode: ImportMode.replace,
        )),
        throwsException,
      );
    });

    test('applies config when not null', () async {
      const config = AppConfig(terminal: TerminalConfig(fontSize: 18.0));

      await service.applyResult(const ImportResult(
        sessions: [],
        config: config,
        mode: ImportMode.merge,
      ));

      expect(appliedConfig, isNotNull);
      expect((appliedConfig as AppConfig).fontSize, 18.0);
    });

    test('skips config when null', () async {
      await service.applyResult(const ImportResult(
        sessions: [],
        mode: ImportMode.merge,
      ));

      expect(appliedConfig, isNull);
    });

    test('handles empty sessions list', () async {
      await service.applyResult(const ImportResult(
        sessions: [],
        mode: ImportMode.merge,
      ));

      expect(store, isEmpty);
      expect(deletedIds, isEmpty);
    });

    test('handles empty sessions list in replace mode', () async {
      final existing = makeSession('old', 'Old');
      store.add(existing);

      await service.applyResult(const ImportResult(
        sessions: [],
        mode: ImportMode.replace,
      ));

      expect(deletedIds, ['old']);
    });
  });
}
