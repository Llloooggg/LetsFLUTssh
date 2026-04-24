import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:pointycastle/export.dart';

import '../../core/config/app_config.dart';
import '../../core/migration/schema_versions.dart';
import '../../core/progress/progress_reporter.dart';
import '../../core/security/kdf_params.dart';
import '../../core/security/key_store.dart';
import '../../core/security/secret_buffer.dart';
import '../../core/session/qr_codec.dart';
import '../../core/session/session.dart';
import '../../core/snippets/snippet.dart';
import '../../core/tags/tag.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/logger.dart';
import '../../utils/platform.dart' as plat;

/// .lfs (LetsFLUTssh) archive format — ZIP encrypted with AES-256-GCM
/// under an Argon2id-derived key.
///
/// Structure inside ZIP:
///   manifest.json  — schema + app version, created_at (see [currentSchemaVersion])
///   sessions.json  — full session data WITH credentials
///   config.json    — app configuration
///   known_hosts    — TOFU host key database
///
/// Wire format:
///   `[LFSE 4][0x02 1][KdfParams N][salt 32][iv 12][ct+tag]`
///
/// GCM's auth tag protects archive integrity end-to-end, so the manifest
/// carries metadata only — no redundant content hash. v1 is the permanent
/// floor; any on-disk archive reporting a different `schema_version`, a
/// missing manifest, an unrecognised header byte, or no `LFSE` magic is
/// rejected with [UnsupportedLfsVersionException]. Future format changes
/// ship a [Migration] registered in `archive_registry.dart`.
class ExportImport {
  /// Current .lfs schema version. Bump on format-breaking changes; every
  /// bump ships a corresponding archive `Migration`. Sourced from
  /// [SchemaVersions.archive] so the migration framework and the archive
  /// share a single source of truth.
  static const int currentSchemaVersion = SchemaVersions.archive;

  static const _saltLen = 32;
  static const _ivLen = 12;

  /// Header magic + single supported version byte (Argon2id).
  static const List<int> _encHeaderMagic = [0x4C, 0x46, 0x53, 0x45]; // 'LFSE'
  static const int _encVersionArgon2id = 0x02;

  /// Upper bound on the fixed part of the Argon2id header
  /// (magic + version + KdfParams). Used by preflight size estimation;
  /// the actual length depends on KdfParams.encodedLength at write time.
  static const int _argon2idHeaderMaxLen = 4 + 1 + 16;

  /// Default Argon2id profile used when [export] is called without an
  /// explicit `kdfParams`. Mutable so the test bootstrap can drop cost
  /// to the Argon2id minimum, keeping the suite fast.
  @visibleForTesting
  static KdfParams defaultKdfParams = KdfParams.productionDefaults;

  /// Absolute ceiling on the Argon2id memory cost we are willing to
  /// honour from an untrusted archive header on desktop — 1 GiB. On
  /// desktop the OS accounts for memory generously (swap, working-set
  /// trimming, plenty of RAM on a 2025-era workstation) so Argon2id at
  /// 1 GiB decodes without OOM-killer risk; higher values fail the
  /// import as malformed so a hostile header still cannot pin the
  /// isolate into swap indefinitely. See [resolveMaxImportArgon2idMemoryKiB]
  /// for the mobile branch which uses a lower static floor.
  @visibleForTesting
  static const int maxImportArgon2idMemoryKiB = 1 * 1024 * 1024;

  /// Hard import-time memory ceiling on iOS / Android — 512 MiB.
  ///
  /// Rationale. `ProcessInfo.maxRss` is the current process peak,
  /// not total physical RAM, so the previous `maxRss * 4` proxy
  /// underestimated RAM on cold-start (tiny peak → tight cap →
  /// legitimate 30 MB `.lfs` imports rejected as malformed on a 6 GB
  /// phone) and overestimated it on long-running warm sessions with
  /// live SSH + open SFTP panels. Neither branch was tracking the
  /// real "can Argon2id decode this without tripping Android's
  /// low-memory killer" question.
  ///
  /// Dart does not expose a total-physical-RAM API, and pulling in a
  /// new method-channel plugin across 5 platforms solely for this
  /// single DoS bound is disproportionate. A flat 512 MiB floor
  /// meets the real constraint: it sits comfortably below the OOM
  /// threshold on every Android device the app supports (Android 8+
  /// baseline ≥ 2 GB RAM; 512 MiB is 25 %) and is still well inside
  /// the 1 GiB desktop ceiling so `resolveMax…` picks the correct
  /// branch by platform. Tests can still override via
  /// [debugMemoryProbeOverride].
  @visibleForTesting
  static const int mobileImportArgon2idMemoryKiB = 512 * 1024;

