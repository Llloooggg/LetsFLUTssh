import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:file_picker/src/platform/file_picker_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/config/app_config.dart';
import 'package:letsflutssh/core/security/master_password.dart';
import 'package:letsflutssh/features/settings/settings_screen.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/providers/config_provider.dart';
import 'package:letsflutssh/providers/master_password_provider.dart';
import 'package:letsflutssh/providers/version_provider.dart';
import 'package:letsflutssh/theme/app_theme.dart';
import 'package:letsflutssh/utils/platform.dart' as plat;
import 'package:letsflutssh/widgets/toast.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import '../../helpers/test_notifiers.dart';

class MockMasterPasswordManager extends MasterPasswordManager {
  bool _enabled = false;

  MockMasterPasswordManager({required String basePath})
    : super(basePath: basePath);

  @override
  Future<Uint8List> enable(String password) async {
    _enabled = true;
    return Uint8List.fromList(List.generate(32, (i) => i));
  }

  @override
  Future<bool> isEnabled() async {
    return _enabled;
  }

  @override
  Future<bool> verify(String password) async => true;

  @override
  Future<Uint8List> deriveKey(String password) async {
    return Uint8List.fromList(List.generate(32, (i) => i));
  }
}

/// Mock FilePickerPlatform that returns null/no-op for all operations so no
/// native dialog is ever launched during these widget tests.
class _MockFilePickerPlatform extends FilePickerPlatform
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
  late _MockFilePickerPlatform mockFilePicker;
  late MockMasterPasswordManager manager;

  setUp(() async {
    // Force mobile layout so the Settings screen renders as a flat ListView.
    plat.debugMobilePlatformOverride = true;
    plat.debugDesktopPlatformOverride = false;
    // Start all collapsible sections expanded so content is immediately visible.
    debugCollapsibleSectionsExpanded = true;
    tempDir = await Directory.systemTemp.createTemp('mp_dialogs_test_');
    mockFilePicker = _MockFilePickerPlatform();
    FilePickerPlatform.instance = mockFilePicker;
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
    manager = MockMasterPasswordManager(basePath: tempDir.path);
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

  /// Builds the provider scaffold around a SettingsScreen.
  ///
  /// Reuses the same [manager] instance from setUp so that enabling the
  /// master password before pumping yields an "enabled" settings screen state.
  Widget buildApp({AppConfig? initialConfig, double height = 3000}) {
    final config = initialConfig ?? AppConfig.defaults;
    return ProviderScope(
      overrides: [
        configProvider.overrideWith(() => PrePopulatedConfigNotifier(config)),
        appVersionProvider.overrideWith(() => FixedVersionNotifier('1.5.0')),
        masterPasswordProvider.overrideWithValue(manager),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: S.localizationsDelegates,
        supportedLocales: S.supportedLocales,
        theme: AppTheme.dark(),
        home: SizedBox(height: height, child: const SettingsScreen()),
      ),
    );
  }

  /// Opens the Manage Master Password tile (initial state: password NOT set).
  /// Results in the `_SetMasterPasswordDialog` being shown.
  Future<void> openSetDialog(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Manage Master Password'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Manage Master Password'));
    await tester.pumpAndSettle();
  }

  /// Opens the Manage Master Password tile when the password IS set, and
  /// taps the given option ('Change Master Password' or 'Remove Master
  /// Password') in the SimpleDialog.
  Future<void> openManageOptionsAndTap(
    WidgetTester tester, {
    required String option,
  }) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await manager.enable('initialPass');
    await tester.pumpWidget(buildApp());

    // Pump multiple frames to allow async operations to complete
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    await tester.scrollUntilVisible(
      find.text('Manage Master Password'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Manage Master Password'));

    // Pump multiple frames to allow dialog to appear
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    // SimpleDialog with Change / Remove options.
    await tester.tap(find.text(option));

    // Pump multiple frames to allow dialog to appear
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  // ---------------------------------------------------------------------------
  // _SetMasterPasswordDialog
  // ---------------------------------------------------------------------------
  group('_SetMasterPasswordDialog', () {
    testWidgets('tap manage master password tile opens set dialog', (
      tester,
    ) async {
      await openSetDialog(tester);

      // Dialog title and its two password fields are visible.
      expect(find.text('Set Master Password'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'New Password'), findsOneWidget);
      expect(
        find.widgetWithText(TextField, 'Confirm Password'),
        findsOneWidget,
      );

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });

    testWidgets('empty password does not close dialog', (tester) async {
      await openSetDialog(tester);

      // Tap OK with both fields empty — non-empty is the only constraint,
      // so the handler silently returns and the dialog stays open.
      await tester.tap(find.text('OK'));
      await tester.pump();

      expect(find.text('Set Master Password'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    });

    testWidgets('short matching passwords close dialog (no minimum length)', (
      tester,
    ) async {
      // Length restrictions were intentionally removed: the only check on
      // a new master password is that it is non-empty. A 5-char password
      // that matches its confirmation must succeed.
      await openSetDialog(tester);

      await tester.enterText(
        find.widgetWithText(TextField, 'New Password'),
        'short',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Confirm Password'),
        'short',
      );

      await tester.tap(find.text('OK'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 5));

      expect(find.text('Set Master Password'), findsNothing);
    });

    testWidgets('mismatched passwords shows warning toast', (tester) async {
      await openSetDialog(tester);

      await tester.enterText(
        find.widgetWithText(TextField, 'New Password'),
        'longpassword1',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Confirm Password'),
        'longpassword2',
      );

      await tester.tap(find.text('OK'));
      await tester.pump();

      expect(find.text('Passwords do not match'), findsOneWidget);
      // Dialog still open.
      expect(find.text('Set Master Password'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    });

    testWidgets('valid passwords closes dialog', (tester) async {
      await openSetDialog(tester);

      await tester.enterText(
        find.widgetWithText(TextField, 'New Password'),
        'longvalidpassword',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Confirm Password'),
        'longvalidpassword',
      );

      await tester.tap(find.text('OK'));
      // Pump a single frame: the dialog closes synchronously via
      // Navigator.pop. Do NOT pumpAndSettle — the settings screen then
      // triggers the real PBKDF2 enable flow on an Isolate, which widget
      // tests can't drive. Extra pumps let isolate and toast timers settle.
      await tester.pump();
      await tester.pump(const Duration(seconds: 5));

      // The dialog is gone. The "Set Master Password" text no longer
      // appears because the settings tile label is "Manage Master Password".
      expect(find.text('Set Master Password'), findsNothing);
    });
  });

  // ---------------------------------------------------------------------------
  // _ChangeMasterPasswordDialog (requires master password enabled first)
  // ---------------------------------------------------------------------------
  group('_ChangeMasterPasswordDialog', () {
    testWidgets('tap change option opens change dialog', (tester) async {
      await openManageOptionsAndTap(tester, option: 'Change Master Password');

      // Change dialog has three labelled fields.
      expect(
        find.widgetWithText(TextField, 'Current Password'),
        findsOneWidget,
      );
      expect(find.widgetWithText(TextField, 'New Password'), findsOneWidget);
      expect(
        find.widgetWithText(TextField, 'Confirm Password'),
        findsOneWidget,
      );

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });

    testWidgets('empty current password does not close dialog', (tester) async {
      await tester.runAsync(() async {
        await openManageOptionsAndTap(tester, option: 'Change Master Password');

        // Leave current empty, fill only the new/confirm fields.
        await tester.enterText(
          find.widgetWithText(TextField, 'New Password'),
          'longvalidpassword',
        );
        await tester.enterText(
          find.widgetWithText(TextField, 'Confirm Password'),
          'longvalidpassword',
        );

        await tester.tap(find.text('OK'));
        await tester.pump();

        // Silent return: dialog stays open, no toast shown.
        expect(find.text('Change Master Password'), findsOneWidget);

        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
      });
    });

    testWidgets(
      'short matching new passwords close dialog (no minimum length)',
      (tester) async {
        // Length restrictions were intentionally removed: only the
        // non-empty check on current + new + confirmation-match remains.
        await tester.runAsync(() async {
          await openManageOptionsAndTap(
            tester,
            option: 'Change Master Password',
          );

          await tester.enterText(
            find.widgetWithText(TextField, 'Current Password'),
            'initialPass',
          );
          await tester.enterText(
            find.widgetWithText(TextField, 'New Password'),
            'short',
          );
          await tester.enterText(
            find.widgetWithText(TextField, 'Confirm Password'),
            'short',
          );

          await tester.tap(find.text('OK'));
          await tester.pump();
          await tester.pump(const Duration(seconds: 5));

          expect(find.text('Change Master Password'), findsNothing);
        });
      },
    );

    testWidgets('empty new password does not close dialog', (tester) async {
      // Current filled but new field empty — silent return (no toast).
      await tester.runAsync(() async {
        await openManageOptionsAndTap(tester, option: 'Change Master Password');

        await tester.enterText(
          find.widgetWithText(TextField, 'Current Password'),
          'initialPass',
        );
        // New + Confirm stay empty.
        await tester.tap(find.text('OK'));
        await tester.pump();

        expect(find.text('Change Master Password'), findsOneWidget);

        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
      });
    });

    testWidgets('mismatched new passwords shows warning toast', (tester) async {
      await tester.runAsync(() async {
        await openManageOptionsAndTap(tester, option: 'Change Master Password');

        await tester.enterText(
          find.widgetWithText(TextField, 'Current Password'),
          'initialPass',
        );
        await tester.enterText(
          find.widgetWithText(TextField, 'New Password'),
          'longvalidpassword1',
        );
        await tester.enterText(
          find.widgetWithText(TextField, 'Confirm Password'),
          'longvalidpassword2',
        );

        await tester.tap(find.text('OK'));
        await tester.pump();

        expect(find.text('Passwords do not match'), findsOneWidget);
        // Dialog still open.
        expect(find.text('Change Master Password'), findsOneWidget);

        await tester.tap(find.text('Cancel'));
        await tester.pump();
        await tester.pump(const Duration(seconds: 4));
        await tester.pumpAndSettle();
      });
    });

    testWidgets(
      'Enter in the last field submits when all three fields are valid',
      (tester) async {
        // User-reported: "при изменении мастер пароля интер не отлавливается
        // как ввод". The Confirm-password field must accept TextInputAction.done
        // and trigger the same submit path as tapping OK.
        await tester.runAsync(() async {
          await openManageOptionsAndTap(
            tester,
            option: 'Change Master Password',
          );

          await tester.enterText(
            find.widgetWithText(TextField, 'Current Password'),
            'initialPass',
          );
          await tester.enterText(
            find.widgetWithText(TextField, 'New Password'),
            'longvalidpassword',
          );
          await tester.enterText(
            find.widgetWithText(TextField, 'Confirm Password'),
            'longvalidpassword',
          );

          // Focus the last field, then simulate the platform "done"
          // keyboard action. The dialog should pop.
          await tester.tap(find.widgetWithText(TextField, 'Confirm Password'));
          await tester.pump();
          await tester.testTextInput.receiveAction(TextInputAction.done);

          // Single pump + short settle: reencryption runs on an isolate
          // which widget tests can't drive; we only care the dialog closed.
          await tester.pump();
          await tester.pump(const Duration(seconds: 5));

          expect(find.text('Change Master Password'), findsNothing);
        });
      },
    );
  });

  // ---------------------------------------------------------------------------
  // _RemoveMasterPasswordDialog (requires master password enabled first)
  // ---------------------------------------------------------------------------
  group('_RemoveMasterPasswordDialog', () {
    testWidgets('tap remove option opens remove dialog', (tester) async {
      await tester.runAsync(() async {
        await openManageOptionsAndTap(tester, option: 'Remove Master Password');

        // Remove dialog shows the warning body and a single current-password
        // field.
        expect(find.text('Remove Master Password'), findsOneWidget);
        expect(
          find.text(
            'Enter your current password to remove master password '
            'protection. Credentials will be re-encrypted with an '
            'auto-generated key.',
          ),
          findsOneWidget,
        );
        expect(
          find.widgetWithText(TextField, 'Current Password'),
          findsOneWidget,
        );

        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
      });
    });

    testWidgets('empty password does not close dialog', (tester) async {
      await tester.runAsync(() async {
        await openManageOptionsAndTap(tester, option: 'Remove Master Password');

        // Tap OK with empty field — silent return.
        await tester.tap(find.text('OK'));
        await tester.pump();

        // Dialog still open.
        expect(find.text('Remove Master Password'), findsOneWidget);

        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
      });
    });
  });
}
