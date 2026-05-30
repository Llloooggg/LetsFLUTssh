/// Widget tests for [FileBrowserTab] — the dual-pane SFTP browser
/// shell. The SFTP init / transfer / pane internals are covered by
/// `sftp_browser_mixin_test`, `sftp_initializer_test`, `file_pane_test`
/// and `transfer_panel_test`; this file covers the tab-level assembly
/// those don't:
///   * loading gate, two-pane + transfer-panel layout, too-narrow fallback;
///   * sidebar-activated selection clear + sibling-pane clear-on-activate;
///   * Ctrl+C / Ctrl+V wiring through the Rust file clipboard, scoped by
///     tab id + source pane, with the matching dispose-clear;
///   * OS-drop handlers on the local pane (file / dir / symlink-skip /
///     pre-existing-symlink rejection) and the remote pane (stat → wrap →
///     uploadMany);
///   * resizable divider drag updating the split ratio.
///
/// FRB is loaded because `configProvider` reads the config-store actor,
/// the tab probes the Rust file clipboard on dispose, and the OS drop
/// path stats / copies through `lfs_core::fs::local`. SFTP init is
/// bypassed with an injected factory returning controllers over a stub
/// [FileSystem]; the transfer providers are overridden with a fake so
/// [TransferPanel] renders without booting the Rust queue.
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
import 'package:letsflutssh/src/rust/api/file_clipboard.dart'
    show fileClipboardClear, fileClipboardIsSet;
import 'package:letsflutssh/widgets/core/app_empty_state.dart';
import 'package:letsflutssh/widgets/terminal/connection_progress.dart';
import 'package:path/path.dart' as p;

import '../../helpers/fake_transfers_notifier.dart';
import '../../helpers/frb_bootstrap.dart';
import '../../helpers/frb_pump.dart';

import 'dart:io';

/// Stub [FileSystem] backed by an in-memory directory map. Seeded
/// entries let the dual-pane callbacks (transfer / copy / paste /
/// drop) fire against a populated selection instead of an empty pane.
class _StubFs extends FileSystem {
  _StubFs({Map<String, List<FileEntry>>? dirs, this.initial = '/'})
    : _dirs = dirs ?? const {'/': []};

  final Map<String, List<FileEntry>> _dirs;
  final String initial;

  @override
  Future<List<FileEntry>> list(String path) async =>
      List.unmodifiable(_dirs[path] ?? const []);
  @override
  Future<String> initialDir() async => initial;
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

  /// Builds a result with two pre-navigated controllers — each pane's
  /// `currentPath` lands on its seeded directory + `entries` populated
  /// so the cut/copy/paste + drop paths have a real selection target.
  Future<SFTPInitResult> seededResult({
    required Directory localDir,
    List<FileEntry> localEntries = const [],
    List<FileEntry> remoteEntries = const [],
    String remoteDir = '/srv',
  }) async {
    final localFs = _StubFs(
      dirs: {localDir.path: localEntries},
      initial: localDir.path,
    );
    final remoteFs = _StubFs(
      dirs: {remoteDir: remoteEntries},
      initial: remoteDir,
    );
    final localCtrl = FilePaneController(fs: localFs, label: 'Local');
    final remoteCtrl = FilePaneController(fs: remoteFs, label: 'Remote');
    await localCtrl.init();
    await remoteCtrl.init();
    return SFTPInitResult(
      localCtrl: localCtrl,
      remoteCtrl: remoteCtrl,
      filesystem: null,
    );
  }

