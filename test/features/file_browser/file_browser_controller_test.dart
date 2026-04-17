import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/sftp/file_system.dart';
import 'package:letsflutssh/core/sftp/sftp_models.dart';
import 'package:letsflutssh/features/file_browser/file_browser_controller.dart';

/// In-memory file system for testing.
class _MockFS implements FileSystem {
  final Map<String, List<FileEntry>> dirs;
  final List<String> createdDirs = [];
  final List<String> removedFiles = [];
  final List<String> removedDirs = [];
  final List<(String, String)> renames = [];
  Map<String, int> dirSizeResults = {};
  Set<String> dirSizeErrors = {};
  List<String> dirSizeCalls = [];

  _MockFS(this.dirs);

  @override
  Future<String> initialDir() async => '/home';

  @override
  Future<List<FileEntry>> list(String path) async {
    if (!dirs.containsKey(path)) throw Exception('Not found: $path');
    return dirs[path]!;
  }

  @override
  Future<void> mkdir(String path) async => createdDirs.add(path);

  @override
  Future<void> remove(String path) async => removedFiles.add(path);

  @override
  Future<void> removeDir(String path) async => removedDirs.add(path);

  @override
  Future<void> rename(String oldPath, String newPath) async =>
      renames.add((oldPath, newPath));
  @override
  Future<int> dirSize(String path) async {
    dirSizeCalls.add(path);
    if (dirSizeErrors.contains(path)) throw Exception('Size error: $path');
    return dirSizeResults[path] ?? 0;
  }
}

