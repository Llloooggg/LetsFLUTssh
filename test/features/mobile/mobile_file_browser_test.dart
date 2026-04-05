import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/connection/connection.dart';
import 'package:letsflutssh/core/sftp/sftp_client.dart';
import 'package:letsflutssh/core/sftp/sftp_models.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/core/transfer/transfer_manager.dart';
import 'package:letsflutssh/features/file_browser/file_browser_controller.dart';
import 'package:letsflutssh/core/sftp/file_system.dart';
import 'package:letsflutssh/features/file_browser/sftp_initializer.dart';
import 'package:letsflutssh/features/mobile/mobile_file_browser.dart';
import 'package:letsflutssh/providers/transfer_provider.dart';
import 'package:letsflutssh/theme/app_theme.dart';
import 'package:letsflutssh/utils/format.dart'; // used by MobileFileList tests
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import '''package:letsflutssh/l10n/app_localizations.dart''';
@GenerateNiceMocks([MockSpec<SftpClient>()])
import 'mobile_file_browser_test.mocks.dart';

/// Fake file system for testing.
class FakeFileSystem implements FileSystem {
  final List<FileEntry> fakeEntries;
  final String fakeInitialDir;
  bool listCalled = false;

  FakeFileSystem({this.fakeEntries = const [], this.fakeInitialDir = '/home/test'});

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
        sshConfig: const SSHConfig(
          server: ServerAddress(host: 'example.com', user: 'root'),
        ),
        state: SSHConnectionState.connecting,
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Scaffold(body: MobileFileBrowser(connection: connection)),
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

