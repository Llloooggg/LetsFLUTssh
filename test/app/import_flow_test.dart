import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:meta/meta.dart' show isTest;
import 'package:letsflutssh/app/import_flow.dart';
import 'package:letsflutssh/core/session/qr_codec.dart';
import 'package:letsflutssh/core/session/qr_decoded_source.dart';
import 'package:letsflutssh/core/import/export_import.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/providers/config_provider.dart';
import 'package:letsflutssh/src/rust/api/archive.dart' as rust_archive;
import 'package:letsflutssh/app/navigator_key.dart';
import 'package:letsflutssh/widgets/import_export/lfs_import_dialog.dart';
import 'package:letsflutssh/widgets/import_export/link_import_preview_dialog.dart';
import 'package:letsflutssh/widgets/core/toast.dart';

import '../helpers/frb_bootstrap.dart';
import '../helpers/test_notifiers.dart';

/// Recorded calls so each test can assert that the right rust seam
/// fired with the expected payload (handle id passes from open →
/// apply, drop only fires on the post-stage failure path, etc.).
class _CallLog {
  final List<({String path, String password})> openCalls = [];
  final List<
    ({
      String handleId,
      ImportMode mode,
      bool applySessions,
      bool applyKeys,
      bool applyTags,
      bool applySnippets,
      bool applyKnownHosts,
      bool applyRecordings,
      bool refreshProvided,
    })
  >
  applyCalls = [];
  final List<String> dropCalls = [];
  final List<String> probeCalls = [];
  int lfsDialogShown = 0;
  int linkDialogShown = 0;
}

rust_archive.DbImportPreview _previewWith({
  bool hasKnownHosts = false,
  int recordingCount = 0,
}) => rust_archive.DbImportPreview(
  schemaVersion: 1,
  sessionCount: 1,
  sessionLabels: const ['demo'],
  managerKeyCount: 0,
  tagCount: 0,
  snippetCount: 0,
  emptyFolderCount: 0,
  hasConfig: false,
  hasKnownHosts: hasKnownHosts,
  recordingCount: recordingCount,
);

rust_archive.DbApplyResult _applyResult({
  int sessions = 1,
  int keys = 0,
  int tags = 0,
  int snippets = 0,
  int knownHosts = 0,
  int linksSkipped = 0,
  String? configJson,
  bool rolledBack = false,
}) => rust_archive.DbApplyResult(
  sessionsApplied: sessions,
  keysApplied: keys,
  keysSkippedDedup: 0,
  tagsApplied: tags,
  snippetsApplied: snippets,
  knownHostsApplied: knownHosts,
  foldersApplied: 0,
  sessionTagsApplied: 0,
  folderTagsApplied: 0,
  sessionSnippetsApplied: 0,
  linksSkipped: linksSkipped,
  errors: const [],
  configJson: configJson,
  rolledBack: rolledBack,
);

ImportFlowSeams _seams({
  required _CallLog log,
  LfsArchiveKind probeKind = LfsArchiveKind.encryptedLfs,
  rust_archive.DbImportPreview? openPreview,
  Object? openThrows,
  rust_archive.DbApplyResult Function()? applyResult,
  Object? applyThrows,
  LfsImportDialogResult? lfsDialogResult,
  LinkImportPreviewResult? linkDialogResult,
}) {
  return ImportFlowSeams(
    probeArchive: (path) async {
      log.probeCalls.add(path);
      return probeKind;
    },
    openArchive: ({required path, required password}) async {
      log.openCalls.add((path: path, password: password));
      if (openThrows != null) throw openThrows;
      return rust_archive.DbImportOpenResult(
        handleId: 'h-1',
        preview: openPreview ?? _previewWith(),
      );
    },
    dropHandle: ({required handleId}) async {
      log.dropCalls.add(handleId);
    },
    applyHandle:
        ({
          required handleId,
          required mode,
          required selection,
          refreshAfterImport,
        }) async {
          log.applyCalls.add((
            handleId: handleId,
            mode: mode,
            applySessions: selection.sessions,
            applyKeys: selection.keys,
            applyTags: selection.tags,
            applySnippets: selection.snippets,
            applyKnownHosts: selection.knownHosts,
            applyRecordings: selection.recordings,
            refreshProvided: refreshAfterImport != null,
          ));
          if (applyThrows != null) throw applyThrows;
          return (applyResult ?? _applyResult)();
        },
    showLfsDialog: (context, {required filePath, isEncrypted = true}) async {
      log.lfsDialogShown += 1;
      return lfsDialogResult;
    },
    showLinkPreviewDialog: (context, {required source}) async {
      log.linkDialogShown += 1;
      return linkDialogResult;
    },
  );
}

