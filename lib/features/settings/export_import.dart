import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:pointycastle/export.dart';

import '../../core/config/app_config.dart';
import '../../core/progress/progress_reporter.dart';
import '../../core/security/key_store.dart';
import '../../core/session/qr_codec.dart';
import '../../core/session/session.dart';
import '../../core/snippets/snippet.dart';
import '../../core/tags/tag.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/logger.dart';

/// .lfs (LetsFLUTssh) archive format — ZIP encrypted with AES-256-GCM.
///
/// Structure inside ZIP:
///   manifest.json  — schema + app version, created_at (see [currentSchemaVersion])
///   sessions.json  — full session data WITH credentials
///   config.json    — app configuration
///   known_hosts    — TOFU host key database
///
/// The ZIP bytes are encrypted with AES-256-GCM using a key derived from
/// a master password via PBKDF2 (600k iterations, SHA-256). GCM's auth tag
/// already protects archive integrity end-to-end, so the manifest carries
/// metadata only — no redundant content hash.
class ExportImport {
  /// Current .lfs schema version. Bump on format-breaking changes.
  ///
  /// - v1 (2026-04): initial manifest introduction. Archives without a
  ///   manifest are treated as legacy v1 for backward compatibility.
  static const int currentSchemaVersion = 1;

  static const _saltLen = 32;
  static const _ivLen = 12;
  static const _pbkdf2Iterations = 600000;

  /// Maximum accepted encrypted archive size (50 MiB). Enforced before any
  /// decryption or decompression so a pathologically large file can't OOM
  /// the process — PBKDF2 + AES-GCM both hold the full plaintext in memory
  /// on mobile. Legitimate exports are dominated by session credentials and
  /// known_hosts; real archives run in the single-digit-MB range, so 50 MiB
  /// is generous for normal use but catches zip-bomb-scale inputs.
  static const int maxArchiveBytes = 50 * 1024 * 1024;
  static const _manifestFile = 'manifest.json';
  static const _sessionsFile = 'sessions.json';
  static const _keysFile = 'keys.json';
  static const _emptyFoldersFile = 'empty_folders.json';
  static const _configFile = 'config.json';
  static const _knownHostsFile = 'known_hosts';
  static const _tagsFile = 'tags.json';
  static const _sessionTagsFile = 'session_tags.json';
  static const _folderTagsFile = 'folder_tags.json';
  static const _snippetsFile = 'snippets.json';
  static const _sessionSnippetsFile = 'session_snippets.json';

  // ─── Per-entry JSON parsers ─────────────────────────────────────────────
  // Extracted for testability / fuzzing. Each parser accepts a raw JSON
  // string (as stored inside the archive) and returns an empty list when
  // the JSON is null, malformed, or not a list. Individual entries that
  // fail to parse are skipped rather than aborting the whole import.

  static String? _entryJson(ArchiveFile? file) {
    if (file == null) return null;
    try {
      return utf8.decode(file.content as List<int>);
    } catch (_) {
      return null;
    }
  }

  static List<Map<String, dynamic>> _decodeList(String? json) {
    if (json == null || json.isEmpty) return const [];
    try {
      final decoded = jsonDecode(json);
      if (decoded is! List) return const [];
      return decoded.whereType<Map<String, dynamic>>().toList();
    } catch (_) {
      return const [];
    }
  }

  static DateTime _parseDate(Object? raw) {
    if (raw is String) {
      final parsed = DateTime.tryParse(raw);
      if (parsed != null) return parsed;
    }
    return DateTime.now();
  }

  static String _asString(Object? raw) => raw is String ? raw : '';

  @visibleForTesting
  static List<SshKeyEntry> parseKeysJson(String? json) {
    return _decodeList(json)
        .map(
          (m) => SshKeyEntry(
            id: _asString(m['id']),
            label: _asString(m['label']),
            privateKey: _asString(m['private_key']),
            publicKey: _asString(m['public_key']),
            keyType: _asString(m['key_type']),
            isGenerated: m['is_generated'] is bool
                ? m['is_generated'] as bool
                : false,
            createdAt: _parseDate(m['created_at']),
          ),
        )
        .toList();
  }

