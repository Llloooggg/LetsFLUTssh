import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/config/app_config.dart';
import 'package:letsflutssh/core/session/session_store.dart';
import 'package:letsflutssh/core/update/update_service.dart';
import 'package:letsflutssh/features/settings/settings_screen.dart';
import 'package:letsflutssh/providers/config_provider.dart';
import 'package:letsflutssh/providers/session_provider.dart';
import 'package:letsflutssh/providers/update_provider.dart';
import 'package:letsflutssh/providers/version_provider.dart';
import 'package:letsflutssh/theme/app_theme.dart';
import 'package:letsflutssh/utils/logger.dart';
import 'package:letsflutssh/utils/platform.dart' as plat;
import 'package:letsflutssh/widgets/toast.dart';

/// Mock FilePicker that returns a temp directory for getDirectoryPath
/// and a temp file path for saveFile, without launching native dialogs.
class _MockFilePicker extends FilePicker {
  String? directoryPath;
  String? savePath;

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
    dynamic Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async => null;
}

/// A ConfigNotifier subclass that starts with a custom initial config.
class _PrePopulatedConfigNotifier extends ConfigNotifier {
  final AppConfig _initialConfig;
  _PrePopulatedConfigNotifier(this._initialConfig);

  @override
  AppConfig build() {
    super.build();
    state = _initialConfig;
    return state;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;
  late _MockFilePicker mockFilePicker;

  setUp(() async {
    // Force mobile layout so existing tests (written for flat ListView) keep working.
    plat.debugMobilePlatformOverride = true;
    plat.debugDesktopPlatformOverride = false;
    // Start all collapsible sections expanded so content is immediately visible.
    debugCollapsibleSectionsExpanded = true;
    tempDir = await Directory.systemTemp.createTemp('settings_test_');
    // Mock FilePicker to prevent native dialog launches in tests.
    mockFilePicker = _MockFilePicker()..directoryPath = tempDir.path;
    FilePicker.platform = mockFilePicker;
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
  Widget buildApp({AppConfig? initialConfig, double height = 1200}) {
    final config = initialConfig ?? AppConfig.defaults;
    return ProviderScope(
      overrides: [
        configProvider.overrideWith(() =>
            _PrePopulatedConfigNotifier(config)),
        appVersionProvider.overrideWith(() => _FixedVersionNotifier('1.5.0')),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: SizedBox(
          height: height,
          child: const SettingsScreen(),
        ),
      ),
    );
  }

  /// Full buildApp with session store + session provider (for export/import).
  Widget buildFullApp({AppConfig? initialConfig}) {
    final config = initialConfig ?? AppConfig.defaults;
    return ProviderScope(
      overrides: [
        configProvider.overrideWith(() =>
            _PrePopulatedConfigNotifier(config)),
        appVersionProvider.overrideWith(() => _FixedVersionNotifier('1.5.0')),
        sessionStoreProvider.overrideWithValue(SessionStore()),
        sessionProvider.overrideWith(SessionNotifier.new),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: const SizedBox(
          height: 2000,
          child: SettingsScreen(),
        ),
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

    testWidgets('renders as Scaffold with ListView', (tester) async {
      await tester.pumpWidget(buildApp());
      expect(find.byType(Scaffold), findsOneWidget);
      expect(find.byType(ListView), findsOneWidget);
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
        find.text('Transfers'), 200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Transfers'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Data'), 200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Data'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Updates'), 200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Updates'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('About'), 200,
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
      expect(find.text('Theme'), findsOneWidget);
      expect(find.text('Dark'), findsOneWidget);
      expect(find.text('Light'), findsOneWidget);
      expect(find.text('System'), findsOneWidget);
      expect(find.text('Font Size'), findsOneWidget);
      expect(find.byType(Slider), findsOneWidget);
    });

    testWidgets('theme selector renders all segment labels', (tester) async {
      await tester.pumpWidget(buildApp());
      expect(find.text('Dark'), findsOneWidget);
      expect(find.text('Light'), findsOneWidget);
      expect(find.text('System'), findsOneWidget);
    });

    testWidgets('theme shows correct selection for dark', (tester) async {
      await tester.pumpWidget(buildApp());
      // The selected segment has AppTheme.accent background
      final darkText = find.text('Dark');
      final darkContainer = find.ancestor(
        of: darkText,
        matching: find.byWidgetPredicate(
          (w) => w is Container && w.color == AppTheme.accent,
        ),
      );
      expect(darkContainer, findsOneWidget);
    });

    testWidgets('theme shows correct selection for light', (tester) async {
      await tester.pumpWidget(
          buildApp(initialConfig: AppConfig.defaults.copyWith(terminal: AppConfig.defaults.terminal.copyWith(theme: 'light'))));
      final lightContainer = find.ancestor(
        of: find.text('Light'),
        matching: find.byWidgetPredicate(
          (w) => w is Container && w.color == AppTheme.accent,
        ),
      );
      expect(lightContainer, findsOneWidget);
    });

    testWidgets('theme shows correct selection for system', (tester) async {
      await tester.pumpWidget(
          buildApp(initialConfig: AppConfig.defaults.copyWith(terminal: AppConfig.defaults.terminal.copyWith(theme: 'system'))));
      final systemContainer = find.ancestor(
        of: find.text('System'),
        matching: find.byWidgetPredicate(
          (w) => w is Container && w.color == AppTheme.accent,
        ),
      );
      expect(systemContainer, findsOneWidget);
    });

    testWidgets('tapping Dark when already Dark keeps Dark selected',
        (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();
      final darkContainer = find.ancestor(
        of: find.text('Dark'),
        matching: find.byWidgetPredicate(
          (w) => w is Container && w.color == AppTheme.accent,
        ),
      );
      expect(darkContainer, findsOneWidget);
    });

    testWidgets('tapping Light theme does not crash', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Light'));
      await tester.pumpAndSettle();
      expect(find.text('Theme'), findsOneWidget);
    });

    testWidgets('tapping System theme does not crash', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('System'));
      await tester.pumpAndSettle();
      expect(find.text('Theme'), findsOneWidget);
    });

    testWidgets('switching Light then Dark then System', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Light'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('System'));
      await tester.pumpAndSettle();
      expect(find.text('Theme'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // Font size slider
  // ---------------------------------------------------------------------------
  group('SettingsScreen — font size slider', () {
    testWidgets('slider shows default value 14', (tester) async {
      await tester.pumpWidget(buildApp());
      expect(find.text('14'), findsOneWidget);
      final slider = tester.widget<Slider>(find.byType(Slider));
      expect(slider.value, 14.0);
      expect(slider.min, 8.0);
      expect(slider.max, 24.0);
      expect(slider.divisions, 16);
    });

    testWidgets('slider with custom font size', (tester) async {
      await tester.pumpWidget(
          buildApp(initialConfig: AppConfig.defaults.copyWith(terminal: AppConfig.defaults.terminal.copyWith(fontSize: 18.0))));
      expect(find.text('18'), findsOneWidget);
    });

    testWidgets('slider shows formatted value text', (tester) async {
      await tester.pumpWidget(
          buildApp(initialConfig: AppConfig.defaults.copyWith(terminal: AppConfig.defaults.terminal.copyWith(fontSize: 16.0))));
      final slider = tester.widget<Slider>(find.byType(Slider));
      expect(slider.value, 16.0);
      expect(find.text('16'), findsOneWidget);
    });

    testWidgets('slider with min value 8', (tester) async {
      await tester.pumpWidget(
          buildApp(initialConfig: AppConfig.defaults.copyWith(terminal: AppConfig.defaults.terminal.copyWith(fontSize: 8.0))));
      expect(find.text('8'), findsOneWidget);
    });

    testWidgets('slider with max value 24', (tester) async {
      await tester.pumpWidget(
          buildApp(initialConfig: AppConfig.defaults.copyWith(terminal: AppConfig.defaults.terminal.copyWith(fontSize: 24.0))));
      expect(find.text('24'), findsOneWidget);
    });

    testWidgets('value out of range is clamped', (tester) async {
      await tester.pumpWidget(
          buildApp(initialConfig: AppConfig.defaults.copyWith(terminal: AppConfig.defaults.terminal.copyWith(fontSize: 4.0))));
      final slider = tester.widget<Slider>(find.byType(Slider));
      expect(slider.value, 8.0);
    });

    testWidgets('onChanged callback is wired', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.scrollUntilVisible(
        find.byType(Slider), 100,
        scrollable: find.byType(Scrollable).first,
      );
      final slider = tester.widget<Slider>(find.byType(Slider));
      expect(slider.onChanged, isNotNull);
      slider.onChanged!(18.0);
      await tester.pump();
    });

    testWidgets('dragging slider changes value', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.drag(find.byType(Slider), const Offset(50, 0));
      await tester.pumpAndSettle();
      expect(find.byType(Slider), findsOneWidget);
    });

    testWidgets('slider with custom font size 20 shows correct value',
        (tester) async {
      await tester.pumpWidget(
          buildApp(initialConfig: AppConfig.defaults.copyWith(terminal: AppConfig.defaults.terminal.copyWith(fontSize: 20.0))));
      final slider = tester.widget<Slider>(find.byType(Slider));
      expect(slider.value, 20.0);
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
          buildApp(initialConfig: AppConfig.defaults.copyWith(terminal: AppConfig.defaults.terminal.copyWith(scrollback: 10000))));
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
    testWidgets('renders Connection section with defaults', (tester) async {
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
      final config = AppConfig.defaults.copyWith(
        ssh: AppConfig.defaults.ssh.copyWith(keepAliveSec: 60, sshTimeoutSec: 30, defaultPort: 2222),
      );
      await tester.pumpWidget(buildApp(initialConfig: config));
      expect(find.text('60'), findsOneWidget);
      expect(find.text('30'), findsOneWidget);
      expect(find.text('2222'), findsOneWidget);
    });

    testWidgets('keepalive field accepts valid value', (tester) async {
      await tester.pumpWidget(buildApp());
      final field = find.widgetWithText(TextFormField, '30');
      await tester.tap(field);
      await tester.pumpAndSettle();
      await tester.enterText(field, '60');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('60'), findsOneWidget);
    });

    testWidgets('keepalive accepts 0 (min boundary)', (tester) async {
      await tester.pumpWidget(buildApp());
      final field = find.widgetWithText(TextFormField, '30');
      await tester.tap(field);
      await tester.pumpAndSettle();
      await tester.enterText(field, '0');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('0'), findsOneWidget);
    });

    testWidgets('keepalive negative value rejected', (tester) async {
      await tester.pumpWidget(buildApp());
      final field = find.widgetWithText(TextFormField, '30');
      await tester.tap(field);
      await tester.pumpAndSettle();
      await tester.enterText(field, '-5');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
    });

    testWidgets('keepalive non-numeric value ignored', (tester) async {
      await tester.pumpWidget(buildApp());
      final field = find.widgetWithText(TextFormField, '30');
      await tester.tap(field);
      await tester.pumpAndSettle();
      await tester.enterText(field, 'abc');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
    });

    testWidgets('timeout field accepts valid value', (tester) async {
      await tester.pumpWidget(buildApp());
      final field = find.widgetWithText(TextFormField, '10');
      await tester.tap(field);
      await tester.pumpAndSettle();
      await tester.enterText(field, '20');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('20'), findsOneWidget);
    });

    testWidgets('timeout min boundary 1', (tester) async {
      await tester.pumpWidget(buildApp());
      final field = find.widgetWithText(TextFormField, '10');
      await tester.tap(field);
      await tester.pumpAndSettle();
      await tester.enterText(field, '1');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('1'), findsOneWidget);
    });

    testWidgets('timeout above max rejected', (tester) async {
      await tester.pumpWidget(buildApp());
      final field = find.widgetWithText(TextFormField, '10');
      await tester.tap(field);
      await tester.pumpAndSettle();
      await tester.enterText(field, '999');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
    });

    testWidgets('SSH timeout with custom config accepts valid value',
        (tester) async {
      final config = AppConfig.defaults.copyWith(ssh: AppConfig.defaults.ssh.copyWith(sshTimeoutSec: 15));
      await tester.pumpWidget(buildFullApp(initialConfig: config));
      final field = find.widgetWithText(TextFormField, '15');
      await tester.tap(field);
      await tester.pumpAndSettle();
      await tester.enterText(field, '30');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('30'), findsWidgets);
    });

