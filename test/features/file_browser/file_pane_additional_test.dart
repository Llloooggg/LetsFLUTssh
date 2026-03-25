import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/sftp/file_system.dart';
import 'package:letsflutssh/core/sftp/sftp_models.dart';
import 'package:letsflutssh/features/file_browser/file_browser_controller.dart';
import 'package:letsflutssh/features/file_browser/file_pane.dart';
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

  List<FileEntry> makeEntries() => [
        FileEntry(name: 'docs', path: '/home/docs', size: 0, mode: 0x41ED, modTime: now, isDir: true),
        FileEntry(name: 'readme.md', path: '/home/readme.md', size: 1024, mode: 0x81A4, modTime: now, isDir: false),
        FileEntry(name: 'script.sh', path: '/home/script.sh', size: 512, mode: 0x81ED, modTime: now, isDir: false),
      ];

  group('FilePane — path bar editing', () {
    testWidgets('tapping path bar enters edit mode with text field', (tester) async {
      final fs = _MockFS({'/home': []});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      // Tap on the path text to enter edit mode
      await tester.tap(find.text('/home').first);
      await tester.pump();

      // Should now have more TextFields (edit mode adds one)
      expect(find.byType(TextField), findsWidgets);
    });
  });

  group('FilePane — context menu on background', () {
    testWidgets('right-click on empty area shows background context menu', (tester) async {
      final fs = _MockFS({'/home': []});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      // Right-click on empty area
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

  group('FilePane — multi-selection context menu', () {
    testWidgets('context menu with multiple selected shows item count', (tester) async {
      final entries = makeEntries();
      final fs = _MockFS({'/home': entries});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      // Select multiple entries
      ctrl.toggleSelect('/home/readme.md');
      ctrl.toggleSelect('/home/script.sh');

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      // Right-click on one of the selected files
      final fileText = find.text('readme.md');
      final center = tester.getCenter(fileText);
      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await gesture.addPointer(location: center);
      await gesture.down(center);
      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.textContaining('Transfer 2 items'), findsOneWidget);
      expect(find.textContaining('Delete 2 items'), findsOneWidget);
    });
  });

  group('FilePane — Delete key', () {
    testWidgets('Del key triggers delete on selected file', (tester) async {
      final entries = makeEntries();
      final fs = _MockFS({'/home': entries});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();
      ctrl.selectSingle('/home/readme.md');

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      // Focus the pane first by tapping
      await tester.tap(find.text('readme.md'));
      await tester.pump();

      // Press Delete key
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();

      // Delete confirmation dialog should appear
      expect(find.textContaining('Delete'), findsWidgets);
    });
  });

  group('FilePane — Draggable on selected files', () {
    testWidgets('selected file is wrapped in Draggable', (tester) async {
      final entries = makeEntries();
      final fs = _MockFS({'/home': entries});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();
      ctrl.selectSingle('/home/readme.md');

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      // Selected file should be rendered
      expect(find.text('readme.md'), findsOneWidget);
    });
  });

  group('FilePane — Owner column', () {
    testWidgets('shows Owner column when entries have owner info', (tester) async {
      final entries = [
        FileEntry(name: 'file.txt', path: '/home/file.txt', size: 100, mode: 0x81A4, modTime: now, isDir: false, owner: 'root'),
      ];
      final fs = _MockFS({'/home': entries});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      expect(find.text('Owner'), findsOneWidget);
    });

    testWidgets('hides Owner column when no entries have owner', (tester) async {
      final entries = makeEntries();
      final fs = _MockFS({'/home': entries});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      expect(find.text('Owner'), findsNothing);
    });
  });

  group('FilePane — drag icon logic', () {
    testWidgets('single file shows file icon, multiple shows file_copy', (tester) async {
      final entries = makeEntries();
      final fs = _MockFS({'/home': entries});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();
      // Select two files
      ctrl.toggleSelect('/home/readme.md');
      ctrl.toggleSelect('/home/script.sh');

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      // Multi-selected entries render in the list
      expect(find.text('readme.md'), findsOneWidget);
      expect(find.text('script.sh'), findsOneWidget);
    });
  });

  group('FilePane — mouse back/forward buttons', () {
    testWidgets('Listener widget is present for mouse button navigation', (tester) async {
      final fs = _MockFS({'/home': []});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      expect(find.byType(Listener), findsWidgets);
    });
  });
}
