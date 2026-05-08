// Utilities for sanitizing sensitive data before logging or surfacing in
// user-facing error toasts.
//
// Pure Dart on purpose. The redaction pipeline used to route through
// `lfs_core::log_sanitize` over FRB, but the cold-start path needs
// these helpers callable BEFORE `RustLib.init` completes — the global
// runZonedGuarded / FlutterError / PlatformDispatcher error handlers
// fire whenever code anywhere in the app throws, including the brief
// window between `WidgetsFlutterBinding.ensureInitialized` and the
// post-frame `_initRustCoreOrFatal`. A FRB-bound sanitiser would
// crash-loop the zone handler in that window (every error → log →
// sanitize → "FRB not initialised" → caught by zone → log again).
//
// dart:core RegExp covers every shape the Rust implementation
// covered, byte-for-byte (the Rust crate was migrated FROM these
// regexes). Match order mirrors the Rust pipeline:
// IPv6 → IPv4 → user@host → as-user / user= / login= → host:port →
// Windows path → Unix path. Each step rewrites the buffer the next
// step scans, so e.g. host:port redaction operates after the IP
// rewrites have already turned bare IPs into `<ip>`.

// PEM-style block — private key, encrypted private key, OpenSSH
// proprietary format. Type-name class is non-newline so multi-word
// types ("ENCRYPTED PRIVATE KEY", "OPENSSH PRIVATE KEY") still match.
// `dotAll: true` makes `.` cross newlines (Rust's `(?s)`).
final RegExp _pemRe = RegExp(
  r'-----BEGIN[^\n]*?(PRIVATE KEY|RSA PRIVATE KEY|EC PRIVATE KEY|OPENSSH PRIVATE KEY)[^\n]*?-----.*?-----END[^\n]*?(PRIVATE KEY|RSA PRIVATE KEY|EC PRIVATE KEY|OPENSSH PRIVATE KEY)[^\n]*?-----',
  dotAll: true,
);

// 200+ char base64-alphabet runs catch the common drift / sqlite
// leak where a failed INSERT dumps its bound parameters (a base64
// blob) into the exception message.
final RegExp _longB64Re = RegExp(r'[A-Za-z0-9+/=]{200,}');

/// Strip PEM private keys and long base64 blobs.
String redactSecrets(String input) {
  return input
      .replaceAll(_pemRe, '[REDACTED PRIVATE KEY]')
      .replaceAll(_longB64Re, '[REDACTED BASE64]');
}

/// Bidi / Trojan-Source control characters. Same set CVE-2021-42574
/// flagged: hostile filename / hostname / log payload can embed
/// these to flip rendered text visually relative to its underlying
/// bytes — e.g. an embedded U+202E (RIGHT-TO-LEFT OVERRIDE) flips
/// the suffix of a hostname so the rendered version no longer
/// matches the underlying ASCII the connect resolver sees.
/// `redactBidi` strips them from any string the UI renders verbatim
/// (TOFU host display, file row, log viewer).
const _bidiCodepoints = <int>[
  0x200E, // LEFT-TO-RIGHT MARK
  0x200F, // RIGHT-TO-LEFT MARK
  0x202A, // LEFT-TO-RIGHT EMBEDDING
  0x202B, // RIGHT-TO-LEFT EMBEDDING
  0x202C, // POP DIRECTIONAL FORMATTING
  0x202D, // LEFT-TO-RIGHT OVERRIDE
  0x202E, // RIGHT-TO-LEFT OVERRIDE
  0x2066, // LEFT-TO-RIGHT ISOLATE
  0x2067, // RIGHT-TO-LEFT ISOLATE
  0x2068, // FIRST STRONG ISOLATE
  0x2069, // POP DIRECTIONAL ISOLATE
];

/// Drop bidi-override characters from [input]. Returns the input
/// unchanged when no offending codepoint is present (fast path —
/// most strings have none). When at least one is found, the
/// codepoint is replaced with `\u{HHHH}` so the rendered hex still
/// signals "this string contained an override" without flipping
/// the visual order.
String redactBidi(String input) {
  if (input.isEmpty) return input;
  // Fast-path scan over codepoints.
  if (!input.runes.any(_bidiCodepoints.contains)) return input;
  final out = StringBuffer();
  for (final cp in input.runes) {
    if (_bidiCodepoints.contains(cp)) {
      out.write('\\u{${cp.toRadixString(16).padLeft(4, '0')}}');
    } else {
      out.writeCharCode(cp);
    }
  }
  return out.toString();
}

