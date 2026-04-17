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
import '../../core/security/secret_buffer.dart';
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

  /// Header placed at the start of v2 encrypted archives so future releases
  /// can raise PBKDF2 iterations without breaking the reader.
  ///
  /// Layout:
  ///   [magic 'LFSE' 4] [version 1] [iterations u32 BE 4] [salt 32] [iv 12]
  ///   [ciphertext + GCM tag]
  ///
  /// Archives written before this header existed start straight with the
  /// 32-byte random salt (no detectable magic); those are treated as legacy
  /// v1 payloads and decrypted with [productionPbkdf2Iterations]. Unencrypted
  /// ZIP archives still expose the `PK\x03\x04` magic and are handled
  /// separately.
  static const List<int> _encHeaderMagic = [0x4C, 0x46, 0x53, 0x45]; // 'LFSE'
  static const int _encHeaderVersion = 1;
  static const int _encHeaderBaseLen =
      4 /* magic */ + 1 /* version */ + 4 /* iters */;

  /// Production PBKDF2-SHA256 iteration count. Public so tests that need a
  /// roundtrip with the real cost can reference it explicitly. Most tests
  /// pass a much lower value via the per-call [iterations] parameter.
  static const int productionPbkdf2Iterations = 600000;

  /// Default PBKDF2 iteration count when [export], [import_] or [preview]
  /// callers do not provide an explicit `iterations` parameter. Mutable so
  /// the test bootstrap (`flutter_test_config.dart`) can globally lower it
  /// for the whole suite without every test having to thread the value
  /// through. Production code never writes this field.
  @visibleForTesting
  static int defaultPbkdf2Iterations = productionPbkdf2Iterations;

  /// Maximum accepted encrypted archive size (50 MiB). Enforced before any
  /// decryption or decompression so a pathologically large file can't OOM
  /// the process — PBKDF2 + AES-GCM both hold the full plaintext in memory
  /// on mobile. Legitimate exports are dominated by session credentials and
  /// known_hosts; real archives run in the single-digit-MB range, so 50 MiB
  /// is generous for normal use but catches zip-bomb-scale inputs.
  static const int maxArchiveBytes = 50 * 1024 * 1024;

  /// Maximum total uncompressed payload accepted from any decoded ZIP
  /// (200 MiB). The outer file size is already capped by [maxArchiveBytes],
  /// but ZIP allows tiny compressed entries to declare wildly large
  /// uncompressed sizes (the classic zip-bomb pattern). After decoding the
  /// archive we sum every entry's `size` and refuse to continue if the
  /// total exceeds this cap, before any further processing reads the
  /// content into memory.
  ///
  /// Set to 4× the compressed cap so legitimate exports with high-ratio
  /// JSON content still fit, but anything pathological is rejected.
  static const int maxDecompressedBytes = 200 * 1024 * 1024;

  /// Walk every entry in [archive] and refuse if the cumulative declared
  /// uncompressed size exceeds [maxDecompressedBytes].
  ///
  /// Throws [LfsArchiveTooLargeException] (re-using the existing exception
  /// for "too big" so the UI surface stays consistent).
  @visibleForTesting
  static void enforceDecompressedSizeCap(Archive archive) {
    var total = 0;
    for (final entry in archive) {
      final size = entry.size;
      if (size < 0) continue; // negative sizes are not meaningful
      total += size;
      if (total > maxDecompressedBytes) {
        throw LfsArchiveTooLargeException(
          size: total,
          limit: maxDecompressedBytes,
        );
      }
    }
  }

  /// Maximum accepted decompressed known_hosts payload (10 MiB). The outer
  /// archive size is already bounded by [maxArchiveBytes], but a malicious
  /// or corrupted .lfs could still ship a tiny ZIP entry that decompresses
  /// to a runaway known_hosts blob — `KnownHostsManager.importFromString`
  /// processes it line-by-line on the UI isolate and would stall the app.
  /// 10 MiB comfortably covers any real fleet (~50k host keys at ~200 B
  /// per line) and rejects pathological inputs early.
  static const int maxKnownHostsBytes = 10 * 1024 * 1024;

  /// Detect an unencrypted `.lfs` (plain ZIP) by its local-file-header
  /// magic `PK\x03\x04`. Encrypted archives start with a random 32-byte
  /// salt, so a false positive is a ~2⁻³² lottery — and even then the
  /// ZIP decoder would reject the garbage.
  static bool isUnencryptedArchive(Uint8List data) {
    if (data.length < 4) return false;
    return data[0] == 0x50 &&
        data[1] == 0x4B &&
        data[2] == 0x03 &&
        data[3] == 0x04;
  }

  /// True when [data] starts with the `LFSE` magic — i.e. a v2+ encrypted
  /// archive that carries its PBKDF2 iteration count in a 9-byte header
  /// ahead of the salt.
  static bool _hasEncryptionHeader(Uint8List data) {
    if (data.length < _encHeaderBaseLen) return false;
    for (var i = 0; i < _encHeaderMagic.length; i++) {
      if (data[i] != _encHeaderMagic[i]) return false;
    }
    return true;
  }

  /// Hard ceiling on the iteration count we are willing to honour from an
  /// untrusted archive header. Anything above this is clamped to [maxImportIterations]
  /// — a hostile or corrupt archive could otherwise embed `0xFFFFFFFF` and
  /// hang PBKDF2 in the isolate for hours (DoS on import).
  ///
  /// The legitimate value for production archives is [productionPbkdf2Iterations]
  /// (currently 600 000); the cap is set 10× above that to leave headroom
  /// for future increases without a format flag day.
  @visibleForTesting
  static const int maxImportIterations = 6000000;

  /// Decode the iteration count from a v2 header. Assumes
  /// [_hasEncryptionHeader] already returned true on [data].
  ///
  /// Throws [LfsMalformedHeaderException] when the encoded value is zero
  /// (impossible to derive a key with zero rounds) or exceeds
  /// [maxImportIterations] (DoS guard against a hostile / corrupt header).
  static int _readHeaderIterations(Uint8List data) {
    final raw = (data[5] << 24) | (data[6] << 16) | (data[7] << 8) | data[8];
    if (raw <= 0 || raw > maxImportIterations) {
      throw LfsMalformedHeaderException(
        reason: 'iterations=$raw is outside [1, $maxImportIterations]',
      );
    }
    return raw;
  }

  /// Probe an `.lfs` candidate file and decide what the import flow
  /// should do with it before asking for a password.
  ///
  /// * ZIP magic + at least one of our marker entries → [LfsArchiveKind.unencryptedLfs]
  /// * ZIP magic but no marker entries (e.g. an `.apk` or unrelated archive
  ///   picked by mistake — SAF on Android ignores the `.lfs` extension
  ///   filter) → [LfsArchiveKind.notLfs]
  /// * Anything else (non-ZIP header) → [LfsArchiveKind.encryptedLfs];
  ///   definitive validation happens after decryption.
  ///
  /// Read/parse failures collapse to [LfsArchiveKind.notLfs] so the caller
  /// can show a single friendly rejection instead of surfacing an IO stack.
  static LfsArchiveKind probeArchive(String filePath) {
    try {
      final file = File(filePath);
      final Uint8List head;
      final raf = file.openSync();
      try {
        head = Uint8List(4);
        final read = raf.readIntoSync(head);
        if (read < 4) return LfsArchiveKind.notLfs;
      } finally {
        raf.closeSync();
      }
      if (!isUnencryptedArchive(head)) return LfsArchiveKind.encryptedLfs;

      // Plain ZIP — decode fully and look for our marker entries. APKs are
      // also ZIPs but carry none of these, so they get filtered out here.
      if (file.lengthSync() > maxArchiveBytes) return LfsArchiveKind.notLfs;
      final Archive archive;
      try {
        archive = ZipDecoder().decodeBytes(file.readAsBytesSync());
      } catch (_) {
        return LfsArchiveKind.notLfs;
      }
      // Probe is best-effort — a zip bomb here just means the file is not
      // recognised as one of ours; classify as notLfs and let the caller
      // surface a friendly rejection.
      try {
        enforceDecompressedSizeCap(archive);
      } on LfsArchiveTooLargeException {
        return LfsArchiveKind.notLfs;
      }
      const markers = [_manifestFile, _sessionsFile, _configFile, _keysFile];
      final isOurs = markers.any((name) => archive.findFile(name) != null);
      return isOurs ? LfsArchiveKind.unencryptedLfs : LfsArchiveKind.notLfs;
    } catch (e) {
      AppLogger.instance.log(
        'probeArchive failed — treating as notLfs',
        name: 'ExportImport',
        error: e,
      );
      return LfsArchiveKind.notLfs;
    }
  }

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

  /// Parse the sessions JSON entry. Each session is decoded inside an
  /// individual try/catch so a single malformed record (wrong type for
  /// `port`, missing required field, etc.) skips that one entry and logs
  /// the count instead of aborting the entire import.
  ///
  /// Returns `(parsedSessions, skippedCount)`.
  @visibleForTesting
  static (List<Session>, int) parseSessionsJson(String? json) {
    final maps = _decodeList(json);
    final out = <Session>[];
    var skipped = 0;
    for (final m in maps) {
      try {
        out.add(Session.fromJson(m));
      } catch (e) {
        skipped++;
        AppLogger.instance.log(
          'Skipped malformed session during import: $e',
          name: 'ExportImport',
        );
      }
    }
    return (out, skipped);
  }

  /// Parse the empty-folders JSON entry. Non-string entries are dropped
  /// rather than crashing the cast.
  @visibleForTesting
  static Set<String> parseEmptyFoldersJson(String? json) {
    if (json == null || json.isEmpty) return const {};
    try {
      final decoded = jsonDecode(json);
      if (decoded is! List) return const {};
      return decoded.whereType<String>().toSet();
    } catch (_) {
      return const {};
    }
  }

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
    int? iterations,
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

    // Empty password → write the raw ZIP unencrypted. The user has already
    // acknowledged the risk via the export dialog's confirmation step; the
    // file carries every saved credential in plain text.
    final Uint8List encrypted;
    if (masterPassword.isEmpty) {
      progress?.phase(l10n?.progressWritingArchive ?? 'Writing archive…');
      encrypted = zipBytes;
      AppLogger.instance.log(
        'Export: wrote unencrypted archive ${encrypted.length} bytes',
        name: 'ExportImport',
      );
    } else {
      // Encrypt with master password (runs in isolate — PBKDF2 is CPU-heavy).
      progress?.phase(l10n?.progressEncrypting ?? 'Encrypting…');
      // Capture iteration count in the main isolate so the value crosses the
      // Isolate boundary as a const, not via the global default that would
      // otherwise be re-read on the worker side.
      final iters = iterations ?? defaultPbkdf2Iterations;
      encrypted = await Isolate.run(
        () => _encryptWithPassword(zipBytes, masterPassword, iters),
      );
      AppLogger.instance.log(
        'Export: encrypted ${encrypted.length} bytes',
        name: 'ExportImport',
      );
    }

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
  /// 9-byte header + salt (32) + IV (12) + GCM tag (16) = 69 bytes.
  static int calculateLfsSize(LfsExportInput input) {
    final archive = _buildArchive(input);
    final zipBytes = Uint8List.fromList(ZipEncoder().encode(archive));
    return zipBytes.length + _encHeaderBaseLen + _saltLen + _ivLen + 16;
  }

  /// Decrypt an .lfs file and parse the archive contents.
  static Future<_ParsedArchive> _decryptAndParseArchive({
    required String filePath,
    required String masterPassword,
    ProgressReporter? progress,
    S? l10n,
    int? iterations,
  }) async {
    progress?.phase(l10n?.progressReadingArchive ?? 'Reading archive…');
    final file = File(filePath);
    final fileSize = await file.length();
    if (fileSize > maxArchiveBytes) {
      throw LfsArchiveTooLargeException(size: fileSize, limit: maxArchiveBytes);
    }
    final encData = await file.readAsBytes();

    // Detect unencrypted archive by the ZIP local-file-header magic
    // `PK\x03\x04` (0x50 0x4B 0x03 0x04). Encrypted archives start with a
    // random 32-byte salt, so the probability of a collision is 2^-32 and
    // the decoder would reject a false positive as malformed anyway.
    final Uint8List zipBytes;
    if (isUnencryptedArchive(encData)) {
      progress?.phase(l10n?.progressParsingArchive ?? 'Parsing archive…');
      zipBytes = encData;
    } else {
      progress?.phase(l10n?.progressDecrypting ?? 'Decrypting…');
      // Decrypt in isolate — PBKDF2 600k iterations is CPU-heavy.
      // GCM auth-tag failure (wrong password or tampered archive) surfaces as
      // InvalidCipherTextException from pointycastle. ZipDecoder will also
      // throw on successfully-decrypted-but-non-ZIP bytes (truncated file).
      // Both cases collapse to LfsDecryptionFailedException so the UI can show
      // a single localized message.
      final iters = iterations ?? defaultPbkdf2Iterations;
      try {
        zipBytes = await Isolate.run(
          () => _decryptWithPassword(encData, masterPassword, iters),
        );
      } catch (e) {
        throw LfsDecryptionFailedException(cause: e);
      }
    }
    progress?.phase(l10n?.progressParsingArchive ?? 'Parsing archive…');
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(zipBytes);
    } catch (e) {
      throw LfsDecryptionFailedException(cause: e);
    }
    // Zip-bomb guard: refuse before the manifest / session readers start
    // pulling entry bytes into memory.
    enforceDecompressedSizeCap(archive);

    final manifest = _parseManifest(archive);
    if (manifest.schemaVersion > currentSchemaVersion) {
      throw UnsupportedLfsVersionException(
        found: manifest.schemaVersion,
        supported: currentSchemaVersion,
      );
    }

    final (sessions, skippedSessions) = parseSessionsJson(
      _entryJson(archive.findFile(_sessionsFile)),
    );
    final emptyFolders = parseEmptyFoldersJson(
      _entryJson(archive.findFile(_emptyFoldersFile)),
    );

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
      '${sessions.length} sessions (skipped $skippedSessions), '
      '${managerKeys.length} keys, '
      '${tags.length} tags, ${snippetList.length} snippets, '
      '${emptyFolders.length} empty folders',
      name: 'ExportImport',
    );
    return _ParsedArchive(
      archive: archive,
      manifest: manifest,
      sessions: sessions,
      skippedSessions: skippedSessions,
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
    int? iterations,
  }) async {
    final parsed = await _decryptAndParseArchive(
      filePath: filePath,
      masterPassword: masterPassword,
      iterations: iterations,
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
      skippedSessions: parsed.skippedSessions,
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
    int? iterations,
  }) async {
    final parsed = await _decryptAndParseArchive(
      filePath: filePath,
      masterPassword: masterPassword,
      progress: progress,
      l10n: l10n,
      iterations: iterations,
    );

    final config = options.includeConfig
        ? _readConfigEntry(parsed.archive)
        : null;
    final knownHostsContent = options.includeKnownHosts
        ? _readKnownHostsEntry(parsed.archive)
        : null;

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
      skippedSessions: options.includeSessions ? parsed.skippedSessions : 0,
    );
  }

  /// Read and parse the optional `config.json` entry. Returns null if
  /// the archive doesn't carry one — callers decide what "no config"
  /// means for their mode.
  static AppConfig? _readConfigEntry(Archive archive) {
    final configFile = archive.findFile(_configFile);
    if (configFile == null) return null;
    final json = utf8.decode(configFile.content as List<int>);
    return AppConfig.fromJson(jsonDecode(json) as Map<String, dynamic>);
  }

  /// Read the optional `known_hosts` entry. Returns null when the
  /// archive doesn't carry one; throws [LfsKnownHostsTooLargeException]
  /// when it does but the decompressed blob exceeds the per-entry cap
  /// — caller must surface that as a localized error.
  static String? _readKnownHostsEntry(Archive archive) {
    final khFile = archive.findFile(_knownHostsFile);
    if (khFile == null) return null;
    final bytes = khFile.content as List<int>;
    if (bytes.length > maxKnownHostsBytes) {
      throw LfsKnownHostsTooLargeException(
        size: bytes.length,
        limit: maxKnownHostsBytes,
      );
    }
    return utf8.decode(bytes);
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
  /// Format: [magic 'LFSE' 4] [version 1] [iterations u32 BE 4]
  ///         [salt 32] [iv 12] [ciphertext + GCM tag]
  ///
  /// The header lets a newer reader pick up a future iteration bump without
  /// a format flag day — decrypt takes iterations from the file, not a
  /// hard-coded constant.
  static Uint8List _encryptWithPassword(
    Uint8List data,
    String password,
    int iterations,
  ) {
    final random = Random.secure();
    final salt = Uint8List.fromList(
      List.generate(_saltLen, (_) => random.nextInt(256)),
    );
    final iv = Uint8List.fromList(
      List.generate(_ivLen, (_) => random.nextInt(256)),
    );

    final keyBuf = _deriveKeyLocked(password, salt, iterations);
    try {
      final cipher = GCMBlockCipher(AESEngine())
        ..init(
          true,
          AEADParameters(KeyParameter(keyBuf.bytes), 128, iv, Uint8List(0)),
        );
      final output = cipher.process(data);
      final header = <int>[
        ..._encHeaderMagic,
        _encHeaderVersion,
        (iterations >> 24) & 0xFF,
        (iterations >> 16) & 0xFF,
        (iterations >> 8) & 0xFF,
        iterations & 0xFF,
      ];
      return Uint8List.fromList([...header, ...salt, ...iv, ...output]);
    } finally {
      keyBuf.dispose();
    }
  }

  /// Decrypt bytes with password-derived key.
  ///
  /// Accepts both the v2 header format (`LFSE…`) and the legacy salt-first
  /// layout. For the legacy case [iterations] is the fallback PBKDF2 cost
  /// (callers pass [defaultPbkdf2Iterations] — which equals
  /// [productionPbkdf2Iterations] in production). For v2 the header
  /// overrides [iterations] so an archive written with a different cost
  /// still decrypts correctly.
  static Uint8List _decryptWithPassword(
    Uint8List data,
    String password,
    int iterations,
  ) {
    final bytes = Uint8List.fromList(data);
    final int saltStart;
    final int effectiveIterations;
    if (_hasEncryptionHeader(bytes)) {
      effectiveIterations = _readHeaderIterations(bytes);
      saltStart = _encHeaderBaseLen;
    } else {
      effectiveIterations = iterations;
      saltStart = 0;
    }

    final salt = bytes.sublist(saltStart, saltStart + _saltLen);
    final ivStart = saltStart + _saltLen;
    final iv = bytes.sublist(ivStart, ivStart + _ivLen);
    final ciphertext = bytes.sublist(ivStart + _ivLen);

    final keyBuf = _deriveKeyLocked(password, salt, effectiveIterations);
    try {
      final cipher = GCMBlockCipher(AESEngine())
        ..init(
          false,
          AEADParameters(KeyParameter(keyBuf.bytes), 128, iv, Uint8List(0)),
        );
      return cipher.process(ciphertext);
    } finally {
      keyBuf.dispose();
    }
  }

  /// Derive a 256-bit key from password using PBKDF2-SHA256, copy it into a
  /// page-locked [SecretBuffer], and zero the intermediate Dart buffers.
  ///
  /// pointycastle's PBKDF2 returns a regular `Uint8List` on the Dart heap —
  /// impossible to fully erase (immutable String reuse, GC relocation), but
  /// we can at least wipe the bytes we control before dropping the ref. The
  /// caller then holds the key only via the native locked buffer, which the
  /// OS guarantees not to page out and we guarantee to zero on dispose.
  static SecretBuffer _deriveKeyLocked(
    String password,
    Uint8List salt,
    int iterations,
  ) {
    final passwordBytes = Uint8List.fromList(utf8.encode(password));
    final pbkdf2 = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(Pbkdf2Parameters(salt, iterations, 32));
    final derived = pbkdf2.process(passwordBytes);
    try {
      return SecretBuffer.fromBytes(derived);
    } finally {
      for (var i = 0; i < derived.length; i++) {
        derived[i] = 0;
      }
      for (var i = 0; i < passwordBytes.length; i++) {
        passwordBytes[i] = 0;
      }
    }
  }
}

