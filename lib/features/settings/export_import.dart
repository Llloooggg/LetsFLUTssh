import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:pointycastle/export.dart';

import '../../core/config/app_config.dart';
import '../../core/security/key_store.dart';
import '../../core/session/qr_codec.dart';
import '../../core/session/session.dart';
import '../../core/snippets/snippet.dart';
import '../../core/tags/tag.dart';
import '../../utils/logger.dart';

/// .lfs (LetsFLUTssh) archive format — ZIP encrypted with AES-256-GCM.
///
/// Structure inside ZIP:
///   sessions.json  — full session data WITH credentials
///   config.json    — app configuration
///   known_hosts    — TOFU host key database
///
/// The ZIP bytes are encrypted with AES-256-GCM using a key derived from
/// a master password via PBKDF2 (600k iterations, SHA-256).
class ExportImport {
  static const _saltLen = 32;
  static const _ivLen = 12;
  static const _pbkdf2Iterations = 600000;
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
  }) async {
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
    final encrypted = await Isolate.run(
      () => _encryptWithPassword(zipBytes, masterPassword),
    );
    AppLogger.instance.log(
      'Export: encrypted ${encrypted.length} bytes',
      name: 'ExportImport',
    );

    // Write to file
    final file = File(outputPath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(encrypted);

    return outputPath;
  }

  /// Build the ZIP archive in memory from [input].
  static Archive _buildArchive(LfsExportInput input) {
    final archive = Archive();
    _addSessions(archive, input);
    _addManagerKeys(archive, input);
    _addConfig(archive, input);
    _addKnownHosts(archive, input);
    _addTags(archive, input);
    _addSnippets(archive, input);
    return archive;
  }

  static void _addSessions(Archive archive, LfsExportInput input) {
    if (!input.options.includeSessions) return;
    final sessionsJson = const JsonEncoder.withIndent(
      '  ',
    ).convert(input.sessions.map((s) => s.toJsonWithCredentials()).toList());
    final sessionsBytes = utf8.encode(sessionsJson);
    archive.addFile(
      ArchiveFile(_sessionsFile, sessionsBytes.length, sessionsBytes),
    );

    if (input.emptyFolders.isNotEmpty) {
      final foldersJson = const JsonEncoder.withIndent(
        '  ',
      ).convert(input.emptyFolders.toList());
      final foldersBytes = utf8.encode(foldersJson);
      archive.addFile(
        ArchiveFile(_emptyFoldersFile, foldersBytes.length, foldersBytes),
      );
    }
  }

  static void _addManagerKeys(Archive archive, LfsExportInput input) {
    if (!input.options.hasManagerKeys || input.managerKeyEntries.isEmpty) {
      return;
    }
    final keysJson = const JsonEncoder.withIndent('  ').convert(
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
    final keysBytes = utf8.encode(keysJson);
    archive.addFile(ArchiveFile(_keysFile, keysBytes.length, keysBytes));
  }

  static void _addConfig(Archive archive, LfsExportInput input) {
    if (!input.options.includeConfig) return;
    final configJson = const JsonEncoder.withIndent(
      '  ',
    ).convert(input.config.toJson());
    final configBytes = utf8.encode(configJson);
    archive.addFile(ArchiveFile(_configFile, configBytes.length, configBytes));
  }

  static void _addKnownHosts(Archive archive, LfsExportInput input) {
    final kh = input.knownHostsContent;
    if (!input.options.includeKnownHosts || kh == null || kh.isEmpty) return;
    final khBytes = utf8.encode(kh);
    archive.addFile(ArchiveFile(_knownHostsFile, khBytes.length, khBytes));
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

  /// Decrypt an .lfs file and parse the archive contents.
  static Future<_ParsedArchive> _decryptAndParseArchive({
    required String filePath,
    required String masterPassword,
  }) async {
    final file = File(filePath);
    final encData = await file.readAsBytes();

    // Decrypt in isolate — PBKDF2 600k iterations is CPU-heavy
    final zipBytes = await Isolate.run(
      () => _decryptWithPassword(encData, masterPassword),
    );
    final archive = ZipDecoder().decodeBytes(zipBytes);

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

    List<SshKeyEntry> managerKeys = [];
    final keysFile = archive.findFile(_keysFile);
    if (keysFile != null) {
      final json = utf8.decode(keysFile.content as List<int>);
      final list = jsonDecode(json) as List;
      managerKeys = list.map((e) {
        final m = e as Map<String, dynamic>;
        return SshKeyEntry(
          id: m['id'] as String? ?? '',
          label: m['label'] as String? ?? '',
          privateKey: m['private_key'] as String? ?? '',
          publicKey: m['public_key'] as String? ?? '',
          keyType: m['key_type'] as String? ?? '',
          isGenerated: m['is_generated'] as bool? ?? false,
          createdAt:
              DateTime.tryParse(m['created_at'] as String? ?? '') ??
              DateTime.now(),
        );
      }).toList();
    }

    // Tags
    List<Tag> tags = [];
    final tagsFile = archive.findFile(_tagsFile);
    if (tagsFile != null) {
      final json = utf8.decode(tagsFile.content as List<int>);
      final list = jsonDecode(json) as List;
      tags = list.map((e) {
        final m = e as Map<String, dynamic>;
        return Tag(
          id: m['id'] as String? ?? '',
          name: m['name'] as String? ?? '',
          color: m['color'] as String?,
          createdAt:
              DateTime.tryParse(m['created_at'] as String? ?? '') ??
              DateTime.now(),
        );
      }).toList();
    }

    List<ExportLink> sessionTagLinks = [];
    final stFile = archive.findFile(_sessionTagsFile);
    if (stFile != null) {
      final json = utf8.decode(stFile.content as List<int>);
      final list = jsonDecode(json) as List;
      sessionTagLinks = list.map((e) {
        final m = e as Map<String, dynamic>;
        return ExportLink(
          sessionId: m['session_id'] as String? ?? '',
          targetId: m['tag_id'] as String? ?? '',
        );
      }).toList();
    }

    List<ExportFolderTagLink> folderTagLinks = [];
    final ftFile = archive.findFile(_folderTagsFile);
    if (ftFile != null) {
      final json = utf8.decode(ftFile.content as List<int>);
      final list = jsonDecode(json) as List;
      folderTagLinks = list.map((e) {
        final m = e as Map<String, dynamic>;
        return ExportFolderTagLink(
          folderPath: m['folder_path'] as String? ?? '',
          tagId: m['tag_id'] as String? ?? '',
        );
      }).toList();
    }

    // Snippets
    List<Snippet> snippetList = [];
    final snFile = archive.findFile(_snippetsFile);
    if (snFile != null) {
      final json = utf8.decode(snFile.content as List<int>);
      final list = jsonDecode(json) as List;
      snippetList = list.map((e) {
        final m = e as Map<String, dynamic>;
        return Snippet(
          id: m['id'] as String? ?? '',
          title: m['title'] as String? ?? '',
          command: m['command'] as String? ?? '',
          description: m['description'] as String? ?? '',
          createdAt:
              DateTime.tryParse(m['created_at'] as String? ?? '') ??
              DateTime.now(),
          updatedAt:
              DateTime.tryParse(m['updated_at'] as String? ?? '') ??
              DateTime.now(),
        );
      }).toList();
    }

    List<ExportLink> sessionSnippetLinks = [];
    final ssFile = archive.findFile(_sessionSnippetsFile);
    if (ssFile != null) {
      final json = utf8.decode(ssFile.content as List<int>);
      final list = jsonDecode(json) as List;
      sessionSnippetLinks = list.map((e) {
        final m = e as Map<String, dynamic>;
        return ExportLink(
          sessionId: m['session_id'] as String? ?? '',
          targetId: m['snippet_id'] as String? ?? '',
        );
      }).toList();
    }

    AppLogger.instance.log(
      'Import: decrypted ${encData.length} bytes, '
      '${sessions.length} sessions, ${managerKeys.length} keys, '
      '${tags.length} tags, ${snippetList.length} snippets, '
      '${emptyFolders.length} empty folders',
      name: 'ExportImport',
    );
    return _ParsedArchive(
      archive: archive,
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
  }) async {
    final parsed = await _decryptAndParseArchive(
      filePath: filePath,
      masterPassword: masterPassword,
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
    );
  }

  // --- Crypto helpers ---

  static void _addJsonFile(Archive archive, String name, List<dynamic> data) {
    final json = const JsonEncoder.withIndent('  ').convert(data);
    final bytes = utf8.encode(json);
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

/// Preview of .lfs archive contents.
class LfsPreview {
  final List<Session> sessions;
  final bool hasConfig;
  final bool hasKnownHosts;
  final Set<String> emptyFolders;
  final int managerKeyCount;
  final int tagCount;
  final int snippetCount;

  const LfsPreview({
    required this.sessions,
    this.hasConfig = false,
    this.hasKnownHosts = false,
    this.emptyFolders = const {},
    this.managerKeyCount = 0,
    this.tagCount = 0,
    this.snippetCount = 0,
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
  });
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
  });
}
