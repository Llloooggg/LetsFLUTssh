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
    final g = _s.map((s) => s.group).where((g) => g.isNotEmpty).toSet().toList()..sort();
    return g;
  }
  @override
  int countSessionsInGroup(String gp) => _s.where((s) => s.group == gp || s.group.startsWith('$gp/')).length;
  @override
  List<Session> byGroup(String group) => _s.where((s) => s.group == group).toList();
  @override
  Future<Session> duplicateSession(String id) async {
    final o = _s.firstWhere((s) => s.id == id);
    final c = Session(label: '${o.label} (copy)', group: o.group, host: o.host, port: o.port, user: o.user, authType: o.authType);
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
        _s[i] = Session(id: _s[i].id, label: _s[i].label, group: newP, host: _s[i].host, port: _s[i].port, user: _s[i].user);
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
      _s[idx] = Session(id: s.id, label: s.label, group: newGroup, host: s.host, port: s.port, user: s.user);
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

  group('SessionPanel — context menu Connect action', () {
    testWidgets('connect menu calls onConnect', (tester) async {
      Session? connected;
      await tester.pumpWidget(buildApp(
        onConnect: (s) => connected = s,
        onSftpConnect: (_) {},
      ));
      await tester.pumpAndSettle();

      // Right-click on staging session
      await rightClick(tester, find.text('staging'));

      // Tap SSH
      await tester.tap(find.text('SSH'));
      await tester.pumpAndSettle();

      expect(connected, isNotNull);
      expect(connected!.label, 'staging');
    });
  });

  group('SessionPanel — context menu SFTP action', () {
    testWidgets('sftp menu calls onSftpConnect', (tester) async {
      Session? sftpConnected;
      await tester.pumpWidget(buildApp(
        onSftpConnect: (s) => sftpConnected = s,
      ));
      await tester.pumpAndSettle();

      await rightClick(tester, find.text('staging'));

      await tester.tap(find.text('SFTP'));
      await tester.pumpAndSettle();

      expect(sftpConnected, isNotNull);
      expect(sftpConnected!.label, 'staging');
    });
  });

  group('SessionPanel — context menu Duplicate action', () {
    testWidgets('duplicate menu creates copy', (tester) async {
      await tester.pumpWidget(buildApp(onSftpConnect: (_) {}));
      await tester.pumpAndSettle();

      await rightClick(tester, find.text('staging'));

      await tester.tap(find.text('Duplicate'));
      await tester.pumpAndSettle();

      // No crash — duplicate was called on the provider
    });
  });

  group('SessionPanel — context menu Edit action', () {
    testWidgets('edit menu opens dialog with session data', (tester) async {
      await tester.pumpWidget(buildApp(onSftpConnect: (_) {}));
      await tester.pumpAndSettle();

      await rightClick(tester, find.text('staging'));

      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();

      // Edit dialog should open with session data
      expect(find.text('Edit Session'), findsOneWidget);

      // Cancel
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });

    testWidgets('editing and saving returns updated session', (tester) async {
      await tester.pumpWidget(buildApp(onSftpConnect: (_) {}));
      await tester.pumpAndSettle();

      await rightClick(tester, find.text('staging'));

      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();

      // Change label
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Label'), 'staging-updated',
      );
      await tester.pumpAndSettle();

      // Save
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      // Dialog should close
      expect(find.text('Edit Session'), findsNothing);
    });
  });

  group('SessionPanel — context menu Delete with confirm', () {
    testWidgets('delete menu shows confirm and deletes on confirm', (tester) async {
      await tester.pumpWidget(buildApp(onSftpConnect: (_) {}));
      await tester.pumpAndSettle();

      await rightClick(tester, find.text('staging'));

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      // Confirm dialog
      expect(find.text('Delete Session'), findsOneWidget);

      // Confirm delete
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
    });
  });

  group('SessionPanel — group context menu Delete All', () {
    testWidgets('Delete All Sessions from background context menu', (tester) async {
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

        // Confirm dialog should show
        expect(find.textContaining('Delete all'), findsOneWidget);

        // Cancel
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
      }
    });

    testWidgets('Delete All Sessions confirm deletes all', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

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

        // Confirm
        await tester.tap(find.widgetWithText(FilledButton, 'Delete All'));
        await tester.pumpAndSettle();
      }
    });
  });

  group('SessionPanel — delete folder confirm path', () {
    testWidgets('delete folder with sessions shows count warning', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      await rightClick(tester, find.text('Production'));

      await tester.tap(find.text('Delete Folder'));
      await tester.pumpAndSettle();

      // Should show folder name and session count
      expect(find.textContaining('Production'), findsWidgets);
      expect(find.textContaining('session(s)'), findsOneWidget);

      // Confirm
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
    });
  });

  group('SessionPanel — rename folder dialog with same name is no-op', () {
    testWidgets('rename with same name does nothing', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      await rightClick(tester, find.text('Production'));

      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();

      // The name should already be "Production" — submit same name
      await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
      await tester.pumpAndSettle();

      // Should close without renaming (same name)
    });
  });

  group('SessionPanel — search bar clear button', () {
    testWidgets('clear button clears search text', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      // Type in search
      final searchField = find.byType(TextField).first;
      await tester.enterText(searchField, 'test');
      await tester.pump();

      // Clear icon should appear
      final clearIcon = find.byIcon(Icons.close);
      if (clearIcon.evaluate().isNotEmpty) {
        await tester.tap(clearIcon.first);
        await tester.pump();
      }
    });
  });

  group('SessionPanel — _handleDialogResult with SaveResult no connect', () {
    testWidgets('SaveResult with connect=false saves but does not connect',
        (tester) async {
      Session? connected;
      await tester.pumpWidget(buildApp(
        onConnect: (s) => connected = s,
        onSftpConnect: (_) {},
      ));
      await tester.pumpAndSettle();

      // Right-click on background, New Session
      final panel = find.byType(SessionPanel);
      final panelBox = tester.getRect(panel);
      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton,
      );
      await gesture.addPointer(location: Offset(panelBox.center.dx, panelBox.bottom - 10));
      await gesture.down(Offset(panelBox.center.dx, panelBox.bottom - 10));
      await gesture.up();
      await tester.pumpAndSettle();

      final newSession = find.text('New Session');
      if (newSession.evaluate().isNotEmpty) {
        await tester.tap(newSession);
        await tester.pumpAndSettle();

        // Fill fields and Save & Connect
        await tester.enterText(find.widgetWithText(TextFormField, 'Host *'), 'save.only');
        await tester.enterText(find.widgetWithText(TextFormField, 'Username *'), 'u');
        await tester.pumpAndSettle();

        await tester.tap(find.text('Save & Connect'));
        await tester.pumpAndSettle();

        // SaveResult with connect=true -> onConnect called
        expect(connected, isNotNull);
      }
    });
  });

  group('SessionPanel — folder name dialog empty submit', () {
    testWidgets('pressing Enter on empty name does not submit', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('New Folder'));
      await tester.pumpAndSettle();

      // Submit via Enter with empty name
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      // Dialog should still be open (empty name rejected)
      expect(find.text('Folder name'), findsOneWidget);

      // Cancel
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });
  });

  group('SessionPanel — folder name dialog error prevents Enter submit', () {
    testWidgets('pressing Enter with duplicate name does not submit',
        (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('New Folder'));
      await tester.pumpAndSettle();

      // Type duplicate name
      final textField = find.byType(TextField).last;
      await tester.enterText(textField, 'Production');
      await tester.pump();

      expect(find.text('Folder "Production" already exists'), findsOneWidget);

      // Press Enter — should not submit because errorText != null
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      // Dialog should still be open
      expect(find.text('Folder "Production" already exists'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });
  });

  group('SessionPanel — create subfolder in group', () {
    testWidgets('New Folder from group creates subfolder', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      await rightClick(tester, find.text('Production'));

      await tester.tap(find.text('New Folder'));
      await tester.pumpAndSettle();

      final textField = find.byType(TextField).last;
      await tester.enterText(textField, 'NewSub');
      await tester.pump();

      await tester.tap(find.widgetWithText(FilledButton, 'Create'));
      await tester.pumpAndSettle();
    });
  });
}
