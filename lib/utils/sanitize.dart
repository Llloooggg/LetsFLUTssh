// Utilities for sanitizing sensitive data before logging.
//
// Prevents accidental logging of:
// - IP addresses (IPv4)
// - Usernames in SSH context (user@host)
// - Port numbers in connection strings
// - File paths containing usernames

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
