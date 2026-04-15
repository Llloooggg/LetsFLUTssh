import 'dart:async';

import 'package:dartssh2/dartssh2.dart' show SftpStatusCode, SftpStatusError;

import '../core/import/import_service.dart';
import '../core/sftp/errors.dart';
import '../core/ssh/errors.dart';
import '../l10n/app_localizations.dart';
import 'sanitize.dart';

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

/// Build a human-readable summary of an [ImportSummary] for the success
/// toast. Leads with the localized "Imported N sessions" string and appends
/// non-zero counts for every other type using existing translated nouns so
/// the message stays informative without adding a dedicated ARB entry per
/// combination.
String formatImportSummary(S l10n, ImportSummary s) {
  final extras = <String>[];
  if (s.managerKeys > 0) extras.add('${s.managerKeys} ${l10n.sshKeys}');
  if (s.tags > 0) extras.add('${s.tags} ${l10n.tags}');
  if (s.snippets > 0) extras.add('${s.snippets} ${l10n.snippets}');
  if (s.knownHostsApplied) extras.add(l10n.knownHosts);
  if (s.configApplied) extras.add(l10n.appSettings);
  final head = l10n.importedSessions(s.sessions);
  if (extras.isEmpty) return head;
  return '$head, ${extras.join(', ')}';
}

/// Sanitize error messages to English — strips OS-locale text from
/// FileSystemException, SocketException, and SSH errors, replacing with
/// the English OS error code description.
///
/// For [SSHError] subtypes the English [SSHError.message] is preserved and
/// only the wrapped [SSHError.cause] is sanitized (it may contain
/// OS-locale text from SocketException / FileSystemException).
///
/// Used for logging and internal error representation (no BuildContext).
/// For user-facing localized errors, use [localizeError] instead.
String sanitizeError(Object error) {
  if (error is SFTPError) {
    return _sanitizeWithCause(error.message, error.cause);
  }
  if (error is SSHError) {
    return _sanitizeWithCause(error.message, error.cause);
  }

  final msg = redactSecrets(error.toString());
  return _sanitizeErrnoMessage(msg) ?? msg;
}

/// Sanitize an error that has a message and an optional cause.
String _sanitizeWithCause(String message, Object? cause) {
  if (cause == null) return message;
  final sanitized = sanitizeError(cause);
  if (sanitized.isNotEmpty && sanitized != message) {
    return '$message ($sanitized)';
  }
  return message;
}

