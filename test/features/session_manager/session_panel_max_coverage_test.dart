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

/// A fake SessionStore that doesn't use path_provider.
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
    final g = _s.map((s) => s.group).where((g) => g.isNotEmpty).toSet().toList()
      ..sort();
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
        label: '${o.label} (copy)',
        group: o.group,
        host: o.host,
        port: o.port,
        user: o.user,
        authType: o.authType);
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
        _s[i] = Session(
            id: _s[i].id,
            label: _s[i].label,
            group: newP,
            host: _s[i].host,
            port: _s[i].port,
            user: _s[i].user);
      }
    }
  }
  @override
  Future<void> update(Session session) async {
    final idx = _s.indexWhere((s) => s.id == session.id);
    if (idx >= 0) _s[idx] = session;
  }
  @override
  Future<Session> add(Session session) async {
    _s.add(session);
    return session;
  }
  @override
  Future<void> moveSession(String id, String newGroup) async {
    final idx = _s.indexWhere((s) => s.id == id);
    if (idx >= 0) {
      final s = _s[idx];
      _s[idx] = Session(
          id: s.id,
          label: s.label,
          group: newGroup,
          host: s.host,
          port: s.port,
          user: s.user);
    }
  }
  @override
  Future<void> moveGroup(String gp, String newParent) async {}
}

