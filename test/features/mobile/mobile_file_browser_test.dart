import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/connection/connection.dart';
import 'package:letsflutssh/core/sftp/sftp_models.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/features/file_browser/file_browser_controller.dart';
import 'package:letsflutssh/core/sftp/file_system.dart';
import 'package:letsflutssh/features/mobile/mobile_file_browser.dart';
import 'package:letsflutssh/theme/app_theme.dart';
import 'package:letsflutssh/utils/format.dart';

/// Fake file system for testing.
class FakeFileSystem implements FileSystem {
  final List<FileEntry> fakeEntries;
  final String fakeInitialDir;
  bool listCalled = false;

  FakeFileSystem({
    this.fakeEntries = const [],
    this.fakeInitialDir = '/home/test',
  });

  @override
  Future<String> initialDir() async => fakeInitialDir;

  @override
  Future<List<FileEntry>> list(String path) async {
    listCalled = true;
    return fakeEntries;
  }

  @override
  Future<void> mkdir(String path) async {}

  @override
  Future<void> remove(String path) async {}

  @override
  Future<void> removeDir(String path) async {}

  @override
  Future<void> rename(String oldPath, String newPath) async {}
  @override
  Future<int> dirSize(String path) async => 0;

}

/// Error-throwing file system for testing error states.
class ErrorFileSystem implements FileSystem {
  @override
  Future<String> initialDir() async => '/home/test';

  @override
  Future<List<FileEntry>> list(String path) async {
    throw Exception('Permission denied');
  }

  @override
  Future<void> mkdir(String path) async {}

  @override
  Future<void> remove(String path) async {}

  @override
  Future<void> removeDir(String path) async {}

  @override
  Future<void> rename(String oldPath, String newPath) async {}
  @override
  Future<int> dirSize(String path) async => 0;

}

/// Standard test entries used across tests.
List<FileEntry> testEntries() => [
      FileEntry(
        name: 'docs',
        path: '/home/test/docs',
        size: 4096,
        mode: 0x1ED, // 0755
        modTime: DateTime(2024, 1, 1),
        isDir: true,
      ),
      FileEntry(
        name: 'readme.txt',
        path: '/home/test/readme.txt',
        size: 1024,
        mode: 0x1A4, // 0644
        modTime: DateTime(2024, 1, 2),
        isDir: false,
      ),
      FileEntry(
        name: 'script.sh',
        path: '/home/test/script.sh',
        size: 512,
        mode: 0x1ED,
        modTime: DateTime(2024, 1, 3),
        isDir: false,
      ),
    ];

