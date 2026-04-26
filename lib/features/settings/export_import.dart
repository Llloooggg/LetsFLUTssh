import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';

import '../../core/config/app_config.dart';
import '../../core/progress/progress_reporter.dart';
import '../../core/security/kdf_params.dart';
import '../../core/security/key_store.dart';
import '../../core/session/qr_codec.dart';
import '../../core/session/session.dart';
import '../../core/snippets/snippet.dart';
import '../../core/tags/tag.dart';
import '../../l10n/app_localizations.dart';
import '../../src/rust/api/archive.dart' as rust_archive;
import '../../src/rust/api/crypto.dart' as rust_crypto;
import '../../utils/logger.dart';

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
///
/// **Read path lives in Rust** — `lfs_core::archive::read_archive_to_pending`
/// + `apply_pending_import` handle decrypt + parse + apply. The Dart
/// half here only composes the export side and exposes `probeArchive`
/// for the SAF file-picker classification step.
class ExportImport {
  /// Current .lfs schema version. Bump on format-breaking changes;
  /// every bump ships a corresponding archive migration in
  /// `lfs_core::migration`. Mirrors `SchemaVersions::ARCHIVE` from
  /// `lfs_core::migration` by literal — the export composer moves
  /// fully Rust-side in a follow-up arc, at which point the
  /// duplication retires.
  static const int currentSchemaVersion = 1;

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

  /// Maximum accepted encrypted archive size (50 MiB). Used by the
  /// `probeArchive` classifier; the Rust read path enforces its own
  /// bounds during decrypt.
  static const int maxArchiveBytes = 50 * 1024 * 1024;

  /// Maximum total uncompressed payload accepted from any decoded ZIP
  /// (200 MiB). Used by `probeArchive` only — the Rust read path uses
  /// the same per-entry caps internally.
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

