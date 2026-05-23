import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../src/rust/api/bus.dart' as rust_bus;
import '../src/rust/api/logger.dart' as rust_logger;
import 'sanitize.dart';

/// Severity marker for a log line. Written as a single char after the
/// timestamp so the live viewer can tint each row without reparsing the
/// message text. Matches the Logcat / journald convention.
///
/// Three levels only — [info], [warn], [error]. No "verbose" / "debug"
/// rung: every call site that wants a trace writes `info`, degraded
/// paths use `warn`, failures use `error`. Adding a fourth level is
/// easy when a real need appears; keeping the taxonomy compact stops
/// dropdown bloat and "what counts as debug?" call-site bikeshedding.
///
/// * [info] — routine operational state transition. "Session loaded",
///   "tier switched to T1+pw", "DB open". The default level for every
///   `log(...)` call that does not pass `error:` or an explicit
///   `level:`.
/// * [warn] — degraded but recoverable. Fallback paths ("fell back to
///   plaintext", "probe failed, using default"), missing optional
///   state, rate-limit kick-ins, skipped duplicates. The operation
///   *continued*; the user keeps a working app with a slightly weaker
///   guarantee. Amber tint + left border in the viewer.
/// * [error] — failure the user likely cares about. Migration fatal,
///   DB corruption, crash-handler breadcrumb, lost credentials,
///   unrecoverable connection drop. `logCritical` forces this level
///   and bypasses the threshold so crash forensics are always on
///   disk. Red tint + left border.
enum LogLevel { info, warn, error }

/// One rendered row in the log viewer — either a parsed
/// `HH:MM:SS X [Tag] message` line with its continuation lines
/// (error / stack trace body), or a header / raw line that did
/// not match the format.
///
/// Continuations are folded into the parent entry so a multi-line
/// error + stack trace renders under a single tinted row instead
/// of each indented line fighting for its own left-border.
///
/// Defined here (not in `lib/core/logs/settings_logging_parser.dart`)
/// because [AppLogger] eagerly constructs a
/// `StreamController<LogEntry>` field initializer; routing the
/// type definition through a sibling that imports `logger.dart`
/// back creates a circular import whose runtime initialisation
/// order silently aborts boot before the zone error handler is
/// installed.
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

/// Format the log timestamp prefix as `HH:MM:SS`.
///
/// Pure Dart on purpose — `logCritical` is the crash-path logger
/// the zone error handler in `main.dart` calls. The handler can
/// fire while `RustLib.init()` is still pending or already
/// failing; routing the timestamp through FRB would crash the
/// crash handler with `flutter_rust_bridge has not been
/// initialized` and swallow the original error, which is the
/// exact failure mode the project's cold-start ordering rule
/// exists to prevent.
String _formatHmsForLog(DateTime now) =>
    '${now.hour.toString().padLeft(2, '0')}:'
    '${now.minute.toString().padLeft(2, '0')}:'
    '${now.second.toString().padLeft(2, '0')}';

String _levelChar(LogLevel l) => switch (l) {
  LogLevel.info => 'I',
  LogLevel.warn => 'W',
  LogLevel.error => 'E',
};

/// Serialised form of [LogLevel] used in `config.json` so the JSON
/// stays stable if the enum order ever changes. `null` = logging off.
String? logLevelToJson(LogLevel? level) => switch (level) {
  null => null,
  LogLevel.info => 'info',
  LogLevel.warn => 'warn',
  LogLevel.error => 'error',
};

LogLevel? logLevelFromJson(String? raw) => switch (raw) {
  'info' => LogLevel.info,
  'warn' => LogLevel.warn,
  'error' => LogLevel.error,
  _ => null,
};

/// Compile-time override for the logging threshold, set via
/// `--dart-define=LETSFLUTSSH_LOG_LEVEL=<level>` at build time.
///
/// When non-empty + a recognised level (`info`/`warn`/`error`),
/// `main.dart` applies it right after `AppLogger.init()` — before
/// `ConfigProvider.load` gets a chance to read `config.json`. This
/// lets `make run` (debug build) ship with logging already on without
/// each developer / beta-tester having to toggle the Settings
/// dropdown on every fresh install.
///
/// Production builds leave the flag empty → the getter returns null
/// → the configProvider load path runs unchanged, so release users
/// still start with logging off unless they explicitly opt in.
LogLevel? get buildTimeLogLevelOverride {
  const raw = String.fromEnvironment('LETSFLUTSSH_LOG_LEVEL');
  if (raw.isEmpty) return null;
  return logLevelFromJson(raw);
}

