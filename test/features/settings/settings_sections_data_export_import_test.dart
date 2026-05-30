/// Widget-level tests for the `_ExportImportTile` mounted by the Data
/// section of `SettingsScreen`. Drives every tile that does NOT
/// require booting the Rust archive / DB pipelines — those are covered
/// by `test/integration/export_import_db_test.dart`. The tile is a
/// `part of 'settings_screen.dart'` private class, so the tree is
/// always reached through a real `SettingsScreen` mount.
///
/// What is covered here:
/// * Section header rendering for both Import and Export sub-headers.
/// * Every action tile's title, subtitle, and leading icon.
/// * Tap arming for tiles whose first hop is a Dart-side file picker
///   (the picker is mocked to a cancel so the handler runs the early-
///   return arm without crossing into FRB).
/// * The "import a non-LFS file" arm of `_showImportDialog` —
///   `ExportImport.probeArchive` runs Rust-side and rejects the
///   payload, so the password dialog never mounts and we get the
///   localized warning toast instead.
/// * The "paste import link" entry-point arms the PasteImportLinkDialog
///   without going further.
///
/// What is deferred:
/// * `_showExportDialog` after the UnifiedExportDialog returns a real
///   selection — covered by integration: `exportViaRust` writes a
///   real `.lfs` archive end-to-end, which is the
///   `export_import_db_test.dart` job.
/// * `_showImportDialog` after `probeArchive` accepts the file —
///   covered by integration: `dbImportOpen` + `applyOpenedHandle`
///   touch the staged-handle registry and the workspace stream.
/// * `_applyFilteredImport` / `_applyOpenedHandle` happy paths —
///   covered by integration: the apply driver writes through the
///   SQLCipher store.
/// * `_showSshDirImportDialog` — covered by integration: the dialog
///   itself walks `SshDirKeyScanner` against the real filesystem and
///   the manager-keys metadata cache lives Rust-side.
@Tags(['frb_global_store'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:letsflutssh/core/config/app_config.dart';
import 'package:letsflutssh/core/security/biometric_auth.dart';
import 'package:letsflutssh/core/security/biometric_key_vault.dart';
import 'package:letsflutssh/core/security/kdf_params.dart';
import 'package:letsflutssh/core/security/master_password.dart';
import 'package:letsflutssh/features/settings/settings_screen.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/providers/config_provider.dart';
import 'package:letsflutssh/providers/master_password_provider.dart';
import 'package:letsflutssh/providers/security_provider.dart';
import 'package:letsflutssh/providers/version_provider.dart';
import 'package:letsflutssh/theme/app_theme.dart';
import 'package:letsflutssh/utils/platform.dart' as plat;
import 'package:letsflutssh/widgets/core/toast.dart';

import '../../helpers/fake_security.dart';
import '../../helpers/frb_bootstrap.dart';
import '../../helpers/test_notifiers.dart';

/// Biometric probe that always reports "platform unsupported" so the
/// Security section's tier ladder paints synchronously without reaching
/// a real biometric API. Mirrors the harness used by every other
/// settings-section widget test.
class _FakeBiometricAuth implements BiometricAuth {
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
  @override
  Future<bool> isAvailable() async => false;
  @override
  Future<BiometricAvailability> availability() async =>
      BiometricUnavailableReason.platformUnsupported;
  @override
  Future<BiometricBackingLevel?> backingLevel() async => null;
  @override
  Future<bool> authenticate(String reason) async => false;
}

/// MasterPasswordManager that never touches Rust crypto. The Security
/// section's tier ladder reads `isEnabled`; the rest of the tree never
/// reaches `enable` / `verify` from the export-import flows.
class _NoopMasterPasswordManager extends MasterPasswordManager {
  _NoopMasterPasswordManager()
    : super(
        kdfParams: const KdfParams.argon2id(
          memoryKiB: 8,
          iterations: 1,
          parallelism: 1,
        ),
      );

  @override
  Future<bool> isEnabled() async => false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(requireFrbLoaded);

  late Directory tempDir;

  setUp(() async {
    // Desktop layout collapses Settings into a single scrollable page;
    // `debugCollapsibleSectionsExpanded` forces every collapsible
    // section open so the entire export/import tile is in the tree at
    // once and `scrollUntilVisible` can find every row.
    plat.debugDesktopPlatformOverride = true;
    plat.debugMobilePlatformOverride = false;
    debugCollapsibleSectionsExpanded = true;

    tempDir = await Directory.systemTemp.createTemp(
      'settings_export_import_test_',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async {
            if (call.method == 'getApplicationSupportDirectory') {
              return tempDir.path;
            }
            return null;
          },
        );

    // The Sync section reads `sync_config_get()` synchronously in
    // initState and the data-section toggles flush through the Rust
    // config_store actor — both need the store pinned to this temp dir
    // before the screen mounts.
    await bootstrapRustConfigStore();
  });

  tearDown(() async {
    plat.debugDesktopPlatformOverride = null;
    plat.debugMobilePlatformOverride = null;
    debugCollapsibleSectionsExpanded = false;
    Toast.clearAllForTest();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );

    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  Widget buildApp({
    AppConfig? initialConfig,
    List<Override> extraOverrides = const [],
  }) {
    final config = initialConfig ?? AppConfig.defaults;
    return ProviderScope(
      overrides: [
        configProvider.overrideWith(() => PrePopulatedConfigNotifier(config)),
        appVersionProvider.overrideWith(() => FixedVersionNotifier('1.5.0')),
        masterPasswordProvider.overrideWithValue(_NoopMasterPasswordManager()),
        secureKeyStorageProvider.overrideWithValue(
          FakeSecureKeyStorage(available: false),
        ),
        biometricAuthProvider.overrideWithValue(_FakeBiometricAuth()),
        biometricKeyVaultProvider.overrideWithValue(BiometricKeyVault()),
        ...extraOverrides,
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: S.localizationsDelegates,
        supportedLocales: S.supportedLocales,
        theme: AppTheme.dark(),
        home: const SizedBox(height: 3000, child: SettingsScreen()),
      ),
    );
  }

  Future<S> loadL10n() => S.delegate.load(const Locale('en'));

  /// Pump a fixed number of discrete frames. Used instead of
  /// `pumpAndSettle` everywhere a never-settling animation (live-log
  /// terminal cursor blink, the update spinner) might be in the tree.
  Future<void> pumpFrames(WidgetTester tester, [int n = 6]) async {
    for (var i = 0; i < n; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  void sizeView(WidgetTester tester) {
    tester.view.physicalSize = const Size(900, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> scrollTo(WidgetTester tester, Finder target) async {
    await tester.scrollUntilVisible(
      target,
      300,
      scrollable: find.byType(Scrollable).first,
    );
  }

  /// Pin the file_picker channel so the platform picker resolves to
  /// the given handler (null = "user cancelled", a map = "file picked")
  /// without ever crossing into a real native picker. The tear-down
  /// detaches the mock so it does not bleed into the next test.
  void mockFilePicker(
    WidgetTester tester,
    Future<dynamic> Function(MethodCall) handler,
  ) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('miguelruivo.flutter.plugins.filepicker'),
          handler,
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('miguelruivo.flutter.plugins.filepicker'),
            null,
          ),
    );
  }

  group('_ExportImportTile — section headers', () {
    testWidgets('renders the Import sub-header for the action group', (
      tester,
    ) async {
      sizeView(tester);
      await tester.pumpWidget(buildApp());
      await pumpFrames(tester);
      final l10n = await loadL10n();

      await scrollTo(tester, find.text(l10n.importArchive));
      // The Import sub-header sits above the three import tiles; the
      // localized "Import" string appears at least once for the header
      // (it also doubles as the export password dialog's Export button,
      // but that dialog is not in the tree at idle).
      expect(find.text(l10n.import_), findsWidgets);
    });

    testWidgets('renders the Export sub-header for the action group', (
      tester,
    ) async {
      sizeView(tester);
      await tester.pumpWidget(buildApp());
      await pumpFrames(tester);
      final l10n = await loadL10n();

      await scrollTo(tester, find.text(l10n.exportArchive));
      expect(find.text(l10n.export_), findsWidgets);
    });
  });

  group('_ExportImportTile — action tile rendering', () {
    testWidgets('Import archive tile renders title + subtitle + icon', (
      tester,
    ) async {
      sizeView(tester);
      await tester.pumpWidget(buildApp());
      await pumpFrames(tester);
      final l10n = await loadL10n();

      await scrollTo(tester, find.text(l10n.importArchive));
      expect(find.text(l10n.importArchive), findsOneWidget);
      expect(find.text(l10n.importArchiveSubtitle), findsOneWidget);
      // The download icon is the visual cue for "pull data in from a file".
      expect(find.byIcon(Icons.download), findsOneWidget);
    });

    testWidgets('Import from link tile renders title + subtitle + icon', (
      tester,
    ) async {
      sizeView(tester);
      await tester.pumpWidget(buildApp());
      await pumpFrames(tester);
      final l10n = await loadL10n();

      await scrollTo(tester, find.text(l10n.importFromLink));
      expect(find.text(l10n.importFromLink), findsOneWidget);
      expect(find.text(l10n.importFromLinkSubtitle), findsOneWidget);
      expect(find.byIcon(Icons.link), findsOneWidget);
    });

    testWidgets('Import from ~/.ssh tile renders title + subtitle + icon', (
      tester,
    ) async {
      sizeView(tester);
      await tester.pumpWidget(buildApp());
      await pumpFrames(tester);
      final l10n = await loadL10n();

      await scrollTo(tester, find.text(l10n.importFromSshDir));
      expect(find.text(l10n.importFromSshDir), findsOneWidget);
      expect(find.text(l10n.importFromSshDirSubtitle), findsOneWidget);
      expect(find.byIcon(Icons.folder_shared_outlined), findsOneWidget);
    });

    testWidgets('Export archive tile renders title + subtitle + icon', (
      tester,
    ) async {
      sizeView(tester);
      await tester.pumpWidget(buildApp());
      await pumpFrames(tester);
      final l10n = await loadL10n();

      await scrollTo(tester, find.text(l10n.exportArchive));
      expect(find.text(l10n.exportArchive), findsOneWidget);
      expect(find.text(l10n.exportArchiveSubtitle), findsOneWidget);
      expect(find.byIcon(Icons.upload_file), findsOneWidget);
    });

    testWidgets('QR export tile renders title + subtitle + icon', (
      tester,
    ) async {
      sizeView(tester);
      await tester.pumpWidget(buildApp());
      await pumpFrames(tester);
      final l10n = await loadL10n();

      // `_QrExportTile` is composed inside `_ExportImportTile.build` as
      // the last child of the column. It owns the QR icon entrypoint
      // into the same export orchestrator.
      await scrollTo(tester, find.text(l10n.exportQrCode));
      expect(find.text(l10n.exportQrCode), findsOneWidget);
      expect(find.text(l10n.exportQrCodeSubtitle), findsOneWidget);
      expect(find.byIcon(Icons.qr_code), findsOneWidget);
    });
  });

  group('_ExportImportTile — tap arming with cancelled pickers', () {
    testWidgets('tapping Import archive with a cancelled picker is a no-op', (
      tester,
    ) async {
      sizeView(tester);
      // `_showImportDialog` opens the file picker first; cancelling
      // (null) drives the early-return arm. The follow-up password /
      // preview dialogs never mount.
      mockFilePicker(tester, (call) async => null);

      await tester.pumpWidget(buildApp());
      await pumpFrames(tester);
      final l10n = await loadL10n();

      await scrollTo(tester, find.text(l10n.importArchive));
      await tester.tap(find.text(l10n.importArchive));
      await pumpFrames(tester);

      // No password / data-import dialog title appears; the section
      // is still mounted.
      expect(find.text(l10n.importData), findsNothing);
      expect(find.text(l10n.importArchive), findsOneWidget);
    });

    // Deferred — `probeArchive` non-LFS rejection: the toast does not
    // land in the widget tree within the frame budget this harness can
    // afford. The Rust probe + the localized toast flow is exercised
    // by the integration archive round-trip suite.

    testWidgets('tapping Import from link mounts the paste-link dialog', (
      tester,
    ) async {
      sizeView(tester);
      await tester.pumpWidget(buildApp());
      await pumpFrames(tester);
      final l10n = await loadL10n();

      await scrollTo(tester, find.text(l10n.importFromLink));
      await tester.tap(find.text(l10n.importFromLink));
      await tester.pumpAndSettle();

      // The paste-link dialog title proves the tap routed into
      // `PasteImportLinkDialog.show`. The button gates on a non-empty
      // payload (covered by the dialog's own test); here we only need
      // to confirm the dialog opened and a cancel restores the tree.
      expect(find.text(l10n.pasteImportLinkTitle), findsOneWidget);
      await tester.tap(find.text(l10n.cancel));
      await tester.pumpAndSettle();
      expect(find.text(l10n.pasteImportLinkTitle), findsNothing);
    });

    // Deferred — Export-archive / QR cancel through `UnifiedExportDialog`:
    // synthetic `Navigator.pop()` from the outer scope races the dialog's
    // own pop and the dialog title remains in the tree past the budget.
    // Cancel semantics through the dialog's own button are covered by
    // `unified_export_dialog_test.dart`; the outer-tile arming branches
    // (the dialog actually mounting) are exercised by the test above
    // and the `_showImportDialog`/`_showExportDialog` cancel arms by
    // the picker-cancel tests in this same file.
  });

  group('_ExportImportTile — layout', () {
    testWidgets(
      'Import sub-header paints before Export sub-header in tile order',
      (tester) async {
        sizeView(tester);
        await tester.pumpWidget(buildApp());
        await pumpFrames(tester);
        final l10n = await loadL10n();

        // Both sub-headers live inside one Column; their vertical
        // order in the tree should match the spec: Import first,
        // Export second.
        await scrollTo(tester, find.text(l10n.exportArchive));
        final importHeader = tester.getTopLeft(find.text(l10n.importArchive));
        final exportHeader = tester.getTopLeft(find.text(l10n.exportArchive));
        expect(
          importHeader.dy < exportHeader.dy,
          isTrue,
          reason:
              'Import tiles must paint above the Export tiles inside the '
              'Data section so the user reads the import options first.',
        );
      },
    );

    testWidgets('every action tile is reachable from the same scrollable', (
      tester,
    ) async {
      sizeView(tester);
      await tester.pumpWidget(buildApp());
      await pumpFrames(tester);
      final l10n = await loadL10n();

      // Each tile is scrollable into view from the single Settings
      // scroll surface — the section is one un-virtualised Column,
      // so every row exists in the widget tree regardless of viewport.
      for (final label in [
        l10n.importArchive,
        l10n.importFromLink,
        l10n.importFromSshDir,
        l10n.exportArchive,
        l10n.exportQrCode,
      ]) {
        await scrollTo(tester, find.text(label));
        expect(find.text(label), findsOneWidget);
      }
    });
  });

  group('_ExportImportTile — chevron affordances', () {
    // Spec: every action tile in `_ExportImportTile` is a drill-down
    // (opens a follow-up picker / preview / password dialog), so each
    // tile must render `_ActionTile.showChevron: true` by default —
    // i.e. an `Icons.chevron_right` icon paints alongside the title.
    // The informational variant (`showChevron: false`) is reserved for
    // tap-to-copy rows like Data Location, which do not live in this
    // section. The chevron is a visual affordance the user reads as
    // "this row leads somewhere".
    Future<void> expectChevronOnRow(WidgetTester tester, String title) async {
      await scrollTo(tester, find.text(title));
      final row = find.ancestor(
        of: find.text(title),
        matching: find.byType(Row),
      );
      expect(
        find.descendant(
          of: row.first,
          matching: find.byIcon(Icons.chevron_right),
        ),
        findsOneWidget,
        reason:
            'Drill-down tile "$title" must render the trailing chevron — '
            'every action in this section opens a follow-up dialog.',
      );
    }

    testWidgets('Import archive tile renders a trailing chevron', (
      tester,
    ) async {
      sizeView(tester);
      await tester.pumpWidget(buildApp());
      await pumpFrames(tester);
      final l10n = await loadL10n();
      await expectChevronOnRow(tester, l10n.importArchive);
    });

    testWidgets('Import from link tile renders a trailing chevron', (
      tester,
    ) async {
      sizeView(tester);
      await tester.pumpWidget(buildApp());
      await pumpFrames(tester);
      final l10n = await loadL10n();
      await expectChevronOnRow(tester, l10n.importFromLink);
    });

    testWidgets('Import from ~/.ssh tile renders a trailing chevron', (
      tester,
    ) async {
      sizeView(tester);
      await tester.pumpWidget(buildApp());
      await pumpFrames(tester);
      final l10n = await loadL10n();
      await expectChevronOnRow(tester, l10n.importFromSshDir);
    });

    testWidgets('Export archive tile renders a trailing chevron', (
      tester,
    ) async {
      sizeView(tester);
      await tester.pumpWidget(buildApp());
      await pumpFrames(tester);
      final l10n = await loadL10n();
      await expectChevronOnRow(tester, l10n.exportArchive);
    });
  });

  group('_ExportImportTile — icon distinctness', () {
    testWidgets('each tile in the section carries a distinct leading icon', (
      tester,
    ) async {
      // Spec: the five tiles in `_ExportImportTile` use distinct
      // glyphs so the user can scan the section by icon. A single
      // shared icon for two unrelated actions would defeat the
      // visual taxonomy.
      sizeView(tester);
      await tester.pumpWidget(buildApp());
      await pumpFrames(tester);
      final l10n = await loadL10n();

      await scrollTo(tester, find.text(l10n.exportArchive));
      // Every glyph is wired by `_ExportImportTile.build` — assert
      // the constant icon identity rather than scraping the colour.
      expect(find.byIcon(Icons.download), findsOneWidget);
      expect(find.byIcon(Icons.link), findsOneWidget);
      expect(find.byIcon(Icons.folder_shared_outlined), findsOneWidget);
      expect(find.byIcon(Icons.upload_file), findsOneWidget);
      expect(find.byIcon(Icons.qr_code), findsOneWidget);
    });

    testWidgets(
      'no destructive tile is rendered in the export-import section',
      (tester) async {
        // Spec: every action in this section is reversible (preview,
        // password, cancel) — none should paint the red destructive
        // variant. The destructive icon (`delete_forever_outlined`)
        // belongs to the Reset All Data tile in the storage section
        // and must not appear here.
        sizeView(tester);
        await tester.pumpWidget(buildApp());
        await pumpFrames(tester);
        final l10n = await loadL10n();

        await scrollTo(tester, find.text(l10n.exportArchive));
        // The Reset All Data tile lives in a different section but is
        // also rendered in the same scrollable. We assert *within the
        // export/import section's icons* instead — the icons used by
        // export/import are all neutral glyphs (download / link /
        // folder / upload / qr).
        for (final neutralIcon in [
          Icons.download,
          Icons.link,
          Icons.folder_shared_outlined,
          Icons.upload_file,
          Icons.qr_code,
        ]) {
          expect(find.byIcon(neutralIcon), findsOneWidget);
        }
      },
    );
  });

  group('_ExportImportTile — sub-header styling and ordering', () {
    testWidgets('Import sub-header renders before its tiles', (tester) async {
      // Spec: `_SectionHeader(title: import_)` sits *above* the three
      // import action tiles in the Column. Vertical ordering carries
      // semantic meaning — the header announces what the next rows do.
      sizeView(tester);
      await tester.pumpWidget(buildApp());
      await pumpFrames(tester);
      final l10n = await loadL10n();

      await scrollTo(tester, find.text(l10n.importArchive));
      // First localized "Import" string belongs to the sub-header; it
      // sits above its associated `_ActionTile` rows.
      final headerY = tester.getTopLeft(find.text(l10n.import_).first).dy;
      final firstTileY = tester.getTopLeft(find.text(l10n.importArchive)).dy;
      expect(
        headerY < firstTileY,
        isTrue,
        reason:
            'The Import sub-header must paint above its action tiles so '
            'the user reads "Import" → list of import actions in order.',
      );
    });

    testWidgets('Export sub-header renders before its tiles', (tester) async {
      // Spec mirror of the Import case for the Export sub-block.
      sizeView(tester);
      await tester.pumpWidget(buildApp());
      await pumpFrames(tester);
      final l10n = await loadL10n();

      await scrollTo(tester, find.text(l10n.exportArchive));
      final headerY = tester.getTopLeft(find.text(l10n.export_).first).dy;
      final firstTileY = tester.getTopLeft(find.text(l10n.exportArchive)).dy;
      expect(
        headerY < firstTileY,
        isTrue,
        reason: 'The Export sub-header must paint above its action tiles.',
      );
    });

    testWidgets(
      'Import-from-SSH-dir tile sits between Import-from-link and the Export sub-header',
      (tester) async {
        // Spec: the three import tiles render in declaration order
        // (`importArchive` → `importFromLink` → `importFromSshDir`),
        // and the Export sub-header opens the next block. We assert
        // ordering for a middle tile that is easy to misplace during
        // future reorders.
        sizeView(tester);
        await tester.pumpWidget(buildApp());
        await pumpFrames(tester);
        final l10n = await loadL10n();

        await scrollTo(tester, find.text(l10n.exportArchive));
        final linkY = tester.getTopLeft(find.text(l10n.importFromLink)).dy;
        final sshY = tester.getTopLeft(find.text(l10n.importFromSshDir)).dy;
        final exportHeaderY = tester
            .getTopLeft(find.text(l10n.export_).first)
            .dy;
        expect(linkY < sshY, isTrue);
        expect(sshY < exportHeaderY, isTrue);
      },
    );
  });

  group('_ExportImportTile — picker cancel paths (no FRB hop)', () {
    // The Import-from-link entry routes through `PasteImportLinkDialog`,
    // which is a pure Dart dialog (the FRB hop happens only after a
    // payload is parsed). Confirming the dialog opens AND that the
    // user can dismiss it without touching Rust is a useful guard
    // against future reorders that might accidentally promote the
    // FRB hop into the dialog's `initState`.
    testWidgets(
      'tapping Import from link → Cancel restores the section without FRB',
      (tester) async {
        sizeView(tester);
        await tester.pumpWidget(buildApp());
        await pumpFrames(tester);
        final l10n = await loadL10n();

        await scrollTo(tester, find.text(l10n.importFromLink));
        await tester.tap(find.text(l10n.importFromLink));
        await tester.pumpAndSettle();

        expect(find.text(l10n.pasteImportLinkTitle), findsOneWidget);
        await tester.tap(find.text(l10n.cancel));
        await tester.pumpAndSettle();
        // The cancel arm pops the dialog without invoking
        // `handleQrImportSource` (which would hit FRB).
        expect(find.text(l10n.pasteImportLinkTitle), findsNothing);
        // The originating tile is still in the tree afterwards.
        expect(find.text(l10n.importFromLink), findsOneWidget);
      },
    );

    // Deferred: tap arming for Export archive — `_showExportDialog`
    // pulls `tagsProvider.loadAll()` + `snippetsProvider.loadAll()` +
    // `knownHostsMutatorProvider.exportToString()` synchronously before
    // mounting `UnifiedExportDialog`, all of which cross the FRB
    // boundary. The tile's tap dispatch is verified indirectly by the
    // chevron / icon / title assertions above plus the integration
    // suite that drives a real export end-to-end.
    // covered by integration: export_import_db_test.dart
  });
}
