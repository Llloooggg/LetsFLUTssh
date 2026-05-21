import 'dart:async';
import 'dart:ui' show Locale;

import 'package:intl/intl.dart' show DateFormat, Intl, NumberFormat;

import '../core/import/import_service.dart';
import '../core/sftp/errors.dart';
import '../core/ssh/errors.dart';
import '../core/update/update_service.dart'
    show InvalidReleaseSignatureException, ReleaseManifestUnavailableException;
import '../core/import/export_import.dart'
    show
        LfsArchiveTooLargeException,
        LfsArchiveTruncatedException,
        LfsDecryptionFailedException,
        LfsKnownHostsTooLargeException,
        UnsupportedLfsVersionException;
import '../l10n/app_localizations.dart';
import '../src/rust/api/format.dart' as rust_format;
import '../src/rust/api/frb_err.dart' as rust_frb_err;
import 'sanitize.dart';

/// Format byte size to a human-readable string with locale-aware
/// decimal separator. Pass [locale] from `Localizations.localeOf(context)`
/// when called from a widget; defaults to [Intl.defaultLocale] (set by
/// `main.dart` after the user's persisted choice resolves) for callers
/// without a context (background workers, log lines).
///
/// The B / KB / MB / GB ladder + decimal-place policy (1 for KB/MB,
/// 2 for GB) mirrors the Rust `lfs_core::format::format_size` so the
/// thresholds stay consistent across surfaces. The number-formatting
/// half lives Dart-side because `intl.NumberFormat` honours the
/// active locale — German / French / Russian users see `1,5 MB`,
/// not the locale-blind `1.5 MB` a Rust-side `format!("{:.1}")` emits.
String formatSize(int bytes, {Locale? locale}) {
  final abs = bytes.abs();
  if (abs < 1024) return '$bytes B';
  final tag = locale?.toLanguageTag() ?? Intl.defaultLocale;
  // `NumberFormat(pattern, locale)` preserves the trailing zero
  // count exactly (`1.0`, `3.00`); `NumberFormat.decimalPattern`
  // strips them (`1.0` → `1`) which would regress the existing
  // wire shape.
  final fmtKbMb = NumberFormat('0.0', tag);
  final fmtGb = NumberFormat('0.00', tag);
  if (abs < 1024 * 1024) {
    return '${fmtKbMb.format(bytes / 1024)} KB';
  }
  if (abs < 1024 * 1024 * 1024) {
    return '${fmtKbMb.format(bytes / (1024 * 1024))} MB';
  }
  return '${fmtGb.format(bytes / (1024.0 * 1024 * 1024))} GB';
}

/// Format DateTime to a short timestamp.
///
/// `locale: null` keeps the ISO shape `YYYY-MM-DD HH:MM` from
/// `lfs_core::format::format_timestamp_minute`. The ISO shape is
/// the contract for log-correlation surfaces (transfer history
/// tooltips that get attached to bug reports — sortable across
/// locales) and any callsite that does not have a `BuildContext`
/// in scope. Pass [locale] from `Localizations.localeOf(context)`
/// from widgets to get the locale's short numeric date +
/// 24-hour time — German `15.03.2025 09:05`, French
/// `15/03/2025 09:05`, US English `3/15/2025 09:05`.
String formatTimestamp(DateTime dt, {Locale? locale}) {
  if (locale == null) {
    return rust_format.formatTimestampMinute(
      year: dt.year,
      month: dt.month,
      day: dt.day,
      hour: dt.hour,
      minute: dt.minute,
    );
  }
  final tag = locale.toLanguageTag();
  return '${DateFormat.yMd(tag).format(dt)} ${DateFormat.Hm(tag).format(dt)}';
}