/// One pre-FRB `logCritical` entry held in the in-memory ring
/// buffer. Both fields are already sanitised by the time they
/// land here — the buffer carries the exact bytes that will be
/// passed to `logger_append_critical` on drain.
class _PendingCritical {
  final String line;
  final List<String> continuations;
  const _PendingCritical(this.line, this.continuations);
}

/// Thin wrapper over the FRB-generated `logger_*` entry points
/// in `lib/src/rust/api/logger.dart`. Exists as a DI seam so unit
/// tests can swap the backing implementation without bootstrapping
/// the FRB native library on every case. Production code keeps the
/// single static [AppLogger.instance] singleton; tests inject a
/// fake by calling [AppLogger.debugSetBackend].
abstract class LoggerBackend {
  Future<String> openSink(String appSupportDir);
  void appendLine(String line);
  void appendCritical(String line, List<String> continuations);
  void flushSink();
  Future<String> readAll();
  Future<void> rotateIfNeeded(int maxBytes, int maxRotated);
  Future<void> clearAll(int maxRotated);
  void closeSink();
}

/// Real backend that routes straight to Rust through FRB.
class _RustLoggerBackend implements LoggerBackend {
  const _RustLoggerBackend();

  @override
  Future<String> openSink(String appSupportDir) =>
      rust_logger.loggerOpenSink(appSupportDir: appSupportDir);

  @override
  void appendLine(String line) => rust_logger.loggerAppendLine(line: line);

  @override
  void appendCritical(String line, List<String> continuations) => rust_logger
      .loggerAppendCritical(line: line, continuations: continuations);

  @override
  void flushSink() => rust_logger.loggerFlush();

  @override
  Future<String> readAll() => rust_logger.loggerReadAll();

  @override
  Future<void> rotateIfNeeded(int maxBytes, int maxRotated) =>
      rust_logger.loggerRotateIfNeeded(
        maxBytes: BigInt.from(maxBytes),
        maxRotated: maxRotated,
      );

  @override
  Future<void> clearAll(int maxRotated) =>
      rust_logger.loggerClearAll(maxRotated: maxRotated);

  @override
  void closeSink() => rust_logger.loggerCloseSink();
}

/// File-based logger.
///
/// Writes logs to `<appSupportDir>/logs/letsflutssh.log` alongside the
/// app data. Automatically rotates when the log file exceeds
/// [maxLogSizeBytes].
///
/// **Threshold-based opt-in.** The user picks a minimum severity in
/// Settings → Logging. `null` = off (default); any `LogLevel` value
/// opens the file sink and admits lines at or above that level. So
/// picking `warn` writes W + E, picking `info` writes everything.
/// Privacy-first: no routine logs leave the user's device until they
/// explicitly opt in, and they choose how verbose.
///
/// **Critical paths bypass the threshold.** [logCritical] writes
/// straight to disk regardless of current threshold so crash
/// boundaries, migration fatals and DB-integrity-probe failures
/// always leave a forensic breadcrumb — the window where a trace
/// matters most is exactly the one where the user has not yet flipped
/// the toggle. The write goes through `logger_append_critical` which
/// opens a fresh append handle Rust-side, so it works even when the
/// routine sink is closed.
///
/// **No OS logging mirror for routine entries.** Routine [log] calls
/// do NOT forward to `dart:developer` — Android Logcat / macOS
/// Console.app / desktop stderr never see our lines. The only logging
/// surface the user (or anyone with `adb logcat` / Console access)
/// sees is the opt-in file under app-support. **Don't add a stderr /
/// OS-log mirror "for development convenience"** — it leaks every
/// line a user with logging enabled produces into a system surface
/// the app cannot retract. Critical-path stderr mirror (desktop only)
/// stays — it is the only forensic surface during the pre-FRB window.
///
/// **File ownership lives Rust-side.** Every `dart:io File` /
/// `Directory` operation against the log path moved to
/// `lfs_core::logger::file_sink`; this class only formats +
/// sanitises lines, holds the in-memory pre-FRB critical-write ring
/// buffer, and broadcasts entries to the live viewer.
///
/// All messages pass through [sanitize] (PEM blobs, IPv4 / user@host,
/// home-directory paths are redacted) and the file is chmod-0600 on
/// POSIX — same hardening as `credentials.*` and `config.json`. The
/// chmod runs inside `logger_open_sink` Rust-side; no Dart code
/// touches permissions on the log path.
class AppLogger {
  static AppLogger? _instance;
  static const maxLogSizeBytes = 5 * 1024 * 1024; // 5 MB
  static const _maxRotatedFiles = 3;

