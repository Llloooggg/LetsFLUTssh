import 'dart:convert';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show PlatformInt64Util;
import 'package:uuid/uuid.dart';

import '../../src/rust/api/path.dart' as rust_path;
import '../../src/rust/api/sessions.dart' as rust_sess;
import '../ssh/ssh_config.dart';

/// Authentication type for a session — re-exported from the
/// FRB-generated mirror of `lfs_core::sessions::AuthType` so the
/// Rust side owns the variant set + the wire grammar
/// (`AuthType::wire_name` / `AuthType::from_wire_name`). The Dart
/// name is unchanged so call sites stay short; the `.name` getter
/// the generated enum exposes (`password` / `key` /
/// `keyWithPassword` / `agent`) doubles as the wire value the DB
/// column and the canonical-JSON payload carry.
///
/// `agent` defers credential discovery to a running system
/// ssh-agent (Unix `$SSH_AUTH_SOCK` / Windows OpenSSH named pipe /
/// Pageant). The session row carries no key id / inline PEM /
/// password — every signature flows through the agent over its
/// socket; the dialog surfaces no extra fields and the connect
/// path short-circuits to [SshAuthAgent] without staging anything
/// into SecretStore.
typedef AuthType = rust_sess.DbAuthType;

/// Transport kind — re-exported from the FRB-generated mirror of
/// `lfs_core::sessions::SessionKind`. SSH covers the classic shell
/// + SFTP file browser; WebDAV runs the file browser against an
/// HTTP-backed remote (Nextcloud, ownCloud, Apache mod_dav, IIS,
/// Synology DSM etc.); S3 runs against any S3-compatible object
/// store (AWS S3, MinIO, Wasabi, Backblaze B2-S3, Cloudflare R2,
/// DigitalOcean Spaces, Scaleway).
///
/// The wire value persisted in the DB matches
/// `lfs_core::db::sessions::SESSION_KIND_*` and is reached via the
/// `.name` getter (`ssh` / `webdav` / `s3`). Parsing routes
/// through [rust_sess.sessionKindFromWire] — empty / unknown
/// tags fold to SSH so a future schema bump that adds a kind the
/// current build does not understand renders the row as SSH until
/// the build catches up.
typedef SessionKind = rust_sess.DbSessionKind;

/// One-off ProxyJump override — used when the user wants to bounce
/// through a host that is **not** a saved session. All three fields
/// are required as a unit; the loader treats a partial override as
/// absent.
///
/// Saved-session bastions take precedence: when [Session.viaSessionId]
/// is non-null, this override is ignored. Document this so the
/// session-edit dialog can surface a warning when the user fills both
/// at once.
class ProxyJumpOverride {
  final String host;
  final int port;
  final String user;

  const ProxyJumpOverride({
    required this.host,
    this.port = 22,
    required this.user,
  });

  // JSON codec lives on the parent `Session` — the canonical
  // encoder (`lfs_core::session_json::encode_canonical_json`)
  // nests the override block directly in the session payload.
  // A separate `ProxyJumpOverride.toJson` / `.fromJson` pair would
  // re-introduce the duplication the migration is removing.

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProxyJumpOverride &&
          host == other.host &&
          port == other.port &&
          user == other.user;

  @override
  int get hashCode => Object.hash(host, port, user);
}

/// Session authentication — extends [SshAuth] with UI-facing [authType].
class SessionAuth extends SshAuth {
  final AuthType authType;

  /// Per-slot "credential exists in persistent storage" flags. Set by
  /// the DB loader when the cache is populated without decrypted
  /// secrets (so plaintext bytes don't sit on the Dart heap). Used by
  /// the list UI to flag incomplete sessions and by the edit dialog
  /// to render "[Saved]" badges next to fields whose underlying row
  /// has a value without ever pre-filling the controller.
  final bool hasStoredPassword;
  final bool hasStoredKeyData;
  final bool hasStoredPassphrase;