  /// Resolve the effective memory cap at import time by platform.
  /// Mobile → [mobileImportArgon2idMemoryKiB] (512 MiB). Desktop →
  /// [maxImportArgon2idMemoryKiB] (1 GiB). The injection point
  /// [debugMemoryProbeOverride] bypasses the platform branch entirely
  /// — set it to the KiB value the test wants honoured.
  static int resolveMaxImportArgon2idMemoryKiB() {
    final override = debugMemoryProbeOverride;
    if (override != null) return override;
    return plat.isMobilePlatform
        ? mobileImportArgon2idMemoryKiB
        : maxImportArgon2idMemoryKiB;
  }

  /// Injection point for tests — set to the KiB value the resolver
  /// should return so the mobile / desktop branch can be exercised
  /// deterministically without the platform gate.
  @visibleForTesting
  static int? debugMemoryProbeOverride;

  /// Upper bound on Argon2id iterations in an untrusted header. Argon2id
  /// is memory-heavy per pass; even a modest iteration count at 1 GiB
  /// takes minutes, so 20 is a generous cap above any legitimate value.
  @visibleForTesting
  static const int maxImportArgon2idIterations = 20;

  /// Upper bound on Argon2id parallelism. Going above physical core count
  /// is counter-productive and this cap prevents a malformed header from
  /// requesting thousands of lanes.
  @visibleForTesting
  static const int maxImportArgon2idParallelism = 16;

  /// Maximum accepted encrypted archive size (50 MiB). Enforced before any
  /// decryption or decompression so a pathologically large file can't OOM
  /// the process — Argon2id + AES-GCM both hold the full plaintext in memory
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

  /// Scan [zipBytes] from the tail for the End-of-Central-Directory
  /// signature (`PK\x05\x06`, `0x50 0x4B 0x05 0x06`). Returns false when
  /// the signature is not present in the last 64 KiB — the PKZip spec
  /// allows up to 64 KiB of ZIP comment after the signature, so a
  /// signature further back cannot be valid.
  static bool _hasEocdSignature(Uint8List zipBytes) {
    const eocdSig = [0x50, 0x4B, 0x05, 0x06];
    const maxCommentLen = 0xFFFF; // 64 KiB ZIP spec cap.
    final windowStart = zipBytes.length > maxCommentLen + 22
        ? zipBytes.length - maxCommentLen - 22
        : 0;
    for (var i = zipBytes.length - 4; i >= windowStart; i--) {
      if (zipBytes[i] == eocdSig[0] &&
          zipBytes[i + 1] == eocdSig[1] &&
          zipBytes[i + 2] == eocdSig[2] &&
          zipBytes[i + 3] == eocdSig[3]) {
        return true;
      }
    }
    return false;
  }

  /// Walk every entry in [archive] and force a read of its decompressed
  /// bytes. A truncated archive whose central directory survived but
  /// whose payload section was cut off (the common mid-transfer failure)
  /// decodes into an [Archive] object that only throws when an entry is
  /// actually read — pulling the bytes early lets us surface the
  /// truncation with a typed exception before any parser touches it.
  ///
  /// Throws [LfsArchiveTruncatedException].
  @visibleForTesting
  static void validateArchiveEntriesReadable(Archive archive) {
    for (final entry in archive) {
      if (!entry.isFile) continue;
      try {
        // Touching `.content` forces the decoder to decompress the
        // entry's payload; for truncated entries this throws.
        entry.content;
      } catch (e) {
        throw LfsArchiveTruncatedException(cause: e, entryName: entry.name);
      }
    }
  }

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

