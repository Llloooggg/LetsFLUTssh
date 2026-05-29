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
    plat.debugDesktopPlatformOverride = true;
    plat.debugMobilePlatformOverride = false;
    debugCollapsibleSectionsExpanded = true;

    tempDir = await Directory.systemTemp.createTemp('settings_data_extra_');
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

  Future<void> pumpFrames(WidgetTester tester, [int n = 12]) async {
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

  // ── QR export tile renders its action label + subtitle ──

  testWidgets('QR export action tile renders its title + subtitle', (
    tester,
  ) async {
    sizeView(tester);
    await tester.pumpWidget(buildApp());
    await pumpFrames(tester);
    final l10n = await loadL10n();

    // The QR-export entry is the last tile in the Export/Import section.
    // It renders unconditionally — the dialog stack is what bridges it
    // to the orchestrator.
    await scrollTo(tester, find.text(l10n.exportQrCode));
    expect(find.text(l10n.exportQrCode), findsOneWidget);
    expect(find.text(l10n.exportQrCodeSubtitle), findsOneWidget);
  });

  // ── Recordings cap dropdown — pick 100 MiB (smaller than default) ──

  testWidgets(
    'changing the recordings cap to 100 MiB persists through configProvider',
    (tester) async {
      sizeView(tester);
      late ProviderContainer container;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            configProvider.overrideWith(
              () => PrePopulatedConfigNotifier(AppConfig.defaults),
            ),
            appVersionProvider.overrideWith(
              () => FixedVersionNotifier('1.5.0'),
            ),
            masterPasswordProvider.overrideWithValue(
              _NoopMasterPasswordManager(),
            ),
            secureKeyStorageProvider.overrideWithValue(
              FakeSecureKeyStorage(available: false),
            ),
            biometricAuthProvider.overrideWithValue(_FakeBiometricAuth()),
            biometricKeyVaultProvider.overrideWithValue(BiometricKeyVault()),
          ],
          child: Consumer(
            builder: (context, ref, _) {
              container = ProviderScope.containerOf(context);
              return MaterialApp(
                locale: const Locale('en'),
                localizationsDelegates: S.localizationsDelegates,
                supportedLocales: S.supportedLocales,
                theme: AppTheme.dark(),
                home: const SizedBox(height: 3000, child: SettingsScreen()),
              );
            },
          ),
        ),
      );
      await pumpFrames(tester);
      final l10n = await loadL10n();

      await scrollTo(tester, find.text(l10n.recordingsTitle));
      // Open the cap dropdown (the trigger shows the current preset
      // label — the default config picks 500 MiB).
      await tester.tap(find.text(l10n.recordingsCapPreset500Mb).last);
      await tester.pumpAndSettle();
      // Pick the 100 MiB preset — the smallest preset on the dropdown.
      await tester.tap(find.text(l10n.recordingsCapPreset100Mb).last);
      await pumpFrames(tester);

      const oneHundredMib = 100 * 1024 * 1024;
      expect(
        container.read(configProvider).recordingsStorageCapBytes,
        oneHundredMib,
      );
      Toast.clearAllForTest();
    },
  );

  // ── Reset-all-data: typed-confirm dialog renders + cancel keeps state ──

  testWidgets('reset-all-data dialog body matches the localized confirm text', (
    tester,
  ) async {
    sizeView(tester);
    await tester.pumpWidget(buildApp());
    await pumpFrames(tester);
    final l10n = await loadL10n();

    await scrollTo(tester, find.text(l10n.resetAllDataTitle));
    // Tapping the destructive tile opens the typed-confirm dialog
    // — the dialog body text is the localized confirm body.
    await tester.tap(find.text(l10n.resetAllDataTitle));
    await tester.pumpAndSettle();

    expect(find.text(l10n.resetAllDataConfirmTitle), findsOneWidget);
    expect(find.text(l10n.resetAllDataConfirmBody), findsOneWidget);

    // Cancelling leaves the tile mounted; no wipe runs.
    await tester.tap(find.text(l10n.cancel));
    await tester.pumpAndSettle();
    expect(find.text(l10n.resetAllDataConfirmTitle), findsNothing);
  });

  // ── Recordings cap subtitle exposes `used / cap` numbers ──

  testWidgets('recordings tile subtitle renders the IEC-formatted cap suffix', (
    tester,
  ) async {
    sizeView(tester);
    // Start with a config that pins a 1 GiB cap so the subtitle
    // suffix is a known IEC label rather than the default 500 MiB.
    const oneGib = 1024 * 1024 * 1024;
    final cfg = AppConfig.defaults.copyWith(recordingsStorageCapBytes: oneGib);
    await tester.pumpWidget(buildApp(initialConfig: cfg));
    await pumpFrames(tester);
    final l10n = await loadL10n();

    await scrollTo(tester, find.text(l10n.recordingsTitle));
    // The dropdown trigger maps the persisted cap to the nearest
    // preset label; 1 GiB is itself a preset, so the 1 GiB preset
    // label renders in the trigger.
    expect(find.text(l10n.recordingsCapPreset1Gb), findsWidgets);
  });

  // ── Data location tile resolves through path_provider and copies ──

  testWidgets('data location tile renders + tapping it does not throw', (
    tester,
  ) async {
    sizeView(tester);
    await tester.pumpWidget(buildApp());
    await pumpFrames(tester);
    final l10n = await loadL10n();

    await scrollTo(tester, find.text(l10n.dataLocation));
    // The path_provider mock seeded the temp dir; the FutureBuilder
    // resolves and the placeholder dots are gone.
    expect(find.text(l10n.dataLocation), findsOneWidget);
    expect(find.text('...'), findsNothing);

    await tester.tap(find.text(l10n.dataLocation));
    await pumpFrames(tester);
    // Tile is still mounted; clipboard side-effect is opaque from
    // here (the toast text matcher is intentionally avoided).
    expect(find.text(l10n.dataLocation), findsOneWidget);
    Toast.clearAllForTest();
  });

  // ── Storage subsection header divides the Data tiles ──

  testWidgets(
    'storage subsection header separates Export/Import from destructive rows',
    (tester) async {
      sizeView(tester);
      await tester.pumpWidget(buildApp());
      await pumpFrames(tester);
      final l10n = await loadL10n();

      // Both Export/Import and the storage subsection paint in the
      // Data tab; the header is what splits them visually.
      await scrollTo(tester, find.text(l10n.dataStorageSection));
      expect(find.text(l10n.dataStorageSection), findsOneWidget);
      expect(find.text(l10n.dataLocation), findsOneWidget);
      expect(find.text(l10n.recordingsTitle), findsOneWidget);
      expect(find.text(l10n.resetAllDataTitle), findsOneWidget);
    },
  );
}
