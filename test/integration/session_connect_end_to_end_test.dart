/// End-to-end connect for every session kind via the Session model.
///
/// The lower-level `connection_lifecycle_test.dart` exercises the
/// russh actor directly through `connectAsync(SSHConfig)`. This file
/// closes the gap above it: a saved `Session` row + per-kind detail
/// row + SecretStore-staged secret should drive a real connect to a
/// matching fixture transport. The persistence chain is what regressed
/// on the v16 schema split — the network handshake is what proves it
/// reconnected.
///
/// Fixtures per kind:
///
/// - **SSH** — the in-process russh fixture
///   (`test_ssh_server_start`).
/// - **WebDAV** — a `dart:io HttpServer` that returns a minimal
///   `207 Multistatus` for `PROPFIND Depth: 0` so the client's connect
///   probe completes.
/// - **S3** — a `dart:io HttpServer` that returns an empty
///   `ListBucketResult` XML for the SigV4-signed list-objects probe.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/connection/connection.dart';
import 'package:letsflutssh/core/db/mappers.dart';
import 'package:letsflutssh/core/session/session.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/providers/connection_provider.dart';
import 'package:letsflutssh/src/rust/api/app.dart' as rust_app;
import 'package:letsflutssh/src/rust/api/db.dart' as rust_db;
import 'package:letsflutssh/src/rust/api/test_hooks.dart' as rust_test;

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

  // ── SSH end-to-end ──────────────────────────────────────────────

  group('SSH session: save → connect via fixture russh server', () {
    late rust_test.TestSshServerInfo serverInfo;

    setUpAll(() async {
      serverInfo = await rust_test.testSshServerStart();
      // Pre-seed known_hosts so the handshake hits Accepted at
      // HostKeyVerify without prompting (no Dart listener in this
      // test process).
      await rust_db.dbKnownHostsUpsertByHostPort(
        host: '127.0.0.1',
        port: serverInfo.port,
        keyType: serverInfo.hostPubkeyAlgorithm,
        keyBase64: serverInfo.hostPubkeyB64,
        addedAtMs: DateTime.now().millisecondsSinceEpoch,
      );
    });

    tearDownAll(() {
      rust_test.testSshServerStopAll();
    });

    ProviderContainer makeContainer() {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      return c;
    }

    test('SSH session loaded from DB connects via the russh fixture', () async {
      final session = Session(
        id: 'ssh-e2e-1',
        label: 'fixture',
        kind: SessionKind.ssh,
        server: ServerAddress(
          host: '127.0.0.1',
          port: serverInfo.port,
          user: 'u',
        ),
        auth: SessionAuth(
          authType: AuthType.password,
          password: serverInfo.password,
        ),
      );
      // Persist through the full v16 path so the read path's
      // LEFT JOIN ssh_session_details actually carries the
      // credentials back.
      await rust_db.dbSessionsUpsert(
        row: sessionToRustRow(session, folderId: null),
      );

      // Reload from DB — same flow the sidebar uses.
      final list = await rust_db.dbSessionsListAll();
      final dbRow = list.firstWhere((s) => s.id == session.id);
      final fresh = dbSessionToSession(dbRow, const {}, withCredentials: true);
      expect(fresh.isValid, isTrue);

      // Hand the reloaded session into the connect path.
      final container = makeContainer();
      final notifier = container.read(connectionsProvider.notifier);
      final conn = notifier.connectAsync(
        fresh.toSSHConfig(),
        label: fresh.displayName,
        sessionId: fresh.id,
      );

      // `transportReady` after `waitUntilReady` is the gate every
      // production consumer uses — the completer fires from the bus
      // listener's terminal-state arm, so by the time it resolves the
      // Connected event has been processed and `state` reflects the
      // final value (see `connection_lifecycle_test.dart`).
      await conn.waitUntilReady().timeout(const Duration(seconds: 15));
      await conn.transportReady;

      expect(conn.state, SSHConnectionState.connected);
      expect(conn.transport, isNotNull);
    });

    test('SSH session with wrong password fails the connect', () async {
      final session = Session(
        id: 'ssh-e2e-fail',
        label: 'fail',
        kind: SessionKind.ssh,
        server: ServerAddress(
          host: '127.0.0.1',
          port: serverInfo.port,
          user: 'u',
        ),
        auth: const SessionAuth(
          authType: AuthType.password,
          password: 'wrong-password',
        ),
      );
      await rust_db.dbSessionsUpsert(
        row: sessionToRustRow(session, folderId: null),
      );

      final list = await rust_db.dbSessionsListAll();
      final fresh = dbSessionToSession(
        list.firstWhere((s) => s.id == session.id),
        const {},
        withCredentials: true,
      );

      final container = makeContainer();
      final notifier = container.read(connectionsProvider.notifier);
      final conn = notifier.connectAsync(
        fresh.toSSHConfig(),
        label: fresh.displayName,
        sessionId: fresh.id,
      );

      // Negative path — the actor publishes Authenticate/failed and
      // settles into `disconnected` with `connectionError != null`.
      // `transportReady` after `waitUntilReady` waits for the bus
      // listener's terminal-state arm to land.
      await conn.waitUntilReady().timeout(const Duration(seconds: 15));
      await conn.transportReady;

      expect(conn.state, SSHConnectionState.disconnected);
      expect(conn.connectionError, isNotNull);
    });
  });

  // ── WebDAV end-to-end ───────────────────────────────────────────

  group('WebDAV session: save → connect via in-process HTTP fixture', () {
    late HttpServer server;
    late int port;
    // Capture the Authorization header the client sends so the test
    // can assert the staged secret reached the wire.
    String? lastAuthorization;

    setUpAll(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      port = server.port;
      server.listen((HttpRequest request) async {
        lastAuthorization = request.headers.value('authorization');
        // The WebDAV connect probe is `PROPFIND /` with Depth: 0.
        // A minimal `207 Multistatus` is enough to satisfy the
        // client's PROPFIND parser; the connect path is happy
        // with an empty entry list.
        if (request.method == 'PROPFIND') {
          request.response
            ..statusCode = 207
            ..headers.contentType = ContentType.parse(
              'application/xml; charset=utf-8',
            );
          const body =
              '<?xml version="1.0" encoding="utf-8"?>'
              '<D:multistatus xmlns:D="DAV:">'
              '<D:response>'
              '<D:href>/</D:href>'
              '<D:propstat>'
              '<D:status>HTTP/1.1 200 OK</D:status>'
              '<D:prop><D:resourcetype><D:collection/></D:resourcetype></D:prop>'
              '</D:propstat>'
              '</D:response>'
              '</D:multistatus>';
          request.response.write(body);
          await request.response.close();
          return;
        }
        request.response.statusCode = 405;
        await request.response.close();
      });
    });

    tearDownAll(() async {
      await server.close(force: true);
    });

    setUp(() {
      lastAuthorization = null;
    });

    ProviderContainer makeContainer() {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      return c;
    }

    test(
      'WebDAV session loaded from DB connects via the in-process HTTP fixture '
      'and sends the staged Basic credential on the wire',
      () async {
        final baseUrl = 'http://127.0.0.1:$port/';
        final session = Session(
          id: 'webdav-e2e-1',
          label: 'fixture-dav',
          kind: SessionKind.webdav,
          server: ServerAddress(host: '127.0.0.1', port: port, user: 'alice'),
        );
        await rust_db.dbSessionsUpsert(
          row: sessionToRustRow(session, folderId: null),
        );
        await rust_db.dbWebdavSessionDetailsUpsert(
          rec: rust_db.DbWebDavSessionDetails(
            sessionId: session.id,
            baseUrl: baseUrl,
            username: 'alice',
            authMethod: 'basic',
            selfSignedFingerprint: null,
          ),
        );
        final secretId = rust_db.dbWebdavSessionDetailsSecretId(
          sessionId: session.id,
        );
        await rust_app.secretsPut(
          id: secretId,
          bytes: Uint8List.fromList(utf8.encode('webdav-pw')),
        );

        // Reload from DB exactly like the sidebar would.
        final list = await rust_db.dbSessionsListAll();
        final fresh = dbSessionToSession(
          list.firstWhere((s) => s.id == session.id),
          const {},
        );

        final container = makeContainer();
        final notifier = container.read(connectionsProvider.notifier);
        final conn = notifier.connectWebDavAsync(fresh);
        await conn.waitUntilReady().timeout(const Duration(seconds: 10));
        // `transportReady` MUST resolve for non-SSH transports too —
        // the SFTP file-browser mixin awaits this gate before adding
        // its `openChannel` step, so a Completer left dangling here
        // is what kept the WebDAV browser stuck on
        // `[✓] Authenticating as <user>` indefinitely in production.
        // The original carve-out ("transportReady completer hangs
        // for non-SSH") papered over that gap in the test instead
        // of fixing the connect helper; the regression returns the
        // moment we drop the `markTransportAdopted` call from
        // `_doWebDavConnect`. See connection.dart →
        // [`markTransportAdopted`].
        final adopted = await conn.transportReady.timeout(
          const Duration(seconds: 10),
        );
        expect(
          adopted,
          isTrue,
          reason:
              'transportReady must complete with true after a '
              'successful WebDAV connect so the file browser can '
              'proceed to open its remote view.',
        );

        expect(conn.state, SSHConnectionState.connected);
        expect(
          lastAuthorization,
          isNotNull,
          reason: 'The HTTP fixture must have seen the PROPFIND probe.',
        );
        // Basic auth header shape: `Basic base64(user:pass)`.
        expect(lastAuthorization, startsWith('Basic '));
        final decoded = utf8.decode(
          base64.decode(lastAuthorization!.substring(6)),
        );
        expect(
          decoded,
          'alice:webdav-pw',
          reason:
              'The Authorization header on the wire must encode the '
              'username from webdav_session_details + the secret bytes '
              'staged under dbWebdavSessionDetailsSecretId.',
        );
      },
    );

    test(
      'WebDAV connect surfaces error when SecretStore has no staged secret',
      () async {
        final baseUrl = 'http://127.0.0.1:$port/';
        final session = Session(
          id: 'webdav-e2e-nosecret',
          label: 'fixture-dav-nosecret',
          kind: SessionKind.webdav,
          server: ServerAddress(host: '127.0.0.1', port: port, user: 'alice'),
        );
        await rust_db.dbSessionsUpsert(
          row: sessionToRustRow(session, folderId: null),
        );
        await rust_db.dbWebdavSessionDetailsUpsert(
          rec: rust_db.DbWebDavSessionDetails(
            sessionId: session.id,
            baseUrl: baseUrl,
            username: 'alice',
            authMethod: 'basic',
            selfSignedFingerprint: null,
          ),
        );
        // Skip secretsPut on purpose — the connect path's Rust side
        // must return a clear "secret not staged" error rather than
        // sending an unauthenticated request.

        final list = await rust_db.dbSessionsListAll();
        final fresh = dbSessionToSession(
          list.firstWhere((s) => s.id == session.id),
          const {},
        );

        final container = makeContainer();
        final notifier = container.read(connectionsProvider.notifier);
        final conn = notifier.connectWebDavAsync(fresh);
        await conn.waitUntilReady().timeout(const Duration(seconds: 10));
        // Failure path: `markTransportAdopted(adopted: false)` must
        // wake the gate so the file browser renders the error state
        // instead of spinning forever — same root-cause as the
        // success-path assertion above.
        final adopted = await conn.transportReady.timeout(
          const Duration(seconds: 10),
        );
        expect(
          adopted,
          isFalse,
          reason:
              'transportReady must complete with false when the '
              'connect throws so the file browser exits its waiting '
              'state and surfaces the error.',
        );
        expect(conn.state, SSHConnectionState.disconnected);
        expect(
          conn.connectionError,
          isNotNull,
          reason:
              'Missing SecretStore secret must surface as a connect-'
              'time error, not a silent unauthenticated probe.',
        );
      },
    );

    test('WebDAV password survives a SecretStore wipe — proves the save → '
        'restart → connect persistence chain', () async {
      // Reproduces the user-reported regression: the in-memory
      // `SecretStore` was the only landing pad for the WebDAV
      // password, so a process restart wiped it and the next
      // connect failed even though every other field on the row
      // had been written to disk. The fix persists the password on
      // `webdav_session_details.password` (SQLCipher-encrypted at
      // rest) and stages it back into the SecretStore on the
      // connect call. We simulate a restart by dropping the
      // SecretStore slot directly after save.
      final baseUrl = 'http://127.0.0.1:$port/';
      final session = Session(
        id: 'webdav-persist-1',
        label: 'fixture-dav-persist',
        kind: SessionKind.webdav,
        server: ServerAddress(host: '127.0.0.1', port: port, user: 'alice'),
      );
      await rust_db.dbSessionsUpsert(
        row: sessionToRustRow(session, folderId: null),
      );
      await rust_db.dbWebdavSessionDetailsUpsert(
        rec: rust_db.DbWebDavSessionDetails(
          sessionId: session.id,
          baseUrl: baseUrl,
          username: 'alice',
          authMethod: 'basic',
          selfSignedFingerprint: null,
        ),
      );
      // Save flow: persist the password through the new column
      // setter (mirrors `_syncWebDavDetails`).
      await rust_db.dbWebdavSessionDetailsSetPassword(
        sessionId: session.id,
        password: 'persist-me',
      );
      // Has-password probe surfaces to the edit dialog as the
      // "[Saved] type to change" hint.
      expect(
        await rust_db.dbWebdavSessionDetailsHasPassword(sessionId: session.id),
        isTrue,
      );
      // Simulate process restart by dropping the in-memory
      // SecretStore slot. The DB column survives.
      final secretId = rust_db.dbWebdavSessionDetailsSecretId(
        sessionId: session.id,
      );
      rust_app.secretsDropMany(ids: [secretId]);
      expect(rust_app.secretsHas(id: secretId), isFalse);

      final list = await rust_db.dbSessionsListAll();
      final fresh = dbSessionToSession(
        list.firstWhere((s) => s.id == session.id),
        const {},
      );

      final container = makeContainer();
      final notifier = container.read(connectionsProvider.notifier);
      final conn = notifier.connectWebDavAsync(fresh);
      await conn.waitUntilReady().timeout(const Duration(seconds: 10));
      final adopted = await conn.transportReady.timeout(
        const Duration(seconds: 10),
      );

      expect(
        adopted,
        isTrue,
        reason:
            'Connect must succeed without re-typing the password '
            'after the SecretStore is wiped — the connect path '
            'stages the password back from '
            'webdav_session_details.password.',
      );
      expect(conn.state, SSHConnectionState.connected);
      expect(
        lastAuthorization,
        startsWith('Basic '),
        reason: 'The wire request must have carried the staged credential.',
      );
      final decoded = utf8.decode(
        base64.decode(lastAuthorization!.substring(6)),
      );
      expect(decoded, 'alice:persist-me');
    });
  });

  // ── S3 end-to-end ───────────────────────────────────────────────

  group('S3 session: save → connect via in-process HTTP fixture', () {
    late HttpServer server;
    late int port;
    String? lastAuthorization;

    setUpAll(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      port = server.port;
      server.listen((HttpRequest request) async {
        lastAuthorization = request.headers.value('authorization');
        // The S3 connect probe is a one-page `ListObjectsV2` against
        // the default bucket. `list-type=2` shows up as a query
        // parameter; any GET with that parameter from the SigV4
        // signer is good enough for the fixture. Return an empty
        // result so the probe parses cleanly.
        if (request.method == 'GET') {
          request.response
            ..statusCode = 200
            ..headers.contentType = ContentType.parse(
              'application/xml; charset=utf-8',
            );
          const body =
              '<?xml version="1.0" encoding="utf-8"?>'
              '<ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">'
              '<Name>my-bucket</Name>'
              '<Prefix></Prefix>'
              '<KeyCount>0</KeyCount>'
              '<MaxKeys>1</MaxKeys>'
              '<IsTruncated>false</IsTruncated>'
              '</ListBucketResult>';
          request.response.write(body);
          await request.response.close();
          return;
        }
        request.response.statusCode = 405;
        await request.response.close();
      });
    });

    tearDownAll(() async {
      await server.close(force: true);
    });

    setUp(() {
      lastAuthorization = null;
    });

    ProviderContainer makeContainer() {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      return c;
    }

    test(
      'S3 session loaded from DB connects via the in-process HTTP fixture and '
      'sends a SigV4-signed Authorization header on the wire',
      () async {
        final endpoint = 'http://127.0.0.1:$port';
        final session = Session(
          id: 's3-e2e-1',
          label: 'fixture-s3',
          kind: SessionKind.s3,
          server: ServerAddress(
            host: '127.0.0.1',
            port: port,
            user: 'AKIATEST',
          ),
        );
        await rust_db.dbSessionsUpsert(
          row: sessionToRustRow(session, folderId: null),
        );
        await rust_db.dbS3SessionDetailsUpsert(
          rec: rust_db.DbS3SessionDetails(
            sessionId: session.id,
            accessKeyId: 'AKIATEST',
            region: 'us-east-1',
            endpoint: endpoint,
            // Path-style required — the bucket lives at
            // `<endpoint>/<bucket>` rather than the
            // `<bucket>.<endpoint>` shape, which doesn't resolve on
            // a loopback fixture without DNS magic.
            pathStyle: true,
            defaultBucket: 'my-bucket',
            defaultPrefix: '',
          ),
        );
        final secretId = rust_db.dbS3SessionDetailsSecretId(
          sessionId: session.id,
        );
        await rust_app.secretsPut(
          id: secretId,
          bytes: Uint8List.fromList(utf8.encode('s3-secret-key')),
        );

        final list = await rust_db.dbSessionsListAll();
        final fresh = dbSessionToSession(
          list.firstWhere((s) => s.id == session.id),
          const {},
        );

        final container = makeContainer();
        final notifier = container.read(connectionsProvider.notifier);
        final conn = notifier.connectS3Async(fresh);
        await conn.waitUntilReady().timeout(const Duration(seconds: 10));
        // Same `transportReady` invariant as WebDAV — the gate must
        // resolve so the file browser can open. The S3 connect path
        // had the identical bug (no `markTransportAdopted` call)
        // before the fix.
        final adopted = await conn.transportReady.timeout(
          const Duration(seconds: 10),
        );
        expect(
          adopted,
          isTrue,
          reason:
              'transportReady must complete with true after a '
              'successful S3 connect so the file browser can '
              'proceed to open its remote view.',
        );

        expect(conn.state, SSHConnectionState.connected);
        expect(
          lastAuthorization,
          isNotNull,
          reason:
              'The HTTP fixture must have seen the SigV4-signed '
              'ListObjectsV2 probe.',
        );
        expect(
          lastAuthorization,
          startsWith('AWS4-HMAC-SHA256 '),
          reason:
              'The Authorization header must be a SigV4-shaped '
              'signature; the access key id rides inside it.',
        );
        expect(
          lastAuthorization,
          contains('Credential=AKIATEST/'),
          reason:
              'The credential scope must include the access key id '
              'from s3_session_details.',
        );
      },
    );

    test(
      'S3 connect surfaces error when SecretStore has no staged secret',
      () async {
        final endpoint = 'http://127.0.0.1:$port';
        final session = Session(
          id: 's3-e2e-nosecret',
          label: 'fixture-s3-nosecret',
          kind: SessionKind.s3,
          server: ServerAddress(host: '127.0.0.1', port: port, user: 'AKIA'),
        );
        await rust_db.dbSessionsUpsert(
          row: sessionToRustRow(session, folderId: null),
        );
        await rust_db.dbS3SessionDetailsUpsert(
          rec: rust_db.DbS3SessionDetails(
            sessionId: session.id,
            accessKeyId: 'AKIA',
            region: 'us-east-1',
            endpoint: endpoint,
            pathStyle: true,
            defaultBucket: 'my-bucket',
            defaultPrefix: '',
          ),
        );
        // Skip secretsPut.

        final list = await rust_db.dbSessionsListAll();
        final fresh = dbSessionToSession(
          list.firstWhere((s) => s.id == session.id),
          const {},
        );

        final container = makeContainer();
        final notifier = container.read(connectionsProvider.notifier);
        final conn = notifier.connectS3Async(fresh);
        await conn.waitUntilReady().timeout(const Duration(seconds: 10));
        final adopted = await conn.transportReady.timeout(
          const Duration(seconds: 10),
        );
        expect(
          adopted,
          isFalse,
          reason:
              'transportReady must complete with false when the '
              'S3 connect throws so the file browser exits its '
              'waiting state.',
        );
        expect(conn.state, SSHConnectionState.disconnected);
        expect(conn.connectionError, isNotNull);
      },
    );

    test('S3 secret access key survives a SecretStore wipe — proves the save → '
        'restart → connect persistence chain', () async {
      // Same regression class as the WebDAV persistence test:
      // before the fix the secret access key only lived in
      // `SecretStore` (RAM), so a process restart wiped it. After
      // the fix it persists on `s3_session_details.secret_access_key`
      // and the connect path stages it back into the SecretStore.
      final endpoint = 'http://127.0.0.1:$port';
      final session = Session(
        id: 's3-persist-1',
        label: 'fixture-s3-persist',
        kind: SessionKind.s3,
        server: ServerAddress(host: '127.0.0.1', port: port, user: 'AKIATEST'),
      );
      await rust_db.dbSessionsUpsert(
        row: sessionToRustRow(session, folderId: null),
      );
      await rust_db.dbS3SessionDetailsUpsert(
        rec: rust_db.DbS3SessionDetails(
          sessionId: session.id,
          accessKeyId: 'AKIATEST',
          region: 'us-east-1',
          endpoint: endpoint,
          pathStyle: true,
          defaultBucket: 'my-bucket',
          defaultPrefix: '',
        ),
      );
      await rust_db.dbS3SessionDetailsSetSecretAccessKey(
        sessionId: session.id,
        secretAccessKey: 'persist-secret-key',
      );
      expect(
        await rust_db.dbS3SessionDetailsHasSecretAccessKey(
          sessionId: session.id,
        ),
        isTrue,
      );
      // Simulate process restart.
      final secretId = rust_db.dbS3SessionDetailsSecretId(
        sessionId: session.id,
      );
      rust_app.secretsDropMany(ids: [secretId]);
      expect(rust_app.secretsHas(id: secretId), isFalse);

      final list = await rust_db.dbSessionsListAll();
      final fresh = dbSessionToSession(
        list.firstWhere((s) => s.id == session.id),
        const {},
      );

      final container = makeContainer();
      final notifier = container.read(connectionsProvider.notifier);
      final conn = notifier.connectS3Async(fresh);
      await conn.waitUntilReady().timeout(const Duration(seconds: 10));
      final adopted = await conn.transportReady.timeout(
        const Duration(seconds: 10),
      );

      expect(
        adopted,
        isTrue,
        reason:
            'Connect must succeed without re-typing the secret '
            'access key after the SecretStore is wiped — the '
            'connect path stages it back from '
            's3_session_details.secret_access_key.',
      );
      expect(conn.state, SSHConnectionState.connected);
      expect(
        lastAuthorization,
        startsWith('AWS4-HMAC-SHA256 '),
        reason: 'The wire request must have carried a SigV4 signature.',
      );
      expect(
        lastAuthorization,
        contains('Credential=AKIATEST/'),
        reason:
            'The signature scope must reference the access key id '
            'from s3_session_details.',
      );
    });
  });

  // ── Routing: connectTerminal for WebDAV/S3 opens SFTP tab ───────

  group('SessionConnect.connectTerminal kind dispatch', () {
    test(
      'WebDAV / S3 kinds always route to addSftpTab even when the caller '
      'invokes connectTerminal',
      () {
        // The routing logic lives in `SessionConnect.connectTerminal`;
        // a unit test would exercise it through a fake workspace
        // notifier. Adding a widget-level test for that path lives in
        // `test/features/session_manager/session_connect_test.dart`
        // (where the existing connectTerminal/connectSftp suites
        // already wire up the harness). The integration assertion
        // here is the persistence chain above — we keep the routing
        // expectations alongside the suite that builds the matching
        // harness, not duplicated here.
      },
      skip:
          'covered by test/features/session_manager/session_connect_test.dart',
    );
  });
}
