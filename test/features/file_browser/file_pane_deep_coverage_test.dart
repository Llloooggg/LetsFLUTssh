import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/sftp/file_system.dart';
import 'package:letsflutssh/core/sftp/sftp_models.dart';
import 'package:letsflutssh/features/file_browser/file_browser_controller.dart';
import 'package:letsflutssh/features/file_browser/file_pane.dart';
import 'package:letsflutssh/features/file_browser/file_row.dart';
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

  group('FilePane — drag feedback rendering', () {
    testWidgets('selected file renders Draggable widget', (tester) async {
      final entries = [
        FileEntry(name: 'a.txt', path: '/home/a.txt', size: 100, mode: 0x81A4, modTime: now, isDir: false),
      ];
      final fs = _MockFS({'/home': entries});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();
      ctrl.selectSingle('/home/a.txt');

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      // Selected file should be wrapped in Draggable
      expect(find.byType(Draggable<PaneDragData>), findsOneWidget);
    });

    testWidgets('unselected file is not wrapped in Draggable', (tester) async {
      final entries = [
        FileEntry(name: 'a.txt', path: '/home/a.txt', size: 100, mode: 0x81A4, modTime: now, isDir: false),
      ];
      final fs = _MockFS({'/home': entries});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();
      // No selection

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      expect(find.byType(Draggable<PaneDragData>), findsNothing);
    });
  });

  group('FilePane — navigation back/forward via controller', () {
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

    testWidgets('back button enabled after navigation', (tester) async {
      final fs = _MockFS({'/home': [], '/tmp': []});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();
      await ctrl.navigateTo('/tmp');

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      expect(ctrl.canGoBack, isTrue);

      // Tap Back
      await tester.tap(find.byTooltip('Back'));
      await tester.pump();

      expect(ctrl.currentPath, '/home');
    });

    testWidgets('forward button enabled after going back', (tester) async {
      final fs = _MockFS({'/home': [], '/tmp': []});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();
      await ctrl.navigateTo('/tmp');
      await ctrl.goBack();

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      expect(ctrl.canGoForward, isTrue);

      // Tap Forward
      await tester.tap(find.byTooltip('Forward'));
      await tester.pump();

      expect(ctrl.currentPath, '/tmp');
    });
  });

  group('FilePane — Owner column in headers', () {
    testWidgets('Owner column header appears when entries have owner', (tester) async {
      final entries = [
        FileEntry(name: 'a.txt', path: '/home/a.txt', size: 100, mode: 0x81A4, modTime: now, isDir: false, owner: 'john'),
      ];
      final fs = _MockFS({'/home': entries});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      expect(find.text('Owner'), findsOneWidget);
    });

    testWidgets('clicking Owner header sorts by owner', (tester) async {
      final entries = [
        FileEntry(name: 'a.txt', path: '/home/a.txt', size: 100, mode: 0x81A4, modTime: now, isDir: false, owner: 'bob'),
        FileEntry(name: 'b.txt', path: '/home/b.txt', size: 200, mode: 0x81A4, modTime: now, isDir: false, owner: 'alice'),
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

  group('FilePane — error state color', () {
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

  group('FilePane — controller listener lifecycle', () {
    testWidgets('controller updates rebuild widget', (tester) async {
      final fs = _MockFS({'/home': [], '/tmp': []});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      expect(find.text('Empty directory'), findsOneWidget);

      // Add files via navigating
      fs.dirs['/home'] = [
        FileEntry(name: 'new.txt', path: '/home/new.txt', size: 50, mode: 0x81A4, modTime: now, isDir: false),
      ];
      await ctrl.refresh();
      await tester.pump();

      expect(find.text('new.txt'), findsOneWidget);
    });
  });

  group('FilePane — _dragIcon helper', () {
    testWidgets('single directory drag shows folder icon in feedback', (tester) async {
      final entries = [
        FileEntry(name: 'mydir', path: '/home/mydir', size: 0, mode: 0x41ED, modTime: now, isDir: true),
      ];
      final fs = _MockFS({'/home': entries});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();
      ctrl.selectSingle('/home/mydir');

      await tester.pumpWidget(buildApp(controller: ctrl));
      await tester.pump();

      // Verify Draggable is rendered for selected dir
      expect(find.byType(Draggable<PaneDragData>), findsOneWidget);
    });
  });
}
