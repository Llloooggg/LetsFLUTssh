import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:file_picker/src/platform/file_picker_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/config/app_config.dart';
import 'package:letsflutssh/core/logs/log_store.dart';
import 'package:letsflutssh/core/security/master_password.dart';
import 'package:letsflutssh/core/logs/settings_logging_parser.dart';
import 'package:letsflutssh/features/settings/settings_screen.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/providers/config_provider.dart';
import 'package:letsflutssh/core/security/biometric_auth.dart';
import 'package:letsflutssh/core/security/biometric_key_vault.dart';
import 'package:letsflutssh/providers/master_password_provider.dart';
import 'package:letsflutssh/providers/security_provider.dart';
import 'package:letsflutssh/providers/version_provider.dart';
import 'package:letsflutssh/theme/app_theme.dart';
import 'package:letsflutssh/utils/logger.dart';
import 'package:letsflutssh/utils/platform.dart' as plat;
import 'package:letsflutssh/widgets/core/toast.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import '../../helpers/fake_security.dart';
import '../../helpers/frb_bootstrap.dart';
import '../../helpers/test_notifiers.dart';

/// _SecuritySection.build() reads secureKeyStorageProvider,
/// biometricAuthProvider and biometricKeyVaultProvider during its
/// initState probe. The real implementations route through FRB
/// (lfs_os_security::secure_key_storage / biometric_auth /
/// hardware_tier_vault) which is bootstrapped in setUpAll, but the
/// fake overrides below short-circuit each probe to a deterministic
/// "not available" so the section settles immediately and the
/// disposing-the-viewer tests don't race a long-running probe.
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

class _MockMasterPasswordManager extends MasterPasswordManager {
  bool _enabled = false;

  _MockMasterPasswordManager();

  @override
  Future<Uint8List> enable(Uint8List password) async {
    _enabled = true;
    return Uint8List.fromList(List.generate(32, (i) => i));
  }

  @override
  Future<bool> isEnabled() async => _enabled;

  @override
  Future<bool> verify(Uint8List password) async => true;
}

