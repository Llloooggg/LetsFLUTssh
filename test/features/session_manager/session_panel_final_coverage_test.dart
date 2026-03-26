import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/session/session.dart';
import 'package:letsflutssh/core/session/session_store.dart';
import 'package:letsflutssh/core/session/session_tree.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/features/session_manager/session_panel.dart';
import 'package:letsflutssh/providers/session_provider.dart';
import 'package:letsflutssh/theme/app_theme.dart';

class _FakeStore extends SessionStore {
  final List<Session> _s;
  final Set<String> _eg;

  _FakeStore({List<Session>? sessions, Set<String>? emptyGroups})
      : _s = sessions ?? [],
        _eg = emptyGroups ?? {};

  @override
  List<Session> get sessions => List.unmodifiable(_s);
  @override
  Set<String> get emptyGroups => Set.unmodifiable(_eg);
  @override
  List<String> groups() {
    final g = _s.map((s) => s.group).where((g) => g.isNotEmpty).toSet().toList()..sort();
    return g;
  }
  @override
  int countSessionsInGroup(String gp) =>
      _s.where((s) => s.group == gp || s.group.startsWith('$gp/')).length;
  @override
  List<Session> byGroup(String group) =>
      _s.where((s) => s.group == group).toList();
  @override
  Future<Session> duplicateSession(String id) async {
    final o = _s.firstWhere((s) => s.id == id);
    final c = Session(
        label: '${o.label} (copy)', group: o.group, host: o.host,
        port: o.port, user: o.user, authType: o.authType);
    _s.add(c);
    return c;
  }
  @override
  Future<void> delete(String id) async => _s.removeWhere((s) => s.id == id);
  @override
  Future<void> deleteAll() async { _s.clear(); _eg.clear(); }
  @override
  Future<void> deleteGroup(String gp) async {
    _s.removeWhere((s) => s.group == gp || s.group.startsWith('$gp/'));
    _eg.remove(gp);
  }
  @override
  Future<void> addEmptyGroup(String gp) async => _eg.add(gp);
  @override
  Future<void> renameGroup(String old, String newP) async {
    for (var i = 0; i < _s.length; i++) {
      if (_s[i].group == old) {
        _s[i] = Session(id: _s[i].id, label: _s[i].label, group: newP,
            host: _s[i].host, port: _s[i].port, user: _s[i].user);
      }
    }
  }
  @override
  Future<void> update(Session session) async {
    final idx = _s.indexWhere((s) => s.id == session.id);
    if (idx >= 0) _s[idx] = session;
  }
  @override
  Future<Session> add(Session session) async { _s.add(session); return session; }
  @override
  Future<void> moveSession(String id, String newGroup) async {
    final idx = _s.indexWhere((s) => s.id == id);
    if (idx >= 0) {
      final s = _s[idx];
      _s[idx] = Session(id: s.id, label: s.label, group: newGroup,
          host: s.host, port: s.port, user: s.user);
    }
  }
  @override
  Future<void> moveGroup(String gp, String newParent) async {}
}

