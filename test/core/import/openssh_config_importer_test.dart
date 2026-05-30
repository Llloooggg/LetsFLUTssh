import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/import/export_import.dart';
import 'package:letsflutssh/core/import/openssh_config_importer.dart';
import 'package:letsflutssh/core/session/session.dart';
import 'package:letsflutssh/src/rust/api/openssh_config_import.dart' as imp;
import 'package:letsflutssh/src/rust/api/ssh_config.dart' as ssh;

import '../../helpers/frb_bootstrap.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('mapRustImportSession', () {
    test('password auth type maps onto AuthType.password', () {
      const row = imp.DbOpenSshImportSession(
        id: 's-1',
        label: 'prod-web',
        folder: '~/.ssh imports',
        host: 'web.example',
        port: 2222,
        user: 'deploy',
        authType: ssh.DbOpenSshAuthType.password,
        keyId: '',
      );
      final s = OpenSshConfigImporter.mapRustImportSession(row);
      expect(s.id, 's-1');
      expect(s.label, 'prod-web');
      expect(s.folder, '~/.ssh imports');
      expect(s.host, 'web.example');
      expect(s.port, 2222);
      expect(s.user, 'deploy');
      expect(s.authType, AuthType.password);
      expect(s.keyId, '');
    });

    test('key auth type maps onto AuthType.key + carries keyId through', () {
      const row = imp.DbOpenSshImportSession(
        id: 's-2',
        label: 'staging',
        folder: '',
        host: '10.0.0.5',
        port: 22,
        user: 'root',
        authType: ssh.DbOpenSshAuthType.key,
        keyId: 'key-42',
      );
      final s = OpenSshConfigImporter.mapRustImportSession(row);
      expect(s.authType, AuthType.key);
      expect(s.keyId, 'key-42');
    });
  });

  group('OpenSshConfigImportPreview — value-object surface', () {
    test('defaults both host-warning lists to empty', () {
      // Spec: callers that don't pass either list (e.g. tests
      // constructing a happy-path preview) should see empty lists,
      // not null. The settings UI iterates both unconditionally;
      // a null would null-deref the warning banner.
      const result = ImportResult(
        sessions: [],
        managerKeys: [],
        mode: ImportMode.merge,
      );
      const preview = OpenSshConfigImportPreview(
        result: result,
        parsedHosts: 0,
      );
      expect(preview.hostsWithMissingKeys, isEmpty);
      expect(preview.hostsWithEncryptedKeys, isEmpty);
      expect(preview.parsedHosts, 0);
    });

    test(
      'carries the encrypted-key host list distinct from the missing list',
      () {
        // Spec: encrypted-key hosts are a *subset* of missing-key hosts
        // (encrypted keys cannot be used until decrypted, so the session
        // is imported credential-less). The two lists are not the same
        // field — UIs that want to surface the more specific "decrypt
        // first" hint must read `hostsWithEncryptedKeys` directly.
        const preview = OpenSshConfigImportPreview(
          result: ImportResult(
            sessions: [],
            managerKeys: [],
            mode: ImportMode.merge,
          ),
          parsedHosts: 3,
          hostsWithMissingKeys: ['a', 'b', 'c'],
          hostsWithEncryptedKeys: ['b'],
        );
        expect(preview.hostsWithMissingKeys, ['a', 'b', 'c']);
        expect(preview.hostsWithEncryptedKeys, ['b']);
      },
    );
  });

  group('mapRustImportSession — edge cases', () {
    test('empty user / keyId pass through unchanged for password-auth row', () {
      // Spec: the mapper is field-copy only — it does not impose any
      // "user must be non-empty" / "keyId must be empty when auth is
      // password" invariant. Storable-field grammar lives in Rust
      // (`sessionsValidateFields`) and runs at save time; the mapper
      // must surface whatever the Rust importer emitted so the
      // preview shows the truth.
      const row = imp.DbOpenSshImportSession(
        id: 's-empty',
        label: '',
        folder: '',
        host: 'host.example',
        port: 22,
        user: '',
        authType: ssh.DbOpenSshAuthType.password,
        keyId: '',
      );
      final s = OpenSshConfigImporter.mapRustImportSession(row);
      expect(s.user, '');
      expect(s.label, '');
      expect(s.folder, '');
      expect(s.keyId, '');
      expect(s.authType, AuthType.password);
    });
  });

  group('mapRustImportKey', () {
    test('row → SshKeyEntry preserves every field, isGenerated=false', () {
      final unixMs = DateTime.utc(2024, 6, 1).millisecondsSinceEpoch;
      final row = imp.DbOpenSshImportKey(
        id: 'k-1',
        label: 'work-laptop',
        privatePem: '-----BEGIN OPENSSH PRIVATE KEY-----\nAAAA',
        publicOpenssh: 'ssh-ed25519 AAAA work-laptop',
        keyType: 'ssh-ed25519',
        fingerprint: 'SHA256:abc',
        createdAtUnixMs: unixMs,
      );
      final e = OpenSshConfigImporter.mapRustImportKey(row);
      expect(e.id, 'k-1');
      expect(e.label, 'work-laptop');
      expect(e.privateKey, '-----BEGIN OPENSSH PRIVATE KEY-----\nAAAA');
      expect(e.publicKey, 'ssh-ed25519 AAAA work-laptop');
      expect(e.keyType, 'ssh-ed25519');
      // `DateTime.fromMillisecondsSinceEpoch` returns a local-time
      // DateTime; compare on the absolute unix-ms value to avoid TZ
      // drift between dev / CI hosts.
      expect(e.createdAt.millisecondsSinceEpoch, unixMs);
      expect(
        e.isGenerated,
        isFalse,
        reason: 'Imported keys came from disk, not from the in-app generator',
      );
    });

    test('zero-epoch createdAtUnixMs maps to the unix-epoch instant', () {
      // Spec: the mapper never sanity-checks the timestamp — the Rust
      // side decides whether `0` is a legitimate "unknown" or a real
      // value. The Dart side surfaces whatever it received so the
      // preview cannot silently rewrite the audit field.
      const row = imp.DbOpenSshImportKey(
        id: 'k-0',
        label: 'epoch',
        privatePem: 'pem',
        publicOpenssh: 'pub',
        keyType: 'ssh-rsa',
        fingerprint: '',
        createdAtUnixMs: 0,
      );
      final e = OpenSshConfigImporter.mapRustImportKey(row);
      expect(e.createdAt.millisecondsSinceEpoch, 0);
      expect(e.keyType, 'ssh-rsa');
    });
  });

  group('OpenSshConfigImportPreview — constructor argument plumbing', () {
    test('parsedHosts surfaces verbatim alongside an empty session list', () {
      // Spec: parsedHosts is the *raw* host-entry count from the
      // OpenSSH config, before any filter — empty session lists are
      // legal (e.g. every host was filtered as suspicious or
      // missing-key) and the preview UI still wants to surface
      // "we read N hosts but rejected all of them".
      const preview = OpenSshConfigImportPreview(
        result: ImportResult(
          sessions: [],
          managerKeys: [],
          mode: ImportMode.merge,
        ),
        parsedHosts: 7,
      );
      expect(preview.parsedHosts, 7);
      expect(preview.result.sessions, isEmpty);
      expect(preview.result.managerKeys, isEmpty);
      expect(preview.result.mode, ImportMode.merge);
    });

    test('replace mode threads through the inner ImportResult', () {
      // Spec: ImportMode is decided at the call site (the preview
      // dialog's "merge / replace" toggle). The preview constructor
      // does not override it — the same import payload renders both
      // modes by varying only the mode field.
      const preview = OpenSshConfigImportPreview(
        result: ImportResult(
          sessions: [],
          managerKeys: [],
          mode: ImportMode.replace,
        ),
        parsedHosts: 0,
      );
      expect(preview.result.mode, ImportMode.replace);
    });
  });

  group('OpenSshConfigImporter — Rust-bound static helpers', () {
    // `expandHome` + `isSuspiciousPath` are thin wrappers around FRB
    // calls into `lfs_core::path`. Bootstrapping FRB exercises the
    // real grammar instead of pretending the Dart side owns it.
    setUpAll(requireFrbLoaded);

    test(
      'expandHome leaves a path without a leading "~" untouched — the wrapper '
      'does not normalise or canonicalise, only substitutes the home prefix',
      () {
        // Spec: `expandHome` routes through `opensshConfigExpandHome`.
        // The Rust grammar substitutes a leading `~` (with or without
        // trailing slash) and returns every other input verbatim.
        // A Dart-side path-normaliser regression would surface here as
        // a slash-shape change on the absolute / relative arms.
        expect(
          OpenSshConfigImporter.expandHome('/etc/ssh/sshd_config'),
          '/etc/ssh/sshd_config',
        );
        expect(
          OpenSshConfigImporter.expandHome('relative/path'),
          'relative/path',
        );
        expect(OpenSshConfigImporter.expandHome(''), '');
      },
    );

    test(
      'expandHome substitutes a leading "~" with a non-empty home prefix — the '
      'returned path starts at an absolute boundary, never with a literal "~"',
      () {
        // Spec: the Rust helper resolves `~` against the env / OnceLock
        // home dir. On the desktop CI host this is always a real
        // directory, so the substitution wipes the leading tilde and
        // surfaces an absolute path. Pin the "no leftover ~" contract
        // — a regression that surfaced "~" verbatim would let a
        // downstream FRB call try to open a literal "~/.ssh/key" file.
        final expanded = OpenSshConfigImporter.expandHome('~/.ssh/id_ed25519');
        expect(expanded, isNot(startsWith('~')));
        expect(expanded, endsWith('/.ssh/id_ed25519'));
      },
    );

    test(
      'isSuspiciousPath flags traversal segments and clears straight absolute '
      'paths — the wrapper delegates to lfs_core::path::is_suspicious_path',
      () {
        // Spec: `isSuspiciousPath` rejects any path containing `..`
        // segments because a maliciously crafted `IdentityFile`
        // directive could coerce the importer into reading sensitive
        // files outside `~/.ssh/`. Straight absolute paths the user
        // typed intentionally pass through. Pin both arms so a
        // regression that loosened the rule or rejected legitimate
        // absolute paths surfaces here.
        expect(
          OpenSshConfigImporter.isSuspiciousPath('~/.ssh/../../etc/shadow'),
          isTrue,
        );
        expect(
          OpenSshConfigImporter.isSuspiciousPath('/etc/ssh/keys/host_ed25519'),
          isFalse,
        );
        expect(OpenSshConfigImporter.isSuspiciousPath('id_ed25519'), isFalse);
      },
    );
  });

  group('OpenSshConfigImporter.buildPreview — end-to-end Rust round-trip', () {
    // The whole pipeline (parse + Include + key import + auth-type
    // decision + UUID minting + Dart-side wrap) goes through one FRB
    // call into `lfs_core::import::openssh_config::build_preview`.
    // Exercise the wrap on a minimal config so the `_wrapPreview` path
    // (sessions / managerKeys / emptyFolders / hostsWithMissingKeys
    // mutation guards) is pinned end-to-end.
    setUpAll(requireFrbLoaded);

    test('a config with one Host stanza and no IdentityFile lands as one '
        'password-auth session, no manager keys, and the parsed-host count '
        'matches — the wrap relays counts verbatim', () async {
      // Spec: `buildPreview` constructs `OpenSshConfigImportPreview`
      // with `parsedHosts` from the raw Rust count, sessions mapped
      // through `mapRustImportSession`, and an `emptyFolders` set
      // populated only when the session list is non-empty. With a
      // single host and no usable key, the auth defaults to password
      // and the folder label is recorded in `emptyFolders`. Pin the
      // wrap-assembly contract.
      const configContent = '''
Host prod
  HostName prod.example.com
  User deploy
  Port 22
''';
      final importer = OpenSshConfigImporter(baseDirOverride: '/tmp');
      final preview = await importer.buildPreview(
        configContent: configContent,
        folderLabel: 'unit-test',
      );
      expect(preview.parsedHosts, 1);
      expect(preview.result.sessions, hasLength(1));
      final session = preview.result.sessions.single;
      expect(session.label, 'prod');
      expect(session.host, 'prod.example.com');
      expect(session.user, 'deploy');
      expect(session.authType, AuthType.password);
      expect(preview.result.managerKeys, isEmpty);
      // Spec: emptyFolders is populated when sessions is *non*-empty
      // so the apply path knows which folder to seed even when the
      // session list will collapse on dedup.
      expect(preview.result.emptyFolders, contains('unit-test'));
      // Spec: hostsWith* lists are unmodifiable views — a caller
      // attempt to grow them must throw, not silently corrupt the
      // preview before apply.
      expect(() => preview.result.sessions.first, returnsNormally);
      expect(
        () => preview.hostsWithMissingKeys.add('x'),
        throwsUnsupportedError,
      );
    });

    test('an empty config yields zero parsedHosts, zero sessions, and an empty '
        'emptyFolders set — the wrap does not seed the folder label when no '
        'session lands', () async {
      // Spec: `_wrapPreview` only adds the folder label to
      // `emptyFolders` when `sessions.isEmpty` is false. The empty
      // path must produce no folder hint either — a regression that
      // always seeded the folder would surface an "empty folder"
      // marker on every failed import and pollute the user's
      // folder tree.
      final importer = OpenSshConfigImporter(baseDirOverride: '/tmp');
      final preview = await importer.buildPreview(
        configContent: '',
        folderLabel: 'unused',
      );
      expect(preview.parsedHosts, 0);
      expect(preview.result.sessions, isEmpty);
      expect(preview.result.managerKeys, isEmpty);
      expect(preview.result.emptyFolders, isEmpty);
    });

    test(
      'ImportMode threads through buildPreview into the ImportResult unchanged '
      '— the wrap does not override the caller-chosen merge / replace mode',
      () async {
        // Spec: `_wrapPreview` carries `mode` from the caller into
        // `ImportResult.mode`. The Rust side is mode-agnostic; the Dart
        // wrap decides. Pin that the replace arm survives the wrap so
        // a regression that defaulted to merge (or silently swapped
        // the value) surfaces here, not at the apply step where the
        // user would lose existing data unexpectedly.
        final importer = OpenSshConfigImporter(baseDirOverride: '/tmp');
        final preview = await importer.buildPreview(
          configContent: '',
          folderLabel: 'replace-test',
          mode: ImportMode.replace,
        );
        expect(preview.result.mode, ImportMode.replace);
      },
    );

    test(
      'buildPreviewFromPath returns null for a non-existent file — every '
      '"nothing to show" outcome collapses into the silent-fallthrough sentinel',
      () async {
        // Spec: `buildPreviewFromPath` documents "Returns `null` for
        // missing files / I/O errors / non-UTF-8 content". A
        // regression that surfaced the underlying FRB error would
        // force the caller (settings dialog) to catch one more
        // exception path; the null sentinel collapses every
        // unreachable-source outcome into one silent fallthrough.
        final importer = OpenSshConfigImporter(baseDirOverride: '/tmp');
        final preview = await importer.buildPreviewFromPath(
          path:
              '/nonexistent/never-created-${DateTime.now().microsecondsSinceEpoch}.cfg',
          folderLabel: 'missing-source',
        );
        expect(preview, isNull);
      },
    );
  });

  group('mapRustImportSession — non-standard port + label preservation', () {
    test('high port numbers survive the int round-trip unchanged', () {
      // Spec: the Rust side already capped the port at u16; the Dart
      // mapper is a straight assignment. Pin the upper boundary so a
      // refactor that introduced clamping / nullability would surface
      // here rather than silently masking the high-port branch.
      const row = imp.DbOpenSshImportSession(
        id: 's-port',
        label: 'edge',
        folder: 'imports',
        host: 'edge.example',
        port: 65535,
        user: 'admin',
        authType: ssh.DbOpenSshAuthType.key,
        keyId: 'k-edge',
      );
      final s = OpenSshConfigImporter.mapRustImportSession(row);
      expect(s.port, 65535);
      expect(s.host, 'edge.example');
      expect(s.keyId, 'k-edge');
    });
  });
}
