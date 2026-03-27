import 'dart:convert';

import 'session.dart';
import '../ssh/ssh_config.dart';

/// Maximum payload size in bytes (before deep link wrapping).
///
/// QR version 40 with error correction L holds 2953 bytes in binary mode.
/// The deep link wrapper `letsflutssh://import?d=` adds ~25 bytes,
/// plus base64 encoding inflates by ~33%. Conservative limit.
const qrMaxPayloadBytes = 2000;

/// Encode sessions and empty groups into a compact JSON string for QR codes.
///
/// Format: `{"v":1,"s":[{"l":"label","g":"group","h":"host","p":22,"u":"user","a":"password"}],"eg":["Group1"]}`
/// Short keys minimize payload size.
/// No credentials are included — only connection metadata.
String encodeSessionsForQr(List<Session> sessions, {Set<String> emptyGroups = const {}}) {
  final payload = <String, dynamic>{
    'v': 1,
    's': sessions.map((s) => _encodeSession(s)).toList(),
    if (emptyGroups.isNotEmpty)
      'eg': emptyGroups.toList(),
  };
  return jsonEncode(payload);
}

/// Decode sessions and empty groups from a QR payload string.
///
/// Returns null if the payload is invalid or has an unsupported version.
QrImportData? decodeSessionsFromQr(String payload) {
  try {
    final json = jsonDecode(payload) as Map<String, dynamic>;
    final version = json['v'] as int?;
    if (version != 1) return null;

    final sessionList = json['s'] as List?;
    if (sessionList == null) return null;

    final sessions = sessionList
        .cast<Map<String, dynamic>>()
        .map(_decodeSession)
        .toList();

    final emptyGroups = (json['eg'] as List?)
        ?.cast<String>()
        .toSet() ?? <String>{};

    return QrImportData(sessions: sessions, emptyGroups: emptyGroups);
  } catch (_) {
    return null;
  }
}

/// Calculate the byte size of the encoded payload for the given sessions.
int calculateQrPayloadSize(List<Session> sessions, {Set<String> emptyGroups = const {}}) {
  return utf8.encode(encodeSessionsForQr(sessions, emptyGroups: emptyGroups)).length;
}

/// Wrap encoded sessions into a deep link URI for QR code.
///
/// Format: `letsflutssh://import?d=BASE64URL`
/// The phone's OS camera scans the QR → recognizes the custom scheme →
/// opens the app → deep link handler imports sessions.
String wrapInDeepLink(String encodedPayload) {
  final b64 = base64Url.encode(utf8.encode(encodedPayload));
  return 'letsflutssh://import?d=$b64';
}

/// Extract and decode sessions from an import deep link URI.
///
/// Returns null if the URI is not a valid import link.
QrImportData? decodeImportUri(Uri uri) {
  if (uri.scheme != 'letsflutssh' || uri.host != 'import') return null;
  final b64 = uri.queryParameters['d'];
  if (b64 == null || b64.isEmpty) return null;
  try {
    final json = utf8.decode(base64Url.decode(b64));
    return decodeSessionsFromQr(json);
  } catch (_) {
    return null;
  }
}

/// Result of decoding a QR payload.
class QrImportData {
  final List<Session> sessions;
  final Set<String> emptyGroups;

  const QrImportData({required this.sessions, required this.emptyGroups});
}

Map<String, dynamic> _encodeSession(Session s) {
  final m = <String, dynamic>{
    'l': s.label,
    'h': s.host,
    'u': s.user,
  };
  // Only include non-default values to save space
  if (s.port != 22) m['p'] = s.port;
  if (s.group.isNotEmpty) m['g'] = s.group;
  if (s.authType != AuthType.password) m['a'] = s.authType.name;
  return m;
}

Session _decodeSession(Map<String, dynamic> m) {
  return Session(
    label: m['l'] as String? ?? '',
    server: ServerAddress(
      host: m['h'] as String? ?? '',
      port: m['p'] as int? ?? 22,
      user: m['u'] as String? ?? '',
    ),
    group: m['g'] as String? ?? '',
    auth: SessionAuth(
      authType: AuthType.values.firstWhere(
        (e) => e.name == (m['a'] as String? ?? 'password'),
        orElse: () => AuthType.password,
      ),
    ),
    incomplete: true,
  );
}
