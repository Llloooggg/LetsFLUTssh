import 'dart:convert';

import 'package:archive/archive.dart';

import '../../utils/logger.dart';
import 'session.dart';
import '../config/app_config.dart';
import '../ssh/ssh_config.dart';

/// Current payload format version.
///
/// v1 — legacy: base64(JSON) without compression
/// v2 — current: base64(deflate(JSON)) with key deduplication
const _currentFormatVersion = 2;

/// Maximum payload size in bytes (before deep link wrapping).
///
/// QR version 40 with error correction L holds 2953 bytes in binary mode.
/// The deep link wrapper `letsflutssh://import?d=` adds ~25 bytes,
/// plus base64 encoding inflates by ~33%. Conservative limit.
const qrMaxPayloadBytes = 2000;

/// Options controlling what data to include in export.
///
/// Credentials (passwords, embedded keys, manager keys) default to `false`
/// for security. The UI should require explicit opt-in per export.
class ExportOptions {
  final bool includeSessions;
  final bool includeConfig;
  final bool includeKnownHosts;
  final bool includePasswords;

  /// Embedded SSH keys (keyData directly in session, from file paste)
  final bool includeEmbeddedKeys;

  /// Keys from key manager (keyId → resolved to keyData)
  final bool includeManagerKeys;

  const ExportOptions({
    this.includeSessions = true,
    this.includeConfig = true,
    this.includeKnownHosts = true,
    this.includePasswords = false,
    this.includeEmbeddedKeys = false,
    this.includeManagerKeys = false,
  });

  ExportOptions copyWith({
    bool? includeSessions,
    bool? includeConfig,
    bool? includeKnownHosts,
    bool? includePasswords,
    bool? includeEmbeddedKeys,
    bool? includeManagerKeys,
  }) {
    return ExportOptions(
      includeSessions: includeSessions ?? this.includeSessions,
      includeConfig: includeConfig ?? this.includeConfig,
      includeKnownHosts: includeKnownHosts ?? this.includeKnownHosts,
      includePasswords: includePasswords ?? this.includePasswords,
      includeEmbeddedKeys: includeEmbeddedKeys ?? this.includeEmbeddedKeys,
      includeManagerKeys: includeManagerKeys ?? this.includeManagerKeys,
    );
  }

  bool get hasAnySelection =>
      includeSessions || includeConfig || includeKnownHosts;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExportOptions &&
          includeSessions == other.includeSessions &&
          includeConfig == other.includeConfig &&
          includeKnownHosts == other.includeKnownHosts &&
          includePasswords == other.includePasswords &&
          includeEmbeddedKeys == other.includeEmbeddedKeys &&
          includeManagerKeys == other.includeManagerKeys;

  @override
  int get hashCode => Object.hash(
    includeSessions,
    includeConfig,
    includeKnownHosts,
    includePasswords,
    includeEmbeddedKeys,
    includeManagerKeys,
  );
}

/// Encode sessions into a compact JSON, compress with deflate, return base64url.
///
/// Format: `{"km":{"k0":"ssh-rsa..."},"s":[...],"eg":[...],"c":{...},"kh":"..."}`
/// Keys are deduplicated in `km` (key map), sessions reference via `ki`.
/// The entire JSON is deflate-compressed before base64 encoding.
/// Deduplicate SSH keys across sessions and return a short-id map.
///
/// Returns `(keyMap: shortId→keyData, sessionKeyIds: sessionId→shortId)`.
({Map<String, String> keyMap, Map<String, String?> sessionKeyIds})
_deduplicateKeys(List<Session> sessions, ExportOptions options) {
  final sessionKeyIds = <String, String?>{};
  if (!options.includeEmbeddedKeys && !options.includeManagerKeys) {
    return (keyMap: <String, String>{}, sessionKeyIds: sessionKeyIds);
  }

  final keyToShortId = <String, String>{};
  var counter = 0;
  for (final s in sessions) {
    if (s.keyData.isEmpty) continue;
    final isFromManager = s.keyId.isNotEmpty;
    if (isFromManager && !options.includeManagerKeys) continue;
    if (!isFromManager && !options.includeEmbeddedKeys) continue;

    final shortId = keyToShortId.putIfAbsent(s.keyData, () {
      final id = 'k$counter';
      counter++;
      return id;
    });
    sessionKeyIds[s.id] = shortId;
  }

  final keyMap = <String, String>{};
  keyToShortId.forEach((keyData, shortId) => keyMap[shortId] = keyData);
  return (keyMap: keyMap, sessionKeyIds: sessionKeyIds);
}

