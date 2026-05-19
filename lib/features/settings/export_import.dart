import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../core/config/app_config.dart';
import '../../core/progress/progress_reporter.dart';
import '../../core/security/kdf_params.dart';
import '../../core/security/ssh_key.dart';
import '../../core/session/qr_codec.dart';
import '../../core/session/session.dart';
import '../../core/snippets/snippet.dart';
import '../../core/tags/tag.dart';
import '../../l10n/app_localizations.dart';
import '../../src/rust/api/archive.dart' as rust_archive;
import '../../src/rust/api/config.dart' as rust_config;
import '../../src/rust/api/migration.dart' as rust_migration;
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
  /// Current `.lfs` schema version. Bump on format-breaking changes;
  /// every bump ships a corresponding archive migration in
  /// `lfs_core::migration`. Reads
  /// `lfs_core::migration::SchemaVersions::ARCHIVE` through a sync
  /// FRB getter so the constant lives one place across the workspace.
  static int get currentSchemaVersion =>
      rust_migration.migrationArchiveTargetVersion();

  /// Default Argon2id profile used when [exportViaRust] is called
  /// without an explicit `kdfParams`. Routes through
  /// [KdfParams.productionDefaults] (mirrored from the canonical Rust
  /// constant at startup) by default; tests assign [overrideForTest]
  /// to drop cost to the Argon2id minimum, keeping the suite fast.
  static KdfParams get defaultKdfParams =>
      overrideForTest ?? KdfParams.productionDefaults;

  /// Test-only override for [defaultKdfParams]. Null in production —
  /// the getter falls through to [KdfParams.productionDefaults].
  @visibleForTesting
  static KdfParams? overrideForTest;

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
  ///
  /// Routes through `lfs_core::archive::probe::probe` — the ZIP decoder,
  /// size caps, and marker scan all live Rust-side so `package:archive`
  /// can retire from the Dart deps tree once every consumer migrates.
  /// Async because the Rust function runs on the blocking pool to keep
  /// the FRB worker thread free for parallel callers (Settings can fire
  /// the probe while a transfer driver is mid-loop).
  static Future<LfsArchiveKind> probeArchive(String filePath) async {
    try {
      final result = await rust_archive.dbArchiveProbe(path: filePath);
      switch (result) {
        case rust_archive.DbArchiveProbeKind.encryptedLfs:
          return LfsArchiveKind.encryptedLfs;
        case rust_archive.DbArchiveProbeKind.unencryptedLfs:
          return LfsArchiveKind.unencryptedLfs;
        case rust_archive.DbArchiveProbeKind.notLfs:
          return LfsArchiveKind.notLfs;
      }
    } catch (e) {
      AppLogger.instance.log(
        'probeArchive failed — treating as notLfs',
        name: 'ExportImport',
        error: e,
      );
      return LfsArchiveKind.notLfs;
    }
  }

  /// Export app data to an encrypted `.lfs` file via the Rust
  /// orchestrator. Sessions / keys / tags / snippets / known-hosts
  /// are read from `letsflutssh.db` inside Rust; only `config.json`
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
    // Strip per-host security + sync slots Rust-side via the typed
    // FRB shim so the Dart code never re-implements the strip-list.
    final configJson = config != null
        ? rust_config.configAppConfigStripForExportTyped(
            value: config.toTyped(),
          )
        : '';
    progress?.phase(l10n?.progressWritingArchive ?? 'Writing archive…');
    final byteCount = await rust_archive.dbExportArchive(
      input: rust_archive.DbExportInput(
        options: rust_archive.DbExportOptions(
          includeSessions: options.includeSessions,
          includeKnownHosts: options.includeKnownHosts,
          includeConfig: options.includeConfig && config != null,
          includeTags: options.includeTags,
          includeSnippets: options.includeSnippets,
          includeAllManagerKeys: options.includeAllManagerKeys,
          hasManagerKeys: options.hasManagerKeys,
          includeRecordings: options.includeRecordings,
        ),
        selectedSessionIds: selectedSessionIds,
        selectedEmptyFolders: selectedEmptyFolders,
        configJson: configJson,
        schemaVersion: currentSchemaVersion,
        appVersion: appVersion,
        masterPassword: Uint8List.fromList(utf8.encode(masterPassword)),
        kdfMemoryKib: params.memoryKiB,
        kdfIterations: params.iterations,
        kdfParallelism: params.parallelism,
        createdAtMs: DateTime.now().millisecondsSinceEpoch,
      ),
      outputPath: outputPath,
    );
    AppLogger.instance.log(
      'Export: Rust orchestrator wrote $byteCount bytes to $outputPath',
      name: 'ExportImport',
    );
    return outputPath;
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

  /// Placeholder manifest used as the default for
  /// [LfsPreview.manifest] when no real manifest is available yet.
  /// `schemaVersion: 0` is the "not parsed" sentinel — real archives
  /// always report `>= SchemaVersions::ARCHIVE`, so a code path that
  /// observes `0` here knows it received the default rather than a
  /// real manifest. Kept `const` so it can sit on a default-argument
  /// position; cannot reference `ExportImport.currentSchemaVersion`
  /// (now an FRB-backed getter) for that reason.
  static const LfsManifest placeholder = LfsManifest(schemaVersion: 0);
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