Widget _wrapApp({
  required Widget child,
  List<Override> overrides = const [],
  bool useGlobalNavigatorKey = false,
}) {
  return ProviderScope(
    overrides: [
      configProvider.overrideWith(TestConfigNotifier.new),
      ...overrides,
    ],
    child: MaterialApp(
      // handleQrImport reads navigatorKey.currentContext to route the
      // post-frame toast — wire the global key through MaterialApp so
      // the deeplink entry point becomes reachable from a unit test.
      navigatorKey: useGlobalNavigatorKey ? navigatorKey : null,
      localizationsDelegates: S.localizationsDelegates,
      supportedLocales: S.supportedLocales,
      home: Scaffold(body: child),
    ),
  );
}

Widget _triggerButton(
  String label,
  Future<void> Function(BuildContext, WidgetRef) action,
) {
  return Consumer(
    builder: (context, ref, _) {
      return ElevatedButton(
        onPressed: () => action(context, ref),
        child: Text(label),
      );
    },
  );
}

/// Wrap the test body so the toast timer (3 s auto-hide) gets
/// cancelled before flutter_test's pending-timer invariant check
/// runs. The outer `tearDown` fires too late — the binding asserts
/// `!timersPending` between the test body and tearDown.
@isTest
void _testFlow(
  String description,
  Future<void> Function(WidgetTester tester) body,
) {
  testWidgets(description, (tester) async {
    try {
      await body(tester);
    } finally {
      Toast.clearAllForTest();
    }
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // `decodeConfigFromApply` (used by handleQrImportSource + showLfsImportDialog)
  // routes through `configAppConfigFromJsonTyped` FRB sync — no Dart-side
  // codec to fall back on, so the native lib must be loaded before any
  // test that exercises the config-restore branch.
  setUpAll(requireFrbLoaded);

  tearDown(() {
    debugSetImportFlowSeams(null);
    Toast.clearAllForTest();
  });

  group('showLfsImportDialog', () {
    _testFlow('rejects notLfs archive with error toast and no rust calls', (
      tester,
    ) async {
      final log = _CallLog();
      debugSetImportFlowSeams(
        _seams(log: log, probeKind: LfsArchiveKind.notLfs),
      );

      await tester.pumpWidget(
        _wrapApp(
          child: _triggerButton(
            'go',
            (ctx, ref) => showLfsImportDialog(ctx, ref, '/tmp/foo.txt'),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(log.probeCalls, ['/tmp/foo.txt']);
      expect(log.lfsDialogShown, 0);
      expect(log.openCalls, isEmpty);
      expect(log.applyCalls, isEmpty);
      expect(log.dropCalls, isEmpty);
      expect(
        find.text('Selected file is not a LetsFLUTssh archive.'),
        findsOneWidget,
      );
    });

    _testFlow('cancelled password dialog short-circuits without rust calls', (
      tester,
    ) async {
      final log = _CallLog();
      debugSetImportFlowSeams(_seams(log: log, lfsDialogResult: null));

      await tester.pumpWidget(
        _wrapApp(
          child: _triggerButton(
            'go',
            (ctx, ref) => showLfsImportDialog(ctx, ref, '/tmp/x.lfs'),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pump();
      await tester.pump();

      expect(log.lfsDialogShown, 1);
      expect(log.openCalls, isEmpty);
      expect(log.applyCalls, isEmpty);
      expect(log.dropCalls, isEmpty);
    });

    _testFlow(
      'encrypted archive: open + apply called with merge mode, success toast',
      (tester) async {
        final log = _CallLog();
        debugSetImportFlowSeams(
          _seams(
            log: log,
            openPreview: _previewWith(hasKnownHosts: true),
            applyResult: () => _applyResult(sessions: 3, knownHosts: 1),
            lfsDialogResult: (password: 'secret', mode: ImportMode.merge),
          ),
        );

        await tester.pumpWidget(
          _wrapApp(
            child: _triggerButton(
              'go',
              (ctx, ref) => showLfsImportDialog(ctx, ref, '/tmp/x.lfs'),
            ),
          ),
        );
        await tester.tap(find.text('go'));
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        expect(log.openCalls, [(path: '/tmp/x.lfs', password: 'secret')]);
        expect(log.applyCalls.single.handleId, 'h-1');
        expect(log.applyCalls.single.mode, ImportMode.merge);
        expect(log.applyCalls.single.applyKnownHosts, isTrue);
        expect(log.applyCalls.single.refreshProvided, isTrue);
        // Drop only on staged-handle failure path; success consumes the
        // handle inside applyHandle.
        expect(log.dropCalls, isEmpty);
        // formatImportSummary head reuses the localised plural.
        expect(find.textContaining('3'), findsWidgets);
      },
    );

    _testFlow('apply links_skipped surfaces in the success toast notes', (
      tester,
    ) async {
      final log = _CallLog();
      debugSetImportFlowSeams(
        _seams(
          log: log,
          openPreview: _previewWith(hasKnownHosts: false),
          applyResult: () => _applyResult(sessions: 1, linksSkipped: 2),
          lfsDialogResult: (password: 'secret', mode: ImportMode.merge),
        ),
      );

      await tester.pumpWidget(
        _wrapApp(
          child: _triggerButton(
            'go',
            (ctx, ref) => showLfsImportDialog(ctx, ref, '/tmp/x.lfs'),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      // The Rust-reported dropped-link count must reach the toast —
      // the note branch was dead before the count was plumbed through.
      expect(find.textContaining('dropped'), findsWidgets);
    });

    _testFlow('plaintext archive: empty password threads through to open', (
      tester,
    ) async {
      final log = _CallLog();
      debugSetImportFlowSeams(
        _seams(
          log: log,
          probeKind: LfsArchiveKind.unencryptedLfs,
          lfsDialogResult: (password: '', mode: ImportMode.merge),
        ),
      );

      await tester.pumpWidget(
        _wrapApp(
          child: _triggerButton(
            'go',
            (ctx, ref) => showLfsImportDialog(ctx, ref, '/tmp/p.lfs'),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pump();
      await tester.pump();

      expect(log.openCalls, [(path: '/tmp/p.lfs', password: '')]);
      expect(log.applyCalls, hasLength(1));
    });

    _testFlow('open throws: error toast, drop not called (no handle yet)', (
      tester,
    ) async {
      final log = _CallLog();
      debugSetImportFlowSeams(
        _seams(
          log: log,
          openThrows: const LfsDecryptionFailedException(),
          lfsDialogResult: (password: 'wrong', mode: ImportMode.merge),
        ),
      );

      await tester.pumpWidget(
        _wrapApp(
          child: _triggerButton(
            'go',
            (ctx, ref) => showLfsImportDialog(ctx, ref, '/tmp/x.lfs'),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(log.openCalls, hasLength(1));
      expect(log.applyCalls, isEmpty);
      expect(log.dropCalls, isEmpty);
      expect(find.textContaining('Import failed'), findsOneWidget);
    });

    _testFlow('apply throws: drop fires with the staged handle', (
      tester,
    ) async {
      final log = _CallLog();
      debugSetImportFlowSeams(
        _seams(
          log: log,
          applyThrows: const LfsDecryptionFailedException(),
          lfsDialogResult: (password: 'p', mode: ImportMode.merge),
        ),
      );

      await tester.pumpWidget(
        _wrapApp(
          child: _triggerButton(
            'go',
            (ctx, ref) => showLfsImportDialog(ctx, ref, '/tmp/x.lfs'),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pump();
      await tester.pump();

      expect(log.openCalls, hasLength(1));
      expect(log.applyCalls, hasLength(1));
      // Handle was registered before applyHandle threw → must be released.
      expect(log.dropCalls, ['h-1']);
    });

    _testFlow(
      'rolledBack apply surfaces errLfsImportRolledBack in the error toast',
      (tester) async {
        // Spec: `_summaryFromApply` throws [LfsImportRolledBackException]
        // when the Rust apply reports `rolledBack: true`. The catch arm
        // in `_applyLfsImport` routes the exception through `localizeError`,
        // which maps that exception to the "data restored" string —
        // distinct from the generic "Import failed" copy.
        final log = _CallLog();
        debugSetImportFlowSeams(
          _seams(
            log: log,
            applyResult: () => _applyResult(rolledBack: true),
            lfsDialogResult: (password: 'p', mode: ImportMode.replace),
          ),
        );

        await tester.pumpWidget(
          _wrapApp(
            child: _triggerButton(
              'go',
              (ctx, ref) => showLfsImportDialog(ctx, ref, '/tmp/x.lfs'),
            ),
          ),
        );
        await tester.tap(find.text('go'));
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        // The localized template embeds "your data has been restored";
        // assert on a stable substring so the test does not pin the
        // entire wording of the ARB string.
        expect(find.textContaining('restored'), findsWidgets);
        // Apply seam succeeded (no throw) but the handle is consumed
        // on its way out — drop should NOT fire on the rolled-back
        // success-shape return.
        expect(log.applyCalls, hasLength(1));
        expect(log.dropCalls, isEmpty);
      },
    );

    _testFlow('opened preview with recordings drives applyRecordings=true', (
      tester,
    ) async {
      // Spec: when the staged preview reports a non-zero recording
      // count, `_applyLfsImport` passes `recordings: true` so the
      // Rust apply step extracts the recordings tree after the DB
      // transaction commits.
      final log = _CallLog();
      debugSetImportFlowSeams(
        _seams(
          log: log,
          openPreview: _previewWith(recordingCount: 4),
          lfsDialogResult: (password: 'p', mode: ImportMode.merge),
        ),
      );

      await tester.pumpWidget(
        _wrapApp(
          child: _triggerButton(
            'go',
            (ctx, ref) => showLfsImportDialog(ctx, ref, '/tmp/r.lfs'),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(log.applyCalls.single.applyRecordings, isTrue);
    });

    _testFlow('openArchiveWithTypedErrors maps DbImportOpenError_FutureVersion '
        'to UnsupportedLfsVersionException — error toast carries the version', (
      tester,
    ) async {
      // Spec: the wrapper in `openArchiveWithTypedErrors` rethrows
      // `DbImportOpenError_FutureVersion` as the typed
      // `UnsupportedLfsVersionException` so the `localizeError`
      // chain renders the dedicated "newer archive" template
      // instead of the generic Rust error string.
      final log = _CallLog();
      debugSetImportFlowSeams(
        _seams(
          log: log,
          openThrows: const UnsupportedLfsVersionException(
            found: 99,
            supported: 3,
          ),
          lfsDialogResult: (password: 'p', mode: ImportMode.merge),
        ),
      );

      await tester.pumpWidget(
        _wrapApp(
          child: _triggerButton(
            'go',
            (ctx, ref) => showLfsImportDialog(ctx, ref, '/tmp/x.lfs'),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      // The localized "newer than supported" template embeds the
      // archive's version number.
      expect(find.textContaining('99'), findsWidgets);
      // No handle was registered (open threw) so drop must NOT fire.
      expect(log.dropCalls, isEmpty);
    });

    _testFlow('replace mode propagates through apply seam', (tester) async {
      final log = _CallLog();
      debugSetImportFlowSeams(
        _seams(
          log: log,
          lfsDialogResult: (password: 'p', mode: ImportMode.replace),
        ),
      );

      await tester.pumpWidget(
        _wrapApp(
          child: _triggerButton(
            'go',
            (ctx, ref) => showLfsImportDialog(ctx, ref, '/tmp/x.lfs'),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pump();
      await tester.pump();

      expect(log.applyCalls.single.mode, ImportMode.replace);
    });
  });

  group('handleQrImportSource', () {
    _testFlow('success path: applyHandle called with toggles, success toast', (
      tester,
    ) async {
      final log = _CallLog();
      debugSetImportFlowSeams(
        _seams(log: log, applyResult: () => _applyResult(sessions: 2, tags: 5)),
      );

      final source = QrDecodedSource.rust(
        rust_archive.DbImportOpenResult(
          handleId: 'qr-h',
          preview: _previewWith(),
        ),
      );

      await tester.pumpWidget(
        _wrapApp(
          child: _triggerButton('go', (ctx, ref) async {
            await handleQrImportSource(
              context: ctx,
              ref: ref,
              source: source,
              choice: (
                mode: ImportMode.merge,
                options: const ExportOptions(
                  includeSessions: true,
                  includeTags: true,
                  includeSnippets: false,
                  includeManagerKeys: false,
                  includeKnownHosts: false,
                  includeConfig: false,
                ),
              ),
            );
          }),
        ),
      );

      await tester.tap(find.text('go'));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(log.applyCalls.single.handleId, 'qr-h');
      expect(log.applyCalls.single.applySessions, isTrue);
      expect(log.applyCalls.single.applyTags, isTrue);
      expect(log.applyCalls.single.applySnippets, isFalse);
      expect(log.applyCalls.single.applyKeys, isFalse);
      expect(log.applyCalls.single.applyKnownHosts, isFalse);
      expect(find.textContaining('2'), findsWidgets);
    });

    _testFlow('includeAllManagerKeys (default "Full" preset) sets applyKeys', (
      tester,
    ) async {
      final log = _CallLog();
      debugSetImportFlowSeams(
        _seams(log: log, applyResult: () => _applyResult(sessions: 1)),
      );

      final source = QrDecodedSource.rust(
        rust_archive.DbImportOpenResult(
          handleId: 'qr-h',
          preview: _previewWith(),
        ),
      );

      await tester.pumpWidget(
        _wrapApp(
          child: _triggerButton('go', (ctx, ref) async {
            await handleQrImportSource(
              context: ctx,
              ref: ref,
              source: source,
              // "Full import" preset: only includeAllManagerKeys is set,
              // includeManagerKeys stays false. Both must enable apply.
              choice: (
                mode: ImportMode.merge,
                options: const ExportOptions(
                  includeSessions: true,
                  includeAllManagerKeys: true,
                  includeManagerKeys: false,
                ),
              ),
            );
          }),
        ),
      );

      await tester.tap(find.text('go'));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(log.applyCalls.single.applyKeys, isTrue);
    });

    _testFlow('apply throws: error toast', (tester) async {
      final log = _CallLog();
      debugSetImportFlowSeams(
        _seams(log: log, applyThrows: const LfsDecryptionFailedException()),
      );

      final source = QrDecodedSource.rust(
        rust_archive.DbImportOpenResult(
          handleId: 'qr-h',
          preview: _previewWith(),
        ),
      );

      await tester.pumpWidget(
        _wrapApp(
          child: _triggerButton('go', (ctx, ref) async {
            await handleQrImportSource(
              context: ctx,
              ref: ref,
              source: source,
              choice: (
                mode: ImportMode.merge,
                options: const ExportOptions(includeSessions: true),
              ),
            );
          }),
        ),
      );

      await tester.tap(find.text('go'));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.textContaining('Import failed'), findsOneWidget);
    });

    _testFlow(
      'includeConfig=false: apply.configJson present but config NOT applied',
      (tester) async {
        final log = _CallLog();
        debugSetImportFlowSeams(
          _seams(
            log: log,
            applyResult: () =>
                _applyResult(configJson: '{"locale":"en","theme":"dark"}'),
          ),
        );

        final source = QrDecodedSource.rust(
          rust_archive.DbImportOpenResult(
            handleId: 'qr-h',
            preview: _previewWith(),
          ),
        );

        late ProviderContainer container;
        await tester.pumpWidget(
          _wrapApp(
            child: Consumer(
              builder: (ctx, ref, _) {
                container = ProviderScope.containerOf(ctx);
                return ElevatedButton(
                  onPressed: () => handleQrImportSource(
                    context: ctx,
                    ref: ref,
                    source: source,
                    choice: (
                      mode: ImportMode.merge,
                      options: const ExportOptions(
                        includeSessions: true,
                        includeConfig: false,
                      ),
                    ),
                  ),
                  child: const Text('go'),
                );
              },
            ),
          ),
        );

        // Snapshot starting config.
        final before = container.read(configProvider);
        await tester.tap(find.text('go'));
        await tester.pump();
        await tester.pump();
        // Config restore must NOT have run because includeConfig is false.
        // Identity equality is enough — TestConfigNotifier.build() returns
        // AppConfig.defaults verbatim, so a new instance would not match.
        expect(identical(container.read(configProvider), before), isTrue);
      },
    );
  });

  group('handleQrImport (deeplink entry)', () {
    _testFlow('null link-preview dialog short-circuits without apply', (
      tester,
    ) async {
      final log = _CallLog();
      debugSetImportFlowSeams(_seams(log: log, linkDialogResult: null));

      await tester.pumpWidget(
        _wrapApp(
          useGlobalNavigatorKey: true,
          child: _triggerButton(
            'go',
            (ctx, ref) => handleQrImport(
              ref,
              QrDecodedSource.rust(
                rust_archive.DbImportOpenResult(
                  handleId: 'h-qr',
                  preview: _previewWith(),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pump();
      await tester.pump();

      expect(log.linkDialogShown, 1);
      expect(log.applyCalls, isEmpty);
    });

    // The happy / apply-throws variants of handleQrImport call
    // Toast.show via the navigatorKey's current context, which then
    // resolves Overlay.of against a Navigator-rooted context. The
    // flutter_test MaterialApp does place a Navigator (and therefore
    // an Overlay) above the home tree, but the global navigatorKey's
    // currentContext sits at the NavigatorState level — Overlay.of
    // walks ancestors and the wrapper reports "no Overlay above this
    // context" because the Overlay descends from Navigator, not
    // ancestrally above it. End-to-end coverage of the toast leg
    // belongs in `integration_test/` where a full app shell wraps
    // the deeplink pump. The unit-level apply-handle / dialog-cancel
    // shape is exercised here (above) and through
    // `handleQrImportSource` (below), which call the same
    // `_applyRustQrSource` body.
  });

  group('config restore branch', () {
    late Directory tempDir;

    setUp(() async {
      // These flows flush a restored config. The save path no longer
      // re-inits the store per write, so route path_provider to a temp
      // dir and pin the store before the debounced save fires.
      tempDir = await Directory.systemTemp.createTemp('import_flow_test_');
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

    _testFlow(
      'handleQrImportSource with includeConfig=true updates config provider',
      (tester) async {
        final log = _CallLog();
        debugSetImportFlowSeams(
          _seams(
            log: log,
            applyResult: () => _applyResult(configJson: '{"locale":"ru"}'),
          ),
        );

        late ProviderContainer container;
        await tester.pumpWidget(
          _wrapApp(
            child: Consumer(
              builder: (ctx, ref, _) {
                container = ProviderScope.containerOf(ctx);
                return ElevatedButton(
                  onPressed: () => handleQrImportSource(
                    context: ctx,
                    ref: ref,
                    source: QrDecodedSource.rust(
                      rust_archive.DbImportOpenResult(
                        handleId: 'h',
                        preview: _previewWith(),
                      ),
                    ),
                    choice: (
                      mode: ImportMode.merge,
                      options: const ExportOptions(
                        includeSessions: true,
                        includeConfig: true,
                      ),
                    ),
                  ),
                  child: const Text('go'),
                );
              },
            ),
          ),
        );

        final before = container.read(configProvider);
        await tester.tap(find.text('go'));
        await tester.pump();
        await tester.pump();
        // ConfigNotifier.update debounces save 300 ms — advance past
        // it so the pending Timer is flushed before tearDown's
        // pending-timer invariant runs.
        await tester.pump(const Duration(milliseconds: 350));

        // Config restore ran — provider rebuilt with locale='ru'.
        final after = container.read(configProvider);
        expect(identical(after, before), isFalse);
        expect(after.locale, 'ru');
      },
    );

    _testFlow(
      'showLfsImportDialog with restored configJson updates config provider',
      (tester) async {
        final log = _CallLog();
        debugSetImportFlowSeams(
          _seams(
            log: log,
            applyResult: () => _applyResult(configJson: '{"locale":"de"}'),
            lfsDialogResult: (password: 'p', mode: ImportMode.merge),
          ),
        );

        late ProviderContainer container;
        await tester.pumpWidget(
          _wrapApp(
            child: Consumer(
              builder: (ctx, ref, _) {
                container = ProviderScope.containerOf(ctx);
                return ElevatedButton(
                  onPressed: () => showLfsImportDialog(ctx, ref, '/tmp/x.lfs'),
                  child: const Text('go'),
                );
              },
            ),
          ),
        );

        final before = container.read(configProvider);
        await tester.tap(find.text('go'));
        await tester.pump();
        await tester.pump();
        // ConfigNotifier.update debounces save 300 ms — advance past
        // it so the pending Timer is flushed before tearDown's
        // pending-timer invariant runs.
        await tester.pump(const Duration(milliseconds: 350));

        final after = container.read(configProvider);
        expect(identical(after, before), isFalse);
        expect(after.locale, 'de');
      },
    );
  });
}
