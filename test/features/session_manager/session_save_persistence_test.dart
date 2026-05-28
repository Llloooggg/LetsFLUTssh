/// Real-DB integration tests for the session-save persistence funnel
/// — `syncForwards`, `syncWebDavDetails`, `syncS3Details`,
/// `applySessionSaveResult`, and `syncSessionDetailsFromSaveResult`.
/// These all converge stored rows to exactly the desired shape (idempotent
/// upserts + deletes); we drive each path against a real in-memory DB
/// and assert the resulting tables match.
///
/// `port_forward_rules`, `webdav_session_details`, `s3_session_details`
/// all carry a foreign key to `sessions`, so a real session row is
/// seeded first. Tagged `frb_global_store`: the rows live in the
/// process-global DB and the assertions check the exact set. See
/// dart_test.yaml.
@Tags(['frb_global_store'])
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/session/port_forwards_dao.dart';
import 'package:letsflutssh/core/session/session.dart';
import 'package:letsflutssh/core/ssh/port_forward_rule.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/features/session_manager/session_edit_dialog.dart';
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

  group('syncWebDavDetails', () {
    test('upserts a webdav row and stages the password when dirty', () async {
      // Spec: a `WebDavSaveData` with `passwordDirty=true` + non-empty
      // password writes both the detail row AND a SecretStore entry
      // keyed by `dbWebdavSessionDetailsSecretId`. The session must
      // already exist (FK) — `setUp` seeds 's1'.
      await syncWebDavDetails(
        's1',
        WebDavSaveData(
          baseUrl: 'https://files.example.com/dav',
          username: 'alice',
          authMethod: 'basic',
          trustedCertPem: null,
          insecureSkipVerify: false,
          password: 'secret-password-1',
          passwordDirty: true,
        ),
      );
      final row = await rust_db.dbWebdavSessionDetailsGet(sessionId: 's1');
      expect(row, isNotNull);
      expect(row!.baseUrl, 'https://files.example.com/dav');
      expect(row.username, 'alice');
      expect(row.authMethod, 'basic');
      final secretId = rust_db.dbWebdavSessionDetailsSecretId(sessionId: 's1');
      final secret = rust_app.secretsGet(id: secretId);
      expect(secret, isNotNull);
      expect(utf8.decode(secret!), 'secret-password-1');
    });

    test('passwordDirty=false leaves any prior secret untouched', () async {
      // Spec: an edit that only changed the label should NOT clobber
      // a previously stored password. The funnel gates the
      // `secretsPut` call on `passwordDirty && password.isNotEmpty`.
      // First write the password, then re-sync without dirty.
      await syncWebDavDetails(
        's1',
        WebDavSaveData(
          baseUrl: 'https://example.com/dav',
          username: 'bob',
          authMethod: 'basic',
          trustedCertPem: null,
          insecureSkipVerify: false,
          password: 'real-secret',
          passwordDirty: true,
        ),
      );
      await syncWebDavDetails(
        's1',
        WebDavSaveData(
          baseUrl: 'https://example.com/dav-renamed',
          username: 'bob',
          authMethod: 'basic',
          trustedCertPem: null,
          insecureSkipVerify: false,
          password: '', // empty + dirty=false
          passwordDirty: false,
        ),
      );
      // Detail row updated, secret untouched.
      final row = await rust_db.dbWebdavSessionDetailsGet(sessionId: 's1');
      expect(row!.baseUrl, 'https://example.com/dav-renamed');
      final secret = rust_app.secretsGet(
        id: rust_db.dbWebdavSessionDetailsSecretId(sessionId: 's1'),
      );
      expect(secret, isNotNull);
      expect(utf8.decode(secret!), 'real-secret');
    });

    test(
      'passwordDirty=true with empty password leaves the secret alone',
      () async {
        // Spec: an empty typed value is treated as "did not type a new
        // password", same as `passwordDirty=false`. Otherwise blanking
        // a field then saving would silently wipe the stored secret.
        await syncWebDavDetails(
          's1',
          WebDavSaveData(
            baseUrl: 'https://example.com/dav',
            username: 'bob',
            authMethod: 'basic',
            trustedCertPem: null,
            insecureSkipVerify: false,
            password: 'real-secret',
            passwordDirty: true,
          ),
        );
        await syncWebDavDetails(
          's1',
          WebDavSaveData(
            baseUrl: 'https://example.com/dav',
            username: 'bob',
            authMethod: 'basic',
            trustedCertPem: null,
            insecureSkipVerify: false,
            password: '',
            passwordDirty: true,
          ),
        );
        final secret = rust_app.secretsGet(
          id: rust_db.dbWebdavSessionDetailsSecretId(sessionId: 's1'),
        );
        expect(utf8.decode(secret!), 'real-secret');
      },
    );
  });

  group('syncS3Details', () {
    test(
      'upserts an s3 row and stages the secret access key when dirty',
      () async {
        await syncS3Details(
          's1',
          S3SaveData(
            accessKeyId: 'AKIA-test',
            region: 'us-east-1',
            endpoint: 's3.example.com',
            pathStyle: true,
            defaultBucket: 'my-bucket',
            defaultPrefix: 'data/',
            trustedCertPem: null,
            insecureSkipVerify: false,
            secretAccessKey: 'wJalrXUtnFEMI/K7MDENG',
            passwordDirty: true,
          ),
        );
        final row = await rust_db.dbS3SessionDetailsGet(sessionId: 's1');
        expect(row, isNotNull);
        expect(row!.accessKeyId, 'AKIA-test');
        expect(row.region, 'us-east-1');
        expect(row.pathStyle, isTrue);
        expect(row.defaultBucket, 'my-bucket');
        final secret = rust_app.secretsGet(
          id: rust_db.dbS3SessionDetailsSecretId(sessionId: 's1'),
        );
        expect(secret, isNotNull);
        expect(utf8.decode(secret!), 'wJalrXUtnFEMI/K7MDENG');
      },
    );

    test(
      'passwordDirty=false leaves any prior secret-access-key intact',
      () async {
        await syncS3Details(
          's1',
          S3SaveData(
            accessKeyId: 'AKIA-first',
            region: 'us-east-1',
            endpoint: '',
            pathStyle: false,
            defaultBucket: '',
            defaultPrefix: '',
            trustedCertPem: null,
            insecureSkipVerify: false,
            secretAccessKey: 'first-key',
            passwordDirty: true,
          ),
        );
        await syncS3Details(
          's1',
          S3SaveData(
            accessKeyId: 'AKIA-renamed',
            region: 'us-east-1',
            endpoint: '',
            pathStyle: false,
            defaultBucket: '',
            defaultPrefix: '',
            trustedCertPem: null,
            insecureSkipVerify: false,
            secretAccessKey: '',
            passwordDirty: false,
          ),
        );
        final row = await rust_db.dbS3SessionDetailsGet(sessionId: 's1');
        expect(row!.accessKeyId, 'AKIA-renamed');
        final secret = rust_app.secretsGet(
          id: rust_db.dbS3SessionDetailsSecretId(sessionId: 's1'),
        );
        expect(utf8.decode(secret!), 'first-key');
      },
    );
  });

  // `syncSessionDetailsFromSaveResult` takes a `WidgetRef`, which can
  // only be sourced from a real Consumer widget. The funnel composition
  // arms (webdavData + s3Data + forwards dispatch + null branches) are
  // covered by `session_panel_test` driving the real edit dialog flow;
  // the per-helper invariants above pin the underlying writes one layer
  // down without spinning up a widget harness.
}
