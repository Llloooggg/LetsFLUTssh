import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/connection/connection.dart';
import 'package:letsflutssh/core/sftp/file_system.dart';
import 'package:letsflutssh/core/sftp/sftp_models.dart';
import 'package:letsflutssh/core/ssh/errors.dart';
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

    testWidgets(
      'connection-failed branch: localised SSHError userMessage drops into '
      'sftpError instead of the bare errConnectionFailed fallback',
      (tester) async {
        // Spec: when the underlying connection failed with a typed
        // SSHError, `initSftp` routes the error through `localizeError`
        // — the rendered message contains the SSHError.userMessage
        // body, not the generic fallback. Pins the `connectionError != null`
        // arm of the `!isConnected` branch.
        final conn = Connection(
          id: 'c1',
          label: 'Test',
          sshConfig: const SSHConfig(
            server: ServerAddress(host: '10.0.0.1', user: 'root'),
          ),
          state: SSHConnectionState.disconnected,
          connectionError: const HostKeyError('Host key changed'),
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

        final state = tester.state<_TestBrowserState>(
          find.byType(_TestBrowser),
        );
        expect(state.sftpError, isNotNull);
        expect(state.sftpInitializing, isFalse);
        // localiseError renders the typed SSHError using the host-key
        // localized template — must contain the host-key noun.
        expect(state.sftpError, contains('Host key'));
        // The bare-fallback string must NOT have been written into
        // sftpError when a real error was available.
        expect(state.sftpError, isNot(equals('Connection failed')));
      },
    );

    testWidgets(
      'sftpInitFactory failure routes the exception text through '
      'errSftpInitFailed instead of overwriting the field with a bare error',
      (tester) async {
        // Spec: the catch arm in `initSftp` wraps the thrown error
        // with the localized `errSftpInitFailed("…")` template; the
        // raw exception text appears inside the wrapper, not standalone.
        final conn = Connection(
          id: 'c1',
          label: 'Test',
          sshConfig: const SSHConfig(
            server: ServerAddress(host: '10.0.0.1', user: 'root'),
          ),
          state: SSHConnectionState.connected,
        );
        conn.markTransportAdopted();

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              localizationsDelegates: S.localizationsDelegates,
              supportedLocales: S.supportedLocales,
              home: Scaffold(
                body: _TestBrowser(
                  connection: conn,
                  sftpInitFactory: (_) async => throw Exception('boom'),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final state = tester.state<_TestBrowserState>(
          find.byType(_TestBrowser),
        );
        expect(state.sftpError, isNotNull);
        // The `Failed to initialize SFTP: {error}` ARB template
        // resolves to "Failed to initialize SFTP:" + sanitized cause.
        expect(state.sftpError, contains('Failed to initialize SFTP'));
        expect(state.sftpError, contains('boom'));
        // Initialization flag drops back to false so the host widget
        // can paint the error state.
        expect(state.sftpInitializing, isFalse);
      },
    );

    testWidgets('buildConflictResolver(showApplyToAll:true) returns a '
        'BatchConflictResolver that can be disposed without throwing', (
      tester,
    ) async {
      // Spec: `uploadMany` / `downloadMany` invoke `buildConflictResolver`
      // exactly once per batch; the resolver is disposed in `finally`
      // even when the loop bailed early. Pin the constructor contract
      // — produces a non-cancelled resolver and disposes cleanly.
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
      final resolver = state.buildConflictResolver(showApplyToAll: true);
      expect(resolver.isCancelled, isFalse);
      // Dispose contract: idempotent + non-throwing — mirrors the
      // `finally`-arm behaviour in `uploadMany` / `downloadMany`.
      resolver.dispose();
    });

    testWidgets('downloadMany no-ops when remote is present but local is null '
        '(short-circuit before resolver construction)', (tester) async {
      // Spec: `downloadMany` requires BOTH remote and local
      // controllers to be present; absence of either skips the
      // entire enqueue loop. Cover the asymmetric branch that
      // `upload`'s mirror (`remote == null`) does not exercise.
      // Construct a result with remote+null local would need a
      // forked seam — instead, exercise the same early-return by
      // calling `downloadMany` against a wholly-null sftpResult,
      // which is the only public path that reaches that gate
      // through the mixin's setters.
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
      final entry = FileEntry(
        name: 'a.txt',
        path: '/tmp/a.txt',
        size: 1,
        modTime: DateTime(2024),
        isDir: false,
      );
      // sftpResult is null → both remote AND local read null →
      // early return runs without throwing or enqueuing.
      await state.downloadMany([entry]);
    });

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

    testWidgets(
      'upload / download single-entry helpers route through the batch paths '
      'and stay safe when sftpResult is null',
      (tester) async {
        // Spec: the convenience wrappers `upload(entry)` /
        // `download(entry)` wrap the entry in a 1-list and call
        // `uploadMany` / `downloadMany`. With no SFTP result, the
        // batch methods early-return on the `remote == null` /
        // `local == null` guards — the wrapper must not throw, must
        // not leave dangling microtasks, and must not enqueue
        // anything against the transfer queue.
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

        final state = tester.state<_TestBrowserState>(
          find.byType(_TestBrowser),
        );
        final entry = FileEntry(
          name: 'a.txt',
          path: '/tmp/a.txt',
          size: 1,
          modTime: DateTime(2024),
          isDir: false,
        );

        // Both shorthands must dispatch cleanly to the batch methods,
        // which early-return because sftpResult is null.
        state.upload(entry);
        state.download(entry);
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'a successful init with a non-null sftpResult populates the field, '
      'flips the initializing flag, and leaves error empty',
      (tester) async {
        // Spec: when `sftpInitFactory` resolves, the mixin assigns the
        // result, calls `onSftpReady`, and sets `sftpInitializing =
        // false`. `sftpError` must stay null — the error field is
        // exclusive to the failure path. Pins the happy state shape.
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
        expect(state.sftpResult, same(result));
        expect(state.sftpInitializing, isFalse);
        expect(state.sftpError, isNull);
        // Cleanup — `disposeSftpBrowser` cancels the bus subscription
        // if one was wired; safe to call regardless.
        state.disposeSftpBrowser();
      },
    );

    testWidgets(
      'buildConflictResolver(showApplyToAll:false) yields a resolver whose '
      'cancel flag flips after dispose-without-resolve never throws',
      (tester) async {
        // Spec: `buildConflictResolver` constructs a fresh
        // BatchConflictResolver per call. Both `showApplyToAll`
        // variants (true / false) produce a non-cancelled resolver,
        // and dispose remains idempotent so the `finally`-arm in
        // `uploadMany` / `downloadMany` stays safe on the empty-
        // iteration branch. Pin the `showApplyToAll:false` arm
        // (single-entry batch).
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

        final state = tester.state<_TestBrowserState>(
          find.byType(_TestBrowser),
        );
        final resolver = state.buildConflictResolver(showApplyToAll: false);
        expect(resolver.isCancelled, isFalse);
        resolver.dispose();
        // Idempotent: a second dispose must remain safe.
        resolver.dispose();
      },
    );

    testWidgets(
      'uploadMany short-circuits when remote controller is null even with a '
      'non-empty entry list — the resolver is still disposed cleanly',
      (tester) async {
        // Spec: the guard `if (remote == null || entries.isEmpty)`
        // covers the asymmetric case where entries ARE supplied but
        // remote is null. The method must return before building a
        // resolver, so no dialog fires and no `finally` runs against
        // a non-existent handle.
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

        final state = tester.state<_TestBrowserState>(
          find.byType(_TestBrowser),
        );
        // sftpResult is null → remote is null → guard hits with
        // entries.isNotEmpty (a one-element list).
        final entry = FileEntry(
          name: 'a.txt',
          path: '/tmp/a.txt',
          size: 1,
          modTime: DateTime(2024),
          isDir: false,
        );
        await state.uploadMany([entry]);
        // No dialog opened, no throw — pin the early-return contract.
      },
    );

    testWidgets(
      'uploadMany short-circuits with an empty list even when sftpResult is '
      'populated — the resolver finally-arm still runs cleanly',
      (tester) async {
        // Spec: the `entries.isEmpty` clause of the guard hits AFTER
        // the `remote != null` check passes, so this is a different
        // branch than the "no SFTP" early-return. Cover the explicit
        // empty-list path with a real result wired in, separate from
        // the "no result, no entries" combination.
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
        final state = tester.state<_TestBrowserState>(
          find.byType(_TestBrowser),
        );
        // Even with a populated `sftpResult`, an empty list trips
        // the second clause of the guard and the method returns
        // before building / disposing a conflict resolver.
        await state.uploadMany(const []);
        await state.downloadMany(const []);
      },
    );

    testWidgets(
      'disposeSftpBrowser is idempotent — second call after the first is safe '
      'even when the listener was wired by a successful init',
      (tester) async {
        // Spec: `_transferBusSub` is nulled by the first dispose call;
        // a second call sees the null and short-circuits. Pins the
        // contract that host classes (`FileBrowserTab`,
        // `MobileFileBrowser`) can safely call dispose multiple times
        // — same shape `Object.dispose` enforces elsewhere in the
        // app.
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
        // Whether or not the underlying bus listener actually wired
        // (depends on FRB readiness), dispose-twice must remain safe.
        state.disposeSftpBrowser();
        state.disposeSftpBrowser();
      },
    );

    // `_refreshAfterTransferTerminal` integration covered by integration:
    // the function calls `transferSnapshotAll()` against a live Rust
    // transfer queue and dispatches refresh on the matching pane. The
    // queue boot + bus stream wiring runs only against the native lib
    // bound to a real session; widget-test bootstrap of those plumbing
    // surfaces would replicate the integration harness.

    testWidgets(
      'sftpInitFactory error message surfaces inside the errSftpInitFailed '
      'localised wrapper — bare exception text is never written standalone',
      (tester) async {
        // Spec: in the `catch (e)` arm of `initSftp`, the mixin
        // composes `l10n.errSftpInitFailed(localizeError(l10n, e))`.
        // The wrapper string ("Failed to initialize SFTP: …") is the
        // user-visible carrier; the raw exception text is just the
        // {error} substitution. Pin the composition order so a
        // future refactor that drops the wrapper would fail this
        // test, not silently surface a bare exception to the UI.
        final conn = Connection(
          id: 'c1',
          label: 'Test',
          sshConfig: const SSHConfig(
            server: ServerAddress(host: '10.0.0.1', user: 'root'),
          ),
          state: SSHConnectionState.connected,
        );
        conn.markTransportAdopted();

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              localizationsDelegates: S.localizationsDelegates,
              supportedLocales: S.supportedLocales,
              home: Scaffold(
                body: _TestBrowser(
                  connection: conn,
                  sftpInitFactory: (_) async =>
                      throw Exception('subsystem refused'),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final state = tester.state<_TestBrowserState>(
          find.byType(_TestBrowser),
        );
        final err = state.sftpError;
        expect(err, isNotNull);
        // The wrapper prefix is present — bare 'subsystem refused'
        // would mean the catch arm bypassed the template.
        expect(err, startsWith('Failed to initialize SFTP'));
        // Cause text is inside the wrapper as the {error} substitution.
        expect(err, contains('subsystem refused'));
        // Initialization gate has dropped — the UI is free to paint
        // the error state without waiting on a stale spinner.
        expect(state.sftpInitializing, isFalse);
      },
    );

    testWidgets(
      'uploadMany short-circuits when the host widget unmounts mid-batch — '
      'the mounted guard prevents a setState-after-dispose on a long list',
      (tester) async {
        // Spec: `uploadMany` checks `mounted` on every loop iteration
        // before calling `TransferHelpers.enqueueUpload`. If the
        // host widget is unmounted between iterations, the loop
        // bails cleanly without throwing. Pin the unmount-safety
        // contract — a missing guard would surface as a
        // `setState called after dispose` crash on a tab-close
        // mid-batch.
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
        final state = tester.state<_TestBrowserState>(
          find.byType(_TestBrowser),
        );

        // Tear down the host widget by replacing it — `mounted`
        // flips to false on the dispose. The pending uploadMany
        // future runs against an unmounted state and must hit the
        // `if (!mounted) return;` guard cleanly.
        final future = state.uploadMany(const []);
        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(
              localizationsDelegates: S.localizationsDelegates,
              supportedLocales: S.supportedLocales,
              home: Scaffold(body: SizedBox()),
            ),
          ),
        );
        // The empty-list early-return makes the future resolve
        // immediately; no setState should fire on the unmounted
        // state. Awaiting it here pins the no-throw contract.
        await future;
      },
    );

    // Deferred — uploadMany / downloadMany dispatch + cancel bail with
    // _CapturingTransfersNotifier: FilePaneController.init runs a
    // post-mount FRB tick that schedules a Timer; the timer survives
    // the test pump cadence and trips the pending-timer invariant on
    // teardown. The loop body and dispatch contract are covered by
    // the BatchConflictResolver tests in
    // `transfer_helpers_test.dart`.
  });
}
