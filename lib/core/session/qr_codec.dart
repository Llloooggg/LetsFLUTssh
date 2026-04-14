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

  ExportOptions copyWith({
    bool? includeSessions,
    bool? includeConfig,
    bool? includeKnownHosts,
    bool? includePasswords,
    bool? includeEmbeddedKeys,
    bool? includeManagerKeys,
    bool? includeAllManagerKeys,
    bool? includeTags,
    bool? includeSnippets,
  }) {
    return ExportOptions(
      includeSessions: includeSessions ?? this.includeSessions,
      includeConfig: includeConfig ?? this.includeConfig,
      includeKnownHosts: includeKnownHosts ?? this.includeKnownHosts,
      includePasswords: includePasswords ?? this.includePasswords,
      includeEmbeddedKeys: includeEmbeddedKeys ?? this.includeEmbeddedKeys,
      includeManagerKeys: includeManagerKeys ?? this.includeManagerKeys,
      includeAllManagerKeys:
          includeAllManagerKeys ?? this.includeAllManagerKeys,
      includeTags: includeTags ?? this.includeTags,
      includeSnippets: includeSnippets ?? this.includeSnippets,
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
/// [managerKeyEntries] maps keyId → [SshKeyEntry] for manager key metadata.
/// Pass empty map when manager keys are not included.
String encodeExportPayload(
  List<Session> sessions, {
  Set<String> emptyFolders = const {},
  ExportOptions options = const ExportOptions(),
  AppConfig? config,
  String? knownHostsContent,
  Map<String, SshKeyEntry> managerKeyEntries = const {},
  List<Tag> tags = const [],
  List<ExportLink> sessionTags = const [],
  List<ExportFolderTagLink> folderTags = const [],
  List<Snippet> snippets = const [],
  List<ExportLink> sessionSnippets = const [],
}) {
  final (:keyMap, :sessionKeyIds, :managerShortIds) = _deduplicateKeys(
    sessions,
    options,
  );

  // For "all manager keys" mode, add keys not referenced by any session.
  if (options.includeAllManagerKeys && managerKeyEntries.isNotEmpty) {
    final keyToShortId = <String, String>{};
    keyMap.forEach((shortId, keyData) => keyToShortId[keyData] = shortId);
    var counter = keyMap.length;
    for (final entry in managerKeyEntries.entries) {
      if (keyToShortId.containsKey(entry.value.privateKey)) {
        // Key already in map (from session dedup), just mark as manager.
        managerShortIds.add(keyToShortId[entry.value.privateKey]!);
        continue;
      }
      final shortId = 'k$counter';
      counter++;
      keyMap[shortId] = entry.value.privateKey;
      managerShortIds.add(shortId);
    }
  }

  final payload = <String, dynamic>{'v': _currentFormatVersion};
  if (keyMap.isNotEmpty) payload['km'] = keyMap;

  // Manager key metadata: shortId → {label, type, publicKey}
  if (managerShortIds.isNotEmpty) {
    final mk = <String, dynamic>{};
    // Build reverse lookup: privateKey → SshKeyEntry
    final keyDataToEntry = <String, SshKeyEntry>{};
    for (final e in managerKeyEntries.values) {
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

  if (options.includeSessions) {
    payload['s'] = sessions
        .map(
          (s) => encodeSessionCompact(
            s,
            keyId: sessionKeyIds[s.id],
            isManagerKey:
                s.keyId.isNotEmpty &&
                sessionKeyIds.containsKey(s.id) &&
                managerShortIds.contains(sessionKeyIds[s.id]),
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

  // Tags
  if (options.includeTags && tags.isNotEmpty) {
    payload['tg'] = tags
        .map(
          (t) => {'i': t.id, 'n': t.name, if (t.color != null) 'cl': t.color},
        )
        .toList();
    if (sessionTags.isNotEmpty) {
      payload['st'] = sessionTags
          .map((l) => {'si': l.sessionId, 'ti': l.targetId})
          .toList();
    }
    if (folderTags.isNotEmpty) {
      payload['ft'] = folderTags
          .map((l) => {'fi': l.folderPath, 'ti': l.tagId})
          .toList();
    }
  }

  // Snippets
  if (options.includeSnippets && snippets.isNotEmpty) {
    payload['sn'] = snippets
        .map(
          (s) => {
            'i': s.id,
            't': s.title,
            'cm': s.command,
            if (s.description.isNotEmpty) 'd': s.description,
          },
        )
        .toList();
    if (sessionSnippets.isNotEmpty) {
      payload['ss'] = sessionSnippets
          .map((l) => {'si': l.sessionId, 'ni': l.targetId})
          .toList();
    }
  }

  final json = jsonEncode(payload);
  final compressed = Deflate(utf8.encode(json)).getBytes();
  final encoded = base64Url.encode(compressed);
  AppLogger.instance.log(
    'Encoded payload: ${sessions.length} sessions, '
    '${emptyFolders.length} folders, '
    '${tags.length} tags, ${snippets.length} snippets, '
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
  Map<String, SshKeyEntry> managerKeyEntries = const {},
  List<Tag> tags = const [],
  List<ExportLink> sessionTags = const [],
  List<ExportFolderTagLink> folderTags = const [],
  List<Snippet> snippets = const [],
  List<ExportLink> sessionSnippets = const [],
}) {
  return encodeExportPayload(
    sessions,
    emptyFolders: emptyFolders,
    options: options,
    config: config,
    knownHostsContent: knownHostsContent,
    managerKeyEntries: managerKeyEntries,
    tags: tags,
    sessionTags: sessionTags,
    folderTags: folderTags,
    snippets: snippets,
    sessionSnippets: sessionSnippets,
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

    // Manager key metadata (v3+): shortId → {label, type, publicKey}
    final managerKeyMeta = <String, Map<String, dynamic>>{};
    if (json.containsKey('mk')) {
      final mk = json['mk'] as Map<String, dynamic>;
      for (final entry in mk.entries) {
        managerKeyMeta[entry.key] = entry.value as Map<String, dynamic>;
      }
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

    // Build SshKeyEntry list for manager keys
    final managerKeys = <SshKeyEntry>[];
    for (final entry in managerKeyMeta.entries) {
      final shortId = entry.key;
      final meta = entry.value;
      final keyData = keyMap[shortId];
      if (keyData == null) continue;
      managerKeys.add(
        SshKeyEntry(
          id: shortId,
          label: meta['l'] as String? ?? '',
          privateKey: keyData,
          publicKey: meta['p'] as String? ?? '',
          keyType: meta['t'] as String? ?? '',
          createdAt: DateTime.now(),
        ),
      );
    }

    AppConfig? config;
    if (json.containsKey('c')) {
      config = AppConfig.fromJson(json['c'] as Map<String, dynamic>);
    }
    String? knownHostsContent;
    if (json.containsKey('kh')) {
      knownHostsContent = json['kh'] as String?;
    }

    // Tags (v4+)
    final tags = <Tag>[];
    final sessionTagLinks = <ExportLink>[];
    final folderTagLinks = <ExportFolderTagLink>[];
    if (json.containsKey('tg')) {
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
    }

    // Snippets (v4+)
    final decodedSnippets = <Snippet>[];
    final sessionSnippetLinks = <ExportLink>[];
    if (json.containsKey('sn')) {
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
    }

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