  /// Export app data to an encrypted `.lfs` file via the Rust
  /// orchestrator. Sessions / keys / tags / snippets / known-hosts
  /// are read from `lfs_core.db` inside Rust; only `config.json`
  /// (file-based) is passed across the FRB boundary as a JSON
  /// string. Plaintext credentials never round-trip through the
  /// Dart heap during export.
  ///
  /// Returns the file path of the created archive.
  static Future<String> exportViaRust({
    required String masterPassword,
    required String outputPath,
    required ExportOptions options,
    required List<String> selectedSessionIds,
    List<String> selectedEmptyFolders = const [],
    AppConfig? config,
    ProgressReporter? progress,
    S? l10n,
    KdfParams? kdfParams,
    String? appVersion,
  }) async {
    progress?.phase(l10n?.progressEncrypting ?? 'Encrypting…');
    final params = kdfParams ?? defaultKdfParams;
    final configJson = config != null
        ? jsonEncode(config.toJsonForExport())
        : '';
    final encrypted = await rust_archive.dbExportArchive(
      input: rust_archive.DbExportInput(
        options: rust_archive.DbExportOptions(
          includeSessions: options.includeSessions,
          includeKnownHosts: options.includeKnownHosts,
          includeConfig: options.includeConfig && config != null,
          includeTags: options.includeTags,
          includeSnippets: options.includeSnippets,
          includeAllManagerKeys: options.includeAllManagerKeys,
          hasManagerKeys: options.hasManagerKeys,
        ),
        selectedSessionIds: selectedSessionIds,
        selectedEmptyFolders: selectedEmptyFolders,
        configJson: configJson,
        schemaVersion: currentSchemaVersion,
        appVersion: appVersion,
        masterPassword: masterPassword,
        kdfMemoryKib: params.memoryKiB,
        kdfIterations: params.iterations,
        kdfParallelism: params.parallelism,
        createdAtMs: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    AppLogger.instance.log(
      'Export: Rust orchestrator produced ${encrypted.length} bytes',
      name: 'ExportImport',
    );

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

  /// Legacy in-Dart archive composer. Retained for the test suite
  /// (round-tripping `_buildArchive` against the Dart import path)
  /// and for callers that still need the explicit `LfsExportInput`
  /// shape. Production export goes through [exportViaRust] so
  /// plaintext credentials stay Rust-side.
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
      // _encryptWithPassword is async itself: KDF inside Isolate.run,
      // GCM via FRB on the root isolate. No outer Isolate.run.
      encrypted = await _encryptWithPassword(zipBytes, masterPassword, params);
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
  ///
  /// Argon2id KDF runs inside an [Isolate.run] (CPU + memory-heavy);
  /// AES-GCM lives in `lfs_core::crypto` and is awaited on the root
  /// isolate (FRB bindings are tied there). The derived key crosses
  /// the isolate boundary as a regular [Uint8List] — the SecretBuffer
  /// page-lock that used to wrap it does not survive an isolate hop,
  /// and dropping the isolate already releases its heap.
  static Future<Uint8List> _encryptWithPassword(
    Uint8List data,
    String password,
    KdfParams params,
  ) async {
    final random = Random.secure();
    final salt = Uint8List.fromList(
      List.generate(_saltLen, (_) => random.nextInt(256)),
    );
    final iv = Uint8List.fromList(
      List.generate(_ivLen, (_) => random.nextInt(256)),
    );

    final derivedKey = await _deriveArgon2idAsync(password, salt, params);
    try {
      final ct = await rust_crypto.cryptoAesGcmEncryptRaw(
        key: derivedKey,
        nonce: iv,
        plaintext: data,
        aad: Uint8List(0),
      );
      final paramsBytes = params.encode();
      final header = <int>[
        ..._encHeaderMagic,
        _encVersionArgon2id,
        ...paramsBytes,
      ];
      return Uint8List.fromList([...header, ...salt, ...iv, ...ct]);
    } finally {
      // Best-effort scrub. Dart Uint8List is mutable; overwriting the
      // bytes drops the only reference we control before GC reclaims.
      for (var i = 0; i < derivedKey.length; i++) {
        derivedKey[i] = 0;
      }
    }
  }

  /// Argon2id derivation via the Rust core's blocking pool.
  /// Returns plain bytes; caller scrubs the buffer after use.
  static Future<Uint8List> _deriveArgon2idAsync(
    String password,
    Uint8List salt,
    KdfParams params,
  ) async {
    final out = await rust_crypto.cryptoArgon2IdDerive(
      password: Uint8List.fromList(utf8.encode(password)),
      salt: salt,
      memoryKib: params.memoryKiB,
      iterations: params.iterations,
      parallelism: params.parallelism,
      length: 32,
    );
    return Uint8List.fromList(out);
  }

  /// Build an archive with an unknown version byte. Used only by tests
  /// that assert the rejection path — the header layout is well-formed
  /// but the version byte is not [_encVersionArgon2id], so the Rust
  /// reader rejects it before any cipher runs.
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

/// Manifest metadata returned by the Rust import preview.
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
/// archive is larger than the per-entry cap (10 MiB). The line-by-line
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

/// Thrown when the ZIP container inside a .lfs archive is incomplete.
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
/// (e.g. an Argon2id memory cost above the import cap, an iteration count
/// of 0, or a malformed KdfParams envelope). Importing would otherwise
/// hang the isolate or crash on bad input.
class LfsMalformedHeaderException implements Exception {
  final String reason;
  const LfsMalformedHeaderException({required this.reason});

  @override
  String toString() => 'LfsMalformedHeaderException: $reason';
}

/// Sanitised preview of an `.lfs` archive — produced by the Rust
/// reader (`dbImportOpen`) and surfaced in the LFS preview dialog.
/// Carries counts + non-secret labels only; the full payload (session
/// passwords, key PEM, …) stays Rust-side under a registry handle until
/// the apply step consumes it.
class LfsPreview {
  final int schemaVersion;
  final int sessionCount;
  final List<String> sessionLabels;
  final int managerKeyCount;
  final int tagCount;
  final int snippetCount;
  final int emptyFoldersCount;
  final bool hasConfig;
  final bool hasKnownHosts;
  final LfsManifest manifest;

  const LfsPreview({
    required this.schemaVersion,
    this.sessionCount = 0,
    this.sessionLabels = const [],
    this.managerKeyCount = 0,
    this.tagCount = 0,
    this.snippetCount = 0,
    this.emptyFoldersCount = 0,
    this.hasConfig = false,
    this.hasKnownHosts = false,
    this.manifest = LfsManifest.placeholder,
  });

  bool get hasSessions => sessionCount > 0;

  /// Build an [LfsPreview] from the FRB `DbImportPreview` mirror.
  factory LfsPreview.fromRust(rust_archive.DbImportPreview p) {
    return LfsPreview(
      schemaVersion: p.schemaVersion.toInt(),
      sessionCount: p.sessionCount.toInt(),
      sessionLabels: List<String>.unmodifiable(p.sessionLabels),
      managerKeyCount: p.managerKeyCount.toInt(),
      tagCount: p.tagCount.toInt(),
      snippetCount: p.snippetCount.toInt(),
      emptyFoldersCount: p.emptyFolderCount.toInt(),
      hasConfig: p.hasConfig,
      hasKnownHosts: p.hasKnownHosts,
      manifest: LfsManifest(schemaVersion: p.schemaVersion.toInt()),
    );
  }
}

/// Import mode for sessions.
enum ImportMode { merge, replace }

/// Result of importing data from a non-`.lfs` source (QR payload,
/// paste-link, OpenSSH config). `.lfs` archives bypass this struct
/// entirely — they decode straight into a Rust-side handle and apply
/// from there. Used by [applyResultViaRust] to stage the JSON envelope.
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