  /// Composite "any credential is stored" — kept as a getter so call
  /// sites that only care about "is the session complete enough to
  /// connect" don't have to inspect every slot.
  bool get hasStoredSecret =>
      hasStoredPassword || hasStoredKeyData || hasStoredPassphrase;

  const SessionAuth({
    this.authType = AuthType.password,
    this.hasStoredPassword = false,
    this.hasStoredKeyData = false,
    this.hasStoredPassphrase = false,
    super.password,
    super.keyPath,
    super.keyData,
    super.keyId,
    super.passphrase,
  });

  @override
  SessionAuth copyWith({
    AuthType? authType,
    String? keyId,
    bool? hasStoredPassword,
    bool? hasStoredKeyData,
    bool? hasStoredPassphrase,
    String? password,
    String? keyPath,
    String? keyData,
    String? passphrase,
    // Accepted to satisfy the [SshAuth.copyWith] override signature.
    // SessionAuth carries the typed [authType] field instead — the
    // agent flag is derived in [Session.toSSHConfig] when projecting
    // the bag into [SshAuth]; routing it back through this copyWith
    // would risk a SessionAuth whose flag disagreed with authType.
    bool? useAgent,
  }) => SessionAuth(
    authType: authType ?? this.authType,
    keyId: keyId ?? this.keyId,
    hasStoredPassword: hasStoredPassword ?? this.hasStoredPassword,
    hasStoredKeyData: hasStoredKeyData ?? this.hasStoredKeyData,
    hasStoredPassphrase: hasStoredPassphrase ?? this.hasStoredPassphrase,
    password: password ?? this.password,
    keyPath: keyPath ?? this.keyPath,
    keyData: keyData ?? this.keyData,
    passphrase: passphrase ?? this.passphrase,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SessionAuth &&
          authType == other.authType &&
          keyId == other.keyId &&
          hasStoredPassword == other.hasStoredPassword &&
          hasStoredKeyData == other.hasStoredKeyData &&
          hasStoredPassphrase == other.hasStoredPassphrase &&
          password == other.password &&
          keyPath == other.keyPath &&
          keyData == other.keyData &&
          passphrase == other.passphrase;

  @override
  int get hashCode => Object.hash(
    authType,
    keyId,
    hasStoredPassword,
    hasStoredKeyData,
    hasStoredPassphrase,
    password,
    keyPath,
    keyData,
    passphrase,
  );

  /// Strip every plaintext credential, preserving the per-slot
  /// `hasStoredX` markers (computed from the live values when not
  /// already set). Used by `SessionStore` to push optimistic
  /// cache entries that match the post-DAO snapshot shape — the
  /// list view never holds plaintext between an upsert and the
  /// `SessionsChanged` bus event landing.
  SessionAuth withoutCredentials() => SessionAuth(
    authType: authType,
    keyId: keyId,
    hasStoredPassword: hasStoredPassword || password.isNotEmpty,
    hasStoredKeyData: hasStoredKeyData || keyData.isNotEmpty,
    hasStoredPassphrase: hasStoredPassphrase || passphrase.isNotEmpty,
    keyPath: keyPath,
  );
}

/// Session model — stored as JSON, credentials in encrypted storage.
/// `kind` decides the transport (SSH/SFTP vs WebDAV); legacy callers
/// that omit it default to [SessionKind.ssh].
class Session {
  final String id;
  final String label;
  final String folder; // path like "Production/Web"
  final SessionKind kind;
  final ServerAddress server;
  final SessionAuth auth;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Free-form key-value bag persisted into `Sessions.extras` as JSON.
  ///
  /// Use [extrasBool] / [extrasStr] / [extrasInt] for typed reads and
  /// [withExtras] to produce a copy with a delta merged in. Anything
  /// load-bearing (auth, port forwards, proxy jump) gets its own
  /// columns; this is the escape hatch for feature flags that don't
  /// justify a migration on their own (recording toggle, layout
  /// hints, etc.).
  final Map<String, Object?> extras;

