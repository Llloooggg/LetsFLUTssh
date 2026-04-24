import '../../utils/logger.dart';

/// One rendered row in the log viewer — either a parsed
/// `HH:MM:SS X [Tag] message` line with its continuation lines
/// (error / stack trace body), or a header / raw line that did not
/// match the format.
///
/// Continuations are folded into the parent entry so a multi-line
/// error + stack trace renders under a single tinted row instead of
/// each indented line fighting for its own left-border.
class LogEntry {
  final LogLevel? level;
  final String? timestamp;
  final String? tag;
  final String message;
  final List<String> continuations;
  final bool isHeader;

  const LogEntry({
    this.level,
    this.timestamp,
    this.tag,
    required this.message,
    this.continuations = const [],
    this.isHeader = false,
  });
}

/// Regex for primary log lines. Captures (1) timestamp, (2) level
/// char, (3) tag, (4) message. Tag uses `[^\]]+` so nested brackets
/// elsewhere in the message are preserved verbatim.
final RegExp logLinePattern = RegExp(
  r'^(\d{2}:\d{2}:\d{2}) ([DIWE]) \[([^\]]+)\] (.*)$',
);

/// Parse a raw log blob into a list of [LogEntry].
///
/// Header lines (`--- Log started ...`, `Platform:`, `Dart:`) and any
/// line that does not match [logLinePattern] become standalone header
/// entries so the viewer can dim them. Indented continuation lines
/// (`  Error: ...`, `  Stack trace:`, raw stack frames) attach to the
/// previous entry so they inherit the level tint.
///
/// Exposed for tests and the viewer widget; pure over its input, no
/// I/O, no theme or Flutter dependency.
List<LogEntry> parseLogEntries(String content) {
  final entries = <LogEntry>[];
  final lines = content.split('\n');
  for (final raw in lines) {
    if (raw.isEmpty) continue;
    if (raw.startsWith('  ') && entries.isNotEmpty) {
      final prev = entries.removeLast();
      entries.add(
        LogEntry(
          level: prev.level,
          timestamp: prev.timestamp,
          tag: prev.tag,
          message: prev.message,
          continuations: [...prev.continuations, raw],
          isHeader: prev.isHeader,
        ),
      );
      continue;
    }
    final m = logLinePattern.firstMatch(raw);
    if (m == null) {
      entries.add(LogEntry(message: raw, isHeader: true));
      continue;
    }
    entries.add(
      LogEntry(
        level: switch (m.group(2)) {
          'D' => LogLevel.debug,
          'W' => LogLevel.warn,
          'E' => LogLevel.error,
          _ => LogLevel.info,
        },
        timestamp: m.group(1),
        tag: m.group(3),
        message: m.group(4) ?? '',
      ),
    );
  }
  return entries;
}
