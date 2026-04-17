// Utilities for sanitizing sensitive data before logging or surfacing in
// user-facing error toasts.
//
// Prevents accidental leakage of:
// - SSH private keys in PEM format and long base64 key blobs
// - IP addresses (IPv4)
// - Usernames in SSH context (user@host)
// - Port numbers in connection strings
// - File paths containing usernames
//
// Sqlite/drift exceptions are the usual offender: their `toString()` embeds
// the failing `INSERT` statement along with every bound parameter, which can
// include a PEM-encoded private key pulled from a session row. Anything that
// might put such a message in front of the user (toasts, error dialogs) must
// run it through [redactSecrets] first.

/// Strip PEM private keys and long base64 blobs.
///
/// Called before any user-visible error surfaces (toasts, dialogs) and as
/// the first step of [AppLogger.sanitize] for log files. Catches the common
/// drift/sqlite leak where a failed `INSERT` dumps its bound parameters —
/// including `-----BEGIN OPENSSH PRIVATE KEY-----...` — into the exception
/// message.
String redactSecrets(String input) {
  // Match any PEM-style block (private key, encrypted private key, future
  // proprietary formats with hyphens in the type name like "OPENSSH PRIVATE
  // KEY"). The type-name class is restricted to non-newline characters
  // rather than non-hyphen so types like "OPENSSH-PRIVATE-KEY" or
  // "ENCRYPTED PRIVATE KEY" still match.
  final pemPattern = RegExp(
    r'-----BEGIN[^\n]*?(PRIVATE KEY|RSA PRIVATE KEY|EC PRIVATE KEY|OPENSSH PRIVATE KEY)[^\n]*?-----'
    r'[\s\S]*?'
    r'-----END[^\n]*?(PRIVATE KEY|RSA PRIVATE KEY|EC PRIVATE KEY|OPENSSH PRIVATE KEY)[^\n]*?-----',
    multiLine: true,
  );
  var out = input.replaceAll(pemPattern, '[REDACTED PRIVATE KEY]');
  out = out.replaceAll(RegExp(r'[A-Za-z0-9+/=]{200,}'), '[REDACTED BASE64]');
  return out;
}

/// Remove sensitive data from error messages before logging.
String sanitizeErrorMessage(String message) {
  // Redact IPv4 addresses FIRST (before user@host pattern matching)
  message = message.replaceAllMapped(
    RegExp(r'\b(\d{1,3}\.){3}\d{1,3}\b'),
    (_) => '<ip>',
  );

  // Redact user@host patterns (e.g., "admin@example.com" → "<user>@example.com")
  // Also handles "admin@<ip>" after IP redaction
  message = message.replaceAllMapped(
    RegExp(r'([a-zA-Z0-9_.-]+)@([a-zA-Z0-9_.]+\.[a-zA-Z]{2,}|<ip>)'),
    (m) => '<user>@${m.group(2) ?? '<host>'}',
  );

  // Redact port numbers in host:port patterns
  message = message.replaceAllMapped(
    RegExp(r'(<ip>|[a-zA-Z0-9_.-]+):(\d{2,5})\b'),
    (m) => '${m.group(1) ?? '<host>'}:<port>',
  );

  // Redact Windows file paths with usernames (C:\Users\Name\...)
  message = message.replaceAllMapped(
    RegExp(r'[A-Z]:\\Users\\[^\\]+\\'),
    (_) => '<path>\\',
  );

  // Redact Unix/macOS file paths with usernames (/Users/Name/..., /home/name/...)
  message = message.replaceAllMapped(
    RegExp(r'/(Users|home)/[^/]+/'),
    (_) => '/<user>/',
  );

  return message;
}