  /// ProxyJump bastion — id of another saved session whose SSH client
  /// opens a `forwardLocal` channel that this session uses as its
  /// transport. Null = direct connect.
  ///
  /// Takes precedence over [viaOverride]. Set together they imply
  /// the user is migrating away from a one-off override; the loader
  /// honours [viaSessionId] and ignores the override.
  final String? viaSessionId;

  /// One-off ProxyJump override — used when the user does not have
  /// the bastion as a saved session. Ignored when [viaSessionId] is
  /// non-null. See [ProxyJumpOverride] for the unit-set rule.
  final ProxyJumpOverride? viaOverride;

  /// User-facing free-form note. Persisted in `Sessions.notes`
  /// (default: empty). Round-tripped through every save path —
  /// edits to other fields must NOT clobber it.
  final String notes;

  /// Manual sort order within a folder. Lower values appear first;
  /// equal values fall back to alphabetic by `label`. Zero means
  /// "unspecified" (the row uses default ordering). Persisted in
  /// `Sessions.sort_order`.
  final int sortOrder;

  /// Wall-clock timestamp of the most recent successful connect, in
  /// milliseconds since epoch. `null` if the session has never been
  /// connected. Persisted in `Sessions.last_connected_at`.
  final int? lastConnectedAtMs;

  Session({
    String? id,
    required this.label,
    this.folder = '',
    this.kind = SessionKind.ssh,
    required this.server,
    this.auth = const SessionAuth(),
    DateTime? createdAt,
    DateTime? updatedAt,
    Map<String, Object?>? extras,
    this.viaSessionId,
    this.viaOverride,
    this.notes = '',
    this.sortOrder = 0,
    this.lastConnectedAtMs,
  }) : id = id ?? const Uuid().v4(),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now(),
       extras = Map.unmodifiable(extras ?? const <String, Object?>{});

  /// True when this session uses the SSH/SFTP transport. Cheap
  /// readable shorthand — call sites that branch by kind read
  /// better with these getters than with `kind == SessionKind.ssh`.
  bool get isSsh => kind == SessionKind.ssh;

  /// True when this session uses the WebDAV transport.
  bool get isWebDav => kind == SessionKind.webdav;

  /// True when this session uses the S3 transport.
  bool get isS3 => kind == SessionKind.s3;

  /// True when this session bounces through a bastion before reaching
  /// [host]:[port]. UI uses this to surface a "via X" subtitle.
  bool get hasProxyJump => viaSessionId != null || viaOverride != null;

  // --- Convenience accessors (keep call sites short) ---
  String get host => server.host;
  int get port => server.port;
  String get user => server.user;
  AuthType get authType => auth.authType;
  String get keyId => auth.keyId;
  String get password => auth.password;
  String get keyPath => auth.keyPath;
  String get keyData => auth.keyData;
  String get passphrase => auth.passphrase;

  // --- Extras helpers ---
  bool? extrasBool(String key) {
    final v = extras[key];
    return v is bool ? v : null;
  }

  String? extrasStr(String key) {
    final v = extras[key];
    return v is String ? v : null;
  }

  int? extrasInt(String key) {
    final v = extras[key];
    if (v is int) return v;
    if (v is double) return v.toInt();
    return null;
  }

  /// Return a copy with [delta] merged into [extras]. A `null` value
  /// removes the key (so callers can clear feature flags without
  /// resorting to a sentinel string). Keeps `updatedAt` fresh via
  /// [copyWith].
  Session withExtras(Map<String, Object?> delta) {
    final merged = Map<String, Object?>.from(extras);
    delta.forEach((k, v) {
      if (v == null) {
        merged.remove(k);
      } else {
        merged[k] = v;
      }
    });
    return copyWith(extras: merged);
  }