/// Internal parsed archive result.
class _ParsedArchive {
  final Archive archive;
  final LfsManifest manifest;
  final List<Session> sessions;
  final int skippedSessions;
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
    this.skippedSessions = 0,
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

/// Classification of a file offered to the import flow. Produced by
/// [ExportImport.probeArchive] before any password is requested.
enum LfsArchiveKind {
  /// Plain ZIP carrying at least one LetsFLUTssh marker entry — import
  /// can proceed with an empty password.
  unencryptedLfs,

  /// Non-ZIP header — most likely an AES-GCM payload from our encryptor.
  /// The caller must still prompt for a password; final validation runs
  /// after decryption.
  encryptedLfs,

  /// File is readable but is not a LetsFLUTssh archive (wrong format, or
  /// an unrelated ZIP like an `.apk` picked by mistake on Android — SAF
  /// ignores the `allowedExtensions: ['lfs']` filter for unregistered
  /// MIME types).
  notLfs,
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

/// Thrown when the known_hosts entry inside a successfully decrypted .lfs
/// archive is larger than [ExportImport.maxKnownHostsBytes]. The line-by-line
/// importer would otherwise stall the UI on a multi-GB blob.
class LfsKnownHostsTooLargeException implements Exception {
  final int size;
  final int limit;
  const LfsKnownHostsTooLargeException({
    required this.size,
    required this.limit,
  });

