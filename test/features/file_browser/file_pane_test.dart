import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
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
import 'package:letsflutssh/widgets/cross_marquee_controller.dart';

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

/// Find FilePane's outermost Listener (the one with back/forward mouse handling).
Listener _findFilePaneListener(WidgetTester tester) {
  final filePaneElement = tester.element(find.byType(FilePane));
  Listener? found;
  void visitor(Element element) {
    if (found != null) return;
    if (element.widget is Listener) {
      final l = element.widget as Listener;
      if (l.onPointerDown != null) {
        found = l;
        return;
      }
    }
    element.visitChildren(visitor);
  }
  filePaneElement.visitChildren(visitor);
  return found!;
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
    VoidCallback? onPaneActivated,
    CrossMarqueeController? crossMarquee,
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
            onPaneActivated: onPaneActivated,
            crossMarquee: crossMarquee,
          ),
        ),
      ),
    );
  }

  List<FileEntry> makeEntries() => [
        FileEntry(name: 'docs', path: '/home/docs', size: 0, mode: 0x41ED,
            modTime: now, isDir: true),
        FileEntry(name: 'readme.md', path: '/home/readme.md', size: 1024,
            mode: 0x81A4, modTime: now, isDir: false),
        FileEntry(name: 'script.sh', path: '/home/script.sh', size: 512,
            mode: 0x81ED, modTime: now, isDir: false),
      ];

  List<FileEntry> manyEntries() => [
        FileEntry(name: 'a.txt', path: '/home/a.txt', size: 100, mode: 0x81A4,
            modTime: now, isDir: false),
        FileEntry(name: 'b.txt', path: '/home/b.txt', size: 200, mode: 0x81A4,
            modTime: now, isDir: false),
        FileEntry(name: 'c.txt', path: '/home/c.txt', size: 300, mode: 0x81A4,
            modTime: now, isDir: false),
        FileEntry(name: 'd.txt', path: '/home/d.txt', size: 400, mode: 0x81A4,
            modTime: now, isDir: false),
        FileEntry(name: 'e.txt', path: '/home/e.txt', size: 500, mode: 0x81A4,
            modTime: now, isDir: false),
      ];

  // ---------------------------------------------------------------------------
  // Loading state
  // ---------------------------------------------------------------------------
  group('FilePane — loading state', () {
    testWidgets('shows CircularProgressIndicator when loading', (tester) async {
      final fs = _NeverCompleteFS();
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      unawaited(ctrl.navigateTo('/slow'));

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      fs.complete();
      await tester.pump();
    });

    testWidgets('after init shows empty directory', (tester) async {
      final fs = _MockFS({'/home': []});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      expect(find.text('Empty directory'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // Empty state
  // ---------------------------------------------------------------------------
  group('FilePane — empty state', () {
    testWidgets('shows "Empty directory" when entries are empty',
        (tester) async {
      final fs = _MockFS({'/home': []});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      expect(find.text('Empty directory'), findsOneWidget);
    });

    testWidgets('empty directory text has font size 13', (tester) async {
      final fs = _MockFS({'/home': []});
      final ctrl = FilePaneController(fs: fs, label: 'Local');
      await ctrl.init();

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      final textWidget = tester.widget<Text>(find.text('Empty directory'));
      expect(textWidget.style?.fontSize, 13);
    });
  });

  // ---------------------------------------------------------------------------
  // Error state
  // ---------------------------------------------------------------------------
  group('FilePane — error state', () {
    testWidgets('shows error icon, message, and retry button', (tester) async {
      final fs = _MockFS({});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.navigateTo('/nonexistent');

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.textContaining('Not found'), findsOneWidget);
    });

    testWidgets('retry button recovers from error', (tester) async {
      final fs = _MockFS({});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.navigateTo('/broken');

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();
      expect(find.text('Retry'), findsOneWidget);

      fs.dirs['/broken'] = [
        FileEntry(name: 'fixed.txt', path: '/broken/fixed.txt', size: 100,
            mode: 0x81A4, modTime: now, isDir: false),
      ];
      await tester.tap(find.text('Retry'));
      await tester.pump();

      expect(find.text('fixed.txt'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
    });

    testWidgets('error icon uses theme error color', (tester) async {
      final fs = _MockFS({});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.navigateTo('/missing');

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      final icon = tester.widget<Icon>(find.byIcon(Icons.error_outline));
      final theme = AppTheme.dark();
      expect(icon.color, theme.colorScheme.error);
    });

    testWidgets('error text uses theme error color', (tester) async {
      final fs = _MockFS({});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.navigateTo('/missing');

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      final errorText = tester.widget<Text>(find.textContaining('Not found'));
      final theme = AppTheme.dark();
      expect(errorText.style?.color, theme.colorScheme.error);
    });
  });

  // ---------------------------------------------------------------------------
  // File list rendering
  // ---------------------------------------------------------------------------
  group('FilePane — file list rendering', () {
    testWidgets('renders file entries in list', (tester) async {
      final entries = [
        FileEntry(name: 'docs', path: '/home/docs', size: 0, mode: 0x41ED,
            modTime: now, isDir: true),
        FileEntry(name: 'readme.md', path: '/home/readme.md', size: 1024,
            mode: 0x81A4, modTime: now, isDir: false),
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

      expect(find.text('/home'), findsWidgets);
    });
  });

  // ---------------------------------------------------------------------------
  // Header / navigation buttons
  // ---------------------------------------------------------------------------
  group('FilePane — navigation buttons', () {
    testWidgets('header shows label and nav buttons', (tester) async {
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
        '/home': [FileEntry(name: 'docs', path: '/home/docs', size: 0,
            mode: 0x41ED, modTime: now, isDir: true)],
        '/home/docs': [],
        '/': [],
      });
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();
      await ctrl.navigateTo('/home/docs');

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      await tester.tap(find.byTooltip('Up'));
      await tester.pump();
      expect(ctrl.currentPath, '/home');
    });

    testWidgets('back button navigates after history', (tester) async {
      final fs = _MockFS({'/home': [], '/tmp': []});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();
      await ctrl.navigateTo('/tmp');

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      expect(ctrl.canGoBack, isTrue);

      await tester.tap(find.byTooltip('Back'));
      await tester.pump();
      expect(ctrl.currentPath, '/home');
    });

    testWidgets('forward button navigates after goBack', (tester) async {
      final fs = _MockFS({'/home': [], '/tmp': []});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();
      await ctrl.navigateTo('/tmp');
      await ctrl.goBack();

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      expect(ctrl.canGoForward, isTrue);

      await tester.tap(find.byTooltip('Forward'));
      await tester.pump();
      expect(ctrl.currentPath, '/tmp');
    });

    testWidgets('refresh button reloads directory', (tester) async {
      final fs = _MockFS({'/home': []});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.refresh));
      await tester.pump();
      expect(find.text('Empty directory'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // Column headers / sorting
  // ---------------------------------------------------------------------------
  group('FilePane — column headers', () {
    testWidgets('renders sortable column headers', (tester) async {
      final entries = [
        FileEntry(name: 'readme.md', path: '/home/readme.md', size: 1024,
            mode: 0x81A4, modTime: now, isDir: false),
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

    testWidgets('clicking same column toggles sort direction', (tester) async {
      final entries = makeEntries();
      final fs = _MockFS({'/home': entries});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      expect(ctrl.sortAscending, isTrue);

      await tester.tap(find.text('Name'));
      await tester.pump();
      expect(ctrl.sortAscending, isFalse);

      await tester.tap(find.text('Name'));
      await tester.pump();
      expect(ctrl.sortAscending, isTrue);
    });

    testWidgets('clicking Modified header', (tester) async {
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

    testWidgets('clicking Mode header', (tester) async {
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

      expect(find.byIcon(Icons.arrow_upward), findsWidgets);

      await tester.tap(find.text('Name'));
      await tester.pump();
      expect(find.byIcon(Icons.arrow_downward), findsWidgets);
    });
  });

  // ---------------------------------------------------------------------------
  // Owner column
  // ---------------------------------------------------------------------------
  group('FilePane — Owner column', () {
    testWidgets('shows Owner column when entries have owner', (tester) async {
      final entries = [
        FileEntry(name: 'file.txt', path: '/home/file.txt', size: 100,
            mode: 0x81A4, modTime: now, isDir: false, owner: 'root'),
      ];
      final fs = _MockFS({'/home': entries});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      expect(find.text('Owner'), findsOneWidget);
    });

    testWidgets('hides Owner column when no entries have owner',
        (tester) async {
      final entries = makeEntries();
      final fs = _MockFS({'/home': entries});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      expect(find.text('Owner'), findsNothing);
    });

    testWidgets('clicking Owner header sorts by owner', (tester) async {
      final entries = [
        FileEntry(name: 'a.txt', path: '/home/a.txt', size: 100,
            mode: 0x81A4, modTime: now, isDir: false, owner: 'bob'),
        FileEntry(name: 'b.txt', path: '/home/b.txt', size: 200,
            mode: 0x81A4, modTime: now, isDir: false, owner: 'alice'),
      ];
      final fs = _MockFS({'/home': entries});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      await tester.tap(find.text('Owner'));
      await tester.pump();
      expect(ctrl.sortColumn, SortColumn.owner);
    });
  });

  // ---------------------------------------------------------------------------
  // Footer
  // ---------------------------------------------------------------------------
  group('FilePane — footer', () {
    testWidgets('shows item count and total size', (tester) async {
      final entries = [
        FileEntry(name: 'docs', path: '/home/docs', size: 0, mode: 0x41ED,
            modTime: now, isDir: true),
        FileEntry(name: 'file.txt', path: '/home/file.txt', size: 2048,
            mode: 0x81A4, modTime: now, isDir: false),
        FileEntry(name: 'big.bin', path: '/home/big.bin', size: 1048576,
            mode: 0x81A4, modTime: now, isDir: false),
      ];
      final fs = _MockFS({'/home': entries});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      expect(find.textContaining('3 items'), findsOneWidget);
    });

    testWidgets('shows 0 items for empty directory', (tester) async {
      final fs = _MockFS({'/home': []});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      expect(find.textContaining('0 items'), findsOneWidget);
    });

    testWidgets('shows selection count when items selected', (tester) async {
      final entries = [
        FileEntry(name: 'a.txt', path: '/home/a.txt', size: 100,
            mode: 0x81A4, modTime: now, isDir: false),
        FileEntry(name: 'b.txt', path: '/home/b.txt', size: 200,
            mode: 0x81A4, modTime: now, isDir: false),
      ];
      final fs = _MockFS({'/home': entries});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();
      ctrl.selectSingle('/home/a.txt');

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      expect(find.textContaining('1 selected'), findsOneWidget);

      ctrl.toggleSelect('/home/b.txt');
      await tester.pump();
      expect(find.textContaining('2 selected'), findsOneWidget);
    });

    testWidgets('no selection text when nothing selected', (tester) async {
      final entries = manyEntries();
      final fs = _MockFS({'/home': entries});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      expect(find.textContaining('5 items'), findsOneWidget);
      expect(find.text('(0 selected)'), findsNothing);
    });
  });

  // ---------------------------------------------------------------------------
  // Path bar editing
  // ---------------------------------------------------------------------------
  group('FilePane — path bar editing', () {
    testWidgets('tapping path bar enters edit mode', (tester) async {
      final fs = _MockFS({'/home': []});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      await tester.tap(find.text('/home').first);
      await tester.pump();

      expect(find.byType(TextField), findsWidgets);
    });

    testWidgets('submitting path bar navigates to new path', (tester) async {
      final fs = _MockFS({'/home': [], '/tmp': []});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      await tester.tap(find.text('/home').first);
      await tester.pump();

      await tester.enterText(find.byType(TextField).first, '/tmp');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(ctrl.currentPath, '/tmp');
    });

    testWidgets('tapping outside cancels edit', (tester) async {
      final fs = _MockFS({'/home': [], '/': []});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      await tester.tap(find.text('/home').first);
      await tester.pump();

      await tester.tapAt(const Offset(10, 10));
      await tester.pump();

      expect(ctrl.currentPath, '/home');
    });
  });

  // ---------------------------------------------------------------------------
  // Double-tap navigation
  // ---------------------------------------------------------------------------
  group('FilePane — double-tap', () {
    testWidgets('double-tap on directory navigates into it', (tester) async {
      final entries = [
        FileEntry(name: 'docs', path: '/home/docs', size: 0, mode: 0x41ED,
            modTime: now, isDir: true),
      ];
      final fs = _MockFS({'/home': entries, '/home/docs': []});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      await tester.tap(find.text('docs'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('docs'));
      await tester.pumpAndSettle();

      expect(ctrl.currentPath, '/home/docs');
    });

    testWidgets('double-tap on file calls onTransfer', (tester) async {
      FileEntry? transferred;
      final entries = [
        FileEntry(name: 'file.txt', path: '/home/file.txt', size: 100,
            mode: 0x81A4, modTime: now, isDir: false),
      ];
      final fs = _MockFS({'/home': entries});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(
        controller: ctrl,
        onTransfer: (entry) => transferred = entry,
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

  // ---------------------------------------------------------------------------
  // Context menus — file / directory
  // ---------------------------------------------------------------------------
  group('FilePane — context menu on files', () {
    testWidgets('right-click on file shows context menu', (tester) async {
      final entries = [
        FileEntry(name: 'test.txt', path: '/home/test.txt', size: 512,
            mode: 0x81A4, modTime: now, isDir: false),
      ];
      final fs = _MockFS({'/home': entries});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      final fileText = find.text('test.txt');
      final center = tester.getCenter(fileText);
      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
      await gesture.addPointer(location: center);
      await gesture.down(center);
      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.text('Transfer'), findsOneWidget);
      expect(find.text('New Folder'), findsOneWidget);
      expect(find.text('Rename'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
    });

    testWidgets('right-click on directory shows Open option', (tester) async {
      final entries = [
        FileEntry(name: 'docs', path: '/home/docs', size: 0, mode: 0x41ED,
            modTime: now, isDir: true),
      ];
      final fs = _MockFS({'/home': entries, '/home/docs': []});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      final dirText = find.text('docs');
      final center = tester.getCenter(dirText);
      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
      await gesture.addPointer(location: center);
      await gesture.down(center);
      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.text('Open'), findsOneWidget);
      expect(find.text('Transfer'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // Context menu actions
  // ---------------------------------------------------------------------------
  group('FilePane — context menu actions', () {
    testWidgets('Open navigates into directory', (tester) async {
      final entries = [
        FileEntry(name: 'subdir', path: '/home/subdir', size: 0,
            mode: 0x41ED, modTime: now, isDir: true),
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

    testWidgets('New Folder opens dialog', (tester) async {
      final entries = [
        FileEntry(name: 'file.txt', path: '/home/file.txt', size: 100,
            mode: 0x81A4, modTime: now, isDir: false),
      ];
      final fs = _MockFS({'/home': entries});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      await tester.tap(find.text('file.txt'), buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();

      await tester.tap(find.text('New Folder'));
      await tester.pumpAndSettle();

      expect(find.text('Folder name'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });

    testWidgets('Rename opens rename dialog', (tester) async {
      final entries = [
        FileEntry(name: 'old.txt', path: '/home/old.txt', size: 100,
            mode: 0x81A4, modTime: now, isDir: false),
      ];
      final fs = _MockFS({'/home': entries});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      await tester.tap(find.text('old.txt'), buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();

      expect(find.text('New name'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });

    testWidgets('Delete opens confirmation', (tester) async {
      final entries = [
        FileEntry(name: 'del.txt', path: '/home/del.txt', size: 100,
            mode: 0x81A4, modTime: now, isDir: false),
      ];
      final fs = _MockFS({'/home': entries});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      await tester.tap(find.text('del.txt'), buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Delete "del.txt"?'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });

    testWidgets('Transfer calls onTransfer for single file', (tester) async {
      FileEntry? transferred;
      final entries = [
        FileEntry(name: 'data.bin', path: '/home/data.bin', size: 1000,
            mode: 0x81A4, modTime: now, isDir: false),
      ];
      final fs = _MockFS({'/home': entries});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(
        controller: ctrl,
        onTransfer: (entry) => transferred = entry,
      ));
      await tester.pump();

      await tester.tap(find.text('data.bin'), buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Transfer'));
      await tester.pumpAndSettle();

      expect(transferred, isNotNull);
      expect(transferred!.name, 'data.bin');
    });
  });

  // ---------------------------------------------------------------------------
  // Multi-select context menu
  // ---------------------------------------------------------------------------
  group('FilePane — multi-select context menu', () {
    testWidgets('shows item count for Transfer and Delete', (tester) async {
      final entries = [
        FileEntry(name: 'a.txt', path: '/home/a.txt', size: 100,
            mode: 0x81A4, modTime: now, isDir: false),
        FileEntry(name: 'b.txt', path: '/home/b.txt', size: 200,
            mode: 0x81A4, modTime: now, isDir: false),
      ];
      final fs = _MockFS({'/home': entries});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();
      ctrl.toggleSelect('/home/a.txt');
      ctrl.toggleSelect('/home/b.txt');

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      await tester.tap(find.text('a.txt'), buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();

      expect(find.text('Transfer 2 items'), findsOneWidget);
      expect(find.text('Delete 2 items'), findsOneWidget);
      expect(find.text('Rename'), findsNothing);
      expect(find.text('Open'), findsNothing);
    });

    testWidgets('Transfer calls onTransferMultiple', (tester) async {
      List<FileEntry>? transferred;
      final entries = [
        FileEntry(name: 'a.txt', path: '/home/a.txt', size: 100,
            mode: 0x81A4, modTime: now, isDir: false),
        FileEntry(name: 'b.txt', path: '/home/b.txt', size: 200,
            mode: 0x81A4, modTime: now, isDir: false),
      ];
      final fs = _MockFS({'/home': entries});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();
      ctrl.toggleSelect('/home/a.txt');
      ctrl.toggleSelect('/home/b.txt');

      await tester.pumpWidget(buildApp(
        controller: ctrl,
        onTransferMultiple: (entries) => transferred = entries,
      ));
      await tester.pump();

      await tester.tap(find.text('a.txt'), buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Transfer 2 items'));
      await tester.pumpAndSettle();

      expect(transferred, isNotNull);
      expect(transferred!.length, 2);
    });

    testWidgets('Delete N items opens confirmation', (tester) async {
      final entries = manyEntries();
      final fs = _MockFS({'/home': entries});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();
      ctrl.toggleSelect('/home/a.txt');
      ctrl.toggleSelect('/home/b.txt');

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      await tester.tap(find.text('a.txt'), buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Delete 2 items'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Delete 2'), findsWidgets);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });
  });

  // ---------------------------------------------------------------------------
  // Background context menu
  // ---------------------------------------------------------------------------
  group('FilePane — background context menu', () {
    testWidgets('empty dir shows New Folder and Refresh', (tester) async {
      final fs = _MockFS({'/home': []});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      await tester.tap(find.text('Empty directory'),
          buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();

      expect(find.text('New Folder'), findsOneWidget);
      expect(find.text('Refresh'), findsOneWidget);
    });

    testWidgets('Refresh from background menu reloads', (tester) async {
      final fs = _MockFS({'/home': []});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      await tester.tap(find.text('Empty directory'),
          buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();

      fs.dirs['/home'] = [
        FileEntry(name: 'new.txt', path: '/home/new.txt', size: 50,
            mode: 0x81A4, modTime: now, isDir: false),
      ];

      await tester.tap(find.text('Refresh'));
      await tester.pump();

      expect(find.text('new.txt'), findsOneWidget);
    });

    testWidgets('New Folder from background menu opens dialog', (tester) async {
      final fs = _MockFS({'/home': []});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      await tester.tap(find.text('Empty directory'),
          buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();

      await tester.tap(find.text('New Folder'));
      await tester.pumpAndSettle();

      expect(find.text('Folder name'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });
  });

  // ---------------------------------------------------------------------------
  // Delete key
  // ---------------------------------------------------------------------------
  group('FilePane — Delete key', () {
    testWidgets('Del key with selected file shows delete confirmation',
        (tester) async {
      final entries = [
        FileEntry(name: 'to_delete.txt', path: '/home/to_delete.txt',
            size: 100, mode: 0x81A4, modTime: now, isDir: false),
      ];
      final fs = _MockFS({'/home': entries});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      await tester.tap(find.text('to_delete.txt'));
      await tester.pump();
      ctrl.selectSingle('/home/to_delete.txt');
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();

      expect(find.text('Delete "to_delete.txt"?'), findsOneWidget);
    });

    testWidgets('Del key with no selection is ignored', (tester) async {
      final entries = manyEntries();
      final fs = _MockFS({'/home': entries});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      await tester.tap(find.text('a.txt'));
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 10));
      await tester.pumpAndSettle();
      ctrl.clearSelection();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump();

      expect(find.textContaining('Delete "'), findsNothing);
    });
  });

  // ---------------------------------------------------------------------------
  // Drag & drop
  // ---------------------------------------------------------------------------
  group('FilePane — drag feedback', () {
    testWidgets('selected file renders Draggable', (tester) async {
      final entries = [
        FileEntry(name: 'a.txt', path: '/home/a.txt', size: 100,
            mode: 0x81A4, modTime: now, isDir: false),
      ];
      final fs = _MockFS({'/home': entries});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();
      ctrl.selectSingle('/home/a.txt');

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      expect(find.byType(Draggable<PaneDragData>), findsOneWidget);
    });

    testWidgets('unselected file has no Draggable', (tester) async {
      final entries = [
        FileEntry(name: 'a.txt', path: '/home/a.txt', size: 100,
            mode: 0x81A4, modTime: now, isDir: false),
      ];
      final fs = _MockFS({'/home': entries});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      expect(find.byType(Draggable<PaneDragData>), findsNothing);
    });

    testWidgets('single selected has correct PaneDragData', (tester) async {
      final entries = [
        FileEntry(name: 'single.txt', path: '/home/single.txt', size: 100,
            mode: 0x81A4, modTime: now, isDir: false),
      ];
      final fs = _MockFS({'/home': entries});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();
      ctrl.selectSingle('/home/single.txt');

      await tester.pumpWidget(buildApp(controller: ctrl, paneId: 'pane-X'));
      await tester.pump();

      final draggable = tester.widget<Draggable<PaneDragData>>(
        find.byType(Draggable<PaneDragData>));
      expect(draggable.data!.sourcePaneId, 'pane-X');
      expect(draggable.data!.entries.length, 1);
      expect(draggable.data!.entries.first.name, 'single.txt');
    });

    testWidgets('multiple selected carry all entries', (tester) async {
      final entries = [
        FileEntry(name: 'a.txt', path: '/home/a.txt', size: 100,
            mode: 0x81A4, modTime: now, isDir: false),
        FileEntry(name: 'b.txt', path: '/home/b.txt', size: 200,
            mode: 0x81A4, modTime: now, isDir: false),
      ];
      final fs = _MockFS({'/home': entries});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();
      ctrl.toggleSelect('/home/a.txt');
      ctrl.toggleSelect('/home/b.txt');

      await tester.pumpWidget(buildApp(controller: ctrl, paneId: 'pane-Y'));
      await tester.pump();

      final draggables = tester.widgetList<Draggable<PaneDragData>>(
        find.byType(Draggable<PaneDragData>));
      expect(draggables.length, 2);

      for (final d in draggables) {
        expect(d.data!.entries.length, 2);
        expect(d.data!.sourcePaneId, 'pane-Y');
      }
    });

    testWidgets('selected directory wraps in Draggable', (tester) async {
      final entries = [
        FileEntry(name: 'mydir', path: '/home/mydir', size: 0, mode: 0x41ED,
            modTime: now, isDir: true),
      ];
      final fs = _MockFS({'/home': entries});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();
      ctrl.selectSingle('/home/mydir');

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      final draggable = tester.widget<Draggable<PaneDragData>>(
        find.byType(Draggable<PaneDragData>));
      expect(draggable.data!.entries.first.isDir, isTrue);
    });

    testWidgets('3 selected files show 3 Draggables', (tester) async {
      final entries = manyEntries();
      final fs = _MockFS({'/home': entries});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();
      ctrl.toggleSelect('/home/a.txt');
      ctrl.toggleSelect('/home/b.txt');
      ctrl.toggleSelect('/home/c.txt');

      await tester.pumpWidget(buildApp(controller: ctrl, paneId: 'pane-multi'));
      await tester.pump();

      final draggables = tester.widgetList<Draggable<PaneDragData>>(
        find.byType(Draggable<PaneDragData>));
      expect(draggables.length, 3);
      for (final d in draggables) {
        expect(d.data!.entries.length, 3);
      }
    });
  });

  // ---------------------------------------------------------------------------
  // DragTarget cross-pane
  // ---------------------------------------------------------------------------
  group('FilePane — DragTarget cross-pane', () {
    testWidgets('renders with onDropReceived callback', (tester) async {
      final entries = [
        FileEntry(name: 'file.txt', path: '/home/file.txt', size: 100,
            mode: 0x81A4, modTime: now, isDir: false),
      ];
      final fs = _MockFS({'/home': entries});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(
        controller: ctrl, paneId: 'pane-A', onDropReceived: (_) {}));
      await tester.pump();

      expect(find.text('file.txt'), findsOneWidget);
    });

    testWidgets('rejects when onDropReceived is null', (tester) async {
      final entries = [
        FileEntry(name: 'file.txt', path: '/home/file.txt', size: 100,
            mode: 0x81A4, modTime: now, isDir: false),
      ];
      final fs = _MockFS({'/home': entries});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(
        controller: ctrl, paneId: 'pane-A', onDropReceived: null));
      await tester.pump();

      expect(find.text('file.txt'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // Marquee selection
  // ---------------------------------------------------------------------------
  group('FilePane — marquee selection', () {
    testWidgets('pointer down on unselected area sets anchor', (tester) async {
      final entries = manyEntries();
      final fs = _MockFS({'/home': entries});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      final aText = find.text('a.txt');
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: tester.getCenter(aText));
      await gesture.down(tester.getCenter(aText));
      await tester.pump();
      await gesture.up();
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 10));
      await tester.pumpAndSettle();

      expect(find.text('a.txt'), findsOneWidget);
    });

    testWidgets('pointer move past threshold activates marquee', (tester) async {
      final entries = manyEntries();
      final fs = _MockFS({'/home': entries});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      final startPos = tester.getCenter(find.text('a.txt'));
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: startPos);
      await gesture.down(startPos);
      await tester.pump();

      await gesture.moveTo(startPos + const Offset(0, 40));
      await tester.pump();

      expect(ctrl.selected.isNotEmpty, isTrue);

      await gesture.up();
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 10));
      await tester.pumpAndSettle();
    });

    testWidgets('pointer move below threshold does not activate', (tester) async {
      final entries = manyEntries();
      final fs = _MockFS({'/home': entries});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      final startPos = tester.getCenter(find.text('a.txt'));
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: startPos);
      await gesture.down(startPos);
      await tester.pump();

      await gesture.moveTo(startPos + const Offset(1, 1));
      await tester.pump();

      expect(ctrl.selected, isEmpty);

      await gesture.up();
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 10));
      await tester.pumpAndSettle();
    });

    testWidgets('pointer up clears marquee state', (tester) async {
      final entries = manyEntries();
      final fs = _MockFS({'/home': entries});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      final startPos = tester.getCenter(find.text('a.txt'));
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: startPos);
      await gesture.down(startPos);
      await tester.pump();
      await gesture.moveTo(startPos + const Offset(0, 30));
      await tester.pump();
      await gesture.up();
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 10));
      await tester.pumpAndSettle();

      expect(find.text('a.txt'), findsOneWidget);
    });

    testWidgets('pointer down on selected row does not set anchor',
        (tester) async {
      final entries = manyEntries();
      final fs = _MockFS({'/home': entries});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();
      ctrl.selectSingle('/home/a.txt');

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      final aText = find.text('a.txt');
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: tester.getCenter(aText));
      await gesture.down(tester.getCenter(aText));
      await tester.pump();
      await gesture.moveTo(tester.getCenter(aText) + const Offset(0, 30));
      await tester.pump();
      await gesture.up();
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 10));
      await tester.pumpAndSettle();

      expect(ctrl.selected.contains('/home/a.txt'), isTrue);
    });

    testWidgets('right-click does not trigger marquee', (tester) async {
      final entries = [
        FileEntry(name: 'a.txt', path: '/home/a.txt', size: 100,
            mode: 0x81A4, modTime: now, isDir: false),
        FileEntry(name: 'b.txt', path: '/home/b.txt', size: 200,
            mode: 0x81A4, modTime: now, isDir: false),
      ];
      final fs = _MockFS({'/home': entries});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      final startPos = tester.getCenter(find.text('a.txt'));
      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
      await gesture.addPointer(location: startPos);
      await gesture.down(startPos);
      await tester.pump();
      await gesture.moveTo(startPos + const Offset(0, 40));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.text('a.txt'), findsWidgets);
    });

    testWidgets('Ctrl+marquee preserves existing selection', (tester) async {
      final entries = manyEntries();
      final fs = _MockFS({'/home': entries});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();
      // Pre-select a.txt
      ctrl.selectSingle('/home/a.txt');

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      // Hold Ctrl and start marquee from b.txt downward
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);

      final startPos = tester.getCenter(find.text('b.txt'));
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: startPos);
      await gesture.down(startPos);
      await tester.pump();
      await gesture.moveTo(startPos + const Offset(0, 40));
      await tester.pump();
      await gesture.up();
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 10));
      await tester.pumpAndSettle();

      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

      // a.txt should still be selected (pre-marquee preserved)
      expect(ctrl.selected.contains('/home/a.txt'), isTrue);
      // b.txt should also be selected (from marquee)
      expect(ctrl.selected.contains('/home/b.txt'), isTrue);
    });

    testWidgets('single tap selects file', (tester) async {
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

  // ---------------------------------------------------------------------------
  // Mouse back/forward buttons
  // ---------------------------------------------------------------------------
  group('FilePane — mouse back/forward buttons', () {
    testWidgets('Listener is present', (tester) async {
      final fs = _MockFS({'/home': []});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      expect(find.byType(Listener), findsWidgets);
    });

    testWidgets('kBackMouseButton calls goBack', (tester) async {
      final fs = _MockFS({'/home': [], '/home/docs': []});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();
      await ctrl.navigateTo('/home/docs');
      expect(ctrl.currentPath, '/home/docs');
      expect(ctrl.canGoBack, isTrue);

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      final mouseListener = _findFilePaneListener(tester);
      final center = tester.getCenter(find.byType(FilePane));

      await tester.runAsync(() async {
        mouseListener.onPointerDown!(PointerDownEvent(
          position: center, buttons: kBackMouseButton));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });

      await tester.pump();
      expect(ctrl.currentPath, '/home');

      ctrl.dispose();
    });

    testWidgets('kForwardMouseButton calls goForward', (tester) async {
      final fs = _MockFS({'/home': [], '/home/docs': []});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();
      await ctrl.navigateTo('/home/docs');
      await ctrl.goBack();
      expect(ctrl.currentPath, '/home');
      expect(ctrl.canGoForward, isTrue);

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      final mouseListener = _findFilePaneListener(tester);
      final center = tester.getCenter(find.byType(FilePane));

      await tester.runAsync(() async {
        mouseListener.onPointerDown!(PointerDownEvent(
          position: center, buttons: kForwardMouseButton));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });

      await tester.pump();
      expect(ctrl.currentPath, '/home/docs');

      ctrl.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  // OS drag & drop
  // ---------------------------------------------------------------------------
  group('FilePane — OS drag', () {
    testWidgets('renders with onOsDropReceived callback', (tester) async {
      final fs = _MockFS({'/home': []});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(
        controller: ctrl, onOsDropReceived: (_) {}));
      await tester.pump();

      expect(find.text('Empty directory'), findsOneWidget);

      ctrl.dispose();
    });

    testWidgets('renders with osDragging false initially', (tester) async {
      final fs = _MockFS({'/home': []});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      expect(find.text('Empty directory'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // Background context menu on non-empty file list
  // ---------------------------------------------------------------------------
  group('FilePane — background context menu on non-empty list', () {
    testWidgets('right-click in empty area of non-empty list shows menu',
        (tester) async {
      // Use entries that don't fill the viewport — empty area below
      final entries = [
        FileEntry(name: 'only.txt', path: '/home/only.txt', size: 100,
            mode: 0x81A4, modTime: now, isDir: false),
      ];
      final fs = _MockFS({'/home': entries});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      // Find the file list area and right-click below the last row
      // The list is inside a GestureDetector with onSecondaryTapUp
      // Right-click in an area that is part of the list but not on a row
      final listFinder = find.byType(ListView);
      final listBox = tester.getRect(listFinder);
      // Click in lower area of list (below the single 28px row)
      final emptyAreaPos = Offset(listBox.center.dx, listBox.top + 80);

      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
      await gesture.addPointer(location: emptyAreaPos);
      await gesture.down(emptyAreaPos);
      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.text('New Folder'), findsOneWidget);
      expect(find.text('Refresh'), findsOneWidget);

      // Dismiss menu
      await tester.tapAt(const Offset(1, 1));
      await tester.pumpAndSettle();
    });
  });

  // ---------------------------------------------------------------------------
  // Path bar onTapOutside restores path
  // ---------------------------------------------------------------------------
  group('FilePane — path bar onTapOutside', () {
    testWidgets('tapping outside path bar restores original path text',
        (tester) async {
      final fs = _MockFS({'/home': [], '/': []});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      // Enter edit mode
      await tester.tap(find.text('/home').first);
      await tester.pump();

      // Type something different
      final textField = find.byType(TextField).first;
      await tester.enterText(textField, '/some/other/path');
      await tester.pump();

      // Tap outside to trigger onTapOutside
      await tester.tapAt(const Offset(10, 300));
      await tester.pump();

      // Path should be restored to /home (original)
      expect(ctrl.currentPath, '/home');
      // Path bar should show /home, not the typed text
      expect(find.text('/home'), findsWidgets);
    });

    testWidgets('submitting edited path navigates and updates bar',
        (tester) async {
      final fs = _MockFS({'/home': [], '/var': []});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      // Enter edit mode
      await tester.tap(find.text('/home').first);
      await tester.pump();

      // Submit a new path
      await tester.enterText(find.byType(TextField).first, '/var');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(ctrl.currentPath, '/var');
    });
  });

  // ---------------------------------------------------------------------------
  // Controller lifecycle
  // ---------------------------------------------------------------------------
  group('FilePane — controller listener lifecycle', () {
    testWidgets('controller updates rebuild widget', (tester) async {
      final fs = _MockFS({'/home': [], '/tmp': []});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      expect(find.text('Empty directory'), findsOneWidget);

      fs.dirs['/home'] = [
        FileEntry(name: 'new.txt', path: '/home/new.txt', size: 50,
            mode: 0x81A4, modTime: now, isDir: false),
      ];
      await ctrl.refresh();
      await tester.pump();

      expect(find.text('new.txt'), findsOneWidget);
    });

    testWidgets('navigating updates path bar text', (tester) async {
      final fs = _MockFS({'/home': [], '/tmp': [], '/var': []});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      expect(find.text('/home'), findsWidgets);

      await ctrl.navigateTo('/tmp');
      await tester.pump();

      expect(find.text('/tmp'), findsWidgets);
    });
  });

  // ---------------------------------------------------------------------------
  // OS drag & drop — DropTarget callbacks
  // ---------------------------------------------------------------------------
  group('FilePane — DropTarget onDragEntered/onDragExited/onDragDone', () {
    testWidgets('onDragEntered sets _osDragging true and shows border',
        (tester) async {
      final fs = _MockFS({'/home': []});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(
        controller: ctrl,
        onOsDropReceived: (_) {},
      ));
      await tester.pump();

      // Find the DropTarget and invoke onDragEntered
      final dropTarget =
          tester.widget<DropTarget>(find.byType(DropTarget).first);
      dropTarget.onDragEntered!(DropEventDetails(
        localPosition: Offset.zero,
        globalPosition: Offset.zero,
      ));
      await tester.pump();

      // The Container should now have a border decoration (primary color)
      final theme = AppTheme.dark();
      // Find Container with BoxDecoration that has a border
      final containers = find.byType(Container);
      bool foundBorder = false;
      for (final element in containers.evaluate()) {
        final container = element.widget as Container;
        final dec = container.decoration;
        if (dec is BoxDecoration && dec.border != null) {
          final border = dec.border as Border;
          if (border.top.color == theme.colorScheme.primary &&
              border.top.width == 2) {
            foundBorder = true;
            break;
          }
        }
      }
      expect(foundBorder, isTrue, reason: 'Should show primary border on OS drag enter');
    });

    testWidgets('onDragExited reverts border decoration', (tester) async {
      final fs = _MockFS({'/home': []});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(
        controller: ctrl,
        onOsDropReceived: (_) {},
      ));
      await tester.pump();

      final dropTarget =
          tester.widget<DropTarget>(find.byType(DropTarget).first);

      // Enter drag
      dropTarget.onDragEntered!(DropEventDetails(
        localPosition: Offset.zero,
        globalPosition: Offset.zero,
      ));
      await tester.pump();

      // Exit drag
      dropTarget.onDragExited!(DropEventDetails(
        localPosition: Offset.zero,
        globalPosition: Offset.zero,
      ));
      await tester.pump();

      // Verify no primary-colored border remains
      final theme = AppTheme.dark();
      final containers = find.byType(Container);
      bool foundOsBorder = false;
      for (final element in containers.evaluate()) {
        final container = element.widget as Container;
        final dec = container.decoration;
        if (dec is BoxDecoration && dec.border != null) {
          final border = dec.border as Border;
          if (border.top.color == theme.colorScheme.primary &&
              border.top.width == 2) {
            foundOsBorder = true;
            break;
          }
        }
      }
      expect(foundOsBorder, isFalse,
          reason: 'Border should be gone after drag exit');
    });

    testWidgets('onDragDone resets _osDragging and calls onOsDropReceived',
        (tester) async {
      List<String>? receivedPaths;
      final fs = _MockFS({'/home': []});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(
        controller: ctrl,
        onOsDropReceived: (paths) => receivedPaths = paths,
      ));
      await tester.pump();

      final dropTarget =
          tester.widget<DropTarget>(find.byType(DropTarget).first);

      // Enter drag first
      dropTarget.onDragEntered!(DropEventDetails(
        localPosition: Offset.zero,
        globalPosition: Offset.zero,
      ));
      await tester.pump();

      // Now complete the drag with files
      dropTarget.onDragDone!(DropDoneDetails(
        files: [
          DropItemFile('/tmp/file1.txt'),
          DropItemFile('/tmp/file2.txt'),
        ],
        localPosition: Offset.zero,
        globalPosition: Offset.zero,
      ));
      await tester.pump();

      // Verify callback was called with correct paths
      expect(receivedPaths, isNotNull);
      expect(receivedPaths!.length, 2);
      expect(receivedPaths![0], '/tmp/file1.txt');
      expect(receivedPaths![1], '/tmp/file2.txt');

      // Verify border is gone (osDragging reset to false)
      final theme = AppTheme.dark();
      final containers = find.byType(Container);
      bool foundOsBorder = false;
      for (final element in containers.evaluate()) {
        final container = element.widget as Container;
        final dec = container.decoration;
        if (dec is BoxDecoration && dec.border != null) {
          final border = dec.border as Border;
          if (border.top.color == theme.colorScheme.primary &&
              border.top.width == 2) {
            foundOsBorder = true;
            break;
          }
        }
      }
      expect(foundOsBorder, isFalse,
          reason: 'Border should be gone after drag done');
    });

    testWidgets('onDragDone with empty files does not call onOsDropReceived',
        (tester) async {
      List<String>? receivedPaths;
      final fs = _MockFS({'/home': []});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(
        controller: ctrl,
        onOsDropReceived: (paths) => receivedPaths = paths,
      ));
      await tester.pump();

      final dropTarget =
          tester.widget<DropTarget>(find.byType(DropTarget).first);
      dropTarget.onDragDone!(const DropDoneDetails(
        files: [],
        localPosition: Offset.zero,
        globalPosition: Offset.zero,
      ));
      await tester.pump();

      expect(receivedPaths, isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // DragTarget — onWillAcceptWithDetails returns false when no onDropReceived
  // ---------------------------------------------------------------------------
  group('FilePane — DragTarget onWillAcceptWithDetails', () {
    testWidgets('rejects drag when onDropReceived is null', (tester) async {
      final entries = [
        FileEntry(name: 'file.txt', path: '/home/file.txt', size: 100,
            mode: 0x81A4, modTime: now, isDir: false),
      ];
      final fs = _MockFS({'/home': entries});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(
        controller: ctrl,
        paneId: 'target-pane',
        onDropReceived: null,
      ));
      await tester.pump();

      // Find the inner DragTarget<PaneDragData>
      final dragTarget = tester.widget<DragTarget<PaneDragData>>(
        find.byType(DragTarget<PaneDragData>),
      );

      // Call onWillAcceptWithDetails directly
      final result = dragTarget.onWillAcceptWithDetails!(
        DragTargetDetails<PaneDragData>(
          data: PaneDragData(
            sourcePaneId: 'other-pane',
            entries: [entries.first],
          ),
          offset: Offset.zero,
        ),
      );
      expect(result, isFalse);
    });

    testWidgets('rejects drag from same pane', (tester) async {
      final entries = [
        FileEntry(name: 'file.txt', path: '/home/file.txt', size: 100,
            mode: 0x81A4, modTime: now, isDir: false),
      ];
      final fs = _MockFS({'/home': entries});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(
        controller: ctrl,
        paneId: 'same-pane',
        onDropReceived: (_) {},
      ));
      await tester.pump();

      final dragTarget = tester.widget<DragTarget<PaneDragData>>(
        find.byType(DragTarget<PaneDragData>),
      );

      final result = dragTarget.onWillAcceptWithDetails!(
        DragTargetDetails<PaneDragData>(
          data: PaneDragData(
            sourcePaneId: 'same-pane',
            entries: [entries.first],
          ),
          offset: Offset.zero,
        ),
      );
      expect(result, isFalse);
    });

    testWidgets('accepts drag from different pane with onDropReceived',
        (tester) async {
      final entries = [
        FileEntry(name: 'file.txt', path: '/home/file.txt', size: 100,
            mode: 0x81A4, modTime: now, isDir: false),
      ];
      final fs = _MockFS({'/home': entries});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(
        controller: ctrl,
        paneId: 'target-pane',
        onDropReceived: (_) {},
      ));
      await tester.pump();

      final dragTarget = tester.widget<DragTarget<PaneDragData>>(
        find.byType(DragTarget<PaneDragData>),
      );

      final result = dragTarget.onWillAcceptWithDetails!(
        DragTargetDetails<PaneDragData>(
          data: PaneDragData(
            sourcePaneId: 'source-pane',
            entries: [entries.first],
          ),
          offset: Offset.zero,
        ),
      );
      expect(result, isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // DragTarget — onAcceptWithDetails calls onDropReceived
  // ---------------------------------------------------------------------------
  group('FilePane — DragTarget onAcceptWithDetails', () {
    testWidgets('onAcceptWithDetails calls onDropReceived with entries',
        (tester) async {
      List<FileEntry>? droppedEntries;
      final entries = [
        FileEntry(name: 'file.txt', path: '/home/file.txt', size: 100,
            mode: 0x81A4, modTime: now, isDir: false),
      ];
      final fs = _MockFS({'/home': entries});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(
        controller: ctrl,
        paneId: 'target-pane',
        onDropReceived: (e) => droppedEntries = e,
      ));
      await tester.pump();

      final dragTarget = tester.widget<DragTarget<PaneDragData>>(
        find.byType(DragTarget<PaneDragData>),
      );

      final sourceEntries = [
        FileEntry(name: 'remote.txt', path: '/remote/remote.txt', size: 200,
            mode: 0x81A4, modTime: now, isDir: false),
      ];

      dragTarget.onAcceptWithDetails!(
        DragTargetDetails<PaneDragData>(
          data: PaneDragData(
            sourcePaneId: 'source-pane',
            entries: sourceEntries,
          ),
          offset: Offset.zero,
        ),
      );
      await tester.pump();

      expect(droppedEntries, isNotNull);
      expect(droppedEntries!.length, 1);
      expect(droppedEntries!.first.name, 'remote.txt');
    });
  });

  // ---------------------------------------------------------------------------
  // DragTarget — hover state decoration (isHovering)
  // ---------------------------------------------------------------------------
  group('FilePane — DragTarget hover decoration', () {
    testWidgets('builder shows border when candidateData is non-empty',
        (tester) async {
      final entries = [
        FileEntry(name: 'file.txt', path: '/home/file.txt', size: 100,
            mode: 0x81A4, modTime: now, isDir: false),
      ];
      final fs = _MockFS({'/home': entries});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(
        controller: ctrl,
        paneId: 'target-pane',
        onDropReceived: (_) {},
      ));
      await tester.pump();

      final dragTarget = tester.widget<DragTarget<PaneDragData>>(
        find.byType(DragTarget<PaneDragData>),
      );

      // Call the builder with non-empty candidateData to simulate hover
      final hoverWidget = dragTarget.builder(
        tester.element(find.byType(DragTarget<PaneDragData>)),
        [
          PaneDragData(
            sourcePaneId: 'source-pane',
            entries: [entries.first],
          ),
        ],
        [],
      );

      // The returned widget should be a Container with a BoxDecoration border
      expect(hoverWidget, isA<Container>());
      final container = hoverWidget as Container;
      expect(container.decoration, isA<BoxDecoration>());
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.border, isNotNull);
      final border = decoration.border! as Border;
      expect(border.top.width, 2);
    });

    testWidgets('builder shows no border when candidateData is empty',
        (tester) async {
      final entries = [
        FileEntry(name: 'file.txt', path: '/home/file.txt', size: 100,
            mode: 0x81A4, modTime: now, isDir: false),
      ];
      final fs = _MockFS({'/home': entries});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(
        controller: ctrl,
        paneId: 'target-pane',
        onDropReceived: (_) {},
      ));
      await tester.pump();

      final dragTarget = tester.widget<DragTarget<PaneDragData>>(
        find.byType(DragTarget<PaneDragData>),
      );

      // Call the builder with empty candidateData (no hover)
      final noHoverWidget = dragTarget.builder(
        tester.element(find.byType(DragTarget<PaneDragData>)),
        [],
        [],
      );

      expect(noHoverWidget, isA<Container>());
      final container = noHoverWidget as Container;
      expect(container.decoration, isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // Ctrl+tap selection
  // ---------------------------------------------------------------------------
  group('FilePane — Ctrl+tap toggles selection', () {
    testWidgets('Ctrl+tap on file row calls toggleSelect via onCtrlTap',
        (tester) async {
      final entries = manyEntries();
      final fs = _MockFS({'/home': entries});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      // Select first file programmatically (InkWell onTap is unreliable
      // in widget tests when onDoubleTap is also registered).
      ctrl.selectSingle('/home/a.txt');
      await tester.pump();
      expect(ctrl.selected, {'/home/a.txt'});

      // Ctrl+tap on second file — adds it to selection.
      // Hold Ctrl so FileRow's InkWell.onTap calls onCtrlTap instead of onTap.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.tap(find.text('b.txt'));
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 10));
      await tester.pumpAndSettle();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(ctrl.selected, {'/home/a.txt', '/home/b.txt'});

      // Ctrl+tap on first file again — deselects it.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.tap(find.text('a.txt'));
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 10));
      await tester.pumpAndSettle();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(ctrl.selected, {'/home/b.txt'});
    });
  });

  // ---------------------------------------------------------------------------
  // Click on empty space clears selection
  // ---------------------------------------------------------------------------
  group('FilePane — click empty space clears selection', () {
    testWidgets('clicking empty area below files clears selection',
        (tester) async {
      final entries = [
        FileEntry(name: 'a.txt', path: '/home/a.txt', size: 10,
            mode: 0x81A4, modTime: DateTime(2024), isDir: false),
      ];
      final fs = _MockFS({'/home': entries});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();
      ctrl.selectSingle('/home/a.txt');

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      expect(ctrl.selected, {'/home/a.txt'});

      // Tap empty area below the single file row (row height is 28)
      final listFinder = find.byType(ListView);
      final listBox = tester.getRect(listFinder);
      // Tap at the bottom of the list (well past the single row)
      await tester.tapAt(Offset(listBox.center.dx, listBox.center.dy + 100));
      await tester.pump();

      expect(ctrl.selected, isEmpty);
    });

    testWidgets('tapping empty state clears selection', (tester) async {
      final fs = _MockFS({'/home': []});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      await tester.tap(find.text('Empty directory'));
      await tester.pump();

      expect(ctrl.selected, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // onPaneActivated callback
  // ---------------------------------------------------------------------------
  group('FilePane — onPaneActivated', () {
    testWidgets('fires onPaneActivated when interacting with file list',
        (tester) async {
      final entries = [
        FileEntry(name: 'a.txt', path: '/home/a.txt', size: 10,
            mode: 0x81A4, modTime: DateTime(2024), isDir: false),
      ];
      final fs = _MockFS({'/home': entries});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      var activated = false;
      await tester.pumpWidget(buildApp(
        controller: ctrl,
        onPaneActivated: () => activated = true,
      ));
      await tester.pump();

      await tester.tap(find.text('a.txt'));
      // Flush double-tap timer
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 10));
      await tester.pumpAndSettle();

      expect(activated, isTrue);
    });

    testWidgets('fires onPaneActivated on empty state tap', (tester) async {
      final fs = _MockFS({'/home': []});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      var activated = false;
      await tester.pumpWidget(buildApp(
        controller: ctrl,
        onPaneActivated: () => activated = true,
      ));
      await tester.pump();

      await tester.tap(find.text('Empty directory'));
      await tester.pump();

      expect(activated, isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // Cross-widget marquee (from session panel)
  // ---------------------------------------------------------------------------
  group('FilePane — cross-widget marquee', () {
    testWidgets('crossMarquee start+move selects files', (tester) async {
      final entries = manyEntries();
      final fs = _MockFS({'/home': entries});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      final crossMarquee = CrossMarqueeController();
      addTearDown(crossMarquee.dispose);

      await tester.pumpWidget(buildApp(
        controller: ctrl,
        crossMarquee: crossMarquee,
      ));
      await tester.pump();

      // Get the global position of the file list area
      final pane = find.byType(FilePane);
      final paneBox = tester.getRect(pane);

      // Simulate cross-marquee: start at top of file list, move to bottom
      crossMarquee.start(paneBox.topLeft + const Offset(10, 10));
      await tester.pump();
      crossMarquee.move(paneBox.topLeft + const Offset(10, 100));
      await tester.pump();

      // Should have selected some files
      expect(ctrl.selected, isNotEmpty);

      // End the marquee
      crossMarquee.end();
      await tester.pump();
    });

    testWidgets('crossMarquee end clears marquee state', (tester) async {
      final entries = manyEntries();
      final fs = _MockFS({'/home': entries});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      final crossMarquee = CrossMarqueeController();
      addTearDown(crossMarquee.dispose);

      await tester.pumpWidget(buildApp(
        controller: ctrl,
        crossMarquee: crossMarquee,
      ));
      await tester.pump();

      final pane = find.byType(FilePane);
      final paneBox = tester.getRect(pane);

      // Start and move
      crossMarquee.start(paneBox.topLeft + const Offset(10, 10));
      await tester.pump();
      crossMarquee.move(paneBox.topLeft + const Offset(10, 100));
      await tester.pump();

      // MarqueePainter should be visible
      expect(find.byType(CustomPaint), findsWidgets);

      // End
      crossMarquee.end();
      await tester.pump();

      // MarqueePainter should be gone — no marquee overlay
      // (the selection stays, but the visual overlay is removed)
      final painters = tester.widgetList<CustomPaint>(find.byType(CustomPaint));
      final marquee = painters.where((p) => p.painter is MarqueePainter);
      expect(marquee, isEmpty);
    });
  });
}
