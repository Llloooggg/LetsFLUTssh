import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../src/rust/api/bus.dart' as rust_bus;
import '../src/rust/api/path.dart' as rust_path;
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
/// Defined here (not in `lib/features/settings/settings_logging_parser.dart`)
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
/// the toggle. The write uses [FileMode.append] on [logPath] directly,
/// never touches [_sink], so it does not leak routine entries past
/// the opt-out gate.
///
/// **No OS logging mirror.** Routine [log] calls do NOT forward to
/// `dart:developer` — Android Logcat / macOS Console.app / desktop
/// stderr never see our lines. The only logging surface the user
/// (or anyone with `adb logcat` / Console access) sees is the
/// opt-in file under app-support. **Don't add a stderr / OS-log
/// mirror "for development convenience"** — it leaks every line a
/// user with logging enabled produces into a system surface the
/// app cannot retract.
///
/// All messages pass through [sanitize] (PEM blobs, IPv4 / user@host,
/// home-directory paths are redacted) and the file is chmod-0600 on
/// POSIX — same hardening as `credentials.*` and `config.json`.
class AppLogger {
  static AppLogger? _instance;
  static const maxLogSizeBytes = 5 * 1024 * 1024; // 5 MB
  static const _maxRotatedFiles = 3;

  IOSink? _sink;
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

  AppLogger._();

  /// Get the singleton instance.
  static AppLogger get instance => _instance ??= AppLogger._();

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

