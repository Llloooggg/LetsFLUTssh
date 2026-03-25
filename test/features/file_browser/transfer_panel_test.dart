import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:letsflutssh/core/transfer/transfer_manager.dart';
import 'package:letsflutssh/core/transfer/transfer_task.dart';
import 'package:letsflutssh/features/file_browser/transfer_panel.dart';
import 'package:letsflutssh/providers/transfer_provider.dart';

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
    child: const MaterialApp(
      home: Scaffold(
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
    testWidgets('renders collapsed header with "Transfers" label', (tester) async {
      await tester.pumpWidget(_buildTestWidget(manager: manager));
      await tester.pumpAndSettle();

      expect(find.text('Transfers'), findsOneWidget);
      expect(find.text('Name'), findsNothing);
    });

    testWidgets('expands on tap to show column headers', (tester) async {
      await tester.pumpWidget(_buildTestWidget(manager: manager));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Transfers'));
      await tester.pumpAndSettle();

      expect(find.text('Name'), findsOneWidget);
      expect(find.text('Local'), findsOneWidget);
      expect(find.text('Remote'), findsOneWidget);
      expect(find.text('Size'), findsOneWidget);
      expect(find.text('Duration'), findsOneWidget);
    });

    testWidgets('shows "No transfers yet" when expanded with empty history', (tester) async {
      await tester.pumpWidget(_buildTestWidget(manager: manager));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Transfers'));
      await tester.pumpAndSettle();

      expect(find.text('No transfers yet'), findsOneWidget);
    });

    testWidgets('collapses on second tap', (tester) async {
      await tester.pumpWidget(_buildTestWidget(manager: manager));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Transfers'));
      await tester.pumpAndSettle();
      expect(find.text('Name'), findsOneWidget);

      await tester.tap(find.text('Transfers'));
      await tester.pumpAndSettle();
      expect(find.text('Name'), findsNothing);
    });

    testWidgets('shows clear history button when expanded', (tester) async {
      await tester.pumpWidget(_buildTestWidget(manager: manager));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.delete_sweep), findsNothing);

      await tester.tap(find.text('Transfers'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.delete_sweep), findsOneWidget);
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

      await tester.pumpWidget(_buildTestWidget(manager: manager, history: history));
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

      await tester.pumpWidget(_buildTestWidget(manager: manager, history: history));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Transfers'));
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

      await tester.pumpWidget(_buildTestWidget(manager: manager, history: history));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Transfers'));
      await tester.pumpAndSettle();

      expect(find.text('↑'), findsOneWidget);
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

      await tester.pumpWidget(_buildTestWidget(manager: manager, history: history));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Transfers'));
      await tester.pumpAndSettle();

      expect(find.text('↓'), findsOneWidget);
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

      await tester.pumpWidget(_buildTestWidget(manager: manager, history: history));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Transfers'));
      await tester.pumpAndSettle();

      expect(find.text('fail.txt'), findsOneWidget);
      expect(find.byIcon(Icons.error), findsOneWidget);
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

      await tester.pumpWidget(_buildTestWidget(manager: manager, history: history));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Transfers'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.check_circle), findsOneWidget);
    });

    testWidgets('shows active transfer status in header', (tester) async {
      const status = ActiveTransferState(
        running: 2,
        queued: 3,
        currentInfo: 'Uploading test.txt...',
      );

      await tester.pumpWidget(_buildTestWidget(manager: manager, status: status));
      await tester.pumpAndSettle();

      expect(find.text('2 active, 3 queued'), findsOneWidget);
      expect(find.text('Uploading test.txt...'), findsOneWidget);
    });
  });
}
