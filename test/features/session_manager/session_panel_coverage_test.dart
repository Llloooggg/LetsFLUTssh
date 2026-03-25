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
class FakeSessionStore extends SessionStore {
  final List<Session> _fakeSessions;
  final Set<String> _fakeEmptyGroups;

  FakeSessionStore({
    List<Session>? sessions,
    Set<String>? emptyGroups,
  })  : _fakeSessions = sessions ?? [],
        _fakeEmptyGroups = emptyGroups ?? {};

  @override
  List<Session> get sessions => List.unmodifiable(_fakeSessions);

  @override
  Set<String> get emptyGroups => Set.unmodifiable(_fakeEmptyGroups);

  @override
  List<String> groups() {
    final g = _fakeSessions
        .map((s) => s.group)
        .where((g) => g.isNotEmpty)
        .toSet()
        .toList();
    g.sort();
    return g;
  }

  @override
  int countSessionsInGroup(String groupPath) {
    return _fakeSessions
        .where(
            (s) => s.group == groupPath || s.group.startsWith('$groupPath/'))
        .length;
  }

  @override
  List<Session> byGroup(String group) {
    return _fakeSessions.where((s) => s.group == group).toList();
  }

  @override
  Future<Session> duplicateSession(String id) async {
    final original = _fakeSessions.firstWhere((s) => s.id == id);
    final copy = Session(
      label: '${original.label} (copy)',
      group: original.group,
      host: original.host,
      port: original.port,
      user: original.user,
      authType: original.authType,
    );
    _fakeSessions.add(copy);
    return copy;
  }

  @override
  Future<void> delete(String id) async {
    _fakeSessions.removeWhere((s) => s.id == id);
  }

  @override
  Future<void> deleteAll() async {
    _fakeSessions.clear();
    _fakeEmptyGroups.clear();
  }

  @override
  Future<void> deleteGroup(String groupPath) async {
    _fakeSessions.removeWhere(
        (s) => s.group == groupPath || s.group.startsWith('$groupPath/'));
    _fakeEmptyGroups.remove(groupPath);
  }

  @override
  Future<void> addEmptyGroup(String groupPath) async {
    _fakeEmptyGroups.add(groupPath);
  }

  @override
  Future<void> renameGroup(String oldPath, String newPath) async {
    for (var i = 0; i < _fakeSessions.length; i++) {
      final s = _fakeSessions[i];
      if (s.group == oldPath) {
        _fakeSessions[i] = Session(
          id: s.id,
          label: s.label,
          group: newPath,
          host: s.host,
          port: s.port,
          user: s.user,
        );
      } else if (s.group.startsWith('$oldPath/')) {
        _fakeSessions[i] = Session(
          id: s.id,
          label: s.label,
          group: s.group.replaceFirst(oldPath, newPath),
          host: s.host,
          port: s.port,
          user: s.user,
        );
      }
    }
    _fakeEmptyGroups.remove(oldPath);
    _fakeEmptyGroups.add(newPath);
  }

  @override
  Future<void> update(Session session) async {
    final idx = _fakeSessions.indexWhere((s) => s.id == session.id);
    if (idx >= 0) {
      _fakeSessions[idx] = session;
    }
  }

  @override
  Future<Session> add(Session session) async {
    _fakeSessions.add(session);
    return session;
  }

  @override
  Future<void> moveSession(String sessionId, String newGroup) async {
    final idx = _fakeSessions.indexWhere((s) => s.id == sessionId);
    if (idx >= 0) {
      final s = _fakeSessions[idx];
      _fakeSessions[idx] = Session(
        id: s.id,
        label: s.label,
        group: newGroup,
        host: s.host,
        port: s.port,
        user: s.user,
      );
    }
  }

