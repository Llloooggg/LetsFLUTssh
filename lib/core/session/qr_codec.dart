import 'dart:convert';

import 'package:archive/archive.dart';

import '../../utils/logger.dart';
import '../security/key_store.dart';
import '../snippets/snippet.dart';
import '../tags/tag.dart';
import 'session.dart';
import '../config/app_config.dart';
import '../ssh/ssh_config.dart';

/// Current payload format version.
///
/// v1 — legacy: base64(JSON) without compression
/// v2/v3 — never released
/// v4 — manager key metadata, tags, snippets, session/folder links
const _currentFormatVersion = 4;

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

  /// Keys from key manager referenced by selected sessions only.
  final bool includeManagerKeys;

  /// All keys from key manager (for full app transfer).
  /// Mutually exclusive with [includeManagerKeys] in the UI.
  final bool includeAllManagerKeys;

  /// Tags and their session/folder assignments.
  final bool includeTags;

  /// Snippets and their session links.
  final bool includeSnippets;

  const ExportOptions({
    this.includeSessions = true,
    this.includeConfig = true,
    this.includeKnownHosts = true,
    this.includePasswords = false,
    this.includeEmbeddedKeys = false,
    this.includeManagerKeys = false,
    this.includeAllManagerKeys = false,
    this.includeTags = false,
    this.includeSnippets = false,
  });

  /// Whether any manager key mode is enabled.
  bool get hasManagerKeys => includeManagerKeys || includeAllManagerKeys;

  ExportOptions withIncludeSessions(bool v) => ExportOptions(
    includeSessions: v,
    includeConfig: includeConfig,
    includeKnownHosts: includeKnownHosts,
    includePasswords: includePasswords,
    includeEmbeddedKeys: includeEmbeddedKeys,
    includeManagerKeys: includeManagerKeys,
    includeAllManagerKeys: includeAllManagerKeys,
    includeTags: includeTags,
    includeSnippets: includeSnippets,
  );

  ExportOptions withIncludeConfig(bool v) => ExportOptions(
    includeSessions: includeSessions,
    includeConfig: v,
    includeKnownHosts: includeKnownHosts,
    includePasswords: includePasswords,
    includeEmbeddedKeys: includeEmbeddedKeys,
    includeManagerKeys: includeManagerKeys,
    includeAllManagerKeys: includeAllManagerKeys,
    includeTags: includeTags,
    includeSnippets: includeSnippets,
  );

  ExportOptions withIncludeKnownHosts(bool v) => ExportOptions(
    includeSessions: includeSessions,
    includeConfig: includeConfig,
    includeKnownHosts: v,
    includePasswords: includePasswords,
    includeEmbeddedKeys: includeEmbeddedKeys,
    includeManagerKeys: includeManagerKeys,
    includeAllManagerKeys: includeAllManagerKeys,
    includeTags: includeTags,
    includeSnippets: includeSnippets,
  );

  ExportOptions withIncludePasswords(bool v) => ExportOptions(
    includeSessions: includeSessions,
    includeConfig: includeConfig,
    includeKnownHosts: includeKnownHosts,
    includePasswords: v,
    includeEmbeddedKeys: includeEmbeddedKeys,
    includeManagerKeys: includeManagerKeys,
    includeAllManagerKeys: includeAllManagerKeys,
    includeTags: includeTags,
    includeSnippets: includeSnippets,
  );

  ExportOptions withIncludeEmbeddedKeys(bool v) => ExportOptions(
    includeSessions: includeSessions,
    includeConfig: includeConfig,
    includeKnownHosts: includeKnownHosts,
    includePasswords: includePasswords,
    includeEmbeddedKeys: v,
    includeManagerKeys: includeManagerKeys,
    includeAllManagerKeys: includeAllManagerKeys,
    includeTags: includeTags,
    includeSnippets: includeSnippets,
  );

  ExportOptions withIncludeManagerKeys(bool v) => ExportOptions(
    includeSessions: includeSessions,
    includeConfig: includeConfig,
    includeKnownHosts: includeKnownHosts,
    includePasswords: includePasswords,
    includeEmbeddedKeys: includeEmbeddedKeys,
    includeManagerKeys: v,
    includeAllManagerKeys: includeAllManagerKeys,
    includeTags: includeTags,
    includeSnippets: includeSnippets,
  );

  ExportOptions withIncludeAllManagerKeys(bool v) => ExportOptions(
    includeSessions: includeSessions,
    includeConfig: includeConfig,
    includeKnownHosts: includeKnownHosts,
    includePasswords: includePasswords,
    includeEmbeddedKeys: includeEmbeddedKeys,
    includeManagerKeys: includeManagerKeys,
    includeAllManagerKeys: v,
    includeTags: includeTags,
    includeSnippets: includeSnippets,
  );

  ExportOptions withIncludeTags(bool v) => ExportOptions(
    includeSessions: includeSessions,
    includeConfig: includeConfig,
    includeKnownHosts: includeKnownHosts,
    includePasswords: includePasswords,
    includeEmbeddedKeys: includeEmbeddedKeys,
    includeManagerKeys: includeManagerKeys,
    includeAllManagerKeys: includeAllManagerKeys,
    includeTags: v,
    includeSnippets: includeSnippets,
  );

  ExportOptions withIncludeSnippets(bool v) => ExportOptions(
    includeSessions: includeSessions,
    includeConfig: includeConfig,
    includeKnownHosts: includeKnownHosts,
    includePasswords: includePasswords,
    includeEmbeddedKeys: includeEmbeddedKeys,
    includeManagerKeys: includeManagerKeys,
    includeAllManagerKeys: includeAllManagerKeys,
    includeTags: includeTags,
    includeSnippets: v,
  );

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
          includeManagerKeys == other.includeManagerKeys &&
          includeAllManagerKeys == other.includeAllManagerKeys &&
          includeTags == other.includeTags &&
          includeSnippets == other.includeSnippets;

  @override
  int get hashCode => Object.hash(
    includeSessions,
    includeConfig,
    includeKnownHosts,
    includePasswords,
    includeEmbeddedKeys,
    includeManagerKeys,
    includeAllManagerKeys,
    includeTags,
    includeSnippets,
  );
}

