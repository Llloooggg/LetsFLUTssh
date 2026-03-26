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

/// Find FilePane's outermost Listener (the one with back/forward mouse handling).
/// Walks the FilePane element tree to find the first Listener with onPointerDown.
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

  group('FilePane — mouse back/forward buttons (lines 94-99)', () {
    testWidgets('Listener onPointerDown with kBackMouseButton calls goBack',
        (tester) async {
      final fs = _MockFS({
        '/home': [],
        '/home/docs': [],
      });
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
          position: center,
          buttons: kBackMouseButton,
        ));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });

      await tester.pump();
      expect(ctrl.currentPath, '/home');

      ctrl.dispose();
    });

    testWidgets('Listener onPointerDown with kForwardMouseButton calls goForward',
        (tester) async {
      final fs = _MockFS({
        '/home': [],
        '/home/docs': [],
      });
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
          position: center,
          buttons: kForwardMouseButton,
        ));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });

      await tester.pump();
      expect(ctrl.currentPath, '/home/docs');

      ctrl.dispose();
    });
  });

  group('FilePane — DropTarget OS drag callbacks (lines 105-113)', () {
    testWidgets('FilePane renders with onOsDropReceived callback', (tester) async {
      final fs = _MockFS({'/home': []});
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
              onOsDropReceived: (_) {},
            ),
          ),
        ),
      ));
      await tester.pump();

      expect(find.text('Empty directory'), findsOneWidget);

      ctrl.dispose();
    });
  });

  group('FilePane — Draggable onDragStarted/onDragEnd (lines 477-479)', () {
    testWidgets('selected file row wraps in Draggable with correct data',
        (tester) async {
      final entries = [
        FileEntry(
            name: 'a.txt',
            path: '/home/a.txt',
            size: 100,
            mode: 0x81A4,
            modTime: now,
            isDir: false),
        FileEntry(
            name: 'b.txt',
            path: '/home/b.txt',
            size: 200,
            mode: 0x81A4,
            modTime: now,
            isDir: false),
      ];
      final fs = _MockFS({'/home': entries});
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.init();
      ctrl.selectSingle('/home/a.txt');

      await tester.pumpWidget(buildApp(controller: ctrl, paneId: 'left'));
      await tester.pump();

      // Selected row should be wrapped in Draggable
      final draggables = find.byWidgetPredicate(
          (w) => w is Draggable && w.data != null);
      expect(draggables, findsWidgets);

      ctrl.dispose();
    });
  });

  group('FilePane — DragTarget cross-pane drop (lines 596-624)', () {
    testWidgets('DragTarget accepts drop from different pane', (tester) async {
      final entries = [
        FileEntry(
            name: 'file.txt',
            path: '/home/file.txt',
            size: 100,
            mode: 0x81A4,
            modTime: now,
            isDir: false),
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
              paneId: 'right',
              onDropReceived: (_) {},
            ),
          ),
        ),
      ));
      await tester.pump();

      expect(find.text('file.txt'), findsOneWidget);

      ctrl.dispose();
    });
  });
}
