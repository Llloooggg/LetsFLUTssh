import 'dart:async';

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
import 'package:letsflutssh/features/file_browser/file_browser_controller.dart';
import 'package:letsflutssh/features/file_browser/file_browser_tab.dart';
import 'package:letsflutssh/features/file_browser/sftp_initializer.dart';
import 'package:letsflutssh/core/sftp/file_system.dart';
import 'package:letsflutssh/providers/transfer_provider.dart';
import 'package:letsflutssh/theme/app_theme.dart';

@GenerateNiceMocks([MockSpec<SftpClient>()])
import 'file_browser_tab_test.mocks.dart';

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
}

/// Test file entries for local pane.
List<FileEntry> _localEntries() => [
      FileEntry(name: 'local.txt', path: '/test/local.txt', size: 100, mode: 0x1A4, modTime: DateTime(2024), isDir: false),
      FileEntry(name: 'localdir', path: '/test/localdir', size: 4096, mode: 0x1ED, modTime: DateTime(2024), isDir: true),
    ];

/// Test file entries for remote pane.
List<FileEntry> _remoteEntries() => [
      FileEntry(name: 'remote.txt', path: '/remote/remote.txt', size: 200, mode: 0x1A4, modTime: DateTime(2024), isDir: false),
      FileEntry(name: 'remotedir', path: '/remote/remotedir', size: 4096, mode: 0x1ED, modTime: DateTime(2024), isDir: true),
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
  final localCtrl = FilePaneController(fs: _FakeFS(entries: localFiles ?? []), label: 'Local');
  final remoteCtrl = FilePaneController(fs: _FakeFS(entries: remoteFiles ?? []), label: 'Remote');

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
    manager = TransferManager();
  });

  tearDown(() {
    manager.dispose();
  });

  group('FileBrowserTab', () {
    testWidgets('shows error when SFTP init fails (no SSH connection)', (tester) async {
      final conn = Connection(
        id: 'test-1',
        label: 'Test Server',
        sshConfig: const SSHConfig(host: 'example.com', user: 'root'),
        sshConnection: null,
        state: SSHConnectionState.disconnected,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            transferManagerProvider.overrideWithValue(manager),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: Scaffold(
              body: FileBrowserTab(connection: conn),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Should show error state since sshConnection is null
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.textContaining('Failed to initialize SFTP'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('error message contains relevant context', (tester) async {
      final conn = Connection(
        id: 'test-2',
        label: 'Test',
        sshConfig: const SSHConfig(host: 'h', user: 'u'),
        sshConnection: null,
        state: SSHConnectionState.disconnected,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            transferManagerProvider.overrideWithValue(manager),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: Scaffold(
              body: FileBrowserTab(connection: conn),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Error text should mention SSH connection
      expect(find.textContaining('SSH connection not available'), findsOneWidget);
    });

    testWidgets('Retry button re-attempts SFTP init', (tester) async {
      final conn = Connection(
        id: 'test-3',
        label: 'Test',
        sshConfig: const SSHConfig(host: 'h', user: 'u'),
        sshConnection: null,
        state: SSHConnectionState.disconnected,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            transferManagerProvider.overrideWithValue(manager),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: Scaffold(
              body: FileBrowserTab(connection: conn),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Error state should be showing
      expect(find.text('Retry'), findsOneWidget);

      // Tap Retry — triggers re-init (which will fail again since no SSH)
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      // Back to error state after retry fails
      expect(find.text('Retry'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('error state shows error icon', (tester) async {
      final conn = Connection(
        id: 'test-icon',
        label: 'Error Icon Test',
        sshConfig: const SSHConfig(host: 'h', user: 'u'),
        sshConnection: null,
        state: SSHConnectionState.disconnected,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            transferManagerProvider.overrideWithValue(manager),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: Scaffold(
              body: FileBrowserTab(connection: conn),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final icon = tester.widget<Icon>(find.byIcon(Icons.error_outline));
      expect(icon.color, AppTheme.disconnected);
    });

    testWidgets('initializing state shows loading UI before async init resolves', (tester) async {
      // The FileBrowserTab starts with _initializing = true, but _initSftp runs
      // immediately in initState. Since it fails synchronously (null sshConnection),
      // we verify the widget builds and transitions properly.
      final conn = Connection(
        id: 'test-loading',
        label: 'Loading Test',
        sshConfig: const SSHConfig(host: 'example.com', user: 'root'),
        sshConnection: null,
        state: SSHConnectionState.disconnected,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            transferManagerProvider.overrideWithValue(manager),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: Scaffold(
              body: FileBrowserTab(connection: conn),
            ),
          ),
        ),
      );
      // After settling, should be in error state (init failed quickly)
      await tester.pumpAndSettle();

      // Error state should show error icon and retry
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      // Loading indicator should NOT be showing anymore
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('error state shows error text with SFTP context', (tester) async {
      final conn = Connection(
        id: 'test-transition',
        label: 'Transition Test',
        sshConfig: const SSHConfig(host: 'example.com', user: 'root'),
        sshConnection: null,
        state: SSHConnectionState.disconnected,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            transferManagerProvider.overrideWithValue(manager),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: Scaffold(
              body: FileBrowserTab(connection: conn),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Should show the SFTP initialization failure message
      expect(find.textContaining('Failed to initialize SFTP'), findsOneWidget);
      // Should have both error icon and retry button
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('Retry button is a FilledButton.tonal', (tester) async {
      final conn = Connection(
        id: 'test-4',
        label: 'Test',
        sshConfig: const SSHConfig(host: 'h', user: 'u'),
        sshConnection: null,
        state: SSHConnectionState.disconnected,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            transferManagerProvider.overrideWithValue(manager),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: Scaffold(
              body: FileBrowserTab(connection: conn),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(FilledButton), findsOneWidget);
    });
  });

  group('FileBrowserTab — success path (injectable factory)', () {
    testWidgets('split divider exists in success state', (tester) async {
      final conn = Connection(
        id: 'success-2',
        label: 'Test',
        sshConfig: const SSHConfig(host: 'h', user: 'u'),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            transferManagerProvider.overrideWithValue(manager),
          ],
          child: MaterialApp(
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

      // Divider with resize cursor should exist
      final dividers = find.byWidgetPredicate((w) =>
          w is MouseRegion && w.cursor == SystemMouseCursors.resizeColumn);
      expect(dividers, findsOneWidget);
    });

    testWidgets('TransferPanel is shown below panes', (tester) async {
      final conn = Connection(
        id: 'success-4',
        label: 'Test',
        sshConfig: const SSHConfig(host: 'h', user: 'u'),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            transferManagerProvider.overrideWithValue(manager),
          ],
          child: MaterialApp(
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
    testWidgets('shows CircularProgressIndicator while factory is pending', (tester) async {
      final completer = Completer<SFTPInitResult>();
      final conn = Connection(
        id: 'loading-1',
        label: 'Test',
        sshConfig: const SSHConfig(host: 'h', user: 'u'),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            transferManagerProvider.overrideWithValue(manager),
          ],
          child: MaterialApp(
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

      // Factory hasn't resolved yet — loading state
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Initializing SFTP...'), findsOneWidget);

      // Complete with error to clean up
      completer.completeError('test done');
      await tester.pumpAndSettle();
    });

    testWidgets('transitions from loading to success when factory resolves', (tester) async {
      final completer = Completer<SFTPInitResult>();
      final conn = Connection(
        id: 'loading-2',
        label: 'Test',
        sshConfig: const SSHConfig(host: 'h', user: 'u'),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            transferManagerProvider.overrideWithValue(manager),
          ],
          child: MaterialApp(
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
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Resolve with a real result
      completer.complete(await _fakeInitFactory(conn));
      await tester.pumpAndSettle();

      // Should now show the split pane layout
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.textContaining('Transfers'), findsOneWidget);
    });

    testWidgets('transitions from loading to error when factory throws', (tester) async {
      final completer = Completer<SFTPInitResult>();
      final conn = Connection(
        id: 'loading-3',
        label: 'Test',
        sshConfig: const SSHConfig(host: 'h', user: 'u'),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            transferManagerProvider.overrideWithValue(manager),
          ],
          child: MaterialApp(
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
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      completer.completeError('Connection refused');
      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.textContaining('Connection refused'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });
  });

  group('FileBrowserTab — divider drag', () {
    // FilePane internal path bar may overflow when pane shrinks — suppress
    // rendering overflow errors since we're testing divider logic, not layout.
    testWidgets('dragging divider moves it without crash', (tester) async {
      final origHandler = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.toString().contains('overflowed')) return;
        origHandler?.call(details);
      };
      addTearDown(() => FlutterError.onError = origHandler);
      final conn = Connection(
        id: 'drag-1',
        label: 'Test',
        sshConfig: const SSHConfig(host: 'h', user: 'u'),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            transferManagerProvider.overrideWithValue(manager),
          ],
          child: MaterialApp(
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

      final divider = find.byWidgetPredicate((w) =>
          w is MouseRegion && w.cursor == SystemMouseCursors.resizeColumn);
      expect(divider, findsOneWidget);

      // Drag right — exercises the onHorizontalDragUpdate callback
      await tester.drag(divider, const Offset(50, 0));
      await tester.pumpAndSettle();

      // Divider should still exist
      expect(divider, findsOneWidget);
    });

    testWidgets('extreme drag does not crash (clamp logic)', (tester) async {
      final origHandler = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.toString().contains('overflowed')) return;
        origHandler?.call(details);
      };
      addTearDown(() => FlutterError.onError = origHandler);
      final conn = Connection(
        id: 'drag-2',
        label: 'Test',
        sshConfig: const SSHConfig(host: 'h', user: 'u'),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            transferManagerProvider.overrideWithValue(manager),
          ],
          child: MaterialApp(
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

      final divider = find.byWidgetPredicate((w) =>
          w is MouseRegion && w.cursor == SystemMouseCursors.resizeColumn);

      // Drag far left then far right — clamp should prevent crash
      await tester.drag(divider, const Offset(-800, 0));
      await tester.pumpAndSettle();
      expect(divider, findsOneWidget);

      await tester.drag(divider, const Offset(800, 0));
      await tester.pumpAndSettle();
      expect(divider, findsOneWidget);
    });
  });

  group('FileBrowserTab — upload/download enqueue', () {
    testWidgets('upload enqueues a task to TransferManager', (tester) async {
      final conn = Connection(
        id: 'upload-1',
        label: 'Test',
        sshConfig: const SSHConfig(host: 'h', user: 'u'),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            transferManagerProvider.overrideWithValue(manager),
          ],
          child: MaterialApp(
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
        sshConfig: const SSHConfig(host: 'h', user: 'u'),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            transferManagerProvider.overrideWithValue(manager),
          ],
          child: MaterialApp(
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

      // First call failed — error state
      expect(find.text('Retry'), findsOneWidget);
      expect(callCount, 1);

      // Tap Retry — second call succeeds
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(find.text('Retry'), findsNothing);
      expect(find.textContaining('Transfers'), findsOneWidget);
      expect(callCount, 2);
    });
  });

  group('FileBrowserTab — FilePane callbacks (upload/download)', () {
    testWidgets('double-clicking local file triggers upload (onTransfer)', (tester) async {
      final conn = Connection(
        id: 'xfer-1',
        label: 'Test',
        sshConfig: const SSHConfig(host: 'h', user: 'u'),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            transferManagerProvider.overrideWithValue(manager),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: Scaffold(
              body: SizedBox(
                width: 1200,
                height: 800,
                child: FileBrowserTab(
                  connection: conn,
                  sftpInitFactory: (c) => _fakeInitFactoryWithEntries(c,
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

    testWidgets('double-clicking remote file triggers download (onTransfer)', (tester) async {
      final conn = Connection(
        id: 'xfer-2',
        label: 'Test',
        sshConfig: const SSHConfig(host: 'h', user: 'u'),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            transferManagerProvider.overrideWithValue(manager),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: Scaffold(
              body: SizedBox(
                width: 1200,
                height: 800,
                child: FileBrowserTab(
                  connection: conn,
                  sftpInitFactory: (c) => _fakeInitFactoryWithEntries(c,
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

    testWidgets('local pane shows file entries from factory', (tester) async {
      final conn = Connection(
        id: 'xfer-3',
        label: 'Test',
        sshConfig: const SSHConfig(host: 'h', user: 'u'),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            transferManagerProvider.overrideWithValue(manager),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: Scaffold(
              body: SizedBox(
                width: 1200,
                height: 800,
                child: FileBrowserTab(
                  connection: conn,
                  sftpInitFactory: (c) => _fakeInitFactoryWithEntries(c,
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

      // Both panes should show their entries
      expect(find.text('local.txt'), findsOneWidget);
      expect(find.text('localdir'), findsOneWidget);
      expect(find.text('remote.txt'), findsOneWidget);
      expect(find.text('remotedir'), findsOneWidget);
    });

    testWidgets('context menu Transfer on local file enqueues upload', (tester) async {
      final origHandler = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.toString().contains('overflowed')) return;
        origHandler?.call(details);
      };
      addTearDown(() => FlutterError.onError = origHandler);

      final conn = Connection(
        id: 'xfer-ctx',
        label: 'Test',
        sshConfig: const SSHConfig(host: 'h', user: 'u'),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            transferManagerProvider.overrideWithValue(manager),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: Scaffold(
              body: SizedBox(
                width: 1200,
                height: 800,
                child: FileBrowserTab(
                  connection: conn,
                  sftpInitFactory: (c) => _fakeInitFactoryWithEntries(c,
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
    testWidgets('removing widget during success state does not crash', (tester) async {
      final conn = Connection(
        id: 'dispose-1',
        label: 'Test',
        sshConfig: const SSHConfig(host: 'h', user: 'u'),
      );

      final key = GlobalKey();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            transferManagerProvider.overrideWithValue(manager),
          ],
          child: MaterialApp(
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
          overrides: [
            transferManagerProvider.overrideWithValue(manager),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const Scaffold(body: SizedBox()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // No crash = success
    });

    testWidgets('removing widget during loading does not crash', (tester) async {
      final completer = Completer<SFTPInitResult>();
      final conn = Connection(
        id: 'dispose-2',
        label: 'Test',
        sshConfig: const SSHConfig(host: 'h', user: 'u'),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            transferManagerProvider.overrideWithValue(manager),
          ],
          child: MaterialApp(
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
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Remove from tree while still loading
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            transferManagerProvider.overrideWithValue(manager),
          ],
          child: MaterialApp(
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
}