/// Encode sessions into a compact JSON, compress with deflate, return base64url.
///
/// Format: `{"km":{"k0":"ssh-rsa..."},"s":[...],"eg":[...],"c":{...},"kh":"..."}`
/// Keys are deduplicated in `km` (key map), sessions reference via `ki`.
/// Manager keys carry metadata in `mk` and sessions flag `mg:1`.
/// The entire JSON is deflate-compressed before base64 encoding.

/// Bundle of inputs for [encodeExportPayload] / [calculateExportPayloadSize]
/// besides the primary `sessions` list. Groups related optional parameters
/// to keep public function signatures small.
class ExportPayloadInput {
  final Set<String> emptyFolders;
  final ExportOptions options;
  final AppConfig? config;
  final String? knownHostsContent;
  final Map<String, SshKeyEntry> managerKeyEntries;
  final List<Tag> tags;
  final List<ExportLink> sessionTags;
  final List<ExportFolderTagLink> folderTags;
  final List<Snippet> snippets;
  final List<ExportLink> sessionSnippets;

  const ExportPayloadInput({
    this.emptyFolders = const {},
    this.options = const ExportOptions(),
    this.config,
    this.knownHostsContent,
    this.managerKeyEntries = const {},
    this.tags = const [],
    this.sessionTags = const [],
    this.folderTags = const [],
    this.snippets = const [],
    this.sessionSnippets = const [],
  });
}

/// Deduplicate SSH keys across sessions and return a short-id map.
///
/// Keys are deduplicated by content — the same physical key used both
/// as embedded and as manager key appears once in `km`.
({
  Map<String, String> keyMap,
  Map<String, String?> sessionKeyIds,
  Set<String> managerShortIds,
})
_deduplicateKeys(List<Session> sessions, ExportOptions options) {
  final sessionKeyIds = <String, String?>{};
  final managerShortIds = <String>{};
  if (!options.includeEmbeddedKeys && !options.hasManagerKeys) {
    return (
      keyMap: <String, String>{},
      sessionKeyIds: sessionKeyIds,
      managerShortIds: managerShortIds,
    );
  }

  final keyToShortId = <String, String>{};
  var counter = 0;
  for (final s in sessions) {
    if (s.keyData.isEmpty) continue;
    final isFromManager = s.keyId.isNotEmpty;
    if (isFromManager && !options.hasManagerKeys) continue;
    if (!isFromManager && !options.includeEmbeddedKeys) continue;

    final shortId = keyToShortId.putIfAbsent(s.keyData, () {
      final id = 'k$counter';
      counter++;
      return id;
    });
    sessionKeyIds[s.id] = shortId;
    if (isFromManager) managerShortIds.add(shortId);
  }

  final keyMap = <String, String>{};
  keyToShortId.forEach((keyData, shortId) => keyMap[shortId] = keyData);
  return (
    keyMap: keyMap,
    sessionKeyIds: sessionKeyIds,
    managerShortIds: managerShortIds,
  );
}

