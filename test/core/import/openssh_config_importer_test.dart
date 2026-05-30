import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/import/export_import.dart';
import 'package:letsflutssh/core/import/openssh_config_importer.dart';
import 'package:letsflutssh/core/session/session.dart';
import 'package:letsflutssh/src/rust/api/openssh_config_import.dart' as imp;
import 'package:letsflutssh/src/rust/api/ssh_config.dart' as ssh;

void main() {
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
  });
}
