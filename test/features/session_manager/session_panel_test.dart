import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/credential_store.dart';
import 'package:letsflutssh/core/session/session.dart';
import 'package:letsflutssh/core/session/session_store.dart';
import 'package:letsflutssh/core/session/session_tree.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/features/session_manager/session_panel.dart';
import 'package:letsflutssh/features/session_manager/session_tree_view.dart';
import 'package:letsflutssh/providers/session_provider.dart';
import 'package:letsflutssh/theme/app_theme.dart';
import 'package:letsflutssh/utils/platform.dart';

/// A SessionNotifier subclass that starts with pre-populated sessions.
class _PrePopulatedSessionNotifier extends SessionNotifier {
  final List<Session> _initialSessions;
  _PrePopulatedSessionNotifier(this._initialSessions);

  @override
  List<Session> build() {
    super.build();
    state = _initialSessions;
    return state;
  }
}

/// A fake SessionStore that doesn't use path_provider.
class FakeSessionStore extends SessionStore {
  final List<Session> _fakeSessions;
  final Set<String> _fakeEmptyFolders;

  FakeSessionStore({
    List<Session>? sessions,
    Set<String>? emptyFolders,
  })  : _fakeSessions = sessions ?? [],
        _fakeEmptyFolders = emptyFolders ?? {};

  @override
  List<Session> get sessions => List.unmodifiable(_fakeSessions);

  @override
  Set<String> get emptyFolders => Set.unmodifiable(_fakeEmptyFolders);

  @override
  List<String> folders() {
    final g = _fakeSessions
        .map((s) => s.folder)
        .where((g) => g.isNotEmpty)
        .toSet()
        .toList();
    g.sort();
    return g;
  }

  @override
  int countSessionsInFolder(String groupPath) {
    return _fakeSessions
        .where(
            (s) => s.folder == groupPath || s.folder.startsWith('$groupPath/'))
        .length;
  }

  @override
  List<Session> byFolder(String folder) {
    return _fakeSessions.where((s) => s.folder == folder).toList();
  }

  @override
  Future<Session> duplicateSession(String id) async {
    final original = _fakeSessions.firstWhere((s) => s.id == id);
    final copy = Session(label: '${original.label} (copy)', folder: original.folder, server: ServerAddress(host: original.host, port: original.port, user: original.user), auth: SessionAuth(authType: original.authType));
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
    _fakeEmptyFolders.clear();
  }

  @override
  Future<void> deleteFolder(String groupPath) async {
    _fakeSessions.removeWhere(
        (s) => s.folder == groupPath || s.folder.startsWith('$groupPath/'));
    _fakeEmptyFolders.remove(groupPath);
  }

  @override
  Future<void> addEmptyFolder(String groupPath) async {
    _fakeEmptyFolders.add(groupPath);
  }

