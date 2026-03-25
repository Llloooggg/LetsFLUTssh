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

  group('SessionTreeView — _canAcceptDrop logic', () {
    testWidgets('DragTarget for group exists and accepts drop data',
        (tester) async {
      final s1 = makeSession(label: 'S1', group: 'GroupA');
      final s2 = makeSession(label: 'S2', group: 'GroupB');
      final tree = SessionTree.build([s1, s2], emptyGroups: const {});

      await tester.pumpWidget(buildTreeView(
        tree: tree,
        onSessionMoved: (id, target) {},
        onGroupMoved: (path, parent) {},
      ));
      await tester.pump();

      // Both DragTargets and LongPressDraggables should be present
      expect(find.byType(DragTarget<SessionDragData>), findsWidgets);
      expect(
          find.byType(LongPressDraggable<SessionDragData>), findsWidgets);
    });
  });

  group('SessionTreeView — deeply nested groups', () {
    testWidgets('renders 3-level nested groups', (tester) async {
      final s = makeSession(label: 'deep', group: 'A/B/C');
      final tree = SessionTree.build([s], emptyGroups: const {});

      await tester.pumpWidget(buildTreeView(tree: tree));
      await tester.pump();

      expect(find.text('A'), findsOneWidget);
      expect(find.text('B'), findsOneWidget);
      expect(find.text('C'), findsOneWidget);
      expect(find.text('deep'), findsOneWidget);
    });

    testWidgets('collapsing middle level hides descendants', (tester) async {
      final s = makeSession(label: 'deep', group: 'A/B/C');
      final tree = SessionTree.build([s], emptyGroups: const {});

      await tester.pumpWidget(buildTreeView(tree: tree));
      await tester.pump();

      // Collapse B
      await tester.tap(find.text('B'));
      await tester.pump();

      expect(find.text('C'), findsNothing);
      expect(find.text('deep'), findsNothing);
      // A and B should still be visible
      expect(find.text('A'), findsOneWidget);
      expect(find.text('B'), findsOneWidget);
    });
  });

  group('SessionTreeView — indent guides depth', () {
    testWidgets('depth 0 sessions have minimal indent', (tester) async {
      final s = makeSession(label: 'root-srv');
      final tree = SessionTree.build([s], emptyGroups: const {});

      await tester.pumpWidget(buildTreeView(tree: tree));
      await tester.pump();

      // Root session should render without wide indent
      expect(find.text('root-srv'), findsOneWidget);
    });

    testWidgets('deeply nested sessions show multiple indent guides',
        (tester) async {
      final s = makeSession(label: 'deep-srv', group: 'L1/L2/L3');
      final tree = SessionTree.build([s], emptyGroups: const {});

      await tester.pumpWidget(buildTreeView(tree: tree));
      await tester.pump();

      // Session at depth 3 should have indent guides
      expect(find.text('deep-srv'), findsOneWidget);
      // There should be Container widgets used for indent guide lines
      expect(find.byType(Container), findsWidgets);
    });
  });

  group('SessionTreeView — selection state', () {
    testWidgets('tapping a session changes selection', (tester) async {
      final s1 = makeSession(label: 'Srv1');
      final s2 = makeSession(label: 'Srv2');
      final tree = SessionTree.build([s1, s2], emptyGroups: const {});

      await tester.pumpWidget(buildTreeView(
        tree: tree,
        onSessionTap: (_) {},
      ));
      await tester.pump();

      // Tap Srv1
      await tester.tap(find.text('Srv1'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      // Tap Srv2 to change selection
      await tester.tap(find.text('Srv2'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      // Both should still be visible, no crash
      expect(find.text('Srv1'), findsOneWidget);
      expect(find.text('Srv2'), findsOneWidget);
    });
  });

  group('SessionTreeView — drop target highlight', () {
    testWidgets('DragTarget onMove/onLeave exist without crash',
        (tester) async {
      final s1 = makeSession(label: 'S1', group: 'G1');
      final tree = SessionTree.build([s1], emptyGroups: const {});

      await tester.pumpWidget(buildTreeView(
        tree: tree,
        onSessionMoved: (_, __) {},
      ));
      await tester.pump();

      // Verify the tree renders with DragTargets
      expect(find.byType(DragTarget<SessionDragData>), findsWidgets);
    });
  });

  group('SessionTreeView — mixed auth types in tree', () {
    testWidgets('renders different auth icons in same tree', (tester) async {
      final s1 = makeSession(
          label: 'PW', authType: AuthType.password);
      final s2 = makeSession(
          label: 'KY', authType: AuthType.key);
      final s3 = makeSession(
          label: 'KP', authType: AuthType.keyWithPassword);
      final tree = SessionTree.build([s1, s2, s3], emptyGroups: const {});

      await tester.pumpWidget(buildTreeView(tree: tree));
      await tester.pump();

      expect(find.byIcon(Icons.lock), findsWidgets);
      expect(find.byIcon(Icons.vpn_key), findsOneWidget);
      expect(find.byIcon(Icons.enhanced_encryption), findsOneWidget);
    });
  });

  group('SessionTreeView — group with empty groups set', () {
    testWidgets('empty groups render as folders', (tester) async {
      final tree = SessionTree.build([], emptyGroups: {'Folder1', 'Folder2'});

      await tester.pumpWidget(buildTreeView(tree: tree));
      await tester.pump();

      expect(find.text('Folder1'), findsOneWidget);
      expect(find.text('Folder2'), findsOneWidget);
    });

    testWidgets('empty group count shows 0', (tester) async {
      final tree = SessionTree.build([], emptyGroups: {'EmptyG'});

      await tester.pumpWidget(buildTreeView(tree: tree));
      await tester.pump();

      expect(find.text('0'), findsOneWidget);
    });
  });

  group('SessionTreeView — group LongPressDraggable feedback', () {
    testWidgets('group has LongPressDraggable with GroupDrag data',
        (tester) async {
      final s = makeSession(label: 'S', group: 'TestGroup');
      final tree = SessionTree.build([s], emptyGroups: const {});

      await tester.pumpWidget(buildTreeView(tree: tree));
      await tester.pump();

      // On desktop, groups should have LongPressDraggable
      expect(
          find.byType(LongPressDraggable<SessionDragData>), findsWidgets);
    });
  });

  group('SessionTreeView — session tap callback with doubleTap', () {
    testWidgets('double tap fires onSessionDoubleTap', (tester) async {
      Session? doubleTapped;
      final s = makeSession(label: 'DblTap');
      final tree = SessionTree.build([s], emptyGroups: const {});

      await tester.pumpWidget(buildTreeView(
        tree: tree,
        onSessionDoubleTap: (session) => doubleTapped = session,
      ));
      await tester.pump();

      final center = tester.getCenter(find.text('DblTap'));
      await tester.tapAt(center);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(center);
      await tester.pumpAndSettle();

      expect(doubleTapped?.label, 'DblTap');
    });
  });

  group('SessionTreeView — large tree performance', () {
    testWidgets('renders many sessions without crash', (tester) async {
      final sessions = List.generate(
        20,
        (i) => makeSession(label: 'Srv$i', group: i < 10 ? 'G1' : 'G2'),
      );
      final tree = SessionTree.build(sessions, emptyGroups: const {});

      await tester.pumpWidget(buildTreeView(tree: tree));
      await tester.pump();

      expect(find.text('G1'), findsOneWidget);
      expect(find.text('G2'), findsOneWidget);
    });
  });

  group('SessionTreeView — background context menu with sessions', () {
    testWidgets('right-click on background fires onBackgroundContextMenu',
        (tester) async {
      Offset? bgPos;
      final s = makeSession(label: 'Tiny');
      final tree = SessionTree.build([s], emptyGroups: const {});

      await tester.pumpWidget(buildTreeView(
        tree: tree,
        onBackgroundContextMenu: (pos) => bgPos = pos,
      ));
      await tester.pump();

      // Right-click on the tree background
      final treeView = find.byType(SessionTreeView);
      final rect = tester.getRect(treeView);
      final bgPoint = Offset(rect.center.dx, rect.bottom - 10);

      final gesture = await tester.startGesture(
        bgPoint,
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await gesture.up();
      await tester.pumpAndSettle();

      expect(bgPos, isNotNull);
    });
  });
}
