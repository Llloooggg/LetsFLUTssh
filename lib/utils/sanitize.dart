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

// 2-pass sanitize shape — earlier shape ran 8 sequential
// `replaceAll` passes, each scanning the full input. The 2-pass
// shape collapses them to a bare-IP pass + a "everything else"
// combined pass. ~4× reduction. A single-pass combined regex was
// tried and rejected because Rust's `regex` (NFA, no backtracking)
// and Dart's `RegExp` (PCRE-style backtracking) diverge on inputs
// like `fe80::abcd:1234:5678` where the host:port branch wants a
// shorter IPv6 prefix to leave `:5678` for the port slot — Dart
// backtracks and finds it; Rust does not, falling through to the
// bare-IP catch-all and consuming the full IPv6. Two passes
// preserve the per-pass identity between engines so the cross-
// impl drift gate (`test/utils/sanitize_drift_test.dart`) stays
// green.

const String _ipv6Branch =
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
    r')\]?';

const String _ipv4Branch = r'(?:\d{1,3}\.){3}\d{1,3}';

/// Pass 1: bare IPv6 + IPv4 → `<ip>`.
final RegExp _ipRe = RegExp(
  '$_ipv6Branch'
  r'|\b'
  '$_ipv4Branch'
  r'\b',
);

/// Pass 2: combined "everything else" — user@host, as_user, user=,
/// host:port, Windows path, Unix path. Host slot after pass 1 is
/// either a literal `<ip>` placeholder or a domain name.
///
/// `userhost` carries an optional `:port` suffix so the closure
/// can render `<user>@host:<port>` in one shot — alternation can't
/// compose user@host's match with a separate host:port match
/// because each `replaceAllMapped` callback span is consumed and
/// the engine continues from after the match.
final RegExp _restRe = RegExp(
  r'(?<userhost>[a-zA-Z0-9_.\-]+@(?<userhost_host>[a-zA-Z0-9_.]+\.[a-zA-Z]{2,}|<ip>)(?::(?<userhost_port>\d{2,5}))?)'
  r'|(?<asuser>\bas\s+[a-zA-Z0-9_.\-]+)'
  r'|(?<usereq>\b(?<usereq_key>user|login)=[a-zA-Z0-9_.\-]+)'
  r'|(?<hostport>(?<hostport_host><ip>|[a-zA-Z0-9_.\-]+):(?:\d{2,5}))\b'
  r'|(?<winpath>[A-Z]:\\Users\\[^\\\r\n]+)'
  r'|(?<unixpath>/(?:Users|home)/[^/\s]+)',
);

/// Remove sensitive data from error messages before logging or
/// surfacing in toasts. Two-pass shape — IPs first (turn into
/// `<ip>` placeholder), then everything else in one combined
/// regex that dispatches in the replace closure based on which
/// named capture matched.
String sanitizeErrorMessage(String message) {
  final afterIp = message.replaceAll(_ipRe, '<ip>');
  return afterIp.replaceAllMapped(_restRe, (rawMatch) {
    final m = rawMatch as RegExpMatch;
    if (m.namedGroup('userhost') != null) {
      final host = m.namedGroup('userhost_host') ?? '<host>';
      if (m.namedGroup('userhost_port') != null) {
        return '<user>@$host:<port>';
      }
      return '<user>@$host';
    }
    if (m.namedGroup('asuser') != null) {
      return 'as <user>';
    }
    if (m.namedGroup('usereq') != null) {
      final key = m.namedGroup('usereq_key') ?? 'user';
      return '$key=<user>';
    }
    if (m.namedGroup('hostport') != null) {
      final host = m.namedGroup('hostport_host') ?? '<host>';
      return '$host:<port>';
    }
    if (m.namedGroup('winpath') != null) {
      return '<path>';
    }
    if (m.namedGroup('unixpath') != null) {
      return '/<user>';
    }
    return m.group(0) ?? '';
  });
}