/// Encode sessions into a compact JSON, compress with deflate, return base64url.
///
/// [input] groups optional parameters. See [ExportPayloadInput].
String encodeExportPayload(
  List<Session> sessions, {
  ExportPayloadInput input = const ExportPayloadInput(),
}) {
  final options = input.options;
  final (:keyMap, :sessionKeyIds, :managerShortIds) = _deduplicateKeys(
    sessions,
    options,
  );

  _addAllManagerKeys(keyMap, managerShortIds, input);

  final payload = <String, dynamic>{'v': _currentFormatVersion};
  if (keyMap.isNotEmpty) payload['km'] = keyMap;

  _encodeManagerKeyMetadata(payload, keyMap, managerShortIds, input);
  _encodeSessionsAndFolders(
    payload,
    sessions,
    input,
    sessionKeyIds,
    managerShortIds,
  );
  _encodeConfigAndHosts(payload, input);
  _encodeTagsPayload(payload, input);
  _encodeSnippetsPayload(payload, input);

  final json = jsonEncode(payload);
  final compressed = Deflate(utf8.encode(json)).getBytes();
  final encoded = base64Url.encode(compressed);
  AppLogger.instance.log(
    'Encoded payload: ${sessions.length} sessions, '
    '${input.emptyFolders.length} folders, '
    '${input.tags.length} tags, ${input.snippets.length} snippets, '
    'config=${input.config != null}, '
    'knownHosts=${input.knownHostsContent != null}, '
    'size=${encoded.length} bytes',
    name: 'QrCodec',
  );
  return encoded;
}

/// For "all manager keys" mode, add keys not referenced by any session.
void _addAllManagerKeys(
  Map<String, String> keyMap,
  Set<String> managerShortIds,
  ExportPayloadInput input,
) {
  if (!input.options.includeAllManagerKeys) return;
  if (input.managerKeyEntries.isEmpty) return;

  final keyToShortId = <String, String>{};
  keyMap.forEach((shortId, keyData) => keyToShortId[keyData] = shortId);
  var counter = keyMap.length;
  for (final entry in input.managerKeyEntries.entries) {
    final existing = keyToShortId[entry.value.privateKey];
    if (existing != null) {
      // Key already in map (from session dedup), just mark as manager.
      managerShortIds.add(existing);
      continue;
    }
    final shortId = 'k$counter';
    counter++;
    keyMap[shortId] = entry.value.privateKey;
    managerShortIds.add(shortId);
  }
}

void _encodeManagerKeyMetadata(
  Map<String, dynamic> payload,
  Map<String, String> keyMap,
  Set<String> managerShortIds,
  ExportPayloadInput input,
) {
  if (managerShortIds.isEmpty) return;
  final mk = <String, dynamic>{};
  final keyDataToEntry = <String, SshKeyEntry>{};
  for (final e in input.managerKeyEntries.values) {
    keyDataToEntry[e.privateKey] = e;
  }
  for (final shortId in managerShortIds) {
    final keyData = keyMap[shortId];
    if (keyData == null) continue;
    final entry = keyDataToEntry[keyData];
    if (entry != null) {
      mk[shortId] = {
        'l': entry.label,
        't': entry.keyType,
        'p': entry.publicKey,
      };
    }
  }
  if (mk.isNotEmpty) payload['mk'] = mk;
}

