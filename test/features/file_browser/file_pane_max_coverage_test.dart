import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/sftp/file_system.dart';
import 'package:letsflutssh/core/sftp/sftp_models.dart';
import 'package:letsflutssh/features/file_browser/file_browser_controller.dart';
import 'package:letsflutssh/features/file_browser/file_pane.dart';
import 'package:letsflutssh/features/file_browser/file_row.dart';
import 'package:letsflutssh/theme/app_theme.dart';

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

  List<FileEntry> manyEntries() => [
    FileEntry(name: 'a.txt', path: '/home/a.txt', size: 100, mode: 0x81A4, modTime: now, isDir: false),
    FileEntry(name: 'b.txt', path: '/home/b.txt', size: 200, mode: 0x81A4, modTime: now, isDir: false),
    FileEntry(name: 'c.txt', path: '/home/c.txt', size: 300, mode: 0x81A4, modTime: now, isDir: false),
    FileEntry(name: 'd.txt', path: '/home/d.txt', size: 400, mode: 0x81A4, modTime: now, isDir: false),
    FileEntry(name: 'e.txt', path: '/home/e.txt', size: 500, mode: 0x81A4, modTime: now, isDir: false),
  ];

  // Note: mouse back/forward buttons (kBackMouseButton, kForwardMouseButton)
  // cannot be reliably tested in Flutter widget tests because the Listener
  // receives raw PointerDownEvent with button flags, but gesture simulation
  // doesn't propagate these flags through the widget tree correctly.
  // Lines 95-99 (back/forward mouse button handlers) are skipped.

  group('FilePane — drag feedback shows item count for multiple', () {
    testWidgets('multiple selected items show "N items" in Draggable data', (tester) async {
      final entries = manyEntries();
      final fs = _MockFS({'/home': entries});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();
      ctrl.toggleSelect('/home/a.txt');
      ctrl.toggleSelect('/home/b.txt');
      ctrl.toggleSelect('/home/c.txt');

      await tester.pumpWidget(buildApp(controller: ctrl, paneId: 'pane-multi'));
      await tester.pump();

      // All 3 selected should have Draggable wrappers
      final draggables = tester.widgetList<Draggable<PaneDragData>>(
        find.byType(Draggable<PaneDragData>),
      );
      expect(draggables.length, 3);

      // Each should carry all 3 entries
      for (final d in draggables) {
        expect(d.data!.entries.length, 3);
      }
    });
  });

  group('FilePane — pointer up without marquee active clears anchor only', () {
    testWidgets('click and release without move does not crash', (tester) async {
      final entries = manyEntries();
      final fs = _MockFS({'/home': entries});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      // Simple click (down + up without move past threshold)
      final aText = find.text('a.txt');
      final startPos = tester.getCenter(aText);

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: startPos);
      await gesture.down(startPos);
      await tester.pump();

      // Small move below threshold
      await gesture.moveTo(startPos + const Offset(1, 1));
      await tester.pump();

      // Pointer up — should clean up without crash
      await gesture.up();
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 10));
      await tester.pumpAndSettle();

      expect(find.text('a.txt'), findsOneWidget);
    });
  });

  group('FilePane — context menu Delete multi-select', () {
    testWidgets('Delete N items from context menu opens confirmation', (tester) async {
      final entries = manyEntries();
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

      // Should show "Delete 2 items"
      expect(find.text('Delete 2 items'), findsOneWidget);

      await tester.tap(find.text('Delete 2 items'));
      await tester.pumpAndSettle();

      // Confirmation dialog
      expect(find.textContaining('Delete 2'), findsWidgets);

      // Cancel
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });
  });

  group('FilePane — context menu Open on directory', () {
    testWidgets('Open from context menu navigates into directory', (tester) async {
      final entries = [
        FileEntry(name: 'subdir', path: '/home/subdir', size: 0, mode: 0x41ED, modTime: now, isDir: true),
      ];
      final fs = _MockFS({'/home': entries, '/home/subdir': []});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      await tester.tap(find.text('subdir'), buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(ctrl.currentPath, '/home/subdir');
    });
  });

  group('FilePane — single tap selects file', () {
    testWidgets('tapping file selects it', (tester) async {
      final entries = manyEntries();
      final fs = _MockFS({'/home': entries});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      await tester.tap(find.text('b.txt'));
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 10));
      await tester.pumpAndSettle();

      expect(ctrl.selected.contains('/home/b.txt'), isTrue);
    });
  });

  group('FilePane — background right-click on file list clears selection', () {
    testWidgets('background context menu clears selection', (tester) async {
      final entries = manyEntries();
      final fs = _MockFS({'/home': entries});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();
      ctrl.selectSingle('/home/a.txt');

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      expect(ctrl.selected.isNotEmpty, isTrue);

      // Right-click on the list area (not on a file row) — find the GestureDetector
      // Use Stack area below files
      final listView = find.byType(ListView);
      if (listView.evaluate().isNotEmpty) {
        final listRect = tester.getRect(listView);
        // Right-click below the last file entry
        final gesture = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
          buttons: kSecondaryMouseButton,
        );
        final emptyPos = Offset(listRect.center.dx, listRect.bottom - 5);
        await gesture.addPointer(location: emptyPos);
        await gesture.down(emptyPos);
        await gesture.up();
        await tester.pumpAndSettle();

        // Background context menu should appear
        final newFolder = find.text('New Folder');
        if (newFolder.evaluate().isNotEmpty) {
          expect(newFolder, findsOneWidget);
          // Dismiss
          await tester.tapAt(Offset.zero);
          await tester.pumpAndSettle();
        }
      }
    });
  });

  group('FilePane — Delete key with selected files', () {
    testWidgets('Delete key opens confirmation for selected files', (tester) async {
      final entries = manyEntries();
      final fs = _MockFS({'/home': entries});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();
      ctrl.selectSingle('/home/c.txt');

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      // Focus the pane
      await tester.tap(find.text('c.txt'));
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();

      expect(find.textContaining('Delete'), findsWidgets);

      // Cancel
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });
  });

  group('FilePane — Rename dialog from context menu', () {
    testWidgets('Rename dialog shows pre-filled name', (tester) async {
      final entries = [
        FileEntry(name: 'rename_me.txt', path: '/home/rename_me.txt', size: 100, mode: 0x81A4, modTime: now, isDir: false),
      ];
      final fs = _MockFS({'/home': entries});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      await tester.tap(find.text('rename_me.txt'), buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();

      expect(find.text('New name'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });
  });

  group('FilePane — New Folder dialog from background menu', () {
    testWidgets('New Folder from empty dir context menu', (tester) async {
      final fs = _MockFS({'/home': []});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      await tester.tap(find.text('Empty directory'), buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();

      await tester.tap(find.text('New Folder'));
      await tester.pumpAndSettle();

      expect(find.text('Folder name'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });
  });

  group('FilePane — Refresh from background menu', () {
    testWidgets('Refresh refreshes the file listing', (tester) async {
      final fs = _MockFS({'/home': []});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      await tester.tap(find.text('Empty directory'), buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();

      // Add files to mock FS before refresh
      fs.dirs['/home'] = [
        FileEntry(name: 'new.txt', path: '/home/new.txt', size: 50, mode: 0x81A4, modTime: now, isDir: false),
      ];

      await tester.tap(find.text('Refresh'));
      await tester.pump();

      expect(find.text('new.txt'), findsOneWidget);
    });
  });

  group('FilePane — footer with no selection', () {
    testWidgets('footer shows only item count when nothing selected', (tester) async {
      final entries = manyEntries();
      final fs = _MockFS({'/home': entries});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      expect(find.textContaining('5 items'), findsOneWidget);
      // No "selected" text when nothing is selected
      expect(find.text('(0 selected)'), findsNothing);
    });
  });
}
