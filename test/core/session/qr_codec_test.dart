import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/session/qr_codec.dart';
import 'package:letsflutssh/core/session/session.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';

import '../../helpers/frb_bootstrap.dart';

void main() {
  // qr_codec routes through `lfs_core::qr_codec` — bootstrap FRB
  // so the canonical Rust encode + compress + base64url-no-pad
  // grammar is exercised.
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(requireFrbLoaded);

  group('encodeSessionCompact', () {
    Session base({
      String label = 'lab',
      String host = 'example.com',
      String user = 'alice',
      int port = 22,
      String folder = '',
      AuthType authType = AuthType.password,
      String password = '',
    }) => Session(
      label: label,
      server: ServerAddress(host: host, user: user, port: port),
      auth: SessionAuth(authType: authType, password: password),
      folder: folder,
    );

    test('emits only required keys for the default shape', () {
      final m = encodeSessionCompact(base());
      expect(m, {'l': 'lab', 'h': 'example.com', 'u': 'alice'});
    });

    test('default port collapses out of the payload', () {
      final m = encodeSessionCompact(base(port: 22));
      expect(m.containsKey('p'), isFalse);
    });

    test('non-default port surfaces under p', () {
      final m = encodeSessionCompact(base(port: 2222));
      expect(m['p'], 2222);
    });

    test('non-empty folder surfaces under g', () {
      final m = encodeSessionCompact(base(folder: 'infra/prod'));
      expect(m['g'], 'infra/prod');
    });

    test('auth other than password surfaces under a as enum name', () {
      final m = encodeSessionCompact(base(authType: AuthType.key));
      expect(m['a'], 'key');
    });

    test('keyId + isManagerKey surface under ki + mg', () {
      final m = encodeSessionCompact(
        base(authType: AuthType.key),
        keyId: 'k0',
        isManagerKey: true,
      );
      expect(m['ki'], 'k0');
      expect(m['mg'], 1);
    });

    test('password is omitted unless includePasswords opts in', () {
      final off = encodeSessionCompact(base(password: 'secret'));
      expect(off.containsKey('pw'), isFalse);
      final on = encodeSessionCompact(
        base(password: 'secret'),
        includePasswords: true,
      );
      expect(on['pw'], 'secret');
    });

    test('opt-in with empty password still omits the field', () {
      final m = encodeSessionCompact(base(), includePasswords: true);
      expect(m.containsKey('pw'), isFalse);
    });

    // Spec: empty folder collapses out of the payload to save QR-bit
    // budget — the v4 grammar defaults `g` to "" so its omission round-
    // trips to the same empty string. A bug that emitted `g: ""`
    // explicitly would inflate every session by ~10 bytes after deflate.
    test('empty folder collapses out of the payload', () {
      final m = encodeSessionCompact(base(folder: ''));
      expect(m.containsKey('g'), isFalse);
    });

    // Spec: password auth is the default — its name should NOT surface
    // in `a` so the most common case adds no bytes to the payload.
    test('default password auth omits a key entirely', () {
      final m = encodeSessionCompact(base(authType: AuthType.password));
      expect(m.containsKey('a'), isFalse);
    });

    // Spec: every non-default auth variant must be passed through as
    // its wire name. Pin the variants directly so a Rust-side rename
    // (`keyWithPassword` → `key_with_password`) flips this test red.
    test('keyWithPassword and agent variants pass through as wire names', () {
      expect(
        encodeSessionCompact(base(authType: AuthType.keyWithPassword))['a'],
        'keyWithPassword',
      );
      expect(
        encodeSessionCompact(base(authType: AuthType.agent))['a'],
        'agent',
      );
    });

    // Spec: `isManager: false` is the default and must NOT surface the
    // `mg` flag — only a `true` (encoded as `1`) belongs in the payload.
    // The Rust grammar uses `Some(1)` to signal "this keyed session
    // points at a manager key" without paying for a bool serialization.
    test('isManager defaults to false → mg omitted', () {
      final m = encodeSessionCompact(base(authType: AuthType.key), keyId: 'k0');
      expect(m['ki'], 'k0');
      expect(m.containsKey('mg'), isFalse);
    });

    // Spec: a session with every overrideable field set produces a
    // payload that carries every optional key. Pins the full-grammar
    // round-trip — a regression that drops one field surfaces here.
    test('fully-populated session emits every optional field', () {
      final m = encodeSessionCompact(
        base(
          port: 2200,
          folder: 'a/b/c',
          authType: AuthType.keyWithPassword,
          password: 'pw',
        ),
        keyId: 'k7',
        isManagerKey: true,
        includePasswords: true,
      );
      expect(m['l'], 'lab');
      expect(m['h'], 'example.com');
      expect(m['u'], 'alice');
      expect(m['p'], 2200);
      expect(m['g'], 'a/b/c');
      expect(m['a'], 'keyWithPassword');
      expect(m['ki'], 'k7');
      expect(m['mg'], 1);
      expect(m['pw'], 'pw');
    });

    // Spec: the QR payload size cap lives Dart-side as a contract used
    // by the unified export dialog's gauge — `qrMaxPayloadBytes` is the
    // ceiling that keeps a v40 binary QR with EC-L renderable after the
    // deeplink wrapper + base64 inflation. The constant value is part
    // of the public API; a silent bump would let oversize payloads
    // through and the receiver's QR scanner would silently fail.
    test('qrMaxPayloadBytes documents the ~2 KB conservative ceiling', () {
      expect(qrMaxPayloadBytes, 2000);
    });
  });

  group('ExportOptions', () {
    // Spec: credentials default to off across the wire — passwords,
    // embedded PEMs, and manager keys are explicit opt-ins per the
    // security comment in the source. The default constructor pins
    // the safe shape every caller starts from.
    test('default constructor leaves every credential surface off', () {
      const opts = ExportOptions();
      expect(opts.includeSessions, isTrue);
      expect(opts.includeConfig, isTrue);
      expect(opts.includeKnownHosts, isTrue);
      expect(opts.includePasswords, isFalse);
      expect(opts.includeEmbeddedKeys, isFalse);
      expect(opts.includeManagerKeys, isFalse);
      expect(opts.includeAllManagerKeys, isFalse);
      expect(opts.includeTags, isFalse);
      expect(opts.includeSnippets, isFalse);
      expect(opts.includeRecordings, isFalse);
    });

    // Spec: `hasManagerKeys` is the disjunction — either manager-key
    // mode (per-selected or full set) flips it. The export dialog uses
    // it to gate the "include private key bytes" warning copy.
    test('hasManagerKeys flips for either manager-key mode', () {
      expect(const ExportOptions().hasManagerKeys, isFalse);
      expect(
        const ExportOptions().withIncludeManagerKeys(true).hasManagerKeys,
        isTrue,
      );
      expect(
        const ExportOptions().withIncludeAllManagerKeys(true).hasManagerKeys,
        isTrue,
      );
    });

    // Spec: `hasAnySelection` excludes session-linked modifiers
    // (passwords / embedded keys / per-selected manager keys) — they
    // are meaningless without a session payload. A bug that included
    // them would let the Import button enable while the receiver would
    // see an empty archive.
    test('hasAnySelection ignores session-linked modifiers in isolation', () {
      // Everything off → false.
      const empty = ExportOptions(
        includeSessions: false,
        includeConfig: false,
        includeKnownHosts: false,
      );
      expect(empty.hasAnySelection, isFalse);

      // Only password ticked → still false (modifier-only).
      expect(empty.withIncludePasswords(true).hasAnySelection, isFalse);
      // Only embedded-keys ticked → still false.
      expect(empty.withIncludeEmbeddedKeys(true).hasAnySelection, isFalse);
      // Only per-selected manager keys → still false (rides with sessions).
      expect(empty.withIncludeManagerKeys(true).hasAnySelection, isFalse);

      // Standalone toggles flip it true.
      expect(empty.withIncludeSessions(true).hasAnySelection, isTrue);
      expect(empty.withIncludeConfig(true).hasAnySelection, isTrue);
      expect(empty.withIncludeKnownHosts(true).hasAnySelection, isTrue);
      expect(empty.withIncludeAllManagerKeys(true).hasAnySelection, isTrue);
      expect(empty.withIncludeTags(true).hasAnySelection, isTrue);
      expect(empty.withIncludeSnippets(true).hasAnySelection, isTrue);
      expect(empty.withIncludeRecordings(true).hasAnySelection, isTrue);
    });

    // Spec: every `withInclude*` mutator clones the rest unchanged.
    // Spot-check a representative one (`withIncludePasswords`) to pin
    // the immutability contract; a regression that mutated in place
    // would corrupt the dialog's pre/post snapshots used for undo.
    test('with-mutators return a new instance preserving other fields', () {
      const before = ExportOptions(
        includeSessions: false,
        includeConfig: true,
        includeKnownHosts: false,
        includeEmbeddedKeys: true,
      );
      final after = before.withIncludePasswords(true);
      expect(identical(before, after), isFalse);
      expect(after.includePasswords, isTrue);
      expect(after.includeSessions, before.includeSessions);
      expect(after.includeConfig, before.includeConfig);
      expect(after.includeKnownHosts, before.includeKnownHosts);
      expect(after.includeEmbeddedKeys, before.includeEmbeddedKeys);
    });

    // Spec: value equality + hashCode. Two equivalently-configured
    // ExportOptions must compare equal so widget-side `setState` can
    // skip a rebuild when the user re-applies the same shape; a bug
    // here defeats every memoization the unified export dialog relies
    // on.
    test('value equality and hashCode match for equivalent configurations', () {
      const a = ExportOptions(includePasswords: true, includeTags: true);
      const b = ExportOptions(includePasswords: true, includeTags: true);
      const c = ExportOptions(includePasswords: false, includeTags: true);
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(equals(c)));
    });
  });

  group('ExportLink / ExportFolderTagLink', () {
    // Spec: these are the const-constructed link shapes the import
    // payload carries. They hold the foreign-key pair so a future
    // schema change that, say, renamed `sessionId` to `srcId` would
    // need conscious downstream updates — pin the field names.
    test('ExportLink carries the (sessionId, targetId) pair verbatim', () {
      const link = ExportLink(sessionId: 's-1', targetId: 't-1');
      expect(link.sessionId, 's-1');
      expect(link.targetId, 't-1');
    });

    test('ExportFolderTagLink carries (folderPath, tagId) verbatim', () {
      const link = ExportFolderTagLink(folderPath: 'infra/prod', tagId: 't-2');
      expect(link.folderPath, 'infra/prod');
      expect(link.tagId, 't-2');
    });
  });
}
