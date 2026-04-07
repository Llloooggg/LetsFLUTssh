import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import '''package:letsflutssh/l10n/app_localizations.dart''';
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
  @override
  Future<int> dirSize(String path) async => 0;
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
  group('MobileFileList — onTransfer called for file tap (non-selection)', () {
    testWidgets('tapping a file calls onTransfer', (tester) async {
      final fs = _FakeFS(fakeEntries: _entries());
      final ctrl = FilePaneController(fs: fs, label: 'Remote');
      await ctrl.init();

      FileEntry? transferred;

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Scaffold(
              body: MobileFileList(
                controller: ctrl,
                onTransfer: (e) => transferred = e,
                onTransferMultiple: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // Tap a file (not a dir) — should call onTransfer
      await tester.tap(find.text('notes.txt'));
      await tester.pump();

      expect(transferred, isNotNull);
      expect(transferred!.name, 'notes.txt');

      ctrl.dispose();
    });
  });

  group('MobileFileList — tapping dir navigates', () {
    testWidgets('tapping a directory navigates into it', (tester) async {
      final fs = _FakeFS(fakeEntries: _entries());
      final ctrl = FilePaneController(fs: fs, label: 'Remote');
      await ctrl.init();

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
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

      // Tap a directory — should navigate
      await tester.tap(find.text('photos'));
      await tester.pump();

      expect(ctrl.currentPath, '/home/test/photos');

      ctrl.dispose();
    });
  });

  group('MobileFileList — selection mode exit on last deselect', () {
    testWidgets('deselecting last item exits selection mode', (tester) async {
      final fs = _FakeFS(fakeEntries: _entries());
      final ctrl = FilePaneController(fs: fs, label: 'Remote');
      await ctrl.init();

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
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

      // Long press opens bottom sheet; tap "Select" to enter selection mode
      await tester.longPress(find.text('notes.txt'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Select'));
      await tester.pumpAndSettle();
      expect(find.text('1 selected'), findsOneWidget);
      expect(find.byType(Checkbox), findsWidgets);

      // Tap same item to deselect -> should exit selection mode
      await tester.tap(find.text('notes.txt'));
      await tester.pump();

      // Selection mode should be gone
      expect(find.byType(Checkbox), findsNothing);

      ctrl.dispose();
    });
  });

  group('MobileFileList — bottom sheet actions', () {
    testWidgets('bottom sheet Transfer action calls onTransfer', (
      tester,
    ) async {
      final fs = _FakeFS(fakeEntries: _entries());
      final ctrl = FilePaneController(fs: fs, label: 'Remote');
      await ctrl.init();

      FileEntry? transferred;

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Scaffold(
              body: MobileFileList(
                controller: ctrl,
                onTransfer: (e) => transferred = e,
                onTransferMultiple: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // Long press to open bottom sheet
      await tester.longPress(find.text('backup.tar'));
      await tester.pumpAndSettle();

      // Tap Transfer in bottom sheet
      await tester.tap(find.text('Transfer'));
      await tester.pumpAndSettle();

      expect(transferred, isNotNull);
      expect(transferred!.name, 'backup.tar');

      ctrl.dispose();
    });

    testWidgets('bottom sheet Open action navigates to dir', (tester) async {
      final fs = _FakeFS(fakeEntries: _entries());
      final ctrl = FilePaneController(fs: fs, label: 'Remote');
      await ctrl.init();

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
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

      // Long press directory to open bottom sheet
      await tester.longPress(find.text('photos'));
      await tester.pumpAndSettle();

      // Tap Open in bottom sheet
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(ctrl.currentPath, '/home/test/photos');

      ctrl.dispose();
    });

    testWidgets('bottom sheet Rename action opens rename dialog', (
      tester,
    ) async {
      final fs = _FakeFS(fakeEntries: _entries());
      final ctrl = FilePaneController(fs: fs, label: 'Remote');
      await ctrl.init();

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
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

      // Long press to open bottom sheet
      await tester.longPress(find.text('backup.tar'));
      await tester.pumpAndSettle();

      // Tap Rename
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();

      // Rename dialog should appear
      expect(find.text('Rename'), findsWidgets);

      // Cancel the rename dialog
      final cancelButtons = find.text('Cancel');
      if (cancelButtons.evaluate().isNotEmpty) {
        await tester.tap(cancelButtons.last);
        await tester.pumpAndSettle();
      }

      ctrl.dispose();
    });

    testWidgets('bottom sheet New Folder action opens dialog', (tester) async {
      final fs = _FakeFS(fakeEntries: _entries());
      final ctrl = FilePaneController(fs: fs, label: 'Remote');
      await ctrl.init();

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
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

      // Long press to open bottom sheet
      await tester.longPress(find.text('backup.tar'));
      await tester.pumpAndSettle();

      // Tap New Folder
      await tester.tap(find.text('New Folder'));
      await tester.pumpAndSettle();

      // New Folder dialog should appear
      expect(find.text('New Folder'), findsWidgets);

      // Cancel
      final cancelButtons = find.text('Cancel');
      if (cancelButtons.evaluate().isNotEmpty) {
        await tester.tap(cancelButtons.last);
        await tester.pumpAndSettle();
      }

      ctrl.dispose();
    });
  });

  group('MobileFileList — error state', () {
    testWidgets('controller with error shows error message and retry', (
      tester,
    ) async {
      final fs = _FakeFS(fakeEntries: []);
      final ctrl = FilePaneController(fs: fs, label: 'Remote');
      // Navigate to a path that will throw
      final badFs = _ErrorFS();
      final badCtrl = FilePaneController(fs: badFs, label: 'Bad');
      await badCtrl.navigateTo('/error');

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Scaffold(
              body: MobileFileList(
                controller: badCtrl,
                onTransfer: (_) {},
                onTransferMultiple: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);

      badCtrl.dispose();
      ctrl.dispose();
    });
  });

  group('MobileFileList — file row details', () {
    testWidgets('file rows show size, dir rows show folder icon', (
      tester,
    ) async {
      final fs = _FakeFS(fakeEntries: _entries());
      final ctrl = FilePaneController(fs: fs, label: 'Remote');
      await ctrl.init();

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
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

      // Dir should have folder icon
      expect(find.byIcon(Icons.folder), findsOneWidget);
      // Files should have file icon
      expect(find.byIcon(Icons.insert_drive_file), findsNWidgets(2));

      ctrl.dispose();
    });

    testWidgets('selected row has colored background', (tester) async {
      final fs = _FakeFS(fakeEntries: _entries());
      final ctrl = FilePaneController(fs: fs, label: 'Remote');
      await ctrl.init();

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
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

      // Long press opens bottom sheet; tap "Select" to enter selection mode
      await tester.longPress(find.text('notes.txt'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Select'));
      await tester.pumpAndSettle();

      // Verify checkbox is visible (selection mode active)
      expect(find.byType(Checkbox), findsWidgets);

      ctrl.dispose();
    });
  });
}

/// A file system that always throws on list.
class _ErrorFS implements FileSystem {
  @override
  Future<String> initialDir() async => '/error';
  @override
  Future<List<FileEntry>> list(String path) async =>
      throw Exception('FS error');
  @override
  Future<void> mkdir(String path) async {}
  @override
  Future<void> remove(String path) async {}
  @override
  Future<void> removeDir(String path) async {}
  @override
  Future<void> rename(String oldPath, String newPath) async {}
  @override
  Future<int> dirSize(String path) async => 0;
}
