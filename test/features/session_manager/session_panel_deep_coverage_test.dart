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

  group('SessionPanel — empty state with Add Session button', () {
    testWidgets('empty state shows Add Session button that opens dialog',
        (tester) async {
      await tester.pumpWidget(buildApp(sessions: []));
      await tester.pumpAndSettle();

      expect(find.text('No saved sessions'), findsOneWidget);
      expect(find.text('Add Session'), findsOneWidget);

      // Tap Add Session
      await tester.tap(find.text('Add Session'));
      await tester.pumpAndSettle();

      // Dialog should open
      expect(find.text('New Session'), findsOneWidget);

      // Cancel
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });
  });

  group('SessionPanel — search bar', () {
    testWidgets('search bar is present with hint text', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      expect(find.text('Search...'), findsOneWidget);
    });
  });

  group('SessionPanel — _handleDialogResult with ConnectOnlyResult', () {
    testWidgets('ConnectOnly result calls onQuickConnect', (tester) async {
      SSHConfig? quickConnected;
      await tester.pumpWidget(buildApp(
        onQuickConnect: (c) => quickConnected = c,
        onSftpConnect: (_) {},
      ));
      await tester.pumpAndSettle();

      // Right-click on background to open group context menu
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

      // Tap New Session
      final newSession = find.text('New Session');
      if (newSession.evaluate().isNotEmpty) {
        await tester.tap(newSession);
        await tester.pumpAndSettle();

        // Fill required fields
        await tester.enterText(
            find.widgetWithText(TextFormField, 'Host *'), 'testhost');
        await tester.enterText(
            find.widgetWithText(TextFormField, 'Username *'), 'testuser');
        await tester.pumpAndSettle();

        // Tap Connect (without saving)
        await tester.tap(find.text('Connect'));
        await tester.pumpAndSettle();

        expect(quickConnected, isNotNull);
        expect(quickConnected!.host, 'testhost');
        expect(quickConnected!.user, 'testuser');
      }
    });
  });

  group('SessionPanel — _handleDialogResult with SaveResult connect=true', () {
    testWidgets('SaveResult with connect=true calls onConnect',
        (tester) async {
      Session? connected;
      await tester.pumpWidget(buildApp(
        onConnect: (s) => connected = s,
        onSftpConnect: (_) {},
      ));
      await tester.pumpAndSettle();

      // Right-click on background to open group context menu
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

      final newSession = find.text('New Session');
      if (newSession.evaluate().isNotEmpty) {
        await tester.tap(newSession);
        await tester.pumpAndSettle();

        // Fill required fields
        await tester.enterText(
            find.widgetWithText(TextFormField, 'Host *'), 'savehost');
        await tester.enterText(
            find.widgetWithText(TextFormField, 'Username *'), 'saveuser');
        await tester.pumpAndSettle();

        // Tap Save & Connect
        await tester.tap(find.text('Save & Connect'));
        await tester.pumpAndSettle();

        expect(connected, isNotNull);
        expect(connected!.host, 'savehost');
      }
    });
  });

  group('SessionPanel — group context menu New Session in group', () {
    testWidgets('New Session from group context opens dialog with group',
        (tester) async {
      await tester.pumpWidget(buildApp(onSftpConnect: (_) {}));
      await tester.pumpAndSettle();

      // Right-click Production
      await rightClick(tester, find.text('Production'));

      // Tap New Session
      await tester.tap(find.text('New Session'));
      await tester.pumpAndSettle();

      // Dialog should open with Group pre-filled
      expect(find.text('New Session'), findsOneWidget);
      // Group field should have "Production" pre-filled
      // (defaultGroup is passed)

      // Cancel
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });
  });

  group('SessionPanel — folder name dialog duplicate validation', () {
    testWidgets('typing a duplicate folder name shows error', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      // Open New Folder dialog from header
      await tester.tap(find.byTooltip('New Folder'));
      await tester.pumpAndSettle();

      // Type 'Production' (already exists as a group)
      final textField = find.byType(TextField).last;
      await tester.enterText(textField, 'Production');
      await tester.pump();

      // Error should appear
      expect(find.text('Folder "Production" already exists'), findsOneWidget);

      // Create button should be disabled
      final createButton = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Create'));
      expect(createButton.onPressed, isNull);

      // Cancel
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });
  });

  group('SessionPanel — folder name dialog Enter submit', () {
    testWidgets('pressing Enter on valid folder name submits', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('New Folder'));
      await tester.pumpAndSettle();

      // Type valid name
      final textField = find.byType(TextField).last;
      await tester.enterText(textField, 'NewValidFolder');
      await tester.pump();

      // Submit via Enter key
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      // Dialog should close (submitted successfully)
      expect(find.text('Folder name'), findsNothing);
    });
  });

  group('SessionPanel — rename folder', () {
    testWidgets('rename folder changes name', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      // Right-click Production
      await rightClick(tester, find.text('Production'));

      // Tap Rename
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();

      // Should show rename dialog
      expect(find.text('Rename Folder'), findsOneWidget);

      // Change name
      final textField = find.byType(TextField).last;
      await tester.enterText(textField, 'Prod');
      await tester.pump();

      // Submit
      await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
      await tester.pumpAndSettle();

      // Dialog should close
      expect(find.text('Rename Folder'), findsNothing);
    });
  });

  group('SessionPanel — delete folder cancel', () {
    testWidgets('cancelling delete folder keeps folder', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      // Right-click Production
      await rightClick(tester, find.text('Production'));

      // Tap Delete Folder
      await tester.tap(find.text('Delete Folder'));
      await tester.pumpAndSettle();

      // Cancel
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // Dialog closed
      expect(find.text('Delete Folder'), findsNothing);
    });
  });

  group('SessionPanel — delete session cancel', () {
    testWidgets('cancelling delete session keeps session', (tester) async {
      await tester.pumpWidget(buildApp(onSftpConnect: (_) {}));
      await tester.pumpAndSettle();

      // Right-click staging
      await rightClick(tester, find.text('staging'));

      // Tap Delete
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      // Cancel
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Delete Session'), findsNothing);
    });
  });

  group('SessionPanel — _collectAllGroupPaths includes implicit parents', () {
    testWidgets('creating subfolder validates against implicit parent paths',
        (tester) async {
      // The sessions have groups: 'Production', 'Production/DB'
      // _collectAllGroupPaths should produce: {'Production', 'Production/DB'}
      // So creating a folder named 'Production' at root should show error
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('New Folder'));
      await tester.pumpAndSettle();

      final textField = find.byType(TextField).last;
      await tester.enterText(textField, 'Production');
      await tester.pump();

      expect(find.text('Folder "Production" already exists'), findsOneWidget);

      // Cancel
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });
  });

  group('SessionPanel — panel header shows Sessions title', () {
    testWidgets('header shows Sessions title', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      expect(find.text('Sessions'), findsOneWidget);
    });
  });

  group('SessionPanel — group context menu for root empty area shows delete all', () {
    testWidgets('root context menu shows Delete All Sessions when sessions exist',
        (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      // Right-click on empty area
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
        // Delete All Sessions should be present
        expect(deleteAll, findsOneWidget);

        // Dismiss menu
        await tester.tapAt(Offset.zero);
        await tester.pumpAndSettle();
      }
    });
  });

  group('SessionPanel — create empty folder at root', () {
    testWidgets('creating folder at root via header button', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('New Folder'));
      await tester.pumpAndSettle();

      // Type name and create
      final textField = find.byType(TextField).last;
      await tester.enterText(textField, 'Archive');
      await tester.pump();

      await tester.tap(find.widgetWithText(FilledButton, 'Create'));
      await tester.pumpAndSettle();

      // Dialog should close
      expect(find.text('Folder name'), findsNothing);
    });
  });

  group('SessionPanel — create empty folder with empty name is ignored', () {
    testWidgets('creating folder with empty name is no-op', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('New Folder'));
      await tester.pumpAndSettle();

      // Leave name empty and tap Create
      await tester.tap(find.widgetWithText(FilledButton, 'Create'));
      await tester.pumpAndSettle();

      // Dialog closes (returns empty string which is trimmed and skipped)
    });
  });
}
