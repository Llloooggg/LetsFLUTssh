import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/session/session.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/src/rust/api/sessions.dart' as rust_sessions;

import '../helpers/frb_bootstrap.dart';

/// Drift guard: the Dart `Session.toJson` /
/// `toJsonWithCredentials` encoder in `lib/core/session/session.dart`
/// and the Rust `session_canonical_json` encoder in
/// `lfs_frb::api::sessions` must produce logically identical JSON
/// for every Session shape that ships across the wire (snapshot
/// undo/redo, archive export, QR payload).
///
/// The two encoders are TRUE duplicates — same field set, same
/// conditional-omit invariants. A future field-add on one side but
/// not the other would silently break archive round-trip until a
/// downstream `fromJson` call happened to read back the missing
/// field. The test below catches that drift on the boundary.
///
/// JSON comparison uses canonicalised maps (`SplayTreeMap` recurse)
/// so Dart's insertion-order vs Rust's alphabetised serde_json::Map
/// shape doesn't trigger a false positive — the audit's concern
/// is field-set drift, not key-order drift.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(requireFrbLoaded);

  // Fixture covers every conditional field. Empty / null variants
  // exercise the omit-branches; the populated variant exercises
  // the include-branches.
  final populatedSession = Session(
    id: 'sess-1',
    label: 'Edge prod',
    folder: 'production/web',
    server: const ServerAddress(
      host: 'edge.example.com',
      port: 2222,
      user: 'deploy',
    ),
    auth: const SessionAuth(
      authType: AuthType.key,
      keyId: 'key-7c8f',
      password: 'secret-pwd',
      keyPath: '/home/deploy/.ssh/id_ed25519',
      keyData: 'PEM-bytes-go-here',
      passphrase: 'phrase',
    ),
    createdAt: DateTime.utc(2026, 5, 9, 12, 0, 0),
    updatedAt: DateTime.utc(2026, 5, 9, 13, 30, 0),
    extras: const {'tags': 'web,prod', 'priority': 1},
    viaSessionId: 'bastion-id',
    viaOverride: const ProxyJumpOverride(
      host: 'bastion.example.com',
      port: 2200,
      user: 'jump',
    ),
    notes: 'maintenance window 03:00 UTC',
    sortOrder: 5,
    lastConnectedAtMs: 1715000000000,
  );

  final emptyish = Session(
    id: 'sess-2',
    label: '',
    folder: '',
    server: const ServerAddress(host: 'plain.example', port: 22, user: 'me'),
    auth: const SessionAuth(authType: AuthType.password, password: ''),
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 1, 1),
    extras: const {},
    notes: '',
    sortOrder: 0,
  );

  /// Recursively normalise a JSON-decoded map so map ordering does
  /// not affect equality. Lists keep their order (asciinema
  /// frame-style guarantee — the Session encoders never produce
  /// ordered lists where order would matter, but better to keep
  /// list order rather than risk hiding a real diff).
  Object? canonicalise(Object? v) {
    if (v is Map) {
      final sorted = <String, Object?>{};
      for (final key in v.keys.cast<String>().toList()..sort()) {
        sorted[key] = canonicalise(v[key]);
      }
      return sorted;
    }
    if (v is List) {
      return v.map(canonicalise).toList();
    }
    return v;
  }

  rust_sessions.DbSessionJsonInput inputFor(
    Session s, {
    required bool includeCredentials,
  }) {
    final via = s.viaOverride;
    return rust_sessions.DbSessionJsonInput(
      id: s.id,
      label: s.label,
      folder: s.folder,
      host: s.host,
      port: s.port,
      user: s.user,
      authType: s.authType.name,
      keyId: s.keyId,
      keyPath: s.keyPath,
      createdAtIso: s.createdAt.toIso8601String(),
      updatedAtIso: s.updatedAt.toIso8601String(),
      extrasJson: s.extras.isEmpty ? '' : jsonEncode(s.extras),
      viaSessionId: s.viaSessionId,
      viaOverride: via == null
          ? null
          : rust_sessions.DbSessionViaOverride(
              host: via.host,
              port: via.port,
              user: via.user,
            ),
      notes: s.notes,
      sortOrder: s.sortOrder,
      lastConnectedAtMs: s.lastConnectedAtMs,
      includeCredentials: includeCredentials,
      password: s.password,
      keyData: s.keyData,
      passphrase: s.passphrase,
    );
  }

  group('Session JSON cross-impl drift', () {
    test('fully-populated session round-trips identically', () {
      final dartJson = canonicalise(populatedSession.toJson());
      final rustJsonStr = rust_sessions.sessionCanonicalJson(
        input: inputFor(populatedSession, includeCredentials: false),
      );
      final rustJson = canonicalise(jsonDecode(rustJsonStr));
      expect(rustJson, dartJson);
    });

    test('toJsonWithCredentials round-trips identically', () {
      final dartJson = canonicalise(populatedSession.toJsonWithCredentials());
      final rustJsonStr = rust_sessions.sessionCanonicalJson(
        input: inputFor(populatedSession, includeCredentials: true),
      );
      final rustJson = canonicalise(jsonDecode(rustJsonStr));
      expect(rustJson, dartJson);
    });

    test('empty / default session omits the conditional fields', () {
      final dartJson = canonicalise(emptyish.toJson());
      final rustJsonStr = rust_sessions.sessionCanonicalJson(
        input: inputFor(emptyish, includeCredentials: false),
      );
      final rustJson = canonicalise(jsonDecode(rustJsonStr));
      expect(rustJson, dartJson);
      // Sanity: the conditional fields are gone.
      final asMap = rustJson! as Map<String, Object?>;
      expect(asMap.containsKey('key_id'), isFalse);
      expect(asMap.containsKey('extras'), isFalse);
      expect(asMap.containsKey('via_session_id'), isFalse);
      expect(asMap.containsKey('via_override'), isFalse);
      expect(asMap.containsKey('notes'), isFalse);
      expect(asMap.containsKey('sort_order'), isFalse);
      expect(asMap.containsKey('last_connected_at_ms'), isFalse);
    });
  });
}
