import 'dart:convert';

import '../../src/rust/api/qr_codec_encode.dart' as rust_qr;
import 'session.dart';

// `dart:convert` stays for `utf8.encode` on the password byte path;
// the JSON decoder is no longer needed since `encodeSessionCompact`
// routes through the typed FRB return shape.

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

  /// True when at least one *standalone* entity is selected. Used to gate the
  /// Import button in [ImportPreviewDialog].
  ///
  /// "Standalone" means an entity that can exist on its own without a session:
  /// sessions themselves, app config, known_hosts, the full manager-key set,
  /// tags, and snippets. Session-linked modifiers ([includeManagerKeys] — the
  /// subset referenced by selected sessions, [includePasswords] and
  /// [includeEmbeddedKeys]) are deliberately excluded: they're meaningless
  /// without [includeSessions], so ticking them alone would produce an
  /// effectively empty import.
  bool get hasAnySelection =>
      includeSessions ||
      includeConfig ||
      includeKnownHosts ||
      includeAllManagerKeys ||
      includeTags ||
      includeSnippets;

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

/// Encode a session into the compact QR payload format.
///
/// Used internally by [encodeExportPayload] and also available for
/// size estimation in export dialogs.
///
/// Routes through `lfs_core::qr_codec_encode::encode_session_compact`
/// (FRB sync) so the v4 field-name grammar
/// (`l`/`h`/`u`/`p`/`g`/`a`/`ki`/`mg`/`pw`) lives one place across
/// the in-memory encoder and the DB-backed
/// `lfs_core::archive::qr_export_payload` writer.
///
/// The FRB return rides as a typed `DbQrSessionCompact` struct — no
/// Dart-side `jsonDecode` lives on this path. The Dart wrapper just
/// re-keys typed-presence into the `Map<String, dynamic>` shape the
/// outer export payload composes.
Map<String, dynamic> encodeSessionCompact(
  Session s, {
  String? keyId,
  bool isManagerKey = false,
  bool includePasswords = false,
}) {
  // SECURITY: passwords stored in plaintext in QR payload — only
  // enable when user explicitly opts in via includePasswords. QR
  // codes can be scanned by anyone with camera access to the
  // screen. The opt-in gate lives Rust-side in
  // `lfs_core::qr_codec::encode_session_compact`.
  final typed = rust_qr.qrCodecEncodeSessionCompactTyped(
    inputs: rust_qr.QrSessionCompactInputs(
      label: s.label,
      host: s.host,
      user: s.user,
      port: s.port,
      folder: s.folder,
      authType: s.authType.name,
      keyShort: keyId,
      isManager: isManagerKey,
      includePasswords: includePasswords,
      password: utf8.encode(s.password),
    ),
  );
  final out = <String, dynamic>{
    'l': typed.label,
    'h': typed.host,
    'u': typed.user,
  };
  if (typed.port != null) out['p'] = typed.port;
  if (typed.folder != null) out['g'] = typed.folder;
  if (typed.authType != null) out['a'] = typed.authType;
  if (typed.keyShort != null) out['ki'] = typed.keyShort;
  if (typed.isManager != null) out['mg'] = typed.isManager;
  if (typed.password != null) out['pw'] = typed.password;
  return out;
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