  /// Initialize the logger — resolves the log path but does NOT open
  /// the routine sink. Called from `main.dart` before `runApp` so that
  /// [logCritical] has a resolved path ready for any pre-
  /// `runZonedGuarded` crash. The main write sink opens only when
  /// [setThreshold] is called with a non-null value.
  ///
  /// Failures here (path resolution, directory create) never throw —
  /// [logCritical] becomes a best-effort no-op when [_logPath] stays
  /// null.
  Future<void> init() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final logDir = Directory('${dir.path}/logs');
      if (!await logDir.exists()) {
        await logDir.create(recursive: true);
      }
      _logPath = '${logDir.path}/letsflutssh.log';
    } catch (_) {
      // Best-effort init — no OS-logging fallback anymore; a failed
      // init just means neither routine nor critical writes will land.
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
      stderr.writeln(
        'AppLogger: CoreLog pipe skipped: ${sanitize(e.toString())}',
      );
    }
  }

  /// Open the log file for writing.
  Future<void> _openSink() async {
    if (_logPath == null) return;
    try {
      await _rotateIfNeeded();
      final file = File(_logPath!);
      _sink = file.openWrite(mode: FileMode.append);
      await _restrictPermissions(_logPath!);
      if (!_bannerWritten) {
        _sink!.writeln(_buildSessionBanner());
        _sink!.writeln('');
        _bannerWritten = true;
      }
    } catch (_) {
      // Sink open failed — leave _sink null so writes no-op; no OS-
      // logging fallback by design.
    }
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

  /// Narrow the log file's POSIX permissions to owner-only (`0600`)
  /// right after creation. `File.openWrite` calls `open(2)` with the
  /// current umask, which on most desktops is `0022` — i.e. the file
  /// lands world-readable at `0644`. Anything sensitive that slips
  /// past [sanitize] (third-party exception text, hex dumps) is then
  /// readable by every other local user on a shared machine. `chmod
  /// 600` is the same hardening the rest of the app applies to
  /// `credentials.*` and `config.json` after atomic writes.
  ///
  /// No-op on Windows — the file inherits the app-support directory's
  /// ACL, which is user-only by default on per-user application data
  /// paths. Failures are swallowed: a file that existed with wider
  /// perms before this hook is best-effort tightened; we do not want
  /// a chmod failure to block logging.
  ///
  /// Routes through `lfs_core::path::harden_file_perms` —
  /// the chmod / icacls grammar lives in Rust. Best-effort: a
  /// chmod failure must never break logging.
  ///
  /// Cold-start aware: the logger opens its sink in `main.dart` —
  /// BEFORE `_initRustCoreOrFatal` runs and the FRB native lib is
  /// loaded. Calling Rust before init would throw `StateError` and
  /// the chmod silently never lands; the file would stay at the
  /// umask-wide default for the rest of the session. We queue
  /// pre-init paths in [_deferredHardenPaths] and drain them via
  /// [hardenPendingLogPerms] from `_bootstrap` once Rust is ready.
  Future<void> _restrictPermissions(String path) async {
    if (Platform.isWindows) return;
    if (!_frbReady) {
      _deferredHardenPaths.add(path);
      return;
    }
    try {
      await rust_path.pathHardenFilePerms(path: path);
    } catch (_) {
      // Best-effort. Logger hardening must never break logging.
    }
  }

  /// Tracks whether [hardenPendingLogPerms] has already flipped the
  /// FRB-ready gate. Pre-init `_restrictPermissions` calls queue
  /// here; the post-init drain flushes the set and starts forwarding
  /// straight to Rust.
  bool _frbReady = false;
  final Set<String> _deferredHardenPaths = <String>{};

  /// Called from `_LetsFLUTsshAppState._bootstrap` after
  /// `_initRustCoreOrFatal` succeeds. Drains any pre-FRB log-file
  /// chmod requests against the now-available Rust core, and flips
  /// the gate so subsequent [_restrictPermissions] calls forward
  /// straight to Rust. Idempotent.
  Future<void> hardenPendingLogPerms() async {
    _frbReady = true;
    if (Platform.isWindows) {
      _deferredHardenPaths.clear();
      return;
    }
    final paths = _deferredHardenPaths.toList();
    _deferredHardenPaths.clear();
    for (final p in paths) {
      try {
        await rust_path.pathHardenFilePerms(path: p);
      } catch (_) {
        // Best-effort. A failed late-harden is no worse than the
        // pre-fix shape (which silently never hardened at all).
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
    if (threshold == null || _sink == null) return;
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
      _sink!.writeln('$ts ${_levelChar(resolvedLevel)} [$tag] $safeMsg');
      for (final c in continuations) {
        _sink!.writeln(c);
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
  /// always leave a forensic breadcrumb. Never opens or closes the
  /// main sink [_sink] — a direct append keeps the write independent
  /// of user-threshold state and avoids leaking subsequent routine
  /// entries.
  ///
  /// Privacy: the file is still chmod-0600 (same hardening as routine
  /// logs), the message still passes through [sanitize], and rotation
  /// handled by [_openSink] still applies the next time the user
  /// raises the threshold. Bypassing the threshold on crash paths
  /// only is the narrowest exception needed to meet the "fresh
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
    // Stderr mirror — desktop only, critical path only. Routine
    // `log()` calls never touch stderr (file-only by design,
    // privacy-first). Critical writes mirror because the file
    // sink can fail (disk full, permissions, missing path) and
    // the whole point of `logCritical` is forensic visibility on
    // a crashing app. On a desktop launched from a terminal the
    // stderr line is the difference between "process died
    // silently" and "I have a stack trace to grep".
    if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
      try {
        stderr.writeln('$ts E [$tag] $safeMsg');
        for (final c in continuations) {
          stderr.writeln(c);
        }
      } catch (_) {
        // Best-effort. Stderr write must never amplify into
        // a second crash inside the crash handler.
      }
    }
    if (_logPath == null) {
      // No file sink — stderr above is the only forensic
      // surface. Skip the file write + entry emit.
      return;
    }
    _emitEntry(
      LogEntry(
        level: LogLevel.error,
        timestamp: ts,
        tag: tag,
        message: safeMsg,
        continuations: List.unmodifiable(continuations),
      ),
    );
    try {
      // logCritical is always error-level by contract.
      final buf = StringBuffer()
        ..writeln('$ts ${_levelChar(LogLevel.error)} [$tag] $safeMsg');
      for (final c in continuations) {
        buf.writeln(c);
      }
      final file = File(_logPath!);
      // Ensure the parent directory exists — [init] already creates
      // it, but a user-side `clearLogs` can remove the whole `logs/`
      // folder between init and the first crit write.
      await file.parent.create(recursive: true);
      await file.writeAsString(
        buf.toString(),
        mode: FileMode.append,
        flush: true,
      );
      await _restrictPermissions(_logPath!);
    } catch (_) {
      // Swallow — never crash inside the crash handler.
    }
  }

  /// Read the current log file content. Flushes before reading.
  /// Returns empty string if no log file exists.
  Future<String> readLog() async {
    if (_logPath == null) return '';
    try {
      await _sink?.flush();
      final file = File(_logPath!);
      if (!await file.exists()) return '';
      return await file.readAsString();
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

  /// Rotate log file if it exceeds [maxLogSizeBytes].
  Future<void> _rotateIfNeeded() async {
    final file = File(_logPath!);
    if (!await file.exists()) return;

    final size = await file.length();
    if (size < maxLogSizeBytes) return;

    for (var i = _maxRotatedFiles - 1; i >= 1; i--) {
      final src = File('$_logPath.$i');
      if (await src.exists()) {
        await src.rename('$_logPath.${i + 1}');
      }
    }
    await file.rename('$_logPath.1');
  }

  /// Delete all log files.
  Future<void> clearLogs() async {
    final previousThreshold = _threshold;
    await _closeSink();
    if (_logPath == null) return;

    for (var i = 0; i <= _maxRotatedFiles; i++) {
      final path = i == 0 ? _logPath! : '$_logPath.$i';
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    }
    // Clear is a deliberate "new session" boundary — let the next
    // [_openSink] write a fresh banner above the post-clear entries
    // instead of leaving a banner-less file.
    _bannerWritten = false;

    if (previousThreshold != null) await _openSink();
  }

  /// Close the log file sink without disabling the threshold.
  Future<void> _closeSink() async {
    try {
      await _sink?.flush();
      await _sink?.close();
    } catch (_) {}
    _sink = null;
  }
}
