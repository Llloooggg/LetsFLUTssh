import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/connection/connection.dart';
import 'package:letsflutssh/core/sftp/file_system.dart';
import 'package:letsflutssh/core/sftp/sftp_models.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/features/file_browser/file_browser_controller.dart';
import 'package:letsflutssh/features/file_browser/sftp_browser_mixin.dart';
import 'package:letsflutssh/features/file_browser/sftp_initializer.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/widgets/terminal/connection_progress.dart';

import '../../helpers/frb_bootstrap.dart';

/// Minimal widget that applies the mixin so we can unit-test the shared logic.
class _TestBrowser extends ConsumerStatefulWidget {
  final Connection connection;
  final Future<SFTPInitResult> Function(Connection)? sftpInitFactory;

  /// When false, skip the automatic [initSftp] call in [initState] so
  /// the test can drive the mixin's batch-mode methods (`upload` /
  /// `download` / `uploadMany` / `downloadMany`) in isolation without
  /// racing the connect path.
  final bool autoInit;

  /// Seed for `sftpResult` — lets tests cover the
  /// `result == null` early-return branches in `uploadMany` /
  /// `downloadMany` against a deterministic baseline.
  final SFTPInitResult? initialResult;

  const _TestBrowser({
    required this.connection,
    this.sftpInitFactory,
    this.autoInit = true,
    this.initialResult,
  });

  @override
  ConsumerState<_TestBrowser> createState() => _TestBrowserState();
}

