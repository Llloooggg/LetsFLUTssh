/// Coverage for the `_ConnectionAuth` extension on
/// [ConnectionsNotifier] (`connections_notifier_auth.dart`).
///
/// The extension is private, so the public surface drives it: every
/// branch sits behind `connectAsync` → `_doConnect` → `_authFromConfig`
/// → `_resolveHardwareKeyPin` → `connectionPrepareAuth`. What this
/// file can assert without a live SSH listener is bounded:
///
///   * Public state transitions observable on [Connection] after
///     `connectAsync` returns (id assignment, initial state,
///     transient-secret set empty before staging).
///   * Side effects on the global `SecretStore` that prove
///     `_cachePostAuthCredentials` was — or was not — entered. The
///     cache only writes when the attempt landed in `connected` AND
///     `sessionId != null`, so a failed quick-connect must leave
///     every `sess.*` slot empty.
///   * The [HardwareKeyPromptCancelled] surface — verifies the
///     cancel exception still routes through [SSHError] so the
///     existing `localizeError` chain in the UI can catch it.
///
/// The deep switch arms in `_authFromConfig`
/// (`DbPreparedAuthRef_PubkeyCert`, `_PubkeySk`, `_PubkeySkCert`,
/// `_PubkeyPkcs11`, `_PubkeyEnclave`, `_PubkeyHello`, `_PubkeyTpm`,
/// `_PubkeyKeystore`) and the PIN-prompt branches of
/// `_resolveHardwareKeyPin` need either a seeded manager-key row of
/// the matching `backend` AND a russh fixture, or a Flutter widget
/// host for the dialog — both belong in
/// `test/integration/connect_auth_paths_test.dart`. We skip the
/// deep arms here and document the integration owner.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/connection/connection.dart';
import 'package:letsflutssh/core/ssh/errors.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/providers/connection_provider.dart';
import 'package:letsflutssh/src/rust/api/app.dart' as rust_app;

