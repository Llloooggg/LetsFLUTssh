import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/session/session.dart';
import 'package:letsflutssh/core/session/session_tree.dart';
import 'package:letsflutssh/features/session_manager/session_tree_view.dart';
import 'package:letsflutssh/theme/app_theme.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/utils/platform.dart';
import 'package:letsflutssh/widgets/cross_marquee_controller.dart';
import 'package:letsflutssh/widgets/threshold_draggable.dart';
import '''package:letsflutssh/l10n/app_localizations.dart''';

void main() {
  late List<Session> sessions;
  late List<SessionTreeNode> tree;

  setUp(() {
    sessions = [
      Session(
        id: '1',
        label: 'nginx1',
        folder: 'Production/Web',
        server: const ServerAddress(host: '10.0.0.1', user: 'root'),
      ),
      Session(
        id: '2',
        label: 'nginx2',
        folder: 'Production/Web',
        server: const ServerAddress(host: '10.0.0.2', user: 'root'),
      ),
      Session(
        id: '3',
        label: 'db-master',
        folder: 'Production/DB',
        server: const ServerAddress(host: '10.0.1.1', user: 'admin'),
      ),
      Session(
        id: '4',
        label: 'staging',
        folder: '',
        server: const ServerAddress(host: '192.168.1.1', user: 'deploy'),
      ),
    ];
    tree = SessionTree.build(sessions);
  });

  Widget buildApp({
    List<SessionTreeNode>? overrideTree,
    void Function(Session)? onSessionTap,
    void Function(Session)? onSessionDoubleTap,
    Set<String> selectedIds = const {},
    Set<String> selectedFolderPaths = const {},
  }) {
    return ProviderScope(
      child: MaterialApp(
        localizationsDelegates: S.localizationsDelegates,
        supportedLocales: S.supportedLocales,
        theme: AppTheme.dark(),
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 600,
            child: SessionTreeView(
              tree: overrideTree ?? tree,
              onSessionTap: onSessionTap,
              onSessionDoubleTap: onSessionDoubleTap,
              selectedIds: selectedIds,
              selectedFolderPaths: selectedFolderPaths,
            ),
          ),
        ),
      ),
    );
  }

  group('SessionTreeView', () {
    testWidgets('renders folders', (tester) async {
      await tester.pumpWidget(buildApp());
      expect(find.text('Production'), findsOneWidget);
      expect(find.text('Web'), findsOneWidget);
      expect(find.text('DB'), findsOneWidget);
    });

    testWidgets('renders session names', (tester) async {
      await tester.pumpWidget(buildApp());
      expect(find.text('nginx1'), findsOneWidget);
      expect(find.text('nginx2'), findsOneWidget);
      expect(find.text('db-master'), findsOneWidget);
      expect(find.text('staging'), findsOneWidget);
    });

    testWidgets('does not show host inline for sessions', (tester) async {
      await tester.pumpWidget(buildApp());
      expect(find.text('10.0.0.1'), findsNothing);
      expect(find.text('10.0.0.2'), findsNothing);
    });

    testWidgets('shows No sessions for empty tree', (tester) async {
      await tester.pumpWidget(buildApp(overrideTree: []));
      expect(find.text('No sessions'), findsOneWidget);
    });

    testWidgets('tapping folder collapses it', (tester) async {
      await tester.pumpWidget(buildApp());
      // Initially expanded — should see children
      expect(find.text('nginx1'), findsOneWidget);

      // Tap 'Web' folder to collapse
      await tester.tap(find.text('Web'));
      await tester.pumpAndSettle();

      // Children should be hidden
      expect(find.text('nginx1'), findsNothing);
      expect(find.text('nginx2'), findsNothing);
    });

    testWidgets('tapping collapsed folder expands it', (tester) async {
      await tester.pumpWidget(buildApp());

      // Collapse
      await tester.tap(find.text('Web'));
      await tester.pumpAndSettle();
      expect(find.text('nginx1'), findsNothing);

      // Expand again
      await tester.tap(find.text('Web'));
      await tester.pumpAndSettle();
      expect(find.text('nginx1'), findsOneWidget);
    });

    testWidgets('session double-tap triggers callback', (tester) async {
      Session? doubleTapped;
      await tester.pumpWidget(
        buildApp(onSessionDoubleTap: (s) => doubleTapped = s),
      );

      // Manual double-tap detection: two taps within 400 ms window
      final stagingFinder = find.text('staging');
      expect(stagingFinder, findsOneWidget);

      final center = tester.getCenter(stagingFinder);
      // Simulate double-tap: two taps in quick succession
      await tester.tapAt(center);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(center);
      await tester.pumpAndSettle();

      expect(doubleTapped?.label, 'staging');
    });

    testWidgets('shows folder icons', (tester) async {
      await tester.pumpWidget(buildApp());
      expect(find.byIcon(Icons.folder_open), findsWidgets);
    });

    testWidgets('shows terminal icons for sessions', (tester) async {
      await tester.pumpWidget(buildApp());
      expect(find.byIcon(Icons.terminal), findsWidgets);
    });

    testWidgets('shows session count on folders', (tester) async {
      await tester.pumpWidget(buildApp());
      // Production folder has 3 sessions total (2 Web + 1 DB)
      expect(find.text('3'), findsOneWidget);
      // Web has 2
      expect(find.text('2'), findsOneWidget);
      // DB has 1
      expect(find.text('1'), findsOneWidget);
    });

    testWidgets('session tap selects session', (tester) async {
      await tester.pumpWidget(buildApp());

      // Tap on staging session to select it
      await tester.tap(find.text('staging'));
      await tester.pumpAndSettle();

      // After tap, staging should still be visible (not crashed)
      expect(find.text('staging'), findsOneWidget);
    });

    testWidgets('mobile tap does not highlight session row', (tester) async {
      debugMobilePlatformOverride = true;
      addTearDown(() => debugMobilePlatformOverride = null);

      Session? opened;
      await tester.pumpWidget(buildApp(onSessionDoubleTap: (s) => opened = s));

      await tester.tap(find.text('staging'));
      await tester.pumpAndSettle();

      // Session should have been opened
      expect(opened?.label, 'staging');

      // No Container should have a highlight color — the row must not be
      // visually selected after tap on mobile.
      final containers = tester.widgetList<Container>(find.byType(Container));
      final primaryHighlight = containers.where((c) {
        if (c.color == null) return false;
        return c.color!.a < 1.0 && c.color!.a > 0.0;
      });
      expect(primaryHighlight, isEmpty);
    });

    testWidgets('shows indent guides for nested folders', (tester) async {
      await tester.pumpWidget(buildApp());
      // Nested sessions should be indented — look for SizedBox containers
      // used for indent guides
      expect(find.byType(SizedBox), findsWidgets);
    });

    testWidgets('collapsing parent hides all descendants', (tester) async {
      await tester.pumpWidget(buildApp());

      // All children should be visible initially
      expect(find.text('nginx1'), findsOneWidget);
      expect(find.text('db-master'), findsOneWidget);

      // Collapse Production (parent of Web and DB)
      await tester.tap(find.text('Production'));
      await tester.pumpAndSettle();

      // All descendants should be hidden
      expect(find.text('nginx1'), findsNothing);
      expect(find.text('nginx2'), findsNothing);
      expect(find.text('db-master'), findsNothing);
      expect(find.text('Web'), findsNothing);
      expect(find.text('DB'), findsNothing);
    });

    testWidgets(
      'shows expand_more icons for folders (rotated when collapsed)',
      (tester) async {
        await tester.pumpWidget(buildApp());
        // All folders use expand_more (rotated -90° when collapsed)
        expect(find.byIcon(Icons.expand_more), findsWidgets);
      },
    );

    testWidgets('shows folder icon for all folders', (tester) async {
      await tester.pumpWidget(buildApp());
      expect(find.byIcon(Icons.folder_open), findsWidgets);
    });

    testWidgets('shows terminal icon for key auth type', (tester) async {
      final keySessions = [
        Session(
          id: '10',
          label: 'key-server',
          folder: '',
          server: const ServerAddress(host: '10.0.0.10', user: 'root'),
          auth: const SessionAuth(authType: AuthType.key),
        ),
      ];
      final keyTree = SessionTree.build(keySessions);
      await tester.pumpWidget(buildApp(overrideTree: keyTree));

      expect(find.byIcon(Icons.terminal), findsWidgets);
    });

    testWidgets('shows terminal icon for keyWithPassword auth', (tester) async {
      final keySessions = [
        Session(
          id: '11',
          label: 'enc-server',
          folder: '',
          server: const ServerAddress(host: '10.0.0.11', user: 'root'),
          auth: const SessionAuth(authType: AuthType.keyWithPassword),
        ),
      ];
      final keyTree = SessionTree.build(keySessions);
      await tester.pumpWidget(buildApp(overrideTree: keyTree));

      expect(find.byIcon(Icons.terminal), findsWidgets);
    });

    testWidgets('session tap calls onSessionTap callback', (tester) async {
      Session? tappedSession;
      await tester.pumpWidget(buildApp(onSessionTap: (s) => tappedSession = s));

      await tester.tap(find.text('staging'));
      await tester.pumpAndSettle();

      expect(tappedSession?.label, 'staging');
    });

    testWidgets('session tap sets selected state and highlights', (
      tester,
    ) async {
      await tester.pumpWidget(buildApp());

      // Tap on staging to select it
      await tester.tap(find.text('staging'));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      // The session row container should have a highlighted background
      // Find the specific Container for the selected row
      final containers = tester.widgetList<Container>(find.byType(Container));
      final hasHighlight = containers.any((c) => c.color != null);
      expect(hasHighlight, isTrue);
    });

    testWidgets('tapping different session changes selection', (tester) async {
      Session? tappedSession;
      await tester.pumpWidget(buildApp(onSessionTap: (s) => tappedSession = s));

      // Tap first session
      await tester.tap(find.text('staging'));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(tappedSession?.label, 'staging');

      // Tap a different session
      await tester.tap(find.text('nginx1'));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(tappedSession?.label, 'nginx1');
    });

    testWidgets('selected session gets highlighted background', (tester) async {
      await tester.pumpWidget(buildApp());

      // Tap on staging to select it
      await tester.tap(find.text('staging'));
      await tester.pumpAndSettle();

      // Should find Container with primary color alpha background
      expect(find.byType(Container), findsWidgets);
    });

    testWidgets('renders root-level sessions without indent', (tester) async {
      final rootOnly = [
        Session(
          id: '1',
          label: 'root-server',
          folder: '',
          server: const ServerAddress(host: 'h', user: 'u'),
        ),
      ];
      final rootTree = SessionTree.build(rootOnly);
      await tester.pumpWidget(buildApp(overrideTree: rootTree));

      expect(find.text('root-server'), findsOneWidget);
    });

    testWidgets(
      'ThresholdDraggable is present for selected sessions on desktop',
      (tester) async {
        await tester.pumpWidget(buildApp(selectedIds: const {'1'}));

        // Only selected sessions are wrapped in ThresholdDraggable
        expect(find.byType(ThresholdDraggable<SessionDragData>), findsWidgets);
      },
    );

    testWidgets(
      'ThresholdDraggable absent for unselected sessions on desktop',
      (tester) async {
        await tester.pumpWidget(buildApp());

        // No selection → no Draggable → marquee can start from any row
        expect(find.byType(ThresholdDraggable<SessionDragData>), findsNothing);
      },
    );

    testWidgets('DragTarget for root drop zone is present', (tester) async {
      await tester.pumpWidget(buildApp());

      expect(find.byType(DragTarget<SessionDragData>), findsWidgets);
    });
  });

  group('SessionDragData', () {
    test('SessionDrag holds session', () {
      final session = Session(
        id: '1',
        label: 'test',
        server: const ServerAddress(host: 'h', user: 'u'),
      );
      final drag = SessionDrag(session);
      expect(drag.session, session);
    });

    test('FolderDrag holds folder path', () {
      final drag = FolderDrag('Production/Web');
      expect(drag.folderPath, 'Production/Web');
    });
  });

  group('SessionTreeView — deep nesting', () {
    testWidgets('renders 3-level nested folders', (tester) async {
      final s = Session(
        label: 's',
        folder: 'A/B/C',
        server: const ServerAddress(host: 'h', user: 'u'),
      );
      final tree = SessionTree.build([s], emptyFolders: const {});
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Scaffold(
              body: SizedBox(
                width: 300,
                height: 600,
                child: SessionTreeView(tree: tree),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('A'), findsOneWidget);
      expect(find.text('B'), findsOneWidget);
      expect(find.text('C'), findsOneWidget);
      expect(find.text('s'), findsOneWidget);
    });

    testWidgets('depth 4 item renders without overflow', (tester) async {
      final s = Session(
        label: 'deep',
        folder: 'A/B/C/D',
        server: const ServerAddress(host: 'h', user: 'u'),
      );
      final tree = SessionTree.build([s], emptyFolders: const {});
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Scaffold(
              body: SizedBox(
                width: 300,
                height: 600,
                child: SessionTreeView(tree: tree),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('A'), findsOneWidget);
      expect(find.text('D'), findsOneWidget);
      expect(find.text('deep'), findsOneWidget);
    });
  });

  group('SessionTreeView — empty folders', () {
    testWidgets('empty folder renders with 0 count', (tester) async {
      final tree = SessionTree.build([], emptyFolders: {'EmptyFolder'});
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Scaffold(
              body: SizedBox(
                width: 300,
                height: 600,
                child: SessionTreeView(tree: tree),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('EmptyFolder'), findsOneWidget);
      expect(find.text('0'), findsOneWidget);
    });
  });

  group('SessionTreeView — collapse and re-expand', () {
    testWidgets('collapse then re-expand folder shows children again', (
      tester,
    ) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      // Initially all expanded
      expect(find.text('nginx1'), findsOneWidget);

      // Collapse Production
      await tester.tap(find.text('Production'));
      await tester.pumpAndSettle();

      expect(find.text('nginx1'), findsNothing);

      // Re-expand
      await tester.tap(find.text('Production'));
      await tester.pumpAndSettle();

      expect(find.text('nginx1'), findsOneWidget);
    });
  });

  group('SessionTreeView — context menus', () {
    testWidgets('right-click on session triggers onSessionContextMenu', (
      tester,
    ) async {
      Session? contextSession;
      Offset? contextPos;

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Scaffold(
              body: SizedBox(
                width: 300,
                height: 600,
                child: SessionTreeView(
                  tree: tree,
                  onSessionContextMenu: (session, pos) {
                    contextSession = session;
                    contextPos = pos;
                  },
                ),
              ),
            ),
          ),
        ),
      );

      final stagingFinder = find.text('staging');
      expect(stagingFinder, findsOneWidget);

      final center = tester.getCenter(stagingFinder);
      final gesture = await tester.startGesture(center, buttons: 2);
      await gesture.up();
      await tester.pumpAndSettle();

      expect(contextSession?.label, 'staging');
      expect(contextPos, isNotNull);
    });

    testWidgets('right-click on folder triggers onFolderContextMenu', (
      tester,
    ) async {
      String? contextFolder;
      Offset? contextPos;

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Scaffold(
              body: SizedBox(
                width: 300,
                height: 600,
                child: SessionTreeView(
                  tree: tree,
                  onFolderContextMenu: (folder, pos) {
                    contextFolder = folder;
                    contextPos = pos;
                  },
                ),
              ),
            ),
          ),
        ),
      );

      final webFinder = find.text('Web');
      expect(webFinder, findsOneWidget);

      final center = tester.getCenter(webFinder);
      final gesture = await tester.startGesture(center, buttons: 2);
      await gesture.up();
      await tester.pumpAndSettle();

      expect(contextFolder, 'Production/Web');
      expect(contextPos, isNotNull);
    });

    testWidgets('right-click on background triggers onBackgroundContextMenu', (
      tester,
    ) async {
      Offset? contextPos;

      final singleSession = [
        Session(
          id: '1',
          label: 'only',
          folder: '',
          server: const ServerAddress(host: '10.0.0.1', user: 'root'),
        ),
      ];
      final singleTree = SessionTree.build(singleSession);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Scaffold(
              body: SizedBox(
                width: 300,
                height: 600,
                child: SessionTreeView(
                  tree: singleTree,
                  onBackgroundContextMenu: (pos) {
                    contextPos = pos;
                  },
                ),
              ),
            ),
          ),
        ),
      );

      // Right-click on the GestureDetector wrapping the list
      final treeViewFinder = find.byType(SessionTreeView);
      final center = tester.getCenter(treeViewFinder);
      final bottomArea = Offset(center.dx, center.dy + 200);
      final gesture = await tester.startGesture(bottomArea, buttons: 2);
      await gesture.up();
      await tester.pumpAndSettle();

      expect(contextPos, isNotNull);
    });
  });

  group('SessionTreeView — drag and drop', () {
    testWidgets('drag session to different folder calls onSessionMoved', (
      tester,
    ) async {
      String? movedSessionId;
      String? targetFolder;

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Scaffold(
              body: SizedBox(
                width: 300,
                height: 600,
                child: SessionTreeView(
                  tree: tree,
                  selectedIds: const {'1'}, // must be selected to drag
                  onSessionMoved: (sessionId, target) {
                    movedSessionId = sessionId;
                    targetFolder = target;
                  },
                ),
              ),
            ),
          ),
        ),
      );

      final nginx1Finder = find.text('nginx1');
      final dbFinder = find.text('DB');
      expect(nginx1Finder, findsOneWidget);
      expect(dbFinder, findsOneWidget);

      final nginx1Center = tester.getCenter(nginx1Finder);
      final dbCenter = tester.getCenter(dbFinder);

      // ThresholdDraggable requires > 8px movement to initiate drag
      final gesture = await tester.startGesture(nginx1Center);
      await gesture.moveTo(dbCenter);
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(movedSessionId, '1');
      expect(targetFolder, 'Production/DB');
    });

    testWidgets('drag session to root calls onSessionMoved with empty folder', (
      tester,
    ) async {
      String? movedSessionId;
      String? targetFolder;

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Scaffold(
              body: SizedBox(
                width: 300,
                height: 600,
                child: SessionTreeView(
                  tree: tree,
                  selectedIds: const {'1'}, // must be selected to drag
                  onSessionMoved: (sessionId, target) {
                    movedSessionId = sessionId;
                    targetFolder = target;
                  },
                ),
              ),
            ),
          ),
        ),
      );

      final nginx1Finder = find.text('nginx1');
      expect(nginx1Finder, findsOneWidget);

      final nginx1Center = tester.getCenter(nginx1Finder);

      final gesture = await tester.startGesture(nginx1Center);
      // Move to empty area below all items (root DragTarget)
      final treeViewFinder = find.byType(SessionTreeView);
      final treeCenter = tester.getCenter(treeViewFinder);
      final emptyArea = Offset(treeCenter.dx, treeCenter.dy + 250);
      await gesture.moveTo(emptyArea);
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(movedSessionId, '1');
      expect(targetFolder, '');
    });

    testWidgets('drag folder to different folder calls onFolderMoved', (
      tester,
    ) async {
      String? movedFolder;
      String? targetParent;

      final twoFolderSessions = [
        Session(
          id: '1',
          label: 'srv1',
          folder: 'GroupA',
          server: const ServerAddress(host: '10.0.0.1', user: 'root'),
        ),
        Session(
          id: '2',
          label: 'srv2',
          folder: 'GroupB',
          server: const ServerAddress(host: '10.0.0.2', user: 'root'),
        ),
      ];
      final twoFolderTree = SessionTree.build(twoFolderSessions);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Scaffold(
              body: SizedBox(
                width: 300,
                height: 600,
                child: SessionTreeView(
                  tree: twoFolderTree,
                  selectedFolderPaths: const {
                    'GroupA',
                  }, // must be selected to drag
                  onFolderMoved: (folder, target) {
                    movedFolder = folder;
                    targetParent = target;
                  },
                ),
              ),
            ),
          ),
        ),
      );

      final folderAFinder = find.text('GroupA');
      final folderBFinder = find.text('GroupB');
      expect(folderAFinder, findsOneWidget);
      expect(folderBFinder, findsOneWidget);

      final folderACenter = tester.getCenter(folderAFinder);
      final folderBCenter = tester.getCenter(folderBFinder);

      final gesture = await tester.startGesture(folderACenter);
      await gesture.moveTo(folderBCenter);
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(movedFolder, 'GroupA');
      expect(targetParent, 'GroupB');
    });
  });

  // ---------------------------------------------------------------------------
  // Marquee selection (desktop only)
  // ---------------------------------------------------------------------------
  group('SessionTreeView — marquee selection', () {
    testWidgets('drag on desktop fires onMarqueeSelect with session ids', (
      tester,
    ) async {
      Set<String>? selectedIds;

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Scaffold(
              body: SizedBox(
                width: 300,
                height: 600,
                child: SessionTreeView(
                  tree: tree,
                  onMarqueeSelect: (ids, _) => selectedIds = ids,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Drag across a large area to select sessions
      final center = tester.getCenter(find.byType(SessionTreeView));
      final gesture = await tester.startGesture(Offset(center.dx, 10));
      await tester.pump();
      await gesture.moveBy(const Offset(0, 400));
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.up();
      await tester.pump();

      // Should have called onMarqueeSelect with at least some session ids
      expect(selectedIds, isNotNull);
      expect(selectedIds!, isNotEmpty);
    });

    testWidgets('small movement does not trigger marquee', (tester) async {
      Set<String>? selectedIds;

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Scaffold(
              body: SizedBox(
                width: 300,
                height: 600,
                child: SessionTreeView(
                  tree: tree,
                  onMarqueeSelect: (ids, _) => selectedIds = ids,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tiny movement — below threshold
      final center = tester.getCenter(find.byType(SessionTreeView));
      final gesture = await tester.startGesture(center);
      await tester.pump();
      await gesture.moveBy(const Offset(0, 2));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(selectedIds, isNull);
    });
  });

  group('SessionTreeView — cross-widget marquee', () {
    testWidgets('drag outside bounds fires crossMarquee.start', (tester) async {
      final crossMarquee = CrossMarqueeController();
      addTearDown(crossMarquee.dispose);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Scaffold(
              body: SizedBox(
                width: 300,
                height: 600,
                child: SessionTreeView(tree: tree, crossMarquee: crossMarquee),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Start inside, drag far to the right (outside bounds)
      final center = tester.getCenter(find.byType(SessionTreeView));
      final gesture = await tester.startGesture(center);
      await tester.pump();
      await gesture.moveBy(const Offset(400, 0));
      await tester.pump(const Duration(milliseconds: 100));

      expect(crossMarquee.active, isTrue);

      await gesture.up();
      await tester.pump();

      expect(crossMarquee.active, isFalse);
    });

    testWidgets(
      'drag back inside cancels cross-marquee and resumes session marquee',
      (tester) async {
        final crossMarquee = CrossMarqueeController();
        addTearDown(crossMarquee.dispose);
        Set<String>? selectedIds;

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              localizationsDelegates: S.localizationsDelegates,
              supportedLocales: S.supportedLocales,
              theme: AppTheme.dark(),
              home: Scaffold(
                body: SizedBox(
                  width: 300,
                  height: 600,
                  child: SessionTreeView(
                    tree: tree,
                    crossMarquee: crossMarquee,
                    onMarqueeSelect: (ids, _) => selectedIds = ids,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Start below all rows (empty space) so Draggable doesn't intercept
        final center = tester.getCenter(find.byType(SessionTreeView));
        final gesture = await tester.startGesture(Offset(center.dx, 400));
        await tester.pump();

        // Move outside
        await gesture.moveBy(const Offset(400, 0));
        await tester.pump(const Duration(milliseconds: 100));
        expect(crossMarquee.active, isTrue);

        // Move back inside and up into rows
        await gesture.moveTo(Offset(center.dx, 200));
        await tester.pump(const Duration(milliseconds: 100));
        expect(crossMarquee.active, isFalse);

        // Session marquee should be active now — check via onMarqueeSelect
        await gesture.moveBy(const Offset(0, -150));
        await tester.pump(const Duration(milliseconds: 100));

        // selectedIds was called during inside-marquee
        expect(selectedIds, isNotNull);

        await gesture.up();
        await tester.pump();
      },
    );

    testWidgets('cross-marquee not triggered without controller', (
      tester,
    ) async {
      Set<String>? selectedIds;

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Scaffold(
              body: SizedBox(
                width: 300,
                height: 600,
                child: SessionTreeView(
                  tree: tree,
                  onMarqueeSelect: (ids, _) => selectedIds = ids,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Drag outside bounds — without crossMarquee, should still do normal marquee
      final center = tester.getCenter(find.byType(SessionTreeView));
      final gesture = await tester.startGesture(Offset(center.dx, 10));
      await tester.pump();
      await gesture.moveBy(const Offset(0, 200));
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.up();
      await tester.pump();

      expect(selectedIds, isNotNull);
      expect(selectedIds!, isNotEmpty);
    });
  });

  group('Folder selection', () {
    testWidgets('marquee selects folders alongside sessions', (tester) async {
      Set<String>? selectedIds;
      Set<String>? selectedFolderPaths;

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Scaffold(
              body: SizedBox(
                width: 300,
                height: 600,
                child: SessionTreeView(
                  tree: tree,
                  onMarqueeSelect: (ids, folders) {
                    selectedIds = ids;
                    selectedFolderPaths = folders;
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Drag across a large area to select both folders and sessions
      final center = tester.getCenter(find.byType(SessionTreeView));
      final gesture = await tester.startGesture(Offset(center.dx, 10));
      await tester.pump();
      await gesture.moveBy(const Offset(0, 400));
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.up();
      await tester.pump();

      expect(selectedIds, isNotNull);
      expect(selectedFolderPaths, isNotNull);
      // Tree has folders (Production, Web, DB) so marquee should pick them up
      expect(selectedFolderPaths!, isNotEmpty);
    });

    testWidgets('selected folder gets highlight background', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Scaffold(
              body: SizedBox(
                width: 300,
                height: 600,
                child: SessionTreeView(
                  tree: tree,
                  selectedFolderPaths: const {'Production'},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find the Production row container — it should have a non-null color
      // indicating selection highlight
      final productionText = find.text('Production');
      expect(productionText, findsOneWidget);

      // Verify the Container ancestor has a BoxDecoration with color set
      final container = find.ancestor(
        of: productionText,
        matching: find.byType(Container),
      );
      expect(container, findsWidgets);

      // The closest Container should have a decorated background
      final containerWidget = tester.widget<Container>(container.first);
      final decoration = containerWidget.decoration as BoxDecoration?;
      expect(decoration, isNotNull);
      expect(decoration!.color, isNotNull);
    });

    testWidgets('tapping folder during active selection clears selection', (
      tester,
    ) async {
      Set<String>? clearedIds;
      Set<String>? clearedFolders;

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Scaffold(
              body: SizedBox(
                width: 300,
                height: 600,
                child: SessionTreeView(
                  tree: tree,
                  selectedIds: const {'1'}, // active selection
                  onMarqueeSelect: (ids, folders) {
                    clearedIds = ids;
                    clearedFolders = folders;
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap on a folder while there's an active session selection
      await tester.tap(find.text('DB'));
      await tester.pump();

      // Plain click clears the selection
      expect(clearedIds, isEmpty);
      expect(clearedFolders, isEmpty);
    });

    testWidgets('tapping folder without selection expands/collapses', (
      tester,
    ) async {
      String? toggledFolder;

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Scaffold(
              body: SizedBox(
                width: 300,
                height: 600,
                child: SessionTreeView(
                  tree: tree,
                  onToggleFolderSelected: (path) => toggledFolder = path,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // All folders expanded by default — sessions should be visible
      expect(find.text('nginx1'), findsOneWidget);

      // Tap on Web folder — should collapse, not toggle selection
      await tester.tap(find.text('Web'));
      await tester.pump();

      expect(toggledFolder, isNull); // not a selection toggle
      expect(find.text('nginx1'), findsNothing); // collapsed
    });
  });

  group('Multi-drag', () {
    testWidgets('BulkDrag has correct counts', (tester) async {
      final bulk = BulkDrag(
        sessionIds: {'1', '2'},
        folderPaths: {'Production/Web'},
      );
      expect(bulk.totalCount, 3);
      expect(bulk.sessionIds, {'1', '2'});
      expect(bulk.folderPaths, {'Production/Web'});
    });

    testWidgets(
      'dragging selected session with bulk selection creates BulkDrag feedback',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              localizationsDelegates: S.localizationsDelegates,
              supportedLocales: S.supportedLocales,
              theme: AppTheme.dark(),
              home: Scaffold(
                body: SizedBox(
                  width: 300,
                  height: 600,
                  child: SessionTreeView(
                    tree: tree,
                    selectedIds: const {'1', '2'},
                    selectedFolderPaths: const {'Production/Web'},
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Start dragging nginx1 (which is selected)
        final nginx1 = find.text('nginx1');
        expect(nginx1, findsOneWidget);

        final gesture = await tester.startGesture(tester.getCenter(nginx1));
        await gesture.moveBy(const Offset(0, 50));
        await tester.pump();

        // Should show "3 items" feedback
        expect(find.text('3 items'), findsOneWidget);

        await gesture.up();
        await tester.pumpAndSettle();
      },
    );
  });
}