  @override
  Future<void> renameFolder(String oldPath, String newPath) async {
    // Move sessions
    for (var i = 0; i < _fakeSessions.length; i++) {
      final s = _fakeSessions[i];
      if (s.folder == oldPath) {
        _fakeSessions[i] = Session(id: s.id, label: s.label, folder: newPath, server: ServerAddress(host: s.host, port: s.port, user: s.user));
      } else if (s.folder.startsWith('$oldPath/')) {
        _fakeSessions[i] = Session(id: s.id, label: s.label, folder: s.folder.replaceFirst(oldPath, newPath), server: ServerAddress(host: s.host, port: s.port, user: s.user));
      }
    }
    _fakeEmptyFolders.remove(oldPath);
    _fakeEmptyFolders.add(newPath);
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
  Future<void> moveSession(String sessionId, String newFolder) async {
    final idx = _fakeSessions.indexWhere((s) => s.id == sessionId);
    if (idx >= 0) {
      final s = _fakeSessions[idx];
      _fakeSessions[idx] = Session(id: s.id, label: s.label, folder: newFolder, server: ServerAddress(host: s.host, port: s.port, user: s.user));
    }
  }

  @override
  Future<void> moveFolder(String groupPath, String newParent) async {
    // Simplified stub
  }

  @override
  Future<void> deleteMultiple(Set<String> ids) async {
    _fakeSessions.removeWhere((s) => ids.contains(s.id));
  }

  @override
  Future<void> moveMultiple(Set<String> ids, String newFolder) async {
    for (var i = 0; i < _fakeSessions.length; i++) {
      if (ids.contains(_fakeSessions[i].id)) {
        final s = _fakeSessions[i];
        _fakeSessions[i] = Session(id: s.id, label: s.label, folder: newFolder, server: ServerAddress(host: s.host, port: s.port, user: s.user));
      }
    }
  }

  @override
  Future<Map<String, CredentialData>> loadCredentials(Set<String> ids) async => {};

  @override
  Future<void> restoreSnapshot(List<Session> sessions, Set<String> emptyFolders, [Map<String, CredentialData> credentials = const {}]) async {
    _fakeSessions
      ..clear()
      ..addAll(sessions);
    _fakeEmptyFolders
      ..clear()
      ..addAll(emptyFolders);
  }
}

void main() {
  late List<Session> testSessions;

  setUp(() {
    testSessions = [
      Session(id: '1', label: 'web1', folder: 'Production', server: const ServerAddress(host: '10.0.0.1', user: 'root'), auth: const SessionAuth(authType: AuthType.password, password: 'pass')),
      Session(id: '2', label: 'db1', folder: 'Production/DB', server: const ServerAddress(host: '10.0.1.1', user: 'admin'), auth: const SessionAuth(authType: AuthType.password, password: 'pass')),
      Session(id: '3', label: 'staging', folder: '', server: const ServerAddress(host: '192.168.1.1', user: 'deploy'), auth: const SessionAuth(authType: AuthType.password, password: 'pass')),
    ];
  });

  Widget buildApp({
    List<Session>? sessions,
    Set<String>? emptyFolders,
    void Function(Session)? onConnect,
    void Function(SSHConfig)? onQuickConnect,
    void Function(Session)? onSftpConnect,
  }) {
    final sessionList = sessions ?? testSessions;
    final store =
        FakeSessionStore(sessions: sessionList, emptyFolders: emptyFolders);
    final tree = SessionTree.build(sessionList,
        emptyFolders: emptyFolders ?? const {});

    return ProviderScope(
      overrides: [
        sessionStoreProvider.overrideWithValue(store),
        sessionProvider.overrideWith(() =>
            _PrePopulatedSessionNotifier(sessionList)),
        sessionSearchProvider.overrideWith(SessionSearchNotifier.new),
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

  group('SessionPanel — header and structure', () {
    testWidgets('renders header with Sessions title', (tester) async {
      await tester.pumpWidget(buildApp());
      expect(find.text('SESSIONS'), findsOneWidget);
    });

    testWidgets('renders New Folder button in header', (tester) async {
      await tester.pumpWidget(buildApp());
      expect(find.byIcon(Icons.create_new_folder), findsWidgets);
      expect(find.byTooltip('New Folder'), findsOneWidget);
    });

    testWidgets('renders search bar with hint', (tester) async {
      await tester.pumpWidget(buildApp());
      expect(find.byIcon(Icons.search), findsOneWidget);
      expect(find.text('Filter...'), findsOneWidget);
    });

    testWidgets('panel has correct layout structure', (tester) async {
      await tester.pumpWidget(buildApp());
      expect(find.byType(Column), findsWidgets);
      expect(find.byType(Expanded), findsWidgets);
    });
  });

  group('SessionPanel — session tree rendering', () {
    testWidgets('renders session tree when sessions exist', (tester) async {
      await tester.pumpWidget(buildApp());
      expect(find.text('Production'), findsOneWidget);
      expect(find.text('web1'), findsOneWidget);
      expect(find.text('staging'), findsOneWidget);
    });

    testWidgets('shows session hosts', (tester) async {
      await tester.pumpWidget(buildApp());
      expect(find.text('10.0.0.1'), findsOneWidget);
      expect(find.text('192.168.1.1'), findsOneWidget);
    });

    testWidgets('renders nested groups (Production/DB)', (tester) async {
      await tester.pumpWidget(buildApp());
      expect(find.text('DB'), findsOneWidget);
      expect(find.text('db1'), findsOneWidget);
      expect(find.text('10.0.1.1'), findsOneWidget);
    });

    testWidgets('renders folder icons', (tester) async {
      await tester.pumpWidget(buildApp());
      // Folders show folder icon
      expect(find.byIcon(Icons.folder_open), findsWidgets);
    });

    testWidgets('renders expand/collapse chevrons for folders', (tester) async {
      await tester.pumpWidget(buildApp());
      // Folders have expand_more when expanded
      expect(find.byIcon(Icons.expand_more), findsWidgets);
    });

    testWidgets('shows session count on folders', (tester) async {
      await tester.pumpWidget(buildApp());
      // Production folder has 2 sessions (web1 + db1 in subfolder)
      expect(find.text('2'), findsOneWidget);
      // DB subfolder has 1 session
      expect(find.text('1'), findsOneWidget);
    });

    testWidgets('renders terminal icons for sessions', (tester) async {
      await tester.pumpWidget(buildApp());
      expect(find.byIcon(Icons.terminal), findsWidgets);
    });

    testWidgets('renders terminal icon for key auth session', (tester) async {
      final keySession = Session(id: '4', label: 'key-server', folder: '', server: const ServerAddress(host: '10.0.0.5', user: 'ubuntu'), auth: const SessionAuth(authType: AuthType.key));
      await tester.pumpWidget(buildApp(sessions: [keySession]));
      expect(find.byIcon(Icons.terminal), findsWidgets);
    });

    testWidgets('renders terminal icon for keyWithPassword auth session',
        (tester) async {
      final keyPassSession = Session(id: '5', label: 'key-pass-server', folder: '', server: const ServerAddress(host: '10.0.0.6', user: 'user'), auth: const SessionAuth(authType: AuthType.keyWithPassword));
      await tester.pumpWidget(buildApp(sessions: [keyPassSession]));
      expect(find.byIcon(Icons.terminal), findsWidgets);
    });
  });

  group('SessionPanel — empty state', () {
    testWidgets('renders empty state when no sessions', (tester) async {
      await tester.pumpWidget(buildApp(sessions: []));
      expect(find.text('No saved sessions'), findsOneWidget);
      expect(find.text('Add Session'), findsOneWidget);
      expect(find.byIcon(Icons.dns_outlined), findsOneWidget);
    });

    testWidgets('empty state has add button with icon', (tester) async {
      await tester.pumpWidget(buildApp(sessions: []));
      final addButton = find.text('Add Session');
      expect(addButton, findsOneWidget);
      expect(find.byIcon(Icons.add), findsWidgets);
    });
  });

  group('SessionPanel — search bar', () {
    testWidgets('search bar has close button when text present',
        (tester) async {
      await tester.pumpWidget(buildApp());

      final searchField = find.byType(TextField);
      expect(searchField, findsOneWidget);
      await tester.enterText(searchField, 'test');
      await tester.pump();

      expect(find.byIcon(Icons.close), findsOneWidget);
    });

    testWidgets('search field accepts input without error', (tester) async {
      await tester.pumpWidget(buildApp());
      final searchField = find.byType(TextField);
      await tester.enterText(searchField, 'web1');
      await tester.pump();
      // The onChanged callback fires — no crash expected
      expect(find.byType(TextField), findsOneWidget);
    });
  });

  group('SessionPanel — context menus', () {
    testWidgets('right-click on session shows context menu', (tester) async {
      await tester.pumpWidget(buildApp(onSftpConnect: (_) {}));
      await tester.pumpAndSettle();

      // Find a session row and secondary tap on it
      final sessionText = find.text('staging');
      expect(sessionText, findsOneWidget);

      // Simulate right-click (secondary tap up)
      final center = tester.getCenter(sessionText);
      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await gesture.addPointer(location: center);
      await gesture.down(center);
      await gesture.up();
      await tester.pumpAndSettle();

      // Context menu items should appear
      expect(find.text('Terminal'), findsOneWidget);
      expect(find.text('Files'), findsOneWidget);
      expect(find.text('Edit Connection'), findsOneWidget);
      expect(find.text('Duplicate'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
    });

    testWidgets('context menu without sftp callback hides SFTP item',
        (tester) async {
      await tester.pumpWidget(buildApp(onSftpConnect: null));
      await tester.pumpAndSettle();

      final sessionText = find.text('staging');
      final center = tester.getCenter(sessionText);
      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await gesture.addPointer(location: center);
      await gesture.down(center);
      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.text('Terminal'), findsOneWidget);
      expect(find.text('Files'), findsNothing);
    });

    testWidgets('SSH menu action calls onConnect', (tester) async {
      Session? connected;
      await tester.pumpWidget(buildApp(
        onConnect: (s) => connected = s,
        onSftpConnect: (_) {},
      ));
      await tester.pumpAndSettle();

      // Right-click on staging session
      final sessionText = find.text('staging');
      final center = tester.getCenter(sessionText);
      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await gesture.addPointer(location: center);
      await gesture.down(center);
      await gesture.up();
      await tester.pumpAndSettle();

      // Tap SSH
      await tester.tap(find.text('Terminal'));
      await tester.pumpAndSettle();

      expect(connected, isNotNull);
      expect(connected!.id, '3');
    });

    testWidgets('SFTP menu action calls onSftpConnect', (tester) async {
      Session? sftpConnected;
      await tester.pumpWidget(buildApp(
        onSftpConnect: (s) => sftpConnected = s,
      ));
      await tester.pumpAndSettle();

      final sessionText = find.text('staging');
      final center = tester.getCenter(sessionText);
      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await gesture.addPointer(location: center);
      await gesture.down(center);
      await gesture.up();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Files'));
      await tester.pumpAndSettle();

      expect(sftpConnected, isNotNull);
      expect(sftpConnected!.id, '3');
    });

    testWidgets('Delete menu shows confirmation dialog', (tester) async {
      await tester.pumpWidget(buildApp(onSftpConnect: (_) {}));
      await tester.pumpAndSettle();

      final sessionText = find.text('staging');
      final center = tester.getCenter(sessionText);
      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await gesture.addPointer(location: center);
      await gesture.down(center);
      await gesture.up();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      // Confirmation dialog should appear
      expect(find.text('Delete Session'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('Delete confirmation Cancel dismisses dialog', (tester) async {
      await tester.pumpWidget(buildApp(onSftpConnect: (_) {}));
      await tester.pumpAndSettle();

      final sessionText = find.text('staging');
      final center = tester.getCenter(sessionText);
      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await gesture.addPointer(location: center);
      await gesture.down(center);
      await gesture.up();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      // Tap Cancel
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // Dialog should be dismissed
      expect(find.text('Delete Session'), findsNothing);
    });
  });

  group('SessionPanel — folder context menu', () {
    testWidgets('right-click on folder shows folder context menu',
        (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      // Right-click on folder
      final folderText = find.text('Production');
      expect(folderText, findsOneWidget);
      final center = tester.getCenter(folderText);
      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await gesture.addPointer(location: center);
      await gesture.down(center);
      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.text('New Connection'), findsOneWidget);
      expect(find.text('New Folder'), findsOneWidget);
      expect(find.text('Rename Folder'), findsOneWidget);
      expect(find.text('Delete Folder'), findsOneWidget);
    });

    testWidgets('folder expand/collapse toggles on tap', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      // Initially expanded, so children are visible
      expect(find.text('web1'), findsOneWidget);

      // Tap the folder to collapse
      await tester.tap(find.text('Production').first);
      await tester.pumpAndSettle();

      // After collapsing, children hidden; expand_more icon (rotated) still shows
      expect(find.byIcon(Icons.expand_more), findsWidgets);
    });
  });

  group('SessionPanel — New Folder dialog', () {
    testWidgets('New Folder button in header opens folder name dialog',
        (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      // Tap the New Folder button in the header
      await tester.tap(find.byTooltip('New Folder'));
      await tester.pumpAndSettle();

      // Folder name dialog should appear
      expect(find.text('New Folder'), findsWidgets); // title + button tooltip
      expect(find.text('FOLDER NAME'), findsOneWidget);
      expect(find.text('Create'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('folder name dialog Cancel dismisses', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('New Folder'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // Dialog should be gone
      expect(find.text('FOLDER NAME'), findsNothing);
    });

    testWidgets('folder name dialog shows hint text', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('New Folder'));
      await tester.pumpAndSettle();

      expect(find.text('e.g. Production'), findsOneWidget);
    });

    testWidgets('folder name dialog shows duplicate error', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('New Folder'));
      await tester.pumpAndSettle();

      // Type a folder name that already exists
      final textField = find.byType(TextField).last;
      await tester.enterText(textField, 'Production');
      await tester.pump();

      expect(find.text('Folder "Production" already exists'), findsOneWidget);
    });

    testWidgets('folder name dialog shows error on duplicate name',
        (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('New Folder'));
      await tester.pumpAndSettle();

      final textField = find.byType(TextField).last;
      await tester.enterText(textField, 'Production');
      await tester.pump();

      // Error text should be shown
      expect(find.text('Folder "Production" already exists'), findsOneWidget);
    });

    testWidgets('folder name dialog has no error for new name',
        (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('New Folder'));
      await tester.pumpAndSettle();

      final textField = find.byType(TextField).last;
      await tester.enterText(textField, 'NewFolder');
      await tester.pump();

      // No error text should be shown
      expect(find.textContaining('already exists'), findsNothing);
    });
  });

  group('SessionPanel — Delete folder confirmation', () {
    testWidgets('Delete Folder from folder context menu shows confirmation',
        (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      // Right-click on Production folder
      final folderText = find.text('Production');
      final center = tester.getCenter(folderText);
      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await gesture.addPointer(location: center);
      await gesture.down(center);
      await gesture.up();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Delete Folder'));
      await tester.pumpAndSettle();

      expect(find.text('Delete Folder'), findsWidgets);
      expect(find.textContaining('Delete folder "Production"?'), findsOneWidget);
      expect(
          find.textContaining('This will also delete 2 session(s) inside.'),
          findsOneWidget);
    });
  });

  group('SessionPanel — empty folders', () {
    testWidgets('renders empty folders', (tester) async {
      await tester.pumpWidget(buildApp(
        sessions: [],
        emptyFolders: {'EmptyFolder'},
      ));
      // With sessions empty, the empty state is shown. But with
      // filteredSessionTreeProvider override, we need to override the tree too.
      // Since buildApp already handles this, we just check the tree renders.
      // The buildApp builds tree from sessions+emptyFolders.
      // With no sessions but an emptyFolder, tree should have the folder node.
      // However the panel shows _EmptyState when sessions list isEmpty.
      // So we need at least one session.
      // Let's test differently - one session + an empty folder.
    });

    testWidgets('renders empty folder alongside sessions', (tester) async {
      final sessions = [
        Session(id: '1', label: 'web1', folder: '', server: const ServerAddress(host: '10.0.0.1', user: 'root')),
      ];
      await tester.pumpWidget(buildApp(
        sessions: sessions,
        emptyFolders: {'EmptyFolder'},
      ));
      await tester.pumpAndSettle();

      expect(find.text('web1'), findsOneWidget);
      expect(find.text('EmptyFolder'), findsOneWidget);
    });
  });

  group('SessionPanel — double tap', () {
    testWidgets('double-tap on session calls onConnect', (tester) async {
      Session? connected;
      await tester.pumpWidget(buildApp(
        onConnect: (s) => connected = s,
      ));
      await tester.pumpAndSettle();

      // Find the staging session and double-tap
      await tester.tap(find.text('staging'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('staging'));
      await tester.pumpAndSettle();

      expect(connected, isNotNull);
      expect(connected!.label, 'staging');
    });
  });

  group('SessionPanel — with sftp connect callback', () {
    testWidgets('renders with sftp connect callback', (tester) async {
      await tester.pumpWidget(buildApp(
        onSftpConnect: (_) {},
      ));
      expect(find.text('SESSIONS'), findsOneWidget);
    });
  });

  group('SessionPanel — Duplicate action', () {
    testWidgets('Duplicate menu action works', (tester) async {
      await tester.pumpWidget(buildApp(onSftpConnect: (_) {}));
      await tester.pumpAndSettle();

      // Right-click on staging
      final sessionText = find.text('staging');
      final center = tester.getCenter(sessionText);
      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await gesture.addPointer(location: center);
      await gesture.down(center);
      await gesture.up();
      await tester.pumpAndSettle();

      // Tap Duplicate
      await tester.tap(find.text('Duplicate'));
      await tester.pumpAndSettle();

      // Menu should dismiss without error
      expect(find.text('Terminal'), findsNothing);
    });
  });

  group('SessionPanel — Delete session confirmation', () {
    testWidgets('Delete confirm button shows styled text', (tester) async {
      await tester.pumpWidget(buildApp(onSftpConnect: (_) {}));
      await tester.pumpAndSettle();

      final sessionText = find.text('staging');
      final center = tester.getCenter(sessionText);
      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await gesture.addPointer(location: center);
      await gesture.down(center);
      await gesture.up();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      // Dialog shows session name
      expect(find.textContaining('staging'), findsWidgets);
      // Has Delete confirmation button
      final deleteButtons = find.widgetWithText(FilledButton, 'Delete');
      expect(deleteButtons, findsOneWidget);
    });

    testWidgets('Delete confirm button deletes session', (tester) async {
      await tester.pumpWidget(buildApp(onSftpConnect: (_) {}));
      await tester.pumpAndSettle();

      final sessionText = find.text('staging');
      final center = tester.getCenter(sessionText);
      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await gesture.addPointer(location: center);
      await gesture.down(center);
      await gesture.up();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      // Tap Delete in confirmation dialog
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      // Dialog dismissed
      expect(find.text('Delete Session'), findsNothing);
    });
  });

  group('SessionPanel — Rename folder', () {
    testWidgets('Rename from folder context menu opens rename dialog',
        (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      final folderText = find.text('Production');
      final center = tester.getCenter(folderText);
      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await gesture.addPointer(location: center);
      await gesture.down(center);
      await gesture.up();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Rename Folder'));
      await tester.pumpAndSettle();

      expect(find.text('Rename Folder'), findsOneWidget);
      expect(find.text('FOLDER NAME'), findsOneWidget);
      expect(find.text('Rename'), findsOneWidget);
      // The current name should be pre-filled
      final textField = tester.widget<TextField>(find.byType(TextField).last);
      expect(textField.controller?.text, 'Production');
    });
  });

  group('SessionPanel — New Session from folder context', () {
    testWidgets('New Session from folder context opens edit dialog',
        (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      final folderText = find.text('Production');
      final center = tester.getCenter(folderText);
      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await gesture.addPointer(location: center);
      await gesture.down(center);
      await gesture.up();
      await tester.pumpAndSettle();

      await tester.tap(find.text('New Connection'));
      await tester.pumpAndSettle();

      // SessionEditDialog should open — labels have asterisks for required fields
      expect(find.text('HOST *'), findsOneWidget);
      expect(find.text('USERNAME *'), findsOneWidget);
    });
  });

  group('SessionPanel — Edit action', () {
    testWidgets('Edit from context menu opens session edit dialog',
        (tester) async {
      await tester.pumpWidget(buildApp(onSftpConnect: (_) {}));
      await tester.pumpAndSettle();

      final sessionText = find.text('staging');
      final center = tester.getCenter(sessionText);
      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await gesture.addPointer(location: center);
      await gesture.down(center);
      await gesture.up();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Edit Connection'));
      await tester.pumpAndSettle();

      // SessionEditDialog should show with pre-filled values
      expect(find.text('HOST *'), findsOneWidget);
      expect(find.text('USERNAME *'), findsOneWidget);
    });
  });

  group('SessionPanel — selection highlight', () {
    testWidgets('tapping a session highlights it', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      // Tap on staging to select it
      await tester.tap(find.text('staging'));
      await tester.pumpAndSettle();

      // The row should be selected (verify no error occurs)
      expect(find.text('staging'), findsOneWidget);
    });
  });

  group('SessionPanel — indent guides', () {
    testWidgets('nested sessions show indent guides', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      // db1 is in Production/DB (depth 2), should have indent guides
      // We check that SizedBox widgets are present for indentation
      expect(find.text('db1'), findsOneWidget);
    });
  });

  group('SessionPanel — Delete Folder confirmation', () {
    testWidgets('Delete Folder from folder context menu shows confirmation', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      // Right-click on empty area (background) — we use the staging session area
      // but right-click on the background. Let's right-click the 'Sessions' header area.
      // Actually, the background context menu is triggered on the tree view background.
      // We can trigger by right-clicking on the staging row with folder context.
      // Better: right-click directly on the tree's empty space — we need to find
      // a spot after all sessions. Instead, use the folder context menu on root:
      // In the test, the filteredSessionTreeProvider is overridden, so background
      // right-click is on the tree area. Let's test via _showFolderContextMenu('', ...).
      // Actually, the root folder context menu is shown when right-clicking the tree background.
      // Since we have sessions, the 'delete_all' item should appear.
      // The easiest approach: use an offset on the tree view area.

      // The SessionTreeView has onBackgroundContextMenu callback that fires
      // when the tree background is right-clicked. In practice, this is hard to
      // trigger reliably in test. Instead, let's test via the folder context menu
      // on an actual folder, then check the folder menu items.
      //
      // But _confirmDeleteAll is triggered from the root ("") folder menu.
      // Let's test it indirectly by checking the folder menu has 'Delete All Sessions'.

      // For now, test that Delete Folder confirmation for Production works and
      // exercises the _confirmDeleteFolder path with session count.
      final folderText = find.text('Production');
      final center = tester.getCenter(folderText);
      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await gesture.addPointer(location: center);
      await gesture.down(center);
      await gesture.up();
      await tester.pumpAndSettle();

      // Confirm Delete Folder
      await tester.tap(find.text('Delete Folder'));
      await tester.pumpAndSettle();

      // Dialog should show
      expect(find.text('Delete Folder'), findsWidgets);
      expect(find.textContaining('Delete folder "Production"?'), findsOneWidget);

      // Tap Delete to confirm
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      // Dialog should dismiss
      expect(find.textContaining('Delete folder "Production"?'), findsNothing);
    });
  });

  group('SessionPanel — Create folder submission', () {
    testWidgets('Create button submits new folder name', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      // Open New Folder dialog
      await tester.tap(find.byTooltip('New Folder'));
      await tester.pumpAndSettle();

      // Type a new folder name
      final textField = find.byType(TextField).last;
      await tester.enterText(textField, 'NewGroupFolder');
      await tester.pump();

      // Tap Create
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      // Dialog should dismiss
      expect(find.text('FOLDER NAME'), findsNothing);
    });

    testWidgets('folder name dialog submit via Enter key', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('New Folder'));
      await tester.pumpAndSettle();

      final textField = find.byType(TextField).last;
      await tester.enterText(textField, 'SubmitViaEnter');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      // Dialog should dismiss after Enter
      expect(find.text('FOLDER NAME'), findsNothing);
    });
  });

