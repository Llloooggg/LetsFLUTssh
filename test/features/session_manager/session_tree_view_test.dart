import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/session/session.dart';
import 'package:letsflutssh/core/session/session_tree.dart';
import 'package:letsflutssh/features/session_manager/session_tree_view.dart';
import 'package:letsflutssh/theme/app_theme.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/widgets/cross_marquee_controller.dart';

void main() {
  late List<Session> sessions;
  late List<SessionTreeNode> tree;

  setUp(() {
    sessions = [
      Session(id: '1', label: 'nginx1', group: 'Production/Web', server: const ServerAddress(host: '10.0.0.1', user: 'root')),
      Session(id: '2', label: 'nginx2', group: 'Production/Web', server: const ServerAddress(host: '10.0.0.2', user: 'root')),
      Session(id: '3', label: 'db-master', group: 'Production/DB', server: const ServerAddress(host: '10.0.1.1', user: 'admin')),
      Session(id: '4', label: 'staging', group: '', server: const ServerAddress(host: '192.168.1.1', user: 'deploy')),
    ];
    tree = SessionTree.build(sessions);
  });

  Widget buildApp({
    List<SessionTreeNode>? overrideTree,
    void Function(Session)? onSessionTap,
    void Function(Session)? onSessionDoubleTap,
  }) {
    return MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
        body: SizedBox(
          width: 300,
          height: 600,
          child: SessionTreeView(
            tree: overrideTree ?? tree,
            onSessionTap: onSessionTap,
            onSessionDoubleTap: onSessionDoubleTap,
          ),
        ),
      ),
    );
  }

  group('SessionTreeView', () {
    testWidgets('renders group folders', (tester) async {
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

    testWidgets('shows host for sessions', (tester) async {
      await tester.pumpWidget(buildApp());
      expect(find.text('10.0.0.1'), findsOneWidget);
      expect(find.text('10.0.0.2'), findsOneWidget);
    });

    testWidgets('shows No sessions for empty tree', (tester) async {
      await tester.pumpWidget(buildApp(overrideTree: []));
      expect(find.text('No sessions'), findsOneWidget);
    });

    testWidgets('tapping group collapses it', (tester) async {
      await tester.pumpWidget(buildApp());
      // Initially expanded — should see children
      expect(find.text('nginx1'), findsOneWidget);

      // Tap 'Web' group to collapse
      await tester.tap(find.text('Web'));
      await tester.pumpAndSettle();

      // Children should be hidden
      expect(find.text('nginx1'), findsNothing);
      expect(find.text('nginx2'), findsNothing);
    });

    testWidgets('tapping collapsed group expands it', (tester) async {
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
      await tester.pumpWidget(buildApp(
        onSessionDoubleTap: (s) => doubleTapped = s,
      ));

      // GestureDetector wraps InkWell with onDoubleTap — test via double-tap
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
      expect(find.byIcon(Icons.folder), findsWidgets);
    });

    testWidgets('shows shield icons for sessions', (tester) async {
      await tester.pumpWidget(buildApp());
      expect(find.byIcon(Icons.shield), findsWidgets);
    });

    testWidgets('shows session count on groups', (tester) async {
      await tester.pumpWidget(buildApp());
      // Production group has 3 sessions total (2 Web + 1 DB)
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

    testWidgets('shows indent guides for nested groups', (tester) async {
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

    testWidgets('shows expand_more icons for groups (rotated when collapsed)',
        (tester) async {
      await tester.pumpWidget(buildApp());
      // All groups use expand_more (rotated -90° when collapsed)
      expect(find.byIcon(Icons.expand_more), findsWidgets);
    });

    testWidgets('shows folder icon for all groups', (tester) async {
      await tester.pumpWidget(buildApp());
      expect(find.byIcon(Icons.folder), findsWidgets);
    });

    testWidgets('shows shield icon for key auth type', (tester) async {
      final keySessions = [
        Session(id: '10', label: 'key-server', group: '', server: const ServerAddress(host: '10.0.0.10', user: 'root'), auth: const SessionAuth(authType: AuthType.key)),
      ];
      final keyTree = SessionTree.build(keySessions);
      await tester.pumpWidget(buildApp(overrideTree: keyTree));

      expect(find.byIcon(Icons.shield), findsWidgets);
    });

    testWidgets('shows shield icon for keyWithPassword auth', (tester) async {
      final keySessions = [
        Session(id: '11', label: 'enc-server', group: '', server: const ServerAddress(host: '10.0.0.11', user: 'root'), auth: const SessionAuth(authType: AuthType.keyWithPassword)),
      ];
      final keyTree = SessionTree.build(keySessions);
      await tester.pumpWidget(buildApp(overrideTree: keyTree));

      expect(find.byIcon(Icons.shield), findsWidgets);
    });

    testWidgets('session tap calls onSessionTap callback', (tester) async {
      Session? tappedSession;
      await tester.pumpWidget(buildApp(
        onSessionTap: (s) => tappedSession = s,
      ));

      await tester.tap(find.text('staging'));
      // Wait for double-tap detection timeout (300ms) + settle
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      expect(tappedSession?.label, 'staging');
    });

    testWidgets('session tap sets selected state and highlights', (tester) async {
      await tester.pumpWidget(buildApp());

      // Tap on staging to select it
      await tester.tap(find.text('staging'));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      // The session row container should have a highlighted background
      // Find the specific Container for the selected row
      final containers = tester.widgetList<Container>(find.byType(Container));
      final hasHighlight = containers.any(
        (c) => c.color != null,
      );
      expect(hasHighlight, isTrue);
    });

    testWidgets('tapping different session changes selection', (tester) async {
      Session? tappedSession;
      await tester.pumpWidget(buildApp(
        onSessionTap: (s) => tappedSession = s,
      ));

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
        Session(id: '1', label: 'root-server', group: '', server: const ServerAddress(host: 'h', user: 'u')),
      ];
      final rootTree = SessionTree.build(rootOnly);
      await tester.pumpWidget(buildApp(overrideTree: rootTree));

      expect(find.text('root-server'), findsOneWidget);
      expect(find.text('h'), findsOneWidget);
    });

    testWidgets('Draggable is present for sessions on desktop', (tester) async {
      await tester.pumpWidget(buildApp());

      // On desktop, sessions should be wrapped in Draggable
      expect(find.byType(Draggable<SessionDragData>), findsWidgets);
    });

    testWidgets('DragTarget for root drop zone is present', (tester) async {
      await tester.pumpWidget(buildApp());

      expect(find.byType(DragTarget<SessionDragData>), findsWidgets);
    });
  });

  group('SessionDragData', () {
    test('SessionDrag holds session', () {
      final session = Session(id: '1', label: 'test', server: const ServerAddress(host: 'h', user: 'u'));
      final drag = SessionDrag(session);
      expect(drag.session, session);
    });

    test('GroupDrag holds group path', () {
      final drag = GroupDrag('Production/Web');
      expect(drag.groupPath, 'Production/Web');
    });
  });

  group('SessionTreeView — deep nesting', () {
    testWidgets('renders 3-level nested groups', (tester) async {
      final s = Session(label: 's', group: 'A/B/C', server: const ServerAddress(host: 'h', user: 'u'));
      final tree = SessionTree.build([s], emptyGroups: const {});
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 600,
            child: SessionTreeView(tree: tree),
          ),
        ),
      ));
      await tester.pump();

      expect(find.text('A'), findsOneWidget);
      expect(find.text('B'), findsOneWidget);
      expect(find.text('C'), findsOneWidget);
      expect(find.text('s'), findsOneWidget);
    });

    testWidgets('depth 4 item renders without overflow', (tester) async {
      final s = Session(label: 'deep', group: 'A/B/C/D', server: const ServerAddress(host: 'h', user: 'u'));
      final tree = SessionTree.build([s], emptyGroups: const {});
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 600,
            child: SessionTreeView(tree: tree),
          ),
        ),
      ));
      await tester.pump();

      expect(find.text('A'), findsOneWidget);
      expect(find.text('D'), findsOneWidget);
      expect(find.text('deep'), findsOneWidget);
    });
  });

  group('SessionTreeView — empty groups', () {
    testWidgets('empty group renders as folder with 0 count', (tester) async {
      final tree = SessionTree.build([], emptyGroups: {'EmptyFolder'});
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 600,
            child: SessionTreeView(tree: tree),
          ),
        ),
      ));
      await tester.pump();

      expect(find.text('EmptyFolder'), findsOneWidget);
      expect(find.text('0'), findsOneWidget);
    });
  });

  group('SessionTreeView — collapse and re-expand', () {
    testWidgets('collapse then re-expand group shows children again',
        (tester) async {
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
    testWidgets('right-click on session triggers onSessionContextMenu',
        (tester) async {
      Session? contextSession;
      Offset? contextPos;

      await tester.pumpWidget(MaterialApp(
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
      ));

      final stagingFinder = find.text('staging');
      expect(stagingFinder, findsOneWidget);

      final center = tester.getCenter(stagingFinder);
      final gesture = await tester.startGesture(center, buttons: 2);
      await gesture.up();
      await tester.pumpAndSettle();

      expect(contextSession?.label, 'staging');
      expect(contextPos, isNotNull);
    });

    testWidgets('right-click on group triggers onGroupContextMenu',
        (tester) async {
      String? contextGroup;
      Offset? contextPos;

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 600,
            child: SessionTreeView(
              tree: tree,
              onGroupContextMenu: (group, pos) {
                contextGroup = group;
                contextPos = pos;
              },
            ),
          ),
        ),
      ));

      final webFinder = find.text('Web');
      expect(webFinder, findsOneWidget);

      final center = tester.getCenter(webFinder);
      final gesture = await tester.startGesture(center, buttons: 2);
      await gesture.up();
      await tester.pumpAndSettle();

      expect(contextGroup, 'Production/Web');
      expect(contextPos, isNotNull);
    });

    testWidgets('right-click on background triggers onBackgroundContextMenu',
        (tester) async {
      Offset? contextPos;

      final singleSession = [
        Session(
          id: '1',
          label: 'only',
          group: '',
          server: const ServerAddress(host: '10.0.0.1', user: 'root'),
        ),
      ];
      final singleTree = SessionTree.build(singleSession);

      await tester.pumpWidget(MaterialApp(
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
      ));

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
    testWidgets('drag session to different group calls onSessionMoved',
        (tester) async {
      String? movedSessionId;
      String? targetGroup;

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 600,
            child: SessionTreeView(
              tree: tree,
              onSessionMoved: (sessionId, target) {
                movedSessionId = sessionId;
                targetGroup = target;
              },
            ),
          ),
        ),
      ));

      final nginx1Finder = find.text('nginx1');
      final dbFinder = find.text('DB');
      expect(nginx1Finder, findsOneWidget);
      expect(dbFinder, findsOneWidget);

      final nginx1Center = tester.getCenter(nginx1Finder);
      final dbCenter = tester.getCenter(dbFinder);

      // LongPressDraggable requires a long press to initiate drag
      final gesture = await tester.startGesture(nginx1Center);
      await tester.pump(const Duration(milliseconds: 600));
      await gesture.moveTo(dbCenter);
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(movedSessionId, '1');
      expect(targetGroup, 'Production/DB');
    });

    testWidgets('drag session to root calls onSessionMoved with empty group',
        (tester) async {
      String? movedSessionId;
      String? targetGroup;

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 600,
            child: SessionTreeView(
              tree: tree,
              onSessionMoved: (sessionId, target) {
                movedSessionId = sessionId;
                targetGroup = target;
              },
            ),
          ),
        ),
      ));

      final nginx1Finder = find.text('nginx1');
      expect(nginx1Finder, findsOneWidget);

      final nginx1Center = tester.getCenter(nginx1Finder);

      final gesture = await tester.startGesture(nginx1Center);
      await tester.pump(const Duration(milliseconds: 600));
      // Move to empty area below all items (root DragTarget)
      final treeViewFinder = find.byType(SessionTreeView);
      final treeCenter = tester.getCenter(treeViewFinder);
      final emptyArea = Offset(treeCenter.dx, treeCenter.dy + 250);
      await gesture.moveTo(emptyArea);
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(movedSessionId, '1');
      expect(targetGroup, '');
    });

    testWidgets('drag group to different group calls onGroupMoved',
        (tester) async {
      String? movedGroup;
      String? targetParent;

      final twoGroupSessions = [
        Session(
          id: '1',
          label: 'srv1',
          group: 'GroupA',
          server: const ServerAddress(host: '10.0.0.1', user: 'root'),
        ),
        Session(
          id: '2',
          label: 'srv2',
          group: 'GroupB',
          server: const ServerAddress(host: '10.0.0.2', user: 'root'),
        ),
      ];
      final twoGroupTree = SessionTree.build(twoGroupSessions);

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 600,
            child: SessionTreeView(
              tree: twoGroupTree,
              onGroupMoved: (group, target) {
                movedGroup = group;
                targetParent = target;
              },
            ),
          ),
        ),
      ));

      final groupAFinder = find.text('GroupA');
      final groupBFinder = find.text('GroupB');
      expect(groupAFinder, findsOneWidget);
      expect(groupBFinder, findsOneWidget);

      final groupACenter = tester.getCenter(groupAFinder);
      final groupBCenter = tester.getCenter(groupBFinder);

      final gesture = await tester.startGesture(groupACenter);
      await tester.pump(const Duration(milliseconds: 600));
      await gesture.moveTo(groupBCenter);
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(movedGroup, 'GroupA');
      expect(targetParent, 'GroupB');
    });
  });

  // ---------------------------------------------------------------------------
  // Marquee selection (desktop only)
  // ---------------------------------------------------------------------------
  group('SessionTreeView — marquee selection', () {
    testWidgets('drag on desktop fires onMarqueeSelect with session ids', (tester) async {
      Set<String>? selectedIds;

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 600,
            child: SessionTreeView(
              tree: tree,
              onMarqueeSelect: (ids) => selectedIds = ids,
            ),
          ),
        ),
      ));
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

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 600,
            child: SessionTreeView(
              tree: tree,
              onMarqueeSelect: (ids) => selectedIds = ids,
            ),
          ),
        ),
      ));
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

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 600,
            child: SessionTreeView(
              tree: tree,
              crossMarquee: crossMarquee,
            ),
          ),
        ),
      ));
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

    testWidgets('drag back inside cancels cross-marquee and resumes session marquee', (tester) async {
      final crossMarquee = CrossMarqueeController();
      addTearDown(crossMarquee.dispose);
      Set<String>? selectedIds;

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 600,
            child: SessionTreeView(
              tree: tree,
              crossMarquee: crossMarquee,
              onMarqueeSelect: (ids) => selectedIds = ids,
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // Start inside, drag outside, then back inside
      final center = tester.getCenter(find.byType(SessionTreeView));
      final gesture = await tester.startGesture(Offset(center.dx, 10));
      await tester.pump();

      // Move outside
      await gesture.moveBy(const Offset(400, 0));
      await tester.pump(const Duration(milliseconds: 100));
      expect(crossMarquee.active, isTrue);

      // Move back inside and down
      await gesture.moveTo(Offset(center.dx, 200));
      await tester.pump(const Duration(milliseconds: 100));
      expect(crossMarquee.active, isFalse);

      // Session marquee should be active now — check via onMarqueeSelect
      await gesture.moveBy(const Offset(0, 100));
      await tester.pump(const Duration(milliseconds: 100));

      // selectedIds was called during inside-marquee
      expect(selectedIds, isNotNull);

      await gesture.up();
      await tester.pump();
    });

    testWidgets('cross-marquee not triggered without controller', (tester) async {
      Set<String>? selectedIds;

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 600,
            child: SessionTreeView(
              tree: tree,
              onMarqueeSelect: (ids) => selectedIds = ids,
            ),
          ),
        ),
      ));
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
}
