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
  // IPv6 literals FIRST — broader shape than IPv4 and would otherwise
  // get partially chewed by later rules. Covers:
  //   * full 8-group form `2001:0db8:85a3:0000:0000:8a2e:0370:7334`
  //   * compressed forms with `::` (leading, trailing, or middle)
  //   * link-local `fe80::1`, loopback `::1`, unspecified `::`
  //   * bracketed `[2001:db8::1]` shape used in URLs / SSH error
  //     messages — optional `[` + `]` are eaten in the same match so
  //     the follow-up `<ip>:<port>` rule below can redact the port
  //     cleanly (bare `<ip>]` would not match that rule).
  //
  // Dart RegExp alternation picks the **first** matching branch, not
  // the longest. Arrange branches by specificity — the most trailing
  // hex groups first so `2001:db8::1` is consumed whole rather than
  // stopping at `2001:db8::` and leaving `1` behind.
  message = message.replaceAllMapped(
    RegExp(
      r'\[?(?:'
      // Full 8-group (no compression): 1:2:3:4:5:6:7:8
      r'(?:[0-9A-Fa-f]{1,4}:){7}[0-9A-Fa-f]{1,4}'
      // 1 leading group, 1..6 trailing groups after ::
      r'|[0-9A-Fa-f]{1,4}:(?::[0-9A-Fa-f]{1,4}){1,6}'
      // 1..2 leading, 5 trailing
      r'|(?:[0-9A-Fa-f]{1,4}:){1,2}(?::[0-9A-Fa-f]{1,4}){1,5}'
      // 1..3 leading, 4 trailing
      r'|(?:[0-9A-Fa-f]{1,4}:){1,3}(?::[0-9A-Fa-f]{1,4}){1,4}'
      // 1..4 leading, 3 trailing
      r'|(?:[0-9A-Fa-f]{1,4}:){1,4}(?::[0-9A-Fa-f]{1,4}){1,3}'
      // 1..5 leading, 2 trailing
      r'|(?:[0-9A-Fa-f]{1,4}:){1,5}(?::[0-9A-Fa-f]{1,4}){1,2}'
      // 1..6 leading, exactly 1 trailing — catches `2001:db8::1`
      r'|(?:[0-9A-Fa-f]{1,4}:){1,6}:[0-9A-Fa-f]{1,4}'
      // Pure leading-then-:: (no trailing groups) — `1::`, `1:2::`
      r'|(?:[0-9A-Fa-f]{1,4}:){1,7}:'
      // Pure trailing-after-:: — `::8`, `::1:2`, plus bare `::`
      r'|:(?::[0-9A-Fa-f]{1,4}){1,7}'
      r'|::'
      r')\]?',
    ),
    (_) => '<ip>',
  );

  // Redact IPv4 addresses (before user@host pattern matching)
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

  // Defence-in-depth: also catch "as <user>" / "user=<user>" shapes
  // from SSH / dartssh2 error messages that name the authenticating
  // principal without wrapping it in user@host form. Without this the
  // username survives every other redaction, which is exactly the leak
  // the review flagged in `Connecting to ... as burzuf`.
  message = message.replaceAllMapped(
    RegExp(r'\b(as|user=|login=)\s*([a-zA-Z0-9_.-]+)'),
    (m) => '${m.group(1)} <user>',
  );

  // Redact port numbers in host:port patterns
  message = message.replaceAllMapped(
    RegExp(r'(<ip>|[a-zA-Z0-9_.-]+):(\d{2,5})\b'),
    (m) => '${m.group(1) ?? '<host>'}:<port>',
  );

  // Redact Windows file paths with usernames (C:\Users\Name or
  // C:\Users\Name\rest). The username segment stops at the next backslash
  // or newline, so trailing-slash-less paths (log lines ending at the
  // home dir itself, e.g. "Initial dir: C:\Users\bob") are also caught.
  message = message.replaceAllMapped(
    RegExp(r'[A-Z]:\\Users\\[^\\\r\n]+'),
    (_) => '<path>',
  );

  // Redact Unix/macOS file paths with usernames (/Users/Name,
  // /home/name, and any extension path). Same rationale: match the
  // username segment only, so a bare home-dir path at end-of-line is
  // still redacted without needing a trailing slash.
  message = message.replaceAllMapped(
    RegExp(r'/(?:Users|home)/[^/\s]+'),
    (_) => '/<user>',
  );

  return message;
}