String encodeExportPayload(
  List<Session> sessions, {
  Set<String> emptyFolders = const {},
  ExportOptions options = const ExportOptions(),
  AppConfig? config,
  String? knownHostsContent,
}) {
  final (:keyMap, :sessionKeyIds) = _deduplicateKeys(sessions, options);

  final payload = <String, dynamic>{'v': _currentFormatVersion};
  if (keyMap.isNotEmpty) payload['km'] = keyMap;
  if (options.includeSessions) {
    payload['s'] = sessions
        .map(
          (s) => encodeSessionCompact(
            s,
            keyId: sessionKeyIds[s.id],
            includePasswords: options.includePasswords,
          ),
        )
        .toList();
    if (emptyFolders.isNotEmpty) payload['eg'] = emptyFolders.toList();
  }
  if (options.includeConfig && config != null) {
    payload['c'] = config.toJson();
  }
  if (options.includeKnownHosts && knownHostsContent != null) {
    payload['kh'] = knownHostsContent;
  }

  final json = jsonEncode(payload);
  final compressed = Deflate(utf8.encode(json)).getBytes();
  final encoded = base64Url.encode(compressed);
  AppLogger.instance.log(
    'Encoded payload: ${sessions.length} sessions, '
    '${emptyFolders.length} folders, '
    'config=${config != null}, knownHosts=${knownHostsContent != null}, '
    'size=${encoded.length} bytes',
    name: 'QrCodec',
  );
  return encoded;
}

/// Calculate the byte size of the encoded payload (deflate compressed + base64).
int calculateExportPayloadSize(
  List<Session> sessions, {
  Set<String> emptyFolders = const {},
  ExportOptions options = const ExportOptions(),
  AppConfig? config,
  String? knownHostsContent,
}) {
  return encodeExportPayload(
    sessions,
    emptyFolders: emptyFolders,
    options: options,
    config: config,
    knownHostsContent: knownHostsContent,
  ).length;
}

/// Wrap encoded sessions into a deep link URI for QR code.
String wrapInDeepLink(String encodedPayload) {
  return 'letsflutssh://import?d=$encodedPayload';
}

/// Extract and decode sessions from an import deep link URI.
ExportPayloadData? decodeImportUri(Uri uri) {
  if (uri.scheme != 'letsflutssh' || uri.host != 'import') return null;
  final b64 = uri.queryParameters['d'];
  if (b64 == null || b64.isEmpty) return null;
  return _decodePayload(b64);
}

/// Decode sessions, config, known_hosts from an export payload string.
ExportPayloadData? decodeExportPayload(String payload) {
  return _decodePayload(payload);
}

ExportPayloadData? _decodePayload(String b64) {
  // Try new format first: base64(deflate(JSON))
  try {
    final compressed = base64Url.decode(b64);
    final inflated = Inflate(compressed).getBytes();
    final json = utf8.decode(inflated);
    final result = _parsePayload(json);
    // If deflate succeeded but JSON was invalid/unrecognised, fall through
    // to the old format instead of returning null immediately.
    if (result != null) return result;
  } on FormatException {
    // Invalid base64 — not new format
  } on RangeError {
    // Corrupt or truncated deflate data
  } catch (_) {
    // Any other decoding error — fall through to old format
  }

  // Fallback: old format — raw base64(JSON) without deflate compression.
  // This allows scanning QR codes generated by previous app versions.
  try {
    final raw = base64Url.decode(b64);
    final json = utf8.decode(raw);
    // Only treat as old format if it's actually valid JSON
    jsonDecode(json);
    return _parsePayload(json);
  } on FormatException {
    // Invalid base64 or UTF-8 — not a valid payload
  } catch (_) {
    // Any other error during parsing
  }
  return null;
}

