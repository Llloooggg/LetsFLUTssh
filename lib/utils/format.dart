import '../core/ssh/errors.dart';

/// Format byte size to human-readable string.
String formatSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

/// Format DateTime to short timestamp.
String formatTimestamp(DateTime dt) {
  return '${dt.year}-${_pad(dt.month)}-${_pad(dt.day)} '
      '${_pad(dt.hour)}:${_pad(dt.minute)}';
}

/// Format Duration to human-readable string.
String formatDuration(Duration d) {
  if (d.inSeconds < 1) return '${d.inMilliseconds}ms';
  if (d.inMinutes < 1) return '${d.inSeconds}s';
  if (d.inHours < 1) return '${d.inMinutes}m ${d.inSeconds % 60}s';
  return '${d.inHours}h ${d.inMinutes % 60}m';
}

String _pad(int n) => n.toString().padLeft(2, '0');

/// Sanitize error messages to English — strips OS-locale text from
/// FileSystemException, SocketException, and SSH errors, replacing with
/// the English OS error code description.
///
/// For [SSHError] subtypes the English [SSHError.message] is preserved and
/// only the wrapped [SSHError.cause] is sanitized (it may contain
/// OS-locale text from SocketException / FileSystemException).
String sanitizeError(Object error) {
  // SSHError chain: keep English message, sanitize cause recursively.
  if (error is SSHError) {
    if (error.cause == null) return error.message;
    final cause = sanitizeError(error.cause!);
    if (cause.isNotEmpty && cause != error.message) {
      return '${error.message} ($cause)';
    }
    return error.message;
  }

  final msg = error.toString();

  // FileSystemException: "OS Error: <localized text>, errno = N"
  // Extract errno and map to English message.
  final errnoMatch = RegExp(r'errno\s*=\s*(\d+)').firstMatch(msg);
  if (errnoMatch != null) {
    final errno = int.parse(errnoMatch.group(1)!);
    final english = _errnoMessages[errno];
    if (english != null) {
      // Try to extract the path from the exception
      final pathMatch = RegExp(r"path\s*=\s*'([^']*)'").firstMatch(msg);
      final path = pathMatch?.group(1);
      return path != null ? '$english: $path' : english;
    }
  }

  // SocketException / HttpException: strip localized OS error
  final osErrorMatch = RegExp(
    r'OS Error:\s*[^,]+,\s*errno\s*=\s*(\d+)',
  ).firstMatch(msg);
  if (osErrorMatch != null) {
    final errno = int.parse(osErrorMatch.group(1)!);
    final english = _errnoMessages[errno];
    if (english != null) return english;
  }

  return msg;
}

const _errnoMessages = <int, String>{
  // POSIX / Linux
  1: 'Operation not permitted',
  2: 'No such file or directory',
  3: 'No such process',
  5: 'I/O error',
  9: 'Bad file descriptor',
  11: 'Resource temporarily unavailable',
  12: 'Out of memory',
  13: 'Permission denied',
  17: 'File exists',
  20: 'Not a directory',
  21: 'Is a directory',
  22: 'Invalid argument',
  23: 'Too many open files',
  28: 'No space left on device',
  30: 'Read-only file system',
  32: 'Broken pipe',
  36: 'File name too long',
  39: 'Directory not empty',
  98: 'Address already in use',
  99: 'Cannot assign requested address',
  100: 'Network is down',
  101: 'Network is unreachable',
  104: 'Connection reset by peer',
  110: 'Connection timed out',
  111: 'Connection refused',
  112: 'Host is down',
  113: 'No route to host',
  // Windows Winsock (WSA*)
  10013: 'Permission denied',
  10048: 'Address already in use',
  10049: 'Cannot assign requested address',
  10050: 'Network is down',
  10051: 'Network is unreachable',
  10053: 'Connection aborted',
  10054: 'Connection reset by peer',
  10056: 'Already connected',
  10057: 'Not connected',
  10060: 'Connection timed out',
  10061: 'Connection refused',
  10064: 'Host is down',
  10065: 'No route to host',
};