/// Try to extract an errno from the message and map to English.
/// Returns null if no errno-based translation is found.
String? _sanitizeErrnoMessage(String msg) {
  // FileSystemException: "OS Error: <localized text>, errno = N"
  final errnoMatch = RegExp(r'errno\s*=\s*(\d+)').firstMatch(msg);
  if (errnoMatch != null) {
    final english = _errnoEnglish[int.parse(errnoMatch.group(1)!)];
    if (english != null) {
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
    final english = _errnoEnglish[int.parse(osErrorMatch.group(1)!)];
    if (english != null) return english;
  }

  return null;
}

/// Localize error messages using the app's current locale.
///
/// Maps errno codes, [SSHError] subtypes, and common error patterns
/// to translated strings via [S] (app_localizations).
///
/// Use this in UI code where [BuildContext] is available.
/// Falls back to [sanitizeError] for unknown error types.
String localizeError(S l10n, Object error) {
  // SFTPError: map status codes to localized messages.
  if (error is SFTPError) {
    final localized = _localizeSftpError(l10n, error);
    return _withLocalizedCause(l10n, localized, error.cause);
  }

  // SSHError subtypes: use structured data for parameterized messages.
  if (error is HostKeyError) {
    final localized = l10n.errSshHostKeyRejected(
      error.host ?? '?',
      error.port ?? 0,
    );
    return _withLocalizedCause(l10n, localized, error.cause);
  }
  if (error is AuthError) {
    final localized = _localizeAuthError(l10n, error);
    return _withLocalizedCause(l10n, localized, error.cause);
  }
  if (error is ConnectError) {
    final localized = _localizeConnectError(l10n, error);
    return _withLocalizedCause(l10n, localized, error.cause);
  }
  if (error is SSHError) {
    if (error.cause == null) return error.message;
    final cause = localizeError(l10n, error.cause!);
    if (cause.isNotEmpty && cause != error.message) {
      return l10n.errWithCause(error.message, cause);
    }
    return error.message;
  }

  // TimeoutException from Connection.waitUntilReady
  if (error is TimeoutException) {
    final seconds = error.duration?.inSeconds;
    if (seconds != null) {
      return l10n.errConnectionTimedOutSeconds(seconds);
    }
    return l10n.errConnectionTimedOut;
  }

  // OS errors: extract errno and map to localized message.
  return _localizeOsError(l10n, error);
}

String _localizeAuthError(S l10n, AuthError error) {
  final msg = error.message;
  if (msg.startsWith('Authentication failed')) {
    return l10n.errSshAuthFailed(error.user ?? '?', error.host ?? '?');
  }
  if (msg.startsWith('Authentication aborted')) {
    return l10n.errSshAuthAborted;
  }
  if (msg.contains('load SSH key file') || msg.contains('load key file')) {
    return l10n.errSshLoadKeyFileFailed;
  }
  if (msg.contains('parse PEM')) {
    return l10n.errSshParseKeyFailed;
  }
  return msg;
}

String _localizeConnectError(S l10n, ConnectError error) {
  final msg = error.message;
  final host = error.host ?? '?';
  final port = error.port ?? 0;
  if (msg.startsWith('Failed to connect to')) {
    return l10n.errSshConnectFailed(host, port);
  }
  if (msg.startsWith('Connection failed to')) {
    return l10n.errSshConnectionFailed(host, port);
  }
  if (msg == 'Connection disposed') {
    return l10n.errSshConnectionDisposed;
  }
  if (msg == 'Not connected') {
    return l10n.errSshNotConnected;
  }
  if (msg.contains('open shell')) {
    return l10n.errSshOpenShellFailed;
  }
  return msg;
}

String _localizeSftpError(S l10n, SFTPError error) {
  final cause = error.cause;
  if (cause is SftpStatusError) {
    final localized = switch (cause.code) {
      SftpStatusCode.noSuchFile => l10n.errNoSuchFileOrDirectory,
      SftpStatusCode.permissionDenied => l10n.errPermissionDenied,
      _ => error.message,
    };
    if (error.path != null) return l10n.errWithPath(localized, error.path!);
    return localized;
  }
  if (error.path != null) {
    return l10n.errWithPath(error.message, error.path!);
  }
  return error.message;
}

String _withLocalizedCause(S l10n, String localized, Object? cause) {
  if (cause == null) return localized;
  final causeStr = localizeError(l10n, cause);
  if (causeStr.isNotEmpty && causeStr != localized) {
    return l10n.errWithCause(localized, causeStr);
  }
  return localized;
}

/// Map OS error (FileSystemException, SocketException) to localized string.
String _localizeOsError(S l10n, Object error) {
  final msg = redactSecrets(error.toString());

  // FileSystemException: "OS Error: <localized text>, errno = N"
  final errnoMatch = RegExp(r'errno\s*=\s*(\d+)').firstMatch(msg);
  if (errnoMatch != null) {
    final errno = int.parse(errnoMatch.group(1)!);
    final localized = _errnoLocalized(l10n, errno);
    if (localized != null) {
      final pathMatch = RegExp(r"path\s*=\s*'([^']*)'").firstMatch(msg);
      final path = pathMatch?.group(1);
      return path != null ? l10n.errWithPath(localized, path) : localized;
    }
  }

  // SocketException / HttpException: strip localized OS error
  final osErrorMatch = RegExp(
    r'OS Error:\s*[^,]+,\s*errno\s*=\s*(\d+)',
  ).firstMatch(msg);
  if (osErrorMatch != null) {
    final errno = int.parse(osErrorMatch.group(1)!);
    final localized = _errnoLocalized(l10n, errno);
    if (localized != null) return localized;
  }

  return msg;
}

/// Map errno code to localized string, or null if unknown.
String? _errnoLocalized(S l10n, int errno) => switch (errno) {
  // POSIX / Linux
  1 => l10n.errOperationNotPermitted,
  2 => l10n.errNoSuchFileOrDirectory,
  3 => l10n.errNoSuchProcess,
  5 => l10n.errIoError,
  9 => l10n.errBadFileDescriptor,
  11 => l10n.errResourceTemporarilyUnavailable,
  12 => l10n.errOutOfMemory,
  13 => l10n.errPermissionDenied,
  17 => l10n.errFileExists,
  20 => l10n.errNotADirectory,
  21 => l10n.errIsADirectory,
  22 => l10n.errInvalidArgument,
  23 => l10n.errTooManyOpenFiles,
  28 => l10n.errNoSpaceLeftOnDevice,
  30 => l10n.errReadOnlyFileSystem,
  32 => l10n.errBrokenPipe,
  36 => l10n.errFileNameTooLong,
  39 => l10n.errDirectoryNotEmpty,
  98 => l10n.errAddressAlreadyInUse,
  99 => l10n.errCannotAssignAddress,
  100 => l10n.errNetworkIsDown,
  101 => l10n.errNetworkIsUnreachable,
  104 => l10n.errConnectionResetByPeer,
  110 => l10n.errConnectionTimedOut,
  111 => l10n.errConnectionRefused,
  112 => l10n.errHostIsDown,
  113 => l10n.errNoRouteToHost,
  // Windows Winsock (WSA*)
  10013 => l10n.errPermissionDenied,
  10048 => l10n.errAddressAlreadyInUse,
  10049 => l10n.errCannotAssignAddress,
  10050 => l10n.errNetworkIsDown,
  10051 => l10n.errNetworkIsUnreachable,
  10053 => l10n.errConnectionAborted,
  10054 => l10n.errConnectionResetByPeer,
  10056 => l10n.errAlreadyConnected,
  10057 => l10n.errNotConnected,
  10060 => l10n.errConnectionTimedOut,
  10061 => l10n.errConnectionRefused,
  10064 => l10n.errHostIsDown,
  10065 => l10n.errNoRouteToHost,
  _ => null,
};

/// English-only errno map — used by [sanitizeError] for logging.
const _errnoEnglish = <int, String>{
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
