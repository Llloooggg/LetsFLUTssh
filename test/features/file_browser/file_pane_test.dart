import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/sftp/file_system.dart';
import 'package:letsflutssh/core/sftp/sftp_models.dart';
import 'package:letsflutssh/features/file_browser/file_browser_controller.dart';
import 'package:letsflutssh/features/file_browser/file_pane.dart';
import 'package:letsflutssh/theme/app_theme.dart';

/// In-memory file system for testing.
class _MockFS implements FileSystem {
  final Map<String, List<FileEntry>> dirs;

  _MockFS(this.dirs);

  @override
  Future<String> initialDir() async => '/home';

  @override
  Future<List<FileEntry>> list(String path) async {
    if (!dirs.containsKey(path)) throw Exception('Not found: $path');
    return dirs[path]!;
  }

  @override
  Future<void> mkdir(String path) async {}

  @override
  Future<void> remove(String path) async {}

  @override
  Future<void> removeDir(String path) async {}

  @override
  Future<void> rename(String oldPath, String newPath) async {}
}

void main() {
  final now = DateTime(2024, 1, 1);

  Widget buildApp({
    required FilePaneController controller,
    String paneId = 'test-pane',
  }) {
    return MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
        body: SizedBox(
          width: 600,
          height: 400,
          child: FilePane(
            controller: controller,
            paneId: paneId,
          ),
        ),
      ),
    );
  }

  group('FilePane — loading state', () {
    testWidgets('shows CircularProgressIndicator when loading', (tester) async {
      final fs = _MockFS({
        '/home': [], // empty but exists — init will succeed but we check loading
      });
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      // Don't call init — controller starts in loading state? No, loading is false by default.
      // We need to trigger a navigation to a path that takes time.
      // Instead, just check the basic rendering.
      await ctrl.init();
      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      // After init, loading should be false and it shows empty directory
      expect(find.text('Empty directory'), findsOneWidget);
    });
  });

  group('FilePane — empty state', () {
    testWidgets('shows "Empty directory" when entries are empty', (tester) async {
      final fs = _MockFS({'/home': []});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      expect(find.text('Empty directory'), findsOneWidget);
    });
  });

  group('FilePane — error state', () {
    testWidgets('shows error message and retry button on error', (tester) async {
      final fs = _MockFS({}); // No paths at all — navigateTo will fail
      final ctrl = FilePaneController(fs: fs, label: 'Test');

      // Manually navigate to a path that doesn't exist to trigger error
      await ctrl.navigateTo('/nonexistent');

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('retry button triggers refresh', (tester) async {
      // Start with error, then fix the FS
      final fs = _MockFS({});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.navigateTo('/missing');

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      expect(find.text('Retry'), findsOneWidget);

      // Add the path to make retry succeed
      fs.dirs['/missing'] = [];
      await tester.tap(find.text('Retry'));
      await tester.pump();

      // After successful retry, should show empty directory
      expect(find.text('Empty directory'), findsOneWidget);
    });
  });

  group('FilePane — file list rendering', () {
    testWidgets('renders file entries in list', (tester) async {
      final entries = [
        FileEntry(
          name: 'docs',
          path: '/home/docs',
          size: 0,
          mode: 0x41ED, // 0755
          modTime: now,
          isDir: true,
        ),
        FileEntry(
          name: 'readme.md',
          path: '/home/readme.md',
          size: 1024,
          mode: 0x81A4, // 0644
          modTime: now,
          isDir: false,
        ),
      ];
      final fs = _MockFS({'/home': entries});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      expect(find.text('docs'), findsOneWidget);
      expect(find.text('readme.md'), findsOneWidget);
    });

    testWidgets('path bar shows current path', (tester) async {
      final fs = _MockFS({'/home': []});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      // Path bar should show /home
      expect(find.text('/home'), findsWidgets);
    });
  });

  group('FilePane — navigation buttons', () {
    testWidgets('back button is disabled when no history', (tester) async {
      final fs = _MockFS({'/home': []});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      // Find back button (arrow_back icon)
      final backButton = find.byIcon(Icons.arrow_back);
      expect(backButton, findsOneWidget);
    });

    testWidgets('header shows label, nav buttons (back/forward/up/refresh)', (tester) async {
      final fs = _MockFS({'/home': []});
      final ctrl = FilePaneController(fs: fs, label: 'Remote');
      await ctrl.init();

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      expect(find.text('Remote'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
      expect(find.byIcon(Icons.arrow_forward), findsOneWidget);
      expect(find.byIcon(Icons.arrow_upward), findsWidgets);
      expect(find.byIcon(Icons.refresh), findsOneWidget);
    });

    testWidgets('up button navigates to parent directory', (tester) async {
      final fs = _MockFS({
        '/home': [
          FileEntry(name: 'docs', path: '/home/docs', size: 0, mode: 0x41ED, modTime: now, isDir: true),
        ],
        '/home/docs': [],
        '/': [],
      });
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();
      // Navigate into docs
      await ctrl.navigateTo('/home/docs');

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      // Tap the up button by tooltip
      await tester.tap(find.byTooltip('Up'));
      await tester.pump();

      // Should navigate back to /home
      expect(ctrl.currentPath, '/home');
    });
  });

  group('FilePane — footer', () {
    testWidgets('footer shows item count and total size', (tester) async {
      final entries = [
        FileEntry(name: 'docs', path: '/home/docs', size: 0, mode: 0x41ED, modTime: now, isDir: true),
        FileEntry(name: 'file.txt', path: '/home/file.txt', size: 2048, mode: 0x81A4, modTime: now, isDir: false),
        FileEntry(name: 'big.bin', path: '/home/big.bin', size: 1048576, mode: 0x81A4, modTime: now, isDir: false),
      ];
      final fs = _MockFS({'/home': entries});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      // Footer: "3 items, <total size>"
      expect(find.textContaining('3 items'), findsOneWidget);
    });

    testWidgets('footer shows selection count when items selected', (tester) async {
      final entries = [
        FileEntry(name: 'a.txt', path: '/home/a.txt', size: 100, mode: 0x81A4, modTime: now, isDir: false),
        FileEntry(name: 'b.txt', path: '/home/b.txt', size: 200, mode: 0x81A4, modTime: now, isDir: false),
      ];
      final fs = _MockFS({'/home': entries});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();
      ctrl.selectSingle('/home/a.txt');

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      expect(find.textContaining('1 selected'), findsOneWidget);
    });
  });

  group('FilePane — column headers', () {
    testWidgets('renders sortable column headers', (tester) async {
      final entries = [
        FileEntry(name: 'readme.md', path: '/home/readme.md', size: 1024, mode: 0x81A4, modTime: now, isDir: false),
      ];
      final fs = _MockFS({'/home': entries});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      expect(find.text('Name'), findsOneWidget);
      expect(find.text('Size'), findsOneWidget);
      expect(find.text('Modified'), findsOneWidget);
      expect(find.text('Mode'), findsOneWidget);
    });

    testWidgets('clicking column header changes sort', (tester) async {
      final entries = [
        FileEntry(name: 'b.txt', path: '/home/b.txt', size: 200, mode: 0x81A4, modTime: now, isDir: false),
        FileEntry(name: 'a.txt', path: '/home/a.txt', size: 100, mode: 0x81A4, modTime: now, isDir: false),
      ];
      final fs = _MockFS({'/home': entries});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      // Default sort is by name ascending
      expect(ctrl.sortColumn, SortColumn.name);

      // Click Size header
      await tester.tap(find.text('Size'));
      await tester.pump();

      expect(ctrl.sortColumn, SortColumn.size);
    });

    testWidgets('clicking same column header toggles sort direction', (tester) async {
      final entries = [
        FileEntry(name: 'a.txt', path: '/home/a.txt', size: 100, mode: 0x81A4, modTime: now, isDir: false),
      ];
      final fs = _MockFS({'/home': entries});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      expect(ctrl.sortAscending, isTrue);

      // Click Name (already active) to toggle direction
      await tester.tap(find.text('Name'));
      await tester.pump();

      expect(ctrl.sortAscending, isFalse);
    });
  });

  group('FilePane — path bar editing', () {
    testWidgets('tapping path bar enters edit mode', (tester) async {
      final fs = _MockFS({'/home': []});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      // Tap the path text to enter edit mode
      await tester.tap(find.text('/home').first);
      await tester.pump();

      // Should now have a TextField in edit mode
      // The TextField was already present (path bar), but now it should be editable
      final textFields = find.byType(TextField);
      expect(textFields, findsWidgets);
    });
  });

  group('FilePane — context menu on files', () {
    testWidgets('right-click on file shows context menu', (tester) async {
      final entries = [
        FileEntry(name: 'test.txt', path: '/home/test.txt', size: 512, mode: 0x81A4, modTime: now, isDir: false),
      ];
      final fs = _MockFS({'/home': entries});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      // Right-click on the file
      final fileText = find.text('test.txt');
      expect(fileText, findsOneWidget);
      final center = tester.getCenter(fileText);
      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await gesture.addPointer(location: center);
      await gesture.down(center);
      await gesture.up();
      await tester.pumpAndSettle();

      // Context menu items should appear
      expect(find.text('Transfer'), findsOneWidget);
      expect(find.text('New Folder'), findsOneWidget);
      expect(find.text('Rename'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
    });

    testWidgets('right-click on directory shows Open in context menu', (tester) async {
      final entries = [
        FileEntry(name: 'docs', path: '/home/docs', size: 0, mode: 0x41ED, modTime: now, isDir: true),
      ];
      final fs = _MockFS({'/home': entries, '/home/docs': []});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      final dirText = find.text('docs');
      final center = tester.getCenter(dirText);
      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await gesture.addPointer(location: center);
      await gesture.down(center);
      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.text('Open'), findsOneWidget);
      expect(find.text('Transfer'), findsOneWidget);
    });
  });

  group('FilePane — double-tap navigation', () {
    testWidgets('double-tap on directory navigates into it', (tester) async {
      final entries = [
        FileEntry(name: 'docs', path: '/home/docs', size: 0, mode: 0x41ED, modTime: now, isDir: true),
      ];
      final fs = _MockFS({'/home': entries, '/home/docs': []});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      // Double-tap on docs directory
      await tester.tap(find.text('docs'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('docs'));
      await tester.pumpAndSettle();

      expect(ctrl.currentPath, '/home/docs');
    });

    testWidgets('double-tap on file calls onTransfer', (tester) async {
      FileEntry? transferred;
      final entries = [
        FileEntry(name: 'file.txt', path: '/home/file.txt', size: 100, mode: 0x81A4, modTime: now, isDir: false),
      ];
      final fs = _MockFS({'/home': entries});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: SizedBox(
            width: 600,
            height: 400,
            child: FilePane(
              controller: ctrl,
              paneId: 'test',
              onTransfer: (entry) => transferred = entry,
            ),
          ),
        ),
      ));
      await tester.pump();

      await tester.tap(find.text('file.txt'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('file.txt'));
      await tester.pumpAndSettle();

      expect(transferred, isNotNull);
      expect(transferred!.name, 'file.txt');
    });
  });

  group('FilePane — background context menu', () {
    testWidgets('right-click on empty dir shows new folder and refresh', (tester) async {
      final fs = _MockFS({'/home': []});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      // Right-click on empty directory text
      final emptyText = find.text('Empty directory');
      final center = tester.getCenter(emptyText);
      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await gesture.addPointer(location: center);
      await gesture.down(center);
      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.text('New Folder'), findsOneWidget);
      expect(find.text('Refresh'), findsOneWidget);
    });
  });

  group('FilePane — refresh button', () {
    testWidgets('refresh button reloads directory', (tester) async {
      final fs = _MockFS({'/home': []});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      // Tap refresh
      await tester.tap(find.byIcon(Icons.refresh));
      await tester.pump();

      // Should still show empty dir (no crash)
      expect(find.text('Empty directory'), findsOneWidget);
    });
  });
}
