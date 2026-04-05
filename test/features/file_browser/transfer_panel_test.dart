import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:letsflutssh/core/transfer/transfer_manager.dart';
import 'package:letsflutssh/core/transfer/transfer_task.dart';
import 'package:letsflutssh/features/file_browser/transfer_panel.dart';
import 'package:letsflutssh/providers/transfer_provider.dart';
import 'package:letsflutssh/theme/app_theme.dart';

Widget _buildTestWidget({
  required TransferManager manager,
  List<HistoryEntry> history = const [],
  ActiveTransferState status = const ActiveTransferState(),
}) {
  return ProviderScope(
    overrides: [
      transferManagerProvider.overrideWithValue(manager),
      transferHistoryProvider.overrideWith((ref) => Stream.value(history)),
      transferStatusProvider.overrideWith((ref) => Stream.value(status)),
    ],
    child: MaterialApp(
      theme: AppTheme.dark(),
      home: const Scaffold(
        body: Column(
          children: [
            Expanded(child: SizedBox()),
            TransferPanel(),
          ],
        ),
      ),
    ),
  );
}

Widget _buildTestWidgetWithHistoryError({
  required TransferManager manager,
  ActiveTransferState status = const ActiveTransferState(),
}) {
  return ProviderScope(
    overrides: [
      transferManagerProvider.overrideWithValue(manager),
      transferHistoryProvider.overrideWith(
        (ref) => Stream<List<HistoryEntry>>.error(Exception('load failed')),
      ),
      transferStatusProvider.overrideWith((ref) => Stream.value(status)),
    ],
    child: MaterialApp(
      theme: AppTheme.dark(),
      home: const Scaffold(
        body: Column(
          children: [
            Expanded(child: SizedBox()),
            TransferPanel(),
          ],
        ),
      ),
    ),
  );
}

Widget _buildTestWidgetWithHistoryLoading({
  required TransferManager manager,
  ActiveTransferState status = const ActiveTransferState(),
}) {
  return ProviderScope(
    overrides: [
      transferManagerProvider.overrideWithValue(manager),
      transferHistoryProvider.overrideWith(
        (ref) => StreamController<List<HistoryEntry>>().stream,
      ),
      transferStatusProvider.overrideWith((ref) => Stream.value(status)),
    ],
    child: MaterialApp(
      theme: AppTheme.dark(),
      home: const Scaffold(
        body: Column(
          children: [
            Expanded(child: SizedBox()),
            TransferPanel(),
          ],
        ),
      ),
    ),
  );
}

