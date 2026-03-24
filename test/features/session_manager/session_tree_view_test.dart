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
  });
}
