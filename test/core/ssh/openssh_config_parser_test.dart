import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/session/session.dart' show AuthType;
import 'package:letsflutssh/core/ssh/openssh_config_parser.dart';

void main() {
  group('parseOpenSshConfig', () {
    test('empty input returns empty list', () {
      expect(parseOpenSshConfig(''), isEmpty);
      expect(parseOpenSshConfig('   \n\n\t\n'), isEmpty);
    });

    test('comments and blank lines are ignored', () {
      const input = '''
# top comment
  # indented comment

Host example
    # inline block comment
    HostName example.com  # trailing comment
    User alice
''';
      final entries = parseOpenSshConfig(input);
      expect(entries, hasLength(1));
      expect(entries.first.host, 'example');
      expect(entries.first.hostName, 'example.com');
      expect(entries.first.user, 'alice');
    });

    test('parses all supported directives', () {
      const input = '''
Host work
    HostName work.example.com
    User bob
    Port 2222
    IdentityFile ~/.ssh/work_rsa
''';
      final entries = parseOpenSshConfig(input);
      expect(entries, hasLength(1));
      final e = entries.first;
      expect(e.host, 'work');
      expect(e.hostName, 'work.example.com');
      expect(e.user, 'bob');
      expect(e.port, 2222);
      expect(e.identityFiles, ['~/.ssh/work_rsa']);
    });

    test('skips wildcard patterns', () {
      const input = '''
Host *
    User everyone
Host *.internal
    User devops
Host !deny
    User nobody
Host real
    HostName real.example.com
''';
      final entries = parseOpenSshConfig(input);
      expect(entries.map((e) => e.host), ['real']);
    });

    test('Host line with multiple aliases creates entry per alias', () {
      const input = '''
Host db db-primary db-replica
    HostName 10.0.0.5
    User postgres
''';
      final entries = parseOpenSshConfig(input);
      expect(entries.map((e) => e.host), ['db', 'db-primary', 'db-replica']);
      expect(entries.every((e) => e.hostName == '10.0.0.5'), isTrue);
      expect(entries.every((e) => e.user == 'postgres'), isTrue);
    });

    test('multi-alias with wildcards keeps only concrete ones', () {
      const input = '''
Host alpha *.wild beta
    HostName x
''';
      final entries = parseOpenSshConfig(input);
      expect(entries.map((e) => e.host), ['alpha', 'beta']);
    });

    test('keyword case is insensitive', () {
      const input = '''
HOST weird
    hostname WEIRD.example.com
    USER root
    port 22
    identityfile ~/.ssh/id_rsa
''';
      final entries = parseOpenSshConfig(input);
      expect(entries, hasLength(1));
      final e = entries.first;
      expect(e.hostName, 'WEIRD.example.com');
      expect(e.user, 'root');
      expect(e.port, 22);
      expect(e.identityFiles, ['~/.ssh/id_rsa']);
    });

    test('equals-sign syntax is supported', () {
      const input = '''
Host router
    HostName=192.168.1.1
    User = admin
    Port=22
''';
      final entries = parseOpenSshConfig(input);
      expect(entries.first.hostName, '192.168.1.1');
      expect(entries.first.user, 'admin');
      expect(entries.first.port, 22);
    });

    test('quoted values preserve spaces and strip quotes', () {
      const input = '''
Host q
    HostName "server with space.example.com"
    User "cool user"
''';
      final entries = parseOpenSshConfig(input);
      expect(entries.first.hostName, 'server with space.example.com');
      expect(entries.first.user, 'cool user');
    });

    test('multiple IdentityFile directives accumulate', () {
      const input = '''
Host multi
    IdentityFile ~/.ssh/key1
    IdentityFile ~/.ssh/key2
''';
      final entries = parseOpenSshConfig(input);
      expect(entries.first.identityFiles, ['~/.ssh/key1', '~/.ssh/key2']);
    });

    test('duplicate simple directives keep first (OpenSSH semantics)', () {
      const input = '''
Host dup
    User first
    User second
    Port 1
    Port 2
''';
      final entries = parseOpenSshConfig(input);
      expect(entries.first.user, 'first');
      expect(entries.first.port, 1);
    });

    test('invalid port is dropped (not crash)', () {
      const input = '''
Host bad
    Port not-a-number
''';
      final entries = parseOpenSshConfig(input);
      expect(entries.first.port, isNull);
    });

    test('global / Match scope directives are ignored', () {
      const input = '''
# Pre-host directives (global scope) — should not leak
User global-user
Port 9999

Host target
    HostName target.example.com
''';
      final entries = parseOpenSshConfig(input);
      expect(entries, hasLength(1));
      expect(entries.first.user, isNull);
      expect(entries.first.port, isNull);
    });

    test('CRLF and CR line endings are handled', () {
      const crlf = 'Host a\r\n    HostName a.example.com\r\n';
      const cr = 'Host b\r    HostName b.example.com\r';
      expect(parseOpenSshConfig(crlf).first.hostName, 'a.example.com');
      expect(parseOpenSshConfig(cr).first.hostName, 'b.example.com');
    });

    test('realistic multi-host config', () {
      const input = '''
Host github.com
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_ed25519

Host work-vpn
    HostName vpn.example.com
    User alice
    Port 2222
    IdentityFile ~/.ssh/work_rsa

Host *
    ServerAliveInterval 60
''';
      final entries = parseOpenSshConfig(input);
      expect(entries.map((e) => e.host), ['github.com', 'work-vpn']);
      expect(entries[0].identityFiles, ['~/.ssh/id_ed25519']);
      expect(entries[1].port, 2222);
    });

    test('effectiveHost falls back to alias when HostName missing', () {
      const input = '''
Host aliasonly
    User u
''';
      final entries = parseOpenSshConfig(input);
      expect(entries.first.hostName, isNull);
      expect(entries.first.effectiveHost, 'aliasonly');
    });

    group('wildcard defaults (Host * and pattern blocks)', () {
      test(
        'Host * applies User / Port defaults to concrete hosts that omit them',
        () {
          const input = '''
Host *
    User default-user
    Port 2200

Host prod
    HostName prod.example.com
''';
          final entries = parseOpenSshConfig(input);
          expect(entries.map((e) => e.host), ['prod']);
          expect(entries.first.user, 'default-user');
          expect(entries.first.port, 2200);
          expect(entries.first.hostName, 'prod.example.com');
        },
      );

      test(
        'first-match-wins: earlier block value takes precedence (OpenSSH semantics)',
        () {
          // Standard OpenSSH idiom: concrete hosts first, catch-all Host *
          // at the end. `prod`'s own User/Port come first → they win;
          // `Host *` only fills fields that weren't set yet.
          const input = '''
Host prod
    HostName prod.example.com
    User ops
    Port 22

Host *
    User default-user
    Port 2200
    IdentityFile ~/.ssh/id_default
''';
          final entries = parseOpenSshConfig(input);
          expect(entries.first.user, 'ops');
          expect(entries.first.port, 22);
          expect(entries.first.identityFiles, ['~/.ssh/id_default']);
        },
      );

      test('pattern blocks apply only to matching concrete hosts', () {
        const input = '''
Host *.internal
    User intern

Host db.internal
    HostName 10.0.0.5

Host public
    HostName public.example.com
''';
        final entries = parseOpenSshConfig(input);
        final db = entries.firstWhere((e) => e.host == 'db.internal');
        final pub = entries.firstWhere((e) => e.host == 'public');
        expect(db.user, 'intern', reason: 'db.internal matches *.internal');
        expect(pub.user, isNull, reason: 'public does not match *.internal');
      });

      test(
        'IdentityFile from wildcard cascades to concrete hosts (accumulates)',
        () {
          const input = '''
Host *
    IdentityFile ~/.ssh/id_fallback

Host work
    HostName work.example.com
    IdentityFile ~/.ssh/id_work
''';
          final entries = parseOpenSshConfig(input);
          expect(entries.first.identityFiles, [
            '~/.ssh/id_fallback',
            '~/.ssh/id_work',
          ]);
        },
      );

      test('negation pattern (!) blocks a block from applying', () {
        const input = '''
Host * !secure
    User generic

Host normal
    HostName n.example.com

Host secure
    HostName s.example.com
''';
        final entries = parseOpenSshConfig(input);
        final normal = entries.firstWhere((e) => e.host == 'normal');
        final secure = entries.firstWhere((e) => e.host == 'secure');
        expect(normal.user, 'generic');
        expect(
          secure.user,
          isNull,
          reason: '!secure negates the wildcard match for host "secure"',
        );
      });

      test('multi-pattern wildcard block matches via any positive pattern', () {
        const input = '''
Host git* *.ci
    User ci-bot

Host github.com
    HostName ssh.github.com

Host runner.ci
    HostName runner.ci.example
''';
        final entries = parseOpenSshConfig(input);
        for (final e in entries) {
          expect(e.user, 'ci-bot', reason: 'both hosts match one pattern');
        }
      });
    });

    group('PreferredAuthentications directive', () {
      test('maps publickey / password to AuthType list in order', () {
        const input = '''
Host keyfirst
    HostName k.example.com
    PreferredAuthentications publickey,password

Host pwfirst
    HostName p.example.com
    PreferredAuthentications password,publickey
''';
        final entries = parseOpenSshConfig(input);
        final keyFirst = entries.firstWhere((e) => e.host == 'keyfirst');
        final pwFirst = entries.firstWhere((e) => e.host == 'pwfirst');
        expect(keyFirst.preferredAuthTypes, [AuthType.key, AuthType.password]);
        expect(pwFirst.preferredAuthTypes, [AuthType.password, AuthType.key]);
      });

      test('unsupported methods are filtered out, not rejected', () {
        // gssapi-with-mic / hostbased are ignored — the remaining methods
        // keep their relative order so the importer still gets a usable
        // preference list.
        const input = '''
Host demo
    HostName d.example.com
    PreferredAuthentications gssapi-with-mic,hostbased,password
''';
        final e = parseOpenSshConfig(input).single;
        expect(e.preferredAuthTypes, [AuthType.password]);
      });

      test('all-unknown PreferredAuthentications degrades to null', () {
        const input = '''
Host demo
    HostName d.example.com
    PreferredAuthentications gssapi-with-mic,hostbased
''';
        final e = parseOpenSshConfig(input).single;
        expect(
          e.preferredAuthTypes,
          isNull,
          reason: 'null tells the importer to fall back to the default rule',
        );
      });

      test('keyboard-interactive folds into password without duplicating', () {
        const input = '''
Host demo
    HostName d.example.com
    PreferredAuthentications keyboard-interactive,password
''';
        final e = parseOpenSshConfig(input).single;
        expect(e.preferredAuthTypes, [AuthType.password]);
      });

      test('absence leaves preferredAuthTypes null', () {
        const input = '''
Host demo
    HostName d.example.com
    User admin
''';
        final e = parseOpenSshConfig(input).single;
        expect(e.preferredAuthTypes, isNull);
      });
    });

    group('Include directive', () {
      test('expands Include against the supplied reader', () {
        // Supplies a canned file for `extra.conf` via [includeReader] so the
        // test doesn't need to touch the real filesystem.
        const main = '''
Host local
    HostName local.example.com

Include extra.conf
''';
        const extra = '''
Host remote
    HostName remote.example.com
    User admin
''';
        final entries = parseOpenSshConfig(
          main,
          baseDir: '/cfg',
          includeReader: (path) {
            expect(path, '/cfg/extra.conf');
            return extra;
          },
        );
        expect(entries.map((e) => e.host), containsAll(['local', 'remote']));
        final remote = entries.firstWhere((e) => e.host == 'remote');
        expect(remote.user, 'admin');
      });

      test('handles nested includes up to the depth limit', () {
        final files = {
          '/cfg/a.conf': 'Host a\n    HostName a\nInclude b.conf\n',
          '/cfg/b.conf': 'Host b\n    HostName b\nInclude c.conf\n',
          '/cfg/c.conf': 'Host c\n    HostName c\n',
        };
        final entries = parseOpenSshConfig(
          'Include a.conf\n',
          baseDir: '/cfg',
          includeReader: (p) => files[p],
        );
        expect(entries.map((e) => e.host).toSet(), {'a', 'b', 'c'});
      });

      test('self-referencing include does not loop forever', () {
        // `loop.conf` includes itself; the visited-set in the expander
        // skips the second visit so parsing terminates with just the one
        // block that was inside the file.
        final files = {
          '/cfg/loop.conf': 'Host looped\n    HostName l\nInclude loop.conf\n',
        };
        final entries = parseOpenSshConfig(
          'Include loop.conf\n',
          baseDir: '/cfg',
          includeReader: (p) => files[p],
        );
        expect(entries.map((e) => e.host), ['looped']);
      });

      test('missing Include target is silently skipped', () {
        // An include that can't be read is a warning, not a hard error —
        // otherwise a deleted helper file would break the whole import.
        final entries = parseOpenSshConfig(
          'Host a\n    HostName a\nInclude missing.conf\n',
          baseDir: '/cfg',
          includeReader: (_) => null,
        );
        expect(entries.map((e) => e.host), ['a']);
      });
    });
  });
}