  /// True if session has credentials — either carried in this instance
  /// (password/keyData/keyPath/keyId) or known to exist in persistent
  /// storage ([SessionAuth.hasStoredSecret]). The store's cached list
  /// strips plaintext secrets on load; without the stored-secret flag
  /// this getter would mistakenly mark every embedded-key session as
  /// incomplete after an app restart.
  bool get hasCredentials =>
      password.isNotEmpty ||
      keyData.isNotEmpty ||
      keyId.isNotEmpty ||
      keyPath.isNotEmpty ||
      auth.hasStoredSecret;

  /// True if the session is ready to connect.
  ///
  /// SSH: the SSH-shaped row carries host / port / user / credentials
  /// on `ssh_session_details` (after the v16 schema split). All four
  /// must be present.
  ///
  /// WebDAV / S3: the transport tuple (base URL, endpoint, etc.) and
  /// the secret live on the matching `webdav_session_details` /
  /// `s3_session_details` join + SecretStore. Those rows are not on
  /// the in-memory `Session` shape — querying them requires an FRB
  /// hop, which a sync getter cannot do. Treat the row as valid as
  /// long as it exists with the right `kind`; the connect path
  /// (`_doWebDavConnect` / `_doS3Connect`) fails fast on a missing
  /// detail row / unstaged secret with a precise localized error.
  bool get isValid {
    switch (kind) {
      case SessionKind.ssh:
        return host.trim().isNotEmpty &&
            port >= 1 &&
            port <= 65535 &&
            user.trim().isNotEmpty &&
            hasCredentials;
      case SessionKind.webdav:
      case SessionKind.s3:
        return true;
    }
  }

  // Session.validate has retired — callers route through
  // `rust_sess.sessionsValidateFields(host:, port:, user:)` directly
  // so the storable-field grammar (host non-empty, port 1..=65535,
  // user non-empty) lives Rust-side with no Dart-side wrapper.
  // [isValid] above stays as the connect-time credential check.

  /// Sanitised copy of this session — plaintext credentials cleared,
  /// `hasStoredX` markers preserved (or computed from the live
  /// values when not already set). Cache writes use this so the
  /// in-memory list never holds plaintext between an upsert and
  /// the `SessionsChanged` bus event landing.
  Session withoutCredentials() => copyWith(auth: auth.withoutCredentials());

  /// Display string for sidebar Semantics, connection-label fallback,
  /// and detail-panel name row.
  ///
  /// SSH carries `host` / `user` / `port` on the in-memory `Session`
  /// row (loaded off `ssh_session_details` after the v16 schema
  /// split), so the SSH branch renders the familiar
  /// `"label (user@host)"` / `"user@host:port"` shape.
  ///
  /// WebDAV / S3 keep their transport tuple on the matching join
  /// table (`webdav_session_details.base_url`,
  /// `s3_session_details.endpoint`) — the SSH-shaped fields on
  /// `Session` read empty for those kinds, so rendering
  /// `"$user@$host:$port"` would emit `"@:22"`. Fall back to the
  /// label, or — when the user has not yet labelled the session —
  /// a kind-specific token so the surface is never blank.
  String get displayName {
    if (kind != SessionKind.ssh) {
      if (label.isNotEmpty) return label;
      switch (kind) {
        case SessionKind.webdav:
          return 'WebDAV session';
        case SessionKind.s3:
          return 'S3 session';
        case SessionKind.ssh:
          break;
      }
    }
    return label.isNotEmpty ? '$label ($user@$host)' : '$user@$host:$port';
  }

  /// Full folder path with label for tree display.
  String get fullPath => folder.isNotEmpty ? '$folder/$label' : label;

  /// Convert to SSHConfig for connecting.
  SSHConfig toSSHConfig() {
    final expandedKeyPath = rust_path.pathExpandTilde(path: keyPath);
    return SSHConfig(
      server: server,
      auth: SshAuth(
        password: password,
        keyPath: expandedKeyPath,
        keyData: keyData,
        keyId: keyId,
        passphrase: passphrase,
        useAgent: auth.authType == AuthType.agent,
      ),
    );
  }