/// Format Duration to human-readable string via
/// `lfs_core::format::format_duration` — ms / s / m / h granularity.
String formatDuration(Duration d) =>
    rust_format.formatDuration(millis: d.inMilliseconds);

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
  final body = extras.isEmpty ? head : '$head, ${extras.join(', ')}';
  final notes = <String>[];
  if (s.skippedSessions > 0) {
    notes.add(l10n.importSkippedSessions(s.skippedSessions));
  }
  if (s.skippedLinks > 0) {
    notes.add(l10n.importSkippedLinks(s.skippedLinks));
  }
  if (notes.isEmpty) return body;
  return '$body — ${notes.join('; ')}';
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
    final english = _errnoEnglishOf(int.parse(errnoMatch.group(1)!));
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
    final english = _errnoEnglishOf(int.parse(osErrorMatch.group(1)!));
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
  if (error is InvalidReleaseSignatureException) {
    return l10n.errReleaseSignatureInvalid;
  }
  if (error is ReleaseManifestUnavailableException) {
    return l10n.errReleaseManifestUnavailable;
  }

  // FRB typed-envelope routing — preferred over substring matching
  // on rendered text. FRB callsites emit JSON `{kind, detail}`;
  // [_localizeFrbKind] switches on `kind` and falls through `null`
  // for plain-string errors so the typed Dart-exception / OS-error
  // branches below still handle them.
  final frb = _localizeFrbKind(l10n, error);
  if (frb != null) return frb;

  final lfs = _tryLocalizeLfsError(l10n, error);
  if (lfs != null) return lfs;

  final ssh = _tryLocalizeSshError(l10n, error);
  if (ssh != null) return ssh;

  if (error is TimeoutException) return _localizeTimeout(l10n, error);

  // Pinned FRB error keys from `lfs_core::fs::local`. These are
  // flat strings (no JSON envelope) so they bypass
  // `_localizeFrbKind` — match them here so every caller of a
  // local-fs Rust op renders the same localised toast as the
  // matching errno path.
  if (error is String) {
    if (error == 'no_such_file_or_directory') {
      return l10n.errNoSuchFileOrDirectory;
    }
    if (error == 'permission_denied') {
      return l10n.errPermissionDenied;
    }
  }

  // OS errors: extract errno and map to localized message.
  return _localizeOsError(l10n, error);
}

/// Try to parse [error] as a typed FRB envelope and route by kind.
/// Returns null when the error is not a JSON envelope (plain strings,
/// typed Dart exceptions, OS errors, etc.) so the caller keeps
/// walking the fallback chain.
///
/// The envelope parser lives Rust-side (`frb_error_from_wire`); this
/// helper pattern-matches the typed [`rust_frb_err.DbFrbErrorKind`]
/// enum returned across FRB so a future kind rename in Rust shows
/// up as a Dart compile error here rather than a silent re-route to
/// the generic bucket.
String? _localizeFrbKind(S l10n, Object error) {
  if (error is! String) return null;
  if (!error.startsWith('{')) return null;
  final wire = rust_frb_err.frbErrorFromWire(wire: error);
  switch (wire.kind) {
    case rust_frb_err.DbFrbErrorKind.authFailed:
      return l10n.errSshAuthFailed('?', '?');
    case rust_frb_err.DbFrbErrorKind.hostKeyRejected:
      return l10n.errSshHostKeyRejected('?', 0);
    case rust_frb_err.DbFrbErrorKind.timeout:
      return l10n.errConnectionTimedOut;
    case rust_frb_err.DbFrbErrorKind.generic:
    case rust_frb_err.DbFrbErrorKind.connect:
    case rust_frb_err.DbFrbErrorKind.handshake:
    case rust_frb_err.DbFrbErrorKind.authOther:
    case rust_frb_err.DbFrbErrorKind.keyParse:
    case rust_frb_err.DbFrbErrorKind.passphraseRequired:
    case rust_frb_err.DbFrbErrorKind.passphraseIncorrect:
    case rust_frb_err.DbFrbErrorKind.io:
    case rust_frb_err.DbFrbErrorKind.db:
    case rust_frb_err.DbFrbErrorKind.sftp:
    case rust_frb_err.DbFrbErrorKind.sessionUnavailable:
    case rust_frb_err.DbFrbErrorKind.recorder:
    case rust_frb_err.DbFrbErrorKind.archive:
    case rust_frb_err.DbFrbErrorKind.transport:
    case rust_frb_err.DbFrbErrorKind.vault:
    case rust_frb_err.DbFrbErrorKind.vaultCorrupt:
    case rust_frb_err.DbFrbErrorKind.vaultPlatformUnsupported:
    case rust_frb_err.DbFrbErrorKind.update:
    case rust_frb_err.DbFrbErrorKind.platform:
    case rust_frb_err.DbFrbErrorKind.crypto:
    case rust_frb_err.DbFrbErrorKind.cancelled:
    case rust_frb_err.DbFrbErrorKind.archiveFutureVersion:
    case rust_frb_err.DbFrbErrorKind.webDav:
    case rust_frb_err.DbFrbErrorKind.s3:
    case rust_frb_err.DbFrbErrorKind.fido2:
    case rust_frb_err.DbFrbErrorKind.pkcs11:
    case rust_frb_err.DbFrbErrorKind.enclave:
    case rust_frb_err.DbFrbErrorKind.hello:
    case rust_frb_err.DbFrbErrorKind.tpm:
    case rust_frb_err.DbFrbErrorKind.keystore:
    case rust_frb_err.DbFrbErrorKind.unsupported:
      // Other kinds (passphrase_required / passphrase_incorrect /
      // cancelled / sftp / db / archive / vault / ...) don't yet
      // have dedicated localized templates — fall through to the
      // generic path so the detail text still surfaces sanitized.
      return null;
  }
}

