import 'package:flutter_test/flutter_test.dart';

import 'package:letsflutssh/core/session/port_forwards_dao.dart';
import 'package:letsflutssh/core/ssh/port_forward_rule.dart';
import 'package:letsflutssh/src/rust/api/app.dart' as rust_app;
import 'package:letsflutssh/src/rust/api/db.dart' as rust_db;

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

  // Each test starts with the parent Sessions row in place + zero
  // rules so loadPortForwards / upsertPortForward / deletePortForward
  // observable changes are isolated.
  setUp(() async {
    // Wipe the rule table to keep tests independent.
    final existing = await rust_db.dbPortForwardsListForSession(
      sessionId: 'sess-pf',
    );
    for (final row in existing) {
      await rust_db.dbPortForwardsDelete(id: row.id);
    }
    // Idempotent — re-inserts the same parent row each setUp.
    await rust_db.dbSessionsUpsert(
      row: const rust_db.DbSession(
        id: 'sess-pf',
        label: 'PF Test',
        folderId: null,
        host: 'h.example',
        port: 22,
        user: 'u',
        authType: 'password',
        password: '',
        keyPath: '',
        keyData: '',
        keyId: null,
        passphrase: '',
        sortOrder: 0,
        notes: '',
        lastConnectedAtMs: null,
        extras: '{}',
        viaSessionId: null,
        viaHost: null,
        viaPort: null,
        viaUser: null,
        createdAtMs: 0,
        updatedAtMs: 0,
      ),
    );
  });

  PortForwardRule rule({
    String id = 'rule-1',
    PortForwardKind kind = PortForwardKind.local,
    String bindHost = '127.0.0.1',
    int bindPort = 5432,
    String remoteHost = 'db.internal',
    int remotePort = 5432,
    String description = 'prod DB',
    bool enabled = true,
    int sortOrder = 0,
  }) => PortForwardRule(
    id: id,
    kind: kind,
    bindHost: bindHost,
    bindPort: bindPort,
    remoteHost: remoteHost,
    remotePort: remotePort,
    description: description,
    enabled: enabled,
    sortOrder: sortOrder,
    createdAt: DateTime.utc(2026, 1, 1),
  );

  group('loadPortForwards', () {
    test('returns an empty list when the session has no rules', () async {
      expect(await loadPortForwards('sess-pf'), isEmpty);
    });

    test('returns rules sorted by sortOrder', () async {
      await upsertPortForward(
        'sess-pf',
        rule(id: 'a', sortOrder: 2, bindPort: 5001),
      );
      await upsertPortForward(
        'sess-pf',
        rule(id: 'b', sortOrder: 0, bindPort: 5002),
      );
      await upsertPortForward(
        'sess-pf',
        rule(id: 'c', sortOrder: 1, bindPort: 5003),
      );

      final loaded = await loadPortForwards('sess-pf');

      expect(loaded.map((r) => r.id), ['b', 'c', 'a']);
    });

    test('round-trips every rule field via Rust DAO', () async {
      final original = rule(
        id: 'rt',
        kind: PortForwardKind.dynamic_,
        bindHost: '0.0.0.0',
        bindPort: 1080,
        remoteHost: '',
        remotePort: 0,
        description: 'browser SOCKS',
        enabled: false,
        sortOrder: 7,
      );
      await upsertPortForward('sess-pf', original);

      final loaded = await loadPortForwards('sess-pf');

      expect(loaded, hasLength(1));
      final r = loaded.single;
      expect(r.id, 'rt');
      expect(r.kind, PortForwardKind.dynamic_);
      expect(r.bindHost, '0.0.0.0');
      expect(r.bindPort, 1080);
      expect(r.description, 'browser SOCKS');
      expect(r.enabled, isFalse);
      expect(r.sortOrder, 7);
      // DAO round-trips via millisecondsSinceEpoch — same instant,
      // local-time clock.
      expect(r.createdAt.isAtSameMomentAs(DateTime.utc(2026, 1, 1)), isTrue);
    });

    test('isolates rules by sessionId', () async {
      await rust_db.dbSessionsUpsert(
        row: const rust_db.DbSession(
          id: 'sess-other',
          label: 'Other',
          folderId: null,
          host: 'o',
          port: 22,
          user: 'u',
          authType: 'password',
          password: '',
          keyPath: '',
          keyData: '',
          keyId: null,
          passphrase: '',
          sortOrder: 0,
          notes: '',
          lastConnectedAtMs: null,
          extras: '{}',
          viaSessionId: null,
          viaHost: null,
          viaPort: null,
          viaUser: null,
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
      );

      await upsertPortForward('sess-pf', rule(id: 'a-pf'));
      await upsertPortForward('sess-other', rule(id: 'a-other'));

      expect((await loadPortForwards('sess-pf')).single.id, 'a-pf');
      expect((await loadPortForwards('sess-other')).single.id, 'a-other');
    });
  });

  group('upsertPortForward', () {
    test('insert + re-upsert with same id overwrites', () async {
      await upsertPortForward('sess-pf', rule(id: 'k', bindPort: 5000));
      await upsertPortForward('sess-pf', rule(id: 'k', bindPort: 5999));

      final loaded = await loadPortForwards('sess-pf');
      expect(loaded, hasLength(1));
      expect(loaded.single.bindPort, 5999);
    });

    test('upsert against a missing parent session is a no-op (FK)', () async {
      // FK constraint on sessions(id) — the DAO logs + swallows.
      await upsertPortForward('does-not-exist', rule(id: 'orphan'));

      // No exception bubbled up; the rule did not land in any other
      // session's set.
      expect(await loadPortForwards('sess-pf'), isEmpty);
    });
  });

  group('deletePortForward', () {
    test('returns true when a row is removed', () async {
      await upsertPortForward('sess-pf', rule(id: 'd1'));

      expect(await deletePortForward('d1'), isTrue);
      expect(await loadPortForwards('sess-pf'), isEmpty);
    });

    test('returns false for a non-existent rule id', () async {
      expect(await deletePortForward('never-existed'), isFalse);
    });

    test('only deletes the matching rule, leaves siblings intact', () async {
      await upsertPortForward('sess-pf', rule(id: 'keep', bindPort: 5001));
      await upsertPortForward('sess-pf', rule(id: 'drop', bindPort: 5002));

      expect(await deletePortForward('drop'), isTrue);

      final remaining = await loadPortForwards('sess-pf');
      expect(remaining.map((r) => r.id), ['keep']);
    });
  });
}
