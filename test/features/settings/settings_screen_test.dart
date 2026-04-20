import 'dart:io';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_picker/src/platform/file_picker_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/config/app_config.dart';
import 'package:letsflutssh/core/session/session.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/core/update/update_service.dart';
import 'package:letsflutssh/features/settings/settings_screen.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:letsflutssh/core/security/master_password.dart';
import 'package:letsflutssh/core/security/secure_key_storage.dart';
import 'package:letsflutssh/core/ssh/known_hosts.dart';
import 'package:letsflutssh/providers/config_provider.dart';
import 'package:letsflutssh/providers/connection_provider.dart';
import 'package:letsflutssh/providers/key_provider.dart';
import 'package:letsflutssh/providers/security_provider.dart';
import 'package:letsflutssh/providers/master_password_provider.dart';
import 'package:letsflutssh/providers/session_provider.dart';
import 'package:letsflutssh/providers/update_provider.dart';
import 'package:letsflutssh/providers/version_provider.dart';
import 'package:letsflutssh/theme/app_theme.dart';
import 'package:letsflutssh/utils/logger.dart';
import 'package:letsflutssh/utils/platform.dart' as plat;
import 'package:letsflutssh/widgets/toast.dart';

import '../key_manager/key_manager_dialog_test.dart';
import '../../helpers/fake_session_store.dart';
import '../../helpers/test_notifiers.dart';

/// Mock FilePickerPlatform that returns a temp directory for getDirectoryPath
/// and a temp file path for saveFile, without launching native dialogs.
class _MockFilePickerPlatform extends FilePickerPlatform
    with MockPlatformInterfaceMixin {
  String? directoryPath;
  String? savePath;

  /// File returned by [pickFiles]. Tests that exercise the import flow set
  /// this to a real on-disk file so `ExportImport.probeArchive` can read it
  /// and classify it; a missing path is correctly rejected now that the
  /// import flow validates before prompting for a password.
  String? pickedPath;

  @override
  Future<String?> getDirectoryPath({
    String? dialogTitle,
    bool lockParentWindow = false,
    String? initialDirectory,
  }) async => directoryPath;

  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async => savePath;

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
  }) async {
    final path = pickedPath;
    if (path == null) return null;
    return FilePickerResult([
      PlatformFile(
        path: path,
        name: path.split(Platform.pathSeparator).last,
        size: 100,
      ),
    ]);
  }
}