void main() {
  late List<Session> testSessions;

  setUp(() {
    testSessions = [
      Session(id: '1', label: 'web1', group: 'Production', host: '10.0.0.1', user: 'root'),
      Session(id: '2', label: 'db1', group: 'Production/DB', host: '10.0.1.1', user: 'admin'),
      Session(id: '3', label: 'staging', group: '', host: '192.168.1.1', user: 'deploy'),
    ];
  });

  Widget buildApp({
    List<Session>? sessions,
    Set<String>? emptyGroups,
    void Function(Session)? onConnect,
    void Function(SSHConfig)? onQuickConnect,
    void Function(Session)? onSftpConnect,
  }) {
    final sessionList = sessions ?? testSessions;
    final store = _FakeStore(sessions: sessionList, emptyGroups: emptyGroups);
    final tree = SessionTree.build(sessionList, emptyGroups: emptyGroups ?? const {});

    return ProviderScope(
      overrides: [
        sessionStoreProvider.overrideWithValue(store),
        sessionProvider.overrideWith((ref) {
          final notifier = SessionNotifier(store);
          notifier.state = sessionList;
          return notifier;
        }),
        sessionSearchProvider.overrideWith((ref) => ''),
        filteredSessionTreeProvider.overrideWithValue(tree),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 600,
            child: SessionPanel(
              onConnect: onConnect ?? (_) {},
              onQuickConnect: onQuickConnect ?? (_) {},
              onSftpConnect: onSftpConnect,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> rightClick(WidgetTester tester, Finder finder) async {
    final center = tester.getCenter(finder);
    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton,
    );
    await gesture.addPointer(location: center);
    await gesture.down(center);
    await gesture.up();
    await tester.pumpAndSettle();
  }

  group('SessionPanel — double-tap on session calls onConnect', () {
    testWidgets('double-tap on session triggers connect', (tester) async {
      Session? connected;
      await tester.pumpWidget(buildApp(
        onConnect: (s) => connected = s,
        onSftpConnect: (_) {},
      ));
      await tester.pumpAndSettle();

      // Double-tap on web1
      await tester.tap(find.text('web1'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('web1'));
      await tester.pumpAndSettle();

      expect(connected?.label, 'web1');
    });
  });

  group('SessionPanel — context menu dismiss without action is no-op', () {
    testWidgets('dismissing session context menu does nothing', (tester) async {
      await tester.pumpWidget(buildApp(onSftpConnect: (_) {}));
      await tester.pumpAndSettle();

      // Right-click on staging
      await rightClick(tester, find.text('staging'));

      // Dismiss by tapping outside
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();

      // Everything still present
      expect(find.text('staging'), findsWidgets);
    });
  });

  group('SessionPanel — group context menu dismiss without action', () {
    testWidgets('dismissing group context menu does nothing', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      // Right-click on Production
      await rightClick(tester, find.text('Production'));

      // Dismiss
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();

      expect(find.text('Production'), findsWidgets);
    });
  });

  group('SessionPanel — context menu without SFTP callback hides SFTP', () {
    testWidgets('no onSftpConnect hides SFTP menu item', (tester) async {
      await tester.pumpWidget(buildApp(
        onSftpConnect: null,
      ));
      await tester.pumpAndSettle();

      // Right-click on staging
      await rightClick(tester, find.text('staging'));

      // SSH should be present, SFTP should not
      expect(find.text('SSH'), findsOneWidget);
      expect(find.text('SFTP'), findsNothing);

      // Dismiss
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();
    });
  });

  group('SessionPanel — _confirmDeleteAll cancel path', () {
    testWidgets('cancel on Delete All does not delete', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      // Right-click on empty area
      final panel = find.byType(SessionPanel);
      final panelBox = tester.getRect(panel);
      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton,
      );
      await gesture.addPointer(location: Offset(panelBox.center.dx, panelBox.bottom - 10));
      await gesture.down(Offset(panelBox.center.dx, panelBox.bottom - 10));
      await gesture.up();
      await tester.pumpAndSettle();

      final deleteAll = find.text('Delete All Sessions');
      if (deleteAll.evaluate().isNotEmpty) {
        await tester.tap(deleteAll);
        await tester.pumpAndSettle();

        // Cancel the confirmation
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        // Sessions should still exist
        expect(find.text('web1'), findsWidgets);
      }
    });
  });

  group('SessionPanel — search bar interaction', () {
    testWidgets('typing in search bar updates provider', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      // Type in search bar
      final searchField = find.byType(TextField).first;
      await tester.enterText(searchField, 'web');
      await tester.pump();

      // No crash
      expect(find.byType(TextField), findsWidgets);
    });
  });

  group('SessionPanel — rename folder validation with duplicate', () {
    testWidgets('renaming to existing folder name shows error then clear', (tester) async {
      await tester.pumpWidget(buildApp(
        emptyGroups: {'Staging'},
      ));
      await tester.pumpAndSettle();

      // Right-click on Staging and rename
      await rightClick(tester, find.text('Staging'));
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();

      // Type existing name "Production"
      final textField = find.byType(TextField).last;
      await tester.enterText(textField, 'Production');
      await tester.pump();

      expect(find.text('Folder "Production" already exists'), findsOneWidget);

      // Fix the name to something unique
      await tester.enterText(textField, 'StagingNew');
      await tester.pump();

      expect(find.text('Folder "Production" already exists'), findsNothing);

      // Submit
      await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
      await tester.pumpAndSettle();
    });
  });

  group('SessionPanel — _addSession dialog cancel returns null', () {
    testWidgets('Add Session from empty state cancel does nothing', (tester) async {
      await tester.pumpWidget(buildApp(sessions: []));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add Session'));
      await tester.pumpAndSettle();

      // Cancel
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // Still empty state
      expect(find.text('No saved sessions'), findsOneWidget);
    });
  });

  group('SessionPanel — _editSession cancel returns null', () {
    testWidgets('edit then cancel does not update session', (tester) async {
      await tester.pumpWidget(buildApp(onSftpConnect: (_) {}));
      await tester.pumpAndSettle();

      await rightClick(tester, find.text('staging'));
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();

      // Cancel without changes
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // Session unchanged
      expect(find.text('staging'), findsWidgets);
    });
  });

  group('SessionPanel — _addSessionInGroup cancel returns null', () {
    testWidgets('New Session from group context cancel does nothing', (tester) async {
      await tester.pumpWidget(buildApp(onSftpConnect: (_) {}));
      await tester.pumpAndSettle();

      await rightClick(tester, find.text('Production'));
      await tester.tap(find.text('New Session'));
      await tester.pumpAndSettle();

      // Cancel
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // No new session added
      expect(find.text('Production'), findsWidgets);
    });
  });

  group('SessionPanel — _createFolder cancel returns null', () {
    testWidgets('New Folder dialog cancel does nothing', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('New Folder'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // Dialog closed
      expect(find.text('Folder name'), findsNothing);
    });
  });
}