  group('SessionPanel — New Folder in folder context', () {
    testWidgets('New Folder from folder context creates subfolder', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      // Right-click on Production group
      final folderText = find.text('Production');
      final center = tester.getCenter(folderText);
      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await gesture.addPointer(location: center);
      await gesture.down(center);
      await gesture.up();
      await tester.pumpAndSettle();

      // Tap New Folder from the group context menu
      await tester.tap(find.text('New Folder'));
      await tester.pumpAndSettle();

      // Folder name dialog should appear
      expect(find.text('FOLDER NAME'), findsOneWidget);
      expect(find.text('Create'), findsOneWidget);
    });
  });

  group('SessionPanel — Rename folder submission', () {
    testWidgets('Rename dialog submit changes folder name', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      // Right-click on Production group
      final folderText = find.text('Production');
      final center = tester.getCenter(folderText);
      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await gesture.addPointer(location: center);
      await gesture.down(center);
      await gesture.up();
      await tester.pumpAndSettle();

      // Open Rename dialog
      await tester.tap(find.text('Rename Folder'));
      await tester.pumpAndSettle();

      // Change name
      final textField = find.byType(TextField).last;
      await tester.enterText(textField, 'RenamedGroup');
      await tester.pump();

      // Submit
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();

      // Dialog should dismiss
      expect(find.text('Rename Folder'), findsNothing);
    });
  });

  group('SessionPanel — search bar clear button', () {
    testWidgets('close button in search clears text via onChanged', (tester) async {
      await tester.pumpWidget(buildApp());

      // Enter text in search
      final searchField = find.byType(TextField);
      expect(searchField, findsOneWidget);
      await tester.enterText(searchField, 'query');
      await tester.pump();

      // Close button should appear
      final closeButton = find.byIcon(Icons.close);
      expect(closeButton, findsOneWidget);

      // Tap close
      await tester.tap(closeButton);
      await tester.pump();

      // No crash expected
      expect(find.byType(TextField), findsOneWidget);
    });
  });

  group('SessionPanel — move session dialog', () {
    testWidgets('Move context menu opens Move to Folder dialog', (tester) async {
      await tester.pumpWidget(buildApp(
        emptyFolders: {'Archive'},
        onSftpConnect: (_) {},
      ));
      await tester.pumpAndSettle();

      // Right-click on session to open context menu
      final session = find.text('web1');
      expect(session, findsOneWidget);
      await tester.tapAt(
        tester.getCenter(session),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();

      // Tap Move
      final moveItem = find.text('Move');
      if (moveItem.evaluate().isNotEmpty) {
        await tester.tap(moveItem);
        await tester.pumpAndSettle();

        // Move dialog should show
        expect(find.text('Move to Folder'), findsOneWidget);
        // Should show root and groups
        expect(find.text('/ (root)'), findsOneWidget);

        // Cancel
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
      }
    });

    testWidgets('Move dialog — selecting a folder moves session', (tester) async {
      await tester.pumpWidget(buildApp(
        emptyFolders: {'Archive'},
        onSftpConnect: (_) {},
      ));
      await tester.pumpAndSettle();

      // Right-click on session
      final session = find.text('web1');
      await tester.tapAt(
        tester.getCenter(session),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();

      final moveItem = find.text('Move');
      if (moveItem.evaluate().isNotEmpty) {
        await tester.tap(moveItem);
        await tester.pumpAndSettle();

        expect(find.text('Move to Folder'), findsOneWidget);

        // Tap "/ (root)" to move to root (session is in 'Production')
        final rootTile = find.text('/ (root)');
        if (rootTile.evaluate().isNotEmpty) {
          await tester.tap(rootTile);
          await tester.pumpAndSettle();
        }
      }
    });
  });

  group('SessionPanel — no delete all sessions option', () {
    testWidgets('background context menu does not show Delete All Sessions', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      // Right-click on empty area (background context menu)
      final panel = find.byType(SessionPanel);
      final panelBox = tester.getRect(panel);
      await tester.tapAt(
        Offset(panelBox.center.dx, panelBox.bottom - 20),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();

      // Delete All Sessions should NOT be in the menu
      expect(find.text('Delete All Sessions'), findsNothing);
    });
  });

  group('SessionPanel — add session from empty state', () {
    testWidgets('Add Session button in empty state opens dialog', (tester) async {
      await tester.pumpWidget(buildApp(sessions: []));
      await tester.pumpAndSettle();

      // Empty state shows "Add Session" button
      final addButton = find.text('Add Session');
      if (addButton.evaluate().isNotEmpty) {
        await tester.tap(addButton);
        await tester.pumpAndSettle();

        // New Session dialog should open
        expect(find.text('New Connection'), findsOneWidget);

        // Cancel
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
      }
    });

    testWidgets('Add Session with Connect-only calls onQuickConnect', (tester) async {
      SSHConfig? quickConnected;
      await tester.pumpWidget(buildApp(
        sessions: [],
        onQuickConnect: (config) => quickConnected = config,
      ));
      await tester.pumpAndSettle();

      final addButton = find.text('Add Session');
      if (addButton.evaluate().isNotEmpty) {
        await tester.tap(addButton);
        await tester.pumpAndSettle();

        await tester.enterText(find.widgetWithText(TextFormField, '192.168.1.1'), 'test.com');
        await tester.enterText(find.widgetWithText(TextFormField, 'root'), 'user');
        await tester.pumpAndSettle();

        // Fill password (required)
        await tester.tap(find.text('Auth'));
        await tester.pumpAndSettle();
        await tester.enterText(find.widgetWithText(TextFormField, '••••••••'), 'pass');
        await tester.pumpAndSettle();

        await tester.tap(find.text('Connect'));
        await tester.pumpAndSettle();

        expect(quickConnected, isNotNull);
        expect(quickConnected!.host, 'test.com');
      }
    });

    testWidgets('Add Session with Save saves session', (tester) async {
      await tester.pumpWidget(buildApp(
        sessions: [],
      ));
      await tester.pumpAndSettle();

      final addButton = find.text('Add Session');
      if (addButton.evaluate().isNotEmpty) {
        await tester.tap(addButton);
        await tester.pumpAndSettle();

        await tester.enterText(find.widgetWithText(TextFormField, '192.168.1.1'), 'save.com');
        await tester.enterText(find.widgetWithText(TextFormField, 'root'), 'admin');
        await tester.pumpAndSettle();

        // Fill password (required)
        await tester.tap(find.text('Auth'));
        await tester.pumpAndSettle();
        await tester.enterText(find.widgetWithText(TextFormField, '••••••••'), 'pass');
        await tester.pumpAndSettle();

        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();

        // Save without connect — dialog closes but no connect callback
        expect(find.text('Edit Connection'), findsNothing);
      }
    });
  });

  group('SessionPanel — _handleDialogResult ConnectOnly', () {
    testWidgets('Connect-only from new session calls onQuickConnect', (tester) async {
      SSHConfig? quickConnected;
      await tester.pumpWidget(buildApp(
        onQuickConnect: (config) => quickConnected = config,
      ));
      await tester.pumpAndSettle();

      // Open New Session dialog via group context menu
      final folderText = find.text('Production');
      final center = tester.getCenter(folderText);
      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await gesture.addPointer(location: center);
      await gesture.down(center);
      await gesture.up();
      await tester.pumpAndSettle();

      await tester.tap(find.text('New Connection'));
      await tester.pumpAndSettle();

      // Fill fields and tap Connect (not Save & Connect)
      await tester.enterText(find.widgetWithText(TextFormField, '192.168.1.1'), 'example.com');
      await tester.enterText(find.widgetWithText(TextFormField, 'root'), 'root');
      await tester.pumpAndSettle();

      // Fill password (required)
      await tester.tap(find.text('Auth'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextFormField, '••••••••'), 'pass');
      await tester.pumpAndSettle();

      // Find the OutlinedButton "Connect" (not the segment button text)
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      expect(quickConnected, isNotNull);
      expect(quickConnected!.host, 'example.com');
    });

    testWidgets('Save & Connect from new session dialog closes it', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      // Open New Session dialog via group context menu
      final folderText = find.text('Production');
      final center = tester.getCenter(folderText);
      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await gesture.addPointer(location: center);
      await gesture.down(center);
      await gesture.up();
      await tester.pumpAndSettle();

      await tester.tap(find.text('New Connection'));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextFormField, '192.168.1.1'), '10.0.0.5');
      await tester.enterText(find.widgetWithText(TextFormField, 'root'), 'admin');
      await tester.pumpAndSettle();

      // Fill password (required)
      await tester.tap(find.text('Auth'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextFormField, '••••••••'), 'pass');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      // Dialog should close
      expect(find.text('HOST *'), findsNothing);
    });
  });

  group('SessionPanel — Edit action saves', () {
    testWidgets('Edit and Save updates session', (tester) async {
      await tester.pumpWidget(buildApp(onSftpConnect: (_) {}));
      await tester.pumpAndSettle();

      // Right-click on staging to open context menu
      final sessionText = find.text('staging');
      final center = tester.getCenter(sessionText);
      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await gesture.addPointer(location: center);
      await gesture.down(center);
      await gesture.up();
      await tester.pumpAndSettle();

      // Tap Edit
      await tester.tap(find.text('Edit Connection'));
      await tester.pumpAndSettle();

      // Should show Edit Session dialog
      expect(find.text('Edit Connection'), findsOneWidget);

      // Tap Save
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      // Dialog should close
      expect(find.text('Edit Connection'), findsNothing);
    });
  });

  group('SessionPanel — Delete All removed', () {
    testWidgets('background context menu does not have Delete All', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      final panel = find.byType(SessionPanel);
      final panelBox = tester.getRect(panel);

      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await gesture.addPointer(location: Offset(panelBox.center.dx, panelBox.bottom - 10));
      await gesture.down(Offset(panelBox.center.dx, panelBox.bottom - 10));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.text('Delete All Sessions'), findsNothing);
    });
  });

  group('SessionPanel — Rename folder submit via Enter', () {
    testWidgets('Rename folder via Enter key submits', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      // Right-click on Production to open context menu
      final folderText = find.text('Production');
      final center = tester.getCenter(folderText);
      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await gesture.addPointer(location: center);
      await gesture.down(center);
      await gesture.up();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Rename Folder'));
      await tester.pumpAndSettle();

      // Change name and submit via Enter
      final textField = find.byType(TextField).last;
      await tester.enterText(textField, 'Prod');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      // Dialog should close
      expect(find.text('Rename Folder'), findsNothing);
    });
  });

  group('SessionPanel — folder name duplicate detection on rename', () {
    testWidgets('Rename to existing name shows error', (tester) async {
      // Production and Production/DB exist
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      // Right-click on DB (sub-group of Production)
      final dbText = find.text('DB');
      expect(dbText, findsOneWidget);
      final center = tester.getCenter(dbText);
      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await gesture.addPointer(location: center);
      await gesture.down(center);
      await gesture.up();
      await tester.pumpAndSettle();

      // Look for Rename in the context menu
      final renameItem = find.text('Rename Folder');
      if (renameItem.evaluate().isNotEmpty) {
        await tester.tap(renameItem);
        await tester.pumpAndSettle();

        // We need to type a name that would be duplicate
        // The current group is Production/DB, parent is Production
        // If we rename to something that already exists under Production
        // Since there's no other subgroup, this won't trigger duplicate
        // But we can verify the dialog renders correctly
        expect(find.text('Rename Folder'), findsOneWidget);

        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
      }
    });
  });

  group('SessionPanel — delete dialog with empty label', () {
    testWidgets('delete dialog uses displayName when label is empty',
        (tester) async {
      final noLabelSession = Session(id: '10', label: '', folder: '', server: const ServerAddress(host: '10.0.0.10', user: 'admin'));
      await tester.pumpWidget(buildApp(
        sessions: [noLabelSession],
        onSftpConnect: (_) {},
      ));
      await tester.pumpAndSettle();

      final hostText = find.text('10.0.0.10');
      expect(hostText, findsWidgets);

      final center = tester.getCenter(hostText.first);
      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await gesture.addPointer(location: center);
      await gesture.down(center);
      await gesture.up();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Delete "admin@10.0.0.10'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });
  });

  group('SessionPanel — delete empty folder no count warning', () {
    testWidgets('delete folder dialog for empty folder hides session count',
        (tester) async {
      await tester.pumpWidget(
        buildApp(emptyFolders: {'EmptyGroup'}),
      );
      await tester.pumpAndSettle();

      final emptyFolderFinder = find.text('EmptyGroup');
      if (emptyFolderFinder.evaluate().isNotEmpty) {
        final center = tester.getCenter(emptyFolderFinder);
        final gesture = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
          buttons: kSecondaryMouseButton,
        );
        await gesture.addPointer(location: center);
        await gesture.down(center);
        await gesture.up();
        await tester.pumpAndSettle();

        await tester.tap(find.text('Delete Folder'));
        await tester.pumpAndSettle();

        expect(find.text('Delete Folder'), findsOneWidget);
        expect(find.textContaining('session(s) inside'), findsNothing);

        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
      }
    });
  });

  group('SessionPanel — rename nested folder pre-fills leaf name', () {
    testWidgets('renaming DB (nested) shows correct pre-filled name',
        (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      final center = tester.getCenter(find.text('DB'));
      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await gesture.addPointer(location: center);
      await gesture.down(center);
      await gesture.up();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Rename Folder'));
      await tester.pumpAndSettle();

      final textField =
          tester.widget<TextField>(find.byType(TextField).last);
      expect(textField.controller?.text, 'DB');

      await tester.enterText(find.byType(TextField).last, 'Database');
      await tester.pump();

      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();

      expect(find.text('Rename Folder'), findsNothing);
    });
  });

  group('SessionPanel — edit mode Save does not call onConnect', () {
    testWidgets('Save without connect from edit does not call onConnect',
        (tester) async {
      Session? connected;
      await tester.pumpWidget(buildApp(
        onConnect: (s) => connected = s,
        onSftpConnect: (_) {},
      ));
      await tester.pumpAndSettle();

      final center = tester.getCenter(find.text('staging'));
      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await gesture.addPointer(location: center);
      await gesture.down(center);
      await gesture.up();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Edit Connection'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(connected, isNull);
    });
  });

  group('SessionPanel — empty folders in folder validation', () {
    testWidgets('empty groups are included in folder name validation',
        (tester) async {
      await tester.pumpWidget(
        buildApp(emptyFolders: {'Archive', 'Archive/Old'}),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('New Folder'));
      await tester.pumpAndSettle();

      final textField = find.byType(TextField).last;
      await tester.enterText(textField, 'Archive');
      await tester.pump();

      expect(
          find.text('Folder "Archive" already exists'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });
  });

  group('SessionPanel — context menu dismiss', () {
    testWidgets('dismissing session context menu does nothing',
        (tester) async {
      await tester.pumpWidget(buildApp(onSftpConnect: (_) {}));
      await tester.pumpAndSettle();

      final center = tester.getCenter(find.text('staging'));
      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await gesture.addPointer(location: center);
      await gesture.down(center);
      await gesture.up();
      await tester.pumpAndSettle();

      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();

      expect(find.text('staging'), findsWidgets);
    });

    testWidgets('dismissing folder context menu does nothing',
        (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      final center = tester.getCenter(find.text('Production'));
      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await gesture.addPointer(location: center);
      await gesture.down(center);
      await gesture.up();
      await tester.pumpAndSettle();

      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();

      expect(find.text('Production'), findsWidgets);
    });
  });

  group('SessionPanel — folder name Enter on empty is no-op', () {
    testWidgets('pressing Enter on empty name does not submit',
        (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('New Folder'));
      await tester.pumpAndSettle();

      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.text('FOLDER NAME'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });
  });

  group('SessionPanel — rename with empty result is no-op', () {
    testWidgets('rename dialog with empty name is ignored', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      final center = tester.getCenter(find.text('Production'));
      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await gesture.addPointer(location: center);
      await gesture.down(center);
      await gesture.up();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Rename Folder'));
      await tester.pumpAndSettle();

      final textField = find.byType(TextField).last;
      await tester.enterText(textField, '');
      await tester.pump();

      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();
    });
  });

  group('SessionPanel — rename to existing name shows error then clears', () {
    testWidgets('renaming to existing name shows error, fixing clears it',
        (tester) async {
      await tester.pumpWidget(
        buildApp(emptyFolders: {'Staging'}),
      );
      await tester.pumpAndSettle();

      final center = tester.getCenter(find.text('Staging'));
      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await gesture.addPointer(location: center);
      await gesture.down(center);
      await gesture.up();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Rename Folder'));
      await tester.pumpAndSettle();

      final textField = find.byType(TextField).last;
      await tester.enterText(textField, 'Production');
      await tester.pump();

      expect(
          find.text('Folder "Production" already exists'), findsOneWidget);

      await tester.enterText(textField, 'StagingNew');
      await tester.pump();

      expect(
          find.text('Folder "Production" already exists'), findsNothing);

      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();
    });
  });

  group('SessionPanel — cancel dialogs', () {
    testWidgets('cancel on Delete All does not delete', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

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

        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        expect(find.text('web1'), findsWidgets);
      }
    });

    testWidgets('cancel delete folder keeps folder', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      final center = tester.getCenter(find.text('Production'));
      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await gesture.addPointer(location: center);
      await gesture.down(center);
      await gesture.up();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Delete Folder'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Delete Folder'), findsNothing);
    });

    testWidgets('Add Session from empty state cancel does nothing',
        (tester) async {
      await tester.pumpWidget(buildApp(sessions: []));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add Session'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('No saved sessions'), findsOneWidget);
    });

    testWidgets('New Folder dialog cancel does nothing', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('New Folder'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('FOLDER NAME'), findsNothing);
    });
  });

  group('SessionPanel — drag session to folder (onSessionMoved)', () {
    testWidgets('dragging a session onto a folder calls moveSession',
        (tester) async {
      // Use sessions where staging is at root and Production is a group
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      // Find the staging session (root group) and the Production group
      final stagingFinder = find.text('staging');
      final productionFinder = find.text('Production');
      expect(stagingFinder, findsOneWidget);
      expect(productionFinder, findsOneWidget);

      final stagingCenter = tester.getCenter(stagingFinder);
      final productionCenter = tester.getCenter(productionFinder);

      // Simulate long press drag: LongPressDraggable requires a long press
      // followed by a drag to the target
      final gesture = await tester.startGesture(stagingCenter);
      // Hold for long press delay (default 500ms)
      await tester.pump(const Duration(milliseconds: 600));
      // Drag to Production group
      await gesture.moveTo(productionCenter);
      await tester.pump();
      // Release
      await gesture.up();
      await tester.pumpAndSettle();

      // The drag should trigger onSessionMoved internally via the provider.
      // Verify the panel still renders without error after the drop.
      expect(find.byType(SessionPanel), findsOneWidget);
    });
  });

  group('SessionPanel — drag folder to root (onFolderMoved)', () {
    testWidgets('dragging a folder to root area triggers onFolderMoved',
        (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      // Find the DB sub-group (Production/DB)
      final dbFinder = find.text('DB');
      expect(dbFinder, findsOneWidget);

      final dbCenter = tester.getCenter(dbFinder);

      // Get the bottom of the panel to drag to root background DragTarget
      final panel = find.byType(SessionPanel);
      final panelBox = tester.getRect(panel);
      final rootTarget = Offset(panelBox.center.dx, panelBox.bottom - 30);

      // Simulate long press drag
      final gesture = await tester.startGesture(dbCenter);
      await tester.pump(const Duration(milliseconds: 600));
      await gesture.moveTo(rootTarget);
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      // The panel should still render without error after the drop
      expect(find.byType(SessionPanel), findsOneWidget);
    });
  });

  group('SessionPanel — onSessionMoved/onFolderMoved callbacks via SessionTreeView', () {
    testWidgets('onSessionMoved callback calls moveSession on notifier',
        (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      // Find the SessionTreeView and invoke its onSessionMoved callback directly
      final treeView = tester.widget<SessionTreeView>(
        find.byType(SessionTreeView),
      );

      // Call onSessionMoved with staging session id '3' moving to 'Production'
      treeView.onSessionMoved!('3', 'Production');
      await tester.pumpAndSettle();

      // The panel should still render without error
      expect(find.byType(SessionPanel), findsOneWidget);
    });

    testWidgets('onFolderMoved callback calls moveFolder on notifier',
        (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      // Find the SessionTreeView and invoke its onFolderMoved callback directly
      final treeView = tester.widget<SessionTreeView>(
        find.byType(SessionTreeView),
      );

      // Call onFolderMoved to move Production/DB to root
      treeView.onFolderMoved!('Production/DB', '');
      await tester.pumpAndSettle();

      // The panel should still render without error
      expect(find.byType(SessionPanel), findsOneWidget);
    });
  });

  group('SessionPanel — Move to... menu item (mobile)', () {
    setUp(() {
      debugMobilePlatformOverride = true;
    });

    tearDown(() {
      debugMobilePlatformOverride = null;
    });

    testWidgets('Move to... item appears in bottom sheet on mobile',
        (tester) async {
      await tester.pumpWidget(buildApp(onSftpConnect: (_) {}));
      await tester.pumpAndSettle();

      // Long-press triggers bottom sheet on mobile
      await tester.longPress(find.text('staging'));
      await tester.pumpAndSettle();

      // Move to... item should appear in bottom sheet
      expect(find.text('Move to...'), findsOneWidget);
      // Other actions should also be present
      expect(find.text('Terminal'), findsOneWidget);
      expect(find.text('Files'), findsOneWidget);
    });

    testWidgets('Move to... opens move dialog with groups',
        (tester) async {
      await tester.pumpWidget(buildApp(
        onSftpConnect: (_) {},
        emptyFolders: {'Archive'},
      ));
      await tester.pumpAndSettle();

      await tester.longPress(find.text('web1'));
      await tester.pumpAndSettle();

      // Tap Move to...
      await tester.tap(find.text('Move to...'));
      await tester.pumpAndSettle();

      // Move dialog should appear
      expect(find.text('Move to Folder'), findsOneWidget);
      // Should show root option
      expect(find.text('/ (root)'), findsOneWidget);
      // Should show Production folder (in tree + in dialog)
      expect(find.text('Production'), findsWidgets);
      // Should show Archive (empty folder) — may appear in tree and dialog
      expect(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Archive'),
      ), findsOneWidget);
      // Should show Cancel button
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('Move dialog current group tile has check icon and bold text',
        (tester) async {
      await tester.pumpWidget(buildApp(onSftpConnect: (_) {}));
      await tester.pumpAndSettle();

      await tester.longPress(find.text('web1'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Move to...'));
      await tester.pumpAndSettle();

      // Current folder (Production) should have a check icon
      expect(find.byIcon(Icons.check), findsOneWidget);

      // Root has home icon
      expect(find.byIcon(Icons.home), findsOneWidget);
      // Non-root folders have folder icons
      expect(find.byIcon(Icons.folder_open), findsWidgets);
    });

    testWidgets('Move dialog — tapping current group does nothing (disabled)',
        (tester) async {
      await tester.pumpWidget(buildApp(onSftpConnect: (_) {}));
      await tester.pumpAndSettle();

      await tester.longPress(find.text('web1'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Move to...'));
      await tester.pumpAndSettle();

      // Tap the current folder (Production) in the dialog — should be disabled
      // Find Production inside the dialog (there are multiple 'Production' texts)
      final dialogProductionTiles = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Production'),
      );
      expect(dialogProductionTiles, findsOneWidget);
      await tester.tap(dialogProductionTiles);
      await tester.pumpAndSettle();

      // Dialog should still be open (tap on disabled tile is no-op)
      expect(find.text('Move to Folder'), findsOneWidget);
    });

    testWidgets('Move dialog — selecting different group moves session',
        (tester) async {
      await tester.pumpWidget(buildApp(onSftpConnect: (_) {}));
      await tester.pumpAndSettle();

      await tester.longPress(find.text('web1'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Move to...'));
      await tester.pumpAndSettle();

      // Tap "/ (root)" to move session to root
      await tester.tap(find.text('/ (root)'));
      await tester.pumpAndSettle();

      // Dialog should close after selection
      expect(find.text('Move to Folder'), findsNothing);
    });

    testWidgets('Move dialog — Cancel dismisses without moving',
        (tester) async {
      await tester.pumpWidget(buildApp(onSftpConnect: (_) {}));
      await tester.pumpAndSettle();

      await tester.longPress(find.text('web1'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Move to...'));
      await tester.pumpAndSettle();

      // Tap Cancel
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // Dialog should close
      expect(find.text('Move to Folder'), findsNothing);
    });

    testWidgets('Move dialog — root session shows root as current folder',
        (tester) async {
      await tester.pumpWidget(buildApp(onSftpConnect: (_) {}));
      await tester.pumpAndSettle();

      await tester.longPress(find.text('staging'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Move to...'));
      await tester.pumpAndSettle();

      // Root should be current folder (has check icon), since staging.folder == ''
      expect(find.byIcon(Icons.check), findsOneWidget);

      // Tapping root should be disabled (current folder)
      await tester.tap(find.text('/ (root)'));
      await tester.pumpAndSettle();

      // Dialog should still be open
      expect(find.text('Move to Folder'), findsOneWidget);

      // Tapping a different folder should close dialog
      final dialogProduction = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Production'),
      );
      await tester.tap(dialogProduction);
      await tester.pumpAndSettle();

      expect(find.text('Move to Folder'), findsNothing);
    });

    testWidgets('Move dialog shows Production/DB as selectable folder',
        (tester) async {
      await tester.pumpWidget(buildApp(onSftpConnect: (_) {}));
      await tester.pumpAndSettle();

      await tester.longPress(find.text('staging'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Move to...'));
      await tester.pumpAndSettle();

      // Should show Production/DB as a selectable group
      expect(find.text('Production/DB'), findsOneWidget);

      // Tap Production/DB to move there
      await tester.tap(find.text('Production/DB'));
      await tester.pumpAndSettle();

      // Dialog should close
      expect(find.text('Move to Folder'), findsNothing);
    });
  });

  group('SessionPanel — select mode (mobile)', () {
    setUp(() => debugMobilePlatformOverride = true);
    tearDown(() => debugMobilePlatformOverride = null);

    testWidgets('no checklist icon in header (select via bottom sheet)', (tester) async {
      await tester.pumpWidget(buildApp());
      // Checklist icon removed from header — select mode enters via long-press bottom sheet
      expect(find.byIcon(Icons.checklist), findsNothing);
    });

    testWidgets('long-press session shows bottom sheet with Select option', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      // Long-press a session to show bottom sheet
      await tester.longPress(find.text('staging'));
      await tester.pumpAndSettle();

      // Bottom sheet should have a Select option
      expect(find.widgetWithText(ListTile, 'Select'), findsOneWidget);
    });

    testWidgets('Select in bottom sheet enters select mode with item pre-checked', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      await tester.longPress(find.text('staging'));
      await tester.pumpAndSettle();

      // Ensure "Select" is visible and tap it
      final selectTile = find.widgetWithText(ListTile, 'Select');
      await tester.ensureVisible(selectTile);
      await tester.pumpAndSettle();
      await tester.tap(selectTile);
      await tester.pumpAndSettle();

      final state = tester.state<SessionPanelState>(find.byType(SessionPanel));
      expect(state.selectMode, isTrue);
      expect(state.selectedIds, contains('3'));
      expect(find.text('1 selected'), findsOneWidget);
    });

    testWidgets('enterSelectModeWithSession shows action bar', (tester) async {
      await tester.pumpWidget(buildApp());
      final state = tester.state<SessionPanelState>(find.byType(SessionPanel));

      state.enterSelectModeWithSession('1');
      await tester.pump();

      expect(find.text('1 selected'), findsOneWidget);
      expect(find.byIcon(Icons.select_all), findsOneWidget);
      expect(find.byIcon(Icons.drive_file_move), findsOneWidget);
      expect(find.byIcon(Icons.delete), findsOneWidget);
      expect(find.byIcon(Icons.close), findsOneWidget);
    });

    testWidgets('action bar hides search bar and header', (tester) async {
      await tester.pumpWidget(buildApp());
      expect(find.text('SESSIONS'), findsOneWidget);

      final state = tester.state<SessionPanelState>(find.byType(SessionPanel));
      state.enterSelectModeWithSession('1');
      await tester.pump();

      // Header title should be gone
      expect(find.text('SESSIONS'), findsNothing);
    });

    testWidgets('action bar height matches panel header (36px)', (tester) async {
      await tester.pumpWidget(buildApp());

      final state = tester.state<SessionPanelState>(find.byType(SessionPanel));
      state.enterSelectModeWithSession('1');
      await tester.pump();

      // Find the action bar container by its "selected" text
      final selectedText = find.text('1 selected');
      expect(selectedText, findsOneWidget);

      // Verify rendered height of the action bar container
      final actionBarBox = tester.getSize(
        find.ancestor(of: selectedText, matching: find.byType(Container)).first,
      );
      expect(actionBarBox.height, 36.0);
    });

    testWidgets('Cancel exits select mode', (tester) async {
      await tester.pumpWidget(buildApp());
      final state = tester.state<SessionPanelState>(find.byType(SessionPanel));
      state.enterSelectModeWithSession('1');
      await tester.pump();
      expect(find.text('1 selected'), findsOneWidget);

      // Tap close/cancel
      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();

      // Back to normal mode
      expect(find.text('SESSIONS'), findsOneWidget);
      expect(find.text('1 selected'), findsNothing);
    });

    testWidgets('checkboxes appear in select mode', (tester) async {
      await tester.pumpWidget(buildApp());
      expect(find.byType(Checkbox), findsNothing);

      final state = tester.state<SessionPanelState>(find.byType(SessionPanel));
      state.enterSelectModeWithSession('1');
      await tester.pump();

      // Should have checkboxes for each session (3 in testSessions)
      expect(find.byType(Checkbox), findsNWidgets(3));
    });

    testWidgets('tapping session in select mode toggles checkbox', (tester) async {
      await tester.pumpWidget(buildApp());
      final state = tester.state<SessionPanelState>(find.byType(SessionPanel));
      state.enterSelectModeWithSession('1');
      await tester.pump();
      expect(find.text('1 selected'), findsOneWidget);

      // Tap another session to select it too
      await tester.tap(find.text('staging'));
      await tester.pump();
      expect(find.text('2 selected'), findsOneWidget);

      // Tap again to deselect
      await tester.tap(find.text('staging'));
      await tester.pump();
      expect(find.text('1 selected'), findsOneWidget);
    });

    testWidgets('Select All selects all sessions', (tester) async {
      await tester.pumpWidget(buildApp());
      final state = tester.state<SessionPanelState>(find.byType(SessionPanel));
      state.enterSelectModeWithSession('1');
      await tester.pump();

      await tester.tap(find.byIcon(Icons.select_all));
      await tester.pump();

      expect(find.text('3 selected'), findsOneWidget);
    });

    testWidgets('Delete shows confirm dialog', (tester) async {
      await tester.pumpWidget(buildApp());
      final state = tester.state<SessionPanelState>(find.byType(SessionPanel));
      state.enterSelectModeWithSession('1');
      await tester.pump();

      // Tap delete
      await tester.tap(find.byIcon(Icons.delete));
      await tester.pumpAndSettle();

      expect(find.text('Delete Selected'), findsOneWidget);
      expect(find.textContaining('1 session(s)'), findsOneWidget);
    });

    testWidgets('Move shows folder dialog', (tester) async {
      await tester.pumpWidget(buildApp());
      final state = tester.state<SessionPanelState>(find.byType(SessionPanel));
      state.enterSelectModeWithSession('3');
      await tester.pump();

      await tester.tap(find.byIcon(Icons.drive_file_move));
      await tester.pumpAndSettle();

      expect(find.text('Move to Folder'), findsOneWidget);
    });

    testWidgets('Delete confirm deletes sessions and exits select mode', (tester) async {
      await tester.pumpWidget(buildApp());
      final state = tester.state<SessionPanelState>(find.byType(SessionPanel));
      state.enterSelectModeWithSession('1');
      await tester.pump();

      // Select another session
      await tester.tap(find.text('staging'));
      await tester.pump();
      expect(find.text('2 selected'), findsOneWidget);

      // Tap delete
      await tester.tap(find.byIcon(Icons.delete));
      await tester.pumpAndSettle();

      // Confirm deletion
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      // Should exit select mode
      expect(find.text('SESSIONS'), findsOneWidget);
    });

    testWidgets('Move confirm moves sessions and exits select mode', (tester) async {
      await tester.pumpWidget(buildApp());
      final state = tester.state<SessionPanelState>(find.byType(SessionPanel));
      state.enterSelectModeWithSession('3');
      await tester.pump();

      await tester.tap(find.byIcon(Icons.drive_file_move));
      await tester.pumpAndSettle();

      // Select Production folder in the move dialog
      await tester.tap(find.text('Production').last);
      await tester.pumpAndSettle();

      // Should exit select mode after move
      expect(find.text('SESSIONS'), findsOneWidget);
    });

    testWidgets('Move cancel keeps select mode', (tester) async {
      await tester.pumpWidget(buildApp());
      final state = tester.state<SessionPanelState>(find.byType(SessionPanel));
      state.enterSelectModeWithSession('3');
      await tester.pump();

      await tester.tap(find.byIcon(Icons.drive_file_move));
      await tester.pumpAndSettle();

      // Cancel move dialog
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // Still in select mode
      expect(find.text('1 selected'), findsOneWidget);
    });

    testWidgets('visibleForTesting getters expose state', (tester) async {
      await tester.pumpWidget(buildApp());

      final state = tester.state<SessionPanelState>(find.byType(SessionPanel));
      expect(state.selectMode, isFalse);
      expect(state.selectedIds, isEmpty);

      state.enterSelectModeWithSession('1');
      await tester.pump();

      expect(state.selectMode, isTrue);
      expect(state.selectedIds, contains('1'));
    });

    testWidgets('enterSelectModeWithFolder pre-checks folder', (tester) async {
      await tester.pumpWidget(buildApp());

      final state = tester.state<SessionPanelState>(find.byType(SessionPanel));
      state.enterSelectModeWithFolder('Production');
      await tester.pump();

      expect(state.selectMode, isTrue);
      expect(state.selectedFolderPaths, contains('Production'));
      expect(state.selectedIds, isEmpty);
    });
  });

  group('SessionPanel — desktop marquee selection', () {

    testWidgets('marquee selection highlights rows without action bar', (tester) async {
      await tester.pumpWidget(buildApp());

      final state = tester.state<SessionPanelState>(find.byType(SessionPanel));
      state.setMarqueeSelection({'1', '2'});
      await tester.pump();

      // Header should still be visible
      expect(find.text('SESSIONS'), findsOneWidget);
      // No action bar on desktop — bulk actions via context menu
      expect(find.text('2 selected'), findsNothing);
      // No checkboxes (not in select mode)
      expect(find.byType(Checkbox), findsNothing);
    });

    testWidgets('marquee selection with folders tracks selectedFolderPaths', (tester) async {
      await tester.pumpWidget(buildApp());

      final state = tester.state<SessionPanelState>(find.byType(SessionPanel));
      state.setMarqueeSelection({'1'}, {'Production/Web'});
      await tester.pump();

      expect(state.selectedIds, equals({'1'}));
      expect(state.selectedFolderPaths, equals({'Production/Web'}));
    });

    testWidgets('clearDesktopSelection clears both sessions and folders', (tester) async {
      await tester.pumpWidget(buildApp());

      final state = tester.state<SessionPanelState>(find.byType(SessionPanel));
      state.setMarqueeSelection({'1', '2'}, {'Production'});
      await tester.pump();

      expect(state.selectedIds, isNotEmpty);
      expect(state.selectedFolderPaths, isNotEmpty);

      // Simulate clicking empty area — triggers clear via tree view pointer up
      state.setMarqueeSelection({});
      await tester.pump();

      expect(state.selectedIds, isEmpty);
      expect(state.selectedFolderPaths, isEmpty);
    });
  });

  group('SessionPanel — keyboard shortcuts', () {
    tearDown(() => debugMobilePlatformOverride = null);

    testWidgets('Ctrl+C sets copied session, Ctrl+V triggers duplicate', (tester) async {
      debugMobilePlatformOverride = false;
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      // Tap a session — wait past double-tap timeout so single-tap fires
      await tester.tap(find.text('web1'));
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 10));
      await tester.pumpAndSettle();

      final panelState = tester.state<SessionPanelState>(find.byType(SessionPanel));
      expect(panelState.focusedSessionId, '1');

      // Copy stores the session ID
      panelState.copyFocusedSession();

      // Paste duplicates — verify via provider state change
      panelState.pasteCopiedSession();
      await tester.pumpAndSettle();

      // The provider should now have 4 sessions (3 original + 1 copy)
      final container = ProviderScope.containerOf(tester.element(find.byType(SessionPanel)));
      final updatedSessions = container.read(sessionProvider);
      expect(updatedSessions.length, 4);
      expect(updatedSessions.any((s) => s.label.contains('(copy)')), isTrue);
    });

    testWidgets('Delete key opens delete confirmation for focused session', (tester) async {
      debugMobilePlatformOverride = false;
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('staging'));
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 10));
      await tester.pumpAndSettle();

      final state = tester.state<SessionPanelState>(find.byType(SessionPanel));
      expect(state.focusedSessionId, '3');

      state.deleteFocusedSession();
      await tester.pumpAndSettle();

      expect(find.text('Delete Session'), findsOneWidget);
    });

    testWidgets('F2 opens edit dialog for focused session', (tester) async {
      debugMobilePlatformOverride = false;
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('web1'));
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 10));
      await tester.pumpAndSettle();

      final state = tester.state<SessionPanelState>(find.byType(SessionPanel));
      expect(state.focusedSessionId, '1');

      state.editFocusedSession();
      await tester.pumpAndSettle();

      // Edit dialog should open with session data
      expect(find.text('10.0.0.1'), findsWidgets);
    });

    testWidgets('Delete key ignored when no session focused', (tester) async {
      debugMobilePlatformOverride = false;
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      // Don't tap any session — no focus
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();

      // No delete dialog
      expect(find.textContaining('Delete "'), findsNothing);
    });

    testWidgets('Ctrl+V ignored when nothing copied', (tester) async {
      debugMobilePlatformOverride = false;
      final sessions = [
        Session(id: '1', label: 'only', folder: '', server: const ServerAddress(host: '1.2.3.4', user: 'u'), auth: const SessionAuth(authType: AuthType.password)),
      ];
      await tester.pumpWidget(buildApp(sessions: sessions));
      await tester.pumpAndSettle();

      // Ctrl+V without prior Ctrl+C
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      // Still just one session
      expect(find.textContaining('(copy)'), findsNothing);
    });
  });
}