void _encodeSessionsAndFolders(
  Map<String, dynamic> payload,
  List<Session> sessions,
  ExportPayloadInput input,
  Map<String, String?> sessionKeyIds,
  Set<String> managerShortIds,
) {
  if (!input.options.includeSessions) return;
  payload['s'] = sessions
      .map(
        (s) => encodeSessionCompact(
          s,
          keyId: sessionKeyIds[s.id],
          isManagerKey:
              s.keyId.isNotEmpty &&
              sessionKeyIds.containsKey(s.id) &&
              managerShortIds.contains(sessionKeyIds[s.id]),
          includePasswords: input.options.includePasswords,
        ),
      )
      .toList();
  if (input.emptyFolders.isNotEmpty) {
    payload['eg'] = input.emptyFolders.toList();
  }
}

void _encodeConfigAndHosts(
  Map<String, dynamic> payload,
  ExportPayloadInput input,
) {
  final config = input.config;
  if (input.options.includeConfig && config != null) {
    payload['c'] = config.toJson();
  }
  final kh = input.knownHostsContent;
  if (input.options.includeKnownHosts && kh != null) {
    payload['kh'] = kh;
  }
}

void _encodeTagsPayload(
  Map<String, dynamic> payload,
  ExportPayloadInput input,
) {
  if (!input.options.includeTags || input.tags.isEmpty) return;
  payload['tg'] = input.tags
      .map((t) => {'i': t.id, 'n': t.name, if (t.color != null) 'cl': t.color})
      .toList();
  if (input.sessionTags.isNotEmpty) {
    payload['st'] = input.sessionTags
        .map((l) => {'si': l.sessionId, 'ti': l.targetId})
        .toList();
  }
  if (input.folderTags.isNotEmpty) {
    payload['ft'] = input.folderTags
        .map((l) => {'fi': l.folderPath, 'ti': l.tagId})
        .toList();
  }
}

void _encodeSnippetsPayload(
  Map<String, dynamic> payload,
  ExportPayloadInput input,
) {
  if (!input.options.includeSnippets || input.snippets.isEmpty) return;
  payload['sn'] = input.snippets
      .map(
        (s) => {
          'i': s.id,
          't': s.title,
          'cm': s.command,
          if (s.description.isNotEmpty) 'd': s.description,
        },
      )
      .toList();
  if (input.sessionSnippets.isNotEmpty) {
    payload['ss'] = input.sessionSnippets
        .map((l) => {'si': l.sessionId, 'ni': l.targetId})
        .toList();
  }
}

/// Calculate the byte size of the encoded payload (deflate compressed + base64).
int calculateExportPayloadSize(
  List<Session> sessions, {
  ExportPayloadInput input = const ExportPayloadInput(),
}) {
  return encodeExportPayload(sessions, input: input).length;
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
  // Current format (v4): base64(deflate(JSON))
  try {
    final compressed = base64Url.decode(b64);
    final inflated = Inflate(compressed).getBytes();
    final json = utf8.decode(inflated);
    final result = _parsePayload(json);
    if (result != null) return result;
  } on FormatException {
    // Invalid base64
  } on RangeError {
    // Corrupt or truncated deflate data
  } catch (_) {
    // Any other decoding error — fall through to v1 format
  }

  // Fallback: v1 legacy format — raw base64(JSON) without deflate.
  try {
    final raw = base64Url.decode(b64);
    final json = utf8.decode(raw);
    jsonDecode(json);
    return _parsePayload(json);
  } on FormatException {
    // Invalid base64 or UTF-8
  } catch (_) {
    // Any other error
  }
  return null;
}

/// Coerce a JSON-decoded value to [int] — accepts `int`, `num`, else
/// returns [fallback]. Extracted to keep version/field parsers flat.
int _asInt(Object? raw, {required int fallback}) {
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  return fallback;
}

