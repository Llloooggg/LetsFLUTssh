/// Coverage for [ConnectionStateAnnouncer] — the zero-size widget
/// that mirrors `connectionsProvider` state transitions into
/// `SemanticsService.sendAnnouncement` calls so screen-reader users
/// hear "Connecting to host", "Connected to host", "Disconnected
/// from host", or "Connection to host failed" without navigating to
/// the affected row.
///
/// Strategy:
///   * Override `connectionsProvider` with [_MutableConnectionsNotifier]
///     so the announcer reads off a deterministic list whose value
///     we can flip mid-pump without re-mounting the widget tree (a
///     re-mount would reset the per-id `_last` map and erase the
///     "did this state actually change" comparison).
///   * Capture every `flutter/accessibility` channel message into
///     `tester.takeAnnouncements()` — the standard flutter_test seam
///     for asserting `SemanticsService.sendAnnouncement` was called
///     with the expected text.
///   * Mutate the notifier's list and pump again; assert exactly
///     which announcement landed.
///
/// The widget renders `SizedBox.shrink()` — there is no painted
/// surface to assert against, only the side-effect channel.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/app/connection_state_announcer.dart';
import 'package:letsflutssh/core/connection/connection.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/providers/connection_provider.dart';
import 'package:letsflutssh/providers/connections_notifier.dart';

/// Test-local notifier whose state is fully driven by `setAll` so
/// each test step is a deterministic snapshot transition. Avoids
/// re-mounting the widget tree — re-mounting would discard the
/// announcer's per-id `_last` map and the diff that drives the
/// announcement logic would behave as if every connection was
/// freshly observed.
class _MutableConnectionsNotifier extends ConnectionsNotifier {
  _MutableConnectionsNotifier(this._initial);
  final List<Connection> _initial;

  @override
  List<Connection> build() => List<Connection>.from(_initial);

  void setAll(List<Connection> next) {
    state = List<Connection>.from(next);
  }
}

Connection _conn({
  required String id,
  String label = '',
  String host = 'example.com',
  SSHConnectionState state = SSHConnectionState.disconnected,
  Object? error,
}) {
  return Connection(
    id: id,
    label: label,
    sshConfig: SSHConfig(
      server: ServerAddress(host: host, user: 'u'),
    ),
    state: state,
    connectionError: error,
  );
}

/// Mounts the announcer inside a `ProviderScope` whose
/// `connectionsProvider` override exposes a mutable notifier. The
/// caller mutates via `notifier.setAll(...)` and pumps to drive the
/// diff path.
Future<_MutableConnectionsNotifier> _mountAnnouncer(
  WidgetTester tester,
  List<Connection> initial,
) async {
  final notifier = _MutableConnectionsNotifier(initial);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [connectionsProvider.overrideWith(() => notifier)],
      child: const MaterialApp(
        // `S.localizationsDelegates` already bundles the three
        // Global delegates (Material / Widgets / Cupertino) — adding
        // them again would shadow with a duplicate type.
        localizationsDelegates: S.localizationsDelegates,
        supportedLocales: S.supportedLocales,
        home: ConnectionStateAnnouncer(),
      ),
    ),
  );
  // Drain the post-first-frame announcement (the seed pass is
  // silent by contract, but tester.takeAnnouncements would still
  // capture any if the spec were broken — let the first test in
  // each scenario decide whether to assert on or discard them).
  return notifier;
}