  Session copyWith({
    String? label,
    String? folder,
    SessionKind? kind,
    ServerAddress? server,
    SessionAuth? auth,
    Map<String, Object?>? extras,
    Object? viaSessionId = _unsetVia,
    Object? viaOverride = _unsetVia,
    String? notes,
    int? sortOrder,
    Object? lastConnectedAtMs = _unsetVia,
  }) {
    return Session(
      id: id,
      label: label ?? this.label,
      folder: folder ?? this.folder,
      kind: kind ?? this.kind,
      server: server ?? this.server,
      auth: auth ?? this.auth,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
      extras: extras ?? this.extras,
      viaSessionId: identical(viaSessionId, _unsetVia)
          ? this.viaSessionId
          : viaSessionId as String?,
      viaOverride: identical(viaOverride, _unsetVia)
          ? this.viaOverride
          : viaOverride as ProxyJumpOverride?,
      notes: notes ?? this.notes,
      sortOrder: sortOrder ?? this.sortOrder,
      lastConnectedAtMs: identical(lastConnectedAtMs, _unsetVia)
          ? this.lastConnectedAtMs
          : lastConnectedAtMs as int?,
    );
  }

  // Sentinel that lets `copyWith` distinguish "caller did not pass
  // this argument" from "caller passed null to clear it" — both
  // viaSessionId and viaOverride need to be clearable independently
  // from "leave unchanged".
  static const Object _unsetVia = Object();

  // Session duplication routes through `dbSessionsDuplicateWithPath`
  // which composes label-dedup + folder-resolve + new-id mint +
  // insert in one transaction Rust-side. **Don't reintroduce a
  // Dart-side `Session.duplicate()` helper** — the in-memory copy
  // would silently drop `extras` / `viaSessionId` / `viaOverride`
  // on any caller that constructed it before those fields landed.

  /// Serialize without secrets — safe for plaintext JSON storage.
  ///
  /// Routes through the canonical encoder in `lfs_core::session_json`
  /// via the FRB sync shim. Single source of truth for the wire
  /// shape; the Dart side never hand-rolls the field set.
  Map<String, dynamic> toJson() {
    final encoded = rust_sess.sessionCanonicalJson(
      input: sessionToJsonInput(this, includeCredentials: false),
    );
    return jsonDecode(encoded) as Map<String, dynamic>;
  }