  @visibleForTesting
  static List<Tag> parseTagsJson(String? json) {
    return _decodeList(json)
        .map(
          (m) => Tag(
            id: _asString(m['id']),
            name: _asString(m['name']),
            color: m['color'] is String ? m['color'] as String : null,
            createdAt: _parseDate(m['created_at']),
          ),
        )
        .toList();
  }

  @visibleForTesting
  static List<Snippet> parseSnippetsJson(String? json) {
    return _decodeList(json)
        .map(
          (m) => Snippet(
            id: _asString(m['id']),
            title: _asString(m['title']),
            command: _asString(m['command']),
            description: _asString(m['description']),
            createdAt: _parseDate(m['created_at']),
            updatedAt: _parseDate(m['updated_at']),
          ),
        )
        .toList();
  }

  /// Parse session→target links. [targetKey] is `'tag_id'` for session-tag
  /// links or `'snippet_id'` for session-snippet links.
  @visibleForTesting
  static List<ExportLink> parseLinksJson(
    String? json, {
    required String targetKey,
  }) {
    return _decodeList(json)
        .map(
          (m) => ExportLink(
            sessionId: _asString(m['session_id']),
            targetId: _asString(m[targetKey]),
          ),
        )
        .toList();
  }

  @visibleForTesting
  static List<ExportFolderTagLink> parseFolderTagLinksJson(String? json) {
    return _decodeList(json)
        .map(
          (m) => ExportFolderTagLink(
            folderPath: _asString(m['folder_path']),
            tagId: _asString(m['tag_id']),
          ),
        )
        .toList();
  }

  /// Export app data to an encrypted .lfs file.
  ///
  /// [input] groups sessions/config/tags/etc inputs. See [LfsExportInput].
  /// [input.knownHostsContent] is the decrypted known_hosts text (from
  /// [KnownHostsManager.exportToString]). Pass null to omit known_hosts.
  ///
  /// Returns the file path of the created archive.
  static Future<String> export({
    required String masterPassword,
    required LfsExportInput input,
    required String outputPath,
    ProgressReporter? progress,
    S? l10n,
  }) async {
    progress?.phase(l10n?.progressCollectingData ?? 'Collecting data…');
    final archive = _buildArchive(input);

    // Encode ZIP
    final zipBytes = Uint8List.fromList(ZipEncoder().encode(archive));
    AppLogger.instance.log(
      'Export: ZIP archive ${zipBytes.length} bytes, '
      '${input.sessions.length} sessions, '
      'config=${input.options.includeConfig}, '
      'knownHosts='
      '${input.options.includeKnownHosts && input.knownHostsContent != null}',
      name: 'ExportImport',
    );

    // Encrypt with master password (runs in isolate — PBKDF2 600k is CPU-heavy)
    progress?.phase(l10n?.progressEncrypting ?? 'Encrypting…');
    final encrypted = await Isolate.run(
      () => _encryptWithPassword(zipBytes, masterPassword),
    );
    AppLogger.instance.log(
      'Export: encrypted ${encrypted.length} bytes',
      name: 'ExportImport',
    );

    // Write atomically: flush to "<outputPath>.tmp", then rename. If the write
    // fails mid-way (I/O error, out of space, process killed), we don't leave
    // a half-formed .lfs next to a usable old one — users could pick it up,
    // type the master password, and get a decrypt error. rename(2) is atomic
    // on a single filesystem; on mobile/SAF the temp sits in the same dir so
    // this holds.
    progress?.phase(l10n?.progressWritingArchive ?? 'Writing archive…');
    final file = File(outputPath);
    await file.parent.create(recursive: true);
    final tmp = File('$outputPath.tmp');
    try {
      await tmp.writeAsBytes(encrypted, flush: true);
      await tmp.rename(outputPath);
    } catch (e) {
      if (await tmp.exists()) {
        try {
          await tmp.delete();
        } catch (_) {
          // Best-effort cleanup; original error is what the user needs.
        }
      }
      rethrow;
    }

    return outputPath;
  }

  /// Build the ZIP archive in memory from [input].
  static Archive _buildArchive(LfsExportInput input) {
    final archive = Archive();
    _addManifest(archive, input);
    _addSessions(archive, input);
    _addManagerKeys(archive, input);
    _addConfig(archive, input);
    _addKnownHosts(archive, input);
    _addTags(archive, input);
    _addSnippets(archive, input);
    return archive;
  }

