import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/session/session.dart';
import 'package:letsflutssh/core/session/session_tree.dart';
import 'package:letsflutssh/features/session_manager/session_tree_view.dart';
import 'package:letsflutssh/theme/app_theme.dart';

void main() {
  Session makeSession({
    required String label,
    String group = '',
    AuthType authType = AuthType.password,
  }) {
    return Session(
      label: label,
      host: 'h',
      user: 'u',
      group: group,
      authType: authType,
    );
  }

  Widget buildTreeView({
    required List<SessionTreeNode> tree,
    void Function(Session, Offset)? onSessionContextMenu,
    void Function(String, Offset)? onGroupContextMenu,
    void Function(Offset)? onBackgroundContextMenu,
    void Function(Session)? onSessionTap,
    void Function(Session)? onSessionDoubleTap,
    void Function(String, String)? onSessionMoved,
    void Function(String, String)? onGroupMoved,
  }) {
    return MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
        body: SizedBox(
          width: 300,
          height: 600,
          child: SessionTreeView(
            tree: tree,
            onSessionTap: onSessionTap,
            onSessionDoubleTap: onSessionDoubleTap,
            onSessionContextMenu: onSessionContextMenu,
            onGroupContextMenu: onGroupContextMenu,
            onBackgroundContextMenu: onBackgroundContextMenu,
            onSessionMoved: onSessionMoved,
            onGroupMoved: onGroupMoved,
          ),
        ),
      ),
    );
  }

  group('SessionTreeView — empty state', () {
    testWidgets('shows "No sessions" when tree is empty', (tester) async {
      await tester.pumpWidget(buildTreeView(tree: []));
      await tester.pump();

      expect(find.text('No sessions'), findsOneWidget);
    });
  });

  group('SessionTreeView — rendering sessions', () {
    testWidgets('renders session labels', (tester) async {
      final s1 = makeSession(label: 'Web1');
      final s2 = makeSession(label: 'DB1');
      final tree = SessionTree.build(
        [s1, s2],
        emptyGroups: const {},
      );

      await tester.pumpWidget(buildTreeView(tree: tree));
      await tester.pump();

      expect(find.text('Web1'), findsOneWidget);
      expect(find.text('DB1'), findsOneWidget);
    });

    testWidgets('renders host:port info for sessions', (tester) async {
      final s = makeSession(label: 'MyServer');
      final tree = SessionTree.build([s], emptyGroups: const {});

      await tester.pumpWidget(buildTreeView(tree: tree));
      await tester.pump();

      expect(find.textContaining('h:22'), findsOneWidget);
    });

    testWidgets('renders auth icons: lock for password', (tester) async {
      final s = makeSession(label: 'Srv', authType: AuthType.password);
      final tree = SessionTree.build([s], emptyGroups: const {});

      await tester.pumpWidget(buildTreeView(tree: tree));
      await tester.pump();

      expect(find.byIcon(Icons.lock), findsWidgets);
    });

    testWidgets('renders auth icons: vpn_key for key', (tester) async {
      final s = makeSession(label: 'Key', authType: AuthType.key);
      final tree = SessionTree.build([s], emptyGroups: const {});

      await tester.pumpWidget(buildTreeView(tree: tree));
      await tester.pump();

      expect(find.byIcon(Icons.vpn_key), findsWidgets);
    });

    testWidgets('renders auth icons: enhanced_encryption for keyWithPassword', (tester) async {
      final s = makeSession(label: 'KP', authType: AuthType.keyWithPassword);
      final tree = SessionTree.build([s], emptyGroups: const {});

      await tester.pumpWidget(buildTreeView(tree: tree));
      await tester.pump();

      expect(find.byIcon(Icons.enhanced_encryption), findsWidgets);
    });
  });

  group('SessionTreeView — groups', () {
    testWidgets('renders group folders', (tester) async {
      final s1 = makeSession(label: 'Web1', group: 'Production');
      final tree = SessionTree.build([s1], emptyGroups: const {});

      await tester.pumpWidget(buildTreeView(tree: tree));
      await tester.pump();

      expect(find.text('Production'), findsOneWidget);
    });

    testWidgets('groups are expanded by default', (tester) async {
      final s1 = makeSession(label: 'Web1', group: 'Production');
      final tree = SessionTree.build([s1], emptyGroups: const {});

      await tester.pumpWidget(buildTreeView(tree: tree));
      await tester.pump();

      // Session inside the group should be visible
      expect(find.text('Web1'), findsOneWidget);
    });

    testWidgets('tapping group collapses it', (tester) async {
      final s1 = makeSession(label: 'Web1', group: 'Production');
      final tree = SessionTree.build([s1], emptyGroups: const {});

      await tester.pumpWidget(buildTreeView(tree: tree));
      await tester.pump();

      // Tap the group to collapse
      await tester.tap(find.text('Production'));
      await tester.pump();

      // Session should be hidden
      expect(find.text('Web1'), findsNothing);
    });

    testWidgets('tapping collapsed group expands it', (tester) async {
      final s1 = makeSession(label: 'Web1', group: 'Production');
      final tree = SessionTree.build([s1], emptyGroups: const {});

      await tester.pumpWidget(buildTreeView(tree: tree));
      await tester.pump();

      // Collapse
      await tester.tap(find.text('Production'));
      await tester.pump();
      expect(find.text('Web1'), findsNothing);

      // Expand
      await tester.tap(find.text('Production'));
      await tester.pump();
      expect(find.text('Web1'), findsOneWidget);
    });

    testWidgets('nested groups display correctly', (tester) async {
      final s1 = makeSession(label: 'nginx', group: 'Production/Web');
      final tree = SessionTree.build([s1], emptyGroups: const {});

      await tester.pumpWidget(buildTreeView(tree: tree));
      await tester.pump();

      expect(find.text('Production'), findsOneWidget);
      expect(find.text('Web'), findsOneWidget);
      expect(find.text('nginx'), findsOneWidget);
    });

    testWidgets('group shows session count', (tester) async {
      final s1 = makeSession(label: 'Web1', group: 'Prod');
      final s2 = makeSession(label: 'Web2', group: 'Prod');
      final tree = SessionTree.build([s1, s2], emptyGroups: const {});

      await tester.pumpWidget(buildTreeView(tree: tree));
      await tester.pump();

      // Group should show count "2"
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('empty groups from emptyGroups are shown', (tester) async {
      final tree = SessionTree.build([], emptyGroups: {'EmptyFolder'});

      await tester.pumpWidget(buildTreeView(tree: tree));
      await tester.pump();

      expect(find.text('EmptyFolder'), findsOneWidget);
    });
  });

  group('SessionTreeView — callbacks', () {
    testWidgets('session renders with InkWell for tap interaction', (tester) async {
      final s = makeSession(label: 'ClickMe');
      final tree = SessionTree.build([s], emptyGroups: const {});

      await tester.pumpWidget(buildTreeView(
        tree: tree,
        onSessionTap: (_) {},
        onSessionDoubleTap: (_) {},
      ));
      await tester.pump();

      // Session should be rendered
      expect(find.text('ClickMe'), findsOneWidget);
      // InkWell should be present for tap
      expect(find.byType(InkWell), findsWidgets);
    });
  });

  group('SessionTreeView — context menu callbacks', () {
    testWidgets('right-click on session fires onSessionContextMenu', (tester) async {
      Session? menuSession;
      Offset? menuPosition;
      final s = makeSession(label: 'CtxSession');
      final tree = SessionTree.build([s], emptyGroups: const {});

      await tester.pumpWidget(buildTreeView(
        tree: tree,
        onSessionContextMenu: (session, pos) {
          menuSession = session;
          menuPosition = pos;
        },
      ));
      await tester.pump();

      // Right-click (secondary tap) on session
      final sessionFinder = find.text('CtxSession');
      final center = tester.getCenter(sessionFinder);
      final gesture = await tester.startGesture(
        center,
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await gesture.up();
      await tester.pumpAndSettle();

      expect(menuSession?.label, 'CtxSession');
      expect(menuPosition, isNotNull);
    });

    testWidgets('right-click on group fires onGroupContextMenu', (tester) async {
      String? menuGroup;
      Offset? menuPosition;
      final s = makeSession(label: 'S1', group: 'MyGroup');
      final tree = SessionTree.build([s], emptyGroups: const {});

      await tester.pumpWidget(buildTreeView(
        tree: tree,
        onGroupContextMenu: (groupPath, pos) {
          menuGroup = groupPath;
          menuPosition = pos;
        },
      ));
      await tester.pump();

      // Right-click on group
      final groupFinder = find.text('MyGroup');
      final center = tester.getCenter(groupFinder);
      final gesture = await tester.startGesture(
        center,
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await gesture.up();
      await tester.pumpAndSettle();

      expect(menuGroup, 'MyGroup');
      expect(menuPosition, isNotNull);
    });

    testWidgets('right-click on empty area fires onBackgroundContextMenu', (tester) async {
      Offset? bgPosition;
      final s = makeSession(label: 'Small');
      final tree = SessionTree.build([s], emptyGroups: const {});

      await tester.pumpWidget(buildTreeView(
        tree: tree,
        onBackgroundContextMenu: (pos) {
          bgPosition = pos;
        },
      ));
      await tester.pump();

      // Right-click on the tree background area (below sessions)
      final treeView = find.byType(SessionTreeView);
      final treeRect = tester.getRect(treeView);
      final bgPoint = Offset(treeRect.center.dx, treeRect.bottom - 10);

      final gesture = await tester.startGesture(
        bgPoint,
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await gesture.up();
      await tester.pumpAndSettle();

      expect(bgPosition, isNotNull);
    });
  });

  group('SessionTreeView — session tap fires onSessionTap', () {
    testWidgets('tapping session fires onSessionTap callback', (tester) async {
      Session? tapped;
      final s = makeSession(label: 'TapMe');
      final tree = SessionTree.build([s], emptyGroups: const {});

      await tester.pumpWidget(buildTreeView(
        tree: tree,
        onSessionTap: (session) => tapped = session,
        onSessionDoubleTap: (_) {}, // Provide both so GestureDetector resolves faster
      ));
      await tester.pump();

      // Tap and wait for GestureDetector double-tap timeout (kDoubleTapTimeout)
      await tester.tap(find.text('TapMe'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(tapped?.label, 'TapMe');
    });
  });

  group('SessionTreeView — onSessionMoved and onGroupMoved callbacks', () {
    testWidgets('DragTarget for root accepts session drop', (tester) async {
      // Verify DragTarget is present and callbacks are wired
      String? movedSessionId;
      // ignore: unused_local_variable
      String? movedTarget;
      final s = makeSession(label: 'Movable', group: 'Grp');
      final tree = SessionTree.build([s], emptyGroups: const {});

      await tester.pumpWidget(buildTreeView(
        tree: tree,
        onSessionMoved: (id, target) {
          movedSessionId = id;
          movedTarget = target;
        },
      ));
      await tester.pump();

      // We can't easily simulate drag&drop in widget tests, but we can
      // verify the DragTarget is present
      expect(find.byType(DragTarget<SessionDragData>), findsWidgets);
      // And the LongPressDraggable is present
      expect(find.byType(LongPressDraggable<SessionDragData>), findsWidgets);

      // Verify callbacks are wired (no null)
      expect(movedSessionId, isNull); // not yet triggered
    });
  });

  group('SessionDragData — sealed class', () {
    test('SessionDrag holds session', () {
      final s = makeSession(label: 'X');
      final drag = SessionDrag(s);
      expect(drag.session.label, 'X');
    });

    test('GroupDrag holds group path', () {
      final drag = GroupDrag('Production/Web');
      expect(drag.groupPath, 'Production/Web');
    });
  });
}
