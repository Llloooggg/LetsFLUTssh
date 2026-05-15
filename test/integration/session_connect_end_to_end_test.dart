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
        // WebDAV / S3 paths set `state` synchronously inside
        // `_doWebDavConnect` / `_doS3Connect` before firing
        // `completeReady`, so `waitUntilReady` is the only gate
        // needed (the SSH-specific `transportReady` completer hangs
        // for non-SSH because no russh actor publishes Adopt).
        await conn.waitUntilReady().timeout(const Duration(seconds: 10));

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
        // Non-SSH paths set `state` synchronously before
        // `completeReady`; `transportReady` is SSH-only.
        await conn.waitUntilReady().timeout(const Duration(seconds: 10));

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
        expect(conn.state, SSHConnectionState.disconnected);
        expect(conn.connectionError, isNotNull);
      },
    );
  });
}