  /// Cap on pre-FRB critical entries held in [_preFrbCriticalBuffer].
  /// A crash storm before `_initRustCoreOrFatal` returns is bounded;
  /// past the cap the oldest entries drop (FIFO) so the buffer never
  /// grows without limit. 64 covers every realistic pre-FRB burst —
  /// the cold-start window is sub-second on every desktop tier.
  static const _preFrbCriticalCap = 64;

  LoggerBackend _backend = const _RustLoggerBackend();
  bool _sinkOpen = false;
  String? _logPath;
  // App version stamped into the session-start banner the sink writes
  // on first open. `_mainBody` resolves this from `PackageInfo.fromPlatform`
  // before [setThreshold] flips logging on, so the banner already
  // carries the right version without touching the file twice. Stays
  // null in flutter_test contexts — the banner falls through to the
  // platform string only.
  String? _appVersion;
  // Set on the first `_openSink` call; suppresses duplicate banners
  // on subsequent reopens within the same process (Settings toggling
  // Off → On, [_rotateIfNeeded] cycling the file). [clearLogs] resets
  // it to false because a clear is a deliberate "new session"
  // boundary — the next reopen lands a fresh banner above the new
  // entries instead of leaving a banner-less file. [dispose] also
  // resets so test setUp gets a clean slate. Cross-process duplicate
  // banners (process A wrote a banner, exited; process B writes
  // another) are NOT deduplicated here — `LogStore._appendEntry`
  // collapses adjacent banners on the viewer side instead.
  bool _bannerWritten = false;
  // Current minimum severity that hits the sink. `null` = logging
  // off; any LogLevel admits lines at or above that level. Critical
  // paths ([logCritical]) bypass this gate so crash breadcrumbs
  // survive even when routine logging is disabled.
  LogLevel? _threshold;

  // Subscription that forwards Rust-core log lines into this same
  // sink. Without it, internal Rust failures (panics caught by
  // FRB, errors swallowed in match arms, connect-driver traces)
  // never reach `letsflutssh.log`. Held for the lifetime of the
  // logger; `dispose()` cancels it.
  StreamSubscription<rust_bus.BusEvent>? _coreLogSub;

  // Live broadcast of every LogEntry that survives the threshold
  // gate inside [log] / [logCritical]. The Settings → Logs viewer
  // (xterm-backed) listens here and appends to a persistent
  // Terminal buffer, so opening the tab is instant — the whole
  // log surface lives in memory, no on-tab-mount file read. Cap
  // is conceptual only (StreamController doesn't buffer) — the
  // Terminal viewer's own scrollback bounds the long-term retain.
  final StreamController<LogEntry> _entriesController =
      StreamController<LogEntry>.broadcast();

  /// Live broadcast of every routine + critical log entry, after
  /// threshold + sanitisation. Subscribers see the same shape the
  /// on-disk log file holds (sanitized message, optional error +
  /// stack-trace continuations). Survives the lifetime of the
  /// singleton; subscribers should `cancel()` on dispose.
  Stream<LogEntry> get liveEntries => _entriesController.stream;

  /// Tracks whether [onFrbReady] has flipped the
  /// FRB-ready gate. Pre-init `logCritical` calls land in
  /// [_preFrbCriticalBuffer] until this flips; the post-init drain
  /// flushes the buffer and starts forwarding new critical writes
  /// straight to Rust.
  bool _frbReady = false;

  /// In-memory ring buffer for `logCritical` calls that fire
  /// before `_initRustCoreOrFatal` returns. Drained from
  /// [onFrbReady]. Bounded at [_preFrbCriticalCap]
  /// with FIFO eviction; the cold-start window is sub-second so
  /// the bound is far above any realistic crash burst.
  final List<_PendingCritical> _preFrbCriticalBuffer = <_PendingCritical>[];

  AppLogger._();

  /// Get the singleton instance.
  static AppLogger get instance => _instance ??= AppLogger._();

  /// Swap the [LoggerBackend] for tests. Resets `_sinkOpen` and
  /// `_bannerWritten` so the next [_openSink] writes a banner
  /// against the fresh backend.
  @visibleForTesting
  void debugSetBackend(LoggerBackend backend) {
    _backend = backend;
    _sinkOpen = false;
    _bannerWritten = false;
  }