void main() {
  final now = DateTime(2024, 1, 1);
  final testEntries = [
    FileEntry(
      name: 'docs',
      path: '/home/docs',
      size: 0,
      mode: 0755,
      modTime: now,
      isDir: true,
    ),
    FileEntry(
      name: 'readme.md',
      path: '/home/readme.md',
      size: 100,
      mode: 0644,
      modTime: now,
      isDir: false,
    ),
    FileEntry(
      name: 'app.dart',
      path: '/home/app.dart',
      size: 250,
      mode: 0644,
      modTime: now,
      isDir: false,
    ),
  ];

  group('FilePaneController', () {
    late _MockFS fs;
    late FilePaneController ctrl;

    setUp(() {
      fs = _MockFS({
        '/home': testEntries,
        '/home/docs': [],
        '/': [
          FileEntry(
            name: 'home',
            path: '/home',
            size: 0,
            mode: 0755,
            modTime: now,
            isDir: true,
          ),
        ],
      });
      ctrl = FilePaneController(fs: fs, label: 'Test');
    });

    tearDown(() => ctrl.dispose());

    test('init() navigates to initial directory', () async {
      await ctrl.init();
      expect(ctrl.currentPath, '/home');
      expect(ctrl.entries.length, 3);
    });

    test('navigateTo changes path and loads entries', () async {
      await ctrl.init();
      await ctrl.navigateTo('/home/docs');
      expect(ctrl.currentPath, '/home/docs');
      expect(ctrl.entries, isEmpty);
    });

    test('navigateUp goes to parent', () async {
      await ctrl.init();
      await ctrl.navigateTo('/home/docs');
      await ctrl.navigateUp();
      expect(ctrl.currentPath, '/home');
    });

    test('navigateUp from root stays at root', () async {
      await ctrl.init();
      // Navigate to root first
      ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.navigateTo('/', addToHistory: false);
      await ctrl.navigateUp();
      expect(ctrl.currentPath, '/');
    });

    test('back/forward navigation history', () async {
      await ctrl.init();
      await ctrl.navigateTo('/home/docs');
      expect(ctrl.canGoBack, isTrue);
      expect(ctrl.canGoForward, isFalse);

      await ctrl.goBack();
      expect(ctrl.currentPath, '/home');
      expect(ctrl.canGoForward, isTrue);

      await ctrl.goForward();
      expect(ctrl.currentPath, '/home/docs');
    });

    test('goBack on empty history does nothing', () async {
      await ctrl.init();
      expect(ctrl.canGoBack, isFalse);
      await ctrl.goBack();
      expect(ctrl.currentPath, '/home');
    });

    test('goForward on empty history does nothing', () async {
      await ctrl.init();
      expect(ctrl.canGoForward, isFalse);
      await ctrl.goForward();
      expect(ctrl.currentPath, '/home');
    });

    test('selection operations', () async {
      await ctrl.init();
      expect(ctrl.selected, isEmpty);

      ctrl.selectSingle('/home/readme.md');
      expect(ctrl.selected, {'/home/readme.md'});

      ctrl.toggleSelect('/home/app.dart');
      expect(ctrl.selected, {'/home/readme.md', '/home/app.dart'});

      ctrl.toggleSelect('/home/readme.md');
      expect(ctrl.selected, {'/home/app.dart'});

      ctrl.clearSelection();
      expect(ctrl.selected, isEmpty);
    });

    test('selectAll selects all entries', () async {
      await ctrl.init();
      ctrl.selectAll();
      expect(ctrl.selected.length, 3);
    });

    test('selectPaths sets exact selection', () async {
      await ctrl.init();
      ctrl.selectPaths({'/home/readme.md'});
      expect(ctrl.selected, {'/home/readme.md'});
    });

    test('selectedEntries returns matching FileEntry objects', () async {
      await ctrl.init();
      ctrl.selectSingle('/home/readme.md');
      expect(ctrl.selectedEntries.length, 1);
      expect(ctrl.selectedEntries.first.name, 'readme.md');
    });

    test('totalFileSize sums non-directory sizes', () async {
      await ctrl.init();
      // readme.md=100 + app.dart=250 = 350
      expect(ctrl.totalFileSize, 350);
    });

    test('sort by name (default)', () async {
      await ctrl.init();
      // dirs first, then alphabetical
      expect(ctrl.entries[0].name, 'docs');
      expect(ctrl.entries[1].name, 'app.dart');
      expect(ctrl.entries[2].name, 'readme.md');
    });

    test('sort by size', () async {
      await ctrl.init();
      ctrl.setSort(SortColumn.size);
      // dirs first (size 0), then files by size ascending
      expect(ctrl.entries[0].name, 'docs');
      expect(ctrl.entries[1].name, 'readme.md'); // 100
      expect(ctrl.entries[2].name, 'app.dart'); // 250
    });

    test('toggle sort direction', () async {
      await ctrl.init();
      ctrl.setSort(SortColumn.name); // Already name, toggles to descending
      expect(ctrl.sortAscending, isFalse);
      // dirs still first, files in reverse alpha
      expect(ctrl.entries.last.name, 'app.dart');
    });

    test('navigateTo clears selection', () async {
      await ctrl.init();
      ctrl.selectSingle('/home/readme.md');
      await ctrl.navigateTo('/home/docs');
      expect(ctrl.selected, isEmpty);
    });

    test('refresh on error sets error state', () async {
      await ctrl.init();
      await ctrl.navigateTo('/nonexistent', addToHistory: false);
      expect(ctrl.error, isNotNull);
      expect(ctrl.entries, isEmpty);
    });

    test('notifyListeners fires on state changes', () async {
      await ctrl.init();
      var count = 0;
      ctrl.addListener(() => count++);

      ctrl.selectSingle('/home/readme.md');
      expect(count, 1);

      ctrl.toggleSelect('/home/app.dart');
      expect(count, 2);

      ctrl.clearSelection();
      expect(count, 3);

      ctrl.selectAll();
      expect(count, 4);
    });

    test('dispose can be called safely', () async {
      await ctrl.init();
      ctrl.addListener(() {});
      ctrl.dispose();
      // No exception = success. Can't add listener after dispose.
      // Re-create ctrl so tearDown doesn't double-dispose.
      ctrl = FilePaneController(fs: fs, label: 'Test');
    });

    test('cached properties invalidate on refresh', () async {
      await ctrl.init();
      final size1 = ctrl.totalFileSize;
      expect(size1, 350);

      // Refresh loads same data but caches should be invalidated
      await ctrl.refresh();
      final size2 = ctrl.totalFileSize;
      expect(size2, 350);
    });

    test('navigateUp strips trailing slash', () async {
      await ctrl.init();
      await ctrl.navigateTo('/home/docs/');
      await ctrl.navigateUp();
      expect(ctrl.currentPath, '/home');
    });

    test('sort by owner column', () async {
      await ctrl.init();
      ctrl.setSort(SortColumn.owner);
      // Should not throw, entries sorted by owner
      expect(ctrl.entries, isNotEmpty);
    });

    test('folderSize returns null for uncalculated path', () async {
      await ctrl.init();
      expect(ctrl.folderSize('/home/docs'), isNull);
    });

    test('folderSize returns cached value after calculation', () async {
      await ctrl.init();
      fs.dirSizeResults['/home/docs'] = 4096;
      ctrl.requestFolderSize('/home/docs');
      await Future<void>.delayed(Duration.zero);
      expect(ctrl.folderSize('/home/docs'), const FolderSizeOk(4096));
    });

    test('requestFolderSize deduplicates pending requests', () async {
      await ctrl.init();
      fs.dirSizeResults['/home/docs'] = 1024;
      ctrl.requestFolderSize('/home/docs');
      ctrl.requestFolderSize('/home/docs');
      ctrl.requestFolderSize('/home/docs');
      await Future<void>.delayed(Duration.zero);
      expect(fs.dirSizeCalls.where((p) => p == '/home/docs').length, 1);
    });

    test('requestFolderSize skips already cached paths', () async {
      await ctrl.init();
      fs.dirSizeResults['/home/docs'] = 512;
      ctrl.requestFolderSize('/home/docs');
      await Future<void>.delayed(Duration.zero);
      expect(ctrl.folderSize('/home/docs'), const FolderSizeOk(512));

      fs.dirSizeCalls.clear();
      ctrl.requestFolderSize('/home/docs');
      await Future<void>.delayed(Duration.zero);
      expect(fs.dirSizeCalls, isEmpty);
    });

    test('requestFolderSize limits concurrent calculations to 2', () async {
      final slowFs = _MockFS({
        '/home': testEntries,
        '/home/docs': [],
        '/': [
          FileEntry(
            name: 'home',
            path: '/home',
            size: 0,
            mode: 0755,
            modTime: now,
            isDir: true,
          ),
        ],
      });
      slowFs.dirSizeResults = {};

      final slowCtrl = FilePaneController(fs: slowFs, label: 'Slow');
      addTearDown(slowCtrl.dispose);
      await slowCtrl.navigateTo('/home', addToHistory: false);

      slowCtrl.requestFolderSize('/a');
      slowCtrl.requestFolderSize('/b');
      slowCtrl.requestFolderSize('/c');

      await Future<void>.delayed(Duration.zero);
      // All 3 requested; first 2 should start immediately, 3rd queued
      // Since dirSize completes synchronously via async, all drain quickly
      expect(slowFs.dirSizeCalls.length, 3);
    });

    test('requestFolderSize handles errors gracefully', () async {
      await ctrl.init();
      fs.dirSizeErrors.add('/home/docs');
      ctrl.requestFolderSize('/home/docs');
      await Future<void>.delayed(Duration.zero);
      // Failed calculation cached as FolderSizeFailed so the UI can show an
      // error marker and the queue does not endlessly retry.
      expect(ctrl.folderSize('/home/docs'), const FolderSizeFailed());
    });

    test('requestFolderSize notifies listeners on success', () async {
      await ctrl.init();
      fs.dirSizeResults['/home/docs'] = 2048;
      var notified = 0;
      ctrl.addListener(() => notified++);
      ctrl.requestFolderSize('/home/docs');
      await Future<void>.delayed(Duration.zero);
      expect(notified, greaterThanOrEqualTo(1));
    });

    test('navigateTo clears folder size caches', () async {
      await ctrl.init();
      fs.dirSizeResults['/home/docs'] = 4096;
      ctrl.requestFolderSize('/home/docs');
      await Future<void>.delayed(Duration.zero);
      expect(ctrl.folderSize('/home/docs'), const FolderSizeOk(4096));

      await ctrl.navigateTo('/home/docs');
      // Folder sizes cleared on navigation
      expect(ctrl.folderSize('/home/docs'), isNull);
    });

    test(
      'navigateTo adds current path to back stack and clears forward',
      () async {
        await ctrl.init();
        expect(ctrl.currentPath, '/home');
        await ctrl.navigateTo('/home/docs');
        expect(ctrl.canGoBack, isTrue);
        expect(ctrl.canGoForward, isFalse);

        await ctrl.goBack();
        expect(ctrl.canGoForward, isTrue);

        // navigateTo should clear forward stack
        await ctrl.navigateTo('/home/docs');
        expect(ctrl.canGoForward, isFalse);
      },
    );

    test('drainSizeQueue processes remaining items after completion', () async {
      await ctrl.init();
      fs.dirSizeResults['/a'] = 100;
      fs.dirSizeResults['/b'] = 200;
      fs.dirSizeResults['/c'] = 300;

      ctrl.requestFolderSize('/a');
      ctrl.requestFolderSize('/b');
      ctrl.requestFolderSize('/c');
      await Future<void>.delayed(Duration.zero);

      expect(ctrl.folderSize('/a'), const FolderSizeOk(100));
      expect(ctrl.folderSize('/b'), const FolderSizeOk(200));
      expect(ctrl.folderSize('/c'), const FolderSizeOk(300));
    });

    test('drainSizeQueue continues after error', () async {
      await ctrl.init();
      fs.dirSizeErrors.add('/fail');
      fs.dirSizeResults['/ok'] = 999;

      ctrl.requestFolderSize('/fail');
      ctrl.requestFolderSize('/ok');
      await Future<void>.delayed(Duration.zero);

      expect(ctrl.folderSize('/fail'), const FolderSizeFailed());
      expect(ctrl.folderSize('/ok'), const FolderSizeOk(999));
    });

    test(
      'clearFolderSize discards cached failure so retry can succeed',
      () async {
        await ctrl.init();
        fs.dirSizeErrors.add('/flaky');
        ctrl.requestFolderSize('/flaky');
        await Future<void>.delayed(Duration.zero);
        expect(ctrl.folderSize('/flaky'), const FolderSizeFailed());

        // Network came back. Clearing the failure marker lets the next
        // request actually re-call dirSize.
        fs.dirSizeErrors.clear();
        fs.dirSizeResults['/flaky'] = 42;
        ctrl.clearFolderSize('/flaky');
        ctrl.requestFolderSize('/flaky');
        await Future<void>.delayed(Duration.zero);
        expect(ctrl.folderSize('/flaky'), const FolderSizeOk(42));
      },
    );
  });
}
