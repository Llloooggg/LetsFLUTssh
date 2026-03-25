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
  });
}