/// Localize every archive / import-time exception. Returns null when
/// [error] is not an LFS one, so the caller can fall through.
String? _tryLocalizeLfsError(S l10n, Object error) {
  if (error is LfsArchiveTooLargeException) {
    return l10n.errLfsArchiveTooLarge(
      (error.size / (1024 * 1024)).toStringAsFixed(1),
      (error.limit / (1024 * 1024)).toStringAsFixed(0),
    );
  }
  if (error is LfsKnownHostsTooLargeException) {
    return l10n.errLfsKnownHostsTooLarge(
      (error.size / (1024 * 1024)).toStringAsFixed(1),
      (error.limit / (1024 * 1024)).toStringAsFixed(0),
    );
  }
  if (error is LfsImportRolledBackException) {
    return l10n.errLfsImportRolledBack(localizeError(l10n, error.cause));
  }
  if (error is UnsupportedLfsVersionException) {
    return l10n.errLfsUnsupportedVersion(error.found, error.supported);
  }
  // Note: the QR-payload "version too new" path no longer raises a
  // typed Dart exception — the Rust dispatcher returns a typed
  // `QrImportRejected` outcome that the deeplink listener surfaces
  // through `onQrImportVersionTooNew(found, supported)` directly,
  // bypassing this generic localizer.
  if (error is LfsDecryptionFailedException) {
    return l10n.errLfsDecryptFailed;
  }
  if (error is LfsArchiveTruncatedException) {
    return l10n.errLfsArchiveTruncated;
  }
  return null;
}

/// Localize SFTP / SSH transport errors. Returns null when [error] is
/// not SSH-related.
String? _tryLocalizeSshError(S l10n, Object error) {
  if (error is SFTPError) {
    final localized = _localizeSftpError(l10n, error);
    return _withLocalizedCause(l10n, localized, error.cause);
  }
  if (error is HostKeyError) {
    final localized = l10n.errSshHostKeyRejected(
      error.host ?? '?',
      error.port ?? 0,
    );
    return _withLocalizedCause(l10n, localized, error.cause);
  }
  if (error is AuthError) {
    return _withLocalizedCause(
      l10n,
      _localizeAuthError(l10n, error),
      error.cause,
    );
  }
  if (error is ConnectError) {
    return _withLocalizedCause(
      l10n,
      _localizeConnectError(l10n, error),
      error.cause,
    );
  }
  if (error is SSHError) {
    if (error.cause == null) return error.message;
    final cause = localizeError(l10n, error.cause!);
    if (cause.isNotEmpty && cause != error.message) {
      return l10n.errWithCause(error.message, cause);
    }
    return error.message;
  }
  return null;
}

String _localizeTimeout(S l10n, TimeoutException error) {
  final seconds = error.duration?.inSeconds;
  return seconds != null
      ? l10n.errConnectionTimedOutSeconds(seconds)
      : l10n.errConnectionTimedOut;
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
  // Unknown auth-error variant: SSH stacks routinely embed file
  // paths and key fingerprints in their messages. Strip secrets
  // before returning so we never leak them to the UI / log.
  return redactSecrets(msg);
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
  return redactSecrets(msg);
}