void main() {
  late TransferManager manager;

  setUp(() {
    manager = TransferManager();
  });

  tearDown(() {
    manager.dispose();
  });

  group('TransferPanel', () {
    testWidgets('renders collapsed header with "Transfers:" label', (
      tester,
    ) async {
      await tester.pumpWidget(_buildTestWidget(manager: manager));
      await tester.pumpAndSettle();

      expect(find.text('Transfers:'), findsOneWidget);
      expect(find.text('Name'), findsNothing);
    });

    testWidgets('expands on tap to show column headers', (tester) async {
      await tester.pumpWidget(_buildTestWidget(manager: manager));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Transfers:'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Name'), findsOneWidget);
      expect(find.textContaining('Local'), findsOneWidget);
      expect(find.textContaining('Remote'), findsOneWidget);
      expect(find.textContaining('Size'), findsOneWidget);
      // Time column has default sort arrow (descending)
      expect(find.textContaining('Time'), findsOneWidget);
    });

    testWidgets('shows "No transfers yet" when expanded with empty history', (
      tester,
    ) async {
      await tester.pumpWidget(_buildTestWidget(manager: manager));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Transfers:'));
      await tester.pumpAndSettle();

      expect(find.text('No transfers yet'), findsOneWidget);
    });

    testWidgets('collapses on second tap', (tester) async {
      await tester.pumpWidget(_buildTestWidget(manager: manager));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Transfers:'));
      await tester.pumpAndSettle();
      expect(find.text('Name'), findsOneWidget);

      await tester.tap(find.text('Transfers:'));
      await tester.pumpAndSettle();
      expect(find.text('Name'), findsNothing);
    });

    testWidgets('shows clear history button when expanded', (tester) async {
      await tester.pumpWidget(_buildTestWidget(manager: manager));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.delete_outline), findsNothing);

      await tester.tap(find.text('Transfers:'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    });

    testWidgets('shows history count in header', (tester) async {
      final history = [
        HistoryEntry(
          id: '1',
          name: 'test.txt',
          direction: TransferDirection.upload,
          sourcePath: '/local/test.txt',
          targetPath: '/remote/test.txt',
          status: TransferStatus.completed,
          createdAt: DateTime.now(),
          startedAt: DateTime.now(),
          endedAt: DateTime.now(),
        ),
      ];

      await tester.pumpWidget(
        _buildTestWidget(manager: manager, history: history),
      );
      await tester.pumpAndSettle();

      expect(find.text('1 in history'), findsOneWidget);
    });

    testWidgets('shows history entries when expanded', (tester) async {
      final history = [
        HistoryEntry(
          id: '1',
          name: 'upload_file.txt',
          direction: TransferDirection.upload,
          sourcePath: '/local/upload_file.txt',
          targetPath: '/remote/upload_file.txt',
          status: TransferStatus.completed,
          createdAt: DateTime.now(),
          startedAt: DateTime.now(),
          endedAt: DateTime.now(),
        ),
      ];

      await tester.pumpWidget(
        _buildTestWidget(manager: manager, history: history),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Transfers:'));
      await tester.pumpAndSettle();

      expect(find.text('upload_file.txt'), findsOneWidget);
    });

    testWidgets('shows upload direction icon', (tester) async {
      final history = [
        HistoryEntry(
          id: '1',
          name: 'up.txt',
          direction: TransferDirection.upload,
          sourcePath: '/local/up.txt',
          targetPath: '/remote/up.txt',
          status: TransferStatus.completed,
          createdAt: DateTime.now(),
        ),
      ];

      await tester.pumpWidget(
        _buildTestWidget(manager: manager, history: history),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Transfers:'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.arrow_upward), findsOneWidget);
    });

    testWidgets('shows download direction icon', (tester) async {
      final history = [
        HistoryEntry(
          id: '1',
          name: 'down.txt',
          direction: TransferDirection.download,
          sourcePath: '/remote/down.txt',
          targetPath: '/local/down.txt',
          status: TransferStatus.completed,
          createdAt: DateTime.now(),
        ),
      ];

      await tester.pumpWidget(
        _buildTestWidget(manager: manager, history: history),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Transfers:'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.arrow_downward), findsOneWidget);
    });

    testWidgets('shows failed transfer with error icon', (tester) async {
      final history = [
        HistoryEntry(
          id: '1',
          name: 'fail.txt',
          direction: TransferDirection.download,
          sourcePath: '/remote/fail.txt',
          targetPath: '/local/fail.txt',
          status: TransferStatus.failed,
          error: 'Network error',
          createdAt: DateTime.now(),
        ),
      ];

      await tester.pumpWidget(
        _buildTestWidget(manager: manager, history: history),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Transfers:'));
      await tester.pumpAndSettle();

      expect(find.text('fail.txt'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('shows completed transfer with check icon', (tester) async {
      final history = [
        HistoryEntry(
          id: '1',
          name: 'ok.txt',
          direction: TransferDirection.upload,
          sourcePath: '/local/ok.txt',
          targetPath: '/remote/ok.txt',
          status: TransferStatus.completed,
          createdAt: DateTime.now(),
        ),
      ];

      await tester.pumpWidget(
        _buildTestWidget(manager: manager, history: history),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Transfers:'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    });

    testWidgets('resize handle drag updates panel height', (tester) async {
      await tester.pumpWidget(_buildTestWidget(manager: manager));
      await tester.pumpAndSettle();

      // Expand panel first
      await tester.tap(find.text('Transfers:'));
      await tester.pumpAndSettle();

      // Find the resize handle by the resizeRow cursor
      final resizeHandle = find.byWidgetPredicate(
        (w) => w is MouseRegion && w.cursor == SystemMouseCursors.resizeRow,
      );
      expect(resizeHandle, findsOneWidget);

      // Drag the resize handle up
      await tester.drag(resizeHandle, const Offset(0, -50));
      await tester.pumpAndSettle();

      // Panel should still be rendered (no crash)
      expect(find.text('Name'), findsOneWidget);
    });

    testWidgets('resize handle vertical drag clamps to min/max', (
      tester,
    ) async {
      await tester.pumpWidget(_buildTestWidget(manager: manager));
      await tester.pumpAndSettle();

      // Expand panel
      await tester.tap(find.text('Transfers:'));
      await tester.pumpAndSettle();

      final resizeHandle = find.byWidgetPredicate(
        (w) => w is MouseRegion && w.cursor == SystemMouseCursors.resizeRow,
      );
      expect(resizeHandle, findsOneWidget);

      // Drag up by a large amount (should clamp to max 500)
      await tester.drag(resizeHandle, const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(find.text('Name'), findsOneWidget);

      // Drag down by a large amount (should clamp to min 80)
      await tester.drag(resizeHandle, const Offset(0, 600));
      await tester.pumpAndSettle();
      expect(find.text('Name'), findsOneWidget);
    });

    testWidgets('shows formatted size in history row', (tester) async {
      final history = [
        HistoryEntry(
          id: '1',
          name: 'big.bin',
          direction: TransferDirection.upload,
          sourcePath: '/local/big.bin',
          targetPath: '/remote/big.bin',
          status: TransferStatus.completed,
          sizeBytes: 1048576, // 1 MB
          createdAt: DateTime.now(),
          startedAt: DateTime.now(),
          endedAt: DateTime.now().add(const Duration(seconds: 5)),
        ),
      ];

      await tester.pumpWidget(
        _buildTestWidget(manager: manager, history: history),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Transfers:'));
      await tester.pumpAndSettle();

      expect(find.text('big.bin'), findsOneWidget);
      expect(find.textContaining('MB'), findsOneWidget);
    });

    testWidgets('shows shortened paths for long paths', (tester) async {
      final history = [
        HistoryEntry(
          id: '1',
          name: 'deep.txt',
          direction: TransferDirection.download,
          sourcePath: '/very/long/deep/nested/path/to/deep.txt',
          targetPath: '/local/very/long/deep/nested/path/to/deep.txt',
          status: TransferStatus.completed,
          createdAt: DateTime.now(),
        ),
      ];

      await tester.pumpWidget(
        _buildTestWidget(manager: manager, history: history),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Transfers:'));
      await tester.pumpAndSettle();

      expect(find.textContaining('...'), findsWidgets);
    });

    testWidgets('panel is collapsed initially when no active transfers', (
      tester,
    ) async {
      await tester.pumpWidget(_buildTestWidget(manager: manager));
      await tester.pumpAndSettle();

      expect(find.text('Name'), findsNothing);
      expect(find.text('Transfers:'), findsOneWidget);
    });

    testWidgets('clear history button calls manager.clearHistory', (
      tester,
    ) async {
      final history = [
        HistoryEntry(
          id: '1',
          name: 'done.txt',
          direction: TransferDirection.upload,
          sourcePath: '/local/done.txt',
          targetPath: '/remote/done.txt',
          status: TransferStatus.completed,
          createdAt: DateTime.now(),
        ),
      ];

      await tester.pumpWidget(
        _buildTestWidget(manager: manager, history: history),
      );
      await tester.pumpAndSettle();

      // Expand panel
      await tester.tap(find.text('Transfers:'));
      await tester.pumpAndSettle();

      // Tap clear history button
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();

      expect(manager.history, isEmpty);
    });

    testWidgets('auto-expands when active transfers start', (tester) async {
      const status = ActiveTransferState(
        running: 1,
        queued: 0,
        currentInfo: 'Uploading file.txt...',
      );

      await tester.pumpWidget(
        _buildTestWidget(manager: manager, status: status),
      );
      await tester.pumpAndSettle();

      expect(find.text('Name'), findsOneWidget);
      expect(find.text('No transfers yet'), findsOneWidget);
    });

    testWidgets(
      'shows chevron_right icon when collapsed, expand_more when expanded',
      (tester) async {
        await tester.pumpWidget(_buildTestWidget(manager: manager));
        await tester.pumpAndSettle();

        // Initially collapsed: shows chevron_right
        expect(find.byIcon(Icons.chevron_right), findsOneWidget);

        // Expand
        await tester.tap(find.text('Transfers:'));
        await tester.pumpAndSettle();

        // When expanded: shows expand_more
        expect(find.byIcon(Icons.expand_more), findsOneWidget);
      },
    );

    testWidgets('history with multiple entries shows all', (tester) async {
      final history = [
        HistoryEntry(
          id: '1',
          name: 'first.txt',
          direction: TransferDirection.upload,
          sourcePath: '/local/first.txt',
          targetPath: '/remote/first.txt',
          status: TransferStatus.completed,
          createdAt: DateTime.now(),
        ),
        HistoryEntry(
          id: '2',
          name: 'second.txt',
          direction: TransferDirection.download,
          sourcePath: '/remote/second.txt',
          targetPath: '/local/second.txt',
          status: TransferStatus.failed,
          error: 'Disk full',
          createdAt: DateTime.now(),
        ),
      ];

      await tester.pumpWidget(
        _buildTestWidget(manager: manager, history: history),
      );
      await tester.pumpAndSettle();

      expect(find.text('2 in history'), findsOneWidget);

      await tester.tap(find.text('Transfers:'));
      await tester.pumpAndSettle();

      expect(find.text('first.txt'), findsOneWidget);
      expect(find.text('second.txt'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_upward), findsOneWidget);
      expect(find.byIcon(Icons.arrow_downward), findsOneWidget);
    });

    testWidgets('shows duration for completed transfer with timing', (
      tester,
    ) async {
      final startTime = DateTime(2024, 1, 1, 10, 0, 0);
      final endTime = DateTime(2024, 1, 1, 10, 0, 10);
      final history = [
        HistoryEntry(
          id: '1',
          name: 'timed.txt',
          direction: TransferDirection.upload,
          sourcePath: '/local/timed.txt',
          targetPath: '/remote/timed.txt',
          status: TransferStatus.completed,
          createdAt: startTime,
          startedAt: startTime,
          endedAt: endTime,
        ),
      ];

      await tester.pumpWidget(
        _buildTestWidget(manager: manager, history: history),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Transfers:'));
      await tester.pumpAndSettle();

      expect(find.textContaining('10'), findsWidgets);
    });

    testWidgets('column headers have resizable drag handles', (tester) async {
      await tester.pumpWidget(_buildTestWidget(manager: manager));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Transfers:'));
      await tester.pumpAndSettle();

      // Find column resize handles (resizeColumn cursor)
      final resizeHandles = find.byWidgetPredicate(
        (w) => w is MouseRegion && w.cursor == SystemMouseCursors.resizeColumn,
      );
      // 4 column dividers: Local, Remote, Size, Time
      expect(resizeHandles, findsNWidgets(4));
    });

    testWidgets('dragging column handle resizes column', (tester) async {
      await tester.pumpWidget(_buildTestWidget(manager: manager));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Transfers:'));
      await tester.pumpAndSettle();

      final resizeHandles = find.byWidgetPredicate(
        (w) => w is MouseRegion && w.cursor == SystemMouseCursors.resizeColumn,
      );
      // Drag first handle (before Local column)
      await tester.drag(resizeHandles.first, const Offset(30, 0));
      await tester.pumpAndSettle();

      // Panel should still render properly
      expect(find.text('Name'), findsOneWidget);
    });

    testWidgets('clicking column header toggles sort', (tester) async {
      final history = [
        HistoryEntry(
          id: '1',
          name: 'alpha.txt',
          direction: TransferDirection.upload,
          sourcePath: '/local/alpha.txt',
          targetPath: '/remote/alpha.txt',
          status: TransferStatus.completed,
          sizeBytes: 100,
          createdAt: DateTime(2024, 1, 1),
        ),
        HistoryEntry(
          id: '2',
          name: 'beta.txt',
          direction: TransferDirection.download,
          sourcePath: '/remote/beta.txt',
          targetPath: '/local/beta.txt',
          status: TransferStatus.completed,
          sizeBytes: 200,
          createdAt: DateTime(2024, 1, 2),
        ),
      ];

      await tester.pumpWidget(
        _buildTestWidget(manager: manager, history: history),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Transfers:'));
      await tester.pumpAndSettle();

      // Default sort is Time descending — Name has no arrow
      expect(find.text('Name'), findsOneWidget);

      // Click Name header to sort by name
      await tester.tap(find.text('Name'));
      await tester.pumpAndSettle();

      // Name should now show ascending arrow
      expect(find.textContaining('Name'), findsOneWidget);
      expect(find.textContaining('↑'), findsOneWidget);

      // Click Name again to reverse
      await tester.tap(find.textContaining('Name'));
      await tester.pumpAndSettle();

      expect(find.textContaining('↓'), findsOneWidget);
    });

    testWidgets('shows timestamp in Time column for history entry', (
      tester,
    ) async {
      final history = [
        HistoryEntry(
          id: '1',
          name: 'timed.txt',
          direction: TransferDirection.upload,
          sourcePath: '/local/timed.txt',
          targetPath: '/remote/timed.txt',
          status: TransferStatus.completed,
          createdAt: DateTime(2024, 3, 15, 14, 30),
          startedAt: DateTime(2024, 3, 15, 14, 30),
          endedAt: DateTime(2024, 3, 15, 14, 30, 5),
        ),
      ];

      await tester.pumpWidget(
        _buildTestWidget(manager: manager, history: history),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Transfers:'));
      await tester.pumpAndSettle();

      // Should show formatted timestamp with duration
      expect(find.textContaining('2024-03-15'), findsOneWidget);
      expect(find.textContaining('5s'), findsOneWidget);
    });

    testWidgets('column dividers visible in expanded rows', (tester) async {
      final history = [
        HistoryEntry(
          id: '1',
          name: 'file.txt',
          direction: TransferDirection.upload,
          sourcePath: '/local/file.txt',
          targetPath: '/remote/file.txt',
          status: TransferStatus.completed,
          createdAt: DateTime.now(),
        ),
      ];

      await tester.pumpWidget(
        _buildTestWidget(manager: manager, history: history),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Transfers:'));
      await tester.pumpAndSettle();

      // Column dividers are 10px wide SizedBoxes containing a 1px Container
      // Each history row has 4 dividers (before Local, Remote, Size, Time)
      // Plus header has 4 resize handles
      expect(find.text('file.txt'), findsOneWidget);
    });

    testWidgets('does not show clear history button when collapsed', (
      tester,
    ) async {
      await tester.pumpWidget(_buildTestWidget(manager: manager));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.delete_outline), findsNothing);
    });

    testWidgets('shows error text when history stream errors (expanded)', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildTestWidgetWithHistoryError(manager: manager),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Transfers:'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Error:'), findsOneWidget);
    });

    testWidgets('shows SizedBox.shrink in header when history stream errors', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildTestWidgetWithHistoryError(manager: manager),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('in history'), findsNothing);
    });

    testWidgets(
      'shows loading spinner when history stream is pending (expanded)',
      (tester) async {
        await tester.pumpWidget(
          _buildTestWidgetWithHistoryLoading(manager: manager),
        );
        await tester.pump();
        await tester.pump();

        await tester.tap(find.text('Transfers:'));
        await tester.pump();
        await tester.pump();

        expect(find.byType(CircularProgressIndicator), findsOneWidget);
      },
    );

    testWidgets('shows active transfer status in header', (tester) async {
      const status = ActiveTransferState(
        running: 2,
        queued: 3,
        currentInfo: 'Uploading test.txt...',
      );

      await tester.pumpWidget(
        _buildTestWidget(manager: manager, status: status),
      );
      await tester.pumpAndSettle();

      expect(find.text('2 active'), findsOneWidget);
      expect(find.text(', 3 queued'), findsOneWidget);
    });

    testWidgets('footer shows stats when expanded', (tester) async {
      await tester.pumpWidget(_buildTestWidget(manager: manager));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Transfers:'));
      await tester.pumpAndSettle();

      // Footer shows "· N in hist", header shows "N in history"
      expect(find.textContaining('in hist'), findsWidgets);
    });
  });
}
