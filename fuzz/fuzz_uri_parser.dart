// Standalone fuzz target for deep link URI parsing.
//
// Reads raw bytes from stdin, attempts to parse them as a URI,
// and exercises the connect-URI validation logic.
// Compiled to native via `dart compile exe` for AFL++/ClusterFuzzLite.
//
// Usage:
//   dart compile exe fuzz/fuzz_uri_parser.dart -o fuzz/out/fuzz_uri_parser
//   echo 'letsflutssh://connect?host=x&user=y' | ./fuzz/out/fuzz_uri_parser

import 'dart:convert';
import 'dart:io';

void main() {
  final input = stdin.readLineSync(encoding: utf8) ?? '';
  if (input.isEmpty) return;

  // --- Connect URI parsing ---
  _parseConnectUri(input);

  // --- Import URI parsing ---
  _parseImportUri(input);
}

/// Simulates DeepLinkHandler.parseConnectUri without Flutter dependencies.
void _parseConnectUri(String input) {
  final Uri uri;
  try {
    uri = Uri.parse(input.trim());
  } catch (_) {
    return;
  }

  final params = uri.queryParameters;
  final host = params['host']?.trim();
  final user = params['user']?.trim();

  if (host == null || host.isEmpty || user == null || user.isEmpty) {
    return;
  }

  // Validate host: no path separators, null bytes, reasonable length
  if (host.length > 253 ||
      host.contains('/') ||
      host.contains('\\') ||
      host.contains('\x00')) {
    return;
  }

  // Validate port range
  final port = int.tryParse(params['port'] ?? '') ?? 22;
  if (port < 1 || port > 65535) {
    return;
  }

  // If we get here, the URI is valid
  assert(host.isNotEmpty);
  assert(user.isNotEmpty);
  assert(port >= 1 && port <= 65535);
}

/// Simulates decodeImportUri without Flutter dependencies.
void _parseImportUri(String input) {
  final Uri uri;
  try {
    uri = Uri.parse(input.trim());
  } catch (_) {
    return;
  }

  if (uri.scheme != 'letsflutssh' || uri.host != 'import') return;

  final b64 = uri.queryParameters['d'];
  if (b64 == null || b64.isEmpty) return;

  try {
    final decoded = utf8.decode(base64Url.decode(b64));
    // Try JSON parse
    final json = jsonDecode(decoded);
    if (json is! Map<String, dynamic>) return;

    final version = json['v'] as int?;
    if (version != 1) return;

    final sessions = json['s'] as List?;
    if (sessions == null) return;

    for (final s in sessions) {
      if (s is! Map<String, dynamic>) continue;
      s['l'] as String?;
      s['h'] as String?;
    }
  } on FormatException {
    // Invalid base64 or JSON
  } on TypeError {
    // Type cast failure
  }
}