String _localizeSftpError(S l10n, SFTPError error) {
  // SFTP status surfaces as a free-form string through russh-sftp /
  // FRB. Match the common cases by substring (case-insensitive) to
  // pick a localized message, fall back to the raw message otherwise.
  final causeMsg = error.cause?.toString().toLowerCase() ?? '';
  String localized;
  if (causeMsg.contains('no such file') ||
      causeMsg.contains('does not exist') ||
      causeMsg.contains('not found')) {
    localized = l10n.errNoSuchFileOrDirectory;
  } else if (causeMsg.contains('permission denied') ||
      causeMsg.contains('access denied')) {
    localized = l10n.errPermissionDenied;
  } else {
    localized = error.message;
  }
  if (error.path != null) return l10n.errWithPath(localized, error.path!);
  return localized;
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

/// errno → (localized accessor, English fallback) — single source
/// of truth for the two errno-keyed lookups (sanitizer logging
/// path + UI localizer). **Don't fork into two maps** — a new
/// errno would have to land in both, and a missed addition shows
/// up as the localized UI string drifting from the English log
/// line for that errno only.
class _ErrnoEntry {
  const _ErrnoEntry(this.localized, this.english);
  final String Function(S) localized;
  final String english;
}

final Map<int, _ErrnoEntry> _errnoTable = <int, _ErrnoEntry>{
  // POSIX / Linux
  1: _ErrnoEntry((s) => s.errOperationNotPermitted, 'Operation not permitted'),
  2: _ErrnoEntry(
    (s) => s.errNoSuchFileOrDirectory,
    'No such file or directory',
  ),
  3: _ErrnoEntry((s) => s.errNoSuchProcess, 'No such process'),
  5: _ErrnoEntry((s) => s.errIoError, 'I/O error'),
  9: _ErrnoEntry((s) => s.errBadFileDescriptor, 'Bad file descriptor'),
  11: _ErrnoEntry(
    (s) => s.errResourceTemporarilyUnavailable,
    'Resource temporarily unavailable',
  ),
  12: _ErrnoEntry((s) => s.errOutOfMemory, 'Out of memory'),
  13: _ErrnoEntry((s) => s.errPermissionDenied, 'Permission denied'),
  17: _ErrnoEntry((s) => s.errFileExists, 'File exists'),
  20: _ErrnoEntry((s) => s.errNotADirectory, 'Not a directory'),
  21: _ErrnoEntry((s) => s.errIsADirectory, 'Is a directory'),
  22: _ErrnoEntry((s) => s.errInvalidArgument, 'Invalid argument'),
  23: _ErrnoEntry((s) => s.errTooManyOpenFiles, 'Too many open files'),
  28: _ErrnoEntry((s) => s.errNoSpaceLeftOnDevice, 'No space left on device'),
  30: _ErrnoEntry((s) => s.errReadOnlyFileSystem, 'Read-only file system'),
  32: _ErrnoEntry((s) => s.errBrokenPipe, 'Broken pipe'),
  36: _ErrnoEntry((s) => s.errFileNameTooLong, 'File name too long'),
  39: _ErrnoEntry((s) => s.errDirectoryNotEmpty, 'Directory not empty'),
  98: _ErrnoEntry((s) => s.errAddressAlreadyInUse, 'Address already in use'),
  99: _ErrnoEntry(
    (s) => s.errCannotAssignAddress,
    'Cannot assign requested address',
  ),
  100: _ErrnoEntry((s) => s.errNetworkIsDown, 'Network is down'),
  101: _ErrnoEntry((s) => s.errNetworkIsUnreachable, 'Network is unreachable'),
  104: _ErrnoEntry(
    (s) => s.errConnectionResetByPeer,
    'Connection reset by peer',
  ),
  110: _ErrnoEntry((s) => s.errConnectionTimedOut, 'Connection timed out'),
  111: _ErrnoEntry((s) => s.errConnectionRefused, 'Connection refused'),
  112: _ErrnoEntry((s) => s.errHostIsDown, 'Host is down'),
  113: _ErrnoEntry((s) => s.errNoRouteToHost, 'No route to host'),
  // Windows Winsock (WSA*)
  10013: _ErrnoEntry((s) => s.errPermissionDenied, 'Permission denied'),
  10048: _ErrnoEntry((s) => s.errAddressAlreadyInUse, 'Address already in use'),
  10049: _ErrnoEntry(
    (s) => s.errCannotAssignAddress,
    'Cannot assign requested address',
  ),
  10050: _ErrnoEntry((s) => s.errNetworkIsDown, 'Network is down'),
  10051: _ErrnoEntry(
    (s) => s.errNetworkIsUnreachable,
    'Network is unreachable',
  ),
  10053: _ErrnoEntry((s) => s.errConnectionAborted, 'Connection aborted'),
  10054: _ErrnoEntry(
    (s) => s.errConnectionResetByPeer,
    'Connection reset by peer',
  ),
  10056: _ErrnoEntry((s) => s.errAlreadyConnected, 'Already connected'),
  10057: _ErrnoEntry((s) => s.errNotConnected, 'Not connected'),
  10060: _ErrnoEntry((s) => s.errConnectionTimedOut, 'Connection timed out'),
  10061: _ErrnoEntry((s) => s.errConnectionRefused, 'Connection refused'),
  10064: _ErrnoEntry((s) => s.errHostIsDown, 'Host is down'),
  10065: _ErrnoEntry((s) => s.errNoRouteToHost, 'No route to host'),
};

/// Map errno code to localized string, or null if unknown.
String? _errnoLocalized(S l10n, int errno) =>
    _errnoTable[errno]?.localized(l10n);

/// English-only errno fallback — used by [sanitizeError] for logging
/// where no [S] is in scope.
String? _errnoEnglishOf(int errno) => _errnoTable[errno]?.english;