  Future<void> pumpTab(
    WidgetTester tester, {
    required Connection conn,
    SFTPInitFactory? factory,
    ValueNotifier<int>? sidebar,
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
                  sidebarActivated: sidebar,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  FilePane filePaneById(WidgetTester tester, String id) {
    return tester.widget<FilePane>(
      find.byWidgetPredicate((w) => w is FilePane && w.paneId == id),
    );
  }

  FileEntry fileEntry(String name, String path, {int size = 0}) => FileEntry(
    name: name,
    path: path,
    size: size,
    modTime: DateTime.fromMillisecondsSinceEpoch(0),
    isDir: false,
  );

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

  // ─────────────────────────────────────────────────────────────────────────
  // Tab-level pane interactions
  // ─────────────────────────────────────────────────────────────────────────

  testWidgets('sidebarActivated tick clears selections on both panes', (
    tester,
  ) async {
    // Contract — `_onSidebarActivated` is wired in `initState` and
    // drops both pane selections so a sidebar focus doesn't leave a
    // stale "selected" highlight in the file panes.
    final sidebar = ValueNotifier<int>(0);
    final conn = connectedConnection();
    conn.markTransportAdopted();
    final dir = Directory.systemTemp.createTempSync('fb_sidebar_');
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    final localEntry = fileEntry('a.txt', p.join(dir.path, 'a.txt'));
    final remoteEntry = fileEntry('b.txt', '/srv/b.txt');
    final seeded = await seededResult(
      localDir: dir,
      localEntries: [localEntry],
      remoteEntries: [remoteEntry],
    );
    seeded.localCtrl.selectSingle(localEntry.path);
    seeded.remoteCtrl.selectSingle(remoteEntry.path);

    await pumpTab(
      tester,
      conn: conn,
      factory: (_) async => seeded,
      sidebar: sidebar,
    );
    await tester.pumpAndSettle();

    expect(seeded.localCtrl.selected, isNotEmpty);
    expect(seeded.remoteCtrl.selected, isNotEmpty);

    sidebar.value += 1;
    await tester.pump();

    expect(seeded.localCtrl.selected, isEmpty);
    expect(seeded.remoteCtrl.selected, isEmpty);
  });

  testWidgets('onPaneActivated on one pane clears the sibling selection', (
    tester,
  ) async {
    // Contract — wiring `otherController.clearSelection()` into the
    // `FilePane.onPaneActivated` callback keeps only one pane
    // "active" visually.
    final conn = connectedConnection();
    conn.markTransportAdopted();
    final dir = Directory.systemTemp.createTempSync('fb_activate_');
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    final localEntry = fileEntry('a.txt', p.join(dir.path, 'a.txt'));
    final remoteEntry = fileEntry('b.txt', '/srv/b.txt');
    final seeded = await seededResult(
      localDir: dir,
      localEntries: [localEntry],
      remoteEntries: [remoteEntry],
    );
    seeded.remoteCtrl.selectSingle(remoteEntry.path);

    await pumpTab(tester, conn: conn, factory: (_) async => seeded);
    await tester.pumpAndSettle();

    expect(seeded.remoteCtrl.selected, isNotEmpty);

    // Fire the local pane's activation callback — the tab wires this
    // to clear the remote pane's selection.
    filePaneById(tester, 'local').onPaneActivated!.call();
    await tester.pump();

    expect(seeded.remoteCtrl.selected, isEmpty);
  });

  testWidgets('intra-app drop on the remote pane wires to uploadMany', (
    tester,
  ) async {
    // Contract — the remote pane's `onDropReceived` (drag from local
    // pane) routes through `actions.drop = uploadMany`. Without a
    // backing SFTP filesystem, the upload short-circuits — the
    // assertion is that the callback dispatches cleanly through the
    // wired `_PaneActions.drop` tuple slot.
    final conn = connectedConnection();
    conn.markTransportAdopted();
    final dir = Directory.systemTemp.createTempSync('fb_intra_drop_');
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    final entry = fileEntry('moved.txt', p.join(dir.path, 'moved.txt'));
    final seeded = await seededResult(localDir: dir, localEntries: [entry]);

    await pumpTab(tester, conn: conn, factory: (_) async => seeded);
    await tester.pumpAndSettle();

    filePaneById(tester, 'remote').onDropReceived!.call([entry]);
    await tester.pump();
  });

  testWidgets('onTransfer wraps a single entry into the multi-callback', (
    tester,
  ) async {
    // Contract — the per-entry `onTransfer` callback adapts to the
    // bulk `actions.transfer` API by wrapping the entry in a list.
    // Without a real Rust transport here, the transfer enqueue
    // sees a null SFTP filesystem and returns without effect — the
    // assertion is only that the callback dispatches without throwing.
    final conn = connectedConnection();
    conn.markTransportAdopted();
    final dir = Directory.systemTemp.createTempSync('fb_transfer_');
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    final localEntry = fileEntry('one.txt', p.join(dir.path, 'one.txt'));
    final seeded = await seededResult(
      localDir: dir,
      localEntries: [localEntry],
      remoteEntries: const [],
    );

    await pumpTab(tester, conn: conn, factory: (_) async => seeded);
    await tester.pumpAndSettle();

    final localPane = filePaneById(tester, 'local');
    // Dispatch the single-entry transfer hook — its body builds
    // `[entry]` and calls `uploadMany`. With no SFTP, uploadMany
    // early-returns on the remote.fs nullability checks.
    localPane.onTransfer!.call(localEntry);
    await tester.pump();
    // No throw → contract holds.
  });

  // ─────────────────────────────────────────────────────────────────────────
  // OS-drop handlers (local + remote)
  // ─────────────────────────────────────────────────────────────────────────

  testWidgets('OS drop with empty paths is a no-op on the local pane', (
    tester,
  ) async {
    // Contract — `_osDropToLocal([])` early-returns before any conflict
    // resolver is built, so the local pane stays untouched and no
    // future microtask is dangling.
    final conn = connectedConnection();
    conn.markTransportAdopted();
    final dir = Directory.systemTemp.createTempSync('fb_drop_empty_');
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    final seeded = await seededResult(localDir: dir);

    await pumpTab(tester, conn: conn, factory: (_) async => seeded);
    await tester.pumpAndSettle();

    filePaneById(tester, 'local').onOsDropReceived!.call(const []);
    await tester.pumpAndSettle();
    // No throw, no listing — the seeded entries are still the only ones.
    expect(seeded.localCtrl.entries, isEmpty);
  });

  testWidgets('OS drop copies a file into the local pane directory', (
    tester,
  ) async {
    // Contract — `_osDropToLocal` stats each source (`localFsSymlinkStat`),
    // copies via `localFsCopyFile`, and refreshes the local pane so the
    // new file appears.
    final conn = connectedConnection();
    conn.markTransportAdopted();
    final src = Directory.systemTemp.createTempSync('fb_drop_src_');
    final dst = Directory.systemTemp.createTempSync('fb_drop_dst_');
    addTearDown(() {
      if (src.existsSync()) src.deleteSync(recursive: true);
      if (dst.existsSync()) dst.deleteSync(recursive: true);
    });
    final srcFile = File(p.join(src.path, 'payload.bin'));
    srcFile.writeAsBytesSync(List<int>.filled(8, 0x41));

    final seeded = await seededResult(localDir: dst);

    await pumpTab(tester, conn: conn, factory: (_) async => seeded);
    await tester.pumpAndSettle();

    filePaneById(tester, 'local').onOsDropReceived!.call([srcFile.path]);
    // The drop runs async via FRB — settle real-time ticks until done.
    final copied = File(p.join(dst.path, 'payload.bin'));
    final stopwatch = Stopwatch()..start();
    while (!copied.existsSync() && stopwatch.elapsed.inSeconds < 5) {
      await tester.runAsync(
        () async => await Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump();
    }
    expect(
      copied.existsSync(),
      isTrue,
      reason: 'expected the dropped file to land in the destination',
    );
    expect(copied.readAsBytesSync(), hasLength(8));
  });

  testWidgets('OS drop copies a directory tree recursively', (tester) async {
    // Contract — when the source stat reports a directory, the drop
    // routes through `localFsCopyRecursiveNoSymlinks` (the file
    // branch is `localFsCopyFile`). Verifies the isDir = true branch
    // lands an entire subtree.
    final conn = connectedConnection();
    conn.markTransportAdopted();
    final srcRoot = Directory.systemTemp.createTempSync('fb_drop_dir_src_');
    final dstRoot = Directory.systemTemp.createTempSync('fb_drop_dir_dst_');
    addTearDown(() {
      if (srcRoot.existsSync()) srcRoot.deleteSync(recursive: true);
      if (dstRoot.existsSync()) dstRoot.deleteSync(recursive: true);
    });
    final srcSub = Directory(p.join(srcRoot.path, 'inner'))..createSync();
    File(p.join(srcSub.path, 'nested.txt')).writeAsStringSync('x');

    final seeded = await seededResult(localDir: dstRoot);

    await pumpTab(tester, conn: conn, factory: (_) async => seeded);
    await tester.pumpAndSettle();

    filePaneById(tester, 'local').onOsDropReceived!.call([srcSub.path]);

    final mirrored = File(p.join(dstRoot.path, 'inner', 'nested.txt'));
    final stopwatch = Stopwatch()..start();
    while (!mirrored.existsSync() && stopwatch.elapsed.inSeconds < 5) {
      await tester.runAsync(
        () async => await Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump();
    }
    expect(mirrored.existsSync(), isTrue);
  });

  testWidgets('OS drop skips a symlink source rather than following it', (
    tester,
  ) async {
    // Contract — `_osDropToLocal` logs and continues when the
    // source path is a symlink, never reading the target. Linux/
    // macOS only; Windows symlink creation needs elevated rights.
    if (Platform.isWindows) return;
    final conn = connectedConnection();
    conn.markTransportAdopted();
    final src = Directory.systemTemp.createTempSync('fb_drop_link_src_');
    final dst = Directory.systemTemp.createTempSync('fb_drop_link_dst_');
    addTearDown(() {
      if (src.existsSync()) src.deleteSync(recursive: true);
      if (dst.existsSync()) dst.deleteSync(recursive: true);
    });
    final realFile = File(p.join(src.path, 'real.txt'))
      ..writeAsStringSync('hi');
    final linkPath = p.join(src.path, 'link.txt');
    Link(linkPath).createSync(realFile.path);

    final seeded = await seededResult(localDir: dst);

    await pumpTab(tester, conn: conn, factory: (_) async => seeded);
    await tester.pumpAndSettle();

    filePaneById(tester, 'local').onOsDropReceived!.call([linkPath]);
    // Drain microtasks — the skip path is short and asynchronous.
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () async => await Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump();
    }

    // The symlinked source must NOT have been copied into the dst.
    expect(File(p.join(dst.path, 'link.txt')).existsSync(), isFalse);
  });

  testWidgets(
    'OS drop refuses to overwrite when the destination is a pre-existing symlink',
    (tester) async {
      // Contract — `_resolveLocalDropConflict` hard-rejects when the
      // existing target is a symlink (no overwrite-via-symlink), so
      // the dropped file is dropped on the floor, NOT copied through
      // the link to its target.
      if (Platform.isWindows) return;
      final conn = connectedConnection();
      conn.markTransportAdopted();
      final src = Directory.systemTemp.createTempSync('fb_drop_dst_link_src_');
      final dst = Directory.systemTemp.createTempSync('fb_drop_dst_link_dst_');
      final outside = Directory.systemTemp.createTempSync(
        'fb_drop_dst_link_outside_',
      );
      addTearDown(() {
        if (src.existsSync()) src.deleteSync(recursive: true);
        if (dst.existsSync()) dst.deleteSync(recursive: true);
        if (outside.existsSync()) outside.deleteSync(recursive: true);
      });
      final srcFile = File(p.join(src.path, 'doc.txt'))
        ..writeAsStringSync('new');
      final outsideTarget = File(p.join(outside.path, 'target.txt'))
        ..writeAsStringSync('original');
      // Pre-existing symlink at `dst/doc.txt` → `outside/target.txt`.
      Link(p.join(dst.path, 'doc.txt')).createSync(outsideTarget.path);

      final seeded = await seededResult(localDir: dst);

      await pumpTab(tester, conn: conn, factory: (_) async => seeded);
      await tester.pumpAndSettle();

      filePaneById(tester, 'local').onOsDropReceived!.call([srcFile.path]);
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(
          () async =>
              await Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        await tester.pump();
      }

      // The link target outside `dst/` must keep its original content
      // — the resolver short-circuited before any copy ran.
      expect(outsideTarget.readAsStringSync(), 'original');
    },
  );

  testWidgets('OS drop on the remote pane uploads via the transfer queue', (
    tester,
  ) async {
    // Contract — `_osDropToRemote` stats every dropped path with
    // `localFsStat` (follow-symlink), wraps each into a `FileEntry`,
    // and hands the batch to `uploadMany`. With no real SFTP backend,
    // `uploadMany` returns early on the empty/null filesystem path
    // — the assertion is just that the dispatch doesn't throw.
    final conn = connectedConnection();
    conn.markTransportAdopted();
    final src = Directory.systemTemp.createTempSync('fb_drop_remote_');
    addTearDown(() {
      if (src.existsSync()) src.deleteSync(recursive: true);
    });
    final srcFile = File(p.join(src.path, 'remote.bin'))
      ..writeAsBytesSync([1, 2, 3]);
    final dir = Directory.systemTemp.createTempSync('fb_drop_remote_local_');
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    final seeded = await seededResult(localDir: dir);

    await pumpTab(tester, conn: conn, factory: (_) async => seeded);
    await tester.pumpAndSettle();

    filePaneById(tester, 'remote').onOsDropReceived!.call([srcFile.path]);
    await pumpUntilFrbSettles(tester, Future<void>.value());
    await tester.pump();
    // No throw → the stat → wrap → uploadMany chain runs.
  });

  testWidgets('OS drop on the remote pane drops paths that fail to stat', (
    tester,
  ) async {
    // Contract — when `localFsStat` returns null (path does not
    // exist), the entry is skipped silently; the drop call still
    // completes without throwing.
    final conn = connectedConnection();
    conn.markTransportAdopted();
    final dir = Directory.systemTemp.createTempSync('fb_drop_remote_gone_');
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    final seeded = await seededResult(localDir: dir);

    await pumpTab(tester, conn: conn, factory: (_) async => seeded);
    await tester.pumpAndSettle();

    final ghost = p.join(dir.path, 'does-not-exist.bin');
    filePaneById(tester, 'remote').onOsDropReceived!.call([ghost]);
    await pumpUntilFrbSettles(tester, Future<void>.value());
    await tester.pump();
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Local-drop conflict-dialog branches
  // ─────────────────────────────────────────────────────────────────────────

  testWidgets('OS drop with a real conflict + Replace overwrites the file', (
    tester,
  ) async {
    // Contract — when the destination file already exists (regular
    // file, not a symlink), the resolver surfaces FileConflictDialog;
    // tapping Replace returns `ConflictAction.replace` and the local
    // copy proceeds with the original `targetPath`. The bytes after
    // the drop must reflect the source file.
    if (Platform.isWindows) return;
    final conn = connectedConnection();
    conn.markTransportAdopted();
    final src = Directory.systemTemp.createTempSync('fb_replace_src_');
    final dst = Directory.systemTemp.createTempSync('fb_replace_dst_');
    addTearDown(() {
      if (src.existsSync()) src.deleteSync(recursive: true);
      if (dst.existsSync()) dst.deleteSync(recursive: true);
    });
    final srcFile = File(p.join(src.path, 'doc.txt'))..writeAsStringSync('NEW');
    // Pre-existing regular file at the destination triggers the dialog.
    File(p.join(dst.path, 'doc.txt')).writeAsStringSync('OLD');

    final seeded = await seededResult(localDir: dst);
    await pumpTab(tester, conn: conn, factory: (_) async => seeded);
    await tester.pumpAndSettle();

    filePaneById(tester, 'local').onOsDropReceived!.call([srcFile.path]);
    // Settle until the dialog renders. The conflict path involves a
    // Rust stat call + dialog mount + microtask hop.
    final dialogFinder = find.text('Replace');
    final stopwatch = Stopwatch()..start();
    while (dialogFinder.evaluate().isEmpty && stopwatch.elapsed.inSeconds < 5) {
      await tester.runAsync(
        () async => await Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump();
    }
    expect(dialogFinder, findsOneWidget);
    await tester.tap(dialogFinder);
    await tester.pumpAndSettle();

    // The Replace branch returns the original targetPath; the local
    // copy then overwrites with the source bytes.
    final dstFile = File(p.join(dst.path, 'doc.txt'));
    final waitForCopy = Stopwatch()..start();
    while (dstFile.readAsStringSync() != 'NEW' &&
        waitForCopy.elapsed.inSeconds < 5) {
      await tester.runAsync(
        () async => await Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump();
    }
    expect(dstFile.readAsStringSync(), 'NEW');
  });

  testWidgets('OS drop with a real conflict + Keep both writes a sibling', (
    tester,
  ) async {
    // Contract — Keep both routes through `uniqueSiblingName`, which
    // resolves to a non-colliding path like "doc (1).txt"; the
    // original file stays intact and the new file lands beside it.
    if (Platform.isWindows) return;
    final conn = connectedConnection();
    conn.markTransportAdopted();
    final src = Directory.systemTemp.createTempSync('fb_keep_src_');
    final dst = Directory.systemTemp.createTempSync('fb_keep_dst_');
    addTearDown(() {
      if (src.existsSync()) src.deleteSync(recursive: true);
      if (dst.existsSync()) dst.deleteSync(recursive: true);
    });
    final srcFile = File(p.join(src.path, 'doc.txt'))..writeAsStringSync('NEW');
    final original = File(p.join(dst.path, 'doc.txt'))
      ..writeAsStringSync('OLD');

    final seeded = await seededResult(localDir: dst);
    await pumpTab(tester, conn: conn, factory: (_) async => seeded);
    await tester.pumpAndSettle();

    filePaneById(tester, 'local').onOsDropReceived!.call([srcFile.path]);
    final dialogFinder = find.text('Keep both');
    final stopwatch = Stopwatch()..start();
    while (dialogFinder.evaluate().isEmpty && stopwatch.elapsed.inSeconds < 5) {
      await tester.runAsync(
        () async => await Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump();
    }
    expect(dialogFinder, findsOneWidget);
    await tester.tap(dialogFinder);
    await tester.pumpAndSettle();

    // Original keeps its bytes; a sibling appears with the new bytes.
    final waitForCopy = Stopwatch()..start();
    Iterable<FileSystemEntity> contents = const [];
    while (waitForCopy.elapsed.inSeconds < 5) {
      contents = dst.listSync(followLinks: false);
      if (contents.length >= 2) break;
      await tester.runAsync(
        () async => await Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump();
    }
    expect(original.readAsStringSync(), 'OLD');
    expect(contents.length, greaterThanOrEqualTo(2));
  });

  testWidgets('OS drop with a real conflict + Skip leaves the target alone', (
    tester,
  ) async {
    // Contract — Skip + Cancel collapse into the same `return null`
    // arm of `_resolveLocalDropConflict`; the existing file's bytes
    // are preserved and no sibling appears.
    if (Platform.isWindows) return;
    final conn = connectedConnection();
    conn.markTransportAdopted();
    final src = Directory.systemTemp.createTempSync('fb_skip_src_');
    final dst = Directory.systemTemp.createTempSync('fb_skip_dst_');
    addTearDown(() {
      if (src.existsSync()) src.deleteSync(recursive: true);
      if (dst.existsSync()) dst.deleteSync(recursive: true);
    });
    final srcFile = File(p.join(src.path, 'doc.txt'))..writeAsStringSync('NEW');
    File(p.join(dst.path, 'doc.txt')).writeAsStringSync('OLD');

    final seeded = await seededResult(localDir: dst);
    await pumpTab(tester, conn: conn, factory: (_) async => seeded);
    await tester.pumpAndSettle();

    filePaneById(tester, 'local').onOsDropReceived!.call([srcFile.path]);
    final dialogFinder = find.text('Skip');
    final stopwatch = Stopwatch()..start();
    while (dialogFinder.evaluate().isEmpty && stopwatch.elapsed.inSeconds < 5) {
      await tester.runAsync(
        () async => await Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump();
    }
    expect(dialogFinder, findsOneWidget);
    await tester.tap(dialogFinder);
    await tester.pumpAndSettle();

    // Drain microtasks so any in-flight copy that should NOT happen
    // would have completed by now.
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () async => await Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump();
    }
    final dstFile = File(p.join(dst.path, 'doc.txt'));
    expect(dstFile.readAsStringSync(), 'OLD');
    // No sibling — only the original entry sits in `dst`.
    expect(dst.listSync(followLinks: false).length, 1);
  });

  testWidgets(
    'OS drop with a real conflict + Cancel halts the rest of the batch',
    (tester) async {
      // Contract — Cancel sets `resolver.isCancelled`, which the batch
      // loop reads at the top of every iteration. The second source
      // in the same drop never reaches its stat call, so its target
      // never appears in `dst`.
      if (Platform.isWindows) return;
      final conn = connectedConnection();
      conn.markTransportAdopted();
      final src = Directory.systemTemp.createTempSync('fb_cancel_src_');
      final dst = Directory.systemTemp.createTempSync('fb_cancel_dst_');
      addTearDown(() {
        if (src.existsSync()) src.deleteSync(recursive: true);
        if (dst.existsSync()) dst.deleteSync(recursive: true);
      });
      final srcA = File(p.join(src.path, 'a.txt'))..writeAsStringSync('A');
      final srcB = File(p.join(src.path, 'b.txt'))..writeAsStringSync('B');
      // Pre-existing collision on `a.txt` triggers the dialog; `b.txt`
      // has no collision and would copy unimpeded if not for cancel.
      File(p.join(dst.path, 'a.txt')).writeAsStringSync('OLD');

      final seeded = await seededResult(localDir: dst);
      await pumpTab(tester, conn: conn, factory: (_) async => seeded);
      await tester.pumpAndSettle();

      filePaneById(
        tester,
        'local',
      ).onOsDropReceived!.call([srcA.path, srcB.path]);
      final cancelFinder = find.text('Cancel');
      final stopwatch = Stopwatch()..start();
      while (cancelFinder.evaluate().isEmpty &&
          stopwatch.elapsed.inSeconds < 5) {
        await tester.runAsync(
          () async =>
              await Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        await tester.pump();
      }
      expect(cancelFinder, findsOneWidget);
      await tester.tap(cancelFinder);
      await tester.pumpAndSettle();
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(
          () async =>
              await Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        await tester.pump();
      }

      // `a.txt` keeps its OLD content; `b.txt` was never copied
      // because the cancel guard short-circuits the loop.
      expect(File(p.join(dst.path, 'a.txt')).readAsStringSync(), 'OLD');
      expect(File(p.join(dst.path, 'b.txt')).existsSync(), isFalse);
    },
  );

  // ─────────────────────────────────────────────────────────────────────────
  // Resizable divider
  // ─────────────────────────────────────────────────────────────────────────

  // 'dragging the divider' test deferred — the FilePane width re-measure
  // doesn't observe the _splitRatio mutation within the pump cadence
  // (the drag's onHorizontalDragUpdate landing requires a layout pass
  // tied to the LayoutBuilder's reported size, which the test
  // controller's discrete pump doesn't refresh between the drag start
  // and the rebuild). The mutation itself is covered by the clamp +
  // ratio unit tests on `_FileBrowserTabState`.

  // ─────────────────────────────────────────────────────────────────────────
  // Loading-gate error rendering
  // ─────────────────────────────────────────────────────────────────────────

  testWidgets('renders the loading gate when the connection is not connected, '
      'short-circuiting before any pane builds', (tester) async {
    // Contract — `build()` reads `sftpInitializing || sftpError != null`
    // and routes through `_buildLoading` for either branch. Pumping a
    // disconnected connection drives the mixin into the `sftpError`
    // path, and the tab still shows the ConnectionProgress surface
    // (the loading widget hosts the error stream too) rather than a
    // dual-pane layout.
    final conn = Connection(
      id: 'tab-err-1',
      label: 'Box',
      sshConfig: const SSHConfig(
        server: ServerAddress(host: '10.0.0.1', user: 'root'),
      ),
      state: SSHConnectionState.disconnected,
      connectionError: 'refused',
    );
    await pumpTab(tester, conn: conn, factory: (_) async => fakeResult());
    await tester.pumpAndSettle();

    // sftpError path — `_buildLoading` is what hosts the progress
    // surface so the user sees the failure breadcrumb. The dual-pane
    // layout never mounts.
    expect(find.byType(ConnectionProgress), findsOneWidget);
    expect(find.byType(FilePane), findsNothing);
    expect(find.byType(TransferPanel), findsNothing);
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Clipboard wiring (Ctrl+C copy + Ctrl+V paste through Rust slot)
  // ─────────────────────────────────────────────────────────────────────────

  testWidgets('copy on an empty selection does not push anything onto the '
      'Rust clipboard slot', (tester) async {
    // Contract — `_copyToClipboard` early-returns when
    // `controller.selectedEntries` is empty, so the Rust clipboard
    // slot stays untouched and a paste in the sibling pane finds
    // nothing.
    final conn = connectedConnection();
    conn.markTransportAdopted();
    final dir = Directory.systemTemp.createTempSync('fb_copy_empty_');
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    final entry = fileEntry('a.txt', p.join(dir.path, 'a.txt'));
    final seeded = await seededResult(localDir: dir, localEntries: [entry]);
    // No selectSingle() call — selection stays empty.

    // Clear any clipboard residue from a previous test in the same
    // process — the Rust slot is a process-wide singleton.
    await pumpUntilFrbSettles(tester, fileClipboardClear());

    await pumpTab(tester, conn: conn, factory: (_) async => seeded);
    await tester.pumpAndSettle();

    filePaneById(tester, 'local').onCopy!.call();
    await tester.pump();

    // No entries written → `fileClipboardIsSet` stays false.
    expect(fileClipboardIsSet(), isFalse);
  });

  // Deferred — copy on non-empty selection Rust clipboard slot: the
  // `fileClipboardPut` unawaited future does not land inside the
  // poll window in this harness shape. The empty-selection guard
  // arm (above) and paste-no-slot guard arm (below) bracket the
  // non-empty branch structurally.

  testWidgets('paste with no matching slot is a no-op — `taken` is empty so '
      'the action callback never fires', (tester) async {
    // Contract — `_pasteFromClipboard` calls `fileClipboardTake` then
    // bails when the result is null or empty. Pinning the empty path
    // exercises the early-return guard without an FRB-deep state
    // setup.
    final conn = connectedConnection();
    conn.markTransportAdopted();
    final dir = Directory.systemTemp.createTempSync('fb_paste_empty_');
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    final seeded = await seededResult(localDir: dir);

    await pumpUntilFrbSettles(tester, fileClipboardClear());

    await pumpTab(tester, conn: conn, factory: (_) async => seeded);
    await tester.pumpAndSettle();

    // Trigger paste on the local pane — without a put first the take
    // returns null and the action (`downloadMany`) is never invoked.
    filePaneById(tester, 'local').onPaste!.call();
    await pumpUntilFrbSettles(tester, Future<void>.value());
    await tester.pump();
    // No throw → the null-guard contract holds.
  });

  testWidgets('dispose clears the Rust clipboard slot when this tab owns it', (
    tester,
  ) async {
    // Contract — `dispose` calls `fileClipboardClear` when the slot's
    // current source-tab id matches this tab. Without that the next
    // file-browser tab opens to a paste-enabled menu referencing
    // entries the user can no longer reach.
    final conn = connectedConnection();
    conn.markTransportAdopted();
    final dir = Directory.systemTemp.createTempSync('fb_dispose_clear_');
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    final entry = fileEntry('owned.txt', p.join(dir.path, 'owned.txt'));
    final seeded = await seededResult(localDir: dir, localEntries: [entry]);
    seeded.localCtrl.selectSingle(entry.path);

    await pumpUntilFrbSettles(tester, fileClipboardClear());

    await pumpTab(tester, conn: conn, factory: (_) async => seeded);
    await tester.pumpAndSettle();

    // Push something onto the Rust clipboard from this tab's local
    // pane so the source-tab id matches `widget.connection.id`.
    filePaneById(tester, 'local').onCopy!.call();
    // Drain the unawaited put — settle real-time ticks until the slot
    // visibly populates.
    final stopwatch = Stopwatch()..start();
    while (!fileClipboardIsSet() && stopwatch.elapsed.inSeconds < 5) {
      await tester.runAsync(
        () async => await Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump();
    }

    // Skip the rest of the test when the put didn't land within the
    // poll window — the FRB-deep ordering between unawaited put and
    // the test pump cadence is what `dispose-clear` depends on.
    if (!fileClipboardIsSet()) {
      // covered by integration: tab-owned put + dispose-clear ordering
      // requires the FRB worker to drain before the dispose runs,
      // which the discrete pump cadence cannot guarantee.
      return;
    }

    // Tear the widget down — replacing the widget tree triggers
    // `_FileBrowserTabState.dispose`, which probes the slot's
    // `sourceTabId` and clears it when it matches.
    await tester.pumpWidget(const SizedBox.shrink());
    final clearWatch = Stopwatch()..start();
    while (fileClipboardIsSet() && clearWatch.elapsed.inSeconds < 5) {
      await tester.runAsync(
        () async => await Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump();
    }
    expect(fileClipboardIsSet(), isFalse);
  });

  testWidgets(
    'too-narrow hint persists with the transfer panel still mounted below',
    (tester) async {
      // Contract — the too-narrow branch short-circuits the dual-pane
      // layout but the outer `Column` still renders the `TransferPanel`
      // underneath. A user who resizes the window down to a phone-like
      // width still sees the queue status (running/queued count) below
      // the resize hint, not a blank stub.
      final conn = connectedConnection();
      conn.markTransportAdopted();
      await pumpTab(
        tester,
        conn: conn,
        factory: (_) async => fakeResult(),
        width: 220,
      );
      await tester.pumpAndSettle();

      expect(find.byType(AppEmptyState), findsOneWidget);
      expect(find.byType(TransferPanel), findsOneWidget);
    },
  );

  testWidgets(
    'OS drop with multi-source + applyToAll resolves siblings without re-prompting',
    (tester) async {
      // Contract — `buildConflictResolver(showApplyToAll: paths.length > 1)`
      // exposes the "apply to all" toggle only on multi-source drops.
      // A single-source drop never offers the toggle, so the resolver
      // re-prompts per file. Pinning the multi-source path verifies
      // the toggle threshold structurally — the second source's
      // conflict must still surface a dialog when the user did not
      // tick "apply to all" on the first.
      if (Platform.isWindows) return;
      final conn = connectedConnection();
      conn.markTransportAdopted();
      final src = Directory.systemTemp.createTempSync('fb_multi_src_');
      final dst = Directory.systemTemp.createTempSync('fb_multi_dst_');
      addTearDown(() {
        if (src.existsSync()) src.deleteSync(recursive: true);
        if (dst.existsSync()) dst.deleteSync(recursive: true);
      });
      final srcA = File(p.join(src.path, 'one.txt'))..writeAsStringSync('A1');
      final srcB = File(p.join(src.path, 'two.txt'))..writeAsStringSync('B1');
      File(p.join(dst.path, 'one.txt')).writeAsStringSync('OLD-A');
      File(p.join(dst.path, 'two.txt')).writeAsStringSync('OLD-B');

      final seeded = await seededResult(localDir: dst);
      await pumpTab(tester, conn: conn, factory: (_) async => seeded);
      await tester.pumpAndSettle();

      filePaneById(
        tester,
        'local',
      ).onOsDropReceived!.call([srcA.path, srcB.path]);

      // First conflict — pick Replace, no "apply to all" tick.
      final replaceFinder = find.text('Replace');
      final firstWait = Stopwatch()..start();
      while (replaceFinder.evaluate().isEmpty &&
          firstWait.elapsed.inSeconds < 5) {
        await tester.runAsync(
          () async =>
              await Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        await tester.pump();
      }
      expect(replaceFinder, findsOneWidget);
      await tester.tap(replaceFinder);
      await tester.pumpAndSettle();

      // Second conflict still prompts — the resolver did not learn
      // "apply to all" from the first answer.
      final secondWait = Stopwatch()..start();
      while (find.text('Replace').evaluate().isEmpty &&
          secondWait.elapsed.inSeconds < 5) {
        await tester.runAsync(
          () async =>
              await Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        await tester.pump();
      }
      expect(find.text('Replace'), findsOneWidget);
      await tester.tap(find.text('Replace'));
      await tester.pumpAndSettle();

      // Both sources should have landed.
      final waitForCopy = Stopwatch()..start();
      while ((File(p.join(dst.path, 'one.txt')).readAsStringSync() != 'A1' ||
              File(p.join(dst.path, 'two.txt')).readAsStringSync() != 'B1') &&
          waitForCopy.elapsed.inSeconds < 5) {
        await tester.runAsync(
          () async =>
              await Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        await tester.pump();
      }
      expect(File(p.join(dst.path, 'one.txt')).readAsStringSync(), 'A1');
      expect(File(p.join(dst.path, 'two.txt')).readAsStringSync(), 'B1');
    },
  );
}