ExportPayloadData? _parsePayload(String payload) {
  try {
    final json = jsonDecode(payload) as Map<String, dynamic>;

    // Version check: reject future versions up-front — unknown fields may
    // carry data this build cannot interpret, and silently dropping them
    // would cause partial/incorrect imports. Missing `v` is treated as v1
    // (legacy payloads predate the version marker).
    final version = _asInt(json['v'], fallback: 1);
    if (version > _currentFormatVersion) {
      AppLogger.instance.log(
        'Rejected payload: schema v$version is newer than supported '
        'v$_currentFormatVersion — update the app to import this QR.',
        name: 'QrCodec',
      );
      return null;
    }
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

    final keyMap = _parseKeyMap(json);
    final (sessions, emptyFolders) = _parseSessions(json, keyMap);
    final managerKeys = _parseManagerKeys(json, keyMap);
    final config = _parseConfig(json);
    final knownHostsContent = _parseKnownHosts(json);
    final (tags, sessionTagLinks, folderTagLinks) = _parseTags(json);
    final (decodedSnippets, sessionSnippetLinks) = _parseSnippets(json);

    AppLogger.instance.log(
      'Decoded payload: ${sessions.length} sessions, '
      '${emptyFolders.length} folders, '
      '${managerKeys.length} manager keys, '
      '${tags.length} tags, ${decodedSnippets.length} snippets, '
      'config=${config != null}, knownHosts=${knownHostsContent != null}',
      name: 'QrCodec',
    );
    return ExportPayloadData(
      sessions: sessions,
      emptyFolders: emptyFolders,
      managerKeys: managerKeys,
      config: config,
      knownHostsContent: knownHostsContent,
      tags: tags,
      sessionTags: sessionTagLinks,
      folderTags: folderTagLinks,
      snippets: decodedSnippets,
      sessionSnippets: sessionSnippetLinks,
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

Map<String, String> _parseKeyMap(Map<String, dynamic> json) {
  final keyMap = <String, String>{};
  if (json.containsKey('km')) {
    final km = json['km'] as Map<String, dynamic>;
    keyMap.addAll(km.cast<String, String>());
  }
  return keyMap;
}

(List<Session>, Set<String>) _parseSessions(
  Map<String, dynamic> json,
  Map<String, String> keyMap,
) {
  final sessions = <Session>[];
  final emptyFolders = <String>{};
  if (json.containsKey('s')) {
    for (final m in (json['s'] as List).cast<Map<String, dynamic>>()) {
      sessions.add(_decodeSession(m, keyMap));
    }
    final ef = json['eg'] as List?;
    if (ef != null) emptyFolders.addAll(ef.cast<String>());
  }
  return (sessions, emptyFolders);
}

List<SshKeyEntry> _parseManagerKeys(
  Map<String, dynamic> json,
  Map<String, String> keyMap,
) {
  final managerKeys = <SshKeyEntry>[];
  if (!json.containsKey('mk')) return managerKeys;
  final mk = json['mk'] as Map<String, dynamic>;
  for (final entry in mk.entries) {
    final meta = entry.value as Map<String, dynamic>;
    final keyData = keyMap[entry.key];
    if (keyData == null) continue;
    managerKeys.add(
      SshKeyEntry(
        id: entry.key,
        label: meta['l'] as String? ?? '',
        privateKey: keyData,
        publicKey: meta['p'] as String? ?? '',
        keyType: meta['t'] as String? ?? '',
        createdAt: DateTime.now(),
      ),
    );
  }
  return managerKeys;
}

AppConfig? _parseConfig(Map<String, dynamic> json) {
  if (!json.containsKey('c')) return null;
  return AppConfig.fromJson(json['c'] as Map<String, dynamic>);
}

String? _parseKnownHosts(Map<String, dynamic> json) {
  if (!json.containsKey('kh')) return null;
  return json['kh'] as String?;
}

(List<Tag>, List<ExportLink>, List<ExportFolderTagLink>) _parseTags(
  Map<String, dynamic> json,
) {
  final tags = <Tag>[];
  final sessionTagLinks = <ExportLink>[];
  final folderTagLinks = <ExportFolderTagLink>[];
  if (!json.containsKey('tg')) return (tags, sessionTagLinks, folderTagLinks);
  for (final t in (json['tg'] as List).cast<Map<String, dynamic>>()) {
    tags.add(
      Tag(
        id: t['i'] as String? ?? '',
        name: t['n'] as String? ?? '',
        color: t['cl'] as String?,
      ),
    );
  }
  if (json.containsKey('st')) {
    for (final l in (json['st'] as List).cast<Map<String, dynamic>>()) {
      sessionTagLinks.add(
        ExportLink(
          sessionId: l['si'] as String? ?? '',
          targetId: l['ti'] as String? ?? '',
        ),
      );
    }
  }
  if (json.containsKey('ft')) {
    for (final l in (json['ft'] as List).cast<Map<String, dynamic>>()) {
      folderTagLinks.add(
        ExportFolderTagLink(
          folderPath: l['fi'] as String? ?? '',
          tagId: l['ti'] as String? ?? '',
        ),
      );
    }
  }
  return (tags, sessionTagLinks, folderTagLinks);
}

(List<Snippet>, List<ExportLink>) _parseSnippets(Map<String, dynamic> json) {
  final decodedSnippets = <Snippet>[];
  final sessionSnippetLinks = <ExportLink>[];
  if (!json.containsKey('sn')) return (decodedSnippets, sessionSnippetLinks);
  for (final s in (json['sn'] as List).cast<Map<String, dynamic>>()) {
    decodedSnippets.add(
      Snippet(
        id: s['i'] as String? ?? '',
        title: s['t'] as String? ?? '',
        command: s['cm'] as String? ?? '',
        description: s['d'] as String? ?? '',
      ),
    );
  }
  if (json.containsKey('ss')) {
    for (final l in (json['ss'] as List).cast<Map<String, dynamic>>()) {
      sessionSnippetLinks.add(
        ExportLink(
          sessionId: l['si'] as String? ?? '',
          targetId: l['ni'] as String? ?? '',
        ),
      );
    }
  }
  return (decodedSnippets, sessionSnippetLinks);
}

/// Encode a session into the compact QR payload format.
///
/// Used internally by [encodeExportPayload] and also available for
/// size estimation in export dialogs.
Map<String, dynamic> encodeSessionCompact(
  Session s, {
  String? keyId,
  bool isManagerKey = false,
  bool includePasswords = false,
}) {
  final m = <String, dynamic>{'l': s.label, 'h': s.host, 'u': s.user};
  if (s.port != 22) m['p'] = s.port;
  if (s.folder.isNotEmpty) m['g'] = s.folder;
  if (s.authType != AuthType.password) m['a'] = s.authType.name;
  if (keyId != null) m['ki'] = keyId;
  if (isManagerKey) m['mg'] = 1;
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
  final shortKeyId = m['ki'] as String?;
  final isManagerKey = m['mg'] == 1;

  // Manager keys: keyId = shortId (remapped to real ID during import),
  // keyData stays empty (loaded from KeyStore after import).
  // Embedded keys: keyData inline, keyId empty.
  final keyData = (!isManagerKey && shortKeyId != null)
      ? (keyMap[shortKeyId] ?? '')
      : '';
  final keyId = isManagerKey ? (shortKeyId ?? '') : '';

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
      keyId: keyId,
    ),
  );
}

/// A session→tag or session→snippet link from the export payload.
class ExportLink {
  final String sessionId;
  final String targetId;
  const ExportLink({required this.sessionId, required this.targetId});
}

/// A folder→tag link from the export payload.
class ExportFolderTagLink {
  final String folderPath;
  final String tagId;
  const ExportFolderTagLink({required this.folderPath, required this.tagId});
}

/// Result of decoding an export payload.
class ExportPayloadData {
  final List<Session> sessions;
  final Set<String> emptyFolders;

  /// Manager keys to insert into KeyStore on import.
  /// The [SshKeyEntry.id] is the short id from the payload — import code
  /// must remap session keyIds after inserting into the real KeyStore.
  final List<SshKeyEntry> managerKeys;
  final AppConfig? config;
  final String? knownHostsContent;

  /// Tags to insert on import.
  final List<Tag> tags;

  /// Session→tag assignments.
  final List<ExportLink> sessionTags;

  /// Folder→tag assignments.
  final List<ExportFolderTagLink> folderTags;

  /// Snippets to insert on import.
  final List<Snippet> snippets;

  /// Session→snippet links (pinned snippets).
  final List<ExportLink> sessionSnippets;

  const ExportPayloadData({
    required this.sessions,
    required this.emptyFolders,
    this.managerKeys = const [],
    this.config,
    this.knownHostsContent,
    this.tags = const [],
    this.sessionTags = const [],
    this.folderTags = const [],
    this.snippets = const [],
    this.sessionSnippets = const [],
  });

  bool get hasSessions => sessions.isNotEmpty;
  bool get hasConfig => config != null;
  bool get hasKnownHosts {
    final content = knownHostsContent;
    return content != null && content.isNotEmpty;
  }
}
