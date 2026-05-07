import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../features/settings/settings_logging_parser.dart';
import '../../utils/logger.dart';

/// App-level log buffer. Holds every emitted [LogEntry] in memory and
/// publishes the filtered subset that the Settings → Logs viewer
/// renders. Backed by a plain [ChangeNotifier] so a `ListenableBuilder`
/// inside the viewer rebuilds the `ListView.builder` when new entries
/// arrive or the filter changes.
///
/// Lifecycle:
/// - First touch (typically from `_LetsFLUTsshAppState._bootstrap`
///   after FRB init) calls [ensureSeeded], which async-reads the
///   on-disk log file and folds parsed entries into the buffer.
/// - From then on every routine [AppLogger.log] / [AppLogger.logCritical]
///   call emits a [LogEntry] on `AppLogger.liveEntries`; the
///   subscription below appends to `_allEntries` (and to
///   `_filteredEntries` if it passes the active filter), then fires
///   [notifyListeners] so the viewer scrolls in the new row.
/// - [applyFilter] recomputes `_filteredEntries` against the full
///   buffer on level-chip / search changes.
/// - [clearAll] wipes the in-memory buffer; the on-disk wipe lives
///   one layer up in the Settings clear-log action so this class
///   stays uncoupled from file-system I/O.
class LogStore extends ChangeNotifier {
  LogStore._() {
    _entriesSub = AppLogger.instance.liveEntries.listen(_onEntry);
  }

  static LogStore? _instance;

  /// Process-singleton handle. The Settings tab and the boot primer
  /// share the same buffer.
  static LogStore get instance => _instance ??= LogStore._();

  /// Reset the singleton — for tests that drive a fresh logger +
  /// store pair without process restart.
  @visibleForTesting
  static Future<void> resetForTesting() async {
    final old = _instance;
    _instance = null;
    await old?.dispose();
  }

  /// Soft cap on retained entries. Five times the log-file rotation
  /// cap (5 MB ≈ 50 k lines) so a fresh boot can show a couple of
  /// rotations' worth of history before the oldest entries fall out
  /// of the buffer.
  static const int _maxEntries = 50000;

  final List<LogEntry> _allEntries = <LogEntry>[];
  List<LogEntry> _filteredEntries = const [];

  StreamSubscription<LogEntry>? _entriesSub;
  bool _seedDone = false;

  Set<LogLevel> _visibleLevels = const {
    LogLevel.info,
    LogLevel.warn,
    LogLevel.error,
  };
  String _query = '';

  /// Read-only snapshot of every retained entry — used by the
  /// "copy log" toolbar fallback when no selection is active.
  List<LogEntry> get allEntries => List.unmodifiable(_allEntries);

  /// Filtered view the [ListView.builder] iterates over.
  List<LogEntry> get filteredEntries => _filteredEntries;

  /// Current substring filter applied to messages + tags.
  String get query => _query;

  /// Currently-visible severity levels.
  Set<LogLevel> get visibleLevels => Set.unmodifiable(_visibleLevels);

  /// Idempotent. Loads the existing log file via [AppLogger.readLog],
  /// parses it into [LogEntry]s and folds them into the buffer.
  /// Subsequent calls are no-ops — the live subscription handles new
  /// entries.
  ///
  /// Order + dedup: live entries that arrived BEFORE the disk read
  /// completed live in `_allEntries` already (the constructor
  /// subscribes to `liveEntries` immediately). The seed read picks up
  /// the same entries off disk because `AppLogger.log` writes to disk
  /// + emits on the stream in lock-step. To avoid duplicates AND
  /// preserve chronological order:
  ///   * Build a signature set from the seed entries.
  ///   * Drop pre-seed live entries that match a seed signature.
  ///   * Replace the buffer with `seedEntries + leftover live entries`
  ///     so the on-disk history sits at the top in order, then any
  ///     truly-post-seed live entries follow. Without this, a fresh
  ///     boot showed all post-construction live entries above the
  ///     seed dump (which started with a `--- Log started ---` banner)
  ///     — chronologically nonsensical.
  Future<void> ensureSeeded() async {
    if (_seedDone) return;
    _seedDone = true;
    try {
      final content = await AppLogger.instance.readLog();
      _applySeed(content);
    } catch (_) {
      // Best-effort — an empty seed is OK; live appends will still
      // populate the buffer as new entries arrive.
    }
  }