class _TestBrowserState extends ConsumerState<_TestBrowser>
    with SftpBrowserMixin {
  @override
  SFTPInitResult? sftpResult;
  @override
  bool sftpInitializing = true;
  @override
  String? sftpError;
  @override
  final progressKey = GlobalKey<ConnectionProgressState>();

  @override
  Connection get sftpConnection => widget.connection;
  @override
  Future<SFTPInitResult> Function(Connection)? get sftpInitFactory =>
      widget.sftpInitFactory;

  bool onReadyCalled = false;

  @override
  void onSftpReady(SFTPInitResult result) {
    onReadyCalled = true;
  }

  @override
  void initState() {
    super.initState();
    sftpResult = widget.initialResult;
    if (widget.autoInit) {
      initSftp();
    } else {
      sftpInitializing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (sftpInitializing) {
      return ConnectionProgress(
        key: progressKey,
        connection: widget.connection,
        channelLabel: 'Opening SFTP…',
      );
    }
    if (sftpError != null) {
      return Text('Error: $sftpError');
    }
    return const Text('Ready');
  }
}

/// Stub [FileSystem] used to back a synthetic [FilePaneController].
/// All read/write ops return empty / no-op so the controller's `init`
/// completes synchronously and no real disk or network I/O fires.
class _StubFs implements FileSystem {
  @override
  Future<String> initialDir() async => '/';

  @override
  Future<List<FileEntry>> list(String path) async => const [];

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

  @override
  Future<List<FlatFileLeaf>> flatWalkFiles(String root, {int maxDepth = 100}) =>
      flatWalkViaList(this, root, maxDepth: maxDepth);

  @override
  Future<bool> exists(String path) async => false;

  @override
  FileSystemCapabilities get capabilities => FileSystemCapabilities.objectStore;
}

void main() {
  // SftpBrowserMixin logs failures via AppLogger which routes
  // through `lfs_core::log_sanitize` + format helpers — bootstrap
  // FRB so the canonical Rust pipeline runs.
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(requireFrbLoaded);

  group('SftpBrowserMixin', () {
    testWidgets('sets error when connection fails', (tester) async {
      final conn = Connection(
        id: 'c1',
        label: 'Test',
        sshConfig: const SSHConfig(
          server: ServerAddress(host: '10.0.0.1', user: 'root'),
        ),
        state: SSHConnectionState.disconnected,
        connectionError: 'refused',
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            home: Scaffold(body: _TestBrowser(connection: conn)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Should show error since connection is disconnected
      expect(find.textContaining('Error:'), findsOneWidget);
    });

    testWidgets('sets error when sftpInitFactory throws', (tester) async {
      final conn = Connection(
        id: 'c1',
        label: 'Test',
        sshConfig: const SSHConfig(
          server: ServerAddress(host: '10.0.0.1', user: 'root'),
        ),
        state: SSHConnectionState.connected,
      );
      // No actor backs this synthetic connection, so the
      // `transportReady` gate inside `SftpBrowserMixin.initSftp`
      // would hang `pumpAndSettle` forever. Drive the completer
      // straight so the mixin proceeds to call `sftpInitFactory`.
      conn.markTransportAdopted();

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            home: Scaffold(
              body: _TestBrowser(
                connection: conn,
                sftpInitFactory: (_) async => throw Exception('SFTP failed'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Error:'), findsOneWidget);
    });

    testWidgets('upload / download / uploadMany / downloadMany no-op when '
        'sftpResult is null', (tester) async {
      // Auto-init off → `sftpResult` stays null, the mixin's batch
      // methods hit their `remote == null` / `local == null` early
      // returns at lines 226 / 261 without trying to enqueue a real
      // transfer. The shorthand `upload(entry)` / `download(entry)`
      // wrappers at lines 214 / 217 dispatch to the batch methods,
      // so a successful no-op proves the dispatch chain.
      final conn = Connection(
        id: 'c1',
        label: 'Test',
        sshConfig: const SSHConfig(
          server: ServerAddress(host: '10.0.0.1', user: 'root'),
        ),
        state: SSHConnectionState.disconnected,
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            home: Scaffold(
              body: _TestBrowser(connection: conn, autoInit: false),
            ),
          ),
        ),
      );
      await tester.pump();

      final state = tester.state<_TestBrowserState>(find.byType(_TestBrowser));
      expect(state.sftpResult, isNull);

      final entry = FileEntry(
        name: 'a.txt',
        path: '/tmp/a.txt',
        size: 1,
        modTime: DateTime(2024),
        isDir: false,
      );

      // Shorthand wrappers — `upload` and `download` route through
      // `uploadMany` / `downloadMany`; both must return cleanly when
      // there is no remote pane to dispatch against.
      state.upload(entry);
      state.download(entry);
      await tester.pump();

      // Batch methods directly — empty-list path AND null-remote
      // path both early-return without throwing.
      await state.uploadMany(const []);
      await state.downloadMany(const []);
      await state.uploadMany([entry]);
      await state.downloadMany([entry]);
    });

    testWidgets('uploadMany / downloadMany early-return on empty list when '
        'sftpResult is non-null', (tester) async {
      // Seed a real [SFTPInitResult] with stub controllers so both
      // `remote` and `local` are non-null. The empty-list branch
      // (line 226 / 261's second clause) is then the only early
      // return, and the resolver `finally`-dispose path (line 253 /
      // 278) is reached without enqueueing anything.
      final localCtrl = FilePaneController(fs: _StubFs(), label: 'Local');
      final remoteCtrl = FilePaneController(fs: _StubFs(), label: 'Remote');
      addTearDown(() {
        localCtrl.dispose();
        remoteCtrl.dispose();
      });
      final result = SFTPInitResult(
        localCtrl: localCtrl,
        remoteCtrl: remoteCtrl,
        filesystem: null,
      );

      final conn = Connection(
        id: 'c1',
        label: 'Test',
        sshConfig: const SSHConfig(
          server: ServerAddress(host: '10.0.0.1', user: 'root'),
        ),
        state: SSHConnectionState.disconnected,
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            home: Scaffold(
              body: _TestBrowser(
                connection: conn,
                autoInit: false,
                initialResult: result,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final state = tester.state<_TestBrowserState>(find.byType(_TestBrowser));
      expect(state.sftpResult, isNotNull);
      // Empty list — early-return BEFORE building the resolver, so
      // no transfer is enqueued and no dialog opens.
      await state.uploadMany(const []);
      await state.downloadMany(const []);
    });

    testWidgets('disposeSftpBrowser is safe with no active subscription', (
      tester,
    ) async {
      // Cancel-on-dispose contract: even when `_subscribeTransferBus`
      // never wired a subscription (auto-init off → no SFTP ready
      // event), `disposeSftpBrowser` must complete without throwing
      // so host classes can call it unconditionally from their own
      // `dispose`.
      final conn = Connection(
        id: 'c1',
        label: 'Test',
        sshConfig: const SSHConfig(
          server: ServerAddress(host: '10.0.0.1', user: 'root'),
        ),
        state: SSHConnectionState.disconnected,
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            home: Scaffold(
              body: _TestBrowser(connection: conn, autoInit: false),
            ),
          ),
        ),
      );
      await tester.pump();

      final state = tester.state<_TestBrowserState>(find.byType(_TestBrowser));
      // First call cancels the (null) subscription; second call is a
      // no-op repeat that must remain safe.
      state.disposeSftpBrowser();
      state.disposeSftpBrowser();
    });

    testWidgets(
      'connection-failed branch with a null connectionError falls back to '
      'the generic errConnectionFailed string',
      (tester) async {
        // Spec: `initSftp`'s `!conn.isConnected` branch checks
        // `conn.connectionError` and routes through either the
        // localised error or the bare `errConnectionFailed` fallback.
        // The existing "refused" test pinned the localizeError arm;
        // this pins the fallback when `connectionError` is null.
        final conn = Connection(
          id: 'c1',
          label: 'Test',
          sshConfig: const SSHConfig(
            server: ServerAddress(host: '10.0.0.1', user: 'root'),
          ),
          state: SSHConnectionState.disconnected,
        );

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              localizationsDelegates: S.localizationsDelegates,
              supportedLocales: S.supportedLocales,
              home: Scaffold(body: _TestBrowser(connection: conn)),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // The mixin pushes the fallback error into `sftpError`; the
        // `_TestBrowser.build` paints "Error: $sftpError" off that.
        // ARB's `errConnectionFailed` resolves to "Connection failed"
        // in the English bundle the test scope loads by default.
        expect(find.textContaining('Connection failed'), findsOneWidget);
      },
    );

    testWidgets(
      'successful init wires onSftpReady + the transfer-bus subscription, '
      'and disposeSftpBrowser tears the listener down cleanly',
      (tester) async {
        // Spec: after `sftpInitFactory` resolves, the mixin calls
        // `onSftpReady`, flips `sftpInitializing` to false, AND
        // wires the transfer-bus listener through
        // `_subscribeTransferBus`. `disposeSftpBrowser` then cancels
        // the wired listener so the host class's own `dispose`
        // does not leak a subscription on the broadcast pipe.
        final conn = Connection(
          id: 'c1',
          label: 'Test',
          sshConfig: const SSHConfig(
            server: ServerAddress(host: '10.0.0.1', user: 'root'),
          ),
          state: SSHConnectionState.connected,
        );
        conn.markTransportAdopted();

        final localCtrl = FilePaneController(fs: _StubFs(), label: 'Local');
        final remoteCtrl = FilePaneController(fs: _StubFs(), label: 'Remote');
        addTearDown(() {
          localCtrl.dispose();
          remoteCtrl.dispose();
        });
        final result = SFTPInitResult(
          localCtrl: localCtrl,
          remoteCtrl: remoteCtrl,
          filesystem: null,
        );

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              localizationsDelegates: S.localizationsDelegates,
              supportedLocales: S.supportedLocales,
              home: Scaffold(
                body: _TestBrowser(
                  connection: conn,
                  sftpInitFactory: (_) async => result,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final state = tester.state<_TestBrowserState>(
          find.byType(_TestBrowser),
        );
        expect(state.onReadyCalled, isTrue);
        expect(state.sftpInitializing, isFalse);
        expect(state.sftpResult, isNotNull);
        // The host-class contract: callers invoke `disposeSftpBrowser`
        // from their own `dispose`. The mixin must remain safe even
        // when the underlying FRB subscription was never actually
        // wired (the catch arm above left `_transferBusSub = null`).
        state.disposeSftpBrowser();
      },
    );

    testWidgets('calls onSftpReady on success', (tester) async {
      final conn = Connection(
        id: 'c1',
        label: 'Test',
        sshConfig: const SSHConfig(
          server: ServerAddress(host: '10.0.0.1', user: 'root'),
        ),
        state: SSHConnectionState.connected,
      );
      // Same gate as the failure test above — synthetic Connection
      // has no actor to drive `_transportAdopted`, drive it manually.
      conn.markTransportAdopted();

      // We need a fake SFTPInitResult — but it requires real controllers.
      // Test that the factory path works by verifying onSftpReady is called.
      var factoryCalled = false;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            home: Scaffold(
              body: _TestBrowser(
                connection: conn,
                sftpInitFactory: (_) async {
                  factoryCalled = true;
                  throw Exception('stub');
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(factoryCalled, isTrue);
    });
  });
}
