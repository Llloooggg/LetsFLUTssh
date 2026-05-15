/// Save → reload → connect-ready roundtrip for every transport kind.
///
/// Real `lfs_frb` + an in-memory SQLite DB. Mirrors what the session
/// edit dialog's save flow does (`SessionMutator.add` +
/// `_syncWebDavDetails` / `_syncS3Details` + `secretsPut`), then
/// verifies the reloaded row + SecretStore state lets
/// `SessionConnect._createConnection` proceed past the `isValid` gate.
///
/// This is the contract that regressed on the v16 schema split — the
/// SSH-shape `isValid` check still demanded `host` / `port` / `user`
/// non-empty + credentials, but non-SSH kinds load those slots as
/// COALESCE defaults (empty / 22) after the split. The bug surfaced
/// as "WebDAV secret not staged" at connect time because the early
/// `!session.isValid` return short-circuited before the connect path
/// could read the actual transport tuple off `webdav_session_details`.
///
/// Coverage matrix:
/// - SSH: dbSessions upsert + (synthetic) credential staging, reload,
///   isValid + transport tuple round-trip.
/// - WebDAV: dbSessions slim upsert + webdav_session_details upsert +
///   secretsPut, reload, isValid + transport tuple round-trip +
///   `secretsHas` post-condition.
/// - S3: dbSessions slim upsert + s3_session_details upsert +
///   secretsPut, reload, isValid + transport tuple round-trip +
///   `secretsHas` post-condition.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/db/mappers.dart';
import 'package:letsflutssh/core/session/session.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
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

  // Each test wipes whatever the previous left behind so the row
  // shapes (sessions, webdav / s3 join tables) start clean. Use
  // delete_all + delete_multiple to cover both the slim parent and
  // the join children — the join tables cascade off the parent via
  // ON DELETE CASCADE, so wiping the parent is enough.
  setUp(() async {
    final live = await rust_db.dbSessionsListAll();
    if (live.isNotEmpty) {
      await rust_db.dbSessionsDeleteMultiple(ids: [for (final s in live) s.id]);
    }
  });

  // ── SSH ──────────────────────────────────────────────────────────

  test(
    'SSH session: save → reload → isValid + transport tuple round-trip',
    () async {
      final session = Session(
        id: 'ssh-roundtrip-1',
        label: 'prod-shell',
        kind: SessionKind.ssh,
        server: const ServerAddress(
          host: '10.0.0.1',
          port: 2222,
          user: 'deploy',
        ),
        auth: const SessionAuth(
          authType: AuthType.password,
          password: 'hunter2',
        ),
      );

      await rust_db.dbSessionsUpsert(
        row: sessionToRustRow(session, folderId: null),
      );

      final list = await rust_db.dbSessionsListAll();
      final reloaded = list.firstWhere((s) => s.id == session.id);
      final domain = dbSessionToSession(reloaded, const {});

      expect(domain.kind, SessionKind.ssh);
      expect(domain.host, '10.0.0.1');
      expect(domain.port, 2222);
      expect(domain.user, 'deploy');
      // Credentials never round-trip into the in-memory cache, but the
      // per-slot stored-secret flag must flip so the dialog renders
      // "[Saved] type to change" on re-open.
      expect(domain.auth.hasStoredPassword, isTrue);
      expect(
        domain.isValid,
        isTrue,
        reason:
            'SSH session with full host / port / user / stored password '
            'must pass the connect-time validity gate.',
      );
    },
  );

  // ── WebDAV ───────────────────────────────────────────────────────

  test(
    'WebDAV session: save → reload → isValid even though host is empty + secret '
    'staged in SecretStore',
    () async {
      final session = Session(
        id: 'webdav-roundtrip-1',
        label: 'nextcloud',
        kind: SessionKind.webdav,
        // _serverFromBaseUrl populates these from the typed base URL
        // before the in-memory Session reaches the mutator.
        server: const ServerAddress(
          host: 'cloud.example.com',
          port: 443,
          user: 'alice',
        ),
      );

      await rust_db.dbSessionsUpsert(
        row: sessionToRustRow(session, folderId: null),
      );
      await rust_db.dbWebdavSessionDetailsUpsert(
        rec: rust_db.DbWebDavSessionDetails(
          sessionId: session.id,
          baseUrl: 'https://cloud.example.com/remote.php/dav/files/alice/',
          username: 'alice',
          authMethod: 'basic',
          selfSignedFingerprint: null,
        ),
      );

      // Stage the password into SecretStore under the canonical id
      // the connect path looks up. Mirrors `_syncWebDavDetails` in
      // the dialog's save handler.
      final secretId = rust_db.dbWebdavSessionDetailsSecretId(
        sessionId: session.id,
      );
      await rust_app.secretsPut(
        id: secretId,
        bytes: Uint8List.fromList(utf8.encode('webdav-password-123')),
      );

      // Reload from the slim `sessions` row + the WebDAV join row.
      final list = await rust_db.dbSessionsListAll();
      final reloaded = list.firstWhere((s) => s.id == session.id);
      final domain = dbSessionToSession(reloaded, const {});

      // After the v16 schema split, host / port / user load as the
      // COALESCE defaults (empty / 22 / empty) for non-SSH kinds —
      // the SSH columns moved to `ssh_session_details` and WebDAV
      // sessions never get a join row there. `isValid` MUST still
      // return true so the connect path proceeds.
      expect(domain.kind, SessionKind.webdav);
      expect(
        domain.isValid,
        isTrue,
        reason:
            'WebDAV session must be valid even with empty host / port / '
            'user — the transport tuple lives on webdav_session_details '
            'and the connect path reads it directly from there.',
      );

      // Transport tuple readback — every field the connect path
      // depends on.
      final detail = await rust_db.dbWebdavSessionDetailsGet(
        sessionId: session.id,
      );
      expect(detail, isNotNull);
      expect(
        detail!.baseUrl,
        'https://cloud.example.com/remote.php/dav/files/alice/',
      );
      expect(detail.username, 'alice');
      expect(detail.authMethod, 'basic');

      // SecretStore round-trip — the connect path will pass
      // `passwordSecretId` to `webdavConnect`; the Rust side reads
      // the bytes back via `secrets.get`. `secretsHas` is the same
      // probe the dialog's `_loadWebDavDetails` uses to drive the
      // "[Saved] type to change" hint.
      expect(rust_app.secretsHas(id: secretId), isTrue);
    },
  );

  test(
    'WebDAV session: re-edit shows the "stored secret" hint via secretsHas',
    () async {
      final session = Session(
        id: 'webdav-rehint-1',
        label: 'nextcloud-rehint',
        kind: SessionKind.webdav,
        server: const ServerAddress(
          host: 'cloud.example.com',
          port: 443,
          user: 'bob',
        ),
      );
      await rust_db.dbSessionsUpsert(
        row: sessionToRustRow(session, folderId: null),
      );
      await rust_db.dbWebdavSessionDetailsUpsert(
        rec: rust_db.DbWebDavSessionDetails(
          sessionId: session.id,
          baseUrl: 'https://cloud.example.com/',
          username: 'bob',
          authMethod: 'digest',
          selfSignedFingerprint: null,
        ),
      );
      final secretId = rust_db.dbWebdavSessionDetailsSecretId(
        sessionId: session.id,
      );
      // Without the secret staged, `secretsHas` returns false — the
      // dialog renders the default '••••••••' hint and the user has
      // to retype the password.
      expect(rust_app.secretsHas(id: secretId), isFalse);
      await rust_app.secretsPut(
        id: secretId,
        bytes: Uint8List.fromList(utf8.encode('p')),
      );
      // After staging, `secretsHas` flips true — the dialog renders
      // "[Saved] type to change" and the empty-field save preserves
      // the stored secret (passwordDirty stays false).
      expect(rust_app.secretsHas(id: secretId), isTrue);
    },
  );

  // ── S3 ───────────────────────────────────────────────────────────

  test('S3 session: save → reload → isValid even though host is empty + secret '
      'staged in SecretStore', () async {
    final session = Session(
      id: 's3-roundtrip-1',
      label: 'backups-bucket',
      kind: SessionKind.s3,
      // _serverFromS3Endpoint computes these from the typed
      // endpoint / region tuple before the in-memory Session
      // reaches the mutator.
      server: const ServerAddress(
        host: 's3.amazonaws.com',
        port: 443,
        user: 'AKIA1234567890ABCDEF',
      ),
    );

    await rust_db.dbSessionsUpsert(
      row: sessionToRustRow(session, folderId: null),
    );
    await rust_db.dbS3SessionDetailsUpsert(
      rec: rust_db.DbS3SessionDetails(
        sessionId: session.id,
        accessKeyId: 'AKIA1234567890ABCDEF',
        region: 'us-east-1',
        endpoint: '',
        pathStyle: false,
        defaultBucket: 'my-backups',
        defaultPrefix: 'logs/',
      ),
    );

    final secretId = rust_db.dbS3SessionDetailsSecretId(sessionId: session.id);
    await rust_app.secretsPut(
      id: secretId,
      bytes: Uint8List.fromList(utf8.encode('s3-secret-access-key')),
    );

    final list = await rust_db.dbSessionsListAll();
    final reloaded = list.firstWhere((s) => s.id == session.id);
    final domain = dbSessionToSession(reloaded, const {});

    expect(domain.kind, SessionKind.s3);
    expect(
      domain.isValid,
      isTrue,
      reason:
          'S3 session must be valid even with empty host / port / user '
          '— the SigV4 credential pair lives on s3_session_details + '
          'SecretStore.',
    );

    final detail = await rust_db.dbS3SessionDetailsGet(sessionId: session.id);
    expect(detail, isNotNull);
    expect(detail!.accessKeyId, 'AKIA1234567890ABCDEF');
    expect(detail.region, 'us-east-1');
    expect(detail.endpoint, '');
    expect(detail.pathStyle, isFalse);
    expect(detail.defaultBucket, 'my-backups');
    expect(detail.defaultPrefix, 'logs/');

    expect(rust_app.secretsHas(id: secretId), isTrue);
  });

  test(
    'S3 session: re-edit shows the "stored secret" hint via secretsHas',
    () async {
      final session = Session(
        id: 's3-rehint-1',
        label: 's3-rehint',
        kind: SessionKind.s3,
        server: const ServerAddress(
          host: 's3.amazonaws.com',
          port: 443,
          user: 'AKIA',
        ),
      );
      await rust_db.dbSessionsUpsert(
        row: sessionToRustRow(session, folderId: null),
      );
      await rust_db.dbS3SessionDetailsUpsert(
        rec: rust_db.DbS3SessionDetails(
          sessionId: session.id,
          accessKeyId: 'AKIA',
          region: 'eu-west-1',
          endpoint: '',
          pathStyle: false,
          defaultBucket: '',
          defaultPrefix: '',
        ),
      );
      final secretId = rust_db.dbS3SessionDetailsSecretId(
        sessionId: session.id,
      );
      expect(rust_app.secretsHas(id: secretId), isFalse);
      await rust_app.secretsPut(
        id: secretId,
        bytes: Uint8List.fromList(utf8.encode('k')),
      );
      expect(rust_app.secretsHas(id: secretId), isTrue);
    },
  );

  // ── Kind change ──────────────────────────────────────────────────

  test('Kind change SSH → WebDAV drops the ssh_session_details join row '
      'so the old SSH credential blob does not stay reachable', () async {
    // Seed an SSH session with credentials.
    final ssh = Session(
      id: 'kind-change-1',
      label: 'morphing',
      kind: SessionKind.ssh,
      server: const ServerAddress(host: '10.0.0.1', port: 22, user: 'deploy'),
      auth: const SessionAuth(
        authType: AuthType.password,
        password: 'old-ssh-secret',
      ),
    );
    await rust_db.dbSessionsUpsert(row: sessionToRustRow(ssh, folderId: null));
    // Confirm SSH credential round-tripped.
    var list = await rust_db.dbSessionsListAll();
    var reloaded = list.firstWhere((s) => s.id == ssh.id);
    expect(
      dbSessionToSession(reloaded, const {}).auth.hasStoredPassword,
      isTrue,
    );

    // Re-save same id as WebDAV — the v16 upsert path must DELETE
    // the SSH join row so a kind change does not leak the old
    // password under the same session id.
    final webdav = ssh.copyWith(kind: SessionKind.webdav);
    await rust_db.dbSessionsUpsert(
      row: sessionToRustRow(webdav, folderId: null),
    );
    list = await rust_db.dbSessionsListAll();
    reloaded = list.firstWhere((s) => s.id == ssh.id);
    final domain = dbSessionToSession(reloaded, const {});
    expect(domain.kind, SessionKind.webdav);
    expect(
      domain.auth.hasStoredPassword,
      isFalse,
      reason:
          'After kind flip, the SSH credential blob must not survive '
          'as a stored-password marker — Arc B delete_ssh_details '
          'on the write path.',
    );
  });
}