/// Stub FilePicker — the logging section wires up FilePicker.saveFile /
/// getDirectoryPath for the export path. Default behaviour returns
/// `null` for both (cancel); per-test overrides flip [saveFileResult] /
/// [directoryResult] to drive the success arms of `_exportLog`.
class _StubFilePickerPlatform extends FilePickerPlatform
    with MockPlatformInterfaceMixin {
  /// What [saveFile] should return on the next call. `null` simulates a
  /// user-cancelled picker; a non-null path drives the success arm
  /// where `loggerExportTo` actually writes to that target.
  String? saveFileResult;

  /// What [getDirectoryPath] should return on the next call. `null`
  /// = cancel; a directory path drives the mobile success arm which
  /// joins the generated `letsflutssh_log_<ts>.txt` filename onto it.
  String? directoryResult;

  /// Recorded inputs from the most recent [saveFile] / [getDirectoryPath]
  /// call so tests can assert the dialog title + filename composition
  /// inside `_exportLog`.
  String? lastSaveFileName;
  String? lastSaveDialogTitle;
  String? lastDirectoryDialogTitle;

  @override
  Future<String?> getDirectoryPath({
    String? dialogTitle,
    bool lockParentWindow = false,
    String? initialDirectory,
  }) async {
    lastDirectoryDialogTitle = dialogTitle;
    return directoryResult;
  }

  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async {
    lastSaveFileName = fileName;
    lastSaveDialogTitle = dialogTitle;
    return saveFileResult;
  }

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
    bool cancelUploadOnWindowBlur = true,
  }) async => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // SettingsScreen renders security widgets that call `evaluate()`,
  // which routes through `lfs_core::threat_vocabulary` — bootstrap
  // FRB so the screen can build.
  setUpAll(requireFrbLoaded);

  late Directory tempDir;
  late _StubFilePickerPlatform filePickerStub;

  setUp(() async {
    // Mobile layout + expanded sections so the logging section is reachable
    // without the desktop two-pane layout getting in the way.
    plat.debugMobilePlatformOverride = true;
    plat.debugDesktopPlatformOverride = false;
    debugCollapsibleSectionsExpanded = true;

    tempDir = await Directory.systemTemp.createTemp('settings_logging_test_');
    filePickerStub = _StubFilePickerPlatform();
    FilePickerPlatform.instance = filePickerStub;

    // Route path_provider to the temp dir so AppLogger.init() creates the log
    // file in a controlled location.
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

    await AppLogger.instance.init();
    await AppLogger.instance.setThreshold(LogLevel.info);
  });

  tearDown(() async {
    await AppLogger.instance.setThreshold(null);
    await AppLogger.instance.dispose();

    plat.debugMobilePlatformOverride = null;
    plat.debugDesktopPlatformOverride = null;
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

  Widget buildApp({AppConfig? initialConfig}) {
    final config = initialConfig ?? AppConfig.defaults;
    return ProviderScope(
      overrides: [
        configProvider.overrideWith(() => PrePopulatedConfigNotifier(config)),
        appVersionProvider.overrideWith(() => FixedVersionNotifier('1.5.0')),
        masterPasswordProvider.overrideWithValue(_MockMasterPasswordManager()),
        // _SecuritySection probes these on initState — let them resolve
        // instantly to "not available" instead of running the real
        // FRB round-trip / biometric prompt.
        secureKeyStorageProvider.overrideWithValue(
          FakeSecureKeyStorage(available: false),
        ),
        biometricAuthProvider.overrideWithValue(_FakeBiometricAuth()),
        biometricKeyVaultProvider.overrideWithValue(BiometricKeyVault()),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: S.localizationsDelegates,
        supportedLocales: S.supportedLocales,
        theme: AppTheme.dark(),
        home: const SizedBox(height: 2400, child: SettingsScreen()),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // _LoggingSection
  // ---------------------------------------------------------------------------
  group('_LoggingSection', () {
    testWidgets('logging toggle is present whether enabled or not', (
      tester,
    ) async {
      // The visibility contract for the live log viewer is exercised below
      // by `logging enabled with logPath set renders live log viewer` —
      // here we just sanity-check the toggle row itself is mounted.
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildApp());
      // New UI — level selector replaced the Enable Logging toggle.
      await tester.scrollUntilVisible(
        find.text('Logging level'),
        200,
        scrollable: find.byType(Scrollable).first,
      );

      expect(find.text('Logging level'), findsOneWidget);
      // Dropdown collapses to the current value's label — fresh
      // config defaults to null threshold → "Off" option rendered.
      expect(find.text('Off'), findsOneWidget);
    });

    testWidgets('logging enabled with logPath set renders live log viewer', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Sanity check: AppLogger.init() should have populated logPath.
      expect(AppLogger.instance.logPath, isNotNull);

      final config = AppConfig.defaults.copyWith(
        behavior: const BehaviorConfig(logLevel: LogLevel.info),
      );
      await tester.pumpWidget(buildApp(initialConfig: config));
      await tester.scrollUntilVisible(
        find.text('Live Log'),
        200,
        scrollable: find.byType(Scrollable).first,
      );

      // New UI — level selector replaced the Enable Logging toggle.
      expect(find.text('Logging level'), findsOneWidget);
      expect(find.text('Live Log'), findsOneWidget);
      // Toolbar icons from _LiveLogViewer.build.
      expect(find.byIcon(Icons.copy), findsOneWidget);
      expect(find.byIcon(Icons.save_alt), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    });

    testWidgets('clear button is visible and tappable', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final config = AppConfig.defaults.copyWith(
        behavior: const BehaviorConfig(logLevel: LogLevel.info),
      );
      await tester.pumpWidget(buildApp(initialConfig: config));
      for (int i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      // Find the Live Log section first
      expect(find.text('Live Log'), findsOneWidget);

      // Scroll to make the log viewer visible
      await tester.scrollUntilVisible(
        find.text('Live Log'),
        200,
        scrollable: find.byType(Scrollable).first,
      );

      // Find the delete icon - should be visible in the log viewer toolbar
      final deleteIcon = find.byIcon(Icons.delete_outline);
      expect(deleteIcon, findsOneWidget);

      // Verify we can tap it without error
      await tester.tap(deleteIcon);
      // The success toast holds a 3-second auto-dismiss timer; pump
      // past it so no pending timer survives the widget teardown.
      await tester.pump(const Duration(seconds: 4));
    });
  });

  // ---------------------------------------------------------------------------
  // _LiveLogViewer — reachable only through _LoggingSection
  // ---------------------------------------------------------------------------
  group('_LiveLogViewer', () {
    testWidgets('copy button writes log content to system clipboard', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      String? copiedText;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            final args = call.arguments as Map<dynamic, dynamic>;
            copiedText = args['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        );
      });

      AppLogger.instance.log('clipboard entry', name: 'Test');
      await tester.runAsync(
        () => Future.delayed(const Duration(milliseconds: 100)),
      );

      final config = AppConfig.defaults.copyWith(
        behavior: const BehaviorConfig(logLevel: LogLevel.info),
      );
      await tester.pumpWidget(buildApp(initialConfig: config));
      await tester.scrollUntilVisible(
        find.byIcon(Icons.copy),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.runAsync(
        () => Future.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump();

      await tester.tap(find.byIcon(Icons.copy));
      await tester.pump();

      // Clipboard.setData must have been invoked.
      expect(copiedText, isNotNull);

      // Drain the toast timer.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });
  });

  group('parseLogEntries', () {
    // The parser drives the viewer's per-row tint + segment colouring.
    // Regex mismatches silently demote a row to "header dim" which
    // buries the warning / error visual cue users rely on when
    // scanning a log — covering the happy path + each branch here
    // guards the level → tint mapping against future format drift.

    test('empty input yields empty list', () {
      expect(parseLogEntries(''), isEmpty);
      expect(parseLogEntries('\n\n'), isEmpty);
    });

    test('parses info / warn / error primary lines with tag + timestamp', () {
      final entries = parseLogEntries(
        [
          '12:34:56 I [App] routine entry',
          '12:34:57 W [KeyStore] fell back to plaintext',
          '12:34:58 E [MigrationRunner] fatal: bad chain',
        ].join('\n'),
      );
      expect(entries, hasLength(3));
      expect(entries[0].level, LogLevel.info);
      expect(entries[0].timestamp, '12:34:56');
      expect(entries[0].tag, 'App');
      expect(entries[0].message, 'routine entry');
      expect(entries[0].isHeader, isFalse);
      expect(entries[1].level, LogLevel.warn);
      expect(entries[1].tag, 'KeyStore');
      expect(entries[2].level, LogLevel.error);
      expect(entries[2].tag, 'MigrationRunner');
    });

    test('header lines become dim entries', () {
      final entries = parseLogEntries(
        [
          '--- Log started 2026-04-24T00:00:00Z ---',
          'Platform: linux "Linux 6.6"',
          'Dart: 3.4.0',
          '12:34:56 I [App] first real line',
        ].join('\n'),
      );
      expect(entries.take(3).every((e) => e.isHeader), isTrue);
      expect(entries[0].message, startsWith('--- Log started'));
      expect(entries[3].level, LogLevel.info);
    });

    test('indented continuations fold into the previous entry', () {
      final entries = parseLogEntries(
        [
          '12:34:56 E [SFTP] connection dropped',
          '  Error: SshException: server closed channel',
          '  Stack trace:',
          '  #0      SSHClient.<...>',
          '12:34:57 I [App] reconnecting',
        ].join('\n'),
      );
      expect(entries, hasLength(2));
      expect(entries[0].level, LogLevel.error);
      expect(entries[0].continuations, hasLength(3));
      expect(entries[0].continuations.first, startsWith('  Error:'));
      expect(entries[1].message, 'reconnecting');
    });

    test('unparseable lines become dim header entries without losing text', () {
      // Old-format lines (pre-LogLevel) or a truncated entry mid-write
      // fall here. The line must still render — buried data silently
      // is worse than a visibly-uncoloured row.
      final entries = parseLogEntries('12:34:56 [App] legacy format');
      expect(entries, hasLength(1));
      expect(entries[0].isHeader, isTrue);
      expect(entries[0].message, '12:34:56 [App] legacy format');
    });

    test('tags with special chars are preserved verbatim', () {
      final entries = parseLogEntries(
        '12:34:56 I [SecurityInitController] re-open on unlock',
      );
      expect(entries.single.tag, 'SecurityInitController');
      expect(entries.single.message, 're-open on unlock');
    });
  });

  // _exportLog FilePicker round-trip tests deferred: loggerExportTo
  // runs in a Rust spawn_blocking task that does not settle
  // deterministically within the test pump cadence. The contract is
  // covered Rust-side.

  // ---------------------------------------------------------------------------
  // _LogFilterBar — drives the search field + level chips inside the live
  // viewer. The bar is reachable only with logging enabled (the viewer host
  // mounts behind the threshold + file-content guard).
  // ---------------------------------------------------------------------------
  group('_LogFilterBar', () {
    /// Resize the viewport so the live-log viewer is in the tree and
    /// settle the LogStore seed + initial paint with discrete pumps
    /// (the terminal cursor blink prevents `pumpAndSettle`).
    Future<void> mountWithViewer(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final config = AppConfig.defaults.copyWith(
        behavior: const BehaviorConfig(logLevel: LogLevel.info),
      );
      await tester.pumpWidget(buildApp(initialConfig: config));
      for (int i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.scrollUntilVisible(
        find.text('Live Log'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
    }

    // 'typing into the filter field' test deferred: the LogStore mutation
    // path runs through a debounced applyFilter that needs the live
    // viewer's stream subscription to flush; the test harness's pump
    // cadence doesn't observe the post-debounce state synchronously.
    // The store contract is covered by log_store_test.dart directly.

    testWidgets('tapping a level chip removes its level from visibleLevels', (
      tester,
    ) async {
      await mountWithViewer(tester);

      // Three level chips are mounted (I/W/E) with all levels active
      // by default. Tapping the I chip drops Info from the store's
      // visibleLevels. The chips are siblings of the filter TextField
      // inside `_LogFilterBar`; the I chip is the first chip.
      final infoChip = find.text('I');
      expect(infoChip, findsWidgets);
      await tester.tap(infoChip.first);
      for (int i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      // Spec: the store reflects the user-toggled level set.
      expect(LogStore.instance.visibleLevels.contains(LogLevel.info), isFalse);
      expect(LogStore.instance.visibleLevels.contains(LogLevel.warn), isTrue);
      expect(LogStore.instance.visibleLevels.contains(LogLevel.error), isTrue);

      // Tapping again re-adds it — the toggle is symmetric.
      await tester.tap(infoChip.first);
      for (int i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(LogStore.instance.visibleLevels.contains(LogLevel.info), isTrue);
      Toast.clearAllForTest();
    });
  });

  // ---------------------------------------------------------------------------
  // _LogViewerHost — the host decides whether to mount the viewer based on
  // (threshold set OR file has content). The "logging off + file empty"
  // branch already lives in settings_sections_coverage_test; this group
  // covers the "logging off + file has content" branch (archived label).
  // ---------------------------------------------------------------------------
  // 'mounts as Archived log when logging off but file non-empty' test
  // deferred: the AppLogger threshold flip + the `loggerLogFileHasContent`
  // sync probe race the test's pump cadence — the host re-evaluates on
  // a Stream tick the harness doesn't drain. Covering the archived-log
  // arm requires a stream-flush probe seam.
}
