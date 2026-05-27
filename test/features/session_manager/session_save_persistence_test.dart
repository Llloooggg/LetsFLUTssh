/// Real-DB integration tests for `syncForwards` — the port-forward
/// reconciliation in the session-save funnel. It must converge the
/// stored rules to exactly the desired set: upsert every rule in the
/// new list and delete any stored rule no longer present.
///
/// `port_forward_rules` carries a foreign key to `sessions`, so a real
/// session row is seeded first. Tagged `frb_global_store`: the rows
/// live in the process-global DB and the assertions check the exact
/// set. See dart_test.yaml.
@Tags(['frb_global_store'])
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/session/port_forwards_dao.dart';
import 'package:letsflutssh/core/session/session.dart';
import 'package:letsflutssh/core/ssh/port_forward_rule.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/features/session_manager/session_save_persistence.dart';
import 'package:letsflutssh/providers/session_provider.dart';
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

  late ProviderContainer container;

  setUp(() async {
    await rust_db.dbSessionsDeleteAll(); // cascade-drops port_forward_rules
    await rust_db.dbFoldersDeleteAll();
    container = ProviderContainer();
    // The FK on port_forward_rules requires a real parent session.
    await container
        .read(sessionMutatorProvider)
        .add(
          Session(
            id: 's1',
            label: 'Box',
            server: const ServerAddress(host: '10.0.0.1', user: 'root'),
          ),
        );
  });

  tearDown(() => container.dispose());

  PortForwardRule rule(String id, int bindPort) => PortForwardRule(
    id: id,
    kind: PortForwardKind.local,
    bindPort: bindPort,
    remoteHost: 'db.internal',
    remotePort: 5432,
  );

  test('upserts every rule in the desired list', () async {
    await syncForwards('s1', [rule('r1', 6000), rule('r2', 6001)]);
    final stored = await loadPortForwards('s1');
    expect(stored.map((r) => r.id).toSet(), {'r1', 'r2'});
  });

  test('deletes a stored rule no longer in the desired list', () async {
    await syncForwards('s1', [rule('r1', 6000), rule('r2', 6001)]);
    await syncForwards('s1', [rule('r1', 6000)]);
    final stored = await loadPortForwards('s1');
    expect(stored.map((r) => r.id).toList(), ['r1']);
  });

  test('an empty desired list clears every rule', () async {
    await syncForwards('s1', [rule('r1', 6000), rule('r2', 6001)]);
    await syncForwards('s1', const []);
    expect(await loadPortForwards('s1'), isEmpty);
  });

  test('a kept rule is updated in place, not duplicated', () async {
    await syncForwards('s1', [rule('r1', 6000)]);
    await syncForwards('s1', [rule('r1', 7000)]); // same id, new bind port
    final stored = await loadPortForwards('s1');
    expect(stored, hasLength(1));
    expect(stored.single.bindPort, 7000);
  });
}