  /// Restore the production FRB-backed backend. Pair with
  /// `debugSetBackend` in test tear-down.
  @visibleForTesting
  void debugResetBackend() {
    _backend = const _RustLoggerBackend();
    _sinkOpen = false;
    _bannerWritten = false;
  }

  /// Reset every piece of in-memory state — used by tests that need
  /// a clean slate between cases without a fresh process. Does NOT
  /// touch the Rust-side held sink (the caller flips that through
  /// `loggerCloseSink` separately) because the held state is
  /// process-wide and resetting it from Dart would require an FRB
  /// hop on every test, which the suite already serialises.
  @visibleForTesting
  void debugResetState() {
    _threshold = null;
    _sinkOpen = false;
    _bannerWritten = false;
    _frbReady = false;
    _logPath = null;
    _appVersion = null;
    _preFrbCriticalBuffer.clear();
  }

  /// Flip the FRB-ready gate without running the post-FRB drain.
  /// Production code never calls this — `onFrbReady` is
  /// the canonical entry point because it also drains the
  /// pre-FRB critical buffer and (when a threshold is set) runs
  /// the deferred sink open. Tests that want to simulate the post-
  /// bootstrap state without the drain side-effect call this
  /// instead. The pre-FRB critical-buffer test still asserts the
  /// drain pathway explicitly.
  @visibleForTesting
  void debugMarkFrbReady() {
    _frbReady = true;
  }

  /// Path to the current log file, or null if not initialized.
  String? get logPath => _logPath;

  /// Stamp the app version that the next [_openSink] writes into the
  /// session-start banner. Wired from `_mainBody` after
  /// `PackageInfo.fromPlatform` resolves; idempotent. Best-effort —
  /// callers do not check for failures, the banner falls back to a
  /// version-less form when this stays null.
  void setAppVersion(String version) {
    _appVersion = version;
  }

  /// Whether file logging is currently enabled (threshold set).
  bool get enabled => _threshold != null;

  /// Current severity threshold. `null` means logging is off.
  LogLevel? get threshold => _threshold;

  /// Change the minimum severity that lands in the sink. Passing
  /// `null` closes the sink; passing any [LogLevel] opens it if not
  /// already open. Cheap to call repeatedly — threshold updates with
  /// the sink already open don't reopen.
  Future<void> setThreshold(LogLevel? value) async {
    if (value == _threshold) return;
    final opening = _threshold == null && value != null;
    final closing = _threshold != null && value == null;
    _threshold = value;
    if (opening) {
      await _openSink();
    } else if (closing) {
      await _closeSink();
    }
  }

  /// Initialize the logger — resolves the log path without touching
  /// the filesystem. The Rust-side `logger_open_sink` creates the
  /// `logs/` parent directory + opens the file when [setThreshold]
  /// flips logging on; `init()` only resolves the platform's
  /// app-support directory through `path_provider` so [logPath]
  /// reports a useful value before any user has flipped the toggle.
  ///
  /// Cold-start safe: `path_provider` is a Flutter plugin (not FRB),
  /// so it works from `main.dart` before `RustLib.init()`. No
  /// `dart:io File` / `Directory` operations run here — the path is
  /// a string composed from the resolver's return value.
  ///
  /// Failures here (path resolution) never throw — [logCritical]
  /// keeps buffering pre-FRB and the drain on FRB-ready becomes a
  /// silent no-op when [_logPath] stays null.
  Future<void> init() async {
    try {
      final dir = await getApplicationSupportDirectory();
      _logPath = '${dir.path}/logs/letsflutssh.log';
    } catch (_) {
      // Best-effort init — a failed `path_provider` resolve means
      // neither routine nor critical writes will land; the stderr
      // mirror inside `logCritical` is the only forensic surface
      // for that (rare) machine state.
    }
  }

