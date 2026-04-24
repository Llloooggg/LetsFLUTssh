import 'dart:developer' as dev;
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'sanitize.dart';

/// Severity marker for a log line. Written as a single char after the
/// timestamp so the live viewer can tint each row without reparsing the
/// message text. Matches the Logcat / journald convention.
///
/// * [info] — routine operational entry. No extra visual treatment in
///   the viewer beyond the baseline monospace colour.
/// * [warn] — degraded but recoverable ("fell back to plaintext",
///   "probe failed, using default"). Amber tint + left border.
/// * [error] — failure the user likely cares about (crash, migration
///   fatal, DB corruption). Red tint + left border. `logCritical`
///   forces this level even when routine logging is off.
enum LogLevel { info, warn, error }

String _levelChar(LogLevel l) => switch (l) {
  LogLevel.info => 'I',
  LogLevel.warn => 'W',
  LogLevel.error => 'E',
};

/// File-based logger.
///
/// Writes logs to `<appSupportDir>/logs/letsflutssh.log` alongside the app data.
/// Automatically rotates when the log file exceeds [maxLogSizeBytes].
///
/// **Routine logs are opt-in.** Disabled by default — user enables via
/// Settings → Enable Logging. This preserves the privacy-by-default stance
/// for the steady-state stream of info / debug lines.
///
/// **Critical paths bypass the toggle.** [logCritical] writes straight to
/// disk regardless of [enabled] state so crash boundaries, migration
/// fatals and DB-integrity-probe failures always leave a forensic
/// breadcrumb — the window where a trace matters most is exactly the one
/// where the user has not yet flipped the toggle. The write uses
/// [FileMode.append] on [logPath] directly, never touches [_sink], so
/// it does not leak routine entries past the opt-out gate.
///
/// All messages pass through [sanitize] (PEM blobs, IPv4 / user@host,
/// home-directory paths are redacted) and the file is chmod-0600 on POSIX —
/// same hardening as `credentials.*` and `config.json`.
class AppLogger {
  static AppLogger? _instance;
  static const maxLogSizeBytes = 5 * 1024 * 1024; // 5 MB
  static const _maxRotatedFiles = 3;

  IOSink? _sink;
  String? _logPath;
  // Routine logs default OFF — the user opts in via Settings. Critical
  // paths ([logCritical]) bypass this gate entirely so crash breadcrumbs
  // survive even when routine logging is disabled.
  bool _enabled = false;

  AppLogger._();

  /// Get the singleton instance.
  static AppLogger get instance => _instance ??= AppLogger._();

  /// Path to the current log file, or null if not initialized.
  String? get logPath => _logPath;

  /// Whether file logging is currently enabled.
  bool get enabled => _enabled;

  /// Enable or disable file logging at runtime (no restart needed).
  Future<void> setEnabled(bool value) async {
    if (value == _enabled) return;
    _enabled = value;
    if (value) {
      await _openSink();
    } else {
      await dispose();
    }
  }

  /// Initialize the logger — resolves the log path but does NOT open
  /// the routine sink. Called from `main.dart` before `runApp` so that
  /// [logCritical] has a resolved path ready for any pre-`runZonedGuarded`
  /// crash. The main write sink opens only when the user has routine
  /// logging enabled (handled by `ConfigProvider.load` → [setEnabled]).
  ///
  /// Failures here (path resolution, directory create) never throw —
  /// [logCritical] degrades to `dart:developer` when [_logPath] is null.
  Future<void> init() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final logDir = Directory('${dir.path}/logs');
      if (!await logDir.exists()) {
        await logDir.create(recursive: true);
      }
      _logPath = '${logDir.path}/letsflutssh.log';
    } catch (e) {
      dev.log('AppLogger: failed to init: $e');
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
    } catch (e) {
      dev.log('AppLogger: failed to open log file: $e');
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
  /// Applied to every log message, error, and stack trace — including those
  /// originating from third-party libraries (dartssh2, drift, archive, etc.),
  /// so host/user/IP data leaked through library exception messages never
  /// reaches the log file or DevTools.
  ///
  /// Scrubs:
  /// - PEM private keys and long base64 blobs (key material)
  /// - IPv4 addresses, `user@host`, `host:port`
  /// - Home-directory paths (`/home/<user>/`, `C:\Users\<user>\`)
  static String sanitize(String input) {
    // Strip key material first, then scrub IPs / user@host / home paths —
    // catches data leaking through third-party exception messages.
    return sanitizeErrorMessage(redactSecrets(input));
  }

  /// Log a message. Also forwards to dart:developer log (DevTools).
  /// File write only happens if logging is [enabled].
  ///
  /// [level] defaults to [LogLevel.info]; when an [error] object is
  /// passed without an explicit level, auto-promote to [LogLevel.error]
  /// so existing call sites that pass `error:` show up tinted red in
  /// the viewer without having to be rewritten.
  void log(
    String message, {
    String? name,
    Object? error,
    StackTrace? stackTrace,
    LogLevel? level,
  }) {
    final tag = name ?? 'App';
    final safeMsg = sanitize(message);
    final safeError = error == null ? null : sanitize(error.toString());
    final resolvedLevel =
        level ?? (error != null ? LogLevel.error : LogLevel.info);
    dev.log(safeMsg, name: tag, error: safeError);

    if (!_enabled || _sink == null) return;

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
        _sink!.writeln(sanitize('$stackTrace'));
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
  /// of user-toggle state and avoids leaking subsequent routine entries.
  ///
  /// Privacy: the file is still chmod-0600 (same hardening as routine
  /// logs), the message still passes through [sanitize], and rotation
  /// handled by [_openSink] still applies the next time the user
  /// flips the toggle on. Bypassing the toggle on crash paths only is
  /// the narrowest exception needed to meet the "fresh install
  /// crashes should be debuggable without a pre-flip" requirement.
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
    // Always forward to dart:developer too, same contract as [log].
    dev.log(safeMsg, name: tag, error: safeError);
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
        buf.writeln(sanitize('$stackTrace'));
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

  /// Flush and close the log file.
  Future<void> dispose() async {
    _enabled = false;
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
    final wasEnabled = _enabled;
    await _closeSink();
    if (_logPath == null) return;

    for (var i = 0; i <= _maxRotatedFiles; i++) {
      final path = i == 0 ? _logPath! : '$_logPath.$i';
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    }

    if (wasEnabled) await _openSink();
  }

  /// Close the log file sink without disabling logging.
  Future<void> _closeSink() async {
    try {
      await _sink?.flush();
      await _sink?.close();
    } catch (_) {}
    _sink = null;
  }
}
