import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:letsflutssh/core/sftp/sftp_models.dart';
import 'package:letsflutssh/core/sftp/file_system.dart';
import 'package:letsflutssh/features/file_browser/file_browser_controller.dart';
import 'package:letsflutssh/features/mobile/mobile_file_browser.dart';
import 'package:letsflutssh/theme/app_theme.dart';

/// Fake file system for testing.
class _FakeFS implements FileSystem {
  final List<FileEntry> fakeEntries;
  final String fakeInitialDir;

  _FakeFS({this.fakeEntries = const [], String initialDir = '/home/test'})
      : fakeInitialDir = initialDir;

  @override
  Future<String> initialDir() async => fakeInitialDir;
  @override
  Future<List<FileEntry>> list(String path) async => fakeEntries;
  @override
  Future<void> mkdir(String path) async {}
  @override
  Future<void> remove(String path) async {}
  @override
  Future<void> removeDir(String path) async {}
  @override
  Future<void> rename(String oldPath, String newPath) async {}
}

List<FileEntry> _entries() => [
      FileEntry(
        name: 'photos',
        path: '/home/test/photos',
        size: 4096,
        mode: 0x1ED,
        modTime: DateTime(2024, 1, 1),
        isDir: true,
      ),
      FileEntry(
        name: 'notes.txt',
        path: '/home/test/notes.txt',
        size: 2048,
        mode: 0x1A4,
        modTime: DateTime(2024, 1, 2),
        isDir: false,
      ),
      FileEntry(
        name: 'backup.tar',
        path: '/home/test/backup.tar',
        size: 10240,
        mode: 0x1A4,
        modTime: DateTime(2024, 1, 3),
        isDir: false,
      ),
    ];

void main() {
  group('MobileFileBrowser — toolbar toggle and path breadcrumb', () {
    late _FakeFS fakeFs;
    late FilePaneController controller;

    setUp(() {
      fakeFs = _FakeFS(fakeEntries: _entries());
      controller = FilePaneController(fs: fakeFs, label: 'Remote');
    });

    tearDown(() => controller.dispose());

    Widget buildFileList({
      FilePaneController? ctrl,
      void Function(FileEntry)? onTransfer,
      void Function(List<FileEntry>)? onTransferMultiple,
    }) {
      return ProviderScope(
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: MobileFileList(
              controller: ctrl ?? controller,
              onTransfer: onTransfer ?? (_) {},
              onTransferMultiple: onTransferMultiple ?? (_) {},
            ),
          ),
        ),
      );
    }

    testWidgets('transfer bar transfer button calls onTransferMultiple and exits selection',
        (tester) async {
      List<FileEntry>? transferred;
      await controller.init();
      await tester.pumpWidget(buildFileList(
        onTransferMultiple: (entries) => transferred = entries,
      ));
      await tester.pump();

      // Enter selection mode
      await tester.longPress(find.text('notes.txt'));
      await tester.pump();

      // Add another item
      await tester.tap(find.text('backup.tar'));
      await tester.pump();
      expect(find.text('2 selected'), findsOneWidget);

      // Tap transfer icon in selection bar
      await tester.tap(find.byTooltip('Transfer'));
      await tester.pump();

      expect(transferred, isNotNull);
      expect(transferred!.length, 2);
      // Selection mode exited
      expect(find.byType(Checkbox), findsNothing);
    });

    testWidgets('bottom sheet Delete action opens confirm dialog',
        (tester) async {
      await controller.init();
      await tester.pumpWidget(buildFileList());
      await tester.pump();

      // Enter selection mode
      await tester.longPress(find.text('notes.txt'));
      await tester.pump();

      // Long press again in selection mode to show bottom sheet
      await tester.longPress(find.text('backup.tar'));
      await tester.pumpAndSettle();

      // Tap Delete in bottom sheet
      final deleteItems = find.text('Delete');
      expect(deleteItems, findsWidgets);
      await tester.tap(deleteItems.last);
      await tester.pumpAndSettle();

      // Confirm dialog should appear
      expect(find.textContaining('Delete'), findsWidgets);

      // Cancel the dialog (avoids toast timer issues)
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });

    testWidgets('tapping dir in selection mode toggles dir selection',
        (tester) async {
      await controller.init();
      await tester.pumpWidget(buildFileList());
      await tester.pump();

      // Enter selection mode on a file
      await tester.longPress(find.text('notes.txt'));
      await tester.pump();
      expect(find.text('1 selected'), findsOneWidget);

      // Tap the dir — should toggle its selection (not navigate)
      await tester.tap(find.text('photos'));
      await tester.pump();
      expect(find.text('2 selected'), findsOneWidget);

      // Tap photos again to deselect
      await tester.tap(find.text('photos'));
      await tester.pump();
      expect(find.text('1 selected'), findsOneWidget);
    });

    testWidgets('selection bar shows correct count text', (tester) async {
      await controller.init();
      await tester.pumpWidget(buildFileList());
      await tester.pump();

      // Enter selection mode
      await tester.longPress(find.text('photos'));
      await tester.pump();
      expect(find.text('1 selected'), findsOneWidget);

      // Select all 3
      await tester.tap(find.text('notes.txt'));
      await tester.pump();
      await tester.tap(find.text('backup.tar'));
      await tester.pump();
      expect(find.text('3 selected'), findsOneWidget);
    });

    testWidgets('selection bar delete button opens confirm then exits selection',
        (tester) async {
      await controller.init();
      await tester.pumpWidget(buildFileList());
      await tester.pump();

      // Enter selection
      await tester.longPress(find.text('backup.tar'));
      await tester.pump();

      // Tap delete in bar
      await tester.tap(find.byTooltip('Delete'));
      await tester.pumpAndSettle();

      // Cancel the confirm dialog
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // Selection mode should exit after confirmDelete
      expect(find.byType(Checkbox), findsNothing);
    });
  });

  group('MobileFileList — uninitialised controller', () {
    testWidgets('uninitialised controller shows empty directory',
        (tester) async {
      final fs = _FakeFS(fakeEntries: []);
      final ctrl = FilePaneController(fs: fs, label: 'Empty');
      // Don't init — entries empty, loading false

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: Scaffold(
              body: MobileFileList(
                controller: ctrl,
                onTransfer: (_) {},
                onTransferMultiple: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Empty directory'), findsOneWidget);

      ctrl.dispose();
    });
  });

  group('MobileFileList — didUpdateWidget', () {
    testWidgets('changing controller updates listener', (tester) async {
      final fs1 = _FakeFS(fakeEntries: _entries());
      final ctrl1 = FilePaneController(fs: fs1, label: 'First');
      await ctrl1.init();

      final fs2 = _FakeFS(fakeEntries: [
        FileEntry(
          name: 'other.txt',
          path: '/home/test/other.txt',
          size: 100,
          mode: 0x1A4,
          modTime: DateTime(2024),
          isDir: false,
        ),
      ]);
      final ctrl2 = FilePaneController(fs: fs2, label: 'Second');
      await ctrl2.init();

      // Build with ctrl1 first
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: Scaffold(
              body: MobileFileList(
                controller: ctrl1,
                onTransfer: (_) {},
                onTransferMultiple: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('notes.txt'), findsOneWidget);

      // Rebuild with ctrl2
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: Scaffold(
              body: MobileFileList(
                controller: ctrl2,
                onTransfer: (_) {},
                onTransferMultiple: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('other.txt'), findsOneWidget);

      ctrl1.dispose();
      ctrl2.dispose();
    });
  });
}