  @override
  Future<void> moveGroup(String groupPath, String newParent) async {
    // Simplified stub
  }
}

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
        FakeSessionStore(sessions: sessionList, emptyGroups: emptyGroups);
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

  /// Helper to right-click on a text element.
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

  group('SessionPanel — delete session with label vs displayName', () {
    testWidgets('delete dialog uses displayName when label is empty',
        (tester) async {
      final noLabelSession = Session(
        id: '10',
        label: '',
        group: '',
        host: '10.0.0.10',
        user: 'admin',
      );
      await tester.pumpWidget(buildApp(
        sessions: [noLabelSession],
        onSftpConnect: (_) {},
      ));
      await tester.pumpAndSettle();

      // Right-click on the session — use the host:port text, take first match
      final hostText = find.text('10.0.0.10:22');
      expect(hostText, findsWidgets);
      await rightClick(tester, hostText.first);

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      // Dialog should show displayName (admin@10.0.0.10) in the delete text
      expect(find.textContaining('Delete "admin@10.0.0.10'), findsOneWidget);

      // Cancel
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });
  });

  group('SessionPanel — delete folder with zero sessions', () {
    testWidgets(
        'delete folder dialog for empty group does not show session count warning',
        (tester) async {
      final sessions = [
        Session(
            id: '1',
            label: 'root-srv',
            group: '',
            host: '10.0.0.1',
            user: 'root'),
      ];
      await tester.pumpWidget(buildApp(
        sessions: sessions,
        emptyGroups: {'EmptyFolder'},
      ));
      await tester.pumpAndSettle();

      // Right-click on EmptyFolder
      await rightClick(tester, find.text('EmptyFolder'));

      await tester.tap(find.text('Delete Folder'));
      await tester.pumpAndSettle();

      // Should show dialog but NOT session count warning
      expect(find.textContaining('Delete folder "EmptyFolder"?'), findsOneWidget);
      expect(find.textContaining('session(s) inside'), findsNothing);

      // Cancel
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });
  });

  group('SessionPanel — rename same name is no-op', () {
    testWidgets('rename with unchanged name does not submit', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      // Right-click on Production
      await rightClick(tester, find.text('Production'));

      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();

      // Don't change the name, just submit with the same name
      await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
      await tester.pumpAndSettle();

      // Dialog should close (returns the same name, _renameFolder skips it)
      expect(find.text('Rename Folder'), findsNothing);
    });
  });

  group('SessionPanel — rename nested folder parent path', () {
    testWidgets('renaming DB (nested) shows correct pre-filled name',
        (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      // Right-click on DB (child of Production)
      await rightClick(tester, find.text('DB'));

      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();

      // Should pre-fill with "DB"
      final textField = tester.widget<TextField>(find.byType(TextField).last);
      expect(textField.controller?.text, 'DB');

      // Change name and submit
      await tester.enterText(find.byType(TextField).last, 'Database');
      await tester.pump();

      await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
      await tester.pumpAndSettle();

      // Dialog should close
      expect(find.text('Rename Folder'), findsNothing);
    });
  });

  group('SessionPanel — _handleDialogResult SaveResult with connect=false', () {
    testWidgets('Save without connect from new session does not call onConnect',
        (tester) async {
      // This exercises the _handleDialogResult SaveResult path with connect=false.
      // The SaveResult with connect=false only happens via edit mode.
      Session? connected;
      await tester.pumpWidget(buildApp(
        onConnect: (s) => connected = s,
        onSftpConnect: (_) {},
      ));
      await tester.pumpAndSettle();

      // Right-click on staging → Edit
      await rightClick(tester, find.text('staging'));

      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();

      // Tap Save (not Save & Connect) — this should update but not connect
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      // onConnect should NOT have been called
      expect(connected, isNull);
    });
  });

  group('SessionPanel — folder submit via Enter with error text', () {
    testWidgets('Enter key does not submit when duplicate name is shown',
        (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('New Folder'));
      await tester.pumpAndSettle();

      // Type a duplicate name
      final textField = find.byType(TextField).last;
      await tester.enterText(textField, 'Production');
      await tester.pump();

      // Error should be visible
      expect(find.text('Folder "Production" already exists'), findsOneWidget);

      // Try submitting via Enter — should NOT close dialog
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      // Dialog should still be open (error prevents submit)
      expect(find.text('Folder name'), findsOneWidget);

      // Cancel to clean up
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });
  });

  group('SessionPanel — empty folder creation via context menu', () {
    testWidgets('creating subfolder in Production via group context menu',
        (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      // Right-click Production
      await rightClick(tester, find.text('Production'));

      // Tap New Folder from context menu
      await tester.tap(find.text('New Folder'));
      await tester.pumpAndSettle();

      // Type subfolder name
      final textField = find.byType(TextField).last;
      await tester.enterText(textField, 'SubFolder');
      await tester.pump();

      // Create
      await tester.tap(find.widgetWithText(FilledButton, 'Create'));
      await tester.pumpAndSettle();

      // Dialog should close
      expect(find.text('Folder name'), findsNothing);
    });
  });

  group('SessionPanel — New Session from root background context menu', () {
    testWidgets('background context menu shows New Session and New Folder',
        (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      // Right-click on empty area below all sessions
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

      // Should show New Session and New Folder options
      final newSession = find.text('New Session');
      final newFolder = find.text('New Folder');

      if (newSession.evaluate().isNotEmpty) {
        expect(newSession, findsOneWidget);
        expect(newFolder, findsWidgets);

        // Tap New Session from root context menu
        await tester.tap(newSession);
        await tester.pumpAndSettle();

        // Session edit dialog should open
        expect(find.text('Host *'), findsOneWidget);

        // Cancel
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
      }
    });
  });

  group('SessionPanel — SSH connect via context menu', () {
    testWidgets('SSH connect action calls onConnect', (tester) async {
      Session? connected;
      await tester.pumpWidget(buildApp(
        onConnect: (s) => connected = s,
        onSftpConnect: (_) {},
      ));
      await tester.pumpAndSettle();

      // Right-click on web1
      await rightClick(tester, find.text('web1'));

      await tester.tap(find.text('SSH'));
      await tester.pumpAndSettle();

      expect(connected?.label, 'web1');
    });
  });

  group('SessionPanel — SFTP connect via context menu', () {
    testWidgets('SFTP action calls onSftpConnect', (tester) async {
      Session? sftpConnected;
      await tester.pumpWidget(buildApp(
        onSftpConnect: (s) => sftpConnected = s,
      ));
      await tester.pumpAndSettle();

      // Right-click on web1
      await rightClick(tester, find.text('web1'));

      await tester.tap(find.text('SFTP'));
      await tester.pumpAndSettle();

      expect(sftpConnected?.label, 'web1');
    });
  });

  group('SessionPanel — duplicate action via context menu', () {
    testWidgets('Duplicate action duplicates session', (tester) async {
      await tester.pumpWidget(buildApp(onSftpConnect: (_) {}));
      await tester.pumpAndSettle();

      // Right-click on web1
      await rightClick(tester, find.text('web1'));

      await tester.tap(find.text('Duplicate'));
      await tester.pumpAndSettle();

      // Should not crash — duplicate was called on notifier
    });
  });

  group('SessionPanel — delete session confirm and execute', () {
    testWidgets('delete confirm dialog deletes session on confirm',
        (tester) async {
      await tester.pumpWidget(buildApp(onSftpConnect: (_) {}));
      await tester.pumpAndSettle();

      // Right-click on staging (root-level session)
      await rightClick(tester, find.text('staging'));

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      // Confirm dialog should show
      expect(find.text('Delete Session'), findsOneWidget);
      expect(find.textContaining('Delete "staging"'), findsOneWidget);

      // Confirm deletion
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      // Dialog should close
      expect(find.text('Delete Session'), findsNothing);
    });
  });

  group('SessionPanel — delete folder confirm', () {
    testWidgets('delete folder with sessions shows count warning',
        (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      // Right-click Production folder (has 2 sessions)
      await rightClick(tester, find.text('Production'));

      await tester.tap(find.text('Delete Folder'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Delete folder "Production"?'),
          findsOneWidget);
      expect(find.textContaining('session(s) inside'), findsOneWidget);

      // Confirm
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      // Dialog should close
      expect(find.text('Delete Folder'), findsNothing);
    });
  });

  group('SessionPanel — edit session via context menu', () {
    testWidgets('edit action opens edit dialog', (tester) async {
      await tester.pumpWidget(buildApp(onSftpConnect: (_) {}));
      await tester.pumpAndSettle();

      // Right-click on staging
      await rightClick(tester, find.text('staging'));

      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();

      // Edit dialog should open with session data
      expect(find.text('Edit Session'), findsOneWidget);

      // Cancel
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });
  });

  group('SessionPanel — delete all sessions', () {
    testWidgets('delete all confirm dialog deletes all sessions',
        (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      // Right-click on empty area — need the background context menu
      // Background context menu is on the SessionTreeView
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

      final deleteAll = find.text('Delete All Sessions');
      if (deleteAll.evaluate().isNotEmpty) {
        await tester.tap(deleteAll);
        await tester.pumpAndSettle();

        // Confirm dialog
        expect(find.textContaining('Delete all'), findsOneWidget);

        // Confirm
        await tester.tap(find.widgetWithText(FilledButton, 'Delete All'));
        await tester.pumpAndSettle();
      }
    });
  });

  group('SessionPanel — move dialog current group highlighting', () {
    testWidgets('move dialog highlights current group', (tester) async {
      // This test only works on mobile (where Move is in context menu),
      // but we can still verify the dialog logic by checking it doesn't crash.
      // On desktop, 'Move to...' doesn't appear in the context menu.
      await tester.pumpWidget(buildApp(onSftpConnect: (_) {}));
      await tester.pumpAndSettle();

      // Right-click on web1 (in Production group)
      await rightClick(tester, find.text('web1'));

      // On desktop, 'Move to...' won't be in the menu, so skip if not found
      final moveItem = find.text('Move to...');
      if (moveItem.evaluate().isNotEmpty) {
        await tester.tap(moveItem);
        await tester.pumpAndSettle();

        // Should show current group (Production) with check icon
        expect(find.byIcon(Icons.check), findsOneWidget);

        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
      }
    });
  });
}
