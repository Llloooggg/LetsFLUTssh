import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:file_picker/src/platform/file_picker_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/config/app_config.dart';
import 'package:letsflutssh/core/security/master_password.dart';
import 'package:letsflutssh/features/settings/settings_screen.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/providers/config_provider.dart';
import 'package:letsflutssh/core/security/biometric_auth.dart';
import 'package:letsflutssh/core/security/biometric_key_vault.dart';
import 'package:letsflutssh/core/security/secure_key_storage.dart';
import 'package:letsflutssh/providers/master_password_provider.dart';
import 'package:letsflutssh/providers/security_provider.dart';
import 'package:letsflutssh/providers/version_provider.dart';
import 'package:letsflutssh/theme/app_theme.dart';
import 'package:letsflutssh/utils/logger.dart';
import 'package:letsflutssh/utils/platform.dart' as plat;
import 'package:letsflutssh/widgets/toast.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import '../../helpers/test_notifiers.dart';

/// _SecuritySection.build() reads secureKeyStorageProvider, biometricAuth-
/// Provider and biometricKeyVaultProvider during its initState probe. The
/// real implementations call `plugins.it_nomads.com/flutter_secure_storage`
/// and `dev.fluttercommunity.plus.local_auth`, neither of which have mock
/// handlers in this test file. Without replacement those calls block
/// forever in the fake-async zone and the final disposing-the-viewer test
/// eventually looks like a hang. The fakes below short-circuit every path
/// to an unavailable state so _checkState resolves immediately.
class _FakeFlutterSecureStorage implements FlutterSecureStorage {
  final Map<String, String> _store = {};

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      _store.remove(key);
    } else {
      _store[key] = value;
    }
  }

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => _store[key];

  @override
  Future<bool> containsKey({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => _store.containsKey(key);

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _store.remove(key);
  }

  @override
  Future<Map<String, String>> readAll({
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => Map.of(_store);

  @override
  Future<void> deleteAll({
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _store.clear();
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeBiometricAuth implements BiometricAuth {
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
  @override
  Future<bool> isAvailable() async => false;
  @override
  Future<BiometricAvailability> availability() async =>
      BiometricUnavailableReason.platformUnsupported;
  @override
  Future<bool> authenticate(String reason) async => false;
}

class _MockMasterPasswordManager extends MasterPasswordManager {
  bool _enabled = false;

  _MockMasterPasswordManager({required String basePath})
    : super(basePath: basePath);

  @override
  Future<Uint8List> enable(String password) async {
    _enabled = true;
    return Uint8List.fromList(List.generate(32, (i) => i));
  }

  @override
  Future<bool> isEnabled() async => _enabled;

  @override
  Future<bool> verify(String password) async => true;

  @override
  Future<Uint8List> deriveKey(String password) async {
    return Uint8List.fromList(List.generate(32, (i) => i));
  }
}

/// Stub FilePicker — the logging section wires up FilePicker.saveFile /
/// getDirectoryPath for the export path. These tests don't trigger export,
/// but the platform channel still needs a non-null instance to avoid
/// MissingPluginException if it's touched.
class _StubFilePickerPlatform extends FilePickerPlatform
    with MockPlatformInterfaceMixin {
  @override
  Future<String?> getDirectoryPath({
    String? dialogTitle,
    bool lockParentWindow = false,
    String? initialDirectory,
  }) async => null;

  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async => null;

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

  late Directory tempDir;

  setUp(() async {
    // Mobile layout + expanded sections so the logging section is reachable
    // without the desktop two-pane layout getting in the way.
    plat.debugMobilePlatformOverride = true;
    plat.debugDesktopPlatformOverride = false;
    debugCollapsibleSectionsExpanded = true;

    tempDir = await Directory.systemTemp.createTemp('settings_logging_test_');
    FilePickerPlatform.instance = _StubFilePickerPlatform();

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
    await AppLogger.instance.setEnabled(true);
  });

  tearDown(() async {
    await AppLogger.instance.setEnabled(false);
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
    final fakeStorage = _FakeFlutterSecureStorage();
    return ProviderScope(
      overrides: [
        configProvider.overrideWith(() => PrePopulatedConfigNotifier(config)),
        appVersionProvider.overrideWith(() => FixedVersionNotifier('1.5.0')),
        masterPasswordProvider.overrideWithValue(
          _MockMasterPasswordManager(basePath: tempDir.path),
        ),
        // _SecuritySection probes these on initState — let them resolve
        // instantly to "not available" instead of hanging on unmocked
        // platform channels that this test file doesn't install.
        secureKeyStorageProvider.overrideWithValue(
          SecureKeyStorage(storage: fakeStorage),
        ),
        biometricAuthProvider.overrideWithValue(_FakeBiometricAuth()),
        biometricKeyVaultProvider.overrideWithValue(
          BiometricKeyVault(storage: fakeStorage),
        ),
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
      await tester.scrollUntilVisible(
        find.text('Enable Logging'),
        200,
        scrollable: find.byType(Scrollable).first,
      );

      expect(find.text('Enable Logging'), findsOneWidget);
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
        behavior: const BehaviorConfig(enableLogging: true),
      );
      await tester.pumpWidget(buildApp(initialConfig: config));
      await tester.scrollUntilVisible(
        find.text('Live Log'),
        200,
        scrollable: find.byType(Scrollable).first,
      );

      expect(find.text('Enable Logging'), findsOneWidget);
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
        behavior: const BehaviorConfig(enableLogging: true),
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
      for (int i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    });
  });

  // ---------------------------------------------------------------------------
  // _LiveLogViewer — reachable only through _LoggingSection
  // ---------------------------------------------------------------------------
  group('_LiveLogViewer', () {
    testWidgets('renders placeholder when log file is empty', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Delete the log file so readLog() returns '' and the viewer shows its
      // "(no log entries yet)" placeholder. Sink must be closed first so the
      // file isn't held open.
      await tester.runAsync(() async {
        await AppLogger.instance.setEnabled(false);
        final logPath = AppLogger.instance.logPath;
        if (logPath != null) {
          final file = File(logPath);
          if (await file.exists()) {
            await file.delete();
          }
        }
      });

      final config = AppConfig.defaults.copyWith(
        behavior: const BehaviorConfig(enableLogging: true),
      );
      await tester.pumpWidget(buildApp(initialConfig: config));
      await tester.scrollUntilVisible(
        find.text('Live Log'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      // Let the initial async _refresh complete so the placeholder text lands.
      await tester.runAsync(
        () => Future.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump();

      expect(find.text('(no log entries yet)'), findsOneWidget);
    });

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
        behavior: const BehaviorConfig(enableLogging: true),
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

    testWidgets('backgrounding the app stops polling, resuming restarts it', (
      tester,
    ) async {
      // Guards the battery-drain fix: when the app is backgrounded, the
      // 1Hz log-file poll must stop so it doesn't keep the CPU awake and
      // prevent Android from entering doze.
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final config = AppConfig.defaults.copyWith(
        behavior: const BehaviorConfig(enableLogging: true),
      );
      await tester.pumpWidget(buildApp(initialConfig: config));
      await tester.scrollUntilVisible(
        find.text('Live Log'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.runAsync(
        () => Future.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pump();

      // Drive the lifecycle through the legal order resumed → inactive →
      // hidden → paused. The timer must be cancelled by the end so advancing
      // fake-async by multiple polling intervals is a no-op.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();

      // If the timer were still alive, this would enqueue real async file
      // reads every second; with it cancelled, nothing runs.
      await tester.pump(const Duration(seconds: 3));

      // Resume path: hidden → inactive → resumed. Timer restarts.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));

      // Pause again before teardown so no timer is pending at dispose.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();

      expect(find.text('Live Log'), findsOneWidget);
    });

    testWidgets(
      'disposing the viewer cancels its periodic timer',
      (tester) async {
        tester.view.physicalSize = const Size(800, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final config = AppConfig.defaults.copyWith(
          behavior: const BehaviorConfig(enableLogging: true),
        );
        await tester.pumpWidget(buildApp(initialConfig: config));
        await tester.scrollUntilVisible(
          find.text('Live Log'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        // Settle any in-flight real-time work (initial _refresh of the log
        // viewer, FlutterSecureStorage probe from the Security section) so
        // the next pumpWidget's dispose pass isn't racing an open async
        // operation on a platform channel that's unmocked in this test file.
        await tester.runAsync(
          () => Future.delayed(const Duration(milliseconds: 200)),
        );
        await tester.pump();

        // Replace the widget tree with something that does NOT contain
        // _LiveLogViewer — this triggers dispose() and must cancel the timer.
        // If the timer wasn't cancelled, the test framework would flag a
        // pending timer after the test finishes.
        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: Text('empty'))),
        );
        // Drain whatever disposal-triggered microtasks remain (the Security
        // section's _checkState may still be awaiting an unmocked platform
        // channel — without this flush those awaits keep the test binding
        // stuck in pending-async-work and the --timeout 30s guard trips
        // indirectly instead of the test completing cleanly).
        await tester.runAsync(
          () => Future.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();

        expect(find.text('empty'), findsOneWidget);
        expect(find.text('Live Log'), findsNothing);
      },
      timeout: const Timeout(Duration(seconds: 15)),
    );
  });
}
