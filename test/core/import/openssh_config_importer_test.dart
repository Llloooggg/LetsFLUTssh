import 'package:flutter_test/flutter_test.dart';
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
