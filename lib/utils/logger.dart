import 'dart:io';

import 'package:path_provider/path_provider.dart';

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
///   "tier switched to L2", "DB open". The default level for every
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
/// **No OS logging mirror.** Unlike the previous revision, routine
/// [log] calls do NOT forward to `dart:developer` — Android Logcat /
/// macOS Console.app / desktop stderr never see our lines. The only
/// logging surface the user (or anyone with `adb logcat` / Console
/// access) sees is the opt-in file under app-support.
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
  // Current minimum severity that hits the sink. `null` = logging
  // off; any LogLevel admits lines at or above that level. Critical
  // paths ([logCritical]) bypass this gate so crash breadcrumbs
  // survive even when routine logging is disabled.
  LogLevel? _threshold;

  AppLogger._();

  /// Get the singleton instance.
  static AppLogger get instance => _instance ??= AppLogger._();

  /// Path to the current log file, or null if not initialized.
  String? get logPath => _logPath;

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

  /// Open the log file for writing.
  Future<void> _openSink() async {
    if (_logPath == null) return;
    try {
      await _rotateIfNeeded();
      final file = File(_logPath!);
      _sink = file.openWrite(mode: FileMode.append);
      await _restrictPermissions(_logPath!);

      final now = DateTime.now().toIso8601String();
      _sink!.writeln('--- Log started $now ---');
      _sink!.writeln(
        'Platform: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
      );
      _sink!.writeln('Dart: ${Platform.version.split(' ').first}');
      _sink!.writeln('');
    } catch (_) {
      // Sink open failed — leave _sink null so writes no-op; no OS-
      // logging fallback by design.
    }
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
  Future<void> _restrictPermissions(String path) async {
    if (Platform.isWindows) return;
    try {
      await Process.run('chmod', ['600', path]);
    } catch (_) {
      // Best-effort. Logger hardening must never break logging.
    }
  }

  /// Strips sensitive data from a string before logging.
  ///
  /// Applied to every log message, error, and stack trace — including
  /// those originating from third-party libraries (russh, drift,
  /// archive, etc.) and from the Rust core via FRB, so host/user/IP
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
    try {
      final now = DateTime.now();
      final ts =
          '${now.hour.toString().padLeft(2, '0')}:'
          '${now.minute.toString().padLeft(2, '0')}:'
          '${now.second.toString().padLeft(2, '0')}';
      _sink!.writeln('$ts ${_levelChar(resolvedLevel)} [$tag] $safeMsg');
      if (safeError != null) {
        _sink!.writeln('  Error: $safeError');
      }
      if (stackTrace != null) {
        _sink!.writeln('  Stack trace:');
        // Indent every stack-trace line with two spaces so the viewer
        // parser folds them into the parent entry instead of treating
        // each `#N …` frame as its own dim-italic header row.
        for (final frame in sanitize('$stackTrace').split('\n')) {
          if (frame.isEmpty) continue;
          _sink!.writeln('  $frame');
        }
      }
    } catch (_) {
      // Don't crash the app for logging failures.
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
    if (_logPath == null) return;
    try {
      final now = DateTime.now();
      final ts =
          '${now.hour.toString().padLeft(2, '0')}:'
          '${now.minute.toString().padLeft(2, '0')}:'
          '${now.second.toString().padLeft(2, '0')}';
      // logCritical is always error-level by contract.
      final buf = StringBuffer()
        ..writeln('$ts ${_levelChar(LogLevel.error)} [$tag] $safeMsg');
      if (safeError != null) buf.writeln('  Error: $safeError');
      if (stackTrace != null) {
        buf.writeln('  Stack trace:');
        // Indent every stack-trace line with two spaces — same rule
        // as the routine [log] path so the viewer parser folds frames
        // into the parent entry.
        for (final frame in sanitize('$stackTrace').split('\n')) {
          if (frame.isEmpty) continue;
          buf.writeln('  $frame');
        }
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
    await _closeSink();
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