  /// Subscribe to `BusTopic::CoreLog` so every Rust-core log line
  /// folds into the same on-disk file Dart writes through. The
  /// subscriber routes the message through [log] with the matching
  /// level, so the threshold + sanitization + line format stay in
  /// one place.
  ///
  /// Must be called **after** `rust_app.appInit()` — `bus_subscribe`
  /// internally reaches into `lfs_core::app::instance()` which
  /// panics if AppState isn't yet built. main.dart wires it
  /// straight after `rust_app.appInit()` for that reason.
  ///
  /// Best-effort — flutter_test contexts that don't load the FRB
  /// native lib hit the catch and the pipe stays unwired (Dart
  /// tests don't exercise Rust log paths anyway).
  void attachCoreLogPipe() {
    if (_coreLogSub != null) return; // idempotent
    try {
      _coreLogSub = rust_bus
          .busSubscribe(topic: rust_bus.BusTopic.coreLog)
          .listen((event) {
            if (event is rust_bus.BusEvent_CoreLog) {
              final level = logLevelFromJson(event.levelWireName);
              log(event.message, name: event.name, level: level);
            }
          });
    } catch (e) {
      // FRB native lib not loaded — skip the pipe; Rust log lines
      // will not surface in the Dart-side file, but the rest of
      // logging keeps working. Sanitise the error before stderr
      // write — `e` may carry an FRB envelope or path fragments
      // that the same redaction chain `log()` runs would catch.
      // `_safeStderrWriteln` gates on `hasTerminal` so a packaged GUI
      // app does not crash on the async flush of a dead stderr handle.
      _safeStderrWriteln(
        'AppLogger: CoreLog pipe skipped: ${sanitize(e.toString())}',
      );
    }
  }

  /// Open the log file for writing.
  ///
  /// Routes through `logger_open_sink` → `logger_rotate_if_needed`
  /// → banner write. The Rust side owns parent-directory creation,
  /// the file handle, and the chmod-0600 step; this method composes
  /// the path argument and writes the banner line through the same
  /// `logger_append_line` channel routine writes use.
  ///
  /// Cold-start aware: when [_frbReady] is false (Rust core not yet
  /// loaded — the few-ms window during `RustLib.init()` inside
  /// `_mainBody`), the open is deferred — `_sinkOpen` stays false and
  /// routine [log] calls no-op. [onFrbReady] reopens from
  /// `_mainBody` once FRB is ready, picking up the threshold the
  /// user (or `--dart-define`) seeded pre-FRB.
  Future<void> _openSink() async {
    if (_logPath == null) return;
    if (!_frbReady) {
      // Pre-FRB: the sink lives Rust-side and cannot be opened yet.
      // `onFrbReady` reopens after `_initRustCoreOrFatal` flips
      // `_frbReady`; the threshold the caller just set stays
      // recorded in `_threshold` so the deferred open picks it up.
      return;
    }
    final dir = _appSupportDirFromLogPath(_logPath!);
    if (dir == null) return;
    try {
      await _backend.openSink(dir);
      _sinkOpen = true;
      await _backend.rotateIfNeeded(maxLogSizeBytes, _maxRotatedFiles);
      if (!_bannerWritten) {
        _backend.appendLine(_buildSessionBanner());
        _backend.appendLine('');
        _bannerWritten = true;
      }
    } catch (_) {
      // Sink open failed Rust-side — leave _sinkOpen false so
      // writes no-op; no OS-logging fallback by design.
      _sinkOpen = false;
    }
  }

  /// Derive the platform's app-support directory from a registered
  /// log path. The log path always has the shape
  /// `<app_support>/logs/letsflutssh.log`, so stripping the
  /// trailing `/logs/letsflutssh.log` recovers the directory the
  /// Rust open-sink helper expects. Returns null when the path does
  /// not match the expected shape — defensive against a future
  /// caller stamping `_logPath` from somewhere other than [init].
  String? _appSupportDirFromLogPath(String logPath) {
    const suffix = '/logs/letsflutssh.log';
    if (logPath.endsWith(suffix)) {
      return logPath.substring(0, logPath.length - suffix.length);
    }
    // Windows separators — `path_provider` returns forward slashes
    // on every supported platform today, but keep the back-slash
    // branch wired so a path that arrives via a different resolver
    // does not silently fail to open the sink.
    const winSuffix = r'\logs\letsflutssh.log';
    if (logPath.endsWith(winSuffix)) {
      return logPath.substring(0, logPath.length - winSuffix.length);
    }
    return null;
  }

  /// Single-line session-start banner the viewer renders as
  /// [`_SessionBoundary`]. Carries every piece of run-identifying
  /// metadata in one row so a support session reading the file (or
  /// scrolling the viewer) sees the boundary between two app runs at
  /// a glance — without three separate header lines duplicating the
  /// same "this is a new session" signal. Pipe-delimited so the
  /// viewer can split into segments without a regex.
  String _buildSessionBanner() {
    final now = DateTime.now();
    final timestamp =
        '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}';
    final platform =
        '${Platform.operatingSystem} ${Platform.operatingSystemVersion}'.trim();
    final parts = <String>['Log started $timestamp', platform];
    final v = _appVersion;
    if (v != null && v.isNotEmpty) parts.add('LetsFLUTssh $v');
    return '--- ${parts.join(' | ')} ---';
  }