    testWidgets('shows error state when connection is disconnected', (tester) async {
      final connection = Connection(
        id: 'test-1',
        label: 'Test Server',
        sshConfig: const SSHConfig(
          server: ServerAddress(host: 'example.com', user: 'root'),
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Scaffold(body: MobileFileBrowser(connection: connection)),
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
        sshConfig: const SSHConfig(
          server: ServerAddress(host: 'example.com', user: 'root'),
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Scaffold(body: MobileFileBrowser(connection: connection)),
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
          localizationsDelegates: S.localizationsDelegates,
          supportedLocales: S.supportedLocales,
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

    testWidgets('shows empty directory when controller has no entries', (tester) async {
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
      await tester.pumpWidget(buildFileList(onTransfer: (entry) => transferred = entry));
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

    testWidgets('selection mode shows transfer and delete buttons', (tester) async {
      await controller.init();
      await tester.pumpWidget(buildFileList());
      await tester.pump();

      await tester.longPress(find.text('readme.txt'));
      await tester.pump();

      expect(find.byTooltip('Transfer'), findsOneWidget);
      expect(find.byTooltip('Delete'), findsOneWidget);
    });

    testWidgets('selection bar close button exits selection mode', (tester) async {
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

    testWidgets('transfer button in selection bar calls onTransferMultiple', (tester) async {
      List<FileEntry>? transferred;
      await controller.init();
      await tester.pumpWidget(buildFileList(onTransferMultiple: (entries) => transferred = entries));
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

    testWidgets('long press in selection mode shows bottom sheet actions', (tester) async {
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

    testWidgets('bottom sheet shows Open action for directories', (tester) async {
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

    testWidgets('bottom sheet Transfer action calls onTransfer', (tester) async {
      FileEntry? transferred;
      await controller.init();
      await tester.pumpWidget(buildFileList(onTransfer: (e) => transferred = e));
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

    testWidgets('bottom sheet Rename action opens rename dialog', (tester) async {
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

    testWidgets('bottom sheet New Folder action opens new folder dialog', (tester) async {
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

      expect(find.text('FOLDER NAME'), findsOneWidget);
    });

    testWidgets('bottom sheet Delete action opens delete confirmation', (tester) async {
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

    testWidgets('delete button in selection bar opens delete confirmation', (tester) async {
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

    testWidgets('checkbox in selection mode toggles selection', (tester) async {
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

    testWidgets('error state retry button refreshes controller', (tester) async {
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

    testWidgets('switching controller resets selection mode and listens to new controller', (tester) async {
      await controller.init();

      final secondFs = FakeFileSystem(
        fakeEntries: [
          FileEntry(
            name: 'other.txt',
            path: '/remote/other.txt',
            size: 256,
            mode: 0x1A4,
            modTime: DateTime(2024, 2, 1),
            isDir: false,
          ),
        ],
      );
      final secondCtrl = FilePaneController(fs: secondFs, label: 'Remote');
      await secondCtrl.init();

      // Build with first controller
      await tester.pumpWidget(buildFileList());
      await tester.pump();

      // Enter selection mode on first controller
      await tester.longPress(find.text('readme.txt'));
      await tester.pump();
      expect(find.byType(Checkbox), findsWidgets);

      // Switch to second controller — selection mode should reset
      await tester.pumpWidget(buildFileList(ctrl: secondCtrl));
      await tester.pump();

      expect(find.byType(Checkbox), findsNothing);
      expect(find.text('other.txt'), findsOneWidget);

      // Verify new controller's updates trigger rebuilds:
      // navigate somewhere (refresh) should still work
      await secondCtrl.refresh();
      await tester.pump();
      expect(find.text('other.txt'), findsOneWidget);

      secondCtrl.dispose();
    });
  });

  // ===========================================================================
  // MobileFileBrowser — success path (injectable factory)
  // ===========================================================================
  group('MobileFileBrowser — success path', () {
    late TransferManager manager;

    setUp(() {
      manager = TransferManager(taskTimeout: Duration.zero);
    });

    tearDown(() {
      manager.dispose();
    });

    Future<SFTPInitResult> fakeInitFactory(Connection conn) async {
      final mockSftp = MockSftpClient();
      when(mockSftp.absolute('.')).thenAnswer((_) async => '/remote');
      when(mockSftp.listdir(any)).thenAnswer((_) async => []);

      final sftpService = SFTPService(mockSftp);
      final localCtrl = FilePaneController(
        fs: FakeFileSystem(fakeEntries: testEntries()),
        label: 'Local',
      );
      final remoteCtrl = FilePaneController(
        fs: FakeFileSystem(fakeEntries: testEntries(), fakeInitialDir: '/remote'),
        label: 'Remote',
      );

      await Future.wait([localCtrl.init(), remoteCtrl.init()]);

      return SFTPInitResult(localCtrl: localCtrl, remoteCtrl: remoteCtrl, sftpService: sftpService);
    }

    Widget buildBrowser(Connection conn) {
      return ProviderScope(
        overrides: [transferManagerProvider.overrideWithValue(manager)],
        child: MaterialApp(
          localizationsDelegates: S.localizationsDelegates,
          supportedLocales: S.supportedLocales,
          theme: AppTheme.dark(),
          home: Scaffold(
            body: MobileFileBrowser(connection: conn, sftpInitFactory: fakeInitFactory),
          ),
        ),
      );
    }

    testWidgets('renders toolbar and file list on success', (tester) async {
      final conn = Connection(
        id: 'success-1',
        label: 'Test',
        sshConfig: const SSHConfig(
          server: ServerAddress(host: 'h', user: 'u'),
        ),
        state: SSHConnectionState.connected,
      );

      await tester.pumpWidget(buildBrowser(conn));
      await tester.pumpAndSettle();

      // Toolbar with Local/Remote toggle
      expect(find.text('Local'), findsOneWidget);
      expect(find.text('Remote'), findsOneWidget);
      // Refresh button
      expect(find.byTooltip('Refresh'), findsOneWidget);
      // Navigation buttons
      expect(find.byTooltip('Back'), findsOneWidget);
      expect(find.byTooltip('Up'), findsOneWidget);
      // File list entries (starts on remote)
      expect(find.text('docs'), findsOneWidget);
      expect(find.text('readme.txt'), findsOneWidget);
    });

    testWidgets('switching Local/Remote toggle changes active pane', (tester) async {
      final conn = Connection(
        id: 'toggle-1',
        label: 'Test',
        sshConfig: const SSHConfig(
          server: ServerAddress(host: 'h', user: 'u'),
        ),
        state: SSHConnectionState.connected,
      );

      await tester.pumpWidget(buildBrowser(conn));
      await tester.pumpAndSettle();

      // Starts on Remote — path should show /remote
      expect(find.text('/remote'), findsOneWidget);

      // Switch to Local
      await tester.tap(find.text('Local'));
      await tester.pumpAndSettle();

      // Path should show local initial dir
      expect(find.text('/home/test'), findsOneWidget);

      // Switch back to Remote
      await tester.tap(find.text('Remote'));
      await tester.pumpAndSettle();

      expect(find.text('/remote'), findsOneWidget);
    });

    testWidgets('TransferPanel is shown below file list', (tester) async {
      final conn = Connection(
        id: 'tp-1',
        label: 'Test',
        sshConfig: const SSHConfig(
          server: ServerAddress(host: 'h', user: 'u'),
        ),
        state: SSHConnectionState.connected,
      );

      await tester.pumpWidget(buildBrowser(conn));
      await tester.pumpAndSettle();

      expect(find.textContaining('Transfers'), findsOneWidget);
    });

    testWidgets('SFTP init failure shows error with retry', (tester) async {
      final conn = Connection(
        id: 'fail-1',
        label: 'Test',
        sshConfig: const SSHConfig(
          server: ServerAddress(host: 'h', user: 'u'),
        ),
        state: SSHConnectionState.connected,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [transferManagerProvider.overrideWithValue(manager)],
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Scaffold(
              body: MobileFileBrowser(
                connection: conn,
                sftpInitFactory: (_) async => throw Exception('SFTP channel failed'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Failed to init SFTP'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('refresh button triggers controller refresh', (tester) async {
      final conn = Connection(
        id: 'refresh-1',
        label: 'Test',
        sshConfig: const SSHConfig(
          server: ServerAddress(host: 'h', user: 'u'),
        ),
        state: SSHConnectionState.connected,
      );

      await tester.pumpWidget(buildBrowser(conn));
      await tester.pumpAndSettle();

      // Tap refresh — should not crash and file list should remain
      await tester.tap(find.byTooltip('Refresh'));
      await tester.pumpAndSettle();

      expect(find.text('docs'), findsOneWidget);
    });
  });

  // ===========================================================================
  // MobileFileList — _confirmDelete exits selection mode
  // ===========================================================================
  group('MobileFileList — delete exits selection', () {
    late FakeFileSystem fakeFs;
    late FilePaneController controller;

    setUp(() {
      fakeFs = FakeFileSystem(fakeEntries: testEntries());
      controller = FilePaneController(fs: fakeFs, label: 'Test');
    });

    tearDown(() {
      controller.dispose();
    });

    Widget buildFileList({void Function(FileEntry)? onTransfer, void Function(List<FileEntry>)? onTransferMultiple}) {
      return ProviderScope(
        child: MaterialApp(
          localizationsDelegates: S.localizationsDelegates,
          supportedLocales: S.supportedLocales,
          theme: AppTheme.dark(),
          home: Scaffold(
            body: MobileFileList(
              controller: controller,
              onTransfer: onTransfer ?? (_) {},
              onTransferMultiple: onTransferMultiple ?? (_) {},
            ),
          ),
        ),
      );
    }

    testWidgets('delete button in selection bar exits selection after confirm dialog', (tester) async {
      await controller.init();
      await tester.pumpWidget(buildFileList());
      await tester.pump();

      // Enter selection mode
      await tester.longPress(find.text('readme.txt'));
      await tester.pump();

      expect(find.byType(Checkbox), findsWidgets);

      // Tap delete button in selection bar
      await tester.tap(find.byTooltip('Delete'));
      await tester.pumpAndSettle();

      // Dismiss the confirm dialog (Cancel)
      if (find.text('Cancel').evaluate().isNotEmpty) {
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
      }

      // Selection mode should be exited after _confirmDelete completes
      expect(find.byType(Checkbox), findsNothing);
    });
  });
}
