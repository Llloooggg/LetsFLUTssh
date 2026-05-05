import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:letsflutssh/core/config/app_config.dart';
import 'package:letsflutssh/core/security/biometric_auth.dart';
import 'package:letsflutssh/core/security/biometric_key_vault.dart';
import 'package:letsflutssh/features/settings/settings_screen.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/providers/config_provider.dart';
import 'package:letsflutssh/providers/security_provider.dart';
import 'package:letsflutssh/providers/version_provider.dart';
import 'package:letsflutssh/theme/app_theme.dart';
import 'package:letsflutssh/utils/platform.dart' as plat;
import 'package:letsflutssh/widgets/toast.dart';

import '../../helpers/fake_security.dart';
import '../../helpers/frb_bootstrap.dart';
import '../../helpers/test_notifiers.dart';

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(requireFrbLoaded);

  late Directory tempDir;

  setUp(() async {
    plat.debugDesktopPlatformOverride = true;
    plat.debugMobilePlatformOverride = false;
    debugCollapsibleSectionsExpanded = true;

    tempDir = await Directory.systemTemp.createTemp('settings_data_test_');
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

  Widget buildApp({AppConfig? initialConfig}) {
    final config = initialConfig ?? AppConfig.defaults;
    return ProviderScope(
      overrides: [
        configProvider.overrideWith(() => PrePopulatedConfigNotifier(config)),
        appVersionProvider.overrideWith(() => FixedVersionNotifier('1.5.0')),
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
        home: const SizedBox(height: 3000, child: SettingsScreen()),
      ),
    );
  }

  Future<S> loadL10n() => S.delegate.load(const Locale('en'));

  group('_DataSection rendering', () {
    testWidgets('Storage section header is rendered', (tester) async {
      tester.view.physicalSize = const Size(900, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildApp());
      for (int i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      final l10n = await loadL10n();
      await tester.scrollUntilVisible(
        find.text(l10n.dataStorageSection),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text(l10n.dataStorageSection), findsOneWidget);
    });

    testWidgets('Data location tile resolves the support dir path', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(900, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildApp());
      // Pump several frames so the FutureBuilder for getApplicationSupportDirectory
      // resolves through the mocked path_provider channel.
      for (int i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      final l10n = await loadL10n();
      await tester.scrollUntilVisible(
        find.text(l10n.dataLocation),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text(l10n.dataLocation), findsOneWidget);
      // Path resolved to the mocked tempDir — its leaf segment must
      // surface somewhere on the tile (the resolved path is rendered
      // as the tile body).
      final leaf = tempDir.path.split(Platform.pathSeparator).last;
      expect(find.textContaining(leaf), findsWidgets);
    });

    testWidgets('Reset All Data tile is rendered with destructive copy', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(900, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildApp());
      for (int i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      final l10n = await loadL10n();
      await tester.scrollUntilVisible(
        find.text(l10n.resetAllDataTitle),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text(l10n.resetAllDataTitle), findsOneWidget);
      expect(find.text(l10n.resetAllDataSubtitle), findsOneWidget);
    });

    testWidgets('Tapping Reset All Data opens the confirmation dialog', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(900, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildApp());
      for (int i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      final l10n = await loadL10n();
      final scrollable = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(
        find.text(l10n.resetAllDataTitle),
        300,
        scrollable: scrollable,
      );
      await tester.tap(find.text(l10n.resetAllDataTitle));
      await tester.pumpAndSettle();

      // The confirm dialog carries its own title + body strings.
      expect(find.text(l10n.resetAllDataConfirmTitle), findsOneWidget);
      // Cancel the dialog so no actual wipe runs and the tearDown
      // stays clean. ConfirmDialog renders AppButton.cancel — a
      // custom widget, not a Material TextButton — so find the
      // localised label directly rather than gating on widget type.
      await tester.tap(find.text(l10n.cancel));
      await tester.pumpAndSettle();
      expect(find.text(l10n.resetAllDataConfirmTitle), findsNothing);
    });
  });
}
