/// Coverage for [parseLogEntries] — the pure parser the log viewer
/// reads `letsflutssh.log` through.
///
/// Lines are either:
///   * primary entries matching `HH:MM:SS X [Tag] msg` (X ∈ I/W/E),
///   * header / raw lines that do not match the regex (rendered dim),
///   * continuation lines starting with two spaces, which fold into
///     the previous entry so a multi-line error + stack-trace
///     renders under a single tinted row.
///
/// Tests assert each shape end-to-end and the awkward edge cases
/// (continuation as first line → no prior entry to attach to,
/// brackets inside the message preserved, unknown level chars
/// fall back to info via the switch default, empty lines dropped).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/features/settings/settings_logging_parser.dart';
import 'package:letsflutssh/utils/logger.dart';

void main() {
  group('parseLogEntries — empty + trivial', () {
    test('empty input yields no entries', () {
      expect(parseLogEntries(''), isEmpty);
    });

    test('blank lines are dropped', () {
      expect(parseLogEntries('\n\n\n'), isEmpty);
    });
  });

  group('parseLogEntries — primary entries', () {
    test('I-level line parses to LogLevel.info', () {
      final entries = parseLogEntries('12:34:56 I [Auth] login ok');
      expect(entries, hasLength(1));
      final e = entries.single;
      expect(e.level, LogLevel.info);
      expect(e.timestamp, '12:34:56');
      expect(e.tag, 'Auth');
      expect(e.message, 'login ok');
      expect(e.isHeader, isFalse);
      expect(e.continuations, isEmpty);
    });

    test('W-level line parses to LogLevel.warn', () {
      final entries = parseLogEntries('00:00:00 W [Net] retrying');
      expect(entries.single.level, LogLevel.warn);
    });

    test('E-level line parses to LogLevel.error', () {
      final entries = parseLogEntries('23:59:59 E [Boot] failed');
      expect(entries.single.level, LogLevel.error);
    });

    test(
      'message preserves brackets — tag stops at the first close-bracket',
      () {
        final entries = parseLogEntries(
          '12:00:00 I [SshKeys] loaded entry [primary] ok',
        );
        expect(entries.single.tag, 'SshKeys');
        expect(entries.single.message, 'loaded entry [primary] ok');
      },
    );
  });

  group('parseLogEntries — header / non-matching lines', () {
    test('non-matching line becomes a header entry', () {
      final entries = parseLogEntries('--- Log started 2026-05-06 ---');
      expect(entries.single.isHeader, isTrue);
      expect(entries.single.message, '--- Log started 2026-05-06 ---');
      expect(entries.single.level, isNull);
      expect(entries.single.tag, isNull);
    });

    test('Platform: / Dart: header lines stay as headers', () {
      final entries = parseLogEntries('Platform: linux\nDart: 3.5.0');
      expect(entries, hasLength(2));
      expect(entries.every((e) => e.isHeader), isTrue);
    });

    test(
      'unknown level char falls through to header (regex requires I/W/E)',
      () {
        final entries = parseLogEntries('12:00:00 D [Tag] debug message');
        expect(entries.single.isHeader, isTrue);
        expect(entries.single.message, '12:00:00 D [Tag] debug message');
      },
    );
  });

  group('parseLogEntries — continuation folding', () {
    test('continuation line attaches to the prior entry', () {
      final entries = parseLogEntries(
        '12:00:00 E [Boot] something broke\n'
        '  Error: bang',
      );
      expect(entries, hasLength(1));
      expect(entries.single.message, 'something broke');
      expect(entries.single.continuations, ['  Error: bang']);
      // Inherits level + tag from the prior entry.
      expect(entries.single.level, LogLevel.error);
      expect(entries.single.tag, 'Boot');
    });

    test('multiple continuations all attach in order', () {
      final entries = parseLogEntries(
        '12:00:00 E [Boot] crash\n'
        '  Error: bang\n'
        '  Stack trace:\n'
        '  #0 main',
      );
      expect(entries, hasLength(1));
      expect(entries.single.continuations, [
        '  Error: bang',
        '  Stack trace:',
        '  #0 main',
      ]);
    });

    test('continuation as the very first non-empty line becomes a header', () {
      // No prior entry → the parser treats it like any non-matching
      // standalone row.
      final entries = parseLogEntries('  orphaned continuation');
      expect(entries.single.isHeader, isTrue);
      expect(entries.single.message, '  orphaned continuation');
    });

    test('continuation does not attach across an intervening header', () {
      final entries = parseLogEntries(
        '12:00:00 I [A] first\n'
        '--- separator ---\n'
        '  this attaches to the header, not to entry A',
      );
      expect(entries, hasLength(2));
      expect(entries.first.continuations, isEmpty);
      expect(entries.last.isHeader, isTrue);
      expect(entries.last.continuations, [
        '  this attaches to the header, not to entry A',
      ]);
    });

    test('continuation inherits isHeader=true when prior is a header', () {
      final entries = parseLogEntries(
        '--- Log started ---\n'
        '  Platform: linux',
      );
      expect(entries, hasLength(1));
      expect(entries.single.isHeader, isTrue);
      expect(entries.single.continuations, ['  Platform: linux']);
    });
  });

  group('parseLogEntries — mixed real-world blob', () {
    test('header → entry → continuation → entry → entry sequence', () {
      final entries = parseLogEntries(
        [
          '--- Log started ---',
          '12:00:00 I [Boot] initialised',
          '12:00:01 E [Auth] login failed',
          '  Error: invalid credentials',
          '  Stack trace: ...',
          '12:00:02 W [Net] retrying',
        ].join('\n'),
      );

      expect(entries, hasLength(4));
      // Header
      expect(entries[0].isHeader, isTrue);
      // Boot info
      expect(entries[1].level, LogLevel.info);
      expect(entries[1].tag, 'Boot');
      // Auth error with two continuations
      expect(entries[2].level, LogLevel.error);
      expect(entries[2].continuations, hasLength(2));
      // Net warn — fresh entry, no continuations
      expect(entries[3].level, LogLevel.warn);
      expect(entries[3].continuations, isEmpty);
    });
  });

  group('logLinePattern — regex shape', () {
    test('matches a canonical line', () {
      expect(logLinePattern.hasMatch('00:00:00 I [Tag] msg'), isTrue);
    });

    test('rejects missing tag', () {
      expect(logLinePattern.hasMatch('00:00:00 I msg'), isFalse);
    });

    test('rejects malformed timestamp', () {
      expect(logLinePattern.hasMatch('0:0:0 I [Tag] msg'), isFalse);
    });
  });
}
