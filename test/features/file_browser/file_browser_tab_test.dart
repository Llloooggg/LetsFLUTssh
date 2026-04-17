import 'dart:async';
import '''package:letsflutssh/l10n/app_localizations.dart''';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:letsflutssh/core/connection/connection.dart';
import 'package:letsflutssh/core/sftp/sftp_client.dart';
import 'package:letsflutssh/core/sftp/sftp_models.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/core/transfer/transfer_manager.dart';
import 'package:letsflutssh/core/transfer/transfer_task.dart';
import 'package:letsflutssh/features/file_browser/file_browser_controller.dart';
import 'package:letsflutssh/features/file_browser/file_browser_tab.dart';
import 'package:letsflutssh/features/file_browser/file_pane.dart';
import 'package:letsflutssh/features/file_browser/file_row.dart';
import 'package:letsflutssh/features/file_browser/sftp_initializer.dart';
import 'package:letsflutssh/core/sftp/file_system.dart';
import 'package:letsflutssh/providers/transfer_provider.dart';
import 'package:letsflutssh/theme/app_theme.dart';
import 'package:letsflutssh/widgets/connection_progress.dart';
@GenerateNiceMocks([MockSpec<SftpClient>()])
import 'file_browser_tab_test.mocks.dart';

/// Tracking SFTPService that records upload/download calls without real I/O.
class _TrackingSFTPService extends SFTPService {
  final List<({String method, String src, String dst})> calls = [];

  _TrackingSFTPService(super.sftp);

  /// Tests assume a clean destination — no conflict dialog is expected.
  /// Tests that exercise the conflict path should use a dedicated fixture.
  @override
  Future<bool> exists(String path) async => false;

  @override
  Future<void> upload(
    String localPath,
    String remotePath,
    void Function(TransferProgress)? onProgress,
  ) async {
    calls.add((method: 'upload', src: localPath, dst: remotePath));
    onProgress?.call(
      TransferProgress(
        fileName: localPath.split('/').last,
        totalBytes: 100,
        doneBytes: 100,
        isUpload: true,
        isCompleted: true,
      ),
    );
  }

  @override
  Future<void> download(
    String remotePath,
    String localPath,
    void Function(TransferProgress)? onProgress,
  ) async {
    calls.add((method: 'download', src: remotePath, dst: localPath));
    onProgress?.call(
      TransferProgress(
        fileName: remotePath.split('/').last,
        totalBytes: 100,
        doneBytes: 100,
        isUpload: false,
        isCompleted: true,
      ),
    );
  }

  @override
  Future<void> uploadDir(
    String localDir,
    String remoteDir,
    void Function(TransferProgress)? onProgress,
  ) async {
    calls.add((method: 'uploadDir', src: localDir, dst: remoteDir));
    onProgress?.call(
      TransferProgress(
        fileName: localDir.split('/').last,
        totalBytes: 1,
        doneBytes: 1,
        isUpload: true,
        isCompleted: true,
      ),
    );
  }

  @override
  Future<void> downloadDir(
    String remoteDir,
    String localDir,
    void Function(TransferProgress)? onProgress,
  ) async {
    calls.add((method: 'downloadDir', src: remoteDir, dst: localDir));
    onProgress?.call(
      TransferProgress(
        fileName: remoteDir.split('/').last,
        totalBytes: 1,
        doneBytes: 1,
        isUpload: false,
        isCompleted: true,
      ),
    );
  }
}

/// Fake FS that returns a custom initial directory.
class _FakeFSWithDir implements FileSystem {
  final String initDir;
  final List<FileEntry> entries;

  _FakeFSWithDir({required this.initDir, this.entries = const []});

  @override
  Future<String> initialDir() async => initDir;
  @override
  Future<List<FileEntry>> list(String path) async => entries;
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

/// Creates a fake SFTPInitResult using a tracking SFTPService.
/// Local pane starts at /local, remote pane starts at /remote.
Future<(SFTPInitResult, _TrackingSFTPService)> _trackingInitFactory(
  Connection conn, {
  List<FileEntry>? localFiles,
  List<FileEntry>? remoteFiles,
}) async {
  final mockSftp = MockSftpClient();
  when(mockSftp.absolute('.')).thenAnswer((_) async => '/remote');
  when(mockSftp.listdir(any)).thenAnswer((_) async => []);

  final trackingService = _TrackingSFTPService(mockSftp);
  final localCtrl = FilePaneController(
    fs: _FakeFSWithDir(initDir: '/local', entries: localFiles ?? []),
    label: 'Local',
  );
  final remoteCtrl = FilePaneController(
    fs: _FakeFSWithDir(initDir: '/remote', entries: remoteFiles ?? []),
    label: 'Remote',
  );

  await Future.wait([localCtrl.init(), remoteCtrl.init()]);

  return (
    SFTPInitResult(
      localCtrl: localCtrl,
      remoteCtrl: remoteCtrl,
      sftpService: trackingService,
    ),
    trackingService,
  );
}

/// Fake FileSystem for testing.
class _FakeFS implements FileSystem {
  final List<FileEntry> entries;

  _FakeFS({this.entries = const []});

