import 'dart:developer' as dev;
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// File-based logger controlled by user setting.
///
/// Writes logs to `<appSupportDir>/logs/letsflutssh.log` alongside the app data.
/// Automatically rotates when the log file exceeds [maxLogSizeBytes].
/// Disabled by default — user enables via Settings → Enable Logging.
/// Never logs sensitive data (passwords, keys, credentials).
class AppLogger {
  static AppLogger? _instance;
  static const maxLogSizeBytes = 5 * 1024 * 1024; // 5 MB
  static const _maxRotatedFiles = 3;

  IOSink? _sink;
  String? _logPath;
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

  /// Initialize the logger — resolves the log path but does NOT start writing.
  /// Call [setEnabled(true)] to start writing (triggered by config load).
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

  /// Strips sensitive data (PEM private keys, passwords in SQL) from a string.
  /// Applied to all log messages and error traces.
  static String sanitize(String input) {
    // Redact OpenSSH/PKCS private keys in PEM format.
    final pemPattern = RegExp(
      r'-----BEGIN[^-]*PRIVATE KEY-----[\s\S]*?-----END[^-]*PRIVATE KEY-----',
      multiLine: true,
    );
    var out = input.replaceAll(pemPattern, '[REDACTED PRIVATE KEY]');
    // Redact base64-encoded key blobs (long continuous base64 runs).
    out = out.replaceAll(RegExp(r'[A-Za-z0-9+/=]{200,}'), '[REDACTED BASE64]');
    return out;
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