  static void _addManifest(Archive archive, LfsExportInput input) {
    final manifest = <String, dynamic>{
      'schema_version': currentSchemaVersion,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    };
    final appVersion = input.appVersion;
    if (appVersion != null && appVersion.isNotEmpty) {
      manifest['app_version'] = appVersion;
    }
    _addRawJson(archive, _manifestFile, manifest);
  }

  static void _addSessions(Archive archive, LfsExportInput input) {
    if (!input.options.includeSessions) return;
    _addJsonFile(
      archive,
      _sessionsFile,
      input.sessions.map((s) => s.toJsonWithCredentials()).toList(),
    );
    if (input.emptyFolders.isNotEmpty) {
      _addJsonFile(archive, _emptyFoldersFile, input.emptyFolders.toList());
    }
  }

  static void _addManagerKeys(Archive archive, LfsExportInput input) {
    if (!input.options.hasManagerKeys || input.managerKeyEntries.isEmpty) {
      return;
    }
    _addJsonFile(
      archive,
      _keysFile,
      input.managerKeyEntries
          .map(
            (e) => {
              'id': e.id,
              'label': e.label,
              'private_key': e.privateKey,
              'public_key': e.publicKey,
              'key_type': e.keyType,
              'is_generated': e.isGenerated,
              'created_at': e.createdAt.toIso8601String(),
            },
          )
          .toList(),
    );
  }

  static void _addConfig(Archive archive, LfsExportInput input) {
    if (!input.options.includeConfig) return;
    _addRawJson(archive, _configFile, input.config.toJson());
  }

  static void _addKnownHosts(Archive archive, LfsExportInput input) {
    final kh = input.knownHostsContent;
    if (!input.options.includeKnownHosts || kh == null || kh.isEmpty) return;
    _addTextFile(archive, _knownHostsFile, kh);
  }

  static void _addTags(Archive archive, LfsExportInput input) {
    if (!input.options.includeTags || input.tags.isEmpty) return;
    _addJsonFile(
      archive,
      _tagsFile,
      input.tags
          .map(
            (t) => {
              'id': t.id,
              'name': t.name,
              'color': t.color,
              'created_at': t.createdAt.toIso8601String(),
            },
          )
          .toList(),
    );
    if (input.sessionTags.isNotEmpty) {
      _addJsonFile(
        archive,
        _sessionTagsFile,
        input.sessionTags
            .map((l) => {'session_id': l.sessionId, 'tag_id': l.targetId})
            .toList(),
      );
    }
    if (input.folderTags.isNotEmpty) {
      _addJsonFile(
        archive,
        _folderTagsFile,
        input.folderTags
            .map((l) => {'folder_path': l.folderPath, 'tag_id': l.tagId})
            .toList(),
      );
    }
  }

  static void _addSnippets(Archive archive, LfsExportInput input) {
    if (!input.options.includeSnippets || input.snippets.isEmpty) return;
    _addJsonFile(
      archive,
      _snippetsFile,
      input.snippets
          .map(
            (s) => {
              'id': s.id,
              'title': s.title,
              'command': s.command,
              'description': s.description,
              'created_at': s.createdAt.toIso8601String(),
              'updated_at': s.updatedAt.toIso8601String(),
            },
          )
          .toList(),
    );
    if (input.sessionSnippets.isNotEmpty) {
      _addJsonFile(
        archive,
        _sessionSnippetsFile,
        input.sessionSnippets
            .map((l) => {'session_id': l.sessionId, 'snippet_id': l.targetId})
            .toList(),
      );
    }
  }

  /// Estimate the final .lfs file size (bytes) for given inputs without
  /// actually writing to disk or running PBKDF2.
  ///
  /// Builds the ZIP archive in memory and adds fixed encryption overhead:
  /// salt (32) + IV (12) + GCM tag (16) = 60 bytes.
  static int calculateLfsSize(LfsExportInput input) {
    final archive = _buildArchive(input);
    final zipBytes = Uint8List.fromList(ZipEncoder().encode(archive));
    return zipBytes.length + _saltLen + _ivLen + 16;
  }

