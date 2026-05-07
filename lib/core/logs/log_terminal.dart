import 'dart:async';

import 'package:xterm/xterm.dart';

import '../../features/settings/settings_logging_parser.dart';
import '../../utils/logger.dart';

/// App-level log viewer backed by an `xterm.dart` [Terminal]. Holds
/// every emitted [LogEntry] in `_allEntries` plus the rendered
/// representation in the Terminal's scrollback. The Settings → Logs
/// tab mounts a [TerminalView] against the same instance, so the
/// open is instant — there is no on-mount file read, no list
/// rebuild.
///
/// Lifecycle:
/// - First touch (typically from `_LetsFLUTsshAppState._bootstrap`
///   after FRB init) calls [ensureSeeded], which async-reads the
///   on-disk log file and feeds parsed entries into the Terminal.
/// - From then on every routine [AppLogger.log] / [AppLogger.logCritical]
///   call emits a [LogEntry] on `AppLogger.liveEntries`; the
///   subscription below appends to both `_allEntries` and the
///   Terminal (when the entry passes the active filter).
/// - [applyFilter] re-feeds the Terminal with the filtered subset
///   when the user toggles a level chip or types in the search box.
///   Selection is lost on filter change — expected when the
///   displayed corpus changes.
/// - [clearAll] wipes the in-memory list + the Terminal display.
///   The on-disk wipe lives one layer up (Settings clear-log
///   action) so this class stays uncoupled from file-system I/O.
class LogTerminal {
  LogTerminal._() {
    _entriesSub = AppLogger.instance.liveEntries.listen(_onEntry);
  }

  static LogTerminal? _instance;

  /// Process-singleton handle. The first call constructs it +
  /// subscribes to the AppLogger live stream; subsequent calls
  /// return the same instance so the Settings tab and the boot
  /// primer share the same Terminal buffer.
  static LogTerminal get instance => _instance ??= LogTerminal._();

  /// Reset the singleton — for tests that drive a fresh logger
  /// + terminal pair without process restart. Cancels the
  /// subscription so the test instance does not leak into the
  /// next test.
  @Deprecated('Test-only; production code never resets the singleton.')
  static Future<void> resetForTesting() async {
    final old = _instance;
    _instance = null;
    await old?.dispose();
  }

  /// Scrollback cap. Five times the log-file rotation cap (5 MB ≈
  /// 50 k lines) so a fresh boot can show a couple of rotations'
  /// worth of history without the Terminal evicting older lines
  /// the user might still want to scroll up to.
  static const int _maxLines = 50000;

  final Terminal _terminal = Terminal(maxLines: _maxLines);
  final List<LogEntry> _allEntries = <LogEntry>[];

  StreamSubscription<LogEntry>? _entriesSub;
  bool _seedDone = false;

  // Filter state — mutated by `applyFilter`; the live `_onEntry`
  // path consults these when deciding whether to write a fresh
  // entry to the Terminal.
  Set<LogLevel> _visibleLevels = const {
    LogLevel.info,
    LogLevel.warn,
    LogLevel.error,
  };
  String _query = '';

  /// The xterm Terminal the Settings viewer mounts a `TerminalView`
  /// against. Stable for the process lifetime.
  Terminal get terminal => _terminal;

  /// Read-only snapshot of every emitted entry — used by the
  /// "copy all" toolbar fallback when no Terminal selection is
  /// active.
  List<LogEntry> get allEntries => List.unmodifiable(_allEntries);

  /// Current substring filter applied to messages + tags.
  String get query => _query;

  /// Currently-visible severity levels.
  Set<LogLevel> get visibleLevels => Set.unmodifiable(_visibleLevels);

  /// Idempotent. Loads the existing log file via [AppLogger.readLog],
  /// parses it into [LogEntry]s and feeds them through the active
  /// filter into the Terminal. Subsequent calls are no-ops — the
  /// live subscription handles new entries.
  Future<void> ensureSeeded() async {
    if (_seedDone) return;
    _seedDone = true;
    try {
      final content = await AppLogger.instance.readLog();
      if (content.isEmpty) return;
      final entries = parseLogEntries(content);
      _allEntries.addAll(entries);
      for (final e in entries) {
        if (_passesFilter(e)) _writeToTerminal(e);
      }
    } catch (_) {
      // Best-effort — an empty seed is OK; live appends will still
      // populate the terminal as new entries arrive.
    }
  }

