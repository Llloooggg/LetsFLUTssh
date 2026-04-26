// Utilities for sanitizing sensitive data before logging or surfacing in
// user-facing error toasts.
//
// Routes through `lfs_core::log_sanitize` over the synchronous FRB
// endpoints — the canonical implementation lives Rust-side. The Dart
// fallback below mirrors the same regex pipeline; production never
// reaches it because the FRB native lib is loaded at app start, but
// flutter_test does not load it and many tests (format_test, widget
// tests, AppLogger) call `sanitizeError` transitively. The fallback
// keeps that test surface working without a per-suite RustLib.init
// bootstrap.

import '../src/rust/api/log_sanitize.dart' as rust_san;

/// Strip PEM private keys and long base64 blobs.
String redactSecrets(String input) {
  try {
    return rust_san.redactSecrets(input: input);
  } catch (_) {
    return _redactSecretsDart(input);
  }
}

/// Remove sensitive data (IPv4 / IPv6 addresses, user@host, host:port,
/// home-dir paths, …) from error messages.
String sanitizeErrorMessage(String message) {
  try {
    return rust_san.sanitizeErrorMessage(input: message);
  } catch (_) {
    return _sanitizeErrorMessageDart(message);
  }
}

String _redactSecretsDart(String input) {
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

String _sanitizeErrorMessageDart(String message) {
  // IPv6 literals FIRST — broader shape than IPv4 and would otherwise
  // get partially chewed by later rules.
  message = message.replaceAllMapped(
    RegExp(
      r'\[?(?:'
      r'(?:[0-9A-Fa-f]{1,4}:){7}[0-9A-Fa-f]{1,4}'
      r'|[0-9A-Fa-f]{1,4}:(?::[0-9A-Fa-f]{1,4}){1,6}'
      r'|(?:[0-9A-Fa-f]{1,4}:){1,2}(?::[0-9A-Fa-f]{1,4}){1,5}'
      r'|(?:[0-9A-Fa-f]{1,4}:){1,3}(?::[0-9A-Fa-f]{1,4}){1,4}'
      r'|(?:[0-9A-Fa-f]{1,4}:){1,4}(?::[0-9A-Fa-f]{1,4}){1,3}'
      r'|(?:[0-9A-Fa-f]{1,4}:){1,5}(?::[0-9A-Fa-f]{1,4}){1,2}'
      r'|(?:[0-9A-Fa-f]{1,4}:){1,6}:[0-9A-Fa-f]{1,4}'
      r'|(?:[0-9A-Fa-f]{1,4}:){1,7}:'
      r'|:(?::[0-9A-Fa-f]{1,4}){1,7}'
      r'|::'
      r')\]?',
    ),
    (_) => '<ip>',
  );

  // Redact IPv4 addresses (before user@host pattern matching).
  message = message.replaceAllMapped(
    RegExp(r'\b(\d{1,3}\.){3}\d{1,3}\b'),
    (_) => '<ip>',
  );

  // Redact user@host patterns (e.g. "admin@example.com" → "<user>@example.com").
  message = message.replaceAllMapped(
    RegExp(r'([a-zA-Z0-9_.-]+)@([a-zA-Z0-9_.]+\.[a-zA-Z]{2,}|<ip>)'),
    (m) => '<user>@${m.group(2) ?? '<host>'}',
  );

  // Defence-in-depth: also catch "as <user>" / "user=<user>" shapes
  // from SSH / russh error messages that name the authenticating
  // principal without wrapping it in user@host form.
  message = message.replaceAllMapped(
    RegExp(r'\bas\s+([a-zA-Z0-9_.-]+)'),
    (m) => 'as <user>',
  );
  message = message.replaceAllMapped(
    RegExp(r'\b(user|login)=([a-zA-Z0-9_.-]+)'),
    (m) => '${m.group(1)}=<user>',
  );

  // Redact port numbers in host:port patterns.
  message = message.replaceAllMapped(
    RegExp(r'(<ip>|[a-zA-Z0-9_.-]+):(\d{2,5})\b'),
    (m) => '${m.group(1) ?? '<host>'}:<port>',
  );

  // Redact Windows file paths with usernames.
  message = message.replaceAllMapped(
    RegExp(r'[A-Z]:\\Users\\[^\\\r\n]+'),
    (_) => '<path>',
  );

  // Redact Unix/macOS file paths with usernames.
  message = message.replaceAllMapped(
    RegExp(r'/(?:Users|home)/[^/\s]+'),
    (_) => '/<user>',
  );

  return message;
}
