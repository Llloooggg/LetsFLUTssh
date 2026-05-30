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
import 'package:letsflutssh/widgets/core/sidebar_nav_dialog.dart';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(requireFrbLoaded);

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('settings_screen_test_');
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

  tearDown(() {
    plat.debugDesktopPlatformOverride = null;
    plat.debugMobilePlatformOverride = null;
    debugCollapsibleSectionsExpanded = false;
    Toast.clearAllForTest();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );

    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Widget buildSettingsScreen({AppConfig? initialConfig, required Widget home}) {
    final config = initialConfig ?? AppConfig.defaults;
    return ProviderScope(
      overrides: [
        configProvider.overrideWith(() => PrePopulatedConfigNotifier(config)),
        appVersionProvider.overrideWith(() => FixedVersionNotifier('1.0.0')),
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
        home: home,
      ),
    );
  }

  Future<S> loadL10n() => S.delegate.load(const Locale('en'));

  Future<void> pumpFrames(WidgetTester tester, [int n = 6]) async {
    for (var i = 0; i < n; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  // ── Mobile SettingsScreen branch ──

  group('SettingsScreen (mobile)', () {
    setUp(() {
      plat.debugDesktopPlatformOverride = false;
      plat.debugMobilePlatformOverride = true;
    });

    testWidgets('renders the mobile AppBar with the localized title', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        buildSettingsScreen(home: const SettingsScreen()),
      );
      await pumpFrames(tester);
      final l10n = await loadL10n();

      // The mobile shell wraps the body in a Scaffold with an AppBar
      // whose title localises through S.of(context).settings — the
      // top-of-screen anchor for the route's identity.
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.text(l10n.settings), findsWidgets);
    });

    testWidgets('renders every section header on the collapsed list', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        buildSettingsScreen(home: const SettingsScreen()),
      );
      await pumpFrames(tester);
      final l10n = await loadL10n();

      // Mobile renders every section header eagerly even when
      // collapsed; the find-by-text in tests would otherwise miss
      // anything below the fold under a lazy sliver. Scroll the
      // scrollable to surface each header in turn.
      final scrollable = find.byType(Scrollable).first;
      for (final title in [
        l10n.appearance,
        l10n.connectionSection,
        l10n.transfers,
        l10n.security,
        l10n.sshIntegrationSection,
        l10n.data,
        l10n.syncSection,
        l10n.logging,
        l10n.updates,
        l10n.about,
      ]) {
        await tester.scrollUntilVisible(
          find.text(title),
          300,
          scrollable: scrollable,
        );
        expect(
          find.text(title),
          findsOneWidget,
          reason: 'header missing: $title',
        );
      }
    });

    testWidgets('reset-to-defaults button is rendered at the bottom', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        buildSettingsScreen(home: const SettingsScreen()),
      );
      await pumpFrames(tester);
      final l10n = await loadL10n();

      await tester.scrollUntilVisible(
        find.text(l10n.resetToDefaults),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text(l10n.resetToDefaults), findsOneWidget);
    });

    testWidgets('SettingsScreen.show pushes a route', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        buildSettingsScreen(
          home: Builder(
            builder: (ctx) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => SettingsScreen.show(ctx),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await pumpFrames(tester);
      final l10n = await loadL10n();

      // The static `SettingsScreen.show` is the canonical mobile entry
      // — tapping the launcher must push a route whose AppBar carries
      // the localised settings title.
      await tester.tap(find.text('open'));
      await pumpFrames(tester);

      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(find.text(l10n.settings), findsWidgets);
    });
  });

  // ── Desktop SettingsDialog branch ──

  group('SettingsDialog (desktop)', () {
    setUp(() {
      plat.debugDesktopPlatformOverride = true;
      plat.debugMobilePlatformOverride = false;
    });

    testWidgets('SettingsDialog.show mounts the SidebarNavDialog', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        buildSettingsScreen(
          home: Builder(
            builder: (ctx) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => SettingsDialog.show(ctx),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await pumpFrames(tester);

      await tester.tap(find.text('open'));
      await pumpFrames(tester);

      // The desktop entry point routes through `SidebarNavDialog`; the
      // mobile collapsible accordion must not mount on this path.
      expect(find.byType(SidebarNavDialog), findsOneWidget);
    });

    testWidgets('every section title surfaces as a nav-rail entry', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        buildSettingsScreen(
          home: Builder(
            builder: (ctx) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => SettingsDialog.show(ctx),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await pumpFrames(tester);
      await tester.tap(find.text('open'));
      await pumpFrames(tester);
      final l10n = await loadL10n();

      // The dialog's nav rail must list every section title so the
      // desktop and mobile entry points present the same surface area.
      // Each title may also be echoed in the panel header; assert
      // `findsWidgets` rather than `findsOneWidget`.
      for (final title in [
        l10n.appearance,
        l10n.connectionSection,
        l10n.transfers,
        l10n.security,
        l10n.sshIntegrationSection,
        l10n.data,
        l10n.syncSection,
        l10n.logging,
        l10n.updates,
        l10n.about,
      ]) {
        expect(
          find.text(title),
          findsWidgets,
          reason: 'nav entry missing: $title',
        );
      }
    });

    testWidgets('reset-to-defaults action lives in the sidebar footer', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        buildSettingsScreen(
          home: Builder(
            builder: (ctx) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => SettingsDialog.show(ctx),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await pumpFrames(tester);
      await tester.tap(find.text('open'));
      await pumpFrames(tester);
      final l10n = await loadL10n();

      // The reset-to-defaults footer button is the desktop dialog's
      // single destructive shortcut. Its label must surface on the
      // first frame the dialog mounts (no hover required to expose it).
      expect(find.text(l10n.resetToDefaults), findsWidgets);
    });

    testWidgets('tapping the reset footer button resets the config', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Pre-populate with a customised config so the reset has
      // something to clear back to defaults.
      final custom = AppConfig.defaults.copyWith(
        ui: AppConfig.defaults.ui.copyWith(uiScale: 1.5),
      );
      late ProviderContainer container;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            configProvider.overrideWith(
              () => PrePopulatedConfigNotifier(custom),
            ),
            appVersionProvider.overrideWith(
              () => FixedVersionNotifier('1.0.0'),
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
                home: Builder(
                  builder: (ctx) => Scaffold(
                    body: Center(
                      child: ElevatedButton(
                        onPressed: () => SettingsDialog.show(ctx),
                        child: const Text('open'),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );
      await pumpFrames(tester);
      expect(container.read(configProvider).uiScale, 1.5);

      await tester.tap(find.text('open'));
      await pumpFrames(tester);
      final l10n = await loadL10n();

      // Tap the reset action in the sidebar footer. Multiple
      // `resetToDefaults` strings live in the tree (footer label +
      // confirm dialog), so target the first hit-testable footer text.
      final resetText = find.text(l10n.resetToDefaults).first;
      await tester.tap(resetText, warnIfMissed: false);
      await pumpFrames(tester);

      // The reset action replaces the config with defaults — the
      // customised uiScale goes back to the documented default.
      expect(
        container.read(configProvider).uiScale,
        AppConfig.defaults.uiScale,
      );
    });
  });

  // Deferred — `debugCollapsibleSectionsExpanded` seam: scrolling on
  // the mobile-shell physical-size pump hangs in this harness, so the
  // seam's effect is covered indirectly by the per-section tests
  // above which mount each section directly.
}