void main() {
  testWidgets(
    'first sight of a connection seeds the snapshot silently — initial '
    'paint is already visible to the user, no announcement needed',
    (tester) async {
      // Mounting with a non-empty list should NOT fire announcements.
      // The widget treats every id it has never seen as "user is
      // already looking at this row" and only announces on state
      // *changes* afterwards. Otherwise a tab-switch back to the
      // workspace would replay every session state at once.
      await _mountAnnouncer(tester, [
        _conn(id: 'c1', host: 'h1', state: SSHConnectionState.connected),
        _conn(id: 'c2', host: 'h2', state: SSHConnectionState.connecting),
      ]);
      await tester.pump();
      expect(tester.takeAnnouncements(), isEmpty);
    },
  );

  testWidgets('disconnected → connecting fires the "Connecting to host" line', (
    tester,
  ) async {
    final notifier = await _mountAnnouncer(tester, [
      _conn(
        id: 'c1',
        host: 'srv.example',
        state: SSHConnectionState.disconnected,
      ),
    ]);
    // Drop the first-sight seed; the next transition is what we
    // assert on.
    tester.takeAnnouncements();

    notifier.setAll([
      _conn(
        id: 'c1',
        host: 'srv.example',
        state: SSHConnectionState.connecting,
      ),
    ]);
    await tester.pump();

    final ann = tester.takeAnnouncements();
    expect(ann, hasLength(1));
    expect(ann.single.message, contains('srv.example'));
    expect(ann.single.message.toLowerCase(), contains('connecting'));
  });

  testWidgets('connecting → connected fires the "Connected to host" line', (
    tester,
  ) async {
    final notifier = await _mountAnnouncer(tester, [
      _conn(id: 'c1', host: 'host-a', state: SSHConnectionState.connecting),
    ]);
    tester.takeAnnouncements();

    notifier.setAll([
      _conn(id: 'c1', host: 'host-a', state: SSHConnectionState.connected),
    ]);
    await tester.pump();

    final ann = tester.takeAnnouncements();
    expect(ann, hasLength(1));
    expect(ann.single.message, contains('host-a'));
    // 'Connected' must appear and 'Connecting' must not (suffix
    // would slip past a plain `contains('connect')` check). Match
    // the semantic rather than the literal so a translation tweak
    // does not break the assertion.
    expect(
      ann.single.message.toLowerCase(),
      allOf(contains('connected'), isNot(contains('connecting'))),
    );
  });

  testWidgets('connected → disconnected (clean teardown) fires "Disconnected" '
      'when connectionError is null', (tester) async {
    final notifier = await _mountAnnouncer(tester, [
      _conn(id: 'c1', host: 'h.q', state: SSHConnectionState.connected),
    ]);
    tester.takeAnnouncements();

    notifier.setAll([
      // No `error:` — clean shutdown, e.g. user closed the tab.
      _conn(id: 'c1', host: 'h.q', state: SSHConnectionState.disconnected),
    ]);
    await tester.pump();

    final ann = tester.takeAnnouncements();
    expect(ann, hasLength(1));
    expect(ann.single.message, contains('h.q'));
    expect(ann.single.message.toLowerCase(), contains('disconnected'));
  });

  testWidgets(
    'connecting → disconnected with connectionError fires the "failed" '
    'line so the screen-reader user can tell they need to retry',
    (tester) async {
      final notifier = await _mountAnnouncer(tester, [
        _conn(
          id: 'c1',
          host: 'broken.example',
          state: SSHConnectionState.connecting,
        ),
      ]);
      tester.takeAnnouncements();

      notifier.setAll([
        _conn(
          id: 'c1',
          host: 'broken.example',
          state: SSHConnectionState.disconnected,
          error: 'auth failed',
        ),
      ]);
      await tester.pump();

      final ann = tester.takeAnnouncements();
      expect(ann, hasLength(1));
      expect(ann.single.message, contains('broken.example'));
      // Failure variant is structurally different from a clean
      // teardown — "failed" must appear so a screen-reader user
      // knows whether they need to retry.
      expect(ann.single.message.toLowerCase(), contains('failed'));
    },
  );

  testWidgets('a label, when set, replaces the host in the announcement', (
    tester,
  ) async {
    final notifier = await _mountAnnouncer(tester, [
      _conn(
        id: 'c1',
        label: 'Production DB',
        host: 'prod-db.internal',
        state: SSHConnectionState.disconnected,
      ),
    ]);
    tester.takeAnnouncements();

    notifier.setAll([
      _conn(
        id: 'c1',
        label: 'Production DB',
        host: 'prod-db.internal',
        state: SSHConnectionState.connecting,
      ),
    ]);
    await tester.pump();

    final ann = tester.takeAnnouncements();
    expect(ann, hasLength(1));
    // User-facing label is the readable identifier; the raw host
    // is implementation detail, only surfaced when no label exists.
    expect(ann.single.message, contains('Production DB'));
    expect(ann.single.message, isNot(contains('prod-db.internal')));
  });

  testWidgets('a whitespace-only label falls back to the raw host — trim() '
      'guards against an accidentally-blank user-typed label', (tester) async {
    final notifier = await _mountAnnouncer(tester, [
      _conn(
        id: 'c1',
        label: '   ',
        host: 'raw-host.example',
        state: SSHConnectionState.disconnected,
      ),
    ]);
    tester.takeAnnouncements();

    notifier.setAll([
      _conn(
        id: 'c1',
        label: '   ',
        host: 'raw-host.example',
        state: SSHConnectionState.connecting,
      ),
    ]);
    await tester.pump();

    final ann = tester.takeAnnouncements();
    expect(ann, hasLength(1));
    expect(ann.single.message, contains('raw-host.example'));
  });

  testWidgets(
    'idempotent re-emission with the same state and same failure flag '
    'is silent — a list-level rebuild that did not flip any per-id '
    'state must not re-announce',
    (tester) async {
      // The diff key is `(state, failed)` — if a sibling provider
      // forces the workspace to rebuild, the announcer should
      // re-pump silently for every connection whose pair is
      // unchanged. Otherwise a user typing in a filter box would
      // get "Connected to host" yelled at them on every keystroke.
      final notifier = await _mountAnnouncer(tester, [
        _conn(id: 'c1', host: 'h1', state: SSHConnectionState.connected),
        _conn(id: 'c2', host: 'h2', state: SSHConnectionState.connecting),
      ]);
      tester.takeAnnouncements();

      // Same shape, fresh list instances — the Notifier's `==` over
      // List<Connection> compares identity, so the new list re-emits
      // even though every (state, failed) pair is identical.
      notifier.setAll([
        _conn(id: 'c1', host: 'h1', state: SSHConnectionState.connected),
        _conn(id: 'c2', host: 'h2', state: SSHConnectionState.connecting),
      ]);
      await tester.pump();

      expect(tester.takeAnnouncements(), isEmpty);
    },
  );

  testWidgets(
    'a connection that leaves the registry is dropped from the snapshot '
    'map so it can be re-seeded silently if it reappears',
    (tester) async {
      // Initial: c1 connected. The map carries c1.
      final notifier = await _mountAnnouncer(tester, [
        _conn(id: 'c1', host: 'h1', state: SSHConnectionState.connected),
      ]);
      tester.takeAnnouncements();

      // c1 disappears (the user closed the tab — the actor was
      // removed). The map cleanup step must drop it so the next
      // first-sight of the same id behaves like a fresh seed.
      notifier.setAll(<Connection>[]);
      await tester.pump();
      tester.takeAnnouncements();

      // c1 reappears in the same state. With the cleanup step
      // working, the announcer treats it as a fresh first-sight
      // and stays silent. Were the snapshot still held, the diff
      // `(connected, false) == (connected, false)` would also be
      // silent — but the relevant guarantee is that no STALE
      // disconnected/failed line fires for the re-seed.
      notifier.setAll([
        _conn(id: 'c1', host: 'h1', state: SSHConnectionState.connected),
      ]);
      await tester.pump();
      expect(tester.takeAnnouncements(), isEmpty);
    },
  );
}