void main() {
  group('MobileFileBrowser — widget rendering', () {
    testWidgets('shows loading state while connection is connecting', (tester) async {
      final connection = Connection(
        id: 'test-1',
        label: 'Test Server',
        sshConfig: const SSHConfig(server: ServerAddress(host: 'example.com', user: 'root')),
        state: SSHConnectionState.connecting,
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: Scaffold(
              body: MobileFileBrowser(connection: connection),
            ),
          ),
        ),
      );

      // Should show loading while waiting for connection
      expect(find.text('Initializing SFTP...'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Stop the connection-wait polling loop before test teardown
      connection.state = SSHConnectionState.disconnected;
      await tester.pumpAndSettle();
    });

    testWidgets('shows error state when connection is disconnected',
        (tester) async {
      final connection = Connection(
        id: 'test-1',
        label: 'Test Server',
        sshConfig: const SSHConfig(server: ServerAddress(host: 'example.com', user: 'root')),
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: Scaffold(
              body: MobileFileBrowser(connection: connection),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.textContaining('Connection failed'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('Retry button is tappable and triggers reinit', (tester) async {
      final connection = Connection(
        id: 'test-1',
        label: 'Test Server',
        sshConfig: const SSHConfig(server: ServerAddress(host: 'example.com', user: 'root')),
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: Scaffold(
              body: MobileFileBrowser(connection: connection),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Retry'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      // After retry fails again, error state is shown again
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });
  });

  group('MobileFileList — rendering', () {
    late FakeFileSystem fakeFs;
    late FilePaneController controller;

    setUp(() {
      fakeFs = FakeFileSystem(fakeEntries: testEntries());
      controller = FilePaneController(fs: fakeFs, label: 'Test');
    });

    tearDown(() {
      controller.dispose();
    });

    Widget buildFileList({
      FilePaneController? ctrl,
      void Function(FileEntry)? onTransfer,
      void Function(List<FileEntry>)? onTransferMultiple,
    }) {
      return ProviderScope(
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: MobileFileList(
              controller: ctrl ?? controller,
              onTransfer: onTransfer ?? (_) {},
              onTransferMultiple: onTransferMultiple ?? (_) {},
            ),
          ),
        ),
      );
    }

    testWidgets('shows empty directory when controller has no entries',
        (tester) async {
      // Don't init controller — entries are empty, loading is false
      await tester.pumpWidget(buildFileList());
      await tester.pump();

      expect(find.text('Empty directory'), findsOneWidget);
    });

    testWidgets('shows empty directory text', (tester) async {
      final emptyFs = FakeFileSystem(fakeEntries: []);
      final emptyCtrl = FilePaneController(fs: emptyFs, label: 'Empty');
      await emptyCtrl.init();

      await tester.pumpWidget(buildFileList(ctrl: emptyCtrl));
      await tester.pump();

      expect(find.text('Empty directory'), findsOneWidget);
      emptyCtrl.dispose();
    });

    testWidgets('shows error state with retry button', (tester) async {
      final errorFs = ErrorFileSystem();
      final errorCtrl = FilePaneController(fs: errorFs, label: 'Error');
      await errorCtrl.init();

      await tester.pumpWidget(buildFileList(ctrl: errorCtrl));
      await tester.pump();

      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.textContaining('Permission denied'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      errorCtrl.dispose();
    });

    testWidgets('renders file list with entries', (tester) async {
      await controller.init();
      await tester.pumpWidget(buildFileList());
      await tester.pump();

      expect(find.text('docs'), findsOneWidget);
      expect(find.text('readme.txt'), findsOneWidget);
      expect(find.text('script.sh'), findsOneWidget);
    });

    testWidgets('shows folder icons for directories', (tester) async {
      await controller.init();
      await tester.pumpWidget(buildFileList());
      await tester.pump();

      expect(find.byIcon(Icons.folder), findsOneWidget);
      expect(find.byIcon(Icons.insert_drive_file), findsWidgets);
    });

    testWidgets('shows file sizes for non-directory entries', (tester) async {
      await controller.init();
      await tester.pumpWidget(buildFileList());
      await tester.pump();

      // readme.txt is 1024 bytes
      expect(find.text(formatSize(1024)), findsOneWidget);
      // script.sh is 512 bytes
      expect(find.text(formatSize(512)), findsOneWidget);
    });

    testWidgets('shows mode strings for entries', (tester) async {
      await controller.init();
      await tester.pumpWidget(buildFileList());
      await tester.pump();

      // Directories have drwxr-xr-x (0755)
      expect(find.text('drwxr-xr-x'), findsOneWidget);
    });

    testWidgets('tapping directory navigates into it', (tester) async {
      await controller.init();
      await tester.pumpWidget(buildFileList());
      await tester.pump();

      await tester.tap(find.text('docs'));
      await tester.pump();

      expect(controller.currentPath, '/home/test/docs');
    });

    testWidgets('tapping file calls onTransfer', (tester) async {
      FileEntry? transferred;
      await controller.init();
      await tester.pumpWidget(buildFileList(
        onTransfer: (entry) => transferred = entry,
      ));
      await tester.pump();

      await tester.tap(find.text('readme.txt'));
      await tester.pump();

      expect(transferred, isNotNull);
      expect(transferred!.name, 'readme.txt');
    });

    testWidgets('long press enters selection mode', (tester) async {
      await controller.init();
      await tester.pumpWidget(buildFileList());
      await tester.pump();

      await tester.longPress(find.text('readme.txt'));
      await tester.pump();

      // Selection mode — checkboxes appear
      expect(find.byType(Checkbox), findsWidgets);
      // Selection bar shows count
      expect(find.text('1 selected'), findsOneWidget);
    });

    testWidgets('selection mode shows transfer and delete buttons',
        (tester) async {
      await controller.init();
      await tester.pumpWidget(buildFileList());
      await tester.pump();

      await tester.longPress(find.text('readme.txt'));
      await tester.pump();

      expect(find.byTooltip('Transfer'), findsOneWidget);
      expect(find.byTooltip('Delete'), findsOneWidget);
    });

    testWidgets('selection bar close button exits selection mode',
        (tester) async {
      await controller.init();
      await tester.pumpWidget(buildFileList());
      await tester.pump();

      await tester.longPress(find.text('readme.txt'));
      await tester.pump();
      expect(find.text('1 selected'), findsOneWidget);

      // Tap close button on selection bar
      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();

      // Selection mode exited — no checkboxes
      expect(find.byType(Checkbox), findsNothing);
      expect(find.text('1 selected'), findsNothing);
    });

    testWidgets('tapping in selection mode toggles selection', (tester) async {
      await controller.init();
      await tester.pumpWidget(buildFileList());
      await tester.pump();

      // Enter selection mode by long pressing
      await tester.longPress(find.text('readme.txt'));
      await tester.pump();
      expect(find.text('1 selected'), findsOneWidget);

      // Tap another entry to add to selection
      await tester.tap(find.text('script.sh'));
      await tester.pump();
      expect(find.text('2 selected'), findsOneWidget);

      // Tap again to deselect
      await tester.tap(find.text('script.sh'));
      await tester.pump();
      expect(find.text('1 selected'), findsOneWidget);
    });

    testWidgets('deselecting all exits selection mode', (tester) async {
      await controller.init();
      await tester.pumpWidget(buildFileList());
      await tester.pump();

      await tester.longPress(find.text('readme.txt'));
      await tester.pump();
      expect(find.text('1 selected'), findsOneWidget);

      // Tap the selected entry to deselect — should exit selection mode
      await tester.tap(find.text('readme.txt'));
      await tester.pump();

      expect(find.byType(Checkbox), findsNothing);
    });

    testWidgets('transfer button in selection bar calls onTransferMultiple',
        (tester) async {
      List<FileEntry>? transferred;
      await controller.init();
      await tester.pumpWidget(buildFileList(
        onTransferMultiple: (entries) => transferred = entries,
      ));
      await tester.pump();

      await tester.longPress(find.text('readme.txt'));
      await tester.pump();

      await tester.tap(find.byTooltip('Transfer'));
      await tester.pump();

      expect(transferred, isNotNull);
      expect(transferred!.length, 1);
      expect(transferred!.first.name, 'readme.txt');
      // Selection mode should be exited
      expect(find.byType(Checkbox), findsNothing);
    });

    testWidgets('long press in selection mode shows bottom sheet actions',
        (tester) async {
      await controller.init();
      await tester.pumpWidget(buildFileList());
      await tester.pump();

      // Enter selection mode
      await tester.longPress(find.text('readme.txt'));
      await tester.pump();

      // Long press again (already in selection mode) shows bottom sheet
      await tester.longPress(find.text('script.sh'));
      await tester.pumpAndSettle();

      // Bottom sheet with actions
      expect(find.text('Transfer'), findsOneWidget);
      expect(find.text('Rename'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
      expect(find.text('New Folder'), findsOneWidget);
    });

    testWidgets('bottom sheet shows Open action for directories',
        (tester) async {
      await controller.init();
      await tester.pumpWidget(buildFileList());
      await tester.pump();

      // Enter selection mode
      await tester.longPress(find.text('readme.txt'));
      await tester.pump();

      // Long press on a directory (already in selection mode)
      await tester.longPress(find.text('docs'));
      await tester.pumpAndSettle();

      expect(find.text('Open'), findsOneWidget);
      expect(find.text('Transfer'), findsOneWidget);
    });

    testWidgets('bottom sheet Transfer action calls onTransfer',
        (tester) async {
      FileEntry? transferred;
      await controller.init();
      await tester.pumpWidget(buildFileList(
        onTransfer: (e) => transferred = e,
      ));
      await tester.pump();

      // Enter selection mode and open bottom sheet
      await tester.longPress(find.text('readme.txt'));
      await tester.pump();
      await tester.longPress(find.text('script.sh'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Transfer'));
      await tester.pumpAndSettle();

      expect(transferred, isNotNull);
      expect(transferred!.name, 'script.sh');
    });

    testWidgets('bottom sheet Open action navigates into dir', (tester) async {
      await controller.init();
      await tester.pumpWidget(buildFileList());
      await tester.pump();

      // Enter selection mode
      await tester.longPress(find.text('readme.txt'));
      await tester.pump();

      // Long press on docs dir to open bottom sheet
      await tester.longPress(find.text('docs'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(controller.currentPath, '/home/test/docs');
    });

    testWidgets('bottom sheet Rename action opens rename dialog',
        (tester) async {
      await controller.init();
      await tester.pumpWidget(buildFileList());
      await tester.pump();

      // Enter selection mode and open bottom sheet
      await tester.longPress(find.text('readme.txt'));
      await tester.pump();
      await tester.longPress(find.text('script.sh'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();

      // Rename dialog should appear
      expect(find.text('Rename'), findsWidgets);
    });

    testWidgets('bottom sheet New Folder action opens new folder dialog',
        (tester) async {
      await controller.init();
      await tester.pumpWidget(buildFileList());
      await tester.pump();

      // Enter selection mode and open bottom sheet
      await tester.longPress(find.text('readme.txt'));
      await tester.pump();
      await tester.longPress(find.text('script.sh'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('New Folder'));
      await tester.pumpAndSettle();

      expect(find.text('Folder name'), findsOneWidget);
    });

    testWidgets('bottom sheet Delete action opens delete confirmation',
        (tester) async {
      await controller.init();
      await tester.pumpWidget(buildFileList());
      await tester.pump();

      // Enter selection mode and open bottom sheet
      await tester.longPress(find.text('readme.txt'));
      await tester.pump();
      await tester.longPress(find.text('script.sh'));
      await tester.pumpAndSettle();

      // Find the Delete text in the bottom sheet (not the toolbar one)
      final deleteItems = find.text('Delete');
      expect(deleteItems, findsWidgets);
      // Tap the last one (bottom sheet)
      await tester.tap(deleteItems.last);
      await tester.pumpAndSettle();

      // Delete confirmation dialog should appear
      expect(find.textContaining('Delete'), findsWidgets);
    });

    testWidgets('delete button in selection bar opens delete confirmation',
        (tester) async {
      await controller.init();
      await tester.pumpWidget(buildFileList());
      await tester.pump();

      // Enter selection mode
      await tester.longPress(find.text('readme.txt'));
      await tester.pump();

      // Tap Delete button in selection bar
      await tester.tap(find.byTooltip('Delete'));
      await tester.pumpAndSettle();

      // Delete confirmation dialog should appear
      expect(find.textContaining('Delete'), findsWidgets);
    });

    testWidgets('checkbox in selection mode toggles selection',
        (tester) async {
      await controller.init();
      await tester.pumpWidget(buildFileList());
      await tester.pump();

      // Enter selection mode
      await tester.longPress(find.text('readme.txt'));
      await tester.pump();

      // Should have checkboxes
      final checkboxes = find.byType(Checkbox);
      expect(checkboxes, findsWidgets);

      // Tap a checkbox to toggle — tap the one for docs (first entry)
      await tester.tap(checkboxes.first);
      await tester.pump();

      // Selection count should change
      expect(find.text('2 selected'), findsOneWidget);
    });

    testWidgets('file list has correct item extent (48px)', (tester) async {
      await controller.init();
      await tester.pumpWidget(buildFileList());
      await tester.pump();

      final listView = tester.widget<ListView>(find.byType(ListView));
      expect(listView.itemExtent, 48.0);
    });

    testWidgets('error state retry button refreshes controller',
        (tester) async {
      final errorFs = ErrorFileSystem();
      final errorCtrl = FilePaneController(fs: errorFs, label: 'Error');
      await errorCtrl.init();

      await tester.pumpWidget(buildFileList(ctrl: errorCtrl));
      await tester.pump();

      expect(find.text('Retry'), findsOneWidget);

      // Tap retry
      await tester.tap(find.text('Retry'));
      await tester.pump();

      // Still in error state (error FS always throws)
      expect(find.textContaining('Permission denied'), findsOneWidget);
      errorCtrl.dispose();
    });

    testWidgets('InkWell rows are present for each entry', (tester) async {
      await controller.init();
      await tester.pumpWidget(buildFileList());
      await tester.pump();

      // 3 entries = 3 InkWell widgets (inside the list)
      expect(find.byType(InkWell), findsNWidgets(3));
    });
  });

  group('FilePaneController', () {
    late FakeFileSystem fakeFs;
    late FilePaneController controller;

    setUp(() {
      fakeFs = FakeFileSystem(fakeEntries: testEntries());
      controller = FilePaneController(fs: fakeFs, label: 'Test');
    });

    test('init navigates to initial directory', () async {
      await controller.init();
      expect(controller.currentPath, '/home/test');
      expect(controller.entries.length, 3);
    });

    test('navigateTo changes path and refreshes', () async {
      await controller.init();
      await controller.navigateTo('/other');
      expect(controller.currentPath, '/other');
    });

    test('navigateUp goes to parent', () async {
      await controller.init();
      await controller.navigateUp();
      expect(controller.currentPath, '/home');
    });

    test('goBack returns to previous path', () async {
      await controller.init();
      await controller.navigateTo('/other');
      expect(controller.canGoBack, isTrue);
      await controller.goBack();
      expect(controller.currentPath, '/home/test');
    });

    test('goForward after goBack', () async {
      await controller.init();
      await controller.navigateTo('/other');
      await controller.goBack();
      expect(controller.canGoForward, isTrue);
      await controller.goForward();
      expect(controller.currentPath, '/other');
    });

    test('selectSingle selects one entry', () async {
      await controller.init();
      controller.selectSingle('/home/test/readme.txt');
      expect(controller.selected, {'/home/test/readme.txt'});
    });

    test('toggleSelect adds and removes', () async {
      await controller.init();
      controller.toggleSelect('/home/test/readme.txt');
      expect(controller.selected.contains('/home/test/readme.txt'), isTrue);
      controller.toggleSelect('/home/test/readme.txt');
      expect(controller.selected.contains('/home/test/readme.txt'), isFalse);
    });

    test('clearSelection clears all', () async {
      await controller.init();
      controller.selectSingle('/home/test/readme.txt');
      controller.clearSelection();
      expect(controller.selected, isEmpty);
    });

    test('selectAll selects all entries', () async {
      await controller.init();
      controller.selectAll();
      expect(controller.selected.length, 3);
    });

    test('selectedEntries returns FileEntry objects', () async {
      await controller.init();
      controller.selectSingle('/home/test/readme.txt');
      expect(controller.selectedEntries.length, 1);
      expect(controller.selectedEntries.first.name, 'readme.txt');
    });

    test('setSort toggles direction on same column', () async {
      await controller.init();
      expect(controller.sortColumn, SortColumn.name);
      expect(controller.sortAscending, isTrue);
      controller.setSort(SortColumn.name);
      expect(controller.sortAscending, isFalse);
    });

    test('setSort changes column', () async {
      await controller.init();
      controller.setSort(SortColumn.size);
      expect(controller.sortColumn, SortColumn.size);
      expect(controller.sortAscending, isTrue);
    });

    test('error state on failed listing', () async {
      final errorFs = ErrorFileSystem();
      final errorCtrl = FilePaneController(fs: errorFs, label: 'Error');
      await errorCtrl.init();
      expect(errorCtrl.error, isNotNull);
      expect(errorCtrl.error, contains('Permission denied'));
      expect(errorCtrl.entries, isEmpty);
      errorCtrl.dispose();
    });

    test('loading state during refresh', () async {
      await controller.init();
      expect(controller.loading, isFalse);
    });

    test('entries sorted directories first', () async {
      await controller.init();
      expect(controller.entries.first.isDir, isTrue);
      expect(controller.entries.first.name, 'docs');
    });

    test('multiple selections work', () async {
      await controller.init();
      controller.toggleSelect('/home/test/readme.txt');
      controller.toggleSelect('/home/test/script.sh');
      expect(controller.selected.length, 2);
      expect(controller.selectedEntries.length, 2);
    });

    test('selectSingle replaces previous selection', () async {
      await controller.init();
      controller.selectSingle('/home/test/readme.txt');
      controller.selectSingle('/home/test/script.sh');
      expect(controller.selected.length, 1);
      expect(controller.selected.first, '/home/test/script.sh');
    });

    test('navigateTo clears selection', () async {
      await controller.init();
      controller.selectSingle('/home/test/readme.txt');
      await controller.navigateTo('/other');
      expect(controller.selected, isEmpty);
    });

    test('refresh keeps current path', () async {
      await controller.init();
      final path = controller.currentPath;
      await controller.refresh();
      expect(controller.currentPath, path);
    });

    test('canGoBack is false initially', () async {
      await controller.init();
      expect(controller.canGoBack, isFalse);
    });

    test('canGoForward is false initially', () async {
      await controller.init();
      expect(controller.canGoForward, isFalse);
    });

    test('setSort by size then by modified', () async {
      await controller.init();
      controller.setSort(SortColumn.size);
      expect(controller.sortColumn, SortColumn.size);
      controller.setSort(SortColumn.modified);
      expect(controller.sortColumn, SortColumn.modified);
      expect(controller.sortAscending, isTrue);
    });

    test('setSort by mode', () async {
      await controller.init();
      controller.setSort(SortColumn.mode);
      expect(controller.sortColumn, SortColumn.mode);
    });

    test('notify listeners on state changes', () async {
      int notifyCount = 0;
      controller.addListener(() => notifyCount++);
      await controller.init();
      expect(notifyCount, greaterThan(0));
    });

    tearDown(() {
      controller.dispose();
    });
  });

  group('Connection model', () {
    test('creates with default disconnected state', () {
      final conn = Connection(
        id: 'test-1',
        label: 'Test Server',
        sshConfig: const SSHConfig(server: ServerAddress(host: 'example.com', user: 'root')),
      );
      expect(conn.state, SSHConnectionState.disconnected);
      expect(conn.isConnected, isFalse);
    });

    test('isConnected returns true when state is connected', () {
      final conn = Connection(
        id: 'test-1',
        label: 'Test Server',
        sshConfig: const SSHConfig(server: ServerAddress(host: 'example.com', user: 'root')),
        state: SSHConnectionState.connected,
      );
      expect(conn.isConnected, isTrue);
    });

    test('stores ssh config', () {
      const config = SSHConfig(server: ServerAddress(host: 'example.com', port: 2222, user: 'admin'));
      final conn = Connection(
        id: 'test-1',
        label: 'My Server',
        sshConfig: config,
      );
      expect(conn.sshConfig.host, 'example.com');
      expect(conn.sshConfig.user, 'admin');
      expect(conn.sshConfig.port, 2222);
      expect(conn.label, 'My Server');
    });

    test('connecting state', () {
      final conn = Connection(
        id: 'test-1',
        label: 'Test',
        sshConfig: const SSHConfig(server: ServerAddress(host: 'h', user: 'u')),
        state: SSHConnectionState.connecting,
      );
      expect(conn.isConnected, isFalse);
      expect(conn.state, SSHConnectionState.connecting);
    });
  });

  group('FileEntry model', () {
    test('modeString for directory with 755', () {
      final entry = FileEntry(
        name: 'docs',
        path: '/docs',
        size: 4096,
        mode: 493,
        modTime: DateTime(2024),
        isDir: true,
      );
      expect(entry.modeString, startsWith('d'));
      expect(entry.modeString.length, 10);
    });

    test('modeString for file with 644', () {
      final entry = FileEntry(
        name: 'file.txt',
        path: '/file.txt',
        size: 100,
        mode: 420,
        modTime: DateTime(2024),
        isDir: false,
      );
      expect(entry.modeString, startsWith('-'));
    });

    test('modeString returns --- for zero mode', () {
      final entry = FileEntry(
        name: 'file.txt',
        path: '/file.txt',
        size: 100,
        mode: 0,
        modTime: DateTime(2024),
        isDir: false,
      );
      expect(entry.modeString, '---');
    });

    test('modeString for file with 777', () {
      final entry = FileEntry(
        name: 'all.sh',
        path: '/all.sh',
        size: 100,
        mode: 511,
        modTime: DateTime(2024),
        isDir: false,
      );
      expect(entry.modeString, '-rwxrwxrwx');
    });

    test('modeString for file with 400', () {
      final entry = FileEntry(
        name: 'readonly.txt',
        path: '/readonly.txt',
        size: 100,
        mode: 256,
        modTime: DateTime(2024),
        isDir: false,
      );
      expect(entry.modeString, '-r--------');
    });

    test('owner field defaults to empty', () {
      final entry = FileEntry(
        name: 'file.txt',
        path: '/file.txt',
        size: 100,
        mode: 420,
        modTime: DateTime(2024),
        isDir: false,
      );
      expect(entry.owner, '');
    });

    test('owner field stores value', () {
      final entry = FileEntry(
        name: 'file.txt',
        path: '/file.txt',
        size: 100,
        mode: 420,
        modTime: DateTime(2024),
        isDir: false,
        owner: 'root',
      );
      expect(entry.owner, 'root');
    });
  });

  group('TransferProgress model', () {
    test('percent calculation', () {
      const progress = TransferProgress(
        fileName: 'test.txt',
        totalBytes: 1000,
        doneBytes: 500,
        isUpload: true,
      );
      expect(progress.percent, 50.0);
    });

    test('percent is 0 when totalBytes is 0', () {
      const progress = TransferProgress(
        fileName: 'test.txt',
        totalBytes: 0,
        doneBytes: 0,
        isUpload: false,
      );
      expect(progress.percent, 0.0);
    });

    test('percent clamped to 100', () {
      const progress = TransferProgress(
        fileName: 'test.txt',
        totalBytes: 100,
        doneBytes: 200,
        isUpload: true,
      );
      expect(progress.percent, 100.0);
    });

    test('isCompleted defaults to false', () {
      const progress = TransferProgress(
        fileName: 'test.txt',
        totalBytes: 100,
        doneBytes: 100,
        isUpload: true,
      );
      expect(progress.isCompleted, isFalse);
    });

    test('isCompleted can be set to true', () {
      const progress = TransferProgress(
        fileName: 'test.txt',
        totalBytes: 100,
        doneBytes: 100,
        isUpload: true,
        isCompleted: true,
      );
      expect(progress.isCompleted, isTrue);
    });

    test('percent at 25%', () {
      const progress = TransferProgress(
        fileName: 'file.bin',
        totalBytes: 400,
        doneBytes: 100,
        isUpload: false,
      );
      expect(progress.percent, 25.0);
    });

    test('download progress', () {
      const progress = TransferProgress(
        fileName: 'data.tar.gz',
        totalBytes: 1048576,
        doneBytes: 524288,
        isUpload: false,
      );
      expect(progress.isUpload, isFalse);
      expect(progress.percent, 50.0);
    });
  });

  group('formatSize utility', () {
    test('formats bytes', () {
      expect(formatSize(100), contains('B'));
    });

    test('formats kilobytes', () {
      expect(formatSize(1024), contains('K'));
    });

    test('formats megabytes', () {
      expect(formatSize(1048576), contains('M'));
    });

    test('formats gigabytes', () {
      expect(formatSize(1073741824), contains('G'));
    });

    test('formats zero', () {
      expect(formatSize(0), isNotEmpty);
    });

    test('formats small file', () {
      expect(formatSize(512), contains('B'));
    });

    test('formats large megabyte value', () {
      expect(formatSize(52428800), contains('M'));
    });
  });
}