  /// Called from `_mainBody` right after `_initRustCoreOrFatal`
  /// succeeds, before `loadAppConfigFromDisk` snapshots the config
  /// store and before `runApp` fires the first frame. Three
  /// responsibilities:
  ///
  /// 1. Flip the FRB-ready gate so subsequent [logCritical] calls
  ///    route straight to Rust instead of buffering, and so a
  ///    later [setThreshold] flip can open the sink.
  /// 2. If the user (or `--dart-define=LETSFLUTSSH_LOG_LEVEL`) has
  ///    already picked a non-null threshold pre-FRB, run the
  ///    deferred [_openSink] now so the routine writer is live by
  ///    the time the first post-FRB call site reaches [log].
  /// 3. Drain [_preFrbCriticalBuffer] through
  ///    `logger_append_critical` so any crash that landed during
  ///    the pre-FRB cold-start window reaches the on-disk log.
  ///
  /// Idempotent — repeated calls re-drain an already-empty buffer
  /// and re-enter [_openSink] which itself short-circuits on an
  /// already-open sink. Best-effort: a single drain failure does
  /// not stop subsequent entries.
  Future<void> onFrbReady() async {
    _frbReady = true;
    if (_logPath == null) {
      _preFrbCriticalBuffer.clear();
      return;
    }
    final dir = _appSupportDirFromLogPath(_logPath!);
    if (dir == null) {
      _preFrbCriticalBuffer.clear();
      return;
    }
    if (_threshold != null && !_sinkOpen) {
      // User (or build-time override) flipped logging on pre-FRB;
      // run the deferred open now. This also writes the session
      // banner that `_openSink` would normally emit at the time
      // the threshold flipped.
      await _openSink();
    } else if (!_sinkOpen) {
      // Logging is off — register the log path Rust-side so
      // `logger_append_critical` has a resolved destination. The
      // routine sink stays held but no `appendLine` call will
      // reach it (the `_sinkOpen` guard inside [log] requires a
      // non-null threshold too).
      try {
        await _backend.openSink(dir);
        _sinkOpen = true;
      } catch (_) {
        _preFrbCriticalBuffer.clear();
        return;
      }
    }
    final pending = List<_PendingCritical>.from(_preFrbCriticalBuffer);
    _preFrbCriticalBuffer.clear();
    for (final entry in pending) {
      try {
        _backend.appendCritical(entry.line, entry.continuations);
      } catch (_) {
        // Best-effort drain. A single failed entry must not block
        // the rest; subsequent crashes still need a writable file.
      }
    }
  }

  /// Strips sensitive data from a string before logging.
  ///
  /// Applied to every log message, error, and stack trace — including
  /// those originating from third-party libraries (russh, rusqlite,
  /// `archive`, etc.) and from the Rust core via FRB, so host/user/IP
  /// data leaked through library exception messages never reaches
  /// the log file.
  ///
  /// Scrubs:
  /// - PEM private keys and long base64 blobs (key material)
  /// - IPv4 addresses, `user@host`, `host:port`
  /// - Home-directory paths (`/home/<user>/`, `C:\Users\<user>\`)
  static String sanitize(String input) {
    // Strip key material first, then scrub IPs / user@host / home
    // paths — catches data leaking through third-party exception
    // messages.
    return sanitizeErrorMessage(redactSecrets(input));
  }

  /// Log a message.
  ///
  /// The line is written to the file sink only when [level] is at or
  /// above the current [threshold]. [level] defaults to
  /// [LogLevel.info]; when an [error] object is passed without an
  /// explicit level, auto-promote to [LogLevel.error] so existing
  /// call sites that pass `error:` show up tinted red in the viewer
  /// without having to be rewritten.
  void log(
    String message, {
    String? name,
    Object? error,
    StackTrace? stackTrace,
    LogLevel? level,
  }) {
    final threshold = _threshold;
    if (threshold == null || !_sinkOpen) return;
    final resolvedLevel =
        level ?? (error != null ? LogLevel.error : LogLevel.info);
    if (resolvedLevel.index < threshold.index) return;

    final tag = name ?? 'App';
    final safeMsg = sanitize(message);
    final safeError = error == null ? null : sanitize(error.toString());
    final now = DateTime.now();
    final ts = _formatHmsForLog(now);
    final continuations = <String>[];
    if (safeError != null) continuations.add('  Error: $safeError');
    if (stackTrace != null) {
      continuations.add('  Stack trace:');
      for (final frame in sanitize('$stackTrace').split('\n')) {
        if (frame.isEmpty) continue;
        continuations.add('  $frame');
      }
    }
    try {
      _backend.appendLine('$ts ${_levelChar(resolvedLevel)} [$tag] $safeMsg');
      for (final c in continuations) {
        _backend.appendLine(c);
      }
    } catch (_) {
      // Don't crash the app for logging failures.
    }
    _emitEntry(
      LogEntry(
        level: resolvedLevel,
        timestamp: ts,
        tag: tag,
        message: safeMsg,
        continuations: List.unmodifiable(continuations),
      ),
    );
  }