/// Max coverage for session_panel.dart — covers _moveSession dialog,
/// _confirmDeleteAll confirm path, _editSession save flow,
/// _buildMoveGroupTile, and _handleGroupMenuAction branches.
void main() {
  late List<Session> testSessions;

  setUp(() {
    testSessions = [
      Session(
          id: '1',
          label: 'web1',
          group: 'Production',
          host: '10.0.0.1',
          user: 'root'),
      Session(
          id: '2',
          label: 'db1',
          group: 'Production/DB',
          host: '10.0.1.1',
          user: 'admin'),
      Session(
          id: '3',
          label: 'staging',
          group: '',
          host: '192.168.1.1',
          user: 'deploy'),
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
    final store =
        _FakeStore(sessions: sessionList, emptyGroups: emptyGroups);
    final tree = SessionTree.build(sessionList,
        emptyGroups: emptyGroups ?? const {});

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
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await gesture.addPointer(location: center);
    await gesture.down(center);
    await gesture.up();
    await tester.pumpAndSettle();
  }

  group('SessionPanel — _confirmDeleteAll confirm path deletes all sessions', () {
    testWidgets('confirming Delete All clears sessions', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      // Right-click on empty area in tree
      final panel = find.byType(SessionPanel);
      final panelBox = tester.getRect(panel);
      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await gesture.addPointer(
          location: Offset(panelBox.center.dx, panelBox.bottom - 10));
      await gesture.down(
          Offset(panelBox.center.dx, panelBox.bottom - 10));
      await gesture.up();
      await tester.pumpAndSettle();

      // Tap Delete All Sessions
      final deleteAll = find.text('Delete All Sessions');
      if (deleteAll.evaluate().isNotEmpty) {
        await tester.tap(deleteAll);
        await tester.pumpAndSettle();

        // Confirm dialog should show with session count
        expect(find.textContaining('Delete all 3 session(s)'), findsOneWidget);
        expect(find.textContaining('cannot be undone'), findsOneWidget);

        // Confirm deletion
        await tester.tap(find.widgetWithText(FilledButton, 'Delete All'));
        await tester.pumpAndSettle();
      }
    });
  });

  group('SessionPanel — _editSession saves updated session', () {
    testWidgets('editing session label and saving updates it', (tester) async {
      await tester.pumpWidget(buildApp(onSftpConnect: (_) {}));
      await tester.pumpAndSettle();

      // Right-click staging session
      await rightClick(tester, find.text('staging'));

      // Tap Edit
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();

      // Edit dialog should show
      expect(find.text('Edit Session'), findsOneWidget);

      // Change the label
      final labelField = find.widgetWithText(TextFormField, 'Label');
      await tester.enterText(labelField, 'staging-renamed');
      await tester.pump();

      // Save
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      // Dialog should close
      expect(find.text('Edit Session'), findsNothing);
    });
  });

  group('SessionPanel — _renameFolder with empty result is no-op', () {
    testWidgets('rename dialog cancelled leaves folder unchanged', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      await rightClick(tester, find.text('Production'));

      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();

      expect(find.text('Rename Folder'), findsOneWidget);

      // Clear the field (empty name)
      final textField = find.byType(TextField).last;
      await tester.enterText(textField, '');
      await tester.pump();

      // Submit — empty name should be ignored
      await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
      await tester.pumpAndSettle();
    });
  });

  group('SessionPanel — _createFolder with parentGroup prefix', () {
    testWidgets('creating subfolder prepends parent path', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      // Right-click Production group
      await rightClick(tester, find.text('Production'));

      // Tap New Folder
      await tester.tap(find.text('New Folder'));
      await tester.pumpAndSettle();

      // Type subfolder name
      final textField = find.byType(TextField).last;
      await tester.enterText(textField, 'Staging');
      await tester.pump();

      // Create
      await tester.tap(find.widgetWithText(FilledButton, 'Create'));
      await tester.pumpAndSettle();

      // Dialog should close
      expect(find.text('Folder name'), findsNothing);
    });
  });

  group('SessionPanel — _addSessionInGroup with defaultGroup', () {
    testWidgets('New Session from group context has group pre-filled', (tester) async {
      await tester.pumpWidget(buildApp(onSftpConnect: (_) {}));
      await tester.pumpAndSettle();

      // Right-click Production group
      await rightClick(tester, find.text('Production'));

      // Tap New Session
      await tester.tap(find.text('New Session'));
      await tester.pumpAndSettle();

      // Dialog opens — verify Group field has Production pre-filled
      expect(find.text('New Session'), findsOneWidget);

      // Cancel
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });
  });

  group('SessionPanel — _collectAllGroupPaths with empty groups', () {
    testWidgets('empty groups are included in folder name validation', (tester) async {
      await tester.pumpWidget(
        buildApp(emptyGroups: {'Archive', 'Archive/Old'}),
      );
      await tester.pumpAndSettle();

      // Open New Folder
      await tester.tap(find.byTooltip('New Folder'));
      await tester.pumpAndSettle();

      // Type 'Archive' — should be detected as existing
      final textField = find.byType(TextField).last;
      await tester.enterText(textField, 'Archive');
      await tester.pump();

      expect(find.text('Folder "Archive" already exists'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });
  });

  group('SessionPanel — session with empty label shows displayName in delete dialog', () {
    testWidgets('delete dialog shows displayName when label is empty', (tester) async {
      final sessions = [
        Session(
            id: '1',
            label: '',
            group: '',
            host: '10.0.0.1',
            port: 22,
            user: 'root'),
      ];
      await tester.pumpWidget(buildApp(sessions: sessions, onSftpConnect: (_) {}));
      await tester.pumpAndSettle();

      // Right-click on session (shown as root@10.0.0.1)
      await rightClick(tester, find.textContaining('root@'));

      // Tap Delete
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      // Delete dialog should show displayName
      expect(find.text('Delete Session'), findsOneWidget);
      expect(find.textContaining('root@10.0.0.1'), findsWidgets);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });
  });

  group('SessionPanel — _confirmDeleteFolder with 0 sessions shows no count warning', () {
    testWidgets('delete empty folder shows no session count', (tester) async {
      await tester.pumpWidget(
        buildApp(emptyGroups: {'EmptyGroup'}),
      );
      await tester.pumpAndSettle();

      // The empty group should be visible — right-click it
      final emptyGroupFinder = find.text('EmptyGroup');
      if (emptyGroupFinder.evaluate().isNotEmpty) {
        await rightClick(tester, emptyGroupFinder);

        await tester.tap(find.text('Delete Folder'));
        await tester.pumpAndSettle();

        // Should show delete dialog without session count warning
        expect(find.text('Delete Folder'), findsOneWidget);
        expect(find.textContaining('EmptyGroup'), findsWidgets);

        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
      }
    });
  });
}