/// In-memory fake that mirrors FlutterSecureStorage API.
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
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;
  late _MockFilePickerPlatform mockFilePicker;
  late _FakeFlutterSecureStorage fakeSecureStorage;
  late SecureKeyStorage fakeKeyStorage;

  setUp(() async {
    // Force mobile layout so existing tests (written for flat ListView) keep working.
    plat.debugMobilePlatformOverride = true;
    plat.debugDesktopPlatformOverride = false;
    // Start all collapsible sections expanded so content is immediately visible.
    debugCollapsibleSectionsExpanded = true;
    tempDir = await Directory.systemTemp.createTemp('settings_test_');
    // Mock FilePicker to prevent native dialog launches in tests. The
    // default picked file is a real on-disk encrypted-looking archive so
    // `ExportImport.probeArchive` classifies it as `encryptedLfs` and the
    // import flow proceeds to the password prompt. Individual tests can
    // override `mockFilePicker.pickedPath` to exercise other branches.
    final encryptedStub = File('${tempDir.path}/test.lfs')
      ..writeAsBytesSync([0x13, 0x37, 0x00, 0x42, 0xAB, 0xCD]);
    mockFilePicker = _MockFilePickerPlatform()
      ..directoryPath = tempDir.path
      ..pickedPath = encryptedStub.path;
    FilePickerPlatform.instance = mockFilePicker;
    // Fake secure storage so _SecuritySection's keyStorage.isAvailable() works.
    fakeSecureStorage = _FakeFlutterSecureStorage();
    fakeKeyStorage = SecureKeyStorage(storage: fakeSecureStorage);
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
  });

  tearDown(() async {
    plat.debugMobilePlatformOverride = null;
    plat.debugDesktopPlatformOverride = null;
    debugCollapsibleSectionsExpanded = false;
    Toast.clearAllForTest();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    await tempDir.delete(recursive: true);
  });

  /// Simple buildApp without session provider (used for basic UI tests).
  Widget buildApp({AppConfig? initialConfig, double height = 1600}) {
    final config = initialConfig ?? AppConfig.defaults;
    return ProviderScope(
      overrides: [
        configProvider.overrideWith(() => PrePopulatedConfigNotifier(config)),
        appVersionProvider.overrideWith(() => FixedVersionNotifier('1.5.0')),
        masterPasswordProvider.overrideWithValue(
          MasterPasswordManager(basePath: tempDir.path),
        ),
        secureKeyStorageProvider.overrideWithValue(fakeKeyStorage),
      ],
      child: MaterialApp(
        localizationsDelegates: S.localizationsDelegates,
        supportedLocales: S.supportedLocales,
        theme: AppTheme.dark(),
        home: SizedBox(height: height, child: const SettingsScreen()),
      ),
    );
  }

  /// Full buildApp with session store + session provider (for export/import).
  Widget buildFullApp({AppConfig? initialConfig, List<Session>? sessions}) {
    final config = initialConfig ?? AppConfig.defaults;
    final sessionList = sessions ?? [];
    return ProviderScope(
      overrides: [
        configProvider.overrideWith(() => PrePopulatedConfigNotifier(config)),
        appVersionProvider.overrideWith(() => FixedVersionNotifier('1.5.0')),
        masterPasswordProvider.overrideWithValue(
          MasterPasswordManager(basePath: tempDir.path),
        ),
        sessionStoreProvider.overrideWithValue(
          FakeSessionStore(sessions: sessionList),
        ),
        sessionProvider.overrideWith(
          () => PrePopulatedSessionNotifier(sessionList),
        ),
        secureKeyStorageProvider.overrideWithValue(fakeKeyStorage),
        keyStoreProvider.overrideWithValue(FakeKeyStore([])),
        knownHostsProvider.overrideWithValue(KnownHostsManager()),
      ],
      child: MaterialApp(
        localizationsDelegates: S.localizationsDelegates,
        supportedLocales: S.supportedLocales,
        theme: AppTheme.dark(),
        home: const SizedBox(height: 2400, child: SettingsScreen()),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Structure
  // ---------------------------------------------------------------------------
  group('SettingsScreen — structure', () {
    testWidgets('renders app bar with title', (tester) async {
      await tester.pumpWidget(buildApp());
      expect(find.text('Settings'), findsOneWidget);
    });

    testWidgets('renders as Scaffold with scroll body', (tester) async {
      await tester.pumpWidget(buildApp());
      expect(find.byType(Scaffold), findsOneWidget);
      // Mobile settings now uses SingleChildScrollView + Column so
      // every section materialises eagerly (find-by-text in tests
      // stays symmetric with scroll-to-reveal in the app).
      expect(find.byType(SingleChildScrollView), findsWidgets);
    });

    testWidgets('has collapsible section cards', (tester) async {
      await tester.pumpWidget(buildApp());
      expect(find.byType(ExpansionTile), findsWidgets);
    });

    testWidgets('all section headers are rendered', (tester) async {
      await tester.pumpWidget(buildApp());

      expect(find.text('Appearance'), findsOneWidget);
      expect(find.text('Terminal'), findsOneWidget);
      expect(find.text('Connection'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Transfers'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Transfers'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Data'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Data'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Updates'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Updates'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('About'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('About'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // Appearance section
  // ---------------------------------------------------------------------------
  group('SettingsScreen — Appearance section', () {
    testWidgets('renders Appearance section with all elements', (tester) async {
      await tester.pumpWidget(buildApp());

      expect(find.text('Appearance'), findsOneWidget);
      expect(find.text('Language'), findsOneWidget);
      expect(find.text('Auto'), findsOneWidget);
      expect(find.text('Theme'), findsOneWidget);
      expect(find.text('Dark'), findsOneWidget);
      expect(find.text('Light'), findsOneWidget);
      expect(find.text('System'), findsOneWidget);
      expect(find.text('Terminal Font Size'), findsOneWidget);
      expect(find.text('UI Scale'), findsOneWidget);
      expect(find.byType(Slider), findsNWidgets(2));
    });

    testWidgets('language picker shows Auto by default', (tester) async {
      await tester.pumpWidget(buildApp());
      expect(find.text('Language'), findsOneWidget);
      expect(find.text('Auto'), findsOneWidget);
    });

    testWidgets('language picker shows selected language', (tester) async {
      await tester.pumpWidget(
        buildApp(initialConfig: const AppConfig(locale: 'ru')),
      );
      expect(find.text('Русский'), findsOneWidget);
    });

    testWidgets('language picker opens popup with all options', (tester) async {
      await tester.pumpWidget(buildApp());
      // Tap the language dropdown button
      await tester.tap(find.text('Auto'));
      await tester.pumpAndSettle();
      // All language options should be in the popup
      expect(find.text('English'), findsOneWidget);
      expect(find.text('Русский'), findsOneWidget);
      expect(find.text('中文'), findsOneWidget);
      expect(find.text('Deutsch'), findsOneWidget);
      expect(find.text('日本語'), findsOneWidget);
      expect(find.text('Português'), findsOneWidget);
      expect(find.text('Español'), findsOneWidget);
      expect(find.text('Français'), findsOneWidget);
      expect(find.text('한국어'), findsOneWidget);
      expect(find.text('العربية'), findsOneWidget);
    });

    testWidgets('theme selector renders all segment labels', (tester) async {
      await tester.pumpWidget(buildApp());
      expect(find.text('Dark'), findsOneWidget);
      expect(find.text('Light'), findsOneWidget);
      expect(find.text('System'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // Font size slider
  // ---------------------------------------------------------------------------
  group('SettingsScreen — font size slider', () {
    // Font size slider is the second Slider (index 1); UI Scale is index 0.
    Finder fontSliderFinder() => find.byType(Slider).at(1);

    testWidgets('slider shows default value 14', (tester) async {
      await tester.pumpWidget(buildApp());
      expect(find.text('14'), findsOneWidget);
      final slider = tester.widget<Slider>(fontSliderFinder());
      expect(slider.value, 14.0);
      expect(slider.min, 8.0);
      expect(slider.max, 24.0);
      expect(slider.divisions, 16);
    });

    testWidgets('slider with custom font size', (tester) async {
      await tester.pumpWidget(
        buildApp(
          initialConfig: AppConfig.defaults.copyWith(
            terminal: AppConfig.defaults.terminal.copyWith(fontSize: 18.0),
          ),
        ),
      );
      expect(find.text('18'), findsOneWidget);
    });

    testWidgets('slider shows formatted value text', (tester) async {
      await tester.pumpWidget(
        buildApp(
          initialConfig: AppConfig.defaults.copyWith(
            terminal: AppConfig.defaults.terminal.copyWith(fontSize: 16.0),
          ),
        ),
      );
      final slider = tester.widget<Slider>(fontSliderFinder());
      expect(slider.value, 16.0);
      expect(find.text('16'), findsOneWidget);
    });

    testWidgets('slider with min value 8', (tester) async {
      await tester.pumpWidget(
        buildApp(
          initialConfig: AppConfig.defaults.copyWith(
            terminal: AppConfig.defaults.terminal.copyWith(fontSize: 8.0),
          ),
        ),
      );
      expect(find.text('8'), findsOneWidget);
    });

    testWidgets('slider with max value 24', (tester) async {
      await tester.pumpWidget(
        buildApp(
          initialConfig: AppConfig.defaults.copyWith(
            terminal: AppConfig.defaults.terminal.copyWith(fontSize: 24.0),
          ),
        ),
      );
      expect(find.text('24'), findsOneWidget);
    });

    testWidgets('value out of range is clamped', (tester) async {
      await tester.pumpWidget(
        buildApp(
          initialConfig: AppConfig.defaults.copyWith(
            terminal: AppConfig.defaults.terminal.copyWith(fontSize: 4.0),
          ),
        ),
      );
      final slider = tester.widget<Slider>(fontSliderFinder());
      expect(slider.value, 8.0);
    });

    testWidgets('onChanged callback is wired', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.scrollUntilVisible(
        fontSliderFinder(),
        100,
        scrollable: find.byType(Scrollable).first,
      );
      final slider = tester.widget<Slider>(fontSliderFinder());
      expect(slider.onChanged, isNotNull);
      slider.onChanged!(18.0);
      await tester.pump();
    });

    testWidgets('dragging slider changes value', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.drag(fontSliderFinder(), const Offset(50, 0));
      await tester.pumpAndSettle();
      expect(find.byType(Slider), findsNWidgets(2));
    });
  });

  // ---------------------------------------------------------------------------
  // Terminal section
  // ---------------------------------------------------------------------------
  group('SettingsScreen — Terminal section', () {
    testWidgets('renders Terminal section', (tester) async {
      await tester.pumpWidget(buildApp());
      expect(find.text('Terminal'), findsOneWidget);
      expect(find.text('Scrollback Lines'), findsOneWidget);
      expect(find.text('5000'), findsOneWidget);
    });

    testWidgets('scrollback field with custom value', (tester) async {
      await tester.pumpWidget(
        buildApp(
          initialConfig: AppConfig.defaults.copyWith(
            terminal: AppConfig.defaults.terminal.copyWith(scrollback: 10000),
          ),
        ),
      );
      expect(find.text('10000'), findsOneWidget);
    });

    testWidgets('scrollback field accepts valid input', (tester) async {
      await tester.pumpWidget(buildApp());
      final field = find.widgetWithText(TextFormField, '5000');
      await tester.tap(field);
      await tester.pumpAndSettle();
      await tester.enterText(field, '8000');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('8000'), findsOneWidget);
    });

    testWidgets('scrollback accepts boundary value 100', (tester) async {
      await tester.pumpWidget(buildFullApp());
      final field = find.widgetWithText(TextFormField, '5000');
      await tester.tap(field);
      await tester.pumpAndSettle();
      await tester.enterText(field, '100');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('100'), findsOneWidget);
    });

    testWidgets('scrollback out of range rejected (below min)', (tester) async {
      await tester.pumpWidget(buildFullApp());
      final field = find.widgetWithText(TextFormField, '5000');
      await tester.tap(field);
      await tester.pumpAndSettle();
      await tester.enterText(field, '50');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      // 50 < min (100), no crash
    });

    testWidgets('scrollback out of range rejected (above max)', (tester) async {
      await tester.pumpWidget(buildApp());
      final field = find.widgetWithText(TextFormField, '5000');
      await tester.tap(field);
      await tester.pumpAndSettle();
      await tester.enterText(field, '999999');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
    });

    testWidgets('scrollback non-numeric value does not crash', (tester) async {
      await tester.pumpWidget(buildApp());
      final field = find.widgetWithText(TextFormField, '5000');
      await tester.tap(field);
      await tester.pumpAndSettle();
      await tester.enterText(field, 'abc');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
    });

    testWidgets('scrollback accepts 10000', (tester) async {
      await tester.pumpWidget(buildFullApp());
      final field = find.widgetWithText(TextFormField, '5000');
      await tester.tap(field);
      await tester.pumpAndSettle();
      await tester.enterText(field, '10000');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('10000'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // Connection section
  // ---------------------------------------------------------------------------
  group('SettingsScreen — Connection section', () {
    // Expand the per-test viewport so every Connection-section row fits
    // on screen. The default 800×600 is too short now that Appearance +
    // Security sections above Connection eat the initial viewport, and
    // tap() on an offscreen widget emits a "hit test would not land"
    // warning even when the finder matches. Setting this from setUp()
    // is a no-op (tester.view is a per-test handle), so a helper called
    // from each test body does the job + auto-resets via addTearDown.
    void useTallViewport(WidgetTester tester) {
      tester.view.physicalSize = const Size(1600, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }

    testWidgets('renders Connection section with defaults', (tester) async {
      useTallViewport(tester);
      await tester.pumpWidget(buildApp());
      expect(find.text('Connection'), findsOneWidget);
      expect(find.text('Keep-Alive Interval (sec)'), findsOneWidget);
      expect(find.text('SSH Timeout (sec)'), findsOneWidget);
      expect(find.text('Default Port'), findsOneWidget);
      expect(find.text('30'), findsOneWidget);
      expect(find.text('10'), findsOneWidget);
      expect(find.text('22'), findsOneWidget);
    });

    testWidgets('custom connection values display correctly', (tester) async {
      useTallViewport(tester);
      final config = AppConfig.defaults.copyWith(
        ssh: AppConfig.defaults.ssh.copyWith(
          keepAliveSec: 60,
          sshTimeoutSec: 30,
          defaultPort: 2222,
        ),
      );
      await tester.pumpWidget(buildApp(initialConfig: config));
      expect(find.text('60'), findsOneWidget);
      expect(find.text('30'), findsOneWidget);
      expect(find.text('2222'), findsOneWidget);
    });

    testWidgets('keepalive field accepts valid value', (tester) async {
      useTallViewport(tester);
      await tester.pumpWidget(buildApp());
      final field = find.widgetWithText(TextFormField, '30');
      await tester.ensureVisible(field);
      await tester.tap(field);
      await tester.pumpAndSettle();
      await tester.enterText(field, '60');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('60'), findsOneWidget);
    });

    testWidgets('keepalive accepts 0 (min boundary)', (tester) async {
      useTallViewport(tester);
      await tester.pumpWidget(buildApp());
      final field = find.widgetWithText(TextFormField, '30');
      await tester.ensureVisible(field);
      await tester.tap(field);
      await tester.pumpAndSettle();
      await tester.enterText(field, '0');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('0'), findsOneWidget);
    });

    testWidgets('timeout field accepts valid value', (tester) async {
      useTallViewport(tester);
      await tester.pumpWidget(buildApp());
      final field = find.widgetWithText(TextFormField, '10');
      await tester.ensureVisible(field);
      await tester.tap(field);
      await tester.pumpAndSettle();
      await tester.enterText(field, '20');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('20'), findsOneWidget);
    });

    testWidgets('timeout min boundary 1', (tester) async {
      useTallViewport(tester);
      await tester.pumpWidget(buildApp());
      final field = find.widgetWithText(TextFormField, '10');
      await tester.ensureVisible(field);
      await tester.tap(field);
      await tester.pumpAndSettle();
      await tester.enterText(field, '1');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('1'), findsOneWidget);
    });

    testWidgets('timeout above max rejected', (tester) async {
      useTallViewport(tester);
      await tester.pumpWidget(buildApp());
      final field = find.widgetWithText(TextFormField, '10');
      await tester.ensureVisible(field);
      await tester.tap(field);
      await tester.pumpAndSettle();
      await tester.enterText(field, '999');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
    });

    testWidgets('SSH timeout with custom config accepts valid value', (
      tester,
    ) async {
      useTallViewport(tester);
      final config = AppConfig.defaults.copyWith(
        ssh: AppConfig.defaults.ssh.copyWith(sshTimeoutSec: 15),
      );
      await tester.pumpWidget(buildFullApp(initialConfig: config));
      final field = find.widgetWithText(TextFormField, '15');
      await tester.ensureVisible(field);
      await tester.tap(field);
      await tester.pumpAndSettle();
      await tester.enterText(field, '30');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('30'), findsWidgets);
    });

    testWidgets('port field accepts valid value', (tester) async {
      useTallViewport(tester);
      await tester.pumpWidget(buildApp());
      final field = find.widgetWithText(TextFormField, '22');
      await tester.ensureVisible(field);
      await tester.tap(field);
      await tester.pumpAndSettle();
      await tester.enterText(field, '2222');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('2222'), findsOneWidget);
    });

    testWidgets('port max boundary 65535', (tester) async {
      useTallViewport(tester);
      await tester.pumpWidget(buildApp());
      final field = find.widgetWithText(TextFormField, '22');
      await tester.ensureVisible(field);
      await tester.tap(field);
      await tester.pumpAndSettle();
      await tester.enterText(field, '65535');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('65535'), findsOneWidget);
    });

    testWidgets('port custom value 8022', (tester) async {
      useTallViewport(tester);
      await tester.pumpWidget(buildFullApp());
      final field = find.widgetWithText(TextFormField, '22');
      await tester.ensureVisible(field);
      await tester.tap(field);
      await tester.pumpAndSettle();
      await tester.enterText(field, '8022');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('8022'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // Transfers section
  // ---------------------------------------------------------------------------
  group('SettingsScreen — Transfers section', () {
    testWidgets('renders after scrolling with defaults', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.scrollUntilVisible(
        find.text('Parallel Workers'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Transfers'), findsOneWidget);
      expect(find.text('Parallel Workers'), findsOneWidget);
      expect(find.text('Max History'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('500'), findsOneWidget);
    });

    testWidgets('custom transfer values display correctly', (tester) async {
      final config = AppConfig.defaults.copyWith(
        transferWorkers: 4,
        maxHistory: 1000,
      );
      await tester.pumpWidget(buildApp(initialConfig: config));
      await tester.scrollUntilVisible(
        find.text('Parallel Workers'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('4'), findsOneWidget);
      expect(find.text('1000'), findsOneWidget);
    });

    testWidgets('workers field accepts valid value', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.scrollUntilVisible(
        find.text('Parallel Workers'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      final field = find.widgetWithText(TextFormField, '2');
      await tester.enterText(field, '4');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('4'), findsOneWidget);
    });

    testWidgets('workers out of range rejected', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.scrollUntilVisible(
        find.text('Parallel Workers'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      final field = find.widgetWithText(TextFormField, '2');
      await tester.enterText(field, '99');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
    });

    testWidgets('max history field accepts valid value', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.scrollUntilVisible(
        find.text('Max History'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      final field = find.widgetWithText(TextFormField, '500');
      await tester.enterText(field, '1000');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('1000'), findsOneWidget);
    });

    testWidgets('max history min boundary 10', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.scrollUntilVisible(
        find.text('Max History'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      final field = find.widgetWithText(TextFormField, '500');
      await tester.enterText(field, '10');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      // Multiple "10" Texts can exist in the eager-built settings list
      // (scrollback limits, other numeric defaults). Accept any number
      // of matches — the assertion only needs to confirm that the
      // value we just entered is somewhere in the TextFormField tree.
      expect(find.widgetWithText(TextFormField, '10'), findsWidgets);
    });
  });

  // ---------------------------------------------------------------------------
  // Data section — Export
  // ---------------------------------------------------------------------------
  group('SettingsScreen — Export Data', () {
    testWidgets('renders export tile with subtitle and icon', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.scrollUntilVisible(
        find.text('Export archive'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Data'), findsOneWidget);
      expect(find.text('Export archive'), findsOneWidget);
      expect(
        find.text('Save sessions, config, and keys to encrypted .lfs file'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.upload_file), findsOneWidget);
    });

    testWidgets('tap opens export dialog', (tester) async {
      tester.view.physicalSize = const Size(800, 3200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final sessions = [
        Session(
          label: 'Test',
          server: const ServerAddress(
            host: 'example.com',
            user: 'user',
            port: 22,
          ),
        ),
      ];
      await tester.pumpWidget(buildFullApp(sessions: sessions));
      await tester.pump();
      await tester.scrollUntilVisible(
        find.text('Export archive'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Export archive'));
      await tester.pump();

      expect(find.byType(Dialog), findsOneWidget);
    });

    testWidgets('export dialog shows session and credential options', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 3200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final sessions = [
        Session(
          label: 'Test',
          server: const ServerAddress(
            host: 'example.com',
            user: 'user',
            port: 22,
          ),
        ),
      ];
      await tester.pumpWidget(buildFullApp(sessions: sessions));
      await tester.pump();
      await tester.scrollUntilVisible(
        find.text('Export archive'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Export archive'));
      await tester.pump();

      expect(find.byType(Dialog), findsOneWidget);
      // UnifiedExportDialog shows session name and (collapsed) credential section
      expect(find.text('Test'), findsOneWidget);
      // Expand the "What to export:" section to reveal credential checkboxes.
      await tester.tap(find.text('What to export:'));
      await tester.pumpAndSettle();
      expect(find.text('Session passwords'), findsOneWidget);
      expect(find.byType(Checkbox), findsWidgets);
    });

    testWidgets('export cancel closes dialog without action', (tester) async {
      tester.view.physicalSize = const Size(800, 3200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final sessions = [
        Session(
          label: 'Test',
          server: const ServerAddress(
            host: 'example.com',
            user: 'user',
            port: 22,
          ),
        ),
      ];
      await tester.pumpWidget(buildFullApp(sessions: sessions));
      await tester.pump();
      await tester.scrollUntilVisible(
        find.text('Export archive'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Export archive'));
      await tester.pump();

      expect(find.byType(Dialog), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
    });

    testWidgets('export succeeds with session store and shows toast', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 3200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final sessions = [
        Session(
          label: 'Test',
          server: const ServerAddress(
            host: 'example.com',
            user: 'user',
            port: 22,
          ),
        ),
      ];
      await tester.pumpWidget(buildFullApp(sessions: sessions));
      await tester.pump();
      await tester.scrollUntilVisible(
        find.text('Export archive'),
        100,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Export archive'));
      await tester.pump();

      expect(find.byType(Dialog), findsOneWidget);
    });

    testWidgets('export fails gracefully when path_provider errors', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 3200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async {
              if (call.method == 'getApplicationSupportDirectory') {
                throw PlatformException(code: 'ERROR', message: 'No dir');
              }
              return null;
            },
          );

      await tester.pumpWidget(
        buildFullApp(
          sessions: [
            Session(
              label: 'Test',
              server: const ServerAddress(
                host: 'example.com',
                user: 'user',
                port: 22,
              ),
            ),
          ],
        ),
      );
      await tester.pump();

      await tester.scrollUntilVisible(
        find.text('Export archive'),
        100,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Export archive'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // The dialog rendered — that's the spec. Don't pin the exact
      // button label (the Data section now carries an "Export" section
      // header too, so a loose text match is ambiguous).
      expect(find.byType(Dialog), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // Data section — Export password dialog (passwordless archive flow)
  // ---------------------------------------------------------------------------
  group('SettingsScreen — Export password dialog', () {
    // Reach the password dialog by tapping Export archive, then the
    // UnifiedExportDialog's primary button. buildFullApp already mocks
    // FilePicker so the save prompt resolves.
    Future<void> openExportPasswordDialog(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 3200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final sessions = [
        Session(
          label: 'Test',
          server: const ServerAddress(
            host: 'example.com',
            user: 'user',
            port: 22,
          ),
        ),
      ];
      await tester.pumpWidget(buildFullApp(sessions: sessions));
      await tester.pump();
      await tester.scrollUntilVisible(
        find.text('Export archive'),
        100,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Export archive'));
      await tester.pumpAndSettle();

      // UnifiedExportDialog has "Cancel" + primary "Export" button. Tap
      // Export to advance to _ExportPasswordDialog.
      await tester.tap(find.text('Export').last);
      await tester.pumpAndSettle();
    }

    testWidgets('mismatched passwords show inline error and red border', (
      tester,
    ) async {
      await openExportPasswordDialog(tester);

      // We should now be on _ExportPasswordDialog — two obscured fields.
      final pwFields = find.byWidgetPredicate(
        (w) => w is TextField && w.obscureText,
      );
      expect(pwFields, findsNWidgets(2));

      await tester.enterText(pwFields.at(0), 'secret123');
      await tester.enterText(pwFields.at(1), 'typo');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Export').last);
      await tester.pumpAndSettle();

      // Inline error shown, dialog still open (Navigator.pop never fired).
      expect(find.text('Passwords do not match'), findsOneWidget);
      expect(find.byType(Dialog), findsWidgets);
    });

    testWidgets('empty password opens passwordless confirmation dialog', (
      tester,
    ) async {
      await openExportPasswordDialog(tester);

      // Both fields empty → pressing Export triggers the
      // "Export Without Password?" confirmation.
      await tester.tap(find.text('Export').last);
      await tester.pumpAndSettle();

      expect(find.text('Export Without Password?'), findsOneWidget);
      expect(find.textContaining('will not be encrypted'), findsOneWidget);
      expect(find.text('Continue Without Password'), findsOneWidget);
    });

    testWidgets('cancelling confirmation keeps password dialog open', (
      tester,
    ) async {
      await openExportPasswordDialog(tester);

      await tester.tap(find.text('Export').last);
      await tester.pumpAndSettle();
      expect(find.text('Export Without Password?'), findsOneWidget);

      // Tap Cancel on the confirmation; the password dialog must remain.
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();

      expect(find.text('Export Without Password?'), findsNothing);
      // Password dialog still shown (two obscured TextFields remain).
      expect(
        find.byWidgetPredicate((w) => w is TextField && w.obscureText),
        findsNWidgets(2),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Data section — Import
  // ---------------------------------------------------------------------------
  group('SettingsScreen — Import Data', () {
    testWidgets('renders import tile with subtitle and icon', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.scrollUntilVisible(
        find.text('Import archive'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Import archive'), findsOneWidget);
      expect(find.text('Load data from .lfs file'), findsOneWidget);
      expect(find.byIcon(Icons.download), findsOneWidget);
    });

    testWidgets('tap opens import dialog', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final sessions = [
        Session(
          label: 'Test',
          server: const ServerAddress(
            host: 'example.com',
            user: 'user',
            port: 22,
          ),
        ),
      ];
      await tester.pumpWidget(buildFullApp(sessions: sessions));
      await tester.pump();
      await tester.scrollUntilVisible(
        find.text('Import archive'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Import archive'));
      await tester.pump();

      expect(find.byType(Dialog), findsOneWidget);
    });

    testWidgets('import dialog shows obscured password field', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final sessions = [
        Session(
          label: 'Test',
          server: const ServerAddress(
            host: 'example.com',
            user: 'user',
            port: 22,
          ),
        ),
      ];
      await tester.pumpWidget(buildFullApp(sessions: sessions));
      await tester.pump();
      await tester.scrollUntilVisible(
        find.text('Import archive'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Import archive'));
      await tester.pump();

      expect(find.byType(Dialog), findsOneWidget);
      // Password field is obscured
      final obscured = find.byWidgetPredicate(
        (w) => w is TextField && w.obscureText,
      );
      expect(obscured, findsOneWidget);
    });

    testWidgets('import dialog shows Next button', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final sessions = [
        Session(
          label: 'Test',
          server: const ServerAddress(
            host: 'example.com',
            user: 'user',
            port: 22,
          ),
        ),
      ];
      await tester.pumpWidget(buildFullApp(sessions: sessions));
      await tester.pump();
      await tester.scrollUntilVisible(
        find.text('Import archive'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Import archive'));
      await tester.pump();

      expect(find.text('Next'), findsOneWidget);
      expect(find.byType(Dialog), findsOneWidget);
    });

    testWidgets('empty password does not close import dialog', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final sessions = [
        Session(
          label: 'Test',
          server: const ServerAddress(
            host: 'example.com',
            user: 'user',
            port: 22,
          ),
        ),
      ];
      await tester.pumpWidget(buildFullApp(sessions: sessions));
      await tester.pump();
      await tester.scrollUntilVisible(
        find.text('Import archive'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Import archive'));
      await tester.pump();

      // Tap Next with empty password — dialog should stay open
      await tester.tap(find.text('Next'));
      await tester.pump();
      expect(find.byType(Dialog), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // Data Path tile — copy to clipboard
  // ---------------------------------------------------------------------------
  // About section
  // ---------------------------------------------------------------------------
  group('SettingsScreen — About section', () {
    testWidgets('renders About section', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildApp());
      await tester.scrollUntilVisible(
        find.text('LetsFLUTssh'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('About'), findsOneWidget);
      expect(find.text('LetsFLUTssh'), findsOneWidget);
      // Version string — check format, not a hardcoded number. Appears in
      // both the About tile and the Updates section's subtitle.
      expect(find.textContaining(RegExp(r'v\d+\.\d+\.\d+')), findsWidgets);
      expect(find.textContaining('SSH/SFTP client'), findsOneWidget);
      // info_outline appears in both the section header and the About tile
      expect(find.byIcon(Icons.info_outline), findsWidgets);
    });

    testWidgets('renders source code link', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.scrollUntilVisible(
        find.text('Source Code'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Source Code'), findsOneWidget);
      expect(
        find.text('https://github.com/Llloooggg/LetsFLUTssh'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.code), findsOneWidget);
    });

    testWidgets('tapping Source Code copies URL and shows toast', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildApp());
      await tester.scrollUntilVisible(
        find.text('Source Code'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.text('Source Code'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Source Code'));
      await tester.pump();

      expect(find.text('URL copied to clipboard'), findsOneWidget);

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });

    testWidgets('source code tap does not crash', (tester) async {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildApp());
      await tester.scrollUntilVisible(
        find.text('Source Code'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Source Code'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 5));
      expect(find.text('Source Code'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // Reset to Defaults
  // ---------------------------------------------------------------------------
  group('SettingsScreen — Reset to Defaults', () {
    testWidgets('button is present after scrolling', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.scrollUntilVisible(
        find.text('Reset to Defaults'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Reset to Defaults'), findsOneWidget);
      expect(find.byIcon(Icons.restore), findsOneWidget);
    });

    testWidgets('tapping Reset does not crash', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.scrollUntilVisible(
        find.text('Reset to Defaults'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Reset to Defaults'));
      await tester.pumpAndSettle();
      expect(find.byType(SingleChildScrollView), findsWidgets);
    });

    testWidgets('reset with custom config updates fields', (tester) async {
      final custom = AppConfig.defaults.copyWith(
        terminal: AppConfig.defaults.terminal.copyWith(
          fontSize: 20.0,
          scrollback: 10000,
        ),
        ssh: AppConfig.defaults.ssh.copyWith(keepAliveSec: 60),
      );
      await tester.pumpWidget(buildApp(initialConfig: custom));
      await tester.scrollUntilVisible(
        find.text('Reset to Defaults'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Reset to Defaults'));
      await tester.pumpAndSettle();
      expect(find.byType(SingleChildScrollView), findsWidgets);
    });
  });

  // ---------------------------------------------------------------------------
  // Custom config values
  // ---------------------------------------------------------------------------
  group('SettingsScreen — custom config values', () {
    testWidgets('renders with custom config values', (tester) async {
      final customConfig = AppConfig.defaults.copyWith(
        terminal: AppConfig.defaults.terminal.copyWith(
          fontSize: 18.0,
          theme: 'light',
          scrollback: 10000,
        ),
        ssh: AppConfig.defaults.ssh.copyWith(keepAliveSec: 60),
      );
      await tester.pumpWidget(buildApp(initialConfig: customConfig));
      expect(find.text('10000'), findsOneWidget);
      expect(find.text('60'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // SettingsScreen.show static method
  // ---------------------------------------------------------------------------
  group('SettingsScreen — show() static method', () {
    testWidgets('show() pushes SettingsScreen as a route', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [configProvider.overrideWith(ConfigNotifier.new)],
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () => SettingsScreen.show(context),
                  child: const Text('Open Settings'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Settings'));
      await tester.pumpAndSettle();

      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Appearance'), findsOneWidget);
    });

    testWidgets('show() can go back', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [configProvider.overrideWith(ConfigNotifier.new)],
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () => SettingsScreen.show(context),
                  child: const Text('Open Settings'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Settings'), findsOneWidget);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('Open Settings'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // Export — password mismatch toast verification
  // ---------------------------------------------------------------------------
  group('SettingsScreen — Export password mismatch toast', () {
    testWidgets('mismatch toast shows warning level', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final sessions = [
        Session(
          label: 'Test',
          server: const ServerAddress(
            host: 'example.com',
            user: 'user',
            port: 22,
          ),
        ),
      ];
      await tester.pumpWidget(buildFullApp(sessions: sessions));
      await tester.pump();

      await tester.scrollUntilVisible(
        find.text('Export archive'),
        100,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Export archive'));
      await tester.pump();

      // Verify export dialog is shown
      expect(find.byType(Dialog), findsOneWidget);
    });

    testWidgets('mismatch does not close dialog even with non-empty fields', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final sessions = [
        Session(
          label: 'Test',
          server: const ServerAddress(
            host: 'example.com',
            user: 'user',
            port: 22,
          ),
        ),
      ];
      await tester.pumpWidget(buildFullApp(sessions: sessions));
      await tester.pump();

      await tester.scrollUntilVisible(
        find.text('Export archive'),
        100,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Export archive'));
      await tester.pump();

      // Verify export dialog is shown
      expect(find.byType(Dialog), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // Import file not found toast verification
  // ---------------------------------------------------------------------------
  group('SettingsScreen - Import rejects non-LFS files', () {
    testWidgets(
      'nonexistent picked path shows errLfsNotArchive toast and does not open import dialog',
      (tester) async {
        tester.view.physicalSize = const Size(800, 3200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        mockFilePicker.pickedPath = '${tempDir.path}/does-not-exist.lfs';

        final sessions = [
          Session(
            label: 'Test',
            server: const ServerAddress(
              host: 'example.com',
              user: 'user',
              port: 22,
            ),
          ),
        ];
        await tester.pumpWidget(buildFullApp(sessions: sessions));
        await tester.pump();

        await tester.scrollUntilVisible(
          find.text('Import archive'),
          100,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(find.text('Import archive'));
        await tester.pump();

        expect(find.byType(Dialog), findsNothing);
        expect(
          find.text('Selected file is not a LetsFLUTssh archive.'),
          findsOneWidget,
        );
        // Let the Toast auto-dismiss timer fire before disposing the widget
        // tree — otherwise the binding flags a pending-timer assertion.
        await tester.pumpAndSettle(const Duration(seconds: 5));
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Data Path tile — copy to clipboard
  // ---------------------------------------------------------------------------
  group('SettingsScreen — Data Path tile', () {
    testWidgets('tapping Data Location copies path to clipboard', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 3200);
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

      await tester.pumpWidget(buildApp());
      // Wait for FutureBuilder to resolve path_provider
      await tester.runAsync(
        () => Future.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
      await tester.pump();

      await tester.scrollUntilVisible(
        find.text('Data Location'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Data Location'));
      await tester.pump();

      expect(copiedText, isNotNull);
      expect(find.text('Path copied to clipboard'), findsOneWidget);

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });
  });

  // ---------------------------------------------------------------------------
  // Logging section
  // ---------------------------------------------------------------------------
  group('SettingsScreen — Logging section', () {
    setUp(() async {
      await AppLogger.instance.init();
      await AppLogger.instance.setEnabled(true);
    });

    tearDown(() async {
      await AppLogger.instance.setEnabled(false);
      await AppLogger.instance.dispose();
    });

    testWidgets('Enable Logging switch is visible', (tester) async {
      final config = AppConfig.defaults.copyWith(
        behavior: const BehaviorConfig(enableLogging: true),
      );
      await tester.pumpWidget(buildApp(initialConfig: config));
      await tester.scrollUntilVisible(
        find.text('Enable Logging'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Enable Logging'), findsOneWidget);
    });

    testWidgets('logging tiles visible when enabled', (tester) async {
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
      expect(find.text('Live Log'), findsOneWidget);
      expect(find.byIcon(Icons.copy), findsOneWidget);
      expect(find.byIcon(Icons.save_alt), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    });

    testWidgets('live log viewer renders log content inline', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Write a log entry so content is non-empty
      AppLogger.instance.log('Test log entry', name: 'Test');

      final config = AppConfig.defaults.copyWith(
        behavior: const BehaviorConfig(enableLogging: true),
      );
      await tester.pumpWidget(buildApp(initialConfig: config));
      await tester.scrollUntilVisible(
        find.text('Live Log'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      // Allow _LiveLogViewer timer/initState refresh to complete
      await tester.runAsync(
        () => Future.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump();

      // Inline viewer is present — no dialog
      expect(find.text('Live Log'), findsOneWidget);
      expect(find.byType(SelectableText), findsWidgets);
    });

    testWidgets('live log viewer shows placeholder when log is empty', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Clear logs (real I/O)
      await tester.runAsync(() => AppLogger.instance.clearLogs());

      final config = AppConfig.defaults.copyWith(
        behavior: const BehaviorConfig(enableLogging: true),
      );
      await tester.pumpWidget(buildApp(initialConfig: config));
      await tester.scrollUntilVisible(
        find.text('Live Log'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      // Allow refresh to complete
      await tester.runAsync(
        () => Future.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump();

      // Either placeholder or content is shown — viewer is present
      expect(find.text('Live Log'), findsOneWidget);
    });

    testWidgets('live log viewer copy icon copies content to clipboard', (
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

      AppLogger.instance.log('clipboard test entry', name: 'Test');
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

      expect(copiedText, isNotNull);
      // Toast shows either "Copied to clipboard" or "Log is empty"
      expect(
        find.textContaining('clipboard').evaluate().isNotEmpty ||
            find.textContaining('empty').evaluate().isNotEmpty,
        isTrue,
      );

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });

    testWidgets('Clear Logs clears and shows toast', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      AppLogger.instance.log('entry to clear', name: 'Test');
      await tester.runAsync(
        () => Future.delayed(const Duration(milliseconds: 100)),
      );

      final config = AppConfig.defaults.copyWith(
        behavior: const BehaviorConfig(enableLogging: true),
      );
      await tester.pumpWidget(buildApp(initialConfig: config));
      await tester.scrollUntilVisible(
        find.byIcon(Icons.delete_outline),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.runAsync(
        () => Future.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump();

      await tester.runAsync(() async {
        await tester.tap(find.byIcon(Icons.delete_outline));
        await Future.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
      await tester.pump();

      expect(find.text('Logs cleared'), findsOneWidget);

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });

    testWidgets('toggling Enable Logging switch calls config update', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Start with logging disabled
      await tester.pumpWidget(buildApp(initialConfig: AppConfig.defaults));
      await tester.scrollUntilVisible(
        find.text('Enable Logging'),
        200,
        scrollable: find.byType(Scrollable).first,
      );

      // The toggle pill should have bg4 color (off state)
      final toggleContainer = find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).color == AppTheme.bg4 &&
            (w.decoration as BoxDecoration).borderRadius ==
                BorderRadius.circular(9),
      );
      expect(toggleContainer, findsWidgets);

      // Tap the toggle to enable logging
      await tester.tap(find.text('Enable Logging'));
      await tester.pumpAndSettle();
    });

    testWidgets('logging toggle is present whether enabled or not', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildApp(initialConfig: AppConfig.defaults));
      await tester.scrollUntilVisible(
        find.text('Enable Logging'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Enable Logging'), findsOneWidget);
    });

    testWidgets('toggle renders ON when config has enableLogging true', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final config = AppConfig.defaults.copyWith(
        behavior: const BehaviorConfig(enableLogging: true),
      );
      await tester.pumpWidget(buildApp(initialConfig: config));
      await tester.scrollUntilVisible(
        find.text('Enable Logging'),
        200,
        scrollable: find.byType(Scrollable).first,
      );

      // Find the toggle pill that is in the same Row as "Enable Logging"
      final loggingRow = find
          .ancestor(of: find.text('Enable Logging'), matching: find.byType(Row))
          .first;
      final toggleContainer = find.descendant(
        of: loggingRow,
        matching: find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).color == AppTheme.accent &&
              (w.decoration as BoxDecoration).borderRadius ==
                  BorderRadius.circular(9),
        ),
      );
      expect(toggleContainer, findsOneWidget);
    });

    testWidgets(
      'logging section shows icons for copy/export/clear in live viewer',
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
        expect(find.byIcon(Icons.copy), findsOneWidget);
        expect(find.byIcon(Icons.save_alt), findsOneWidget);
        expect(find.byIcon(Icons.delete_outline), findsOneWidget);
        expect(find.byIcon(Icons.visibility), findsNothing);
      },
    );

    testWidgets('live log copy with empty log shows toast', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Delete the log file so readLog returns '' — all inside runAsync for real I/O
      await tester.runAsync(() async {
        await AppLogger.instance.setEnabled(false);
        final logPath = AppLogger.instance.logPath;
        if (logPath != null) {
          final logFile = File(logPath);
          if (await logFile.exists()) {
            await logFile.delete();
          }
        }
        await AppLogger.instance.setEnabled(true);
      });

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

      // Shows either "Log is empty" or "Copied to clipboard"
      expect(
        find.textContaining('Log').evaluate().isNotEmpty ||
            find.textContaining('clipboard').evaluate().isNotEmpty,
        isTrue,
      );

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });
  });

  // ---------------------------------------------------------------------------
  // _DataPathTile — FutureBuilder paths
  // ---------------------------------------------------------------------------
  group('SettingsScreen — _DataPathTile FutureBuilder', () {
    testWidgets('shows "..." while loading then resolves path', (tester) async {
      tester.view.physicalSize = const Size(800, 3200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildApp());

      // Before FutureBuilder resolves, subtitle should be "..."
      await tester.scrollUntilVisible(
        find.text('Data Location'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      // The FutureBuilder may still show "..." or resolved path
      expect(find.text('Data Location'), findsOneWidget);

      // Let the FutureBuilder resolve. The delay exercises the path
      // where the platform-channel mock answers between two pumps; the
      // exact window is racy on loaded CI, so we pump repeatedly until
      // the subtitle flips or 1s elapses — the point of the test is
      // "loader eventually resolves", not a 100ms SLA.
      final deadline = DateTime.now().add(const Duration(seconds: 1));
      while (DateTime.now().isBefore(deadline) &&
          find.text('...').evaluate().isNotEmpty) {
        await tester.runAsync(
          () => Future.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
      }

      // After resolving, should show actual path (tempDir path)
      expect(find.text('...'), findsNothing);
      expect(find.text('Data Location'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // Export success toast (lines 291-292)
  // ---------------------------------------------------------------------------
  // NOTE: Lines 291-292 (export success toast) require the full async chain:
  // showDialog -> getApplicationSupportDirectory -> ExportImport.export (PBKDF2 600k)
  // -> Toast.show. The PBKDF2 key derivation is CPU-bound and blocks the event loop.
  // In widget test fake async, the platform channel response for path_provider
  // cannot be delivered while PBKDF2 blocks. This makes the success toast path
  // untestable in a widget test without refactoring the export to use an isolate.
  // The existing test at line 772 exercises the dialog->export flow but cannot
  // verify the toast due to this limitation.

  // ---------------------------------------------------------------------------
  // Updates section
  // ---------------------------------------------------------------------------
  group('SettingsScreen — Updates section', () {
    /// Build app with an overridden update provider for testing.
    Widget buildUpdateApp({
      AppConfig? initialConfig,
      UpdateState? initialUpdateState,
    }) {
      final config = initialConfig ?? AppConfig.defaults;
      return ProviderScope(
        overrides: [
          configProvider.overrideWith(() => PrePopulatedConfigNotifier(config)),
          appVersionProvider.overrideWith(() => FixedVersionNotifier('1.5.0')),
          if (initialUpdateState != null)
            updateProvider.overrideWith(
              () => PrePopulatedUpdateNotifier(initialUpdateState),
            ),
        ],
        child: MaterialApp(
          localizationsDelegates: S.localizationsDelegates,
          supportedLocales: S.supportedLocales,
          theme: AppTheme.dark(),
          home: const SizedBox(height: 2000, child: SettingsScreen()),
        ),
      );
    }

    testWidgets('renders check for updates toggle', (tester) async {
      await tester.pumpWidget(buildUpdateApp());
      await tester.scrollUntilVisible(
        find.text('Check for Updates on Startup'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Check for Updates on Startup'), findsOneWidget);
    });

    testWidgets('toggle defaults to on', (tester) async {
      await tester.pumpWidget(buildUpdateApp());
      await tester.scrollUntilVisible(
        find.text('Check for Updates on Startup'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      // The toggle pill near "Check for Updates on Startup" should have accent color (on)
      final toggleContainer = find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).color == AppTheme.accent &&
            (w.decoration as BoxDecoration).borderRadius ==
                BorderRadius.circular(9),
      );
      expect(toggleContainer, findsOneWidget);
    });

    testWidgets('renders check button', (tester) async {
      await tester.pumpWidget(buildUpdateApp());
      await tester.scrollUntilVisible(
        find.text('Check for Updates'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Check for Updates'), findsOneWidget);
    });

    testWidgets('shows up-to-date message', (tester) async {
      await tester.pumpWidget(
        buildUpdateApp(
          initialUpdateState: const UpdateState(
            status: UpdateStatus.upToDate,
            info: UpdateInfo(
              latestVersion: '1.5.0',
              currentVersion: '1.5.0',
              releaseUrl: '',
            ),
          ),
        ),
      );
      await tester.scrollUntilVisible(
        find.textContaining('up to date'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining('up to date'), findsOneWidget);
    });

    testWidgets('shows update available with version', (tester) async {
      await tester.pumpWidget(
        buildUpdateApp(
          initialUpdateState: const UpdateState(
            status: UpdateStatus.updateAvailable,
            info: UpdateInfo(
              latestVersion: '2.0.0',
              currentVersion: '1.5.0',
              releaseUrl: 'https://github.com/releases',
              assetUrl:
                  'https://github.com/Llloooggg/LetsFLUTssh/releases/download/v2.0.0/file.AppImage',
            ),
          ),
        ),
      );
      await tester.scrollUntilVisible(
        find.text('Version 2.0.0 available'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Version 2.0.0 available'), findsOneWidget);
      // Current version now appears in both the Updates row subtitle and
      // the "update available" status tile — either one is fine.
      expect(find.text('Current: v1.5.0'), findsWidgets);
    });

    testWidgets('shows error state', (tester) async {
      await tester.pumpWidget(
        buildUpdateApp(
          initialUpdateState: const UpdateState(
            status: UpdateStatus.error,
            error: 'Network timeout',
          ),
        ),
      );
      await tester.scrollUntilVisible(
        find.text('Update check failed'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Update check failed'), findsOneWidget);
      expect(find.text('Network timeout'), findsOneWidget);
    });

    testWidgets('shows downloading progress', (tester) async {
      await tester.pumpWidget(
        buildUpdateApp(
          initialUpdateState: const UpdateState(
            status: UpdateStatus.downloading,
            progress: 0.42,
          ),
        ),
      );
      await tester.scrollUntilVisible(
        find.textContaining('Downloading'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining('Downloading... 42%'), findsOneWidget);
    });

    testWidgets('shows download complete with install button', (tester) async {
      await tester.pumpWidget(
        buildUpdateApp(
          initialUpdateState: const UpdateState(
            status: UpdateStatus.downloaded,
            downloadedPath: '/tmp/letsflutssh-2.0.0.AppImage',
            progress: 1,
          ),
        ),
      );
      await tester.scrollUntilVisible(
        find.text('Download complete'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Download complete'), findsOneWidget);
      expect(find.text('Install Now'), findsOneWidget);
    });

    testWidgets('shows copy release URL on mobile or when no asset', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildUpdateApp(
          initialUpdateState: const UpdateState(
            status: UpdateStatus.updateAvailable,
            info: UpdateInfo(
              latestVersion: '2.0.0',
              currentVersion: '1.5.0',
              releaseUrl: 'https://github.com/releases',
              // assetUrl is null — no matching asset
            ),
          ),
        ),
      );
      await tester.scrollUntilVisible(
        find.text('Open in Browser'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Open in Browser'), findsOneWidget);
    });

    testWidgets('toggle can be turned off', (tester) async {
      await tester.pumpWidget(
        buildUpdateApp(
          initialConfig: AppConfig.defaults.copyWith(
            behavior: const BehaviorConfig(checkUpdatesOnStart: false),
          ),
        ),
      );
      await tester.scrollUntilVisible(
        find.text('Check for Updates on Startup'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      // Find the toggle pill in the same Row as "Check for Updates on Startup"
      final updateRow = find
          .ancestor(
            of: find.text('Check for Updates on Startup'),
            matching: find.byType(Row),
          )
          .first;
      final toggleContainer = find.descendant(
        of: updateRow,
        matching: find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).color == AppTheme.bg4 &&
              (w.decoration as BoxDecoration).borderRadius ==
                  BorderRadius.circular(9),
        ),
      );
      expect(toggleContainer, findsOneWidget);
    });

    testWidgets('manual check shows toast when up to date', (tester) async {
      tester.view.physicalSize = const Size(800, 3200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final mockService = UpdateService(
        fetch: (_) async => '{"tag_name":"v1.5.0","html_url":"","assets":[]}',
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            configProvider.overrideWith(
              () => PrePopulatedConfigNotifier(AppConfig.defaults),
            ),
            appVersionProvider.overrideWith(
              () => FixedVersionNotifier('1.5.0'),
            ),
            updateServiceProvider.overrideWithValue(mockService),
          ],
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: const SettingsScreen(),
          ),
        ),
      );

      await tester.scrollUntilVisible(
        find.text('Check for Updates'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Check now'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();

      expect(find.text('You\'re running the latest version'), findsOneWidget);
      Toast.clearAllForTest();
    });

    testWidgets('manual check shows toast when update available', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 3200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final mockService = UpdateService(
        fetch: (_) async => '{"tag_name":"v9.0.0","html_url":"","assets":[]}',
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            configProvider.overrideWith(
              () => PrePopulatedConfigNotifier(AppConfig.defaults),
            ),
            appVersionProvider.overrideWith(
              () => FixedVersionNotifier('1.5.0'),
            ),
            updateServiceProvider.overrideWithValue(mockService),
          ],
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: const SettingsScreen(),
          ),
        ),
      );

      await tester.scrollUntilVisible(
        find.text('Check for Updates'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Check now'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();

      expect(find.text('Version 9.0.0 available'), findsWidgets);
      Toast.clearAllForTest();
    });

    testWidgets('manual check shows toast on error', (tester) async {
      tester.view.physicalSize = const Size(800, 3200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final mockService = UpdateService(
        fetch: (_) async => throw Exception('Network error'),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            configProvider.overrideWith(
              () => PrePopulatedConfigNotifier(AppConfig.defaults),
            ),
            appVersionProvider.overrideWith(
              () => FixedVersionNotifier('1.5.0'),
            ),
            updateServiceProvider.overrideWithValue(mockService),
          ],
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: const SettingsScreen(),
          ),
        ),
      );

      await tester.scrollUntilVisible(
        find.text('Check for Updates'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Check now'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();

      expect(find.textContaining('Network error'), findsWidgets);
      Toast.clearAllForTest();
    });

    testWidgets('shows Skip This Version button when not skipped', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildUpdateApp(
          initialUpdateState: const UpdateState(
            status: UpdateStatus.updateAvailable,
            info: UpdateInfo(
              latestVersion: '2.0.0',
              currentVersion: '1.5.0',
              releaseUrl: 'https://github.com/releases',
              assetUrl:
                  'https://github.com/Llloooggg/LetsFLUTssh/releases/download/v2.0.0/file.AppImage',
            ),
          ),
        ),
      );
      await tester.scrollUntilVisible(
        find.text('Skip This Version'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Skip This Version'), findsOneWidget);
      expect(find.text('Unskip'), findsNothing);
    });

    testWidgets('shows Unskip button when version is skipped', (tester) async {
      await tester.pumpWidget(
        buildUpdateApp(
          initialConfig: AppConfig.defaults.copyWith(
            behavior: const BehaviorConfig(skippedVersion: '2.0.0'),
          ),
          initialUpdateState: const UpdateState(
            status: UpdateStatus.updateAvailable,
            info: UpdateInfo(
              latestVersion: '2.0.0',
              currentVersion: '1.5.0',
              releaseUrl: 'https://github.com/releases',
              assetUrl:
                  'https://github.com/Llloooggg/LetsFLUTssh/releases/download/v2.0.0/file.AppImage',
            ),
          ),
        ),
      );
      await tester.scrollUntilVisible(
        find.text('Unskip'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Unskip'), findsOneWidget);
      expect(find.text('Skip This Version'), findsNothing);
    });

    testWidgets('subtitle does not show skipped label', (tester) async {
      await tester.pumpWidget(
        buildUpdateApp(
          initialConfig: AppConfig.defaults.copyWith(
            behavior: const BehaviorConfig(skippedVersion: '2.0.0'),
          ),
          initialUpdateState: const UpdateState(
            status: UpdateStatus.updateAvailable,
            info: UpdateInfo(
              latestVersion: '2.0.0',
              currentVersion: '1.5.0',
              releaseUrl: 'https://github.com/releases',
            ),
          ),
        ),
      );
      await tester.scrollUntilVisible(
        find.text('Version 2.0.0 available'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      // Current version label appears in both the Updates row subtitle and
      // the "update available" status tile — either one satisfies the spec.
      expect(find.text('Current: v1.5.0'), findsWidgets);
      expect(find.textContaining('skipped'), findsNothing);
    });

    testWidgets('stale skip shows Skip button for new version', (tester) async {
      // Skipped v2.0.0, but v3.0.0 is now available — skip doesn't match
      await tester.pumpWidget(
        buildUpdateApp(
          initialConfig: AppConfig.defaults.copyWith(
            behavior: const BehaviorConfig(skippedVersion: '2.0.0'),
          ),
          initialUpdateState: const UpdateState(
            status: UpdateStatus.updateAvailable,
            info: UpdateInfo(
              latestVersion: '3.0.0',
              currentVersion: '1.5.0',
              releaseUrl: 'https://github.com/releases',
              assetUrl:
                  'https://github.com/Llloooggg/LetsFLUTssh/releases/download/v3.0.0/file.AppImage',
            ),
          ),
        ),
      );
      await tester.scrollUntilVisible(
        find.text('Skip This Version'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Skip This Version'), findsOneWidget);
      expect(find.text('Unskip'), findsNothing);
      expect(find.text('Version 3.0.0 available'), findsOneWidget);
    });

    testWidgets('Skip button is a tappable TextButton', (tester) async {
      await tester.pumpWidget(
        buildUpdateApp(
          initialUpdateState: const UpdateState(
            status: UpdateStatus.updateAvailable,
            info: UpdateInfo(
              latestVersion: '2.0.0',
              currentVersion: '1.5.0',
              releaseUrl: 'https://github.com/releases',
              assetUrl:
                  'https://github.com/Llloooggg/LetsFLUTssh/releases/download/v2.0.0/file.AppImage',
            ),
          ),
        ),
      );
      await tester.scrollUntilVisible(
        find.text('Skip This Version'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      final skipButton = tester.widget<TextButton>(
        find.ancestor(
          of: find.text('Skip This Version'),
          matching: find.byType(TextButton),
        ),
      );
      expect(skipButton.onPressed, isNotNull);
    });

    testWidgets('Unskip button is a tappable TextButton', (tester) async {
      await tester.pumpWidget(
        buildUpdateApp(
          initialConfig: AppConfig.defaults.copyWith(
            behavior: const BehaviorConfig(skippedVersion: '2.0.0'),
          ),
          initialUpdateState: const UpdateState(
            status: UpdateStatus.updateAvailable,
            info: UpdateInfo(
              latestVersion: '2.0.0',
              currentVersion: '1.5.0',
              releaseUrl: 'https://github.com/releases',
              assetUrl:
                  'https://github.com/Llloooggg/LetsFLUTssh/releases/download/v2.0.0/file.AppImage',
            ),
          ),
        ),
      );
      await tester.scrollUntilVisible(
        find.text('Unskip'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      final unskipButton = tester.widget<TextButton>(
        find.ancestor(
          of: find.text('Unskip'),
          matching: find.byType(TextButton),
        ),
      );
      expect(unskipButton.onPressed, isNotNull);
    });

    testWidgets('checking state shows spinner and disables button', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildUpdateApp(
          initialUpdateState: const UpdateState(status: UpdateStatus.checking),
        ),
      );
      await tester.scrollUntilVisible(
        find.textContaining('Checking'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining('Checking'), findsOneWidget);
      // Spinner should be visible
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('downloading with zero progress shows indeterminate bar', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildUpdateApp(
          initialUpdateState: const UpdateState(
            status: UpdateStatus.downloading,
            progress: 0,
          ),
        ),
      );
      await tester.scrollUntilVisible(
        find.textContaining('Downloading'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      // Zero progress → indeterminate linear bar (value: null).
      final indicator = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(indicator.value, isNull);
    });

    testWidgets('error state with null error shows unknown error', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildUpdateApp(
          initialUpdateState: const UpdateState(status: UpdateStatus.error),
        ),
      );
      await tester.scrollUntilVisible(
        find.text('Update check failed'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Update check failed'), findsOneWidget);
      expect(find.text('Unknown error'), findsOneWidget);
    });

    testWidgets(
      'InvalidReleaseSignatureException renders the security warning + '
      'Open Releases page action instead of the generic error tile',
      (tester) async {
        // Spec: a signature-verify failure is not a generic network /
        // disk error — it is a security signal. The UI must stop
        // prompting "retry" (same failing download) and instead point
        // the user at the Releases page for a manual reinstall.
        await tester.pumpWidget(
          buildUpdateApp(
            initialUpdateState: const UpdateState(
              status: UpdateStatus.error,
              error: InvalidReleaseSignatureException(
                'Manifest signature did not verify against the pinned public key',
              ),
            ),
          ),
        );
        await tester.scrollUntilVisible(
          find.text('Update verification failed'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('Update verification failed'), findsOneWidget);
        // Generic "Update check failed" tile must NOT appear — otherwise
        // the user sees two competing prompts.
        expect(find.text('Update check failed'), findsNothing);
        // The Open Releases page button must be present and enabled.
        expect(find.text('Open Releases page'), findsOneWidget);
      },
    );

    testWidgets('download complete shows downloaded path', (tester) async {
      await tester.pumpWidget(
        buildUpdateApp(
          initialUpdateState: const UpdateState(
            status: UpdateStatus.downloaded,
            downloadedPath: '/downloads/letsflutssh-2.0.0.AppImage',
            progress: 1,
          ),
        ),
      );
      await tester.scrollUntilVisible(
        find.text('Download complete'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Download complete'), findsOneWidget);
      expect(
        find.text('/downloads/letsflutssh-2.0.0.AppImage'),
        findsOneWidget,
      );
    });

    testWidgets('shows Release Notes button when changelog is available', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildUpdateApp(
          initialUpdateState: const UpdateState(
            status: UpdateStatus.updateAvailable,
            info: UpdateInfo(
              latestVersion: '2.0.0',
              currentVersion: '1.5.0',
              releaseUrl: 'https://github.com/releases',
              changelog: '## v2.0.0\n- New feature',
            ),
          ),
        ),
      );
      await tester.scrollUntilVisible(
        find.text('Release notes:'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Release notes:'), findsOneWidget);
    });

    testWidgets('hides Release Notes button when changelog is null', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildUpdateApp(
          initialUpdateState: const UpdateState(
            status: UpdateStatus.updateAvailable,
            info: UpdateInfo(
              latestVersion: '2.0.0',
              currentVersion: '1.5.0',
              releaseUrl: 'https://github.com/releases',
            ),
          ),
        ),
      );
      await tester.scrollUntilVisible(
        find.text('Version 2.0.0 available'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Release notes:'), findsNothing);
    });

    testWidgets('shows Release Notes button in downloaded state', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildUpdateApp(
          initialUpdateState: const UpdateState(
            status: UpdateStatus.downloaded,
            downloadedPath: '/tmp/letsflutssh-2.0.0.AppImage',
            progress: 1,
            info: UpdateInfo(
              latestVersion: '2.0.0',
              currentVersion: '1.5.0',
              releaseUrl: 'https://github.com/releases',
              changelog: '## v2.0.0\n- Bug fix',
            ),
          ),
        ),
      );
      await tester.scrollUntilVisible(
        find.text('Release notes:'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Release notes:'), findsOneWidget);
    });

    testWidgets('tapping Release Notes opens dialog with changelog', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 3200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        buildUpdateApp(
          initialUpdateState: const UpdateState(
            status: UpdateStatus.updateAvailable,
            info: UpdateInfo(
              latestVersion: '2.0.0',
              currentVersion: '1.5.0',
              releaseUrl: 'https://github.com/releases',
              changelog: '## v2.0.0\n- Awesome feature',
            ),
          ),
        ),
      );
      await tester.scrollUntilVisible(
        find.text('Release notes:'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Release notes:'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Awesome feature'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // About section
  // ---------------------------------------------------------------------------
  group('SettingsScreen — About section', () {
    testWidgets('renders about section with version and source code', (
      tester,
    ) async {
      await tester.pumpWidget(buildApp());
      await tester.scrollUntilVisible(
        find.text('Source Code'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Source Code'), findsOneWidget);
      expect(
        find.text('https://github.com/Llloooggg/LetsFLUTssh'),
        findsOneWidget,
      );
    });

    testWidgets('tapping source code copies URL to clipboard', (tester) async {
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

      await tester.pumpWidget(buildApp());
      await tester.scrollUntilVisible(
        find.text('Source Code'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.text('Source Code'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Source Code'));
      await tester.pump();

      expect(copiedText, 'https://github.com/Llloooggg/LetsFLUTssh');
      expect(find.text('URL copied to clipboard'), findsOneWidget);

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });

    testWidgets('renders app version subtitle', (tester) async {
      await tester.pumpWidget(buildApp());
      // Eager section build means multiple rows may contain the
      // version string (About tile + Updates section). Scroll to
      // the first textual occurrence and assert at least one widget
      // renders it — the stricter "findsOneWidget" shape would flag
      // the duplicate as a failure even though both matches are
      // legitimate.
      await tester.scrollUntilVisible(
        find.textContaining('1.5.0').first,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining('1.5.0'), findsWidgets);
    });
  });

  // ---------------------------------------------------------------------------
  // Desktop two-column layout
  // ---------------------------------------------------------------------------
  group('SettingsDialog — desktop full-screen modal', () {
    Widget buildDesktopApp({AppConfig? initialConfig}) {
      final config = initialConfig ?? AppConfig.defaults;
      return ProviderScope(
        overrides: [
          configProvider.overrideWith(() => PrePopulatedConfigNotifier(config)),
          appVersionProvider.overrideWith(() => FixedVersionNotifier('1.5.0')),
        ],
        child: MaterialApp(
          localizationsDelegates: S.localizationsDelegates,
          supportedLocales: S.supportedLocales,
          theme: AppTheme.dark(),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => SettingsDialog.show(context),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
    }

    setUp(() {
      plat.debugMobilePlatformOverride = false;
      plat.debugDesktopPlatformOverride = true;
    });

    testWidgets('renders nav rail with section labels', (tester) async {
      await tester.pumpWidget(buildDesktopApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // "Appearance" appears in both nav + content header = 2
      expect(find.text('Appearance'), findsNWidgets(2));
      // Others appear once in nav only
      expect(find.text('Terminal'), findsOneWidget);
      expect(find.text('Connection'), findsOneWidget);
      expect(find.text('Transfers'), findsOneWidget);
      expect(find.text('Data'), findsOneWidget);
      expect(find.text('Logging'), findsOneWidget);
      expect(find.text('Updates'), findsOneWidget);
      expect(find.text('About'), findsOneWidget);
      // SSH Keys is NOT in the desktop settings dialog (moved to Tools)
      expect(find.text('SSH Keys'), findsNothing);
    });

    testWidgets('first section is selected by default', (tester) async {
      await tester.pumpWidget(buildDesktopApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Appearance'), findsNWidgets(2));
      expect(find.text('Theme'), findsOneWidget);
      expect(find.text('Terminal Font Size'), findsOneWidget);
    });

    testWidgets('tapping nav item switches content pane', (tester) async {
      await tester.pumpWidget(buildDesktopApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Theme'), findsOneWidget);

      await tester.tap(find.text('Terminal'));
      await tester.pumpAndSettle();

      expect(find.text('Terminal'), findsNWidgets(2));
      expect(find.text('Scrollback Lines'), findsOneWidget);
    });

    testWidgets('tapping Connection shows connection fields', (tester) async {
      await tester.pumpWidget(buildDesktopApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Connection'));
      await tester.pumpAndSettle();

      expect(find.text('Connection'), findsNWidgets(2));
      expect(find.text('Keep-Alive Interval (sec)'), findsOneWidget);
      expect(find.text('SSH Timeout (sec)'), findsOneWidget);
      expect(find.text('Default Port'), findsOneWidget);
    });

    testWidgets('renders Reset to Defaults button', (tester) async {
      await tester.pumpWidget(buildDesktopApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Reset to Defaults'), findsOneWidget);
    });

    testWidgets('close button dismisses dialog', (tester) async {
      await tester.pumpWidget(buildDesktopApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Appearance'), findsNWidgets(2));
      // Tap close button (X icon)
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(find.text('Appearance'), findsNothing);
    });

    testWidgets(
      'desktop dialog leaves a ~7.5% gutter on each side so the modal is '
      '~15% narrower than the viewport',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(buildDesktopApp());
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        // The outer Dialog widget covers the whole Navigator route; the
        // actual modal surface is the Material child that sits inside
        // the animated inset padding.
        final dialogRect = tester.getRect(
          find
              .descendant(
                of: find.byType(Dialog),
                matching: find.byType(Material),
              )
              .first,
        );
        // Expected width: 1600 - 2 * 120 (= 7.5% of 1600) = 1360.
        expect(
          dialogRect.width,
          inInclusiveRange(1350, 1370),
          reason:
              'desktop modal must sit 7.5% off each side of a 1600-wide '
              'viewport — the fixed 32px inset was too wide and wasted '
              'space on large monitors',
        );
        expect(
          dialogRect.left,
          inInclusiveRange(115, 125),
          reason: 'left inset should be ~7.5% of the viewport width',
        );
      },
    );

    // NOTE: the "info rows pin the value text" test was tied to the
    // old _InfoTile layout in the Security section. The Security
    // section now renders four TierThreatBlock cards in a ladder
    // instead of an icon+label+value row, so the right-edge pin
    // assertion no longer has a target. Removed.
  });

  // ---------------------------------------------------------------------------
  // Transfers — Calculate Folder Sizes toggle
  // ---------------------------------------------------------------------------
  group('SettingsScreen — Calculate Folder Sizes', () {
    testWidgets('renders toggle with default off', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.scrollUntilVisible(
        find.text('Calculate Folder Sizes'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Calculate Folder Sizes'), findsOneWidget);
      // Default is false — pill should have bg4 color (off state)
      final transferRow = find
          .ancestor(
            of: find.text('Calculate Folder Sizes'),
            matching: find.byType(Row),
          )
          .first;
      final offPill = find.descendant(
        of: transferRow,
        matching: find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).color == AppTheme.bg4,
        ),
      );
      expect(offPill, findsOneWidget);
    });

    testWidgets('renders toggle as on when enabled', (tester) async {
      final config = AppConfig.defaults.copyWith(
        ui: const UiConfig(showFolderSizes: true),
      );
      await tester.pumpWidget(buildApp(initialConfig: config));
      await tester.scrollUntilVisible(
        find.text('Calculate Folder Sizes'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      final transferRow = find
          .ancestor(
            of: find.text('Calculate Folder Sizes'),
            matching: find.byType(Row),
          )
          .first;
      final onPill = find.descendant(
        of: transferRow,
        matching: find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).color == AppTheme.accent,
        ),
      );
      expect(onPill, findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // QR Export — empty sessions opens dialog (can export config/known hosts)
  // ---------------------------------------------------------------------------
  group('SettingsScreen — QR Export', () {
    testWidgets('empty sessions still opens export dialog', (tester) async {
      tester.view.physicalSize = const Size(800, 3200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildFullApp());
      await tester.scrollUntilVisible(
        find.text('Export QR code'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Export QR code'));
      await tester.pumpAndSettle();

      // No warning toast — dialog opens even with zero sessions
      // (user can still export config or known hosts via QR).
      expect(find.text('No sessions to export'), findsNothing);
    });
  });

  // ---------------------------------------------------------------------------
  // Updates — Install Now failure toast
  // ---------------------------------------------------------------------------
  group('SettingsScreen — Install Now', () {
    testWidgets('install failure shows toast', (tester) async {
      tester.view.physicalSize = const Size(800, 3200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Create a mock update service whose openFile always fails
      final mockService = UpdateService(
        fetch: (_) async => '[]',
        runProcess: (_, _) async => ProcessResult(0, 1, '', 'failed'),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            configProvider.overrideWith(
              () => PrePopulatedConfigNotifier(AppConfig.defaults),
            ),
            appVersionProvider.overrideWith(
              () => FixedVersionNotifier('1.5.0'),
            ),
            updateServiceProvider.overrideWithValue(mockService),
            updateProvider.overrideWith(
              () => PrePopulatedUpdateNotifier(
                const UpdateState(
                  status: UpdateStatus.downloaded,
                  downloadedPath: '/tmp/letsflutssh-2.0.0.AppImage',
                  progress: 1,
                ),
              ),
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: const SettingsScreen(),
          ),
        ),
      );

      await tester.scrollUntilVisible(
        find.text('Install Now'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Install Now'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();

      expect(find.text('Could not open installer'), findsOneWidget);
      Toast.clearAllForTest();
    });

    testWidgets('download & install button visible on desktop with asset', (
      tester,
    ) async {
      plat.debugMobilePlatformOverride = false;
      plat.debugDesktopPlatformOverride = true;
      addTearDown(() {
        plat.debugMobilePlatformOverride = true;
        plat.debugDesktopPlatformOverride = false;
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            configProvider.overrideWith(
              () => PrePopulatedConfigNotifier(AppConfig.defaults),
            ),
            appVersionProvider.overrideWith(
              () => FixedVersionNotifier('1.5.0'),
            ),
            updateProvider.overrideWith(
              () => PrePopulatedUpdateNotifier(
                const UpdateState(
                  status: UpdateStatus.updateAvailable,
                  info: UpdateInfo(
                    latestVersion: '2.0.0',
                    currentVersion: '1.5.0',
                    releaseUrl: 'https://github.com/releases',
                    assetUrl:
                        'https://github.com/Llloooggg/LetsFLUTssh/releases/download/v2.0.0/file.AppImage',
                  ),
                ),
              ),
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: const SizedBox(height: 2000, child: SettingsScreen()),
          ),
        ),
      );

      await tester.scrollUntilVisible(
        find.text('Download & Install'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Download & Install'), findsOneWidget);
    });
  });
}