  void _emitEntry(LogEntry entry) {
    if (_entriesController.isClosed) return;
    try {
      _entriesController.add(entry);
    } catch (_) {
      // Subscribers' onError handlers manage their own failures;
      // a broken stream here must never break logging.
    }
  }

  /// Crash-path logger. Writes straight to the on-disk log file even
  /// when the user has routine logging turned off, so global error
  /// boundaries, migration fatals and DB-integrity-probe failures
  /// always leave a forensic breadcrumb. The Rust-side
  /// `logger_append_critical` opens a fresh append handle that does
  /// not depend on whether the routine sink is open, so the write
  /// lands without re-enabling user-facing logging.
  ///
  /// Pre-FRB calls (zone error handler fires before
  /// `_initRustCoreOrFatal` returns) buffer in
  /// [_preFrbCriticalBuffer] + write to stderr (desktop only) +
  /// emit on the live stream. [onFrbReady] drains the
  /// buffer once Rust is up.
  ///
  /// Privacy: the file is chmod-0600 Rust-side (same hardening as
  /// routine logs), the message still passes through [sanitize], and
  /// rotation handled by [_openSink] still applies the next time
  /// the user raises the threshold. Bypassing the threshold on crash
  /// paths only is the narrowest exception needed to meet the "fresh
  /// install crashes should be debuggable without a pre-flip"
  /// requirement.
  ///
  /// Best-effort — any I/O error swallowed so a broken disk does not
  /// amplify into a second crash inside the crash handler.
  Future<void> logCritical(
    String message, {
    String? name,
    Object? error,
    StackTrace? stackTrace,
  }) async {
    final tag = name ?? 'App';
    final safeMsg = sanitize(message);
    final safeError = error == null ? null : sanitize(error.toString());
    final now = DateTime.now();
    final ts = _formatHmsForLog(now);
    final continuations = <String>[];
    if (safeError != null) continuations.add('  Error: $safeError');
    if (stackTrace != null) {
      continuations.add('  Stack trace:');
      for (final frame in sanitize('$stackTrace').split('\n')) {
        if (frame.isEmpty) continue;
        continuations.add('  $frame');
      }
    }
    final header = '$ts ${_levelChar(LogLevel.error)} [$tag] $safeMsg';
    final continuationList = List<String>.unmodifiable(continuations);

    _mirrorCriticalToStderr(header, continuations);
    _emitEntry(
      LogEntry(
        level: LogLevel.error,
        timestamp: ts,
        tag: tag,
        message: safeMsg,
        continuations: continuationList,
      ),
    );

    if (_logPath == null) {
      // No file sink — stderr above is the only forensic surface.
      return;
    }
    if (!_frbReady) {
      _bufferPreFrbCritical(header, continuationList);
      return;
    }
    try {
      _backend.appendCritical(header, continuationList);
    } catch (_) {
      // Swallow — never crash inside the crash handler.
    }
  }

  /// Stderr mirror for [logCritical]. Desktop only — the file sink
  /// can fail (disk full, permissions, missing path) and the whole
  /// point of `logCritical` is forensic visibility on a crashing
  /// app. On a desktop launched from a terminal the stderr line is
  /// the difference between "process died silently" and "I have a
  /// stack trace to grep".
  ///
  /// Mobile platforms skip the mirror — Android / iOS process
  /// shells do not surface stderr to a user-reachable channel, and
  /// `flutter run` already pipes through `dart:developer`.
  void _mirrorCriticalToStderr(String header, List<String> continuations) {
    if (!(Platform.isLinux || Platform.isMacOS || Platform.isWindows)) {
      return;
    }
    _safeStderrWriteln(header);
    for (final c in continuations) {
      _safeStderrWriteln(c);
    }
  }

