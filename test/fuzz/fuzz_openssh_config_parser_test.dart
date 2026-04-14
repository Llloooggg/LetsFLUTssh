import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/ssh/openssh_config_parser.dart';

/// Fuzz tests for the OpenSSH config parser.
///
/// The parser reads `~/.ssh/config` — user-owned but effectively untrusted
/// from the app's perspective (can be hand-edited, truncated, corrupted).
/// Must never throw unhandled exceptions.
void main() {
  group('parseOpenSshConfig fuzz', () {
    test('empty / whitespace / single chars do not crash', () {
      for (final input in ['', ' ', '\n', '\r\n', '\t', '#', '=', '"']) {
        expect(() => parseOpenSshConfig(input), returnsNormally);
      }
    });

    test('known directives with garbage values do not crash', () {
      final inputs = [
        'Host\n',
        'Host \n',
        'Host =\n',
        'Host  =  \n',
        'HostName\n',
        'Port abc\n',
        'Port -1\n',
        'Port 999999999999999999999999999\n',
        'Port \n',
        'User\n',
        'IdentityFile\n',
        'IdentityFile ""\n',
        'Host "\n',
        'Host "unclosed\n',
        '= value only\n',
        '    \n',
        '#####\n',
        'Host a\n    Port\n    User\n',
      ];
      for (final input in inputs) {
        expect(() => parseOpenSshConfig(input), returnsNormally, reason: input);
      }
    });

    test('random bytes (ASCII) do not crash', () {
      final rng = Random(42);
      for (var i = 0; i < 500; i++) {
        final len = rng.nextInt(400);
        final buf = StringBuffer();
        for (var j = 0; j < len; j++) {
          // printable ASCII + whitespace + edge chars
          buf.writeCharCode(rng.nextInt(95) + 32);
          if (rng.nextInt(15) == 0) buf.write('\n');
          if (rng.nextInt(25) == 0) buf.write('"');
        }
        expect(() => parseOpenSshConfig(buf.toString()), returnsNormally);
      }
    });

    test('random lines mixing known keywords and garbage do not crash', () {
      final rng = Random(7);
      const keywords = [
        'Host',
        'HostName',
        'User',
        'Port',
        'IdentityFile',
        'Match',
        'Include',
        'ServerAliveInterval',
        'ProxyCommand',
        'GARBAGE',
      ];
      for (var i = 0; i < 200; i++) {
        final buf = StringBuffer();
        final lineCount = rng.nextInt(30);
        for (var j = 0; j < lineCount; j++) {
          final kw = keywords[rng.nextInt(keywords.length)];
          final sep = rng.nextBool() ? ' ' : '=';
          final valLen = rng.nextInt(20);
          final value = StringBuffer();
          for (var k = 0; k < valLen; k++) {
            value.writeCharCode(rng.nextInt(95) + 32);
          }
          buf
            ..write(kw)
            ..write(sep)
            ..write(value)
            ..write('\n');
        }
        expect(() => parseOpenSshConfig(buf.toString()), returnsNormally);
      }
    });

    test('unicode and non-ASCII do not crash', () {
      const inputs = [
        'Host тест\n    HostName тест.рф\n    User админ\n',
        'Host 😀\n    HostName 🚀.example\n',
        'Host a\n    HostName \u0000null\n',
      ];
      for (final input in inputs) {
        expect(() => parseOpenSshConfig(input), returnsNormally);
      }
    });

    test('large input does not crash (stress)', () {
      final buf = StringBuffer();
      for (var i = 0; i < 2000; i++) {
        buf
          ..writeln('Host host$i')
          ..writeln('    HostName $i.example.com')
          ..writeln('    User u$i')
          ..writeln('    Port ${i % 65535}');
      }
      final entries = parseOpenSshConfig(buf.toString());
      expect(entries, hasLength(2000));
    });

    test('truncated input (prefix of valid config) does not crash', () {
      const full = '''
Host example
    HostName example.com
    User alice
    Port 2222
    IdentityFile ~/.ssh/id_rsa
''';
      for (var i = 0; i < full.length; i++) {
        expect(() => parseOpenSshConfig(full.substring(0, i)), returnsNormally);
      }
    });
  });
}