  /// Serialize with secrets — for encrypted export only.
  ///
  /// Same routing as [toJson]; the `include_credentials` flag on the
  /// encoder input flips the credential trio on.
  Map<String, dynamic> toJsonWithCredentials() {
    final encoded = rust_sess.sessionCanonicalJson(
      input: sessionToJsonInput(this, includeCredentials: true),
    );
    return jsonDecode(encoded) as Map<String, dynamic>;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Session &&
          id == other.id &&
          label == other.label &&
          folder == other.folder &&
          kind == other.kind &&
          server == other.server &&
          auth == other.auth &&
          viaSessionId == other.viaSessionId &&
          viaOverride == other.viaOverride &&
          notes == other.notes &&
          sortOrder == other.sortOrder &&
          lastConnectedAtMs == other.lastConnectedAtMs &&
          _extrasEqual(extras, other.extras);

  @override
  int get hashCode => Object.hash(
    id,
    label,
    folder,
    kind,
    server,
    auth,
    viaSessionId,
    viaOverride,
    notes,
    sortOrder,
    lastConnectedAtMs,
    // Map.hashCode is identity-based — fold the entries instead so
    // two sessions with logically equal `extras` hash equal too.
    Object.hashAllUnordered(
      extras.entries.map((e) => Object.hash(e.key, e.value)),
    ),
  );

  static bool _extrasEqual(Map<String, Object?> a, Map<String, Object?> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (!b.containsKey(entry.key)) return false;
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }

  /// Re-hydrate from a JSON map produced by [toJson] /
  /// [toJsonWithCredentials] (or any compatible importer).
  ///
  /// Routes through `lfs_core::session_json::decode_canonical_json`
  /// via the FRB sync shim. The Rust decoder owns the full
  /// missing-key / wrong-type / legacy-`group`-alias tolerance set
  /// — see the module-level docstring there for the invariants.
  factory Session.fromJson(Map<String, dynamic> json) {
    final out = rust_sess.sessionDecodeFromJson(json: jsonEncode(json));
    return sessionFromJsonOutput(out);
  }
}

// ── Canonical-JSON ↔ domain translation ─────────────────────────────
//
// Pure Dart-side glue between the FRB DTOs (`DbSessionJsonInput` /
// `DbSessionJsonOutput`) and the domain [Session] / [ProxyJumpOverride]
// classes. Lives in the same file as [Session] so the import graph
// stays acyclic — splitting it out introduced a cycle
// (session.dart → codec → session.dart) which `flutter_test`'s
// `import_cycles_test` rejects.

/// Build the FRB encoder input for [session]. The
/// `includeCredentials` flag mirrors the Dart-side
/// `Session.toJson` vs `Session.toJsonWithCredentials` split — when
/// false the credential trio (`password`, `key_data`, `passphrase`)
/// is omitted from the wire payload.
rust_sess.DbSessionJsonInput sessionToJsonInput(
  Session session, {
  required bool includeCredentials,
}) {
  final via = session.viaOverride;
  return rust_sess.DbSessionJsonInput(
    id: session.id,
    label: session.label,
    folder: session.folder,
    host: session.host,
    port: session.port,
    user: session.user,
    kind: session.kind,
    authType: session.authType,
    keyId: session.keyId,
    keyPath: session.keyPath,
    createdAtIso: session.createdAt.toIso8601String(),
    updatedAtIso: session.updatedAt.toIso8601String(),
    extrasJson: extrasMapToJson(session.extras),
    viaSessionId: session.viaSessionId,
    viaOverride: via == null
        ? null
        : rust_sess.DbSessionViaOverride(
            host: via.host,
            port: via.port,
            user: via.user,
          ),
    notes: session.notes,
    sortOrder: session.sortOrder,
    lastConnectedAtMs: session.lastConnectedAtMs,
    includeCredentials: includeCredentials,
    password: session.password,
    keyData: session.keyData,
    passphrase: session.passphrase,
  );
}

/// Re-hydrate a [Session] from a decoded [rust_sess.DbSessionJsonOutput]
/// payload. Credential fields land in the auth bag verbatim; callers
/// that loaded the payload from a credential-stripped JSON will see
/// empty strings there. Timestamps fall back to `DateTime.now()` when
/// the wire payload omitted them — same tolerance as the retired
/// hand-rolled `Session.fromJson` factory.
Session sessionFromJsonOutput(rust_sess.DbSessionJsonOutput out) {
  return Session(
    id: out.id,
    label: out.label,
    folder: out.folder,
    kind: out.kind,
    server: ServerAddress(host: out.host, port: out.port, user: out.user),
    auth: SessionAuth(
      authType: out.authType,
      keyId: out.keyId,
      password: out.password,
      keyPath: out.keyPath,
      keyData: out.keyData,
      passphrase: out.passphrase,
    ),
    createdAt: DateTime.tryParse(out.createdAtIso) ?? DateTime.now(),
    updatedAt: DateTime.tryParse(out.updatedAtIso) ?? DateTime.now(),
    extras: extrasListToMap(out.extras),
    viaSessionId: out.viaSessionId,
    viaOverride: out.viaOverride == null
        ? null
        : ProxyJumpOverride(
            host: out.viaOverride!.host,
            port: out.viaOverride!.port,
            user: out.viaOverride!.user,
          ),
    notes: out.notes,
    sortOrder: out.sortOrder,
    lastConnectedAtMs: out.lastConnectedAtMs,
  );
}

/// Re-key the FRB `Vec<DbSessionJsonExtra>` list into the
/// `Map<String, Object?>` shape `Session.extras` exposes. Leaf
/// conversion mirrors the typed accessors:
///
/// * `Null` → `null` (key still present, useful for `extras['k'] != null`
///   probes Dart-side).
/// * `Bool` / `Int` / `Double` / `Text` → native Dart types.
/// * `Array` / `Object` → recursive walk into `List<Object?>` /
///   `Map<String, Object?>`. The FRB carrier is fully typed end to
///   end so a nested probe never has to re-parse a JSON string.
Map<String, Object?> extrasListToMap(List<rust_sess.DbSessionJsonExtra> list) {
  final out = <String, Object?>{};
  for (final entry in list) {
    out[entry.key] = _extrasLeafToDart(entry.value);
  }
  return out;
}

Object? _extrasLeafToDart(rust_sess.DbSessionJsonValue v) {
  return v.map(
    null_: (_) => null,
    bool: (b) => b.field0,
    int: (i) => i.field0.toInt(),
    double: (d) => d.field0,
    text: (t) => t.field0,
    array: (a) => a.field0.map(_extrasLeafToDart).toList(growable: false),
    object: (o) => extrasListToMap(o.field0),
  );
}

/// Encode a `Session.extras` map (`Map<String, Object?>`) into the
/// canonical JSON-text wire form persisted in `Sessions.extras`.
/// Routes through `lfs_core::session_json::encode_extras_string` via
/// the FRB sync shim `session_extras_encode` — symmetric counterpart
/// of [`rust_sess.sessionExtrasDecode`]. Empty input yields the
/// empty string (DB column default) so a session without extras
/// stages a clean row.
///
/// The wire grammar (typed leaves, nested arrays / objects)
/// lives Rust-side; the Dart caller only walks its native value
/// tree into the typed `DbSessionJsonExtra` carrier.
String extrasMapToJson(Map<String, Object?> extras) {
  if (extras.isEmpty) return '';
  final list = extras.entries
      .map(
        (e) => rust_sess.DbSessionJsonExtra(
          key: e.key,
          value: _extrasLeafToRust(e.value),
        ),
      )
      .toList(growable: false);
  return rust_sess.sessionExtrasEncode(extras: list);
}

/// Inverse of [`_extrasLeafToDart`]: walk a Dart value tree into
/// the FRB-typed [`DbSessionJsonValue`] mirror. The grammar tracks
/// `Session.extras`'s declared element types (`bool` / `int` /
/// `double` / `String` / `List<Object?>` / `Map<String, Object?>`).
/// Anything outside that set folds to `Null` rather than panicking
/// — the typed accessors on [Session] only read primitives, so a
/// leaf that round-trips as null is functionally identical to a
/// missing key.
rust_sess.DbSessionJsonValue _extrasLeafToRust(Object? value) {
  if (value == null) {
    return const rust_sess.DbSessionJsonValue.null_();
  }
  if (value is bool) {
    return rust_sess.DbSessionJsonValue.bool(value);
  }
  if (value is int) {
    // `PlatformInt64` is `int` on io and `BigInt` on web — the
    // `for_generated` Util routes the value through whichever
    // platform-specific constructor the FRB runtime uses.
    return rust_sess.DbSessionJsonValue.int(PlatformInt64Util.from(value));
  }
  if (value is double) {
    return rust_sess.DbSessionJsonValue.double(value);
  }
  if (value is String) {
    return rust_sess.DbSessionJsonValue.text(value);
  }
  if (value is List) {
    return rust_sess.DbSessionJsonValue.array(
      value.map(_extrasLeafToRust).toList(growable: false),
    );
  }
  if (value is Map<String, Object?>) {
    return rust_sess.DbSessionJsonValue.object(
      value.entries
          .map(
            (e) => rust_sess.DbSessionJsonExtra(
              key: e.key,
              value: _extrasLeafToRust(e.value),
            ),
          )
          .toList(growable: false),
    );
  }
  return const rust_sess.DbSessionJsonValue.null_();
}
