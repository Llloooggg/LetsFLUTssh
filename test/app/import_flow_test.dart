import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:meta/meta.dart' show isTest;
import 'package:letsflutssh/app/import_flow.dart';
import 'package:letsflutssh/core/session/qr_codec.dart';
import 'package:letsflutssh/core/session/qr_decoded_source.dart';
import 'package:letsflutssh/features/settings/export_import.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/providers/config_provider.dart';
import 'package:letsflutssh/src/rust/api/archive.dart' as rust_archive;
import 'package:letsflutssh/widgets/lfs_import_dialog.dart';
import 'package:letsflutssh/widgets/link_import_preview_dialog.dart';
import 'package:letsflutssh/widgets/toast.dart';

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
      bool refreshProvided,
    })
  >
  applyCalls = [];
  final List<String> dropCalls = [];
  final List<String> probeCalls = [];
  int lfsDialogShown = 0;
  int linkDialogShown = 0;
}

rust_archive.DbImportPreview _previewWith({bool hasKnownHosts = false}) =>
    rust_archive.DbImportPreview(
      schemaVersion: 1,
      sessionCount: 1,
      sessionLabels: const ['demo'],
      managerKeyCount: 0,
      tagCount: 0,
      snippetCount: 0,
      emptyFolderCount: 0,
      hasConfig: false,
      hasKnownHosts: hasKnownHosts,
    );

rust_archive.DbApplyResult _applyResult({
  int sessions = 1,
  int keys = 0,
  int tags = 0,
  int snippets = 0,
  int knownHosts = 0,
  String? configJson,
}) => rust_archive.DbApplyResult(
  sessionsApplied: sessions,
  keysApplied: keys,
  keysSkippedDedup: 0,
  tagsApplied: tags,
  snippetsApplied: snippets,
  knownHostsApplied: knownHosts,
  foldersApplied: 0,
  sessionTagsApplied: 0,
  sessionSnippetsApplied: 0,
  errors: const [],
  configJson: configJson,
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
    probeArchive: (path) {
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
          required applySessions,
          required applyKeys,
          required applyTags,
          required applySnippets,
          required applyKnownHosts,
          refreshAfterImport,
        }) async {
          log.applyCalls.add((
            handleId: handleId,
            mode: mode,
            applySessions: applySessions,
            applyKeys: applyKeys,
            applyTags: applyTags,
            applySnippets: applySnippets,
            applyKnownHosts: applyKnownHosts,
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

Widget _wrapApp({required Widget child, List<Override> overrides = const []}) {
  return ProviderScope(
    overrides: [
      configProvider.overrideWith(TestConfigNotifier.new),
      ...overrides,
    ],
    child: MaterialApp(
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

  // handleQrImport (deeplink entry) is exercised end-to-end in
  // integration_test/. The unit-level coverage of the same body
  // (`_applyRustQrSource`) is provided by the handleQrImportSource
  // group above — the only delta is the pre-step
  // `LinkImportPreviewDialog.show` + `addPostFrameCallback`-routed
  // toast through `navigatorKey.currentContext`, both of which need
  // a navigator-routed Overlay that flutter_test's MaterialApp does
  // not place above the global navigator key.
}