/// True when [host] contains any codepoint outside ASCII. Hosts
/// that fail this are IDN candidates: a TOFU prompt that displays
/// the rendered Unicode form alone is vulnerable to a homograph
/// attack (a Cyrillic 'а' rendering identical to Latin 'a' in the
/// dialog while the connect resolver saw the IDN-encoded
/// punycode). Caller layers a "non-ASCII hostname — verify by eye"
/// hint on top of the trust prompt.
bool hostnameHasNonAscii(String host) {
  if (host.isEmpty) return false;
  for (final cp in host.runes) {
    if (cp > 0x7F) return true;
  }
  return false;
}

/// True when [text] looks like it carries secret material — a PEM
/// private-key block or a long base64 run (≥ 200 chars). Used by
/// the terminal clipboard auto-wipe + log redactor to agree on
/// what counts as "do not let this leak". Fast path — single
/// substring scan + one regex match per call.
bool looksSensitive(String text) {
  if (text.contains('-----BEGIN') && text.contains('PRIVATE KEY')) {
    return true;
  }
  return _longB64Re.hasMatch(text);
}

// IPv6 literals — full + every compression shape, including
// link-local / loopback / unspecified. Optionally bracketed so
// the trailing host:port rule can redact the port cleanly.
// Branches ordered most-specific-first because Dart's `RegExp`
// (like Rust's `regex`) picks the first match, not the longest.
final RegExp _ipv6Re = RegExp(
  r'\[?(?:'
  // Full 8-group: 1:2:3:4:5:6:7:8
  r'(?:[0-9A-Fa-f]{1,4}:){7}[0-9A-Fa-f]{1,4}'
  // 1 leading group, 1..6 trailing groups after ::
  r'|[0-9A-Fa-f]{1,4}:(?::[0-9A-Fa-f]{1,4}){1,6}'
  r'|(?:[0-9A-Fa-f]{1,4}:){1,2}(?::[0-9A-Fa-f]{1,4}){1,5}'
  r'|(?:[0-9A-Fa-f]{1,4}:){1,3}(?::[0-9A-Fa-f]{1,4}){1,4}'
  r'|(?:[0-9A-Fa-f]{1,4}:){1,4}(?::[0-9A-Fa-f]{1,4}){1,3}'
  r'|(?:[0-9A-Fa-f]{1,4}:){1,5}(?::[0-9A-Fa-f]{1,4}){1,2}'
  // 1..6 leading + exactly 1 trailing — `2001:db8::1`
  r'|(?:[0-9A-Fa-f]{1,4}:){1,6}:[0-9A-Fa-f]{1,4}'
  // Pure leading-then-:: (`1::`, `1:2::`)
  r'|(?:[0-9A-Fa-f]{1,4}:){1,7}:'
  // Pure trailing-after-:: (`::8`, `::1:2`)
  r'|:(?::[0-9A-Fa-f]{1,4}){1,7}'
  r'|::'
  r')\]?',
);

final RegExp _ipv4Re = RegExp(r'\b(?:\d{1,3}\.){3}\d{1,3}\b');

final RegExp _userAtHostRe = RegExp(
  r'([a-zA-Z0-9_.\-]+)@([a-zA-Z0-9_.]+\.[a-zA-Z]{2,}|<ip>)',
);

final RegExp _asUserRe = RegExp(r'\bas\s+([a-zA-Z0-9_.\-]+)');

final RegExp _userEqRe = RegExp(r'\b(user|login)=([a-zA-Z0-9_.\-]+)');

final RegExp _hostPortRe = RegExp(r'(<ip>|[a-zA-Z0-9_.\-]+):(\d{2,5})\b');

final RegExp _windowsPathRe = RegExp(r'[A-Z]:\\Users\\[^\\\r\n]+');

final RegExp _unixPathRe = RegExp(r'/(?:Users|home)/[^/\s]+');

/// Remove sensitive data from error messages before logging or
/// surfacing in toasts. See file-level comment for the pipeline.
String sanitizeErrorMessage(String message) {
  return message
      .replaceAll(_ipv6Re, '<ip>')
      .replaceAll(_ipv4Re, '<ip>')
      .replaceAllMapped(_userAtHostRe, (m) => '<user>@${m.group(2)}')
      .replaceAll(_asUserRe, 'as <user>')
      .replaceAllMapped(_userEqRe, (m) => '${m.group(1)}=<user>')
      .replaceAllMapped(_hostPortRe, (m) => '${m.group(1)}:<port>')
      .replaceAll(_windowsPathRe, '<path>')
      .replaceAll(_unixPathRe, '/<user>');
}