  /// Write one line to stderr only when a terminal is attached.
  ///
  /// A packaged GUI app (Windows / macOS double-click launch) has no
  /// console: `stderr` is a buffered `IOSink` whose handle is invalid,
  /// and `writeln` defers the actual write to an *async* flush. That
  /// flush throws `FileSystemException: writeFrom failed, path = ''`
  /// outside any synchronous `try/catch`, so the error escapes into the
  /// zone handler and surfaces as a spurious "unexpected error" dialog —
  /// the crash-handler mirror amplifying into a second crash. Gating on
  /// `hasTerminal` skips the write entirely off-terminal; the file sink
  /// stays the always-on channel. The `try` covers residual synchronous
  /// failure modes when a terminal *is* present.
  static void _safeStderrWriteln(String line) {
    if (!stderr.hasTerminal) return;
    try {
      stderr.writeln(line);
    } catch (_) {
      // Best-effort — never amplify into a second crash.
    }
  }

  /// Push a critical entry into the pre-FRB buffer with FIFO
  /// eviction past [_preFrbCriticalCap]. Holding the buffer in
  /// memory keeps `logCritical` callable from the zone error
  /// handler that fires before `_initRustCoreOrFatal` returns —
  /// the cold-start window is the exact one where a fresh-install
  /// crash matters most, and routing the buffer through FRB would
  /// throw `StateError` instead of preserving the entry.
  void _bufferPreFrbCritical(String header, List<String> continuations) {
    if (_preFrbCriticalBuffer.length >= _preFrbCriticalCap) {
      _preFrbCriticalBuffer.removeAt(0);
    }
    _preFrbCriticalBuffer.add(_PendingCritical(header, continuations));
  }

  /// Read the current log file content. Flushes before reading.
  /// Returns empty string if no log file exists.
  ///
  /// Re-registers the log path Rust-side before the read so the
  /// Rust-side `file_sink::STATE.log_path` matches the Dart-side
  /// `_logPath`. The cross-platform unit-test suite runs many cases
  /// in one process with successive temp directories; without the
  /// sync the Rust state would still hold the prior case's path
  /// and the read would resolve against the wrong file. In
  /// production the path never changes after `init` (one
  /// app-support tree per launch), so the sync is a no-op.
  Future<String> readLog() async {
    if (_logPath == null) return '';
    if (!_frbReady) return '';
    final dir = _appSupportDirFromLogPath(_logPath!);
    if (dir == null) return '';
    try {
      // Idempotent on the same dir; switches state when the Dart
      // path is the new test's tempDir vs the Rust-held prior path.
      await _backend.openSink(dir);
      _sinkOpen = true;
      return await _backend.readAll();
    } catch (_) {
      return '';
    }
  }

  /// Flush and close the log file. Sets threshold to null so no
  /// further routine writes land until [setThreshold] is called with
  /// a non-null value.
  Future<void> dispose() async {
    _threshold = null;
    _appVersion = null;
    _bannerWritten = false;
    await _coreLogSub?.cancel();
    _coreLogSub = null;
    await _closeSink();
    if (!_entriesController.isClosed) {
      await _entriesController.close();
    }
  }

  /// Delete all log files.
  Future<void> clearLogs() async {
    final previousThreshold = _threshold;
    await _closeSink();
    if (_logPath == null) return;
    if (!_frbReady) {
      // Pre-FRB: no Rust state to clear, nothing on disk that the
      // user has had the chance to enable yet (routine writes
      // defer pre-FRB). Skip the FRB hop and leave the threshold
      // restoration for the post-bootstrap drain.
      return;
    }
    final dir = _appSupportDirFromLogPath(_logPath!);
    if (dir == null) return;
    try {
      // Sync Rust state to the active log path before deleting —
      // unit tests run many cases in one process with distinct
      // temp dirs, and the Rust held-path would otherwise point at
      // a prior case's tempDir. `loggerOpenSink` is idempotent on
      // the active dir + reseats the path when it changed.
      await _backend.openSink(dir);
      await _backend.clearAll(_maxRotatedFiles);
    } catch (_) {
      // Best-effort delete. A failed unlink leaves stale files
      // behind; the next rotation will eventually reclaim the
      // slots.
    }
    // Clear is a deliberate "new session" boundary — let the next
    // [_openSink] write a fresh banner above the post-clear entries
    // instead of leaving a banner-less file.
    _bannerWritten = false;

    if (previousThreshold != null) {
      _threshold = previousThreshold;
      await _openSink();
    }
  }

  /// Close the log file sink without disabling the threshold.
  Future<void> _closeSink() async {
    try {
      _backend.flushSink();
      _backend.closeSink();
    } catch (_) {}
    _sinkOpen = false;
  }
}