ExportPayloadData? _parsePayload(String payload) {
  try {
    final json = jsonDecode(payload) as Map<String, dynamic>;

    // Version check — log for diagnostics, accept all known versions.
    final version = json['v'] as int?;
    AppLogger.instance.log(
      'Parsing payload: version=$version',
      name: 'QrCodec',
    );

    if (!json.containsKey('s') &&
        !json.containsKey('km') &&
        !json.containsKey('c') &&
        !json.containsKey('kh')) {
      return null;
    }

    final keyMap = <String, String>{};
    if (json.containsKey('km')) {
      final km = json['km'] as Map<String, dynamic>;
      keyMap.addAll(km.cast<String, String>());
    }

    final sessions = <Session>[];
    final emptyFolders = <String>{};
    if (json.containsKey('s')) {
      for (final m in (json['s'] as List).cast<Map<String, dynamic>>()) {
        sessions.add(_decodeSession(m, keyMap));
      }
      final ef = json['eg'] as List?;
      if (ef != null) emptyFolders.addAll(ef.cast<String>());
    }

    AppConfig? config;
    if (json.containsKey('c')) {
      config = AppConfig.fromJson(json['c'] as Map<String, dynamic>);
    }
    String? knownHostsContent;
    if (json.containsKey('kh')) {
      knownHostsContent = json['kh'] as String?;
    }

    AppLogger.instance.log(
      'Decoded payload: ${sessions.length} sessions, '
      '${emptyFolders.length} folders, '
      'config=${config != null}, knownHosts=${knownHostsContent != null}',
      name: 'QrCodec',
    );
    return ExportPayloadData(
      sessions: sessions,
      emptyFolders: emptyFolders,
      config: config,
      knownHostsContent: knownHostsContent,
    );
  } on TypeError {
    // Malformed data from untrusted source — gracefully return null
    // instead of crashing. TypeErrors happen when JSON structure doesn't
    // match expected types (e.g., string where number expected).
    return null;
  } catch (_) {
    return null;
  }
}

/// Encode a session into the compact QR payload format.
///
/// Used internally by [encodeExportPayload] and also available for
/// size estimation in export dialogs.
Map<String, dynamic> encodeSessionCompact(
  Session s, {
  String? keyId,
  bool includePasswords = false,
}) {
  final m = <String, dynamic>{'l': s.label, 'h': s.host, 'u': s.user};
  if (s.port != 22) m['p'] = s.port;
  if (s.folder.isNotEmpty) m['g'] = s.folder;
  if (s.authType != AuthType.password) m['a'] = s.authType.name;
  if (keyId != null) m['ki'] = keyId;
  // SECURITY: passwords stored in plaintext in QR payload — only enable when
  // user explicitly opts in via includePasswords. QR codes can be scanned by
  // anyone with camera access to the screen.
  if (includePasswords && s.password.isNotEmpty) m['pw'] = s.password;
  return m;
}

Session _decodeSession(Map<String, dynamic> m, Map<String, String> keyMap) {
  final authType = AuthType.values.firstWhere(
    (e) => e.name == (m['a'] as String? ?? 'password'),
    orElse: () => AuthType.password,
  );
  final password = m['pw'] as String? ?? '';
  final keyId = m['ki'] as String?;
  final keyData = keyId != null ? (keyMap[keyId] ?? '') : '';

  return Session(
    label: m['l'] as String? ?? '',
    server: ServerAddress(
      host: m['h'] as String? ?? '',
      port: m['p'] as int? ?? 22,
      user: m['u'] as String? ?? '',
    ),
    folder: m['g'] as String? ?? '',
    auth: SessionAuth(
      authType: authType,
      password: password,
      keyData: keyData,
      keyId: keyId ?? '',
    ),
  );
}

/// Result of decoding an export payload.
class ExportPayloadData {
  final List<Session> sessions;
  final Set<String> emptyFolders;
  final AppConfig? config;
  final String? knownHostsContent;

  const ExportPayloadData({
    required this.sessions,
    required this.emptyFolders,
    this.config,
    this.knownHostsContent,
  });

  bool get hasSessions => sessions.isNotEmpty;
  bool get hasConfig => config != null;
  bool get hasKnownHosts {
    final content = knownHostsContent;
    return content != null && content.isNotEmpty;
  }
}