  /// Decrypt an .lfs file and parse the archive contents.
  static Future<_ParsedArchive> _decryptAndParseArchive({
    required String filePath,
    required String masterPassword,
    ProgressReporter? progress,
    S? l10n,
  }) async {
    progress?.phase(l10n?.progressReadingArchive ?? 'Reading archive…');
    final file = File(filePath);
    final fileSize = await file.length();
    if (fileSize > maxArchiveBytes) {
      throw LfsArchiveTooLargeException(size: fileSize, limit: maxArchiveBytes);
    }
    final encData = await file.readAsBytes();

    progress?.phase(l10n?.progressDecrypting ?? 'Decrypting…');
    // Decrypt in isolate — PBKDF2 600k iterations is CPU-heavy.
    // GCM auth-tag failure (wrong password or tampered archive) surfaces as
    // InvalidCipherTextException from pointycastle. ZipDecoder will also
    // throw on successfully-decrypted-but-non-ZIP bytes (truncated file).
    // Both cases collapse to LfsDecryptionFailedException so the UI can show
    // a single localized message.
    final Uint8List zipBytes;
    try {
      zipBytes = await Isolate.run(
        () => _decryptWithPassword(encData, masterPassword),
      );
    } catch (e) {
      throw LfsDecryptionFailedException(cause: e);
    }
    progress?.phase(l10n?.progressParsingArchive ?? 'Parsing archive…');
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(zipBytes);
    } catch (e) {
      throw LfsDecryptionFailedException(cause: e);
    }

    final manifest = _parseManifest(archive);
    if (manifest.schemaVersion > currentSchemaVersion) {
      throw UnsupportedLfsVersionException(
        found: manifest.schemaVersion,
        supported: currentSchemaVersion,
      );
    }