  void _onEntry(LogEntry e) {
    _allEntries.add(e);
    if (_passesFilter(e)) _writeToTerminal(e);
  }

  bool _passesFilter(LogEntry e) {
    if (e.isHeader) {
      // Headers (`--- Log started`, `Platform:`) ride along with
      // the unfiltered view; the moment a query or level filter
      // narrows the corpus the headers drop too — the viewer is
      // showing "matching lines", not session boundaries.
      return _query.isEmpty && _visibleLevels.length == LogLevel.values.length;
    }
    final level = e.level;
    if (level != null && !_visibleLevels.contains(level)) return false;
    if (_query.isEmpty) return true;
    final q = _query.toLowerCase();
    if (e.message.toLowerCase().contains(q)) return true;
    if (e.tag != null && e.tag!.toLowerCase().contains(q)) return true;
    for (final c in e.continuations) {
      if (c.toLowerCase().contains(q)) return true;
    }
    return false;
  }

  void _writeToTerminal(LogEntry e) {
    final buf = StringBuffer();
    if (e.isHeader) {
      // Dim italic-ish banner. Headers carry a leading session
      // marker (`--- Log started ...`) so a triple-newline-and-bold
      // makes the boundary unambiguous to skim.
      if (e.message.startsWith('--- Log started')) {
        buf.write('\r\n');
      }
      buf.write('\x1B[2;1m');
      buf.write(e.message);
      buf.write('\x1B[0m\r\n');
      _terminal.write(buf.toString());
      return;
    }
    // Timestamp — dim grey so the eye anchors on the [TAG] / message.
    buf.write('\x1B[2m');
    buf.write(e.timestamp ?? '');
    buf.write('\x1B[0m ');
    // [TAG] in the level's accent colour, bold so it pops at the
    // start of the row even when scrollback is dense.
    final tagColor = switch (e.level) {
      LogLevel.error => '31', // red
      LogLevel.warn => '33', // yellow
      LogLevel.info => '36', // cyan
      null => '36',
    };
    buf.write('\x1B[1;${tagColor}m[');
    buf.write(e.tag ?? 'App');
    buf.write(']\x1B[0m ');
    // Message in default fg.
    buf.write(e.message);
    buf.write('\r\n');
    // Continuations (Error, Stack trace, indented frames) — dim
    // so the primary message stays visually dominant. The lines
    // already start with two spaces from the parser, preserving
    // the on-disk indentation contract.
    for (final c in e.continuations) {
      buf.write('\x1B[2m');
      buf.write(c);
      buf.write('\x1B[0m\r\n');
    }
    _terminal.write(buf.toString());
  }

  /// Update the filter and re-feed the Terminal with the filtered
  /// subset of `_allEntries`. Selection is lost on this call —
  /// the displayed corpus changes, so any prior selection
  /// boundary becomes meaningless.
  void applyFilter({
    required Set<LogLevel> visibleLevels,
    required String query,
  }) {
    _visibleLevels = Set.of(visibleLevels);
    _query = query;
    // `ESC[2J` erases the display, `ESC[H` parks the cursor at
    // the top — the standard "clear screen" sequence terminals
    // already handle natively.
    _terminal.write('\x1B[2J\x1B[H');
    for (final e in _allEntries) {
      if (_passesFilter(e)) _writeToTerminal(e);
    }
  }

  /// Wipe the in-memory entry list and the Terminal display.
  /// File-side wipe (deleting `letsflutssh.log`) lives one layer up
  /// in the Settings clear-log action so this class stays
  /// uncoupled from disk I/O.
  void clearAll() {
    _allEntries.clear();
    _terminal.write('\x1B[2J\x1B[H');
  }

  /// Cancel the live subscription. Intended for tests + a future
  /// app-shutdown path; production never disposes the singleton.
  Future<void> dispose() async {
    await _entriesSub?.cancel();
    _entriesSub = null;
  }
}
