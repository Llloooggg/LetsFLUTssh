import 'dart:developer' as dev;
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'sanitize.dart';

/// File-based logger.
///
/// Writes logs to `<appSupportDir>/logs/letsflutssh.log` alongside the app data.
/// Automatically rotates when the log file exceeds [maxLogSizeBytes].
///
/// **Always-on by default.** Every log call hits the file sink once [init]
/// resolves the path and opens the sink. The previous "disabled by default"
/// behaviour meant a fresh install that crashed before the user flipped the
/// Settings toggle left no forensic trail — exactly the window where a trail
/// is most needed. [setEnabled]`(false)` is still honoured as an explicit
/// opt-out: it closes the sink and stops writes; logs already on disk stay
/// until the user hits "Clear" in Settings.
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
  // Tracks whether the user has explicitly opted out via Settings. The
  // default is "logs are on" — the sink is opened eagerly by [init] so
  // startup crashes and first-launch failures land on disk without
  // waiting for a user toggle. Flipping this to `false` via [setEnabled]
  // closes the sink for the rest of the session; flipping back re-opens.
  bool _enabled = true;

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

  /// Initialize the logger — resolves the log path AND opens the sink
  /// so the first [log] call writes straight to disk. Called very early
  /// in `main` (before `runApp`) so even pre-`runZonedGuarded` crashes
  /// have a chance to be captured.
  ///
  /// Failures here (path resolution, directory create, sink open) never
  /// throw — the logger degrades to `dart:developer` output only.
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
      return;
    }
    if (_enabled) {
      await _openSink();
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
  void log(
    String message, {
    String? name,
    Object? error,
    StackTrace? stackTrace,
  }) {
    final tag = name ?? 'App';
    final safeMsg = sanitize(message);
    final safeError = error == null ? null : sanitize(error.toString());
    dev.log(safeMsg, name: tag, error: safeError);

    if (!_enabled || _sink == null) return;

    try {
      final now = DateTime.now();
      final ts =
          '${now.hour.toString().padLeft(2, '0')}:'
          '${now.minute.toString().padLeft(2, '0')}:'
          '${now.second.toString().padLeft(2, '0')}';
      _sink!.writeln('$ts [$tag] $safeMsg');
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