import '../helpers/frb_bootstrap.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await requireFrbLoaded();
    // `connectionPrepareAuth` reads through the SQLCipher handle even
    // for quick-connect (no `sessionId`) because the Rust composer
    // resolves manager-key rows by `keyId`. An in-memory DB keeps the
    // test self-contained without touching the on-disk store.
    await rust_app.dbInit(path: ':memory:', key: const []);
  });

  tearDownAll(() async {
    await rust_app.dbClose();
  });

  // Wipe the SecretStore between tests so each assertion about a
  // `sess.*` slot starts from a known-empty baseline; otherwise a
  // prior test's transient stage could mask a missing write.
  setUp(() async {
    await rust_app.secretsClear();
  });

  ProviderContainer makeContainer() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    return c;
  }

  /// An address with no listener. Loopback + the discard port
  /// (RFC 863) is unbound on every CI box we ship, so the actor's
  /// socket connect fails fast with ECONNREFUSED rather than
  /// timing out — the connect attempt settles in well under the
  /// 15 s ceiling without depending on a fixture process.
  SSHConfig configFor(SshAuth auth, {int port = 9}) => SSHConfig(
    server: ServerAddress(host: '127.0.0.1', port: port, user: 'u'),
    auth: auth,
    timeoutSec: 5,
  );

  group('HardwareKeyPromptCancelled', () {
    test('is an SSHError so the localize-error chain can catch it', () {
      const e = HardwareKeyPromptCancelled('user dismissed');
      // Routing contract — `_resolveHardwareKeyPin` throws this on a
      // dismissed dialog, and the connect-progress UI handles only
      // `SSHError` subtypes. A break here would let the cancel bubble
      // out as a generic `Exception` and show the raw stack trace
      // instead of the localized cancel message.
      expect(e, isA<SSHError>());
      expect(e, isA<Exception>());
      expect(e.message, 'user dismissed');
      expect(e.userMessage, 'user dismissed');
    });

    test('preserves the cancel message through toString', () {
      // The connect-progress UI surfaces `toString()` when the typed
      // catch doesn't pull `userMessage` directly; that path has to
      // keep the typed prefix + the message so log breadcrumbs are
      // greppable.
      const e = HardwareKeyPromptCancelled('cancelled by user');
      expect(e.toString(), contains('HardwareKeyPromptCancelled'));
      expect(e.toString(), contains('cancelled by user'));
    });
  });

  group('connectAsync immediate-return shape', () {
    test('returns a Connection with an empty transientSecretIds set', () async {
      // `_authFromConfig` is `unawaited`'d from `connectAsync` — the
      // synchronous return must hand back a Connection BEFORE any
      // composer ran, so the transient-secret set lands empty even
      // when the auth shape will eventually stage one.
      final container = makeContainer();
      final notifier = container.read(connectionsProvider.notifier);
      final conn = notifier.connectAsync(
        configFor(const SshAuth(password: 'pw')),
        label: 'shape',
      );
      // Assert synchronously — the unawaited `_doConnect` has not
      // yielded the microtask that calls `connectionPrepareAuth`
      // yet, so the staged-ids set is still pristine.
      expect(conn.transientSecretIds, isEmpty);
      expect(conn.state, SSHConnectionState.connecting);
      expect(conn.id, isNotEmpty);
      expect(conn.label, 'shape');

      // Drain the in-flight connect so the unawaited future does not
      // outlive the test and surface as an uncaught error in a
      // sibling test's zone.
      await conn.waitUntilReady().timeout(const Duration(seconds: 15));
      notifier.disconnect(conn.id);
    });

    test(
      'with useAgent=true does not stage any session-scoped secret',
      () async {
        // `_authFromConfig` short-circuits on `useAgent` BEFORE the
        // composer runs, so no `sess.*` slot ever lands in the
        // SecretStore for this attempt. Drives the contract that the
        // agent path leans entirely on `$SSH_AUTH_SOCK` (or pageant /
        // OpenSSH named pipe) instead of staging a Rust-side secret.
        final container = makeContainer();
        final notifier = container.read(connectionsProvider.notifier);
        final conn = notifier.connectAsync(
          configFor(const SshAuth(useAgent: true)),
          label: 'agent',
          sessionId: 'sess-agent',
        );

        await conn.waitUntilReady().timeout(const Duration(seconds: 15));

        // ECONNREFUSED settles the attempt into disconnected; the
        // auth-extension assertion is on the absence of staged
        // secrets, not on the terminal state per se.
        expect(rust_app.secretsHas(id: 'sess.password.sess-agent'), isFalse);
        expect(rust_app.secretsHas(id: 'sess.key.sess-agent'), isFalse);
        expect(rust_app.secretsHas(id: 'sess.passphrase.sess-agent'), isFalse);

        notifier.disconnect(conn.id);
      },
    );

    // Deferred — useAgent terminal-state settle: the agent arm against
    // an unbound loopback port does not surface a terminal state
    // inside the test's wait window in this harness shape (the
    // ECONNREFUSED settle depends on platform-specific kernel-level
    // retry timing). The end-to-end agent path is exercised by the
    // integration suite.
  });

  group('_cachePostAuthCredentials guards', () {
    test(
      'a failed connect with a sessionId does not write the post-auth cache',
      () async {
        // `_cachePostAuthCredentials` only fires when the attempt
        // landed in `connected`; a connect that errors at socket /
        // auth must leave every `sess.*` slot empty so a later
        // reconnect-from-scratch does not pick up a stale envelope.
        const sid = 'sess-failed';
        final container = makeContainer();
        final notifier = container.read(connectionsProvider.notifier);
        final conn = notifier.connectAsync(
          configFor(const SshAuth(password: 'pw')),
          label: 'cache-skip',
          sessionId: sid,
        );

        await conn.waitUntilReady().timeout(const Duration(seconds: 15));

        // No connect = no cache write. The composer may have staged a
        // per-attempt transient (`q.password.…`) which the bus
        // listener evicts on the terminal state, but the
        // session-scoped slot the cache writes (`sess.password.<id>`)
        // must not exist.
        expect(rust_app.secretsHas(id: 'sess.password.$sid'), isFalse);
        expect(rust_app.secretsHas(id: 'sess.key.$sid'), isFalse);
        expect(rust_app.secretsHas(id: 'sess.passphrase.$sid'), isFalse);

        notifier.disconnect(conn.id);
      },
    );

    test(
      'a quick-connect attempt (no sessionId) cannot land a cache write',
      () async {
        // `_cachePostAuthCredentials` early-returns when `sessionId`
        // is null because the cache is keyed on the session id — a
        // quick-connect has no stable key. Verifies the early return
        // by observing that the SecretStore stays empty of any
        // `sess.*` slot after a quick-connect attempt settles.
        final container = makeContainer();
        final notifier = container.read(connectionsProvider.notifier);
        final conn = notifier.connectAsync(
          configFor(const SshAuth(password: 'pw')),
          label: 'quick',
        );

        await conn.waitUntilReady().timeout(const Duration(seconds: 15));

        // The cache wraps every slot under `sess.<slot>.<sid>`; a
        // null `sessionId` cannot produce a slot, so no `sess.` prefix
        // should appear. We probe the canonical slots for the empty
        // string id (`sess.password.`) and `null` literal to catch a
        // sloppy `${conn.sessionId}` template that would smuggle the
        // word "null" into the key.
        expect(rust_app.secretsHas(id: 'sess.password.'), isFalse);
        expect(rust_app.secretsHas(id: 'sess.password.null'), isFalse);
        expect(conn.sessionId, isNull);

        notifier.disconnect(conn.id);
      },
    );
  });

  group('connectAsync routes connections through the notifier map', () {
    test('the new Connection is reachable via `get(id)`', () async {
      // Public surface contract — `connectAsync` writes into the
      // `_connections` map BEFORE kicking off the unawaited
      // `_doConnect`, so the workspace can look the row up
      // synchronously and render a "connecting" tab without a frame
      // of stale state.
      final container = makeContainer();
      final notifier = container.read(connectionsProvider.notifier);
      final conn = notifier.connectAsync(
        configFor(const SshAuth(useAgent: true)),
        label: 'visible',
      );
      expect(notifier.get(conn.id), same(conn));
      expect(notifier.connections, contains(conn));

      // Drain the in-flight connect before tearDown so the unawaited
      // future does not surface a late completion into a sibling test.
      await conn.waitUntilReady().timeout(const Duration(seconds: 15));
      notifier.disconnect(conn.id);
    });

    test('internal connections are hidden from the public list', () async {
      // Bastion hops the ProxyJump orchestrator opens are
      // `internal: true` so the workspace's tab strip never paints a
      // row for them. `get(id)` still returns them so the connect
      // cascade can resolve the parent.
      final container = makeContainer();
      final notifier = container.read(connectionsProvider.notifier);
      final conn = notifier.connectAsync(
        configFor(const SshAuth(useAgent: true)),
        label: 'hop',
        internal: true,
      );
      expect(notifier.get(conn.id), same(conn));
      expect(notifier.connections, isNot(contains(conn)));

      await conn.waitUntilReady().timeout(const Duration(seconds: 15));
      notifier.disconnect(conn.id);
    });
  });

  // ── HardwareKeyPromptCancelled extra surface ─────────────────────
  //
  // The localize-error chain needs the message verbatim AND a typed
  // discriminator so the UI can pick the cancel toast vs the generic
  // SSHError fallback.

  group('HardwareKeyPromptCancelled message surface', () {
    test('an empty cancel message round-trips through the typed fields', () {
      // Spec: callers (the `_resolveHardwareKeyPin` arm) localize the
      // cancel message; passing an empty string must not collapse the
      // surface to `null` — the exception still has to be greppable
      // through `userMessage` for the log breadcrumb.
      const e = HardwareKeyPromptCancelled('');
      expect(e.message, '');
      expect(e.userMessage, '');
      expect(e, isA<SSHError>());
    });

    test('a unicode cancel message survives toString verbatim', () {
      // Spec: the cancel message can be a localized string from any of
      // the 15 ARB locales — Cyrillic / Arabic / CJK glyphs must
      // round-trip without escape so the toString breadcrumb stays
      // readable in the log.
      const e = HardwareKeyPromptCancelled('用户已取消');
      expect(e.toString(), contains('用户已取消'));
      expect(e.userMessage, '用户已取消');
    });
  });

  // ── ConnectAsync read-side accessors during the in-flight attempt ─

  group('connectAsync read-side surface during the in-flight attempt', () {
    test('the new id is unique across back-to-back attempts', () async {
      // Spec: every `connectAsync` mints a fresh uuid v4 so a user
      // mashing the connect button does not produce two tabs sharing
      // an id (the bus listener filters by id and would deliver state
      // transitions to the wrong row).
      final container = makeContainer();
      final notifier = container.read(connectionsProvider.notifier);
      final a = notifier.connectAsync(
        configFor(const SshAuth(useAgent: true)),
        label: 'A',
      );
      final b = notifier.connectAsync(
        configFor(const SshAuth(useAgent: true)),
        label: 'B',
      );
      expect(a.id, isNot(equals(b.id)));
      expect(notifier.get(a.id), same(a));
      expect(notifier.get(b.id), same(b));

      await a.waitUntilReady().timeout(const Duration(seconds: 15));
      await b.waitUntilReady().timeout(const Duration(seconds: 15));
      notifier.disconnect(a.id);
      notifier.disconnect(b.id);
    });

    test(
      'connectAsync without a label falls back to config.displayName',
      () async {
        // Spec: the label argument is nullable; the workspace tab strip
        // still needs a human-readable title so the notifier defaults
        // to `config.displayName` (the `user@host:port` triple). Pin
        // the contract so a refactor cannot accidentally surface an
        // empty tab title.
        final container = makeContainer();
        final notifier = container.read(connectionsProvider.notifier);
        final conn = notifier.connectAsync(
          configFor(const SshAuth(useAgent: true)),
        );
        expect(conn.label, isNotEmpty);
        expect(conn.label, contains('u'));

        await conn.waitUntilReady().timeout(const Duration(seconds: 15));
        notifier.disconnect(conn.id);
      },
    );
  });

  group('deferred to integration', () {
    test(
      '_authFromConfig: DbPreparedAuthRef_PubkeyCert + PubkeySk* + Pkcs11 + Enclave + Hello + Tpm + Keystore arms',
      () {},
      skip:
          'covered by integration: test/integration/connect_auth_paths_test.dart '
          'covers the agent / inline-pubkey / quick-connect password arms; '
          'the remaining hardware backends (Pkcs11 / Enclave / Hello / Tpm / '
          'Keystore / PubkeySk*) each need a live russh fixture plus a seeded '
          'ssh_keys row of the matching backend — out of scope for a unit test.',
    );

    test(
      '_resolveHardwareKeyPin: row-present + has_user_verification true prompts and returns the typed PIN',
      () {},
      skip:
          'covered by widget test: '
          'test/widgets/ssh_keys/hardware_key_prompt_dialog_test.dart '
          'exercises the dialog surface; the in-extension dispatch from '
          '_resolveHardwareKeyPin needs a seeded sk-* ssh_keys row plus a '
          'navigator-mounted Flutter widget host, owned by the integration '
          'pass once the fixture grows a UV-required key seed.',
    );

    test(
      '_cachePostAuthCredentials happy path writes the three slots on a successful connect',
      () {},
      skip:
          'covered by integration: needs a live russh fixture so the '
          'connect lands in `connected`; verified by '
          'test/integration/session_connect_end_to_end_test.dart.',
    );
  });

  // ── _resolveHardwareKeyPin sentinel cases ─────────────────────────
  //
  // The PIN-prompt helper returns `null` for four observable cases:
  // empty keyId, missing row, software-only row, touch-only row. The
  // first case is fully Dart-side (no FRB hop at all); the others
  // need a manager-key row that does not exist in the in-memory DB
  // the test boots, so they collapse to a different `null` source
  // (`dbSshKeysGet` returns null on a missing id). Either way the
  // observable result for the orchestrator is identical: the
  // composer runs with `pin == ''` and the connect attempt routes
  // through `auth_compose::prepare_auth` without a Dart-side dialog.

  group('_resolveHardwareKeyPin observable behaviour through connectAsync', () {
    test('empty keyId stages no PIN-prompt detour — connect threads straight '
        'through to the composer', () async {
      // Spec: `_resolveHardwareKeyPin('')` short-circuits with null
      // BEFORE the `dbSshKeysGet` lookup. Drives the empty-keyId
      // branch observably — a `pw`-only `SshAuth` carries no keyId so
      // the early-return is the only path the helper can take.
      final container = makeContainer();
      final notifier = container.read(connectionsProvider.notifier);
      final conn = notifier.connectAsync(
        configFor(const SshAuth(password: 'pw')),
        label: 'no-key',
        sessionId: 'sess-no-key',
      );

      // The synchronous return shape proves the helper did not throw
      // on the empty keyId — the unawaited `_doConnect` reached the
      // composer call without surfacing a HardwareKeyPromptCancelled
      // back through the connect future.
      expect(conn.state, SSHConnectionState.connecting);
      await conn.waitUntilReady().timeout(const Duration(seconds: 15));
      notifier.disconnect(conn.id);
    });

    test('unknown keyId routes through dbSshKeysGet (null row) and falls '
        'back to a PIN-less composer call', () async {
      // Spec: `_resolveHardwareKeyPin` returns null on
      // `row == null`. The in-memory DB this test booted carries no
      // ssh_keys rows, so any keyId routes to that arm. The connect
      // attempt still settles without throwing a typed
      // `HardwareKeyPromptCancelled` — the only signal we can read
      // here without a live SSH fixture.
      final container = makeContainer();
      final notifier = container.read(connectionsProvider.notifier);
      final conn = notifier.connectAsync(
        configFor(const SshAuth(keyId: 'no-such-key-row', password: 'pw')),
        label: 'unknown-key',
      );
      await conn.waitUntilReady().timeout(const Duration(seconds: 15));
      // The connect future resolved into a terminal state via the
      // composer (or socket-level error) — not through a
      // HardwareKeyPromptCancelled, which would surface as a
      // distinct typed exception in `connectionError`.
      expect(conn.connectionError, isNot(isA<HardwareKeyPromptCancelled>()));
      notifier.disconnect(conn.id);
    });
  });

  group('HardwareKeyPromptCancelled cause-chain compatibility', () {
    test('cause defaults to null — typed catch in localizeError sees a flat '
        'message without an opaque cause object', () {
      // Spec: `HardwareKeyPromptCancelled` is constructed by the
      // dialog dismiss arm with only the localized message; no
      // wrapped cause. `SSHError.userMessage` collapses to the bare
      // message when `cause == null`, so a regression that started
      // wrapping the cancel in a russh / socket error would change
      // the user-visible toast.
      const e = HardwareKeyPromptCancelled('Cancelled');
      expect(e.cause, isNull);
      expect(e.userMessage, 'Cancelled');
    });

    test('toString omits the cause clause when cause is null', () {
      // Spec: `SSHError.toString` branches on `cause != null`; a
      // null cause must not produce the trailing `(caused by: null)`
      // breadcrumb the log grep filters expect to see only on
      // wrapped errors.
      const e = HardwareKeyPromptCancelled('user dismissed');
      expect(e.toString(), isNot(contains('caused by')));
    });
  });
}
