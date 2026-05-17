import 'package:flutter_test/flutter_test.dart';

import 'package:letsflutssh/core/import/import_service.dart';
import 'package:letsflutssh/core/session/session.dart';
import 'package:letsflutssh/core/snippets/snippet.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/core/tags/tag.dart';
import 'package:letsflutssh/features/settings/export_import.dart';
import 'package:letsflutssh/src/rust/api/app.dart' as rust_app;
import 'package:letsflutssh/src/rust/api/archive.dart' as rust_archive;

import '../../helpers/frb_bootstrap.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await requireFrbLoaded();
    await rust_app.dbInit(path: ':memory:', key: const []);
  });

  tearDownAll(() async {
    await rust_app.dbClose();
  });

  group('ImportSummary', () {
    test('default constructor — all counters zero, all flags false', () {
      const s = ImportSummary();
      expect(s.sessions, 0);
      expect(s.folders, 0);
      expect(s.managerKeys, 0);
      expect(s.tags, 0);
      expect(s.snippets, 0);
      expect(s.configApplied, isFalse);
      expect(s.knownHostsApplied, isFalse);
      expect(s.skippedSessions, 0);
      expect(s.skippedLinks, 0);
    });

    test('non-default values land on every field', () {
      const s = ImportSummary(
        sessions: 5,
        folders: 2,
        managerKeys: 3,
        tags: 4,
        snippets: 7,
        configApplied: true,
        knownHostsApplied: true,
        skippedSessions: 1,
        skippedLinks: 2,
      );
      expect(s.sessions, 5);
      expect(s.folders, 2);
      expect(s.managerKeys, 3);
      expect(s.tags, 4);
      expect(s.snippets, 7);
      expect(s.configApplied, isTrue);
      expect(s.knownHostsApplied, isTrue);
      expect(s.skippedSessions, 1);
      expect(s.skippedLinks, 2);
    });
  });

  group('LfsImportRolledBackException', () {
    test('preserves the cause object', () {
      const cause = FormatException('boom');
      const e = LfsImportRolledBackException(cause: cause);
      expect(e.cause, cause);
      expect(e, isA<Exception>());
    });

    test('toString embeds the cause', () {
      const e = LfsImportRolledBackException(cause: 'boom');
      expect(e.toString(), 'LfsImportRolledBackException: boom');
    });
  });

  group('decodeConfigFromApply', () {
    rust_archive.DbApplyResult make({String? configJson}) =>
        rust_archive.DbApplyResult(
          sessionsApplied: 0,
          keysApplied: 0,
          keysSkippedDedup: 0,
          tagsApplied: 0,
          snippetsApplied: 0,
          knownHostsApplied: 0,
          foldersApplied: 0,
          sessionTagsApplied: 0,
          folderTagsApplied: 0,
          sessionSnippetsApplied: 0,
          errors: const [],
          configJson: configJson,
          rolledBack: false,
        );

    test('returns null when configJson is null', () {
      expect(decodeConfigFromApply(make()), isNull);
    });

    test('returns null when configJson is empty', () {
      expect(decodeConfigFromApply(make(configJson: '')), isNull);
    });

    test('decodes a minimal config payload', () {
      const json = '{"locale": "ru"}';
      final cfg = decodeConfigFromApply(make(configJson: json));
      expect(cfg, isNotNull);
      expect(cfg!.locale, 'ru');
    });
  });

  group('applyResultViaRust (merge mode integration)', () {
    test('sessions-only merge applies + invokes refresh hook', () async {
      // Fresh session row with deterministic id so we can grep the DB.
      final session = Session(
        id: 'apply-test-1',
        label: 'Apply Test',
        server: const ServerAddress(host: 'h.example', port: 22, user: 'u'),
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      );
      final result = ImportResult(sessions: [session], mode: ImportMode.merge);
      var refreshCalls = 0;
      final apply = await applyResultViaRust(
        result,
        refreshAfterImport: () async => refreshCalls++,
      );
      expect(apply.sessionsApplied, 1);
      expect(apply.errors, isEmpty);
      expect(refreshCalls, 1);
    });

    test('empty result still invokes refresh hook', () async {
      const result = ImportResult(sessions: [], mode: ImportMode.merge);
      var refreshCalls = 0;
      final apply = await applyResultViaRust(
        result,
        refreshAfterImport: () async => refreshCalls++,
      );
      expect(apply.errors, isEmpty);
      expect(refreshCalls, 1);
    });

    test('null refresh hook is permitted', () async {
      const result = ImportResult(sessions: [], mode: ImportMode.merge);
      // Should not throw.
      final apply = await applyResultViaRust(result);
      expect(apply.errors, isEmpty);
    });

    test('tags + snippets merge round-trips counts', () async {
      final result = ImportResult(
        sessions: const [],
        tags: [
          Tag(
            id: 'tag-merge-1',
            name: 'merge-test',
            color: '#00AA00',
            createdAt: DateTime.utc(2026, 1, 1),
          ),
        ],
        snippets: [
          Snippet(id: 'snip-merge-1', title: 'echo hi', command: 'echo hi'),
        ],
        mode: ImportMode.merge,
      );
      final apply = await applyResultViaRust(result);
      expect(apply.tagsApplied, greaterThanOrEqualTo(1));
      expect(apply.snippetsApplied, greaterThanOrEqualTo(1));
    });
  });
}