  /// True when [data] starts with the `LFSE` magic. Pre-magic archives
  /// are rejected as [UnsupportedLfsVersionException] in the decrypt
  /// path — this predicate just drives the version-byte lookup.
  static bool _hasEncryptionHeader(Uint8List data) {
    if (data.length < _encHeaderMagic.length + 1) return false;
    for (var i = 0; i < _encHeaderMagic.length; i++) {
      if (data[i] != _encHeaderMagic[i]) return false;
    }
    return true;
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
      } catch (e) {
        // Best-effort probe — malformed ZIP / APK / random bytes all
        // land here. Logging the reason saves a "why did import reject
        // my file?" round-trip with the user — a corrupted .lfs and an
        // .apk picked by mistake both surface as "notLfs" but have
        // different root causes.
        AppLogger.instance.log(
          'probeArchive: ZIP decode failed (file classified as notLfs): $e',
          name: 'ExportImport',
        );
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
    KdfParams? kdfParams,
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
      // Encrypt with master password (runs in isolate — Argon2id is
      // CPU + memory-heavy). Capture params in the main isolate so the
      // value crosses the Isolate boundary without the worker re-reading
      // the mutable global default.
      progress?.phase(l10n?.progressEncrypting ?? 'Encrypting…');
      final params = kdfParams ?? defaultKdfParams;
      encrypted = await Isolate.run(
        () => _encryptWithPassword(zipBytes, masterPassword, params),
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
    // `toJsonForExport()` strips per-machine security setup — the
    // archive carries portable user data only. Imports use the
    // local machine's existing `security` configuration regardless
    // of what the archive was originally exported from.
    _addRawJson(archive, _configFile, input.config.toJsonForExport());
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
  /// actually writing to disk or running the KDF.
  ///
  /// Adds fixed encryption overhead for the v3 Argon2id format: magic
  /// (4) + version (1) + KdfParams (≤ 16) + salt (32) + IV (12) + GCM
  /// tag (16) — padded to [_argon2idHeaderMaxLen] for the header part so
  /// the estimate holds even if the default KDF params change.
  static int calculateLfsSize(LfsExportInput input) {
    final archive = _buildArchive(input);
    final zipBytes = Uint8List.fromList(ZipEncoder().encode(archive));
    return zipBytes.length + _argon2idHeaderMaxLen + _saltLen + _ivLen + 16;
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
      // Decrypt in isolate — Argon2id is CPU + memory-heavy. GCM
      // auth-tag failure (wrong password or tampered archive) surfaces
      // as InvalidCipherTextException from pointycastle. ZipDecoder
      // will also throw on successfully-decrypted-but-non-ZIP bytes
      // (truncated file). Both cases collapse to
      // LfsDecryptionFailedException so the UI can show a single
      // localized message.
      try {
        zipBytes = await Isolate.run(
          () => _decryptWithPassword(encData, masterPassword),
        );
      } on LfsMalformedHeaderException {
        rethrow;
      } on UnsupportedLfsVersionException {
        rethrow;
      } catch (e) {
        throw LfsDecryptionFailedException(cause: e);
      }
    }
    progress?.phase(l10n?.progressParsingArchive ?? 'Parsing archive…');
    // EOCD guard: the ZipDecoder in the `archive` package is lenient
    // with truncated files — it scans forward from local file headers
    // instead of anchoring on the End-of-Central-Directory record, so a
    // ZIP whose tail (central directory + EOCD) has been cut off still
    // decodes into an `Archive` containing only the entries that
    // happened to survive. That collapses into a "manifest missing"
    // error deeper in the flow, which reads as "archive from the wrong
    // version" to the user. Scan for `PK\x05\x06` up front so
    // truncation surfaces with its own typed exception — it means
    // "archive is incomplete; re-download or re-export", not "wrong
    // password" or "unsupported version".
    if (!_hasEocdSignature(zipBytes)) {
      throw const LfsArchiveTruncatedException();
    }
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(zipBytes);
    } catch (e) {
      // A structurally broken ZIP that still carried EOCD but can't be
      // decoded in full shares the UI copy with a successful EOCD-less
      // truncation — either way the archive is incomplete.
      throw LfsArchiveTruncatedException(cause: e);
    }
    // Zip-bomb guard: refuse before the manifest / session readers start
    // pulling entry bytes into memory.
    enforceDecompressedSizeCap(archive);
    // Integrity guard: the ZipDecoder validates the central directory
    // record but not each entry's compressed payload — a file truncated
    // inside an entry's data section would still decode into an Archive
    // whose first `entry.content` access throws. Force-read every entry
    // up front so a truncation surfaces here with a typed exception
    // rather than deep inside one of the per-entry parsers.
    validateArchiveEntriesReadable(archive);

    final manifest = _parseManifest(archive);
    // Any schema_version that is not exactly [currentSchemaVersion]
    // (future OR past) is rejected — future archives can't be read by
    // this build, past archives fall below the v1 floor. Future format
    // bumps register migrations in archive_registry.dart.
    if (manifest.schemaVersion != currentSchemaVersion) {
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

  /// Parse the manifest entry. The manifest is mandatory — absence or
  /// malformed content throws [UnsupportedLfsVersionException] so the
  /// caller surfaces a clear "archive not recognised; re-export" error.
  /// `found: 0` is the sentinel for "manifest missing or unreadable".
  static LfsManifest _parseManifest(Archive archive) {
    final file = archive.findFile(_manifestFile);
    if (file == null) {
      throw const UnsupportedLfsVersionException(
        found: 0,
        supported: currentSchemaVersion,
      );
    }
    try {
      final json = utf8.decode(file.content as List<int>);
      final decoded = jsonDecode(json);
      if (decoded is! Map<String, dynamic>) {
        throw const UnsupportedLfsVersionException(
          found: 0,
          supported: currentSchemaVersion,
        );
      }
      final versionRaw = decoded['schema_version'];
      final int schemaVersion;
      if (versionRaw is int) {
        schemaVersion = versionRaw;
      } else if (versionRaw is num) {
        schemaVersion = versionRaw.toInt();
      } else {
        throw const UnsupportedLfsVersionException(
          found: 0,
          supported: currentSchemaVersion,
        );
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
    } on UnsupportedLfsVersionException {
      rethrow;
    } catch (e) {
      // Wrap every other manifest parse failure (malformed JSON,
      // unexpected type, truncated header) into the same
      // user-facing "unsupported version" path so the message stays
      // consistent. Log the original reason so a support trace can
      // distinguish "user has a newer build's archive" from "bytes
      // are corrupt".
      AppLogger.instance.log(
        'Manifest parse failed → reporting UnsupportedLfsVersionException: $e',
        name: 'ExportImport',
      );
      throw const UnsupportedLfsVersionException(
        found: 0,
        supported: currentSchemaVersion,
      );
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
  }) async {
    final parsed = await _decryptAndParseArchive(
      filePath: filePath,
      masterPassword: masterPassword,
      progress: progress,
      l10n: l10n,
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

  /// Encrypt bytes with an Argon2id-derived key (AES-256-GCM).
  /// Writes the v3 header: `[LFSE 4][0x02 1][KdfParams N][salt 32][iv 12][ct+tag]`.
  static Uint8List _encryptWithPassword(
    Uint8List data,
    String password,
    KdfParams params,
  ) {
    final random = Random.secure();
    final salt = Uint8List.fromList(
      List.generate(_saltLen, (_) => random.nextInt(256)),
    );
    final iv = Uint8List.fromList(
      List.generate(_ivLen, (_) => random.nextInt(256)),
    );

    final keyBuf = _deriveKeyLocked(password, salt, params);
    try {
      final cipher = GCMBlockCipher(AESEngine())
        ..init(
          true,
          AEADParameters(KeyParameter(keyBuf.bytes), 128, iv, Uint8List(0)),
        );
      final output = cipher.process(data);
      final paramsBytes = params.encode();
      final header = <int>[
        ..._encHeaderMagic,
        _encVersionArgon2id,
        ...paramsBytes,
      ];
      return Uint8List.fromList([...header, ...salt, ...iv, ...output]);
    } finally {
      keyBuf.dispose();
    }
  }

  /// Decrypt bytes with a password-derived key. Argon2id-only. Missing
  /// `LFSE` magic or a header version byte other than
  /// [_encVersionArgon2id] is rejected with
  /// [UnsupportedLfsVersionException].
  static Uint8List _decryptWithPassword(Uint8List data, String password) {
    final bytes = Uint8List.fromList(data);

    if (!_hasEncryptionHeader(bytes)) {
      throw const UnsupportedLfsVersionException(
        found: 0,
        supported: currentSchemaVersion,
      );
    }

    final version = bytes[_encHeaderMagic.length];
    if (version != _encVersionArgon2id) {
      throw UnsupportedLfsVersionException(
        found: version,
        supported: currentSchemaVersion,
      );
    }
    return _decryptArgon2id(bytes, password);
  }

  /// Decrypt a v3 Argon2id archive. Parses params from the header and
  /// enforces [maxImportArgon2idMemoryKiB] / [maxImportArgon2idIterations]
  /// / [maxImportArgon2idParallelism] DoS bounds before running the KDF.
  static Uint8List _decryptArgon2id(Uint8List bytes, String password) {
    final paramsStart = _encHeaderMagic.length + 1;
    if (bytes.length <= paramsStart) {
      throw const LfsMalformedHeaderException(
        reason: 'truncated Argon2id header',
      );
    }
    final KdfParams params;
    try {
      params = KdfParams.decode(Uint8List.sublistView(bytes, paramsStart));
    } on FormatException catch (e) {
      throw LfsMalformedHeaderException(reason: e.message);
    }
    final memoryCap = resolveMaxImportArgon2idMemoryKiB();
    if (params.memoryKiB > memoryCap ||
        params.iterations > maxImportArgon2idIterations ||
        params.parallelism > maxImportArgon2idParallelism) {
      throw LfsMalformedHeaderException(
        reason:
            'Argon2id params exceed import caps '
            '(m=${params.memoryKiB}, t=${params.iterations}, '
            'p=${params.parallelism})',
      );
    }
    final saltStart = paramsStart + params.encodedLength;
    if (bytes.length < saltStart + _saltLen + _ivLen) {
      throw const LfsMalformedHeaderException(
        reason: 'truncated Argon2id payload',
      );
    }
    final salt = bytes.sublist(saltStart, saltStart + _saltLen);
    final ivStart = saltStart + _saltLen;
    final iv = bytes.sublist(ivStart, ivStart + _ivLen);
    final ciphertext = bytes.sublist(ivStart + _ivLen);

    final keyBuf = _deriveKeyLocked(password, salt, params);
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

  /// Derive a 256-bit key, copy it into a page-locked [SecretBuffer], and
  /// zero the Dart-heap intermediate. Dispatches to the algorithm selected
  /// by [params]; for now only Argon2id is defined.
  static SecretBuffer _deriveKeyLocked(
    String password,
    Uint8List salt,
    KdfParams params,
  ) {
    switch (params.algorithm) {
      case KdfAlgorithm.argon2id:
        return _deriveArgon2idKeyLocked(password, salt, params);
    }
  }

  static SecretBuffer _deriveArgon2idKeyLocked(
    String password,
    Uint8List salt,
    KdfParams params,
  ) {
    final passwordBytes = Uint8List.fromList(utf8.encode(password));
    final argon2Params = Argon2Parameters(
      Argon2Parameters.ARGON2_id,
      salt,
      desiredKeyLength: 32,
      iterations: params.iterations,
      memory: params.memoryKiB,
      lanes: params.parallelism,
      version: Argon2Parameters.ARGON2_VERSION_13,
    );
    final generator = Argon2BytesGenerator()..init(argon2Params);
    final derived = Uint8List(32);
    generator.deriveKey(passwordBytes, 0, derived, 0);
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

  /// Build an archive with an unknown version byte. Used only by tests
  /// that assert the rejection path — the header layout is well-formed
  /// but the version byte is not [_encVersionArgon2id], so
  /// [_decryptWithPassword] rejects it before any cipher runs.
  @visibleForTesting
  static Uint8List encryptInvalidVersionForTesting(
    Uint8List data, {
    required int versionByte,
  }) {
    final random = Random.secure();
    final salt = Uint8List.fromList(
      List.generate(_saltLen, (_) => random.nextInt(256)),
    );
    final iv = Uint8List.fromList(
      List.generate(_ivLen, (_) => random.nextInt(256)),
    );
    return Uint8List.fromList([
      ..._encHeaderMagic,
      versionByte,
      ...salt,
      ...iv,
      ...data,
    ]);
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

  /// Placeholder manifest used by code paths that need a
  /// `LfsManifest` instance before the real one is parsed (e.g. the
  /// default value on `LfsPreview.manifest`). Always carries the
  /// current schema version and null metadata — never persisted.
  static const LfsManifest placeholder = LfsManifest(
    schemaVersion: ExportImport.currentSchemaVersion,
  );
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

/// Thrown when the ZIP container inside a .lfs archive is incomplete —
/// End-of-Central-Directory record is missing or corrupt, or an entry's
/// payload was cut off mid-stream (distinguishable at force-read time).
/// Typical cause: the file was copied before a download / SAF write
/// finished. UI should prompt the user to re-download or re-export
/// from the original device.
class LfsArchiveTruncatedException implements Exception {
  final Object? cause;
  final String? entryName;
  const LfsArchiveTruncatedException({this.cause, this.entryName});

  @override
  String toString() {
    final where = entryName == null ? '' : ' at entry "$entryName"';
    return 'LfsArchiveTruncatedException$where';
  }
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
    this.manifest = LfsManifest.placeholder,
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
