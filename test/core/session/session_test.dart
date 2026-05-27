import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/session/session.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/src/rust/api/sessions.dart' as rust_sess;

import '../../helpers/frb_bootstrap.dart';

void main() {
  // The storable-field validator lives Rust-side in
  // `lfs_core::sessions::validate_session_fields` — bootstrap FRB
  // so the canonical Rust grammar is exercised and the retired
  // Dart `Session.validate` wrapper does not regress.
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(requireFrbLoaded);

  String? validate(Session s) => rust_sess.sessionsValidateFields(
    host: s.host,
    port: s.port,
    user: s.user,
  );

  group('Session', () {
    test('validate requires host', () {
      final s = Session(
        label: 'test',
        server: const ServerAddress(host: '', user: 'root'),
      );
      expect(validate(s), 'Host is required');
    });

    test('validate requires user', () {
      final s = Session(
        label: 'test',
        server: const ServerAddress(host: 'example.com', user: ''),
      );
      expect(validate(s), 'Username is required');
    });

    test('validate checks port range', () {
      final s = Session(
        label: 'test',
        server: const ServerAddress(host: 'x', port: 0, user: 'r'),
      );
      expect(validate(s), 'Port must be 1-65535');
    });

    test('validate passes with valid data', () {
      final s = Session(
        label: 'test',
        server: const ServerAddress(host: 'example.com', user: 'root'),
      );
      expect(validate(s), isNull);
    });

    // ── isValid kind-aware gate ────────────────────────────────────
    //
    // The session-tree UI calls `session.isValid` to decide whether
    // to render the "credentials not set" warning icon. After the
    // v17 schema bump, WebDAV / S3 rows finally carry a persistent
    // password column; `isValid` for those kinds must now require
    // `hasCredentials` (just like SSH always has) instead of the
    // earlier unconditional `true`. Without this the warning never
    // fired for incomplete non-SSH rows — the original user
    // regression report.

    test('isValid is false for a WebDAV session with no stored password', () {
      final s = Session(
        id: 'webdav-no-pw',
        label: 'dav',
        kind: SessionKind.webdav,
        server: const ServerAddress(host: 'dav.example.com', user: 'alice'),
      );
      expect(
        s.isValid,
        isFalse,
        reason:
            'WebDAV row without `auth.hasStoredSecret` must trigger '
            'the session-tree credential warning. Until v17 this '
            'returned true unconditionally and the warning never '
            'fired for non-SSH rows.',
      );
    });

    test('isValid is true for a WebDAV session with a stored password', () {
      final s = Session(
        id: 'webdav-pw',
        label: 'dav',
        kind: SessionKind.webdav,
        server: const ServerAddress(host: 'dav.example.com', user: 'alice'),
        auth: const SessionAuth(hasStoredPassword: true),
      );
      expect(s.isValid, isTrue);
    });

    test('isValid is false for an S3 session with no stored secret key', () {
      final s = Session(
        id: 's3-no-secret',
        label: 's3',
        kind: SessionKind.s3,
        server: const ServerAddress(host: 's3.example.com', user: 'AKIA'),
      );
      expect(
        s.isValid,
        isFalse,
        reason:
            'S3 row without a stored secret access key must trigger '
            'the session-tree credential warning — same root cause '
            'as the WebDAV case.',
      );
    });

    test('isValid is true for an S3 session with a stored secret key', () {
      final s = Session(
        id: 's3-secret',
        label: 's3',
        kind: SessionKind.s3,
        server: const ServerAddress(host: 's3.example.com', user: 'AKIA'),
        auth: const SessionAuth(hasStoredPassword: true),
      );
      expect(s.isValid, isTrue);
    });

    test('validate rejects negative port directly', () {
      // The grammar now lives Rust-side and accepts the full i32
      // range; the historical Dart-side wrapper used to clamp the
      // value before the call, but the FRB takes the raw port.
      final s = Session(
        label: 'test',
        server: const ServerAddress(host: 'x', port: -1, user: 'r'),
      );
      expect(validate(s), 'Port must be 1-65535');
    });

    test('displayName with label', () {
      final s = Session(
        label: 'prod',
        server: const ServerAddress(host: 'example.com', user: 'root'),
      );
      expect(s.displayName, 'prod (root@example.com)');
    });

    test('displayName without label', () {
      final s = Session(
        label: '',
        server: const ServerAddress(
          host: 'example.com',
          port: 2222,
          user: 'root',
        ),
      );
      expect(s.displayName, 'root@example.com:2222');
    });

    test('displayName for WebDAV with label uses the label', () {
      // WebDAV / S3 keep host / port / user on the matching join
      // table (`webdav_session_details` / `s3_session_details`).
      // After the v16 schema split those fields read empty on the
      // in-memory `Session` row, so `displayName` must not render
      // `@:22`. With a label the label wins.
      final s = Session(
        label: 'nextcloud',
        kind: SessionKind.webdav,
        server: const ServerAddress(host: '', port: 0, user: ''),
      );
      expect(s.displayName, 'nextcloud');
    });

    test('displayName for unlabeled WebDAV falls back to kind token', () {
      final s = Session(
        label: '',
        kind: SessionKind.webdav,
        server: const ServerAddress(host: '', port: 0, user: ''),
      );
      expect(s.displayName, 'WebDAV session');
    });

    test('displayName for unlabeled S3 falls back to kind token', () {
      final s = Session(
        label: '',
        kind: SessionKind.s3,
        server: const ServerAddress(host: '', port: 0, user: ''),
      );
      expect(s.displayName, 'S3 session');
    });

    test('fullPath with folder', () {
      final s = Session(
        label: 'nginx',
        folder: 'Production/Web',
        server: const ServerAddress(host: 'x', user: 'r'),
      );
      expect(s.fullPath, 'Production/Web/nginx');
    });

    test('fullPath without folder', () {
      final s = Session(
        label: 'nginx',
        server: const ServerAddress(host: 'x', user: 'r'),
      );
      expect(s.fullPath, 'nginx');
    });

    // Session.duplicate() was retired with the Rust port — production
    // duplication routes through dbSessionsDuplicateWithPath, covered
    // by Rust-side tests in lfs_core::db::sessions::duplicate_tests.

    test('JSON roundtrip', () {
      final s = Session(
        label: 'prod',
        folder: 'Servers/Web',
        server: const ServerAddress(
          host: 'example.com',
          port: 2222,
          user: 'admin',
        ),
        auth: const SessionAuth(
          authType: AuthType.key,
          keyPath: '/home/.ssh/id_rsa',
        ),
      );
      final json = s.toJson();
      final restored = Session.fromJson(json);
      expect(restored.label, 'prod');
      expect(restored.folder, 'Servers/Web');
      expect(restored.host, 'example.com');
      expect(restored.port, 2222);
      expect(restored.user, 'admin');
      expect(restored.authType, AuthType.key);
      expect(restored.keyPath, '/home/.ssh/id_rsa');
    });

    test('JSON roundtrip preserves keyId', () {
      final s = Session(
        label: 'with-key-id',
        server: const ServerAddress(host: 'h', user: 'u'),
        auth: const SessionAuth(authType: AuthType.key, keyId: 'store-key-42'),
      );
      final json = s.toJson();
      expect(json['key_id'], 'store-key-42');
      final restored = Session.fromJson(json);
      expect(restored.keyId, 'store-key-42');
    });

    test('JSON without key_id defaults to empty', () {
      final restored = Session.fromJson({'id': 'x', 'host': 'h', 'user': 'u'});
      expect(restored.keyId, isEmpty);
    });

    test('copyWith updates fields', () {
      final s = Session(
        label: 'a',
        server: const ServerAddress(host: 'b', user: 'c'),
      );
      final updated = s.copyWith(
        label: 'new',
        server: s.server.copyWith(port: 3333),
      );
      expect(updated.id, s.id);
      expect(updated.label, 'new');
      expect(updated.port, 3333);
      expect(updated.host, 'b');
    });
  });

  group('SessionAuth', () {
    test('copyWith partial fields', () {
      const auth = SessionAuth(
        authType: AuthType.password,
        password: 'pw',
        keyPath: '/k',
        keyData: 'kd',
        passphrase: 'pp',
      );
      final copy = auth.copyWith(password: 'new');
      expect(copy.authType, AuthType.password);
      expect(copy.password, 'new');
      expect(copy.keyPath, '/k');
      expect(copy.keyData, 'kd');
      expect(copy.passphrase, 'pp');
    });

    test('copyWith all fields', () {
      const auth = SessionAuth();
      final copy = auth.copyWith(
        authType: AuthType.key,
        password: 'p',
        keyPath: 'k',
        keyData: 'd',
        passphrase: 'pp',
      );
      expect(copy.authType, AuthType.key);
      expect(copy.password, 'p');
      expect(copy.keyPath, 'k');
      expect(copy.keyData, 'd');
      expect(copy.passphrase, 'pp');
    });

    test('copyWith no args returns equal', () {
      const auth = SessionAuth(authType: AuthType.password, password: 'x');
      final copy = auth.copyWith();
      expect(copy, equals(auth));
    });

    test('equality for same values', () {
      const a = SessionAuth(
        authType: AuthType.key,
        password: 'p',
        keyPath: 'k',
        keyData: 'd',
        passphrase: 'pp',
      );
      const b = SessionAuth(
        authType: AuthType.key,
        password: 'p',
        keyPath: 'k',
        keyData: 'd',
        passphrase: 'pp',
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('inequality for different authType', () {
      const a = SessionAuth(authType: AuthType.password);
      const b = SessionAuth(authType: AuthType.key);
      expect(a, isNot(equals(b)));
    });

    test('inequality for different keyPath', () {
      const a = SessionAuth(keyPath: '/a');
      const b = SessionAuth(keyPath: '/b');
      expect(a, isNot(equals(b)));
    });

    test('inequality for different keyData', () {
      const a = SessionAuth(keyData: 'x');
      const b = SessionAuth(keyData: 'y');
      expect(a, isNot(equals(b)));
    });

    test('inequality for different passphrase', () {
      const a = SessionAuth(passphrase: 'x');
      const b = SessionAuth(passphrase: 'y');
      expect(a, isNot(equals(b)));
    });

    test('identical returns true', () {
      const a = SessionAuth();
      expect(a == a, isTrue);
    });

    test('not equal to other types', () {
      const a = SessionAuth();
      expect(a == Object(), isFalse);
    });

    test('keyId preserved in copyWith', () {
      const auth = SessionAuth(keyId: 'key-123', authType: AuthType.key);
      final copy = auth.copyWith(password: 'pw');
      expect(copy.keyId, 'key-123');
      expect(copy.password, 'pw');
    });

    test('keyId included in equality', () {
      const a = SessionAuth(keyId: 'k1');
      const b = SessionAuth(keyId: 'k2');
      expect(a, isNot(equals(b)));
    });

    test('keyId defaults to empty', () {
      const auth = SessionAuth();
      expect(auth.keyId, isEmpty);
    });

    group('withoutCredentials', () {
      test('clears every plaintext slot', () {
        const auth = SessionAuth(
          authType: AuthType.keyWithPassword,
          password: 'pw',
          keyPath: '/k',
          keyData: 'kd',
          passphrase: 'pp',
        );
        final cleared = auth.withoutCredentials();
        expect(cleared.password, isEmpty);
        expect(cleared.keyData, isEmpty);
        expect(cleared.passphrase, isEmpty);
      });

      test('preserves keyPath + keyId + authType', () {
        const auth = SessionAuth(
          authType: AuthType.key,
          keyId: 'kid',
          keyPath: '/k',
          keyData: 'kd',
        );
        final cleared = auth.withoutCredentials();
        expect(cleared.authType, AuthType.key);
        expect(cleared.keyId, 'kid');
        expect(cleared.keyPath, '/k');
      });

      test('promotes live values to hasStoredX markers', () {
        // No `hasStoredX` flags pre-set, but the live values
        // mean the underlying row will hold something — the
        // sanitised view must reflect that or the edit dialog
        // would render "[Saved]" badges incorrectly.
        const auth = SessionAuth(password: 'pw', keyData: '', passphrase: 'p');
        final cleared = auth.withoutCredentials();
        expect(cleared.hasStoredPassword, isTrue);
        expect(cleared.hasStoredKeyData, isFalse);
        expect(cleared.hasStoredPassphrase, isTrue);
      });

      test('keeps explicit hasStoredX markers when live values empty', () {
        const auth = SessionAuth(
          hasStoredPassword: true,
          hasStoredKeyData: true,
          hasStoredPassphrase: false,
        );
        final cleared = auth.withoutCredentials();
        expect(cleared.hasStoredPassword, isTrue);
        expect(cleared.hasStoredKeyData, isTrue);
        expect(cleared.hasStoredPassphrase, isFalse);
      });

      test('is idempotent', () {
        const auth = SessionAuth(password: 'pw', keyData: 'kd');
        final once = auth.withoutCredentials();
        final twice = once.withoutCredentials();
        expect(twice.password, isEmpty);
        expect(twice.keyData, isEmpty);
        expect(twice.hasStoredPassword, isTrue);
        expect(twice.hasStoredKeyData, isTrue);
      });
    });
  });

  group('Session equality', () {
    test('same id and fields are equal', () {
      final a = Session(
        id: 'x',
        label: 'a',
        server: const ServerAddress(host: 'h', user: 'u'),
      );
      final b = Session(
        id: 'x',
        label: 'a',
        server: const ServerAddress(host: 'h', user: 'u'),
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('different id makes not equal', () {
      final a = Session(
        id: 'x',
        label: 'a',
        server: const ServerAddress(host: 'h', user: 'u'),
      );
      final b = Session(
        id: 'y',
        label: 'a',
        server: const ServerAddress(host: 'h', user: 'u'),
      );
      expect(a, isNot(equals(b)));
    });

    test('different host makes not equal', () {
      final a = Session(
        id: 'x',
        label: 'a',
        server: const ServerAddress(host: 'h1', user: 'u'),
      );
      final b = Session(
        id: 'x',
        label: 'a',
        server: const ServerAddress(host: 'h2', user: 'u'),
      );
      expect(a, isNot(equals(b)));
    });

    test('different password makes not equal', () {
      final a = Session(
        id: 'x',
        label: 'a',
        server: const ServerAddress(host: 'h', user: 'u'),
        auth: const SessionAuth(password: 'a'),
      );
      final b = Session(
        id: 'x',
        label: 'a',
        server: const ServerAddress(host: 'h', user: 'u'),
        auth: const SessionAuth(password: 'b'),
      );
      expect(a, isNot(equals(b)));
    });

    test('different folder makes not equal', () {
      final a = Session(
        id: 'x',
        label: 'a',
        folder: 'A',
        server: const ServerAddress(host: 'h', user: 'u'),
      );
      final b = Session(
        id: 'x',
        label: 'a',
        folder: 'B',
        server: const ServerAddress(host: 'h', user: 'u'),
      );
      expect(a, isNot(equals(b)));
    });

    test('identical returns true', () {
      final a = Session(
        label: 'a',
        server: const ServerAddress(host: 'h', user: 'u'),
      );
      expect(a == a, isTrue);
    });

    test('not equal to other types', () {
      final a = Session(
        label: 'a',
        server: const ServerAddress(host: 'h', user: 'u'),
      );
      expect(a == Object(), isFalse);
    });
  });

  group('Session hasCredentials', () {
    test('true with password only', () {
      final s = Session(
        label: 'test',
        server: const ServerAddress(host: 'h', user: 'u'),
        auth: const SessionAuth(password: 'pw'),
      );
      expect(s.hasCredentials, isTrue);
    });

    test('true with keyData only', () {
      final s = Session(
        label: 'test',
        server: const ServerAddress(host: 'h', user: 'u'),
        auth: const SessionAuth(keyData: 'ssh-rsa AAA'),
      );
      expect(s.hasCredentials, isTrue);
    });

    test('true with keyId only', () {
      final s = Session(
        label: 'test',
        server: const ServerAddress(host: 'h', user: 'u'),
        auth: const SessionAuth(keyId: 'k1'),
      );
      expect(s.hasCredentials, isTrue);
    });

    test('true with keyPath only', () {
      final s = Session(
        label: 'test',
        server: const ServerAddress(host: 'h', user: 'u'),
        auth: const SessionAuth(keyPath: '/home/user/.ssh/id_rsa'),
      );
      expect(s.hasCredentials, isTrue);
    });

    test('false when all credential fields are empty', () {
      final s = Session(
        label: 'test',
        server: const ServerAddress(host: 'h', user: 'u'),
      );
      expect(s.hasCredentials, isFalse);
    });

    test('true when in-memory fields are empty but hasStoredSecret signals '
        'that the DB holds the secret — covers the startup path where the '
        'session cache is loaded without plaintext credentials', () {
      final s = Session(
        label: 'test',
        server: const ServerAddress(host: 'h', user: 'u'),
        auth: const SessionAuth(authType: AuthType.key, hasStoredKeyData: true),
      );
      expect(s.hasCredentials, isTrue);
      expect(s.isValid, isTrue);
    });
  });

  group('Session isValid', () {
    test('true with all required fields and password', () {
      final s = Session(
        label: 'test',
        server: const ServerAddress(host: 'h', user: 'u'),
        auth: const SessionAuth(password: 'pw'),
      );
      expect(s.isValid, isTrue);
    });

    test('true with keyPath credential', () {
      final s = Session(
        label: 'test',
        server: const ServerAddress(host: 'h', user: 'u'),
        auth: const SessionAuth(
          authType: AuthType.key,
          keyPath: '/home/.ssh/id_rsa',
        ),
      );
      expect(s.isValid, isTrue);
    });

    test('false when host is empty', () {
      final s = Session(
        label: 'test',
        server: const ServerAddress(host: '', user: 'u'),
        auth: const SessionAuth(password: 'pw'),
      );
      expect(s.isValid, isFalse);
    });

    test('false when user is empty', () {
      final s = Session(
        label: 'test',
        server: const ServerAddress(host: 'h', user: ''),
        auth: const SessionAuth(password: 'pw'),
      );
      expect(s.isValid, isFalse);
    });

    test('false when port out of range', () {
      final s = Session(
        label: 'test',
        server: const ServerAddress(host: 'h', port: 0, user: 'u'),
        auth: const SessionAuth(password: 'pw'),
      );
      expect(s.isValid, isFalse);
    });

    test('false when no credentials', () {
      final s = Session(
        label: 'test',
        server: const ServerAddress(host: 'h', user: 'u'),
      );
      expect(s.isValid, isFalse);
    });

    test(
      'WebDAV session with empty host / user but a stored secret is valid',
      () {
        // Regression: after the v16 schema split, host / user / port
        // are stored on `ssh_session_details` and read back as the
        // COALESCE defaults (empty / 22) for non-SSH kinds. The
        // SSH-shape `isValid` check would have rejected every saved
        // WebDAV session, breaking Connect with "WebDAV secret not
        // staged" further down the chain. The transport tuple lives
        // on `webdav_session_details` (FRB-only, async) so the
        // connect path is the authoritative validity gate for the
        // non-SSH kinds — `isValid` defers to it.
        //
        // After v17 the `isValid` gate additionally requires
        // `hasCredentials` for non-SSH rows so the session-tree
        // warning fires for password-less WebDAV rows. The
        // empty-host / empty-user case still passes the gate as
        // long as a credential is present.
        final s = Session(
          label: 'nextcloud',
          kind: SessionKind.webdav,
          server: const ServerAddress(host: '', port: 0, user: ''),
          auth: const SessionAuth(hasStoredPassword: true),
        );
        expect(s.isValid, isTrue);
      },
    );

    test('S3 session with empty host / user but a stored secret is valid', () {
      // Same regression coverage for the S3 transport — the SigV4
      // credential pair lives on `s3_session_details` +
      // SecretStore, not on the session row.
      final s = Session(
        label: 'backups',
        kind: SessionKind.s3,
        server: const ServerAddress(host: '', port: 0, user: ''),
        auth: const SessionAuth(hasStoredPassword: true),
      );
      expect(s.isValid, isTrue);
    });
  });

  group('Session.copyWith via-sentinel semantics', () {
    Session base() => Session(
      id: 'fixed',
      label: 'l',
      server: const ServerAddress(host: 'h', user: 'u'),
      viaSessionId: 'bastion-1',
      viaOverride: const ProxyJumpOverride(host: 'jump', user: 'j'),
      lastConnectedAtMs: 1000,
    );

    test('omitting viaSessionId leaves the existing value untouched', () {
      // The `_unsetVia` sentinel default distinguishes "not passed"
      // from "passed null to clear". Omitting must preserve.
      final copy = base().copyWith(label: 'new');
      expect(copy.viaSessionId, 'bastion-1');
      expect(
        copy.viaOverride,
        const ProxyJumpOverride(host: 'jump', user: 'j'),
      );
      expect(copy.lastConnectedAtMs, 1000);
    });

    test('passing null to viaSessionId clears it', () {
      final copy = base().copyWith(viaSessionId: null);
      expect(copy.viaSessionId, isNull);
      // Untouched siblings stay.
      expect(copy.viaOverride, isNotNull);
      expect(copy.lastConnectedAtMs, 1000);
    });

    test('passing a new viaSessionId replaces it', () {
      final copy = base().copyWith(viaSessionId: 'bastion-2');
      expect(copy.viaSessionId, 'bastion-2');
    });

    test('passing null to viaOverride clears it independently', () {
      final copy = base().copyWith(viaOverride: null);
      expect(copy.viaOverride, isNull);
      expect(copy.viaSessionId, 'bastion-1');
    });

    test('passing a new viaOverride replaces it', () {
      const replacement = ProxyJumpOverride(host: 'h2', port: 2200, user: 'u2');
      final copy = base().copyWith(viaOverride: replacement);
      expect(copy.viaOverride, replacement);
    });

    test('passing null to lastConnectedAtMs clears it', () {
      final copy = base().copyWith(lastConnectedAtMs: null);
      expect(copy.lastConnectedAtMs, isNull);
    });

    test('passing a new lastConnectedAtMs replaces it', () {
      final copy = base().copyWith(lastConnectedAtMs: 2000);
      expect(copy.lastConnectedAtMs, 2000);
    });

    test('copyWith preserves id and createdAt, refreshes updatedAt', () {
      final original = Session(
        id: 'keep-id',
        label: 'l',
        server: const ServerAddress(host: 'h', user: 'u'),
        createdAt: DateTime(2020),
        updatedAt: DateTime(2020),
      );
      final copy = original.copyWith(label: 'changed');
      expect(copy.id, 'keep-id');
      expect(copy.createdAt, DateTime(2020));
      expect(
        copy.updatedAt.isAfter(DateTime(2020)),
        isTrue,
        reason: 'copyWith stamps a fresh updatedAt',
      );
    });

    test('copyWith replaces notes and sortOrder when passed', () {
      final copy = base().copyWith(notes: 'a note', sortOrder: 5);
      expect(copy.notes, 'a note');
      expect(copy.sortOrder, 5);
    });
  });

  group('ProxyJumpOverride', () {
    test('defaults port to 22', () {
      const o = ProxyJumpOverride(host: 'jump', user: 'j');
      expect(o.port, 22);
    });

    test('equality is true for identical field sets', () {
      const a = ProxyJumpOverride(host: 'h', port: 2200, user: 'u');
      const b = ProxyJumpOverride(host: 'h', port: 2200, user: 'u');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('identical short-circuit returns true', () {
      const a = ProxyJumpOverride(host: 'h', user: 'u');
      expect(a == a, isTrue);
    });

    test('inequality on each field independently', () {
      const base = ProxyJumpOverride(host: 'h', port: 22, user: 'u');
      expect(
        base,
        isNot(equals(const ProxyJumpOverride(host: 'x', user: 'u'))),
      );
      expect(
        base,
        isNot(equals(const ProxyJumpOverride(host: 'h', port: 23, user: 'u'))),
      );
      expect(
        base,
        isNot(equals(const ProxyJumpOverride(host: 'h', user: 'x'))),
      );
    });

    test('not equal to a different type', () {
      const a = ProxyJumpOverride(host: 'h', user: 'u');
      const Object other = 'h:22:u';
      expect(a == other, isFalse);
    });
  });

  group('Session.hasProxyJump', () {
    Session withVia({String? viaSessionId, ProxyJumpOverride? viaOverride}) =>
        Session(
          label: 'l',
          server: const ServerAddress(host: 'h', user: 'u'),
          viaSessionId: viaSessionId,
          viaOverride: viaOverride,
        );

    test('false with neither bastion set', () {
      expect(withVia().hasProxyJump, isFalse);
    });

    test('true with a saved-session bastion', () {
      expect(withVia(viaSessionId: 'b').hasProxyJump, isTrue);
    });

    test('true with a one-off override', () {
      expect(
        withVia(
          viaOverride: const ProxyJumpOverride(host: 'h', user: 'u'),
        ).hasProxyJump,
        isTrue,
      );
    });
  });

  group('Session kind getters and capabilities', () {
    Session of(SessionKind kind) => Session(
      label: 'l',
      kind: kind,
      server: const ServerAddress(host: 'h', user: 'u'),
    );

    test('isSsh / isWebDav / isS3 are mutually exclusive per kind', () {
      final ssh = of(SessionKind.ssh);
      expect(ssh.isSsh, isTrue);
      expect(ssh.isWebDav, isFalse);
      expect(ssh.isS3, isFalse);

      final dav = of(SessionKind.webdav);
      expect(dav.isSsh, isFalse);
      expect(dav.isWebDav, isTrue);
      expect(dav.isS3, isFalse);

      final s3 = of(SessionKind.s3);
      expect(s3.isSsh, isFalse);
      expect(s3.isWebDav, isFalse);
      expect(s3.isS3, isTrue);
    });

    test('hasTerminal is true only for SSH', () {
      // Only SSH carries a remote shell today; WebDAV / S3 are file
      // transports with no PTY. The UI dispatch gates the terminal
      // companion button off this.
      expect(of(SessionKind.ssh).hasTerminal, isTrue);
      expect(of(SessionKind.webdav).hasTerminal, isFalse);
      expect(of(SessionKind.s3).hasTerminal, isFalse);
    });

    test('hasFileBrowser is true for every kind', () {
      // SSH→SFTP, WebDAV→PROPFIND, S3→ListObjectsV2 all expose a file
      // browser.
      expect(of(SessionKind.ssh).hasFileBrowser, isTrue);
      expect(of(SessionKind.webdav).hasFileBrowser, isTrue);
      expect(of(SessionKind.s3).hasFileBrowser, isTrue);
    });

    test('SessionKindCapabilities extension matches the Session getters', () {
      // Same answer reachable from a bare SessionKind (Connection.kind
      // holds no Session). The extension is the single source.
      for (final kind in SessionKind.values) {
        expect(of(kind).hasTerminal, kind.hasTerminal, reason: 'kind=$kind');
        expect(
          of(kind).hasFileBrowser,
          kind.hasFileBrowser,
          reason: 'kind=$kind',
        );
      }
    });
  });

  group('Session equality — remaining fields', () {
    Session base() => Session(
      id: 'x',
      label: 'a',
      server: const ServerAddress(host: 'h', user: 'u'),
    );

    test('different kind makes not equal', () {
      expect(base(), isNot(equals(base().copyWith(kind: SessionKind.webdav))));
    });

    test('different viaSessionId makes not equal', () {
      expect(
        base().copyWith(viaSessionId: 'a'),
        isNot(equals(base().copyWith(viaSessionId: 'b'))),
      );
    });

    test('different viaOverride makes not equal', () {
      expect(
        base().copyWith(
          viaOverride: const ProxyJumpOverride(host: 'h1', user: 'u'),
        ),
        isNot(
          equals(
            base().copyWith(
              viaOverride: const ProxyJumpOverride(host: 'h2', user: 'u'),
            ),
          ),
        ),
      );
    });

    test('different notes makes not equal', () {
      expect(
        base().copyWith(notes: 'one'),
        isNot(equals(base().copyWith(notes: 'two'))),
      );
    });

    test('different sortOrder makes not equal', () {
      expect(
        base().copyWith(sortOrder: 1),
        isNot(equals(base().copyWith(sortOrder: 2))),
      );
    });

    test('different lastConnectedAtMs makes not equal', () {
      expect(
        base().copyWith(lastConnectedAtMs: 1),
        isNot(equals(base().copyWith(lastConnectedAtMs: 2))),
      );
    });

    test('different auth makes not equal', () {
      expect(
        base(),
        isNot(equals(base().copyWith(auth: const SessionAuth(password: 'p')))),
      );
    });

    test('equal across every field hashes equal', () {
      final a = Session(
        id: 'x',
        label: 'a',
        folder: 'F',
        kind: SessionKind.ssh,
        server: const ServerAddress(host: 'h', port: 2200, user: 'u'),
        auth: const SessionAuth(password: 'p'),
        createdAt: DateTime(2021),
        updatedAt: DateTime(2021),
        viaSessionId: 'b',
        notes: 'n',
        sortOrder: 3,
        lastConnectedAtMs: 99,
      );
      final b = Session(
        id: 'x',
        label: 'a',
        folder: 'F',
        kind: SessionKind.ssh,
        server: const ServerAddress(host: 'h', port: 2200, user: 'u'),
        auth: const SessionAuth(password: 'p'),
        createdAt: DateTime(2099),
        updatedAt: DateTime(2099),
        viaSessionId: 'b',
        notes: 'n',
        sortOrder: 3,
        lastConnectedAtMs: 99,
      );
      // createdAt / updatedAt are intentionally excluded from == and
      // hashCode (two loads of the same row differ only by load time).
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });
  });

  group('Session convenience accessors', () {
    test('host / port / user / authType / credential getters delegate', () {
      final s = Session(
        label: 'l',
        server: const ServerAddress(host: 'h.example', port: 2022, user: 'bob'),
        auth: const SessionAuth(
          authType: AuthType.keyWithPassword,
          keyId: 'kid',
          password: 'pw',
          keyPath: '/k',
          keyData: 'kd',
          passphrase: 'pp',
        ),
      );
      expect(s.host, 'h.example');
      expect(s.port, 2022);
      expect(s.user, 'bob');
      expect(s.authType, AuthType.keyWithPassword);
      expect(s.keyId, 'kid');
      expect(s.password, 'pw');
      expect(s.keyPath, '/k');
      expect(s.keyData, 'kd');
      expect(s.passphrase, 'pp');
    });
  });

  group('SessionAuth.hasStoredSecret', () {
    test('false when no slot is flagged stored', () {
      const auth = SessionAuth();
      expect(auth.hasStoredSecret, isFalse);
    });

    test('true when any single slot is flagged stored', () {
      expect(const SessionAuth(hasStoredPassword: true).hasStoredSecret, true);
      expect(const SessionAuth(hasStoredKeyData: true).hasStoredSecret, true);
      expect(
        const SessionAuth(hasStoredPassphrase: true).hasStoredSecret,
        true,
      );
    });
  });

  group('Session.withoutCredentials', () {
    test('strips plaintext on the session while preserving identity', () {
      final s = Session(
        id: 'sid',
        label: 'l',
        server: const ServerAddress(host: 'h', user: 'u'),
        auth: const SessionAuth(password: 'pw', keyData: 'kd'),
      );
      final stripped = s.withoutCredentials();
      expect(stripped.id, 'sid');
      expect(stripped.password, isEmpty);
      expect(stripped.keyData, isEmpty);
      // The presence markers promote so hasCredentials stays true.
      expect(stripped.auth.hasStoredPassword, isTrue);
      expect(stripped.auth.hasStoredKeyData, isTrue);
      expect(stripped.hasCredentials, isTrue);
    });
  });

  group('Session.extras', () {
    Session base() => Session(
      id: 'fixed-id',
      label: 'l',
      server: const ServerAddress(host: 'h', user: 'u'),
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

    test('default is empty', () {
      expect(base().extras, isEmpty);
    });

    test('extras map is unmodifiable', () {
      final s = base().withExtras({'k': true});
      expect(() => (s.extras as dynamic)['x'] = 1, throwsUnsupportedError);
    });

    test('typed accessors return null for missing or wrong-typed entries', () {
      final s = base().withExtras({
        'flag': true,
        'name': 'r',
        'count': 7,
        'mismatch': 'oops',
      });
      expect(s.extrasBool('flag'), isTrue);
      expect(s.extrasStr('name'), 'r');
      expect(s.extrasInt('count'), 7);
      expect(s.extrasBool('missing'), isNull);
      expect(s.extrasInt('mismatch'), isNull);
    });

    test('extrasInt coerces a double-valued entry to int (truncating)', () {
      // JSON round-trips can land a whole number as a double; the
      // typed accessor must coerce rather than return null so a
      // numeric flag survives a decode.
      final s = base().withExtras({'n': 7.9});
      expect(s.extrasInt('n'), 7);
    });

    test('extrasStr returns null for a non-string entry', () {
      final s = base().withExtras({'flag': true});
      expect(s.extrasStr('flag'), isNull);
    });

    test('withExtras merges and removes via null', () {
      final s = base().withExtras({'a': 1, 'b': 'x'});
      final merged = s.withExtras({'b': null, 'c': true});
      expect(merged.extras.containsKey('b'), isFalse);
      expect(merged.extras['a'], 1);
      expect(merged.extras['c'], isTrue);
    });

    test('toJson omits empty extras, fromJson tolerates missing key', () {
      final s = base();
      expect(s.toJson().containsKey('extras'), isFalse);
      final round = Session.fromJson({...s.toJson()});
      expect(round.extras, isEmpty);
    });

    test('toJson includes extras when non-empty and round-trips', () {
      final s = base().withExtras({'record': true, 'tag': 'prod'});
      final json = s.toJsonWithCredentials();
      expect(json['extras'], {'record': true, 'tag': 'prod'});
      final back = Session.fromJson(json);
      expect(back.extras['record'], isTrue);
      expect(back.extras['tag'], 'prod');
    });

    test('fromJson tolerates a JSON-encoded extras string', () {
      final s = base();
      final json = s.toJson();
      json['extras'] = '{"k":42}';
      final back = Session.fromJson(json);
      expect(back.extras['k'], 42);
    });

    test('fromJson silently drops corrupt extras', () {
      final s = base();
      final json = s.toJson();
      json['extras'] = '{not-json';
      final back = Session.fromJson(json);
      expect(back.extras, isEmpty);
    });

    test('equality includes extras', () {
      final a = base().withExtras({'k': 1});
      final b = base().copyWith().withExtras({'k': 1});
      final c = base().withExtras({'k': 2});
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });
}