  @override
  String toString() =>
      'LfsKnownHostsTooLargeException: known_hosts is $size bytes, '
      'limit is $limit';
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

/// The encrypted-archive header carried a value that we refuse to honour
/// (e.g. an iteration count of 0 or above [LfsExportImport.maxImportIterations]).
/// Importing would otherwise hang the isolate or crash on bad input.
class LfsMalformedHeaderException implements Exception {
  final String reason;
  const LfsMalformedHeaderException({required this.reason});

  @override
  String toString() => 'LfsMalformedHeaderException: $reason';
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

  /// Number of session entries that failed to parse (malformed JSON, type
  /// mismatch). Surfaced in the preview dialog and in the post-import toast
  /// so the user knows the archive contained corrupt records.
  final int skippedSessions;

  const LfsPreview({
    required this.sessions,
    this.hasConfig = false,
    this.hasKnownHosts = false,
    this.emptyFolders = const {},
    this.managerKeyCount = 0,
    this.tagCount = 0,
    this.snippetCount = 0,
    this.manifest = const LfsManifest.legacy(),
    this.skippedSessions = 0,
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

  /// Count of session JSON entries that failed to parse and were skipped
  /// during archive decoding. Propagated into [ImportSummary.skippedSessions]
  /// so the success toast can surface partial-recovery cases.
  final int skippedSessions;

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
    this.skippedSessions = 0,
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
      skippedSessions: skippedSessions,
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
