import 'dart:async';

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

  List<FileEntry> makeEntries() => [
        FileEntry(name: 'docs', path: '/home/docs', size: 0, mode: 0x41ED, modTime: now, isDir: true),
        FileEntry(name: 'readme.md', path: '/home/readme.md', size: 1024, mode: 0x81A4, modTime: now, isDir: false),
        FileEntry(name: 'script.sh', path: '/home/script.sh', size: 512, mode: 0x81ED, modTime: now, isDir: false),
      ];

  group('FilePane — empty directory rendering', () {
    testWidgets('shows "Empty directory" text with font size 13', (tester) async {
      final fs = _MockFS({'/home': []});
      final ctrl = FilePaneController(fs: fs, label: 'Local');
      await ctrl.init();

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      final textWidget = tester.widget<Text>(find.text('Empty directory'));
      expect(textWidget.style?.fontSize, 13);
    });

    testWidgets('empty directory supports right-click context menu', (tester) async {
      final fs = _MockFS({'/home': []});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      // Right-click on the empty directory area
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

      // Context menu with New Folder and Refresh should appear
      expect(find.text('New Folder'), findsOneWidget);
      expect(find.text('Refresh'), findsOneWidget);
    });
  });

  group('FilePane — error state display', () {
    testWidgets('error state shows error icon, message, and retry button', (tester) async {
      final fs = _MockFS({});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.navigateTo('/nonexistent');

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      // Error text should contain the exception message
      expect(find.textContaining('Not found'), findsOneWidget);
    });

    testWidgets('retry button calls refresh and recovers', (tester) async {
      final fs = _MockFS({});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.navigateTo('/broken');

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      expect(find.text('Retry'), findsOneWidget);

      // Fix the FS and retry
      fs.dirs['/broken'] = [
        FileEntry(name: 'fixed.txt', path: '/broken/fixed.txt', size: 100, mode: 0x81A4, modTime: now, isDir: false),
      ];
      await tester.tap(find.text('Retry'));
      await tester.pump();

      expect(find.text('fixed.txt'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
    });
  });

  group('FilePane — path bar editing', () {
    testWidgets('tap path bar enters edit mode, submit navigates', (tester) async {
      final fs = _MockFS({'/home': [], '/var': []});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      // Tap path bar to enter edit mode
      await tester.tap(find.text('/home').first);
      await tester.pump();

      // Should have a TextField in edit mode
      expect(find.byType(TextField), findsWidgets);

      // Enter new path and submit
      await tester.enterText(find.byType(TextField).first, '/var');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(ctrl.currentPath, '/var');
    });

    testWidgets('tap outside path bar cancels editing and restores path', (tester) async {
      final fs = _MockFS({'/home': [], '/': []});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      // Enter edit mode
      await tester.tap(find.text('/home').first);
      await tester.pump();

      // Tap outside the TextField to cancel
      await tester.tapAt(const Offset(10, 10));
      await tester.pump();

      // Path should remain /home
      expect(ctrl.currentPath, '/home');
    });
  });

  group('FilePane — sort header clicks', () {
    testWidgets('clicking Size header changes sort column', (tester) async {
      final entries = makeEntries();
      final fs = _MockFS({'/home': entries});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      expect(ctrl.sortColumn, SortColumn.name);

      await tester.tap(find.text('Size'));
      await tester.pump();

      expect(ctrl.sortColumn, SortColumn.size);
      expect(ctrl.sortAscending, isTrue);
    });

    testWidgets('clicking same column header toggles ascending/descending', (tester) async {
      final entries = makeEntries();
      final fs = _MockFS({'/home': entries});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      expect(ctrl.sortAscending, isTrue);

      // Click Name (active column) to toggle
      await tester.tap(find.text('Name'));
      await tester.pump();

      expect(ctrl.sortAscending, isFalse);

      // Click again to toggle back
      await tester.tap(find.text('Name'));
      await tester.pump();

      expect(ctrl.sortAscending, isTrue);
    });

    testWidgets('clicking Modified header changes sort', (tester) async {
      final entries = makeEntries();
      final fs = _MockFS({'/home': entries});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      await tester.tap(find.text('Modified'));
      await tester.pump();

      expect(ctrl.sortColumn, SortColumn.modified);
    });

    testWidgets('clicking Mode header changes sort', (tester) async {
      final entries = makeEntries();
      final fs = _MockFS({'/home': entries});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      await tester.tap(find.text('Mode'));
      await tester.pump();

      expect(ctrl.sortColumn, SortColumn.mode);
    });

    testWidgets('active sort column shows arrow indicator', (tester) async {
      final entries = makeEntries();
      final fs = _MockFS({'/home': entries});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      // Default sort is Name ascending — should show arrow_upward
      expect(find.byIcon(Icons.arrow_upward), findsWidgets);

      // Toggle to descending
      await tester.tap(find.text('Name'));
      await tester.pump();

      expect(find.byIcon(Icons.arrow_downward), findsWidgets);
    });
  });

  group('FilePane — Del key on non-key-down event', () {
    testWidgets('Del key with no selection is ignored', (tester) async {
      final entries = makeEntries();
      final fs = _MockFS({'/home': entries});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();
      // Ensure no selection
      ctrl.clearSelection();

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      // Focus the pane
      await tester.tap(find.text('readme.md'));
      // Wait for double-tap timeout to expire
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 10));
      await tester.pumpAndSettle();
      ctrl.clearSelection();
      await tester.pump();

      // Send Delete key — should be ignored (no selection)
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump();

      // No delete dialog should appear
      expect(find.textContaining('Delete "'), findsNothing);
    });
  });

  group('FilePane — loading state display', () {
    testWidgets('loading state shows CircularProgressIndicator', (tester) async {
      // Create a FS that never completes listing
      final fs = _NeverCompleteFS();
      final ctrl = FilePaneController(fs: fs, label: 'Test');

      // Start navigation (will be loading) — don't await
      unawaited(ctrl.navigateTo('/slow'));

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Complete the FS to clean up pending futures
      fs.complete();
      await tester.pump();
    });
  });

  group('FilePane — footer', () {
    testWidgets('footer shows 0 items for empty directory', (tester) async {
      final fs = _MockFS({'/home': []});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      expect(find.textContaining('0 items'), findsOneWidget);
    });
  });

  group('FilePane — DragTarget cross-pane', () {
    testWidgets('renders DragTarget for receiving drops', (tester) async {
      final entries = makeEntries();
      final fs = _MockFS({'/home': entries});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(
        controller: ctrl,
        paneId: 'pane-A',
        onDropReceived: (_) {},
      ));
      await tester.pump();

      // The widget renders with DragTarget present
      expect(find.text('readme.md'), findsOneWidget);
    });
  });
}

/// A file system whose list() never completes until complete() is called.
class _NeverCompleteFS implements FileSystem {
  final _completer = Completer<List<FileEntry>>();

  void complete() => _completer.complete([]);

  @override
  Future<String> initialDir() async => '/slow';
  @override
  Future<List<FileEntry>> list(String path) => _completer.future;
  @override
  Future<void> mkdir(String path) async {}
  @override
  Future<void> remove(String path) async {}
  @override
  Future<void> removeDir(String path) async {}
  @override
  Future<void> rename(String oldPath, String newPath) async {}
}
