import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/import/openssh_config_importer.dart';
import 'package:letsflutssh/core/security/key_store.dart';
import 'package:letsflutssh/core/session/session.dart';
import 'package:letsflutssh/features/settings/export_import.dart';

void main() {
  group('OpenSshConfigImporter', () {
    late String realPem;
    late String otherPem;

    setUpAll(() {
      // Generating Ed25519 is fast (no isolate needed).
      realPem = KeyStore.generateKeyPair(SshKeyType.ed25519, 'test').privateKey;
      otherPem = KeyStore.generateKeyPair(
        SshKeyType.ed25519,
        'other',
      ).privateKey;
    });

    OpenSshConfigImporter importerWith(Map<String, String> files) {
      return OpenSshConfigImporter(readPem: (path) => files[path]);
    }

    test('empty config produces empty result', () {
      final preview = importerWith(
        {},
      ).buildPreview(configContent: '', folderLabel: 'Imported');
      expect(preview.result.sessions, isEmpty);
      expect(preview.result.managerKeys, isEmpty);
      expect(preview.parsedHosts, 0);
      expect(preview.hostsWithMissingKeys, isEmpty);
      expect(preview.result.emptyFolders, isEmpty);
    });

    test('hosts without IdentityFile import with password auth and no key', () {
      final preview = importerWith({}).buildPreview(
        configContent: '''
Host bastion
    HostName bastion.example.com
    User ubuntu
    Port 2222
''',
        folderLabel: 'Imported',
      );
      expect(preview.result.sessions, hasLength(1));
      final s = preview.result.sessions.first;
      expect(s.label, 'bastion');
      expect(s.folder, 'Imported');
      expect(s.host, 'bastion.example.com');
      expect(s.port, 2222);
      expect(s.user, 'ubuntu');
      expect(s.authType, AuthType.password);
      expect(s.keyId, isEmpty);
      expect(preview.result.managerKeys, isEmpty);
      expect(preview.hostsWithMissingKeys, isEmpty);
    });

    test(
      'IdentityFile declared but unreadable -> session imported, flagged',
      () {
        final preview = importerWith({}).buildPreview(
          configContent: '''
Host lost
    HostName lost.example.com
    User x
    IdentityFile /nonexistent/id_rsa
''',
          folderLabel: 'Imported',
        );
        expect(preview.result.sessions, hasLength(1));
        expect(preview.result.sessions.first.authType, AuthType.password);
        expect(preview.result.sessions.first.keyId, isEmpty);
        expect(preview.hostsWithMissingKeys, ['lost']);
      },
    );

    test('IdentityFile found -> session references key, authType=key', () {
      const keyPath = '/home/u/.ssh/id_ed25519';
      final preview = importerWith({keyPath: realPem}).buildPreview(
        configContent:
            '''
Host withkey
    HostName withkey.example.com
    User u
    IdentityFile $keyPath
''',
        folderLabel: 'Imported',
      );
      expect(preview.result.sessions, hasLength(1));
      expect(preview.result.managerKeys, hasLength(1));
      final s = preview.result.sessions.first;
      final k = preview.result.managerKeys.first;
      expect(s.authType, AuthType.key);
      expect(s.keyId, k.id);
      expect(k.label, 'id_ed25519');
      expect(preview.hostsWithMissingKeys, isEmpty);
    });

    test('same key path used by two hosts is deduped in managerKeys', () {
      const keyPath = '/home/u/.ssh/id_ed25519';
      final preview = importerWith({keyPath: realPem}).buildPreview(
        configContent:
            '''
Host a
    HostName a.example.com
    User u
    IdentityFile $keyPath

Host b
    HostName b.example.com
    User u
    IdentityFile $keyPath
''',
        folderLabel: 'Imported',
      );
      expect(preview.result.sessions, hasLength(2));
      expect(preview.result.managerKeys, hasLength(1));
      final keyId = preview.result.managerKeys.first.id;
      expect(preview.result.sessions.every((s) => s.keyId == keyId), isTrue);
    });

    test('different keys produce separate manager entries', () {
      final preview = importerWith({'/keys/a': realPem, '/keys/b': otherPem})
          .buildPreview(
            configContent: '''
Host a
    HostName a.example.com
    User u
    IdentityFile /keys/a
Host b
    HostName b.example.com
    User u
    IdentityFile /keys/b
''',
            folderLabel: 'Imported',
          );
      expect(preview.result.managerKeys, hasLength(2));
      final ids = preview.result.managerKeys.map((k) => k.id).toSet();
      expect(ids, hasLength(2));
    });

    test('multiple IdentityFile entries: first readable wins', () {
      const goodPath = '/keys/good';
      final preview =
          importerWith({
            goodPath: realPem,
            // second path missing from map
          }).buildPreview(
            configContent:
                '''
Host multi
    HostName multi.example.com
    User u
    IdentityFile /keys/missing
    IdentityFile $goodPath
''',
            folderLabel: 'Imported',
          );
      expect(preview.result.sessions.first.authType, AuthType.key);
      expect(preview.result.managerKeys, hasLength(1));
      expect(preview.hostsWithMissingKeys, isEmpty);
    });

    test('wildcards and global scope are skipped', () {
      final preview = importerWith({}).buildPreview(
        configContent: '''
User global
Host *
    User everyone
Host *.internal
    User devops
Host real
    HostName real.example.com
    User alice
''',
        folderLabel: 'Imported',
      );
      expect(preview.result.sessions, hasLength(1));
      expect(preview.result.sessions.first.label, 'real');
      expect(preview.result.sessions.first.user, 'alice');
    });

    test('Host alias is used when HostName is absent', () {
      final preview = importerWith({}).buildPreview(
        configContent: 'Host aliasonly\n    User u\n',
        folderLabel: 'Imported',
      );
      expect(preview.result.sessions.first.host, 'aliasonly');
      expect(preview.result.sessions.first.label, 'aliasonly');
    });

    test('missing User defaults to empty string', () {
      final preview = importerWith({}).buildPreview(
        configContent: 'Host nouser\n    HostName nouser.example.com\n',
        folderLabel: 'Imported',
      );
      expect(preview.result.sessions.first.user, '');
    });

    test('emptyFolders contains folder label only when sessions exist', () {
      final preview = importerWith({}).buildPreview(
        configContent: 'Host a\n    HostName a.example.com\n',
        folderLabel: 'My Folder',
      );
      expect(preview.result.emptyFolders, {'My Folder'});
    });

    test('folderLabel is applied to every imported session', () {
      final preview = importerWith({}).buildPreview(
        configContent: '''
Host a
    HostName a.example.com
Host b
    HostName b.example.com
''',
        folderLabel: 'Imported 2026-04-15',
      );
      expect(
        preview.result.sessions.every((s) => s.folder == 'Imported 2026-04-15'),
        isTrue,
      );
    });

    test('mode defaults to merge, can be overridden', () {
      final merge = importerWith({}).buildPreview(
        configContent: 'Host a\n    HostName a.example.com\n',
        folderLabel: 'f',
      );
      expect(merge.result.mode, ImportMode.merge);
      final replace = importerWith({}).buildPreview(
        configContent: 'Host a\n    HostName a.example.com\n',
        folderLabel: 'f',
        mode: ImportMode.replace,
      );
      expect(replace.result.mode, ImportMode.replace);
    });

    test('invalid PEM content is skipped gracefully', () {
      final preview =
          importerWith({
            '/keys/bad': 'PRIVATE KEY but not a real one',
          }).buildPreview(
            configContent: '''
Host bad
    HostName bad.example.com
    User u
    IdentityFile /keys/bad
''',
            folderLabel: 'Imported',
          );
      expect(preview.result.sessions, hasLength(1));
      expect(preview.result.sessions.first.authType, AuthType.password);
      expect(preview.result.managerKeys, isEmpty);
      expect(preview.hostsWithMissingKeys, ['bad']);
    });

    test('expandHome expands leading ~', () {
      // Smoke test — full expansion depends on platform HOME.
      expect(OpenSshConfigImporter.expandHome('no-tilde'), 'no-tilde');
      expect(OpenSshConfigImporter.expandHome('/absolute'), '/absolute');
      expect(OpenSshConfigImporter.expandHome('~/foo'), isNot(startsWith('~')));
    });
  });
}