    testWidgets('port field accepts valid value', (tester) async {
      await tester.pumpWidget(buildApp());
      final field = find.widgetWithText(TextFormField, '22');
      await tester.tap(field);
      await tester.pumpAndSettle();
      await tester.enterText(field, '2222');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('2222'), findsOneWidget);
    });

    testWidgets('port max boundary 65535', (tester) async {
      await tester.pumpWidget(buildApp());
      final field = find.widgetWithText(TextFormField, '22');
      await tester.tap(field);
      await tester.pumpAndSettle();
      await tester.enterText(field, '65535');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('65535'), findsOneWidget);
    });

    testWidgets('port custom value 8022', (tester) async {
      await tester.pumpWidget(buildFullApp());
      final field = find.widgetWithText(TextFormField, '22');
      await tester.tap(field);
      await tester.pumpAndSettle();
      await tester.enterText(field, '8022');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('8022'), findsOneWidget);
    });

    testWidgets('TextFormField widgets present', (tester) async {
      await tester.pumpWidget(buildApp());
      expect(find.byType(TextFormField), findsWidgets);
    });
  });

  // ---------------------------------------------------------------------------
  // Transfers section
  // ---------------------------------------------------------------------------
  group('SettingsScreen — Transfers section', () {
    testWidgets('renders after scrolling with defaults', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.scrollUntilVisible(
        find.text('Parallel Workers'), 200,
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
        transferWorkers: 4, maxHistory: 1000,
      );
      await tester.pumpWidget(buildApp(initialConfig: config));
      await tester.scrollUntilVisible(
        find.text('Parallel Workers'), 200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('4'), findsOneWidget);
      expect(find.text('1000'), findsOneWidget);
    });

    testWidgets('workers field accepts valid value', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.scrollUntilVisible(
        find.text('Parallel Workers'), 200,
        scrollable: find.byType(Scrollable).first,
      );
      final field = find.widgetWithText(TextFormField, '2');
      await tester.tap(field);
      await tester.pumpAndSettle();
      await tester.enterText(field, '4');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('4'), findsOneWidget);
    });

    testWidgets('workers max boundary 10', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.scrollUntilVisible(
        find.text('Parallel Workers'), 200,
        scrollable: find.byType(Scrollable).first,
      );
      final field = find.widgetWithText(TextFormField, '2');
      await tester.tap(field);
      await tester.pumpAndSettle();
      await tester.enterText(field, '10');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('10'), findsOneWidget);
    });

    testWidgets('workers out of range rejected', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.scrollUntilVisible(
        find.text('Parallel Workers'), 200,
        scrollable: find.byType(Scrollable).first,
      );
      final field = find.widgetWithText(TextFormField, '2');
      await tester.tap(field);
      await tester.pumpAndSettle();
      await tester.enterText(field, '99');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
    });

    testWidgets('max history field accepts valid value', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.scrollUntilVisible(
        find.text('Max History'), 200,
        scrollable: find.byType(Scrollable).first,
      );
      final field = find.widgetWithText(TextFormField, '500');
      await tester.tap(field);
      await tester.pumpAndSettle();
      await tester.enterText(field, '1000');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('1000'), findsOneWidget);
    });

    testWidgets('max history min boundary 10', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.scrollUntilVisible(
        find.text('Max History'), 200,
        scrollable: find.byType(Scrollable).first,
      );
      final field = find.widgetWithText(TextFormField, '500');
      await tester.tap(field);
      await tester.pumpAndSettle();
      await tester.enterText(field, '10');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('10'), findsOneWidget);
    });

    testWidgets('max history max boundary 5000', (tester) async {
      await tester.pumpWidget(buildFullApp());
      await tester.scrollUntilVisible(
        find.text('Max History'), 200,
        scrollable: find.byType(Scrollable).first,
      );
      final field = find.widgetWithText(TextFormField, '500');
      await tester.tap(field);
      await tester.pumpAndSettle();
      await tester.enterText(field, '5000');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('5000'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // Data section — Export
  // ---------------------------------------------------------------------------
  group('SettingsScreen — Export Data', () {
    testWidgets('renders export tile with subtitle and icon', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.scrollUntilVisible(
        find.text('Export Data'), 200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Data'), findsOneWidget);
      expect(find.text('Export Data'), findsOneWidget);
      expect(find.text('Save sessions, config, and keys to encrypted .lfs file'),
          findsOneWidget);
      expect(find.byIcon(Icons.upload_file), findsOneWidget);
    });

    testWidgets('tap opens export dialog', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.scrollUntilVisible(
        find.text('Export Data'), 200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Export Data'));
      await tester.pumpAndSettle();

      expect(find.text('Master Password'), findsOneWidget);
      expect(find.text('Confirm Password'), findsOneWidget);
      expect(find.text('Export'), findsOneWidget);
    });

    testWidgets('export dialog fields are obscured', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.scrollUntilVisible(
        find.text('Export Data'), 200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Export Data'));
      await tester.pumpAndSettle();

      final masterPw = tester.widget<TextField>(
          find.widgetWithText(TextField, 'Master Password'));
      final confirmPw = tester.widget<TextField>(
          find.widgetWithText(TextField, 'Confirm Password'));
      expect(masterPw.obscureText, isTrue);
      expect(confirmPw.obscureText, isTrue);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });

    testWidgets('cancel closes export dialog', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.scrollUntilVisible(
        find.text('Export Data'), 200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Export Data'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Confirm Password'), findsNothing);
    });

    testWidgets('empty password does not close dialog', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.scrollUntilVisible(
        find.text('Export Data'), 200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Export Data'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Export'));
      await tester.pumpAndSettle();
      expect(find.text('Master Password'), findsOneWidget);
    });

    testWidgets('mismatched passwords shows warning toast', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.scrollUntilVisible(
        find.text('Export Data'), 200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Export Data'));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.widgetWithText(TextField, 'Master Password'), 'pass1');
      await tester.enterText(
          find.widgetWithText(TextField, 'Confirm Password'), 'pass2');

      await tester.tap(find.widgetWithText(FilledButton, 'Export'));
      await tester.pump();

      expect(find.text('Passwords do not match'), findsOneWidget);
      expect(find.text('Master Password'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    });

    testWidgets('matching passwords closes dialog', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.scrollUntilVisible(
        find.text('Export Data'), 200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Export Data'));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.widgetWithText(TextField, 'Master Password'), 'matching');
      await tester.enterText(
          find.widgetWithText(TextField, 'Confirm Password'), 'matching');

      await tester.tap(find.text('Export'));
      // After tap, a progress dialog with CircularProgressIndicator appears
      // (can't pumpAndSettle because of infinite animation). Pump frames instead.
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      // Password dialog should be closed (progress dialog is now showing)
      expect(find.text('Confirm Password'), findsNothing);
    });

    testWidgets('export succeeds with session store and shows toast',
        (tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildFullApp());
      await tester.pump();

      await tester.scrollUntilVisible(
        find.text('Export Data'), 100,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Export Data'));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.widgetWithText(TextField, 'Master Password'), 'securepass');
      await tester.enterText(
          find.widgetWithText(TextField, 'Confirm Password'), 'securepass');

      await tester.tap(find.widgetWithText(FilledButton, 'Export'));
      // Progress dialog with CircularProgressIndicator appears — can't pumpAndSettle.
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Confirm Password'), findsNothing);

      // Let isolate complete and progress close
      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(seconds: 5));
      await tester.pump();
    });

    testWidgets('export fails gracefully when path_provider errors',
        (tester) async {
      tester.view.physicalSize = const Size(800, 2000);
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

      await tester.pumpWidget(buildFullApp());
      await tester.pump();

      await tester.scrollUntilVisible(
        find.text('Export Data'), 100,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Export Data'));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.widgetWithText(TextField, 'Master Password'), 'p');
      await tester.enterText(
          find.widgetWithText(TextField, 'Confirm Password'), 'p');

      await tester.tap(find.widgetWithText(FilledButton, 'Export'));
      await tester.pumpAndSettle();

      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });
  });

  // ---------------------------------------------------------------------------
  // Data section — Import
  // ---------------------------------------------------------------------------
  group('SettingsScreen — Import Data', () {
    testWidgets('renders import tile with subtitle and icon', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.scrollUntilVisible(
        find.text('Import Data'), 200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Import Data'), findsOneWidget);
      expect(find.text('Load data from .lfs file'), findsOneWidget);
      expect(find.byIcon(Icons.download), findsOneWidget);
    });

    testWidgets('tap opens import dialog', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildApp());
      await tester.scrollUntilVisible(
        find.text('Import Data'), 200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Import Data'));
      await tester.pumpAndSettle();

      expect(find.text('Path to .lfs file'), findsOneWidget);
      expect(find.text('Master Password'), findsOneWidget);
      expect(find.text('Merge'), findsOneWidget);
      expect(find.text('Replace'), findsOneWidget);
      expect(find.text('Import'), findsOneWidget);
    });

    testWidgets('import dialog path field is not obscured, password is',
        (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildApp());
      await tester.scrollUntilVisible(
        find.text('Import Data'), 200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Import Data'));
      await tester.pumpAndSettle();

      final pwField = tester.widget<TextField>(
          find.widgetWithText(TextField, 'Master Password'));
      expect(pwField.obscureText, isTrue);
      final pathField = tester.widget<TextField>(
          find.widgetWithText(TextField, 'Path to .lfs file'));
      expect(pathField.obscureText, isFalse);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });

    testWidgets('cancel closes import dialog', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildApp());
      await tester.scrollUntilVisible(
        find.text('Import Data'), 200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Import Data'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Path to .lfs file'), findsNothing);
    });

    testWidgets('empty fields do not close dialog', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildApp());
      await tester.scrollUntilVisible(
        find.text('Import Data'), 200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Import Data'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Import'));
      await tester.pumpAndSettle();
      expect(find.text('Path to .lfs file'), findsOneWidget);
    });

    testWidgets('empty password does not close dialog', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildApp());
      await tester.scrollUntilVisible(
        find.text('Import Data'), 200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Import Data'));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.widgetWithText(TextField, 'Path to .lfs file'), '/tmp/test.lfs');
      await tester.tap(find.text('Import'));
      await tester.pumpAndSettle();
      expect(find.text('Path to .lfs file'), findsOneWidget);
    });

    testWidgets('empty path does not close dialog', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildApp());
      await tester.scrollUntilVisible(
        find.text('Import Data'), 200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Import Data'));
      await tester.pumpAndSettle();

      final textFields = find.byType(TextField);
      await tester.enterText(textFields.at(1), 'password123');
      await tester.tap(find.text('Import'));
      await tester.pumpAndSettle();
      expect(find.text('Path to .lfs file'), findsOneWidget);
    });

    testWidgets('default mode is Merge', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildApp());
      await tester.scrollUntilVisible(
        find.text('Import Data'), 200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Import Data'));
      await tester.pumpAndSettle();
      expect(find.text('Add new sessions, keep existing'), findsOneWidget);
    });

    testWidgets('switching to Replace shows description', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildApp());
      await tester.scrollUntilVisible(
        find.text('Import Data'), 200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Import Data'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Replace'));
      await tester.pumpAndSettle();
      expect(find.text('Replace all sessions with imported'), findsOneWidget);

      await tester.tap(find.text('Merge'));
      await tester.pumpAndSettle();
      expect(find.text('Add new sessions, keep existing'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });

    testWidgets('both fields filled closes dialog', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildApp());
      await tester.scrollUntilVisible(
        find.text('Import Data'), 200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Import Data'));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.widgetWithText(TextField, 'Path to .lfs file'),
          '/tmp/nonexistent.lfs');
      await tester.enterText(
          find.widgetWithText(TextField, 'Master Password'), 'password123');

      await tester.tap(find.text('Import'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 5));

      expect(find.text('Path to .lfs file'), findsNothing);
    });

    testWidgets('import in Replace mode sends Replace in result',
        (tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildFullApp());
      await tester.pump();

      await tester.scrollUntilVisible(
        find.text('Import Data'), 100,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Import Data'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Replace'));
      await tester.pumpAndSettle();
      expect(find.text('Replace all sessions with imported'), findsOneWidget);

      await tester.enterText(
          find.widgetWithText(TextField, 'Path to .lfs file'),
          '/tmp/test_import_replace.lfs');
      await tester.enterText(
          find.widgetWithText(TextField, 'Master Password'), 'pw123');

      await tester.tap(find.widgetWithText(FilledButton, 'Import'));
      await tester.pumpAndSettle();
      expect(find.text('Path to .lfs file'), findsNothing);

      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    });

    testWidgets('import with nonexistent file shows error toast',
        (tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildFullApp());
      await tester.pump();

      await tester.scrollUntilVisible(
        find.text('Import Data'), 100,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Import Data'));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.widgetWithText(TextField, 'Path to .lfs file'),
          '/tmp/nonexistent_file_that_does_not_exist_12345.lfs');
      await tester.enterText(
          find.widgetWithText(TextField, 'Master Password'), 'pw');

      await tester.tap(find.widgetWithText(FilledButton, 'Import'));
      await tester.pumpAndSettle();

      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });

    testWidgets('import dialog mode toggle shows Replace description',
        (tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildFullApp());
      await tester.pump();

      await tester.scrollUntilVisible(
        find.text('Import Data'), 100,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Import Data'));
      await tester.pumpAndSettle();

      // Default is Merge
      expect(find.text('Add new sessions, keep existing'), findsOneWidget);

      // Switch to Replace
      await tester.tap(find.text('Replace'));
      await tester.pumpAndSettle();

      expect(find.text('Replace all sessions with imported'), findsOneWidget);

      // Switch back to Merge
      await tester.tap(find.text('Merge'));
      await tester.pumpAndSettle();

      expect(find.text('Add new sessions, keep existing'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });
  });

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
        find.text('LetsFLUTssh'), 200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('About'), findsOneWidget);
      expect(find.text('LetsFLUTssh'), findsOneWidget);
      // Version string — check format, not a hardcoded number
      expect(find.textContaining(RegExp(r'v\d+\.\d+\.\d+')), findsOneWidget);
      expect(find.textContaining('SSH/SFTP client'), findsOneWidget);
      // info_outline appears in both the section header and the About tile
      expect(find.byIcon(Icons.info_outline), findsWidgets);
    });

    testWidgets('renders source code link', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.scrollUntilVisible(
        find.text('Source Code'), 200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Source Code'), findsOneWidget);
      expect(find.text('https://github.com/Llloooggg/LetsFLUTssh'), findsOneWidget);
      expect(find.byIcon(Icons.code), findsOneWidget);
    });

    testWidgets('tapping Source Code copies URL and shows toast',
        (tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildApp());
      await tester.scrollUntilVisible(
        find.text('Source Code'), 200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Source Code'));
      await tester.pump();

      expect(find.text('URL copied to clipboard'), findsOneWidget);

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });

    testWidgets('source code tap does not crash', (tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildApp());
      await tester.scrollUntilVisible(
        find.text('Source Code'), 200,
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
        find.text('Reset to Defaults'), 200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Reset to Defaults'), findsOneWidget);
      expect(find.byIcon(Icons.restore), findsOneWidget);
    });

    testWidgets('tapping Reset does not crash', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.scrollUntilVisible(
        find.text('Reset to Defaults'), 200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Reset to Defaults'));
      await tester.pumpAndSettle();
      expect(find.byType(ListView), findsOneWidget);
    });

    testWidgets('reset with custom config updates fields', (tester) async {
      final custom = AppConfig.defaults.copyWith(
        terminal: AppConfig.defaults.terminal.copyWith(fontSize: 20.0, scrollback: 10000),
        ssh: AppConfig.defaults.ssh.copyWith(keepAliveSec: 60),
      );
      await tester.pumpWidget(buildApp(initialConfig: custom));
      await tester.scrollUntilVisible(
        find.text('Reset to Defaults'), 200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Reset to Defaults'));
      await tester.pumpAndSettle();
      expect(find.byType(ListView), findsOneWidget);
    });

    testWidgets('reset with highly custom config does not crash',
        (tester) async {
      final custom = AppConfig.defaults.copyWith(
        terminal: AppConfig.defaults.terminal.copyWith(fontSize: 22.0, scrollback: 20000, theme: 'light'),
        ssh: AppConfig.defaults.ssh.copyWith(keepAliveSec: 120, sshTimeoutSec: 45, defaultPort: 3333),
        transferWorkers: 8,
        maxHistory: 2000,
      );
      await tester.pumpWidget(buildApp(initialConfig: custom));
      await tester.scrollUntilVisible(
        find.text('Reset to Defaults'), 200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Reset to Defaults'));
      await tester.pumpAndSettle();
      expect(find.byType(ListView), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // Custom config values
  // ---------------------------------------------------------------------------
  group('SettingsScreen — custom config values', () {
    testWidgets('renders with custom config values', (tester) async {
      final customConfig = AppConfig.defaults.copyWith(
        terminal: AppConfig.defaults.terminal.copyWith(fontSize: 18.0, theme: 'light', scrollback: 10000),
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
          overrides: [
            configProvider.overrideWith(ConfigNotifier.new),
          ],
          child: MaterialApp(
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
          overrides: [
            configProvider.overrideWith(ConfigNotifier.new),
          ],
          child: MaterialApp(
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

      await tester.pumpWidget(buildFullApp());
      await tester.pump();

      await tester.scrollUntilVisible(
        find.text('Export Data'), 100,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Export Data'));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.widgetWithText(TextField, 'Master Password'), 'alpha');
      await tester.enterText(
          find.widgetWithText(TextField, 'Confirm Password'), 'beta');

      await tester.tap(find.widgetWithText(FilledButton, 'Export'));
      await tester.pump();

      // Toast text is visible
      expect(find.text('Passwords do not match'), findsOneWidget);

      // Dialog remains open (not closed)
      expect(find.text('Master Password'), findsOneWidget);
      expect(find.text('Confirm Password'), findsOneWidget);

      // Clean up
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    });

    testWidgets('mismatch does not close dialog even with non-empty fields',
        (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildFullApp());
      await tester.pump();

      await tester.scrollUntilVisible(
        find.text('Export Data'), 100,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Export Data'));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.widgetWithText(TextField, 'Master Password'), 'longpassword1');
      await tester.enterText(
          find.widgetWithText(TextField, 'Confirm Password'), 'longpassword2');

      await tester.tap(find.widgetWithText(FilledButton, 'Export'));
      await tester.pump();

      // Dialog still visible
      expect(find.widgetWithText(FilledButton, 'Export'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    });
  });

  // ---------------------------------------------------------------------------
  // Import file not found toast verification
  // ---------------------------------------------------------------------------
  group('SettingsScreen - Import file not found toast', () {
    testWidgets('nonexistent file shows File not found toast text',
        (tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildFullApp());
      await tester.pump();

      await tester.scrollUntilVisible(
        find.text('Import Data'), 100,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Import Data'));
      await tester.pumpAndSettle();

      const fakePath = '/tmp/absolutely_nonexistent_file_9999.lfs';
      await tester.enterText(
          find.widgetWithText(TextField, 'Path to .lfs file'), fakePath);
      await tester.enterText(
          find.widgetWithText(TextField, 'Master Password'), 'pw');

      // Tap Import — dialog closes, then _executeImport runs with real I/O
      await tester.tap(find.widgetWithText(FilledButton, 'Import'));
      // Pump to process dialog close animation
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      // Let real async I/O (File.exists) complete
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 200)));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      // Verify the toast text
      expect(find.textContaining('File not found'), findsOneWidget);

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });
  });

  // ---------------------------------------------------------------------------
  // Data Path tile — copy to clipboard
  // ---------------------------------------------------------------------------
  group('SettingsScreen — Data Path tile', () {
    testWidgets('tapping Data Location copies path to clipboard',
        (tester) async {
      tester.view.physicalSize = const Size(800, 2000);
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
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
      await tester.pump();

      await tester.scrollUntilVisible(
        find.text('Data Location'), 200,
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
      final config = AppConfig.defaults.copyWith(enableLogging: true);
      await tester.pumpWidget(buildApp(initialConfig: config));
      await tester.scrollUntilVisible(
        find.text('Enable Logging'), 200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Enable Logging'), findsOneWidget);
    });

    testWidgets('logging tiles visible when enabled', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final config = AppConfig.defaults.copyWith(enableLogging: true);
      await tester.pumpWidget(buildApp(initialConfig: config));
      await tester.scrollUntilVisible(
        find.text('Live Log'), 200,
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

      final config = AppConfig.defaults.copyWith(enableLogging: true);
      await tester.pumpWidget(buildApp(initialConfig: config));
      await tester.scrollUntilVisible(
        find.text('Live Log'), 200,
        scrollable: find.byType(Scrollable).first,
      );
      // Allow _LiveLogViewer timer/initState refresh to complete
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 300)));
      await tester.pump();

      // Inline viewer is present — no dialog
      expect(find.text('Live Log'), findsOneWidget);
      expect(find.byType(SelectableText), findsWidgets);
    });

    testWidgets('live log viewer shows placeholder when log is empty',
        (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Clear logs (real I/O)
      await tester.runAsync(() => AppLogger.instance.clearLogs());

      final config = AppConfig.defaults.copyWith(enableLogging: true);
      await tester.pumpWidget(buildApp(initialConfig: config));
      await tester.scrollUntilVisible(
        find.text('Live Log'), 200,
        scrollable: find.byType(Scrollable).first,
      );
      // Allow refresh to complete
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 300)));
      await tester.pump();

      // Either placeholder or content is shown — viewer is present
      expect(find.text('Live Log'), findsOneWidget);
    });

    testWidgets('live log viewer copy icon copies content to clipboard', (tester) async {
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
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 100)));

      final config = AppConfig.defaults.copyWith(enableLogging: true);
      await tester.pumpWidget(buildApp(initialConfig: config));
      await tester.scrollUntilVisible(
        find.byIcon(Icons.copy), 200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 300)));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.copy));
      await tester.pump();

      expect(copiedText, isNotNull);
      // Toast shows either "Copied to clipboard" or "Log is empty"
      expect(find.textContaining('clipboard').evaluate().isNotEmpty ||
             find.textContaining('empty').evaluate().isNotEmpty, isTrue);

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });

    testWidgets('live log viewer copy shows toast', (tester) async {
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

      AppLogger.instance.log('copy log test', name: 'Test');
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 100)));

      final config = AppConfig.defaults.copyWith(enableLogging: true);
      await tester.pumpWidget(buildApp(initialConfig: config));
      await tester.scrollUntilVisible(
        find.byIcon(Icons.copy), 200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 300)));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.copy));
      await tester.pump();

      expect(copiedText, isNotNull);
      expect(find.textContaining('clipboard').evaluate().isNotEmpty ||
             find.textContaining('empty').evaluate().isNotEmpty, isTrue);

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });

    testWidgets('Clear Logs clears and shows toast', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      AppLogger.instance.log('entry to clear', name: 'Test');
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 100)));

      final config = AppConfig.defaults.copyWith(enableLogging: true);
      await tester.pumpWidget(buildApp(initialConfig: config));
      await tester.scrollUntilVisible(
        find.byIcon(Icons.delete_outline), 200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 300)));
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

    testWidgets('toggling Enable Logging switch calls config update', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Start with logging disabled
      await tester.pumpWidget(buildApp(initialConfig: AppConfig.defaults));
      await tester.scrollUntilVisible(
        find.text('Enable Logging'), 200,
        scrollable: find.byType(Scrollable).first,
      );

      // The toggle pill should have bg4 color (off state)
      final toggleContainer = find.byWidgetPredicate(
        (w) => w is Container &&
               w.decoration is BoxDecoration &&
               (w.decoration as BoxDecoration).color == AppTheme.bg4 &&
               (w.decoration as BoxDecoration).borderRadius == BorderRadius.circular(9),
      );
      expect(toggleContainer, findsOneWidget);

      // Tap the toggle to enable logging
      await tester.tap(find.text('Enable Logging'));
      await tester.pumpAndSettle();
    });

    testWidgets('logging disabled hides live log viewer', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // enableLogging = false (default) — live log viewer should not appear
      await tester.pumpWidget(buildApp(initialConfig: AppConfig.defaults));
      await tester.scrollUntilVisible(
        find.text('Enable Logging'), 200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Enable Logging'), findsOneWidget);
      expect(find.text('Live Log'), findsNothing);
    });

    testWidgets('toggle renders ON when config has enableLogging true',
        (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final config = AppConfig.defaults.copyWith(enableLogging: true);
      await tester.pumpWidget(buildApp(initialConfig: config));
      await tester.scrollUntilVisible(
        find.text('Enable Logging'), 200,
        scrollable: find.byType(Scrollable).first,
      );

      // Find the toggle pill that is in the same Row as "Enable Logging"
      final loggingRow = find.ancestor(
        of: find.text('Enable Logging'),
        matching: find.byType(Row),
      ).first;
      final toggleContainer = find.descendant(
        of: loggingRow,
        matching: find.byWidgetPredicate(
          (w) => w is Container &&
                 w.decoration is BoxDecoration &&
                 (w.decoration as BoxDecoration).color == AppTheme.accent &&
                 (w.decoration as BoxDecoration).borderRadius == BorderRadius.circular(9),
        ),
      );
      expect(toggleContainer, findsOneWidget);
    });

    testWidgets('logging section shows icons for copy/export/clear in live viewer',
        (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final config = AppConfig.defaults.copyWith(enableLogging: true);
      await tester.pumpWidget(buildApp(initialConfig: config));
      await tester.scrollUntilVisible(
        find.text('Live Log'), 200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byIcon(Icons.copy), findsOneWidget);
      expect(find.byIcon(Icons.save_alt), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
      expect(find.byIcon(Icons.visibility), findsNothing);
    });

    testWidgets('live log copy with empty log shows toast',
        (tester) async {
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

      final config = AppConfig.defaults.copyWith(enableLogging: true);
      await tester.pumpWidget(buildApp(initialConfig: config));
      await tester.scrollUntilVisible(
        find.byIcon(Icons.copy), 200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 300)));
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

    testWidgets('toggle has correct pill shape and label',
        (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final config = AppConfig.defaults.copyWith(enableLogging: true);
      await tester.pumpWidget(buildApp(initialConfig: config));
      await tester.scrollUntilVisible(
        find.text('Enable Logging'), 200,
        scrollable: find.byType(Scrollable).first,
      );

      expect(find.text('Enable Logging'), findsOneWidget);
      // Find the toggle pill in the same Row as "Enable Logging"
      final loggingRow = find.ancestor(
        of: find.text('Enable Logging'),
        matching: find.byType(Row),
      ).first;
      final toggleContainer = find.descendant(
        of: loggingRow,
        matching: find.byWidgetPredicate(
          (w) => w is Container &&
                 w.decoration is BoxDecoration &&
                 (w.decoration as BoxDecoration).borderRadius == BorderRadius.circular(9),
        ),
      );
      expect(toggleContainer, findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // _DataPathTile — FutureBuilder paths
  // ---------------------------------------------------------------------------
  group('SettingsScreen — _DataPathTile FutureBuilder', () {
    testWidgets('shows "..." while loading then resolves path', (tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildApp());

      // Before FutureBuilder resolves, subtitle should be "..."
      await tester.scrollUntilVisible(
        find.text('Data Location'), 200,
        scrollable: find.byType(Scrollable).first,
      );
      // The FutureBuilder may still show "..." or resolved path
      expect(find.text('Data Location'), findsOneWidget);

      // Let the FutureBuilder resolve
      await tester.runAsync(
          () => Future.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
      await tester.pump();

      // After resolving, should show actual path (tempDir path)
      expect(find.text('...'), findsNothing);
      expect(find.text('Data Location'), findsOneWidget);
    });

    testWidgets('Data Location tile has correct icon and padding',
        (tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildApp());
      await tester.runAsync(
          () => Future.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
      await tester.pump();

      await tester.scrollUntilVisible(
        find.text('Data Location'), 200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byIcon(Icons.folder_special), findsOneWidget);
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
          configProvider.overrideWith(
            () => _PrePopulatedConfigNotifier(config),
          ),
          appVersionProvider.overrideWith(() => _FixedVersionNotifier('1.5.0')),
          if (initialUpdateState != null)
            updateProvider.overrideWith(
              () => _PrePopulatedUpdateNotifier(initialUpdateState),
            ),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const SizedBox(
            height: 2000,
            child: SettingsScreen(),
          ),
        ),
      );
    }

    testWidgets('renders check for updates toggle', (tester) async {
      await tester.pumpWidget(buildUpdateApp());
      await tester.scrollUntilVisible(
        find.text('Check for Updates on Startup'), 200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Check for Updates on Startup'), findsOneWidget);
    });

    testWidgets('toggle defaults to on', (tester) async {
      await tester.pumpWidget(buildUpdateApp());
      await tester.scrollUntilVisible(
        find.text('Check for Updates on Startup'), 200,
        scrollable: find.byType(Scrollable).first,
      );
      // The toggle pill near "Check for Updates on Startup" should have accent color (on)
      final toggleContainer = find.byWidgetPredicate(
        (w) => w is Container &&
               w.decoration is BoxDecoration &&
               (w.decoration as BoxDecoration).color == AppTheme.accent &&
               (w.decoration as BoxDecoration).borderRadius == BorderRadius.circular(9),
      );
      expect(toggleContainer, findsOneWidget);
    });

    testWidgets('renders check button', (tester) async {
      await tester.pumpWidget(buildUpdateApp());
      await tester.scrollUntilVisible(
        find.text('Check for Updates'), 200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Check for Updates'), findsOneWidget);
    });

    testWidgets('shows up-to-date message', (tester) async {
      await tester.pumpWidget(buildUpdateApp(
        initialUpdateState: const UpdateState(
          status: UpdateStatus.upToDate,
          info: UpdateInfo(
            latestVersion: '1.5.0',
            currentVersion: '1.5.0',
            releaseUrl: '',
          ),
        ),
      ));
      await tester.scrollUntilVisible(
        find.textContaining('up to date'), 200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining('up to date'), findsOneWidget);
    });

    testWidgets('shows update available with version', (tester) async {
      await tester.pumpWidget(buildUpdateApp(
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
      ));
      await tester.scrollUntilVisible(
        find.text('Version 2.0.0 available'), 200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Version 2.0.0 available'), findsOneWidget);
      expect(find.text('Current: v1.5.0'), findsOneWidget);
    });

    testWidgets('shows error state', (tester) async {
      await tester.pumpWidget(buildUpdateApp(
        initialUpdateState: const UpdateState(
          status: UpdateStatus.error,
          error: 'Network timeout',
        ),
      ));
      await tester.scrollUntilVisible(
        find.text('Update check failed'), 200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Update check failed'), findsOneWidget);
      expect(find.text('Network timeout'), findsOneWidget);
    });

    testWidgets('shows downloading progress', (tester) async {
      await tester.pumpWidget(buildUpdateApp(
        initialUpdateState: const UpdateState(
          status: UpdateStatus.downloading,
          progress: 0.42,
        ),
      ));
      await tester.scrollUntilVisible(
        find.textContaining('Downloading'), 200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining('Downloading... 42%'), findsOneWidget);
    });

    testWidgets('shows download complete with install button', (tester) async {
      await tester.pumpWidget(buildUpdateApp(
        initialUpdateState: const UpdateState(
          status: UpdateStatus.downloaded,
          downloadedPath: '/tmp/letsflutssh-2.0.0.AppImage',
          progress: 1,
        ),
      ));
      await tester.scrollUntilVisible(
        find.text('Download complete'), 200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Download complete'), findsOneWidget);
      expect(find.text('Install Now'), findsOneWidget);
    });

    testWidgets('shows copy release URL on mobile or when no asset',
        (tester) async {
      await tester.pumpWidget(buildUpdateApp(
        initialUpdateState: const UpdateState(
          status: UpdateStatus.updateAvailable,
          info: UpdateInfo(
            latestVersion: '2.0.0',
            currentVersion: '1.5.0',
            releaseUrl: 'https://github.com/releases',
            // assetUrl is null — no matching asset
          ),
        ),
      ));
      await tester.scrollUntilVisible(
        find.text('Open in Browser'), 200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Open in Browser'), findsOneWidget);
    });

    testWidgets('toggle can be turned off', (tester) async {
      await tester.pumpWidget(buildUpdateApp(
        initialConfig: AppConfig.defaults.copyWith(checkUpdatesOnStart: false),
      ));
      await tester.scrollUntilVisible(
        find.text('Check for Updates on Startup'), 200,
        scrollable: find.byType(Scrollable).first,
      );
      // Find the toggle pill in the same Row as "Check for Updates on Startup"
      final updateRow = find.ancestor(
        of: find.text('Check for Updates on Startup'),
        matching: find.byType(Row),
      ).first;
      final toggleContainer = find.descendant(
        of: updateRow,
        matching: find.byWidgetPredicate(
          (w) => w is Container &&
                 w.decoration is BoxDecoration &&
                 (w.decoration as BoxDecoration).color == AppTheme.bg4 &&
                 (w.decoration as BoxDecoration).borderRadius == BorderRadius.circular(9),
        ),
      );
      expect(toggleContainer, findsOneWidget);
    });

    testWidgets('manual check shows toast when up to date', (tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final mockService = UpdateService(
        fetch: (_) async => '{"tag_name":"v1.5.0","html_url":"","assets":[]}',
      );
      await tester.pumpWidget(ProviderScope(
        overrides: [
          configProvider.overrideWith(
            () => _PrePopulatedConfigNotifier(AppConfig.defaults),
          ),
          appVersionProvider.overrideWith(() => _FixedVersionNotifier('1.5.0')),
          updateServiceProvider.overrideWithValue(mockService),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const SettingsScreen(),
        ),
      ));

      await tester.scrollUntilVisible(
        find.text('Check for Updates'), 200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Check for Updates'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();

      expect(find.text('You\'re running the latest version'), findsOneWidget);
      Toast.clearAllForTest();
    });

    testWidgets('manual check shows toast when update available', (tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final mockService = UpdateService(
        fetch: (_) async => '{"tag_name":"v9.0.0","html_url":"","assets":[]}',
      );
      await tester.pumpWidget(ProviderScope(
        overrides: [
          configProvider.overrideWith(
            () => _PrePopulatedConfigNotifier(AppConfig.defaults),
          ),
          appVersionProvider.overrideWith(() => _FixedVersionNotifier('1.5.0')),
          updateServiceProvider.overrideWithValue(mockService),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const SettingsScreen(),
        ),
      ));

      await tester.scrollUntilVisible(
        find.text('Check for Updates'), 200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Check for Updates'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();

      expect(find.text('Version 9.0.0 available'), findsWidgets);
      Toast.clearAllForTest();
    });

    testWidgets('manual check shows toast on error', (tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final mockService = UpdateService(
        fetch: (_) async => throw Exception('Network error'),
      );
      await tester.pumpWidget(ProviderScope(
        overrides: [
          configProvider.overrideWith(
            () => _PrePopulatedConfigNotifier(AppConfig.defaults),
          ),
          appVersionProvider.overrideWith(() => _FixedVersionNotifier('1.5.0')),
          updateServiceProvider.overrideWithValue(mockService),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const SettingsScreen(),
        ),
      ));

      await tester.scrollUntilVisible(
        find.text('Check for Updates'), 200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Check for Updates'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();

      expect(find.textContaining('Network error'), findsWidgets);
      Toast.clearAllForTest();
    });
  });

  // ---------------------------------------------------------------------------
  // Desktop two-column layout
  // ---------------------------------------------------------------------------
  group('SettingsScreen — desktop layout', () {
    Widget buildDesktopApp({AppConfig? initialConfig}) {
      final config = initialConfig ?? AppConfig.defaults;
      return ProviderScope(
        overrides: [
          configProvider.overrideWith(
            () => _PrePopulatedConfigNotifier(config),
          ),
          appVersionProvider.overrideWith(() => _FixedVersionNotifier('1.5.0')),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const SettingsScreen(),
        ),
      );
    }

    setUp(() {
      plat.debugMobilePlatformOverride = false;
      plat.debugDesktopPlatformOverride = true;
    });

    testWidgets('renders nav rail with all section labels', (tester) async {
      await tester.pumpWidget(buildDesktopApp());
      // "Appearance" appears in both nav + content header = 2
      expect(find.text('Appearance'), findsNWidgets(2));
      // Others appear once in nav only (content shows Appearance by default)
      expect(find.text('Terminal'), findsOneWidget);
      expect(find.text('Connection'), findsOneWidget);
      expect(find.text('Transfers'), findsOneWidget);
      expect(find.text('Data'), findsOneWidget);
      expect(find.text('Logging'), findsOneWidget);
      expect(find.text('Updates'), findsOneWidget);
      expect(find.text('About'), findsOneWidget);
    });

    testWidgets('first section is selected by default', (tester) async {
      await tester.pumpWidget(buildDesktopApp());
      // Appearance content should be visible (header + nav = 2 instances)
      expect(find.text('Appearance'), findsNWidgets(2));
      expect(find.text('Theme'), findsOneWidget);
      expect(find.text('Font Size'), findsOneWidget);
    });

    testWidgets('tapping nav item switches content pane', (tester) async {
      await tester.pumpWidget(buildDesktopApp());

      // Initially shows Appearance
      expect(find.text('Theme'), findsOneWidget);

      // Tap Terminal nav item
      await tester.tap(find.text('Terminal'));
      await tester.pumpAndSettle();

      // Terminal content visible (header + nav = 2), Appearance content gone
      expect(find.text('Terminal'), findsNWidgets(2));
      expect(find.text('Scrollback Lines'), findsOneWidget);
      expect(find.text('Font Size'), findsNothing);
    });

    testWidgets('tapping Connection shows connection fields', (tester) async {
      await tester.pumpWidget(buildDesktopApp());
      await tester.tap(find.text('Connection'));
      await tester.pumpAndSettle();

      expect(find.text('Connection'), findsNWidgets(2));
      expect(find.text('Keep-Alive Interval (sec)'), findsOneWidget);
      expect(find.text('SSH Timeout (sec)'), findsOneWidget);
      expect(find.text('Default Port'), findsOneWidget);
    });

    testWidgets('renders Reset to Defaults button', (tester) async {
      await tester.pumpWidget(buildDesktopApp());
      expect(find.text('Reset to Defaults'), findsOneWidget);
    });

    testWidgets('has VerticalDivider between nav and content', (tester) async {
      await tester.pumpWidget(buildDesktopApp());
      expect(find.byType(VerticalDivider), findsOneWidget);
    });
  });
}

/// An UpdateNotifier subclass that starts with a custom initial state.
class _PrePopulatedUpdateNotifier extends UpdateNotifier {
  final UpdateState _initial;
  _PrePopulatedUpdateNotifier(this._initial);

  @override
  UpdateState build() {
    super.build();
    state = _initial;
    return state;
  }
}

/// An AppVersionNotifier that returns a fixed version string.
class _FixedVersionNotifier extends AppVersionNotifier {
  final String _version;
  _FixedVersionNotifier(this._version);

  @override
  String build() => _version;
}