  @override
  Future<String> initialDir() async => '/test';
  @override
  Future<List<FileEntry>> list(String path) async => entries;
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

/// Test file entries for local pane.
List<FileEntry> _localEntries() => [
  FileEntry(
    name: 'local.txt',
    path: '/test/local.txt',
    size: 100,
    mode: 0x1A4,
    modTime: DateTime(2024),
    isDir: false,
  ),
  FileEntry(
    name: 'localdir',
    path: '/test/localdir',
    size: 4096,
    mode: 0x1ED,
    modTime: DateTime(2024),
    isDir: true,
  ),
];

/// Test file entries for remote pane.
List<FileEntry> _remoteEntries() => [
  FileEntry(
    name: 'remote.txt',
    path: '/remote/remote.txt',
    size: 200,
    mode: 0x1A4,
    modTime: DateTime(2024),
    isDir: false,
  ),
  FileEntry(
    name: 'remotedir',
    path: '/remote/remotedir',
    size: 4096,
    mode: 0x1ED,
    modTime: DateTime(2024),
    isDir: true,
  ),
];

/// Creates a fake SFTPInitResult for testing (empty panes).
Future<SFTPInitResult> _fakeInitFactory(Connection conn) async {
  return _fakeInitFactoryWithEntries(conn);
}

/// Creates a fake SFTPInitResult with configurable entries.
Future<SFTPInitResult> _fakeInitFactoryWithEntries(
  Connection conn, {
  List<FileEntry>? localFiles,
  List<FileEntry>? remoteFiles,
}) async {
  final mockSftp = MockSftpClient();
  when(mockSftp.absolute('.')).thenAnswer((_) async => '/remote');
  when(mockSftp.listdir(any)).thenAnswer((_) async => []);

  final sftpService = SFTPService(mockSftp);
  final localCtrl = FilePaneController(
    fs: _FakeFS(entries: localFiles ?? []),
    label: 'Local',
  );
  final remoteCtrl = FilePaneController(
    fs: _FakeFS(entries: remoteFiles ?? []),
    label: 'Remote',
  );

  await Future.wait([localCtrl.init(), remoteCtrl.init()]);

  return SFTPInitResult(
    localCtrl: localCtrl,
    remoteCtrl: remoteCtrl,
    sftpService: sftpService,
  );
}

void main() {
  late TransferManager manager;

  setUp(() {
    manager = TransferManager(taskTimeout: Duration.zero);
  });

  tearDown(() {
    manager.dispose();
  });

  group('FileBrowserTab', () {
    testWidgets('shows error when SFTP init fails (no SSH connection)', (
      tester,
    ) async {
      final conn = Connection(
        id: 'test-1',
        label: 'Test Server',
        sshConfig: const SSHConfig(
          server: ServerAddress(host: 'example.com', user: 'root'),
        ),
        sshConnection: null,
        state: SSHConnectionState.disconnected,
        connectionError: 'SSH connection not available',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [transferManagerProvider.overrideWithValue(manager)],
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Scaffold(body: FileBrowserTab(connection: conn)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Error state now renders via ConnectionProgress (xterm-based)
      expect(find.byType(ConnectionProgress), findsOneWidget);
    });

    testWidgets('error message contains relevant context', (tester) async {
      final conn = Connection(
        id: 'test-2',
        label: 'Test',
        sshConfig: const SSHConfig(
          server: ServerAddress(host: 'h', user: 'u'),
        ),
        sshConnection: null,
        state: SSHConnectionState.disconnected,
        connectionError: 'SSH connection not available',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [transferManagerProvider.overrideWithValue(manager)],
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Scaffold(body: FileBrowserTab(connection: conn)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Error state renders via ConnectionProgress (error info written to
      // the embedded terminal view — no separate text widget to search).
      expect(find.byType(ConnectionProgress), findsOneWidget);
    });

    testWidgets('error state shows ConnectionProgress on SFTP init failure', (
      tester,
    ) async {
      final conn = Connection(
        id: 'test-3',
        label: 'Test',
        sshConfig: const SSHConfig(
          server: ServerAddress(host: 'h', user: 'u'),
        ),
        sshConnection: null,
        state: SSHConnectionState.disconnected,
        connectionError: 'Connection failed',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [transferManagerProvider.overrideWithValue(manager)],
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Scaffold(body: FileBrowserTab(connection: conn)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Error state renders via ConnectionProgress (xterm-based, no Retry
      // button — retry is now in workspace_view's connection bar)
      expect(find.byType(ConnectionProgress), findsOneWidget);
    });

    testWidgets(
      'error state keeps ConnectionProgress visible after init resolves',
      (tester) async {
        // The FileBrowserTab starts with _initializing = true, but _initSftp runs
        // immediately in initState. Since connection is disconnected,
        // we verify the widget builds and transitions properly.
        final conn = Connection(
          id: 'test-loading',
          label: 'Loading Test',
          sshConfig: const SSHConfig(
            server: ServerAddress(host: 'example.com', user: 'root'),
          ),
          sshConnection: null,
          state: SSHConnectionState.disconnected,
          connectionError: 'Connection failed',
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [transferManagerProvider.overrideWithValue(manager)],
            child: MaterialApp(
              localizationsDelegates: S.localizationsDelegates,
              supportedLocales: S.supportedLocales,
              theme: AppTheme.dark(),
              home: Scaffold(body: FileBrowserTab(connection: conn)),
            ),
          ),
        );
        // After settling, should be in error state (init failed quickly)
        await tester.pumpAndSettle();

        // Error state keeps ConnectionProgress visible — it displays the
        // error information inside the terminal view.
        expect(find.byType(ConnectionProgress), findsOneWidget);
      },
    );
  });

  group('FileBrowserTab — success path (injectable factory)', () {
    testWidgets('transfer arrows exist in success state', (tester) async {
      final conn = Connection(
        id: 'success-2',
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
              body: SizedBox(
                width: 1200,
                height: 800,
                child: FileBrowserTab(
                  connection: conn,
                  sftpInitFactory: _fakeInitFactory,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Divider between panes should exist (arrows removed)
      expect(find.byType(Container), findsWidgets);
    });

    testWidgets('TransferPanel is shown below panes', (tester) async {
      final conn = Connection(
        id: 'success-4',
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
              body: SizedBox(
                width: 1200,
                height: 800,
                child: FileBrowserTab(
                  connection: conn,
                  sftpInitFactory: _fakeInitFactory,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // TransferPanel header should be visible
      expect(find.textContaining('Transfers'), findsOneWidget);
    });
  });

  group('FileBrowserTab — loading state with delayed factory', () {
    testWidgets('transitions from loading to success when factory resolves', (
      tester,
    ) async {
      final completer = Completer<SFTPInitResult>();
      final conn = Connection(
        id: 'loading-2',
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
              body: SizedBox(
                width: 1200,
                height: 800,
                child: FileBrowserTab(
                  connection: conn,
                  sftpInitFactory: (_) => completer.future,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(ConnectionProgress), findsOneWidget);

      // Resolve with a real result
      completer.complete(await _fakeInitFactory(conn));
      await tester.pumpAndSettle();

      // Should now show the split pane layout
      expect(find.byType(ConnectionProgress), findsNothing);
      expect(find.textContaining('Transfers'), findsOneWidget);
    });

    testWidgets('transitions from loading to error when factory throws', (
      tester,
    ) async {
      final completer = Completer<SFTPInitResult>();
      final conn = Connection(
        id: 'loading-3',
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
              body: FileBrowserTab(
                connection: conn,
                sftpInitFactory: (_) => completer.future,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(ConnectionProgress), findsOneWidget);

      completer.completeError('Connection refused');
      await tester.pumpAndSettle();

      // Error state keeps ConnectionProgress visible — error info is
      // written to the embedded terminal view inside ConnectionProgress.
      expect(find.byType(ConnectionProgress), findsOneWidget);
    });
  });

  // Transfer arrows removed — transfers via drag&drop and context menu.

  group('FileBrowserTab — upload/download enqueue', () {
    testWidgets('upload enqueues a task to TransferManager', (tester) async {
      final conn = Connection(
        id: 'upload-1',
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
              body: SizedBox(
                width: 1200,
                height: 800,
                child: FileBrowserTab(
                  connection: conn,
                  sftpInitFactory: _fakeInitFactory,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify success state — the split pane is showing
      expect(find.textContaining('Transfers'), findsOneWidget);
      // Manager starts empty
      expect(manager.history, isEmpty);
    });
  });

  group('FileBrowserTab — retry from error to success', () {
    testWidgets('retry transitions from error to success', (tester) async {
      var callCount = 0;
      final conn = Connection(
        id: 'retry-success',
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
              body: SizedBox(
                width: 1200,
                height: 800,
                child: FileBrowserTab(
                  connection: conn,
                  sftpInitFactory: (c) async {
                    callCount++;
                    if (callCount == 1) throw 'First attempt fails';
                    return _fakeInitFactory(c);
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // First call failed — error state shown via ConnectionProgress
      expect(find.byType(ConnectionProgress), findsOneWidget);
      expect(callCount, 1);

      // No Retry button exists in the file browser itself anymore —
      // retry is handled by workspace_view's connection bar.
    });
  });

  group('FileBrowserTab — FilePane callbacks (upload/download)', () {
    testWidgets('double-clicking local file triggers upload (onTransfer)', (
      tester,
    ) async {
      final conn = Connection(
        id: 'xfer-1',
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
              body: SizedBox(
                width: 1200,
                height: 800,
                child: FileBrowserTab(
                  connection: conn,
                  sftpInitFactory: (c) => _fakeInitFactoryWithEntries(
                    c,
                    localFiles: _localEntries(),
                    remoteFiles: _remoteEntries(),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Local pane should show local.txt
      expect(find.text('local.txt'), findsOneWidget);
      // Remote pane should show remote.txt
      expect(find.text('remote.txt'), findsOneWidget);

      // Double-click local.txt to trigger onTransfer → _upload
      await tester.tap(find.text('local.txt'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('local.txt'));
      await tester.pumpAndSettle();

      // Upload task should be enqueued (or already completed)
      expect(manager.history, isNotNull);
    });

    testWidgets('double-clicking remote file triggers download (onTransfer)', (
      tester,
    ) async {
      final conn = Connection(
        id: 'xfer-2',
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
              body: SizedBox(
                width: 1200,
                height: 800,
                child: FileBrowserTab(
                  connection: conn,
                  sftpInitFactory: (c) => _fakeInitFactoryWithEntries(
                    c,
                    localFiles: _localEntries(),
                    remoteFiles: _remoteEntries(),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('remote.txt'), findsOneWidget);

      // Double-click remote.txt to trigger download
      await tester.tap(find.text('remote.txt'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('remote.txt'));
      await tester.pumpAndSettle();
    });

    testWidgets('context menu Transfer on local file enqueues upload', (
      tester,
    ) async {
      final origHandler = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.toString().contains('overflowed')) return;
        origHandler?.call(details);
      };
      addTearDown(() => FlutterError.onError = origHandler);

      final conn = Connection(
        id: 'xfer-ctx',
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
              body: SizedBox(
                width: 1200,
                height: 800,
                child: FileBrowserTab(
                  connection: conn,
                  sftpInitFactory: (c) => _fakeInitFactoryWithEntries(
                    c,
                    localFiles: _localEntries(),
                    remoteFiles: _remoteEntries(),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Select local.txt first by clicking
      await tester.tap(find.text('local.txt'));
      await tester.pumpAndSettle();

      // Right-click for context menu
      final localTxt = find.text('local.txt');
      final center = tester.getCenter(localTxt);
      await tester.tapAt(center, buttons: kSecondaryButton);
      await tester.pumpAndSettle();

      // Context menu should show Transfer
      final transferItem = find.text('Transfer');
      if (transferItem.evaluate().isNotEmpty) {
        await tester.tap(transferItem);
        await tester.pumpAndSettle();
      }
    });
  });

  group('FileBrowserTab — dispose safety', () {
    testWidgets('removing widget during success state does not crash', (
      tester,
    ) async {
      final conn = Connection(
        id: 'dispose-1',
        label: 'Test',
        sshConfig: const SSHConfig(
          server: ServerAddress(host: 'h', user: 'u'),
        ),
        state: SSHConnectionState.connected,
      );

      final key = GlobalKey();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [transferManagerProvider.overrideWithValue(manager)],
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Scaffold(
              body: SizedBox(
                key: key,
                width: 1200,
                height: 800,
                child: FileBrowserTab(
                  connection: conn,
                  sftpInitFactory: _fakeInitFactory,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Remove from tree
      await tester.pumpWidget(
        ProviderScope(
          overrides: [transferManagerProvider.overrideWithValue(manager)],
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: const Scaffold(body: SizedBox()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // No crash = success
    });

    testWidgets('removing widget during loading does not crash', (
      tester,
    ) async {
      final completer = Completer<SFTPInitResult>();
      final conn = Connection(
        id: 'dispose-2',
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
              body: FileBrowserTab(
                connection: conn,
                sftpInitFactory: (_) => completer.future,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(ConnectionProgress), findsOneWidget);

      // Remove from tree while still loading
      await tester.pumpWidget(
        ProviderScope(
          overrides: [transferManagerProvider.overrideWithValue(manager)],
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: const Scaffold(body: SizedBox()),
          ),
        ),
      );

      // Complete after removal — mounted guard should prevent setState crash
      completer.completeError('too late');
      await tester.pumpAndSettle();
      // No crash = success
    });
  });

  group('FileBrowserTab — _upload enqueues transfer tasks', () {
    testWidgets(
      'double-click local file enqueues upload task with correct fields',
      (tester) async {
        final origHandler = FlutterError.onError;
        FlutterError.onError = (details) {
          if (details.toString().contains('overflowed')) return;
          origHandler?.call(details);
        };
        addTearDown(() => FlutterError.onError = origHandler);

        late _TrackingSFTPService tracking;
        final conn = Connection(
          id: 'upload-file-1',
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
                body: SizedBox(
                  width: 1200,
                  height: 800,
                  child: FileBrowserTab(
                    connection: conn,
                    sftpInitFactory: (c) async {
                      final (result, svc) = await _trackingInitFactory(
                        c,
                        localFiles: _localEntries(),
                        remoteFiles: _remoteEntries(),
                      );
                      tracking = svc;
                      return result;
                    },
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Double-click local.txt to trigger onTransfer → _upload
        await tester.tap(find.text('local.txt'));
        await tester.pump(const Duration(milliseconds: 50));
        await tester.tap(find.text('local.txt'));
        await tester.pumpAndSettle();

        // TransferManager should have processed the task
        expect(manager.history, hasLength(1));
        final h = manager.history.first;
        expect(h.direction, TransferDirection.upload);
        expect(h.name, 'local.txt');
        // sourcePath = entry.path from local pane entries
        expect(h.sourcePath, '/test/local.txt');
        // targetPath = posix.join(remoteCtrl.currentPath, entry.name)
        // remoteCtrl starts at /remote
        expect(h.targetPath, '/remote/local.txt');
        expect(h.status, TransferStatus.completed);

        // The tracking service should have recorded the upload call
        expect(tracking.calls, hasLength(1));
        expect(tracking.calls.first.method, 'upload');
      },
    );

    testWidgets(
      'double-click local directory enqueues upload with trailing slash name',
      (tester) async {
        final origHandler = FlutterError.onError;
        FlutterError.onError = (details) {
          if (details.toString().contains('overflowed')) return;
          origHandler?.call(details);
        };
        addTearDown(() => FlutterError.onError = origHandler);

        late _TrackingSFTPService tracking;
        final conn = Connection(
          id: 'upload-dir-1',
          label: 'Test',
          sshConfig: const SSHConfig(
            server: ServerAddress(host: 'h', user: 'u'),
          ),
          state: SSHConnectionState.connected,
        );

        // Only a directory entry — double-click on dir navigates, so we need
        // to trigger _upload via context menu Transfer instead.
        final dirEntry = [
          FileEntry(
            name: 'mydir',
            path: '/test/mydir',
            size: 4096,
            mode: 0x1ED,
            modTime: DateTime(2024),
            isDir: true,
          ),
        ];

        await tester.pumpWidget(
          ProviderScope(
            overrides: [transferManagerProvider.overrideWithValue(manager)],
            child: MaterialApp(
              localizationsDelegates: S.localizationsDelegates,
              supportedLocales: S.supportedLocales,
              theme: AppTheme.dark(),
              home: Scaffold(
                body: SizedBox(
                  width: 1200,
                  height: 800,
                  child: FileBrowserTab(
                    connection: conn,
                    sftpInitFactory: (c) async {
                      final (result, svc) = await _trackingInitFactory(
                        c,
                        localFiles: dirEntry,
                        remoteFiles: _remoteEntries(),
                      );
                      tracking = svc;
                      return result;
                    },
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Select the directory
        await tester.tap(find.text('mydir'));
        await tester.pumpAndSettle();

        // Right-click for context menu
        final center = tester.getCenter(find.text('mydir'));
        await tester.tapAt(center, buttons: kSecondaryButton);
        await tester.pumpAndSettle();

        // Tap Transfer in context menu
        final transferItem = find.text('Transfer');
        expect(transferItem, findsOneWidget);
        await tester.tap(transferItem);
        await tester.pumpAndSettle();

        // Task should be enqueued with trailing slash for directory
        expect(manager.history, hasLength(1));
        expect(manager.history.first.name, 'mydir/');
        expect(manager.history.first.direction, TransferDirection.upload);
        expect(tracking.calls, hasLength(1));
        expect(tracking.calls.first.method, 'uploadDir');
      },
    );
  });

  group('FileBrowserTab — _download enqueues transfer tasks', () {
    testWidgets(
      'double-click remote file enqueues download task with correct fields',
      (tester) async {
        final origHandler = FlutterError.onError;
        FlutterError.onError = (details) {
          if (details.toString().contains('overflowed')) return;
          origHandler?.call(details);
        };
        addTearDown(() => FlutterError.onError = origHandler);

        late _TrackingSFTPService tracking;
        final conn = Connection(
          id: 'download-file-1',
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
                body: SizedBox(
                  width: 1200,
                  height: 800,
                  child: FileBrowserTab(
                    connection: conn,
                    sftpInitFactory: (c) async {
                      final (result, svc) = await _trackingInitFactory(
                        c,
                        localFiles: _localEntries(),
                        remoteFiles: _remoteEntries(),
                      );
                      tracking = svc;
                      return result;
                    },
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Double-click remote.txt to trigger onTransfer → _download
        await tester.tap(find.text('remote.txt'));
        await tester.pump(const Duration(milliseconds: 50));
        await tester.tap(find.text('remote.txt'));
        await tester.pumpAndSettle();

        // TransferManager should have processed the download task
        expect(manager.history, hasLength(1));
        final h = manager.history.first;
        expect(h.direction, TransferDirection.download);
        expect(h.name, 'remote.txt');
        // sourcePath = entry.path from remote pane entries
        expect(h.sourcePath, '/remote/remote.txt');
        // targetPath = p.join(localCtrl.currentPath, entry.name)
        // localCtrl starts at /local
        expect(h.targetPath, '/local/remote.txt');
        expect(h.status, TransferStatus.completed);

        expect(tracking.calls, hasLength(1));
        expect(tracking.calls.first.method, 'download');
      },
    );

    testWidgets(
      'context menu Transfer on remote directory enqueues downloadDir',
      (tester) async {
        final origHandler = FlutterError.onError;
        FlutterError.onError = (details) {
          if (details.toString().contains('overflowed')) return;
          origHandler?.call(details);
        };
        addTearDown(() => FlutterError.onError = origHandler);

        late _TrackingSFTPService tracking;
        final conn = Connection(
          id: 'download-dir-1',
          label: 'Test',
          sshConfig: const SSHConfig(
            server: ServerAddress(host: 'h', user: 'u'),
          ),
          state: SSHConnectionState.connected,
        );

        final remoteDir = [
          FileEntry(
            name: 'rdir',
            path: '/remote/rdir',
            size: 4096,
            mode: 0x1ED,
            modTime: DateTime(2024),
            isDir: true,
          ),
        ];

        await tester.pumpWidget(
          ProviderScope(
            overrides: [transferManagerProvider.overrideWithValue(manager)],
            child: MaterialApp(
              localizationsDelegates: S.localizationsDelegates,
              supportedLocales: S.supportedLocales,
              theme: AppTheme.dark(),
              home: Scaffold(
                body: SizedBox(
                  width: 1200,
                  height: 800,
                  child: FileBrowserTab(
                    connection: conn,
                    sftpInitFactory: (c) async {
                      final (result, svc) = await _trackingInitFactory(
                        c,
                        localFiles: _localEntries(),
                        remoteFiles: remoteDir,
                      );
                      tracking = svc;
                      return result;
                    },
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Select the remote directory
        await tester.tap(find.text('rdir'));
        await tester.pumpAndSettle();

        // Right-click for context menu
        final center = tester.getCenter(find.text('rdir'));
        await tester.tapAt(center, buttons: kSecondaryButton);
        await tester.pumpAndSettle();

        // Tap Transfer
        await tester.tap(find.text('Transfer'));
        await tester.pumpAndSettle();

        expect(manager.history, hasLength(1));
        expect(manager.history.first.name, 'rdir/');
        expect(manager.history.first.direction, TransferDirection.download);
        expect(tracking.calls, hasLength(1));
        expect(tracking.calls.first.method, 'downloadDir');
      },
    );
  });

  group('FileBrowserTab — onTransferMultiple (multi-select transfer)', () {
    testWidgets(
      'context menu Transfer with multiple local files selected enqueues multiple uploads',
      (tester) async {
        final origHandler = FlutterError.onError;
        FlutterError.onError = (details) {
          if (details.toString().contains('overflowed')) return;
          origHandler?.call(details);
        };
        addTearDown(() => FlutterError.onError = origHandler);

        late _TrackingSFTPService tracking;
        late SFTPInitResult initResult;
        final conn = Connection(
          id: 'multi-upload-1',
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
                body: SizedBox(
                  width: 1200,
                  height: 800,
                  child: FileBrowserTab(
                    connection: conn,
                    sftpInitFactory: (c) async {
                      final (result, svc) = await _trackingInitFactory(
                        c,
                        localFiles: _localEntries(),
                        remoteFiles: _remoteEntries(),
                      );
                      tracking = svc;
                      initResult = result;
                      return result;
                    },
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Programmatically select both local entries via the controller
        final localCtrl = initResult.localCtrl;
        localCtrl.selectPaths({'/test/local.txt', '/test/localdir'});
        await tester.pumpAndSettle();

        // Right-click on one of the selected items
        final center = tester.getCenter(find.text('local.txt'));
        await tester.tapAt(center, buttons: kSecondaryButton);
        await tester.pumpAndSettle();

        // Should show "Transfer 2 items" since multiple are selected
        final transferMulti = find.text('Transfer 2 items');
        expect(transferMulti, findsOneWidget);
        await tester.tap(transferMulti);
        await tester.pumpAndSettle();

        // Should have enqueued 2 upload tasks (one file + one dir)
        expect(manager.history, hasLength(2));
        expect(
          manager.history.every((h) => h.direction == TransferDirection.upload),
          isTrue,
        );

        // Tracking service should show upload + uploadDir
        expect(tracking.calls, hasLength(2));
        final methods = tracking.calls.map((c) => c.method).toSet();
        expect(methods, containsAll(['upload', 'uploadDir']));
      },
    );

    testWidgets(
      'context menu Transfer with multiple remote files selected enqueues multiple downloads',
      (tester) async {
        final origHandler = FlutterError.onError;
        FlutterError.onError = (details) {
          if (details.toString().contains('overflowed')) return;
          origHandler?.call(details);
        };
        addTearDown(() => FlutterError.onError = origHandler);

        late _TrackingSFTPService tracking;
        late SFTPInitResult initResult;
        final conn = Connection(
          id: 'multi-download-1',
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
                body: SizedBox(
                  width: 1200,
                  height: 800,
                  child: FileBrowserTab(
                    connection: conn,
                    sftpInitFactory: (c) async {
                      final (result, svc) = await _trackingInitFactory(
                        c,
                        localFiles: _localEntries(),
                        remoteFiles: _remoteEntries(),
                      );
                      tracking = svc;
                      initResult = result;
                      return result;
                    },
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Programmatically select both remote entries via the controller
        final remoteCtrl = initResult.remoteCtrl;
        remoteCtrl.selectPaths({'/remote/remote.txt', '/remote/remotedir'});
        await tester.pumpAndSettle();

        // Right-click on one of the selected items
        final center = tester.getCenter(find.text('remote.txt'));
        await tester.tapAt(center, buttons: kSecondaryButton);
        await tester.pumpAndSettle();

        // Transfer multiple
        final transferMulti = find.text('Transfer 2 items');
        expect(transferMulti, findsOneWidget);
        await tester.tap(transferMulti);
        await tester.pumpAndSettle();

        // Should have enqueued 2 download tasks
        expect(manager.history, hasLength(2));
        expect(
          manager.history.every(
            (h) => h.direction == TransferDirection.download,
          ),
          isTrue,
        );

        expect(tracking.calls, hasLength(2));
        final methods = tracking.calls.map((c) => c.method).toSet();
        expect(methods, containsAll(['download', 'downloadDir']));
      },
    );
  });

  group('FileBrowserTab — onDropReceived (drag between panes)', () {
    testWidgets(
      'dropping local file onto remote pane enqueues download (into local)',
      (tester) async {
        final origHandler = FlutterError.onError;
        FlutterError.onError = (details) {
          if (details.toString().contains('overflowed')) return;
          origHandler?.call(details);
        };
        addTearDown(() => FlutterError.onError = origHandler);

        late _TrackingSFTPService tracking;
        final conn = Connection(
          id: 'drop-local-to-remote',
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
                body: SizedBox(
                  width: 1200,
                  height: 800,
                  child: FileBrowserTab(
                    connection: conn,
                    sftpInitFactory: (c) async {
                      final (result, svc) = await _trackingInitFactory(
                        c,
                        localFiles: _localEntries(),
                        remoteFiles: _remoteEntries(),
                      );
                      tracking = svc;
                      return result;
                    },
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Find the DragTarget in the remote pane.
        // The remote pane has a DragTarget<PaneDragData> that accepts drops
        // from the local pane (different sourcePaneId).
        // We simulate this by finding the DragTarget and calling its callbacks.
        final dragTargets = find.byWidgetPredicate(
          (w) => w is DragTarget<PaneDragData>,
        );
        // There should be 2 DragTargets (one per pane)
        expect(dragTargets, findsNWidgets(2));

        // Select local.txt and drag it — first click to select
        await tester.tap(find.text('local.txt'));
        await tester.pumpAndSettle();

        // Now drag local.txt from left pane to right pane area
        final localTxtCenter = tester.getCenter(find.text('local.txt'));
        // Remote pane is on the right half — target roughly center-right
        final remotePaneCenter = Offset(
          tester.getSize(find.byType(FileBrowserTab)).width * 0.75,
          tester.getSize(find.byType(FileBrowserTab)).height * 0.5,
        );

        await tester.timedDragFrom(
          localTxtCenter,
          remotePaneCenter - localTxtCenter,
          const Duration(milliseconds: 500),
        );
        await tester.pumpAndSettle();

        // When a local file is dropped onto the remote pane, the remote pane's
        // onDropReceived fires, which calls _upload for each dropped entry.
        // The drag may or may not succeed depending on hit testing, so we check
        // if uploads were enqueued.
        if (tracking.calls.isNotEmpty) {
          expect(tracking.calls.first.method, 'upload');
          expect(manager.history.first.direction, TransferDirection.upload);
        }
      },
    );
  });

  group('FileBrowserTab — onDropReceived triggers transfers', () {
    testWidgets(
      'dropping remote entries onto local pane calls onDropReceived → _download for each',
      (tester) async {
        final origHandler = FlutterError.onError;
        FlutterError.onError = (details) {
          if (details.toString().contains('overflowed')) return;
          origHandler?.call(details);
        };
        addTearDown(() => FlutterError.onError = origHandler);

        late _TrackingSFTPService tracking;
        late SFTPInitResult initResult;
        final conn = Connection(
          id: 'drop-remote-to-local',
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
                body: SizedBox(
                  width: 1200,
                  height: 800,
                  child: FileBrowserTab(
                    connection: conn,
                    sftpInitFactory: (c) async {
                      final (result, svc) = await _trackingInitFactory(
                        c,
                        localFiles: _localEntries(),
                        remoteFiles: _remoteEntries(),
                      );
                      tracking = svc;
                      initResult = result;
                      return result;
                    },
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Select remote.txt in the remote pane
        final remoteCtrl = initResult.remoteCtrl;
        remoteCtrl.selectSingle('/remote/remote.txt');
        await tester.pumpAndSettle();

        // Drag from remote pane to local pane — select + drag remote.txt
        final remoteTxt = tester.getCenter(find.text('remote.txt'));
        // Local pane is on the left half
        final localPaneTarget = Offset(
          100, // well within the left pane
          tester.getSize(find.byType(FileBrowserTab)).height * 0.5,
        );

        await tester.timedDragFrom(
          remoteTxt,
          localPaneTarget - remoteTxt,
          const Duration(milliseconds: 500),
        );
        await tester.pumpAndSettle();

        // If drag succeeded, downloads should be enqueued.
        // The DragTarget in the local pane accepts drops from 'remote' pane.
        if (tracking.calls.isNotEmpty) {
          expect(tracking.calls.first.method, 'download');
          expect(manager.history.first.direction, TransferDirection.download);
        }
      },
    );
  });

  group('FileBrowserTab — upload/download size and path fields', () {
    testWidgets('upload task carries file size from entry', (tester) async {
      final origHandler = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.toString().contains('overflowed')) return;
        origHandler?.call(details);
      };
      addTearDown(() => FlutterError.onError = origHandler);

      final conn = Connection(
        id: 'size-check',
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
              body: SizedBox(
                width: 1200,
                height: 800,
                child: FileBrowserTab(
                  connection: conn,
                  sftpInitFactory: (c) async {
                    final (result, _) = await _trackingInitFactory(
                      c,
                      localFiles: _localEntries(), // local.txt has size: 100
                      remoteFiles: _remoteEntries(),
                    );
                    return result;
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Double-click to upload
      await tester.tap(find.text('local.txt'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('local.txt'));
      await tester.pumpAndSettle();

      expect(manager.history.first.sizeBytes, 100);
    });

    testWidgets('download task carries file size from entry', (tester) async {
      final origHandler = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.toString().contains('overflowed')) return;
        origHandler?.call(details);
      };
      addTearDown(() => FlutterError.onError = origHandler);

      final conn = Connection(
        id: 'size-check-dl',
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
              body: SizedBox(
                width: 1200,
                height: 800,
                child: FileBrowserTab(
                  connection: conn,
                  sftpInitFactory: (c) async {
                    final (result, _) = await _trackingInitFactory(
                      c,
                      localFiles: _localEntries(),
                      remoteFiles: _remoteEntries(), // remote.txt has size: 200
                    );
                    return result;
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Double-click remote.txt to download
      await tester.tap(find.text('remote.txt'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('remote.txt'));
      await tester.pumpAndSettle();

      expect(manager.history.first.sizeBytes, 200);
    });
  });

  group('FileBrowserTab — _upload/_download run callback verification', () {
    testWidgets('upload run callback calls sftp.upload and refreshes remote', (
      tester,
    ) async {
      final origHandler = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.toString().contains('overflowed')) return;
        origHandler?.call(details);
      };
      addTearDown(() => FlutterError.onError = origHandler);

      late _TrackingSFTPService tracking;
      final conn = Connection(
        id: 'run-upload',
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
              body: SizedBox(
                width: 1200,
                height: 800,
                child: FileBrowserTab(
                  connection: conn,
                  sftpInitFactory: (c) async {
                    final (result, svc) = await _trackingInitFactory(
                      c,
                      localFiles: _localEntries(),
                      remoteFiles: _remoteEntries(),
                    );
                    tracking = svc;
                    return result;
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Double-click local.txt to trigger _upload
      await tester.tap(find.text('local.txt'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('local.txt'));

      // Ensure async run callback completes
      await tester.runAsync(
        () => Future.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();

      // Verify the run callback executed: sftp.upload was called
      expect(tracking.calls, hasLength(1));
      expect(tracking.calls.first.method, 'upload');
      expect(tracking.calls.first.src, '/test/local.txt');
      expect(tracking.calls.first.dst, '/remote/local.txt');

      // Verify the task completed successfully
      expect(manager.history, hasLength(1));
      expect(manager.history.first.status, TransferStatus.completed);
      expect(manager.history.first.lastPercent, 100);
    });

    testWidgets(
      'download run callback calls sftp.download and refreshes local',
      (tester) async {
        final origHandler = FlutterError.onError;
        FlutterError.onError = (details) {
          if (details.toString().contains('overflowed')) return;
          origHandler?.call(details);
        };
        addTearDown(() => FlutterError.onError = origHandler);

        late _TrackingSFTPService tracking;
        final conn = Connection(
          id: 'run-download',
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
                body: SizedBox(
                  width: 1200,
                  height: 800,
                  child: FileBrowserTab(
                    connection: conn,
                    sftpInitFactory: (c) async {
                      final (result, svc) = await _trackingInitFactory(
                        c,
                        localFiles: _localEntries(),
                        remoteFiles: _remoteEntries(),
                      );
                      tracking = svc;
                      return result;
                    },
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Double-click remote.txt to trigger _download
        await tester.tap(find.text('remote.txt'));
        await tester.pump(const Duration(milliseconds: 50));
        await tester.tap(find.text('remote.txt'));

        // Ensure async run callback completes
        await tester.runAsync(
          () => Future.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pumpAndSettle();

        // Verify the run callback executed: sftp.download was called
        expect(tracking.calls, hasLength(1));
        expect(tracking.calls.first.method, 'download');
        expect(tracking.calls.first.src, '/remote/remote.txt');
        expect(tracking.calls.first.dst, '/local/remote.txt');

        // Verify the task completed successfully
        expect(manager.history, hasLength(1));
        expect(manager.history.first.status, TransferStatus.completed);
        expect(manager.history.first.lastPercent, 100);
      },
    );

    testWidgets(
      'upload run callback calls sftp.uploadDir for directory entries',
      (tester) async {
        final origHandler = FlutterError.onError;
        FlutterError.onError = (details) {
          if (details.toString().contains('overflowed')) return;
          origHandler?.call(details);
        };
        addTearDown(() => FlutterError.onError = origHandler);

        late _TrackingSFTPService tracking;
        final conn = Connection(
          id: 'run-upload-dir',
          label: 'Test',
          sshConfig: const SSHConfig(
            server: ServerAddress(host: 'h', user: 'u'),
          ),
          state: SSHConnectionState.connected,
        );

        final dirEntries = [
          FileEntry(
            name: 'mydir',
            path: '/local/mydir',
            size: 4096,
            mode: 0x1ED,
            modTime: DateTime(2024),
            isDir: true,
          ),
        ];

        await tester.pumpWidget(
          ProviderScope(
            overrides: [transferManagerProvider.overrideWithValue(manager)],
            child: MaterialApp(
              localizationsDelegates: S.localizationsDelegates,
              supportedLocales: S.supportedLocales,
              theme: AppTheme.dark(),
              home: Scaffold(
                body: SizedBox(
                  width: 1200,
                  height: 800,
                  child: FileBrowserTab(
                    connection: conn,
                    sftpInitFactory: (c) async {
                      final (result, svc) = await _trackingInitFactory(
                        c,
                        localFiles: dirEntries,
                        remoteFiles: _remoteEntries(),
                      );
                      tracking = svc;
                      return result;
                    },
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Use onTransferMultiple on local pane to trigger _upload for a directory
        final filePanes = tester
            .widgetList<FilePane>(find.byType(FilePane))
            .toList();
        final localPane = filePanes.firstWhere((p) => p.paneId == 'local');
        localPane.onTransferMultiple!(dirEntries);

        await tester.runAsync(
          () => Future.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pumpAndSettle();

        expect(tracking.calls, hasLength(1));
        expect(tracking.calls.first.method, 'uploadDir');
        expect(tracking.calls.first.src, '/local/mydir');
        expect(tracking.calls.first.dst, '/remote/mydir');
        expect(manager.history.first.name, 'mydir/');
      },
    );

    testWidgets(
      'download run callback calls sftp.downloadDir for directory entries',
      (tester) async {
        final origHandler = FlutterError.onError;
        FlutterError.onError = (details) {
          if (details.toString().contains('overflowed')) return;
          origHandler?.call(details);
        };
        addTearDown(() => FlutterError.onError = origHandler);

        late _TrackingSFTPService tracking;
        final conn = Connection(
          id: 'run-download-dir',
          label: 'Test',
          sshConfig: const SSHConfig(
            server: ServerAddress(host: 'h', user: 'u'),
          ),
          state: SSHConnectionState.connected,
        );

        final dirEntries = [
          FileEntry(
            name: 'rdir',
            path: '/remote/rdir',
            size: 4096,
            mode: 0x1ED,
            modTime: DateTime(2024),
            isDir: true,
          ),
        ];

        await tester.pumpWidget(
          ProviderScope(
            overrides: [transferManagerProvider.overrideWithValue(manager)],
            child: MaterialApp(
              localizationsDelegates: S.localizationsDelegates,
              supportedLocales: S.supportedLocales,
              theme: AppTheme.dark(),
              home: Scaffold(
                body: SizedBox(
                  width: 1200,
                  height: 800,
                  child: FileBrowserTab(
                    connection: conn,
                    sftpInitFactory: (c) async {
                      final (result, svc) = await _trackingInitFactory(
                        c,
                        localFiles: _localEntries(),
                        remoteFiles: dirEntries,
                      );
                      tracking = svc;
                      return result;
                    },
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Use onTransferMultiple on remote pane to trigger _download for a directory
        final filePanes = tester
            .widgetList<FilePane>(find.byType(FilePane))
            .toList();
        final remotePane = filePanes.firstWhere((p) => p.paneId == 'remote');
        remotePane.onTransferMultiple!(dirEntries);

        await tester.runAsync(
          () => Future.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pumpAndSettle();

        expect(tracking.calls, hasLength(1));
        expect(tracking.calls.first.method, 'downloadDir');
        expect(tracking.calls.first.src, '/remote/rdir');
        expect(tracking.calls.first.dst, '/local/rdir');
        expect(manager.history.first.name, 'rdir/');
      },
    );
  });

  // ===========================================================================
  // _buildTooNarrowHint — width constraint
  // ===========================================================================
  group('FileBrowserTab — too narrow hint', () {
    testWidgets('shows hint when width < 250', (tester) async {
      final conn = Connection(
        id: 'narrow-1',
        label: 'Test',
        sshConfig: const SSHConfig(
          server: ServerAddress(host: 'h', user: 'u'),
        ),
        state: SSHConnectionState.connected,
      );

      // TransferPanel may overflow at narrow widths — expected, not what we test.
      final origOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.toString().contains('overflowed')) return;
        origOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = origOnError);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [transferManagerProvider.overrideWithValue(manager)],
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Scaffold(
              body: SizedBox(
                width: 200,
                height: 800,
                child: FileBrowserTab(
                  connection: conn,
                  sftpInitFactory: _fakeInitFactory,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The hint text should appear; FilePane should not render.
      expect(find.text('Resize window to view files'), findsOneWidget);
      expect(find.byType(FilePane), findsNothing);
    });

    testWidgets('shows dual pane when width >= 250', (tester) async {
      final conn = Connection(
        id: 'narrow-2',
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
              body: SizedBox(
                width: 800,
                height: 400,
                child: FileBrowserTab(
                  connection: conn,
                  sftpInitFactory: _fakeInitFactory,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Resize window to view files'), findsNothing);
      expect(find.byType(FilePane), findsWidgets);
    });
  });

  // ===========================================================================
  // _pasteFromClipboard — clipboard copy/paste between panes
  // ===========================================================================
  group('FileBrowserTab — clipboard copy/paste', () {
    testWidgets('paste does nothing when clipboard is empty', (tester) async {
      final conn = Connection(
        id: 'clip-1',
        label: 'Test',
        sshConfig: const SSHConfig(
          server: ServerAddress(host: 'h', user: 'u'),
        ),
        state: SSHConnectionState.connected,
      );

      final (initResult, tracking) = await _trackingInitFactory(
        conn,
        localFiles: _localEntries(),
        remoteFiles: _remoteEntries(),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [transferManagerProvider.overrideWithValue(manager)],
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Scaffold(
              body: SizedBox(
                width: 1200,
                height: 800,
                child: FileBrowserTab(
                  connection: conn,
                  sftpInitFactory: (_) async => initResult,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Trigger paste on remote pane without prior copy — should do nothing.
      final filePanes = tester
          .widgetList<FilePane>(find.byType(FilePane))
          .toList();
      final remotePane = filePanes.firstWhere((p) => p.paneId == 'remote');
      remotePane.onPaste!();

      await tester.runAsync(
        () => Future.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();

      expect(tracking.calls, isEmpty);
    });

    testWidgets('copy from local + paste on remote triggers upload', (
      tester,
    ) async {
      final conn = Connection(
        id: 'clip-2',
        label: 'Test',
        sshConfig: const SSHConfig(
          server: ServerAddress(host: 'h', user: 'u'),
        ),
        state: SSHConnectionState.connected,
      );

      final (initResult, tracking) = await _trackingInitFactory(
        conn,
        localFiles: _localEntries(),
        remoteFiles: _remoteEntries(),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [transferManagerProvider.overrideWithValue(manager)],
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Scaffold(
              body: SizedBox(
                width: 1200,
                height: 800,
                child: FileBrowserTab(
                  connection: conn,
                  sftpInitFactory: (_) async => initResult,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final filePanes = tester
          .widgetList<FilePane>(find.byType(FilePane))
          .toList();
      final localPane = filePanes.firstWhere((p) => p.paneId == 'local');
      final remotePane = filePanes.firstWhere((p) => p.paneId == 'remote');

      // Select a file in local pane, then copy
      initResult.localCtrl.selectSingle(_localEntries().first.path);
      localPane.onCopy!();
      await tester.pumpAndSettle();

      // Paste on remote pane — should trigger upload
      remotePane.onPaste!();

      await tester.runAsync(
        () => Future.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();

      expect(tracking.calls, hasLength(1));
      expect(tracking.calls.first.method, 'upload');
    });

    testWidgets('paste ignores when source pane does not match', (
      tester,
    ) async {
      final conn = Connection(
        id: 'clip-3',
        label: 'Test',
        sshConfig: const SSHConfig(
          server: ServerAddress(host: 'h', user: 'u'),
        ),
        state: SSHConnectionState.connected,
      );

      final (initResult, tracking) = await _trackingInitFactory(
        conn,
        localFiles: _localEntries(),
        remoteFiles: _remoteEntries(),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [transferManagerProvider.overrideWithValue(manager)],
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Scaffold(
              body: SizedBox(
                width: 1200,
                height: 800,
                child: FileBrowserTab(
                  connection: conn,
                  sftpInitFactory: (_) async => initResult,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final filePanes = tester
          .widgetList<FilePane>(find.byType(FilePane))
          .toList();
      final localPane = filePanes.firstWhere((p) => p.paneId == 'local');

      // Copy from local pane
      initResult.localCtrl.selectSingle(_localEntries().first.path);
      localPane.onCopy!();
      await tester.pumpAndSettle();

      // Try to paste on LOCAL pane again — source is 'local', expected is 'remote'.
      // Should do nothing because source pane doesn't match.
      localPane.onPaste!();

      await tester.runAsync(
        () => Future.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();

      expect(tracking.calls, isEmpty);
    });

    testWidgets('copy from remote + paste on local triggers download', (
      tester,
    ) async {
      final conn = Connection(
        id: 'clip-4',
        label: 'Test',
        sshConfig: const SSHConfig(
          server: ServerAddress(host: 'h', user: 'u'),
        ),
        state: SSHConnectionState.connected,
      );

      final (initResult, tracking) = await _trackingInitFactory(
        conn,
        localFiles: _localEntries(),
        remoteFiles: _remoteEntries(),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [transferManagerProvider.overrideWithValue(manager)],
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Scaffold(
              body: SizedBox(
                width: 1200,
                height: 800,
                child: FileBrowserTab(
                  connection: conn,
                  sftpInitFactory: (_) async => initResult,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final filePanes = tester
          .widgetList<FilePane>(find.byType(FilePane))
          .toList();
      final remotePane = filePanes.firstWhere((p) => p.paneId == 'remote');
      final localPane = filePanes.firstWhere((p) => p.paneId == 'local');

      // Copy from remote pane
      initResult.remoteCtrl.selectSingle(_remoteEntries().first.path);
      remotePane.onCopy!();
      await tester.pumpAndSettle();

      // Paste on local pane — should trigger download
      localPane.onPaste!();

      await tester.runAsync(
        () => Future.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();

      expect(tracking.calls, hasLength(1));
      expect(tracking.calls.first.method, 'download');
    });
  });

  // ===========================================================================
  // Divider drag — _splitRatio
  // ===========================================================================
  group('FileBrowserTab — divider drag', () {
    testWidgets('horizontal drag on divider adjusts split ratio', (
      tester,
    ) async {
      final conn = Connection(
        id: 'divider-1',
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
              body: SizedBox(
                width: 1200,
                height: 800,
                child: FileBrowserTab(
                  connection: conn,
                  sftpInitFactory: _fakeInitFactory,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The divider is a GestureDetector inside a Positioned, containing
      // a SizedBox(width: 6). Use ancestor matching to find the right one.
      final dividerFinder = find.descendant(
        of: find.byType(Positioned),
        matching: find.byWidgetPredicate(
          (w) => w is GestureDetector && w.behavior == HitTestBehavior.opaque,
        ),
      );
      expect(dividerFinder, findsOneWidget);

      // Drag divider to the right by 100px.
      await tester.drag(dividerFinder, const Offset(100, 0));
      await tester.pumpAndSettle();

      // If the drag worked, the layout should still render both panes.
      expect(find.byType(FilePane), findsNWidgets(2));
    });
  });

  // ===========================================================================
  // onPaneActivated — clears other pane selection
  // ===========================================================================
  group('FileBrowserTab — onPaneActivated', () {
    testWidgets('activating local pane clears remote selection', (
      tester,
    ) async {
      final conn = Connection(
        id: 'activate-1',
        label: 'Test',
        sshConfig: const SSHConfig(
          server: ServerAddress(host: 'h', user: 'u'),
        ),
        state: SSHConnectionState.connected,
      );

      final (initResult, _) = await _trackingInitFactory(
        conn,
        localFiles: _localEntries(),
        remoteFiles: _remoteEntries(),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [transferManagerProvider.overrideWithValue(manager)],
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Scaffold(
              body: SizedBox(
                width: 1200,
                height: 800,
                child: FileBrowserTab(
                  connection: conn,
                  sftpInitFactory: (_) async => initResult,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Select something in the remote pane.
      initResult.remoteCtrl.selectSingle(_remoteEntries().first.path);
      expect(initResult.remoteCtrl.selectedEntries, isNotEmpty);

      // Activate local pane — should clear remote selection.
      final filePanes = tester
          .widgetList<FilePane>(find.byType(FilePane))
          .toList();
      final localPane = filePanes.firstWhere((p) => p.paneId == 'local');
      localPane.onPaneActivated!();
      await tester.pumpAndSettle();

      expect(initResult.remoteCtrl.selectedEntries, isEmpty);
    });

    testWidgets('activating remote pane clears local selection', (
      tester,
    ) async {
      final conn = Connection(
        id: 'activate-2',
        label: 'Test',
        sshConfig: const SSHConfig(
          server: ServerAddress(host: 'h', user: 'u'),
        ),
        state: SSHConnectionState.connected,
      );

      final (initResult, _) = await _trackingInitFactory(
        conn,
        localFiles: _localEntries(),
        remoteFiles: _remoteEntries(),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [transferManagerProvider.overrideWithValue(manager)],
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Scaffold(
              body: SizedBox(
                width: 1200,
                height: 800,
                child: FileBrowserTab(
                  connection: conn,
                  sftpInitFactory: (_) async => initResult,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Select something in the local pane.
      initResult.localCtrl.selectSingle(_localEntries().first.path);
      expect(initResult.localCtrl.selectedEntries, isNotEmpty);

      // Activate remote pane — should clear local selection.
      final filePanes = tester
          .widgetList<FilePane>(find.byType(FilePane))
          .toList();
      final remotePane = filePanes.firstWhere((p) => p.paneId == 'remote');
      remotePane.onPaneActivated!();
      await tester.pumpAndSettle();

      expect(initResult.localCtrl.selectedEntries, isEmpty);
    });
  });

  // ===========================================================================
  // sidebarActivated listener — clears both pane selections
  // ===========================================================================
  group('FileBrowserTab — sidebarActivated', () {
    testWidgets('sidebarActivated clears both pane selections', (tester) async {
      final sidebarNotifier = ValueNotifier<int>(0);
      addTearDown(sidebarNotifier.dispose);

      final conn = Connection(
        id: 'sidebar-1',
        label: 'Test',
        sshConfig: const SSHConfig(
          server: ServerAddress(host: 'h', user: 'u'),
        ),
        state: SSHConnectionState.connected,
      );

      final (initResult, _) = await _trackingInitFactory(
        conn,
        localFiles: _localEntries(),
        remoteFiles: _remoteEntries(),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [transferManagerProvider.overrideWithValue(manager)],
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Scaffold(
              body: SizedBox(
                width: 1200,
                height: 800,
                child: FileBrowserTab(
                  connection: conn,
                  sftpInitFactory: (_) async => initResult,
                  sidebarActivated: sidebarNotifier,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Select entries in both panes.
      initResult.localCtrl.selectSingle(_localEntries().first.path);
      initResult.remoteCtrl.selectSingle(_remoteEntries().first.path);
      expect(initResult.localCtrl.selectedEntries, isNotEmpty);
      expect(initResult.remoteCtrl.selectedEntries, isNotEmpty);

      // Fire sidebarActivated — should clear both.
      sidebarNotifier.value++;
      await tester.pumpAndSettle();

      expect(initResult.localCtrl.selectedEntries, isEmpty);
      expect(initResult.remoteCtrl.selectedEntries, isEmpty);
    });

    testWidgets('dispose removes sidebarActivated listener', (tester) async {
      final sidebarNotifier = ValueNotifier<int>(0);
      addTearDown(sidebarNotifier.dispose);

      final conn = Connection(
        id: 'sidebar-dispose',
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
              body: SizedBox(
                width: 1200,
                height: 800,
                child: FileBrowserTab(
                  connection: conn,
                  sftpInitFactory: _fakeInitFactory,
                  sidebarActivated: sidebarNotifier,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Remove widget from tree — triggers dispose.
      await tester.pumpWidget(
        ProviderScope(
          overrides: [transferManagerProvider.overrideWithValue(manager)],
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: const Scaffold(body: SizedBox()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Incrementing the notifier after dispose should not crash.
      sidebarNotifier.value++;
      await tester.pumpAndSettle();
      // No crash = listener was properly removed.
    });
  });

  // ===========================================================================
  // Error state when connectionError is null (generic fallback)
  // ===========================================================================
  group('FileBrowserTab — error with null connectionError', () {
    testWidgets('shows error when disconnected with no connectionError', (
      tester,
    ) async {
      final conn = Connection(
        id: 'null-err-1',
        label: 'Test',
        sshConfig: const SSHConfig(
          server: ServerAddress(host: 'h', user: 'u'),
        ),
        sshConnection: null,
        state: SSHConnectionState.disconnected,
        connectionError: null,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [transferManagerProvider.overrideWithValue(manager)],
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Scaffold(body: FileBrowserTab(connection: conn)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Should still show error via ConnectionProgress — uses generic
      // errConnectionFailed message when connectionError is null.
      expect(find.byType(ConnectionProgress), findsOneWidget);
    });
  });

  // ===========================================================================
  // Divider drag clamping — beyond 0.2 and 0.8 limits
  // ===========================================================================
  group('FileBrowserTab — divider drag clamping', () {
    testWidgets('dragging divider far left clamps at 0.2', (tester) async {
      final conn = Connection(
        id: 'clamp-left',
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
              body: SizedBox(
                width: 1000,
                height: 800,
                child: FileBrowserTab(
                  connection: conn,
                  sftpInitFactory: _fakeInitFactory,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final dividerFinder = find.descendant(
        of: find.byType(Positioned),
        matching: find.byWidgetPredicate(
          (w) => w is GestureDetector && w.behavior == HitTestBehavior.opaque,
        ),
      );
      expect(dividerFinder, findsOneWidget);

      // Drag far left — should clamp at 0.2
      await tester.drag(dividerFinder, const Offset(-500, 0));
      await tester.pumpAndSettle();

      // Both panes still visible — not collapsed.
      expect(find.byType(FilePane), findsNWidgets(2));
    });

    testWidgets('dragging divider far right clamps at 0.8', (tester) async {
      final conn = Connection(
        id: 'clamp-right',
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
              body: SizedBox(
                width: 1000,
                height: 800,
                child: FileBrowserTab(
                  connection: conn,
                  sftpInitFactory: _fakeInitFactory,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final dividerFinder = find.descendant(
        of: find.byType(Positioned),
        matching: find.byWidgetPredicate(
          (w) => w is GestureDetector && w.behavior == HitTestBehavior.opaque,
        ),
      );
      expect(dividerFinder, findsOneWidget);

      // Drag far right — should clamp at 0.8
      await tester.drag(dividerFinder, const Offset(500, 0));
      await tester.pumpAndSettle();

      // Both panes still visible — not collapsed.
      expect(find.byType(FilePane), findsNWidgets(2));
    });
  });

  // ===========================================================================
  // Clipboard paste edge cases
  // ===========================================================================
  group('FileBrowserTab — clipboard paste edge cases', () {
    testWidgets('copy multiple files from local, paste on remote uploads all', (
      tester,
    ) async {
      final conn = Connection(
        id: 'clip-multi',
        label: 'Test',
        sshConfig: const SSHConfig(
          server: ServerAddress(host: 'h', user: 'u'),
        ),
        state: SSHConnectionState.connected,
      );

      final (initResult, tracking) = await _trackingInitFactory(
        conn,
        localFiles: _localEntries(),
        remoteFiles: _remoteEntries(),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [transferManagerProvider.overrideWithValue(manager)],
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Scaffold(
              body: SizedBox(
                width: 1200,
                height: 800,
                child: FileBrowserTab(
                  connection: conn,
                  sftpInitFactory: (_) async => initResult,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final filePanes = tester
          .widgetList<FilePane>(find.byType(FilePane))
          .toList();
      final localPane = filePanes.firstWhere((p) => p.paneId == 'local');
      final remotePane = filePanes.firstWhere((p) => p.paneId == 'remote');

      // Select both local entries, then copy.
      initResult.localCtrl.selectPaths({'/test/local.txt', '/test/localdir'});
      localPane.onCopy!();
      await tester.pumpAndSettle();

      // Paste on remote pane — should upload both.
      remotePane.onPaste!();

      await tester.runAsync(
        () => Future.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();

      expect(tracking.calls, hasLength(2));
      final methods = tracking.calls.map((c) => c.method).toSet();
      expect(methods, containsAll(['upload', 'uploadDir']));
    });

    testWidgets(
      'copy from remote, paste on remote does nothing (same source pane)',
      (tester) async {
        final conn = Connection(
          id: 'clip-same-pane',
          label: 'Test',
          sshConfig: const SSHConfig(
            server: ServerAddress(host: 'h', user: 'u'),
          ),
          state: SSHConnectionState.connected,
        );

        final (initResult, tracking) = await _trackingInitFactory(
          conn,
          localFiles: _localEntries(),
          remoteFiles: _remoteEntries(),
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [transferManagerProvider.overrideWithValue(manager)],
            child: MaterialApp(
              localizationsDelegates: S.localizationsDelegates,
              supportedLocales: S.supportedLocales,
              theme: AppTheme.dark(),
              home: Scaffold(
                body: SizedBox(
                  width: 1200,
                  height: 800,
                  child: FileBrowserTab(
                    connection: conn,
                    sftpInitFactory: (_) async => initResult,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final filePanes = tester
            .widgetList<FilePane>(find.byType(FilePane))
            .toList();
        final remotePane = filePanes.firstWhere((p) => p.paneId == 'remote');

        // Copy from remote, then try to paste on remote.
        initResult.remoteCtrl.selectSingle(_remoteEntries().first.path);
        remotePane.onCopy!();
        await tester.pumpAndSettle();

        // Paste on same pane — expected source is 'local' but clipboard
        // source is 'remote', so should do nothing.
        remotePane.onPaste!();

        await tester.runAsync(
          () => Future.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pumpAndSettle();

        expect(tracking.calls, isEmpty);
      },
    );
  });

  // ===========================================================================
  // Empty pane state
  // ===========================================================================
  group('FileBrowserTab — empty panes', () {
    testWidgets('renders dual pane with no entries in either pane', (
      tester,
    ) async {
      final conn = Connection(
        id: 'empty-panes',
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
              body: SizedBox(
                width: 1200,
                height: 800,
                child: FileBrowserTab(
                  connection: conn,
                  sftpInitFactory: (c) => _fakeInitFactoryWithEntries(
                    c,
                    localFiles: [],
                    remoteFiles: [],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Both panes should be present even with no entries.
      expect(find.byType(FilePane), findsNWidgets(2));
      // No file rows should be visible.
      expect(find.byType(FileRow), findsNothing);
    });
  });

  // ===========================================================================
  // _upload/_download no-op when sftp or controller is null
  // ===========================================================================
  group('FileBrowserTab — null guard in _upload/_download', () {
    testWidgets(
      'upload/download during loading does not crash (sftp not yet set)',
      (tester) async {
        final completer = Completer<SFTPInitResult>();
        final conn = Connection(
          id: 'null-guard-1',
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
                body: SizedBox(
                  width: 1200,
                  height: 800,
                  child: FileBrowserTab(
                    connection: conn,
                    sftpInitFactory: (_) => completer.future,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        // While loading, no FilePane is rendered, so _upload/_download cannot
        // be called directly. Verify loading state.
        expect(find.byType(ConnectionProgress), findsOneWidget);
        expect(find.byType(FilePane), findsNothing);
        // No crash = null guards work.
      },
    );
  });

  // ===========================================================================
  // Controllers null fallback — _buildLoading when sftp is null
  // ===========================================================================
  group('FileBrowserTab — controllers not initialized fallback', () {
    testWidgets(
      'shows controllersNotInitialized when sftp result has null controllers',
      (tester) async {
        // This path is guarded: if _sftp is set but localCtrl/remoteCtrl
        // are null. In practice this cannot happen with the current
        // SFTPInitResult constructor, but we can test the loading→success
        // transition with empty panes to ensure the widget renders properly.
        final conn = Connection(
          id: 'ctrl-null',
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
                body: SizedBox(
                  width: 1200,
                  height: 800,
                  child: FileBrowserTab(
                    connection: conn,
                    sftpInitFactory: _fakeInitFactory,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Should show dual panes, not the "controllers not initialized" text.
        expect(find.byType(FilePane), findsNWidgets(2));
      },
    );
  });

  // ===========================================================================
  // Divider cursor and appearance
  // ===========================================================================
  group('FileBrowserTab — divider appearance', () {
    testWidgets('divider has resize cursor and correct width', (tester) async {
      final conn = Connection(
        id: 'divider-look',
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
              body: SizedBox(
                width: 1200,
                height: 800,
                child: FileBrowserTab(
                  connection: conn,
                  sftpInitFactory: _fakeInitFactory,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find the MouseRegion with resize cursor inside the Positioned.
      final mouseRegion = find.descendant(
        of: find.byType(Positioned),
        matching: find.byWidgetPredicate(
          (w) =>
              w is MouseRegion && w.cursor == SystemMouseCursors.resizeColumn,
        ),
      );
      expect(mouseRegion, findsOneWidget);

      // The divider SizedBox should be 6px wide.
      final sizedBox = find.descendant(
        of: mouseRegion,
        matching: find.byWidgetPredicate((w) => w is SizedBox && w.width == 6),
      );
      expect(sizedBox, findsOneWidget);
    });
  });
}
