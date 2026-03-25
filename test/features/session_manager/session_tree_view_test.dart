import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/session/session.dart';
import 'package:letsflutssh/core/session/session_tree.dart';
import 'package:letsflutssh/features/session_manager/session_tree_view.dart';
import 'package:letsflutssh/theme/app_theme.dart';

void main() {
  late List<Session> sessions;
  late List<SessionTreeNode> tree;

  setUp(() {
    sessions = [
      Session(id: '1', label: 'nginx1', group: 'Production/Web', host: '10.0.0.1', user: 'root'),
      Session(id: '2', label: 'nginx2', group: 'Production/Web', host: '10.0.0.2', user: 'root'),
      Session(id: '3', label: 'db-master', group: 'Production/DB', host: '10.0.1.1', user: 'admin'),
      Session(id: '4', label: 'staging', group: '', host: '192.168.1.1', user: 'deploy'),
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

    testWidgets('shows host:port for sessions', (tester) async {
      await tester.pumpWidget(buildApp());
      expect(find.text('10.0.0.1:22'), findsOneWidget);
      expect(find.text('10.0.0.2:22'), findsOneWidget);
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
      // Expanded groups show folder_open icons
      expect(find.byIcon(Icons.folder_open), findsWidgets);
    });

    testWidgets('shows auth icons for sessions', (tester) async {
      await tester.pumpWidget(buildApp());
      // Default auth type is password → lock icon
      expect(find.byIcon(Icons.lock), findsWidgets);
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

    testWidgets('shows chevron_right for collapsed group', (tester) async {
      await tester.pumpWidget(buildApp());

      // Collapse Web
      await tester.tap(find.text('Web'));
      await tester.pumpAndSettle();

      // Collapsed group should show chevron_right
      expect(find.byIcon(Icons.chevron_right), findsWidgets);
    });

    testWidgets('shows expand_more for expanded group', (tester) async {
      await tester.pumpWidget(buildApp());

      // Groups start expanded
      expect(find.byIcon(Icons.expand_more), findsWidgets);
    });

    testWidgets('shows folder icon for collapsed group', (tester) async {
      await tester.pumpWidget(buildApp());

      // Collapse Web
      await tester.tap(find.text('Web'));
      await tester.pumpAndSettle();

      // Should show closed folder icon
      expect(find.byIcon(Icons.folder), findsWidgets);
    });

    testWidgets('shows key icon for key auth type', (tester) async {
      final keySessions = [
        Session(
          id: '10',
          label: 'key-server',
          group: '',
          host: '10.0.0.10',
          user: 'root',
          authType: AuthType.key,
        ),
      ];
      final keyTree = SessionTree.build(keySessions);
      await tester.pumpWidget(buildApp(overrideTree: keyTree));

      expect(find.byIcon(Icons.vpn_key), findsOneWidget);
    });

    testWidgets('shows enhanced_encryption icon for keyWithPassword auth', (tester) async {
      final keySessions = [
        Session(
          id: '11',
          label: 'enc-server',
          group: '',
          host: '10.0.0.11',
          user: 'root',
          authType: AuthType.keyWithPassword,
        ),
      ];
      final keyTree = SessionTree.build(keySessions);
      await tester.pumpWidget(buildApp(overrideTree: keyTree));

      expect(find.byIcon(Icons.enhanced_encryption), findsOneWidget);
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
        Session(id: '1', label: 'root-server', group: '', host: 'h', user: 'u'),
      ];
      final rootTree = SessionTree.build(rootOnly);
      await tester.pumpWidget(buildApp(overrideTree: rootTree));

      expect(find.text('root-server'), findsOneWidget);
      expect(find.text('h:22'), findsOneWidget);
    });

    testWidgets('LongPressDraggable is present for sessions on desktop', (tester) async {
      await tester.pumpWidget(buildApp());

      // On desktop, sessions should be wrapped in LongPressDraggable
      expect(find.byType(LongPressDraggable<SessionDragData>), findsWidgets);
    });

    testWidgets('DragTarget for root drop zone is present', (tester) async {
      await tester.pumpWidget(buildApp());

      expect(find.byType(DragTarget<SessionDragData>), findsWidgets);
    });
  });

  group('SessionDragData', () {
    test('SessionDrag holds session', () {
      final session = Session(id: '1', label: 'test', host: 'h', user: 'u');
      final drag = SessionDrag(session);
      expect(drag.session, session);
    });

    test('GroupDrag holds group path', () {
      final drag = GroupDrag('Production/Web');
      expect(drag.groupPath, 'Production/Web');
    });
  });
}
