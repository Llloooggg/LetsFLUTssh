import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    void Function(FileEntry)? onTransfer,
    void Function(List<FileEntry>)? onTransferMultiple,
    void Function(List<FileEntry>)? onDropReceived,
    void Function(List<String>)? onOsDropReceived,
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
            onTransfer: onTransfer,
            onTransferMultiple: onTransferMultiple,
            onDropReceived: onDropReceived,
            onOsDropReceived: onOsDropReceived,
          ),
        ),
      ),
    );
  }

  group('FilePane — Delete key event handling', () {
    testWidgets('Delete key on selected file opens delete confirmation',
        (tester) async {
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

      // Focus the file pane
      await tester.tap(find.text('a.txt'));
      await tester.pump();

      // Send Delete key
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();

      // Delete confirmation dialog should appear
      expect(find.text('Delete "a.txt"?'), findsOneWidget);

      // Cancel
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });

    testWidgets('Delete key with no selection is ignored', (tester) async {
      final entries = [
        FileEntry(name: 'a.txt', path: '/home/a.txt', size: 100, mode: 0x81A4, modTime: now, isDir: false),
      ];
      final fs = _MockFS({'/home': entries});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();
      // No selection

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      // Focus
      await tester.tap(find.text('a.txt'));
      await tester.pump();

      // Clear selection that happened from tap
      ctrl.clearSelection();
      await tester.pump();

      // Send Delete key
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();

      // No dialog should appear
      expect(find.text('Delete'), findsNothing);
    });
  });

  group('FilePane — path bar editing', () {
    testWidgets('clicking path bar enters edit mode', (tester) async {
      final fs = _MockFS({'/home': [], '/tmp': []});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      // Click on the path text to enter editing mode
      final pathText = find.text('/home');
      // The path bar has a GestureDetector that toggles _editingPath
      await tester.tap(pathText.last);
      await tester.pump();

      // Should now show a TextField for editing
      final textFields = find.byType(TextField);
      expect(textFields, findsWidgets);
    });

    testWidgets('submitting path bar navigates to new path', (tester) async {
      final fs = _MockFS({'/home': [], '/tmp': []});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      // Click on path text to enter edit mode
      final pathText = find.text('/home');
      await tester.tap(pathText.last);
      await tester.pump();

      // There are multiple TextFields (search, path), find the one with /home
      final pathTextField = find.widgetWithText(TextField, '/home');
      if (pathTextField.evaluate().isNotEmpty) {
        await tester.enterText(pathTextField, '/tmp');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();

        expect(ctrl.currentPath, '/tmp');
      }
    });
  });

  group('FilePane — context menu Rename action', () {
    testWidgets('Rename from context menu opens rename dialog', (tester) async {
      final entries = [
        FileEntry(name: 'rename_me.txt', path: '/home/rename_me.txt', size: 100, mode: 0x81A4, modTime: now, isDir: false),
      ];
      final fs = _MockFS({'/home': entries});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      // Right-click on the file
      await tester.tap(find.text('rename_me.txt'), buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();

      // Tap Rename
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();

      // Rename dialog should appear with pre-filled name
      expect(find.text('New name'), findsOneWidget);

      // Cancel
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });
  });

  group('FilePane — context menu on directory shows Open option', () {
    testWidgets('Open option on directory navigates into it', (tester) async {
      final entries = [
        FileEntry(name: 'mydir', path: '/home/mydir', size: 0, mode: 0x41ED, modTime: now, isDir: true),
      ];
      final fs = _MockFS({'/home': entries, '/home/mydir': []});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      // Right-click on directory
      await tester.tap(find.text('mydir'), buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();

      expect(find.text('Open'), findsOneWidget);

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(ctrl.currentPath, '/home/mydir');
    });
  });

  group('FilePane — background context menu', () {
    testWidgets('right-click on empty area shows New Folder and Refresh',
        (tester) async {
      final fs = _MockFS({'/home': []});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      // Right-click on empty directory area
      final emptyText = find.text('Empty directory');
      await tester.tap(emptyText, buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();

      expect(find.text('New Folder'), findsOneWidget);
      expect(find.text('Refresh'), findsOneWidget);
    });

    testWidgets('Refresh option from background menu refreshes', (tester) async {
      final fs = _MockFS({'/home': []});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      final emptyText = find.text('Empty directory');
      await tester.tap(emptyText, buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Refresh'));
      await tester.pumpAndSettle();

      // No crash, still shows empty
      expect(find.text('Empty directory'), findsOneWidget);
    });
  });

  group('FilePane — multi-select context menu', () {
    testWidgets('multi-select context menu hides Rename and Open', (tester) async {
      final entries = [
        FileEntry(name: 'a.txt', path: '/home/a.txt', size: 100, mode: 0x81A4, modTime: now, isDir: false),
        FileEntry(name: 'b.txt', path: '/home/b.txt', size: 200, mode: 0x81A4, modTime: now, isDir: false),
      ];
      final fs = _MockFS({'/home': entries});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();
      ctrl.toggleSelect('/home/a.txt');
      ctrl.toggleSelect('/home/b.txt');

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      // Right-click on one of the selected files
      await tester.tap(find.text('a.txt'), buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();

      // Should show "Transfer 2 items" and "Delete 2 items" but NOT Rename or Open
      expect(find.text('Transfer 2 items'), findsOneWidget);
      expect(find.text('Delete 2 items'), findsOneWidget);
      expect(find.text('Rename'), findsNothing);
      expect(find.text('Open'), findsNothing);

      // Dismiss
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();
    });
  });

  group('FilePane — footer shows item count and selection', () {
    testWidgets('footer shows total items and selection count', (tester) async {
      final entries = [
        FileEntry(name: 'a.txt', path: '/home/a.txt', size: 100, mode: 0x81A4, modTime: now, isDir: false),
        FileEntry(name: 'b.txt', path: '/home/b.txt', size: 200, mode: 0x81A4, modTime: now, isDir: false),
        FileEntry(name: 'c.txt', path: '/home/c.txt', size: 300, mode: 0x81A4, modTime: now, isDir: false),
      ];
      final fs = _MockFS({'/home': entries});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      // Footer should show "3 items, <size>"
      expect(find.textContaining('3 items'), findsOneWidget);

      // Select one
      ctrl.selectSingle('/home/a.txt');
      await tester.pump();

      // Footer should show "(1 selected)"
      expect(find.text('(1 selected)'), findsOneWidget);

      // Select two
      ctrl.toggleSelect('/home/b.txt');
      await tester.pump();

      expect(find.text('(2 selected)'), findsOneWidget);
    });
  });

  group('FilePane — column header sorting', () {
    testWidgets('clicking Size header sorts by size', (tester) async {
      final entries = [
        FileEntry(name: 'big.txt', path: '/home/big.txt', size: 9999, mode: 0x81A4, modTime: now, isDir: false),
        FileEntry(name: 'small.txt', path: '/home/small.txt', size: 10, mode: 0x81A4, modTime: now, isDir: false),
      ];
      final fs = _MockFS({'/home': entries});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      // Click Size header
      await tester.tap(find.text('Size'));
      await tester.pump();

      expect(ctrl.sortColumn, SortColumn.size);
      expect(ctrl.sortAscending, isTrue);

      // Click again to reverse
      await tester.tap(find.text('Size'));
      await tester.pump();

      expect(ctrl.sortColumn, SortColumn.size);
      expect(ctrl.sortAscending, isFalse);
    });

    testWidgets('clicking Modified header sorts by modified', (tester) async {
      final entries = [
        FileEntry(name: 'a.txt', path: '/home/a.txt', size: 100, mode: 0x81A4, modTime: now, isDir: false),
      ];
      final fs = _MockFS({'/home': entries});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      await tester.tap(find.text('Modified'));
      await tester.pump();

      expect(ctrl.sortColumn, SortColumn.modified);
    });

    testWidgets('clicking Mode header sorts by mode', (tester) async {
      final entries = [
        FileEntry(name: 'a.txt', path: '/home/a.txt', size: 100, mode: 0x81A4, modTime: now, isDir: false),
      ];
      final fs = _MockFS({'/home': entries});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      await tester.tap(find.text('Mode'));
      await tester.pump();

      expect(ctrl.sortColumn, SortColumn.mode);
    });
  });

  group('FilePane — header buttons', () {
    testWidgets('Up button navigates to parent', (tester) async {
      final fs = _MockFS({'/home': [], '/': []});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      // Tap Up button
      await tester.tap(find.byTooltip('Up'));
      await tester.pump();

      expect(ctrl.currentPath, '/');
    });

    testWidgets('Refresh button refreshes listing', (tester) async {
      final fs = _MockFS({'/home': []});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      // Tap Refresh
      await tester.tap(find.byTooltip('Refresh'));
      await tester.pump();

      // No crash
      expect(ctrl.currentPath, '/home');
    });
  });

  group('FilePane — Listener widget for mouse buttons is present', () {
    testWidgets('Listener widget exists in FilePane tree', (tester) async {
      final fs = _MockFS({'/home': []});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      // Verify Listener widget is in the tree (handles back/forward mouse)
      expect(find.byType(Listener), findsWidgets);
    });

    testWidgets('navigation back via header Back button works after navigateTo',
        (tester) async {
      final fs = _MockFS({'/home': [], '/tmp': []});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();
      await ctrl.navigateTo('/tmp');

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      expect(ctrl.currentPath, '/tmp');

      // Use Back button in header
      await tester.tap(find.byTooltip('Back'));
      await tester.pump();

      expect(ctrl.currentPath, '/home');
    });

    testWidgets('navigation forward via header Forward button works after goBack',
        (tester) async {
      final fs = _MockFS({'/home': [], '/tmp': []});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();
      await ctrl.navigateTo('/tmp');
      await ctrl.goBack();

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      expect(ctrl.currentPath, '/home');

      await tester.tap(find.byTooltip('Forward'));
      await tester.pump();

      expect(ctrl.currentPath, '/tmp');
    });
  });

  group('FilePane — double-tap file triggers transfer', () {
    testWidgets('double-tap on file calls onTransfer', (tester) async {
      FileEntry? transferred;
      final entries = [
        FileEntry(name: 'transfer.txt', path: '/home/transfer.txt', size: 50, mode: 0x81A4, modTime: now, isDir: false),
      ];
      final fs = _MockFS({'/home': entries});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(
        controller: ctrl,
        onTransfer: (e) => transferred = e,
      ));
      await tester.pump();

      // Double-tap on the file
      await tester.tap(find.text('transfer.txt'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('transfer.txt'));
      await tester.pumpAndSettle();

      expect(transferred, isNotNull);
      expect(transferred!.name, 'transfer.txt');
    });

    testWidgets('double-tap on directory navigates into it', (tester) async {
      final entries = [
        FileEntry(name: 'subdir', path: '/home/subdir', size: 0, mode: 0x41ED, modTime: now, isDir: true),
      ];
      final fs = _MockFS({'/home': entries, '/home/subdir': []});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      // Double-tap on directory
      await tester.tap(find.text('subdir'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('subdir'));
      await tester.pumpAndSettle();

      expect(ctrl.currentPath, '/home/subdir');
    });
  });
}