    List<Session> sessions = [];
    final sessionsFile = archive.findFile(_sessionsFile);
    if (sessionsFile != null) {
      final json = utf8.decode(sessionsFile.content as List<int>);
      final list = jsonDecode(json) as List;
      sessions = list
          .map((e) => Session.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    Set<String> emptyFolders = {};
    final foldersFile = archive.findFile(_emptyFoldersFile);
    if (foldersFile != null) {
      final json = utf8.decode(foldersFile.content as List<int>);
      final list = jsonDecode(json) as List;
      emptyFolders = list.cast<String>().toSet();
    }

    final managerKeys = parseKeysJson(_entryJson(archive.findFile(_keysFile)));
    final tags = parseTagsJson(_entryJson(archive.findFile(_tagsFile)));
    final sessionTagLinks = parseLinksJson(
      _entryJson(archive.findFile(_sessionTagsFile)),
      targetKey: 'tag_id',
    );
    final folderTagLinks = parseFolderTagLinksJson(
      _entryJson(archive.findFile(_folderTagsFile)),
    );
    final snippetList = parseSnippetsJson(
      _entryJson(archive.findFile(_snippetsFile)),
    );
    final sessionSnippetLinks = parseLinksJson(
      _entryJson(archive.findFile(_sessionSnippetsFile)),
      targetKey: 'snippet_id',
    );

    AppLogger.instance.log(
      'Import: decrypted ${encData.length} bytes, '
      '${sessions.length} sessions, ${managerKeys.length} keys, '
      '${tags.length} tags, ${snippetList.length} snippets, '
      '${emptyFolders.length} empty folders',
      name: 'ExportImport',
    );
    return _ParsedArchive(
      archive: archive,
      manifest: manifest,
      sessions: sessions,
      emptyFolders: emptyFolders,
      managerKeys: managerKeys,
      tags: tags,
      sessionTags: sessionTagLinks,
      folderTags: folderTagLinks,
      snippets: snippetList,
      sessionSnippets: sessionSnippetLinks,
    );
  }

  /// Parse the manifest entry. Absence or malformed content is treated as a
  /// legacy v1 archive (no manifest was written before [currentSchemaVersion]
  /// introduction).
  static LfsManifest _parseManifest(Archive archive) {
    final file = archive.findFile(_manifestFile);
    if (file == null) return const LfsManifest.legacy();
    try {
      final json = utf8.decode(file.content as List<int>);
      final decoded = jsonDecode(json);
      if (decoded is! Map<String, dynamic>) return const LfsManifest.legacy();
      final versionRaw = decoded['schema_version'];
      final int schemaVersion;
      if (versionRaw is int) {
        schemaVersion = versionRaw;
      } else if (versionRaw is num) {
        schemaVersion = versionRaw.toInt();
      } else {
        schemaVersion = 1;
      }
      return LfsManifest(
        schemaVersion: schemaVersion,
        appVersion: decoded['app_version'] is String
            ? decoded['app_version'] as String
            : null,
        createdAt: decoded['created_at'] is String
            ? DateTime.tryParse(decoded['created_at'] as String)
            : null,
      );
    } catch (_) {
      return const LfsManifest.legacy();
    }
  }

  /// Preview contents of an .lfs archive without full import.
  static Future<LfsPreview> preview({
    required String filePath,
    required String masterPassword,
  }) async {
    final parsed = await _decryptAndParseArchive(
      filePath: filePath,
      masterPassword: masterPassword,
    );

    final hasConfig = parsed.archive.findFile(_configFile) != null;
    final hasKnownHosts = parsed.archive.findFile(_knownHostsFile) != null;

    return LfsPreview(
      sessions: parsed.sessions,
      hasConfig: hasConfig,
      hasKnownHosts: hasKnownHosts,
      emptyFolders: parsed.emptyFolders,
      managerKeyCount: parsed.managerKeys.length,
      tagCount: parsed.tags.length,
      snippetCount: parsed.snippets.length,
      manifest: parsed.manifest,
    );
  }

  /// Import data from an .lfs archive.
  ///
  /// [options] controls what data to import (only imports what's present).
  /// [mode] controls how sessions are merged:
  /// - `ImportMode.merge` — add new sessions, skip existing (by ID)
  /// - `ImportMode.replace` — replace all sessions with imported ones
  static Future<ImportResult> import_({
    required String filePath,
    required String masterPassword,
    required ImportMode mode,
    ExportOptions options = const ExportOptions(),
    ProgressReporter? progress,
    S? l10n,
  }) async {
    final parsed = await _decryptAndParseArchive(
      filePath: filePath,
      masterPassword: masterPassword,
      progress: progress,
      l10n: l10n,
    );

    // Parse config (only if requested and present)
    AppConfig? config;
    if (options.includeConfig) {
      final configFile = parsed.archive.findFile(_configFile);
      if (configFile != null) {
        final json = utf8.decode(configFile.content as List<int>);
        config = AppConfig.fromJson(jsonDecode(json) as Map<String, dynamic>);
      }
    }

    // Known hosts — return content only if requested
    String? knownHostsContent;
    if (options.includeKnownHosts) {
      final khFile = parsed.archive.findFile(_knownHostsFile);
      if (khFile != null) {
        knownHostsContent = utf8.decode(khFile.content as List<int>);
      }
    }

    return ImportResult(
      sessions: options.includeSessions ? parsed.sessions : [],
      emptyFolders: options.includeSessions ? parsed.emptyFolders : {},
      managerKeys: options.hasManagerKeys ? parsed.managerKeys : [],
      tags: options.includeTags ? parsed.tags : [],
      sessionTags: options.includeTags ? parsed.sessionTags : [],
      folderTags: options.includeTags ? parsed.folderTags : [],
      snippets: options.includeSnippets ? parsed.snippets : [],
      sessionSnippets: options.includeSnippets ? parsed.sessionSnippets : [],
      config: config,
      mode: mode,
      knownHostsContent: knownHostsContent,
      includeTags: options.includeTags,
      includeSnippets: options.includeSnippets,
      includeKnownHosts: options.includeKnownHosts,
    );
  }

  // --- Crypto helpers ---

  static void _addJsonFile(Archive archive, String name, List<dynamic> data) {
    _addRawJson(archive, name, data);
  }

  /// Encode any JSON-serializable value to pretty-printed UTF-8 bytes and
  /// attach it as an archive entry. Single entry point for every JSON entry
  /// in the archive so padding/indentation stays consistent.
  static void _addRawJson(Archive archive, String name, Object? data) {
    final json = const JsonEncoder.withIndent('  ').convert(data);
    _addTextFile(archive, name, json);
  }

  /// Attach a UTF-8 text blob as an archive entry (known_hosts is raw text,
  /// not JSON — this is the one place that path matters).
  static void _addTextFile(Archive archive, String name, String text) {
    final bytes = utf8.encode(text);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  /// Encrypt bytes with password-derived key (PBKDF2 + AES-256-GCM).
  /// Format: [salt (32)] [iv (12)] [ciphertext + GCM tag]
  static Uint8List _encryptWithPassword(Uint8List data, String password) {
    final random = Random.secure();
    final salt = Uint8List.fromList(
      List.generate(_saltLen, (_) => random.nextInt(256)),
    );
    final iv = Uint8List.fromList(
      List.generate(_ivLen, (_) => random.nextInt(256)),
    );

    final key = _deriveKey(password, salt);

    final cipher = GCMBlockCipher(AESEngine())
      ..init(true, AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)));

    final output = cipher.process(data);
    return Uint8List.fromList([...salt, ...iv, ...output]);
  }

