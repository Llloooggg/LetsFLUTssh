import '../../features/settings/export_import.dart';
import '../../src/rust/api/openssh_config_import.dart' as rust_import;
import '../../src/rust/api/ssh_config.dart' as rust_ssh_config;
import '../../utils/platform.dart';
import '../security/ssh_key.dart';
import '../session/session.dart';
import '../ssh/ssh_config.dart';
import 'key_file_helper.dart';

/// Reader that returns PEM contents for a path, or null if unreadable /
/// not a private key. Retained as a typedef for the legacy
/// `ssh_dir_key_scanner` test seam — production no longer hands a
/// reader to the importer because the orchestrator lives Rust-side.
typedef PemKeyReader = Future<String?> Function(String path);

/// Result of preparing a config-file import — ready to pass to
/// [applyResultViaRust].
class OpenSshConfigImportPreview {
  final ImportResult result;

  /// Number of parsed host entries (before filtering).
  final int parsedHosts;

  /// Host aliases for which no usable key could be resolved — includes both
  /// the "file missing / unreadable" case and the "file exists but is
  /// passphrase-encrypted" case, because from the session's point of view the
  /// outcome is identical: the session is imported without a key. The UI
  /// surfaces this as a single "these hosts have no credentials" warning.
  final List<String> hostsWithMissingKeys;

  /// Subset of [hostsWithMissingKeys] where the IdentityFile was readable but
  /// rejected as a passphrase-protected key. Callers that want to surface a
  /// more specific "decrypt the key first" hint can read this field;
  /// everyone else can ignore it and rely on [hostsWithMissingKeys] alone.
  final List<String> hostsWithEncryptedKeys;

  const OpenSshConfigImportPreview({
    required this.result,
    required this.parsedHosts,
    this.hostsWithMissingKeys = const [],
    this.hostsWithEncryptedKeys = const [],
  });
}

/// Builds an [ImportResult] from an OpenSSH config file.
///
/// Pure: performs no storage writes, no UI. Wiring into the settings
/// screen (file picker, preview dialog, apply) happens elsewhere.
///
/// Production path is a single FRB call into
/// `lfs_core::import::openssh_config::build_preview`. The Rust
/// orchestrator owns: config parse + Include resolution + filesystem
/// reads + PEM import + fingerprint dedup + auth-type decision +
/// suspicious-path filter + UUID minting. The Dart side only wraps
/// the returned wire records into the existing `Session` /
/// `SshKeyEntry` / `ImportResult` Flutter-side models.
class OpenSshConfigImporter {
  /// Default `~/.ssh` base for relative `Include` directives. Mirrors
  /// the parser's default — overridable per call from tests that
  /// want to anchor against a tempdir instead of the real home.
  final String? baseDirOverride;

  OpenSshConfigImporter({this.baseDirOverride});

  /// Expand a leading `~` in [path] to the user's home directory.
  /// Paths without `~` pass through untouched. Routes through the
  /// Rust `openssh_config::expand_home` helper so future
  /// `lfs_cli` / `lfs_tauri` consumers see the same expansion.
  static String expandHome(String path) =>
      rust_import.opensshConfigExpandHome(path: path);

  /// Delegates to [KeyFileHelper.isSuspiciousPath]. Kept as a thin wrapper so
  /// existing callers / tests that reach for
  /// `OpenSshConfigImporter.isSuspiciousPath` keep working without pulling
  /// the helper import everywhere.
  static bool isSuspiciousPath(String path) =>
      KeyFileHelper.isSuspiciousPath(path);

  /// Build an import preview from raw config content.
  ///
  /// [folderLabel] is where imported sessions land — recommended to include
  /// the date so users can tell where hosts came from after the fact.
  Future<OpenSshConfigImportPreview> buildPreview({
    required String configContent,
    required String folderLabel,
    String keyLabelSuffix = '',
    ImportMode mode = ImportMode.merge,
  }) async {
    final baseDir = baseDirOverride ?? '$homeDirectory/.ssh';
    final raw = rust_import.opensshConfigBuildPreview(
      configContent: configContent,
      folderLabel: folderLabel,
      keyLabelSuffix: keyLabelSuffix,
      baseDir: baseDir,
      maxIncludeDepth: 8,
    );

    final sessions = raw.sessions.map(_toSession).toList(growable: false);
    final keys = raw.keys.map(_toSshKeyEntry).toList(growable: false);

    return OpenSshConfigImportPreview(
      result: ImportResult(
        sessions: sessions,
        managerKeys: keys,
        mode: mode,
        emptyFolders: sessions.isEmpty ? const {} : {folderLabel},
      ),
      parsedHosts: raw.parsedHosts,
      hostsWithMissingKeys: List.unmodifiable(raw.hostsWithMissingKeys),
      hostsWithEncryptedKeys: List.unmodifiable(raw.hostsWithEncryptedKeys),
    );
  }

  Session _toSession(rust_import.DbOpenSshImportSession row) {
    final authType = switch (row.authType) {
      rust_ssh_config.DbOpenSshAuthType.password => AuthType.password,
      rust_ssh_config.DbOpenSshAuthType.key => AuthType.key,
    };
    return Session(
      id: row.id,
      label: row.label,
      folder: row.folder,
      server: ServerAddress(
        host: row.host,
        port: row.port,
        user: row.user,
      ),
      auth: SessionAuth(authType: authType, keyId: row.keyId),
    );
  }

  SshKeyEntry _toSshKeyEntry(rust_import.DbOpenSshImportKey row) {
    return SshKeyEntry(
      id: row.id,
      label: row.label,
      privateKey: row.privatePem,
      publicKey: row.publicOpenssh,
      keyType: row.keyType,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row.createdAtUnixMs),
      isGenerated: false,
    );
  }
}