  /// Dedup + merge core extracted so unit tests can exercise the
  /// "live entries arrived before seed completed" race without going
  /// through `AppLogger.readLog` (which needs a flutter-binding-backed
  /// path_provider mock).
  ///
  /// Adjacent banners are collapsed: when two `--- Log started ---`
  /// rows sit next to each other with no content between them (two
  /// processes booted in quick succession, neither logged anything
  /// before the next one wrote its own banner), only the LATER banner
  /// is kept. The earlier one is dropped — its session produced no
  /// content, so its boundary marker is noise.
  void _applySeed(String content) {
    if (content.isEmpty) {
      _recomputeFiltered();
      notifyListeners();
      return;
    }
    final seedEntries = parseLogEntries(content);
    final seedSigs = <String>{for (final e in seedEntries) _signatureOf(e)};
    final leftoverLive = <LogEntry>[
      for (final e in _allEntries)
        if (!seedSigs.contains(_signatureOf(e))) e,
    ];
    final merged = <LogEntry>[...seedEntries, ...leftoverLive];
    _allEntries
      ..clear()
      ..addAll(_collapseAdjacentBanners(merged));
    _trimIfNeeded();
    _recomputeFiltered();
    notifyListeners();
  }

  /// Walk a list and drop any banner that is immediately followed by
  /// another banner — the trailing banner wins (more recent session).
  /// Single forward pass, O(N).
  List<LogEntry> _collapseAdjacentBanners(List<LogEntry> input) {
    final out = <LogEntry>[];
    for (final e in input) {
      if (_isBannerHeader(e) && out.isNotEmpty && _isBannerHeader(out.last)) {
        out[out.length - 1] = e;
      } else {
        out.add(e);
      }
    }
    return out;
  }

  /// True for the `--- Log started ... ---` session-boundary line.
  /// Other header rows (`Platform: ...`, `Dart: ...` from rotated
  /// legacy files) do not coalesce — they carry distinct content.
  bool _isBannerHeader(LogEntry e) =>
      e.isHeader && e.message.startsWith('--- ');

  /// Test seam — drive the seed merge against arbitrary text without
  /// needing a real on-disk file. Marks the seed as done so a later
  /// production call short-circuits.
  @visibleForTesting
  void debugApplySeed(String content) {
    _seedDone = true;
    _applySeed(content);
  }

  /// Stable identity tuple for dedup between seed entries and live
  /// entries. Headers carry `null` timestamp/tag — collapse them
  /// onto the message field which already encodes the boundary line
  /// uniquely.
  String _signatureOf(LogEntry e) {
    if (e.isHeader) return 'H|${e.message}';
    return '${e.timestamp ?? ""}|${e.tag ?? ""}|${e.message}';
  }

  void _onEntry(LogEntry e) {
    // Adjacent-banner collapse: if the live stream emits a banner
    // back-to-back with the last entry already buffered, replace the
    // older banner instead of appending. Otherwise append normally.
    if (_isBannerHeader(e) &&
        _allEntries.isNotEmpty &&
        _isBannerHeader(_allEntries.last)) {
      _allEntries[_allEntries.length - 1] = e;
      _recomputeFiltered();
      notifyListeners();
      return;
    }
    _allEntries.add(e);
    _trimIfNeeded();
    if (_passesFilter(e)) {
      _filteredEntries = [..._filteredEntries, e];
    }
    notifyListeners();
  }

  /// Test seam — feed an entry through the same path the live
  /// AppLogger subscription uses, without requiring a flutter-binding-
  /// backed AppLogger sink. Production code reaches `_onEntry` only
  /// via the `liveEntries` subscription set up in the constructor.
  @visibleForTesting
  void debugInject(LogEntry e) => _onEntry(e);

  void _trimIfNeeded() {
    if (_allEntries.length <= _maxEntries) return;
    final excess = _allEntries.length - _maxEntries;
    _allEntries.removeRange(0, excess);
  }

  bool _passesFilter(LogEntry e) {
    if (e.isHeader) {
      // Headers (`--- Log started`, `Platform:`) ride along only with
      // the unfiltered view. The moment a query or level filter
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

  void _recomputeFiltered() {
    _filteredEntries = [
      for (final e in _allEntries)
        if (_passesFilter(e)) e,
    ];
  }

  /// Update the filter and recompute the rendered subset. Called on
  /// every level-chip toggle and search-query keystroke.
  void applyFilter({
    required Set<LogLevel> visibleLevels,
    required String query,
  }) {
    _visibleLevels = Set.of(visibleLevels);
    _query = query;
    _recomputeFiltered();
    notifyListeners();
  }

  /// Wipe the in-memory buffer. File-side wipe (deleting
  /// `letsflutssh.log`) lives one layer up in the Settings clear-log
  /// action so this class stays uncoupled from disk I/O.
  void clearAll() {
    _allEntries.clear();
    _filteredEntries = const [];
    notifyListeners();
  }

  /// Cancel the live subscription. Intended for tests + a future
  /// app-shutdown path; production never disposes the singleton.
  @override
  Future<void> dispose() async {
    await _entriesSub?.cancel();
    _entriesSub = null;
    super.dispose();
  }
}