  /// Decrypt bytes with password-derived key.
  static Uint8List _decryptWithPassword(Uint8List data, String password) {
    final salt = data.sublist(0, _saltLen);
    final iv = data.sublist(_saltLen, _saltLen + _ivLen);
    final ciphertext = data.sublist(_saltLen + _ivLen);

    final key = _deriveKey(password, salt);

    final cipher = GCMBlockCipher(AESEngine())
      ..init(false, AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)));

    return cipher.process(ciphertext);
  }

  /// Derive 256-bit key from password using PBKDF2-SHA256.
  static Uint8List _deriveKey(String password, Uint8List salt) {
    final pbkdf2 = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(Pbkdf2Parameters(salt, _pbkdf2Iterations, 32));

    return pbkdf2.process(Uint8List.fromList(utf8.encode(password)));
  }
}

/// Internal parsed archive result.
class _ParsedArchive {
  final Archive archive;
  final LfsManifest manifest;
  final List<Session> sessions;
  final Set<String> emptyFolders;
  final List<SshKeyEntry> managerKeys;
  final List<Tag> tags;
  final List<ExportLink> sessionTags;
  final List<ExportFolderTagLink> folderTags;
  final List<Snippet> snippets;
  final List<ExportLink> sessionSnippets;

  const _ParsedArchive({
    required this.archive,
    required this.manifest,
    required this.sessions,
    required this.emptyFolders,
    required this.managerKeys,
    this.tags = const [],
    this.sessionTags = const [],
    this.folderTags = const [],
    this.snippets = const [],
    this.sessionSnippets = const [],
  });
}

/// Manifest metadata parsed from the archive.
class LfsManifest {
  final int schemaVersion;
  final String? appVersion;
  final DateTime? createdAt;

  const LfsManifest({
    required this.schemaVersion,
    this.appVersion,
    this.createdAt,
  });

  /// Constructs a sentinel manifest for legacy archives (pre-manifest).
  const LfsManifest.legacy()
    : schemaVersion = 1,
      appVersion = null,
      createdAt = null;
}

/// Thrown when an .lfs archive was written by a newer app version with a
/// schema this build does not understand. The archive is not decrypted past
/// the manifest to avoid corrupting state from unknown fields.
class UnsupportedLfsVersionException implements Exception {
  final int found;
  final int supported;
  const UnsupportedLfsVersionException({
    required this.found,
    required this.supported,
  });

  @override
  String toString() =>
      'UnsupportedLfsVersionException: archive schema v$found is newer '
      'than supported v$supported. Update the app to import this file.';
}

/// Thrown before decryption when the on-disk archive is larger than
/// [ExportImport.maxArchiveBytes]. The UI should show a localized message
/// telling the user the archive was rejected without attempting to decrypt.
class LfsArchiveTooLargeException implements Exception {
  final int size;
  final int limit;
  const LfsArchiveTooLargeException({required this.size, required this.limit});

  @override
  String toString() =>
      'LfsArchiveTooLargeException: archive is $size bytes, limit is $limit';
}

/// Thrown when decrypting/unpacking an .lfs archive fails — either because
/// the master password is wrong (GCM auth-tag mismatch) or the archive was
/// truncated/corrupted after encryption. Callers should show a generic
/// "wrong password or corrupted file" message and let the user retry.
class LfsDecryptionFailedException implements Exception {
  final Object? cause;
  const LfsDecryptionFailedException({this.cause});

  @override
  String toString() => 'LfsDecryptionFailedException';
}

/// Preview of .lfs archive contents.
class LfsPreview {
  final List<Session> sessions;
  final bool hasConfig;
  final bool hasKnownHosts;
  final Set<String> emptyFolders;
  final int managerKeyCount;
  final int tagCount;
  final int snippetCount;
  final LfsManifest manifest;

