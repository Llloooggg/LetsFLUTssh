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
    String host = 'h',
    String user = 'u',
  }) {
    return Session(label: label, host: host, user: user, group: group, authType: authType);
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

  group('SessionTreeView — group collapse/expand toggle', () {
    testWidgets('toggle collapse hides children, toggle again shows them',
        (tester) async {
      final s = makeSession(label: 'child', group: 'Parent');
      final tree = SessionTree.build([s], emptyGroups: const {});

      await tester.pumpWidget(buildTreeView(tree: tree));
      await tester.pump();

      // Initially expanded (all groups expanded on initState)
      expect(find.text('child'), findsOneWidget);
      expect(find.byIcon(Icons.folder_open), findsOneWidget);

      // Collapse
      await tester.tap(find.text('Parent'));
      await tester.pump();

      expect(find.text('child'), findsNothing);
      expect(find.byIcon(Icons.folder), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);

      // Expand again
      await tester.tap(find.text('Parent'));
      await tester.pump();

      expect(find.text('child'), findsOneWidget);
      expect(find.byIcon(Icons.folder_open), findsOneWidget);
    });
  });

  group('SessionTreeView — nested groups expand/collapse independently', () {
    testWidgets('collapsing parent hides all children including nested groups',
        (tester) async {
      final s1 = makeSession(label: 'srv', group: 'A/B');
      final tree = SessionTree.build([s1], emptyGroups: const {});

      await tester.pumpWidget(buildTreeView(tree: tree));
      await tester.pump();

      // Both A and B groups visible, srv visible
      expect(find.text('A'), findsOneWidget);
      expect(find.text('B'), findsOneWidget);
      expect(find.text('srv'), findsOneWidget);

      // Collapse A (parent)
      await tester.tap(find.text('A'));
      await tester.pump();

      // B and srv should be hidden
      expect(find.text('B'), findsNothing);
      expect(find.text('srv'), findsNothing);
    });
  });

  group('SessionTreeView — authIcon for all auth types', () {
    testWidgets('password auth shows lock icon', (tester) async {
      final s = makeSession(label: 'pw', authType: AuthType.password);
      final tree = SessionTree.build([s], emptyGroups: const {});

      await tester.pumpWidget(buildTreeView(tree: tree));
      await tester.pump();

      expect(find.byIcon(Icons.lock), findsOneWidget);
    });

    testWidgets('key auth shows vpn_key icon', (tester) async {
      final s = makeSession(label: 'key', authType: AuthType.key);
      final tree = SessionTree.build([s], emptyGroups: const {});

      await tester.pumpWidget(buildTreeView(tree: tree));
      await tester.pump();

      expect(find.byIcon(Icons.vpn_key), findsOneWidget);
    });

    testWidgets('keyWithPassword auth shows enhanced_encryption icon',
        (tester) async {
      final s = makeSession(label: 'kp', authType: AuthType.keyWithPassword);
      final tree = SessionTree.build([s], emptyGroups: const {});

      await tester.pumpWidget(buildTreeView(tree: tree));
      await tester.pump();

      expect(find.byIcon(Icons.enhanced_encryption), findsOneWidget);
    });
  });

  group('SessionTreeView — _canAcceptDrop edge cases', () {
    testWidgets('dropping group on itself is rejected (no move)', (tester) async {
      final s1 = makeSession(label: 'S1', group: 'GroupA');
      final s2 = makeSession(label: 'S2', group: 'GroupB');
      final tree = SessionTree.build([s1, s2], emptyGroups: const {});

      String? movedPath;
      await tester.pumpWidget(buildTreeView(
        tree: tree,
        onSessionMoved: (_, __) {},
        onGroupMoved: (p, t) => movedPath = '$p->$t',
      ));
      await tester.pump();

      // Try dragging GroupA onto itself
      final center = tester.getCenter(find.text('GroupA'));
      final gesture = await tester.startGesture(center);
      await tester.pump(const Duration(milliseconds: 600));

      // Move slightly and drop back on same spot
      await gesture.moveTo(center + const Offset(0, 5));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      // Should NOT have called onGroupMoved because self-drop is rejected
      expect(movedPath, isNull);
    });
  });

  group('SessionTreeView — double-tap connects on desktop', () {
    testWidgets('double-tap fires onSessionDoubleTap', (tester) async {
      Session? doubleTapped;
      final s = makeSession(label: 'DblTap');
      final tree = SessionTree.build([s], emptyGroups: const {});

      await tester.pumpWidget(buildTreeView(
        tree: tree,
        onSessionDoubleTap: (s) => doubleTapped = s,
      ));
      await tester.pump();

      // Double-tap
      await tester.tap(find.text('DblTap'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('DblTap'));
      await tester.pumpAndSettle();

      expect(doubleTapped, isNotNull);
      expect(doubleTapped!.label, 'DblTap');
    });
  });

  group('SessionTreeView — right-click context menu on session', () {
    testWidgets('right-click fires onSessionContextMenu', (tester) async {
      Session? contextSession;
      Offset? contextPos;
      final s = makeSession(label: 'RightClick');
      final tree = SessionTree.build([s], emptyGroups: const {});

      await tester.pumpWidget(buildTreeView(
        tree: tree,
        onSessionContextMenu: (s, pos) {
          contextSession = s;
          contextPos = pos;
        },
      ));
      await tester.pump();

      // Right-click
      final center = tester.getCenter(find.text('RightClick'));
      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton,
      );
      await gesture.addPointer(location: center);
      await gesture.down(center);
      await gesture.up();
      await tester.pumpAndSettle();

      expect(contextSession, isNotNull);
      expect(contextSession!.label, 'RightClick');
      expect(contextPos, isNotNull);
    });
  });

  group('SessionTreeView — right-click context menu on group', () {
    testWidgets('right-click on group fires onGroupContextMenu',
        (tester) async {
      String? groupPath;
      final s = makeSession(label: 'srv', group: 'MyGroup');
      final tree = SessionTree.build([s], emptyGroups: const {});

      await tester.pumpWidget(buildTreeView(
        tree: tree,
        onGroupContextMenu: (path, _) => groupPath = path,
      ));
      await tester.pump();

      // Right-click on group
      final center = tester.getCenter(find.text('MyGroup'));
      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton,
      );
      await gesture.addPointer(location: center);
      await gesture.down(center);
      await gesture.up();
      await tester.pumpAndSettle();

      expect(groupPath, 'MyGroup');
    });
  });

  group('SessionTreeView — background right-click', () {
    testWidgets('right-click on background fires onBackgroundContextMenu',
        (tester) async {
      Offset? bgPos;
      final s = makeSession(label: 'srv');
      final tree = SessionTree.build([s], emptyGroups: const {});

      await tester.pumpWidget(buildTreeView(
        tree: tree,
        onBackgroundContextMenu: (pos) => bgPos = pos,
      ));
      await tester.pump();

      // Right-click on empty area below the tree
      final treeView = find.byType(SessionTreeView);
      final rect = tester.getRect(treeView);
      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton,
      );
      final pos = Offset(rect.center.dx, rect.bottom - 10);
      await gesture.addPointer(location: pos);
      await gesture.down(pos);
      await gesture.up();
      await tester.pumpAndSettle();

      expect(bgPos, isNotNull);
    });
  });

  group('SessionTreeView — session tap selects', () {
    testWidgets('tapping session changes selection and fires onSessionTap',
        (tester) async {
      Session? tapped;
      final s1 = makeSession(label: 'A');
      final s2 = makeSession(label: 'B');
      final tree = SessionTree.build([s1, s2], emptyGroups: const {});

      await tester.pumpWidget(buildTreeView(
        tree: tree,
        onSessionTap: (s) => tapped = s,
      ));
      await tester.pump();

      await tester.tap(find.text('A'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(tapped, isNotNull);
      expect(tapped!.label, 'A');

      // Tap B to change selection
      await tester.tap(find.text('B'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(tapped!.label, 'B');
    });
  });

  group('SessionTreeView — empty groups show in tree', () {
    testWidgets('empty group shows as folder with 0 count', (tester) async {
      final tree = SessionTree.build([], emptyGroups: {'EmptyFolder'});

      await tester.pumpWidget(buildTreeView(tree: tree));
      await tester.pump();

      expect(find.text('EmptyFolder'), findsOneWidget);
      expect(find.text('0'), findsOneWidget);
    });
  });
}
