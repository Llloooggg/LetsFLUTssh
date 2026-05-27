/// Widget tests for [SessionViaBadge] — the "via X" bastion chip on a
/// session row. Covers the four resolution paths: no proxy jump (hidden),
/// one-off override (host), saved-session bastion (label), and a dangling
/// viaSessionId (a "?" so a deleted bastion is visible, not silent).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/session/session.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/features/session_manager/session_via_badge.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/providers/session_provider.dart';

void main() {
  Session session({String? viaSessionId, ProxyJumpOverride? viaOverride}) {
    return Session(
      id: 's1',
      label: 'Target',
      server: const ServerAddress(host: '10.0.0.1', user: 'root'),
      viaSessionId: viaSessionId,
      viaOverride: viaOverride,
    );
  }

  Future<void> pump(
    WidgetTester tester,
    Session s, {
    Map<String, Session> byId = const {},
  }) {
    return tester.pumpWidget(
      ProviderScope(
        overrides: [sessionsByIdProvider.overrideWithValue(byId)],
        child: MaterialApp(
          localizationsDelegates: S.localizationsDelegates,
          supportedLocales: S.supportedLocales,
          home: Scaffold(
            body: Row(children: [SessionViaBadge(session: s)]),
          ),
        ),
      ),
    );
  }

  testWidgets('renders nothing when the session has no proxy jump', (
    tester,
  ) async {
    await pump(tester, session());
    expect(
      find.descendant(
        of: find.byType(SessionViaBadge),
        matching: find.byType(Text),
      ),
      findsNothing,
    );
  });

  testWidgets('shows the override host for a one-off bastion', (tester) async {
    await pump(
      tester,
      session(
        viaOverride: const ProxyJumpOverride(host: 'jump.example', user: 'j'),
      ),
    );
    expect(find.textContaining('jump.example'), findsOneWidget);
  });

  testWidgets('shows the bastion label for a saved-session jump', (
    tester,
  ) async {
    final bastion = Session(
      id: 'b1',
      label: 'prod-bastion',
      server: const ServerAddress(host: 'b.example', user: 'root'),
    );
    await pump(tester, session(viaSessionId: 'b1'), byId: {'b1': bastion});
    expect(find.textContaining('prod-bastion'), findsOneWidget);
  });

  testWidgets('shows "?" when the referenced bastion is gone', (tester) async {
    // viaSessionId points at a session no longer in the store (FK
    // nulled by the delete cascade) → render "?" so the dangling
    // reference is visible rather than silently dropped.
    await pump(tester, session(viaSessionId: 'deleted'), byId: const {});
    expect(find.textContaining('?'), findsOneWidget);
  });
}