  const LfsPreview({
    required this.sessions,
    this.hasConfig = false,
    this.hasKnownHosts = false,
    this.emptyFolders = const {},
    this.managerKeyCount = 0,
    this.tagCount = 0,
    this.snippetCount = 0,
    this.manifest = const LfsManifest.legacy(),
  });

  bool get hasSessions => sessions.isNotEmpty;
  int get emptyFoldersCount => emptyFolders.length;
}

/// Import mode for sessions.
enum ImportMode { merge, replace }

/// Result of importing an .lfs archive.
class ImportResult {
  final List<Session> sessions;
  final Set<String> emptyFolders;
  final List<SshKeyEntry> managerKeys;
  final List<Tag> tags;
  final List<ExportLink> sessionTags;
  final List<ExportFolderTagLink> folderTags;
  final List<Snippet> snippets;
  final List<ExportLink> sessionSnippets;
  final AppConfig? config;
  final ImportMode mode;
  final String? knownHostsContent;

  /// User-intent flags from the preview dialog. In replace mode these decide
  /// whether the corresponding local data gets wiped even when the archive
  /// carries zero entries of that type (checkbox checked → "overwrite with
  /// nothing"). In merge mode they are informational only — the data lists
  /// already reflect the filter.
  final bool includeTags;
  final bool includeSnippets;
  final bool includeKnownHosts;

  const ImportResult({
    required this.sessions,
    this.emptyFolders = const {},
    this.managerKeys = const [],
    this.tags = const [],
    this.sessionTags = const [],
    this.folderTags = const [],
    this.snippets = const [],
    this.sessionSnippets = const [],
    this.config,
    required this.mode,
    this.knownHostsContent,
    this.includeTags = false,
    this.includeSnippets = false,
    this.includeKnownHosts = false,
  });

  /// Returns a copy of this result filtered by [options], with the given
  /// [mode].
  ///
  /// When `includeSessions` is false, session-dependent collections
  /// (emptyFolders, managerKeys, sessionTags, folderTags, sessionSnippets)
  /// are also dropped, since they are FK-referenced by sessions and cannot
  /// be imported on their own. Standalone tags/snippets remain controllable
  /// via their own flags.
  ImportResult filtered(ExportOptions options, ImportMode mode) {
    final wantSessions = options.includeSessions;
    return ImportResult(
      sessions: wantSessions ? sessions : const [],
      emptyFolders: wantSessions ? emptyFolders : const {},
      managerKeys: wantSessions && options.includeManagerKeys
          ? managerKeys
          : const [],
      tags: options.includeTags ? tags : const [],
      sessionTags: wantSessions && options.includeTags ? sessionTags : const [],
      folderTags: wantSessions && options.includeTags ? folderTags : const [],
      snippets: options.includeSnippets ? snippets : const [],
      sessionSnippets: wantSessions && options.includeSnippets
          ? sessionSnippets
          : const [],
      config: options.includeConfig ? config : null,
      mode: mode,
      knownHostsContent: options.includeKnownHosts ? knownHostsContent : null,
      includeTags: options.includeTags,
      includeSnippets: options.includeSnippets,
      includeKnownHosts: options.includeKnownHosts,
    );
  }
}

/// Bundle of inputs for [ExportImport.export]. Groups related optional
/// parameters so the public signature stays small.
class LfsExportInput {
  final List<Session> sessions;
  final AppConfig config;
  final ExportOptions options;
  final Set<String> emptyFolders;
  final String? knownHostsContent;
  final List<SshKeyEntry> managerKeyEntries;
  final List<Tag> tags;
  final List<ExportLink> sessionTags;
  final List<ExportFolderTagLink> folderTags;
  final List<Snippet> snippets;
  final List<ExportLink> sessionSnippets;

  /// App version string recorded in the manifest (diagnostic only).
  final String? appVersion;

  const LfsExportInput({
    required this.sessions,
    required this.config,
    this.options = const ExportOptions(),
    this.emptyFolders = const {},
    this.knownHostsContent,
    this.managerKeyEntries = const [],
    this.tags = const [],
    this.sessionTags = const [],
    this.folderTags = const [],
    this.snippets = const [],
    this.sessionSnippets = const [],
    this.appVersion,
  });
}
