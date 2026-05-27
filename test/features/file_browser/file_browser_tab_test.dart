/// Widget tests for [FileBrowserTab] — the dual-pane SFTP browser
/// shell. The SFTP init / transfer / pane internals are covered by
/// `sftp_browser_mixin_test`, `sftp_initializer_test`, `file_pane_test`
/// and `transfer_panel_test`; this file covers the tab-level assembly
/// those don't: the loading gate, the two-pane + transfer-panel layout,
/// and the too-narrow fallback.
///
/// FRB is loaded because `configProvider` reads the config-store actor
/// and the tab probes the Rust file clipboard on dispose. The SFTP
/// init is bypassed with an injected factory returning controllers over
/// a stub [FileSystem]; the transfer providers are overridden with a
/// fake so [TransferPanel] renders without booting the Rust queue.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:letsflutssh/core/connection/connection.dart';
import 'package:letsflutssh/core/sftp/file_system.dart';
import 'package:letsflutssh/core/sftp/sftp_models.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/features/file_browser/file_browser_controller.dart';
import 'package:letsflutssh/features/file_browser/file_browser_tab.dart';
import 'package:letsflutssh/features/file_browser/file_pane.dart';
import 'package:letsflutssh/features/file_browser/sftp_initializer.dart';
import 'package:letsflutssh/features/file_browser/transfer_panel.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/providers/config_provider.dart';
import 'package:letsflutssh/providers/transfer_provider.dart';
import 'package:letsflutssh/widgets/core/app_empty_state.dart';
import 'package:letsflutssh/widgets/terminal/connection_progress.dart';

import '../../helpers/fake_transfers_notifier.dart';
import '../../helpers/frb_bootstrap.dart';

import 'dart:io';

/// Stub [FileSystem] — the panes never navigate in these tests (the
/// controllers are handed over un-navigated), so only the listing /
/// initial-dir reads can fire; everything else is out of scope.
class _StubFs extends FileSystem {
  @override
  Future<List<FileEntry>> list(String path) async => const [];
  @override
  Future<String> initialDir() async => '/';
  @override
  Future<int> dirSize(String path) async => 0;
  @override
  Future<void> mkdir(String path) => throw UnimplementedError();
  @override
  Future<void> remove(String path) => throw UnimplementedError();
  @override
  Future<void> removeDir(String path) => throw UnimplementedError();
  @override
  Future<void> rename(String oldPath, String newPath) =>
      throw UnimplementedError();
  @override
  Future<List<FlatFileLeaf>> flatWalkFiles(String root, {int maxDepth = 100}) =>
      throw UnimplementedError();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(requireFrbLoaded);

  late Directory tempDir;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('file_browser_tab_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
    await bootstrapRustConfigStore();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Connection connectedConnection() => Connection(
    id: 'tab-c1',
    label: 'Box',
    sshConfig: const SSHConfig(
      server: ServerAddress(host: '10.0.0.1', user: 'root'),
    ),
    state: SSHConnectionState.connected,
  );

  SFTPInitResult fakeResult() {
    final fs = _StubFs();
    return SFTPInitResult(
      localCtrl: FilePaneController(fs: fs, label: 'Local'),
      remoteCtrl: FilePaneController(fs: fs, label: 'Remote'),
      filesystem: null,
    );
  }

  Future<void> pumpTab(
    WidgetTester tester, {
    required Connection conn,
    SFTPInitFactory? factory,
    double width = 800,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [transfersProvider.overrideWith(FakeTransfersNotifier.new)],
        child: MaterialApp(
          localizationsDelegates: S.localizationsDelegates,
          supportedLocales: S.supportedLocales,
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: width,
                height: 600,
                child: FileBrowserTab(
                  connection: conn,
                  sftpInitFactory: factory,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('shows the connection-progress gate while initialising', (
    tester,
  ) async {
    // No `markTransportAdopted` → the mixin's transport gate never
    // resolves, so the tab stays in its initialising state.
    await pumpTab(
      tester,
      conn: connectedConnection(),
      factory: (_) async => fakeResult(),
    );
    await tester.pump();
    expect(find.byType(ConnectionProgress), findsOneWidget);
    expect(find.byType(FilePane), findsNothing);
  });

  testWidgets('renders two panes and the transfer panel once ready', (
    tester,
  ) async {
    final conn = connectedConnection();
    conn.markTransportAdopted(); // drive the transport gate
    await pumpTab(tester, conn: conn, factory: (_) async => fakeResult());
    await tester.pumpAndSettle();

    expect(find.byType(FilePane), findsNWidgets(2));
    expect(find.byType(TransferPanel), findsOneWidget);
    expect(find.byType(ConnectionProgress), findsNothing);
  });

  testWidgets('collapses to a hint when too narrow for two panes', (
    tester,
  ) async {
    final conn = connectedConnection();
    conn.markTransportAdopted();
    await pumpTab(
      tester,
      conn: conn,
      factory: (_) async => fakeResult(),
      width: 200,
    );
    await tester.pumpAndSettle();

    // The too-narrow branch swaps both panes for a single hint.
    expect(find.byType(AppEmptyState), findsOneWidget);
    expect(find.byType(FilePane), findsNothing);
  });
}
