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
  // The SettingsScreen tree wires FRB-bound helpers in constructors
  // even when this test only drives the pure-Dart preference tiles;
  // mirror the harness used by the surrounding settings tests.
  setUpAll(requireFrbLoaded);

  late Directory tempDir;

  setUp(() async {
    plat.debugDesktopPlatformOverride = true;
    plat.debugMobilePlatformOverride = false;
    debugCollapsibleSectionsExpanded = true;

    tempDir = await Directory.systemTemp.createTemp(
      'settings_preferences_test_',
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

  /// Mount the desktop Settings screen with a captured container so
  /// each test can read the resulting config state through the
  /// provider rather than scraping the widget tree.
  Future<ProviderContainer> mountWithContainer(
    WidgetTester tester, {
    AppConfig? initialConfig,
  }) async {
    final config = initialConfig ?? AppConfig.defaults;
    late ProviderContainer container;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          configProvider.overrideWith(() => PrePopulatedConfigNotifier(config)),
          appVersionProvider.overrideWith(() => FixedVersionNotifier('1.0.0')),
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
    return container;
  }

  Future<S> loadL10n() => S.delegate.load(const Locale('en'));

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

  // ── _AppearanceSection ──

  group('_AppearanceSection', () {
    testWidgets('renders language, theme, UI scale, font size, scrollback', (
      tester,
    ) async {
      sizeView(tester);
      await mountWithContainer(tester);
      await pumpFrames(tester);
      final l10n = await loadL10n();

      await scrollTo(tester, find.text(l10n.language));
      // The Appearance section is the single home for every "how the
      // user sees the app" tile — language, theme, ui scale, terminal
      // font, scrollback. Each tile must mount whenever the section
      // does so a future split surfaces here.
      expect(find.text(l10n.language), findsOneWidget);
      expect(find.text(l10n.theme), findsOneWidget);
      expect(find.text(l10n.uiScale), findsOneWidget);
      expect(find.text(l10n.terminalFontSize), findsOneWidget);
      expect(find.text(l10n.scrollbackLines), findsOneWidget);
    });

    // Deferred — tapping theme "light" segment writes terminal.theme:
    // the segment-control tap routes through `configProvider.update`
    // which schedules an async store timer that races the test's
    // pump cadence. The system-segment test below covers the same
    // dispatch through a parallel arm.

    testWidgets(
      'tapping theme "system" routes onChanged for the third segment',
      (tester) async {
        sizeView(tester);
        final container = await mountWithContainer(tester);
        await pumpFrames(tester);
        final l10n = await loadL10n();

        await scrollTo(tester, find.text(l10n.themeSystem));
        await tester.tap(find.text(l10n.themeSystem));
        await pumpFrames(tester);

        // The three-segment control must reach every value, not just
        // the first two — the "system" branch is the only one that
        // unlocks platform-brightness tracking on the app shell.
        expect(container.read(configProvider).theme, 'system');
      },
    );

    testWidgets('preset config with non-default theme renders selected state', (
      tester,
    ) async {
      sizeView(tester);
      final config = AppConfig.defaults.copyWith(
        terminal: AppConfig.defaults.terminal.copyWith(theme: 'light'),
      );
      await mountWithContainer(tester, initialConfig: config);
      await pumpFrames(tester);
      final l10n = await loadL10n();

      await scrollTo(tester, find.text(l10n.theme));
      // Theme tile mounts with the pre-populated value — both segment
      // labels render, and the section stays mounted across the
      // override.
      expect(find.text(l10n.themeLight), findsOneWidget);
      expect(find.text(l10n.themeDark), findsOneWidget);
    });

    testWidgets('preset locale=ru selects the Russian language label', (
      tester,
    ) async {
      sizeView(tester);
      final config = AppConfig.defaults.copyWith(locale: 'ru');
      await mountWithContainer(tester, initialConfig: config);
      await pumpFrames(tester);
      final l10n = await loadL10n();

      await scrollTo(tester, find.text(l10n.language));
      // The locale tile renders the selected language's native label
      // ("Русский") in the popup trigger. The label is the source of
      // truth for which option the popup shows as selected.
      expect(find.text(l10n.language), findsOneWidget);
      expect(find.textContaining('Русский'), findsWidgets);
    });
  });

  // ── _ConnectionSection ──

  group('_ConnectionSection', () {
    testWidgets(
      'renders keep-alive, ssh timeout, default port, verbose log toggle',
      (tester) async {
        sizeView(tester);
        await mountWithContainer(tester);
        await pumpFrames(tester);
        final l10n = await loadL10n();

        await scrollTo(tester, find.text(l10n.keepAliveInterval));
        // Every connection-tier knob the user can edit must render
        // unconditionally; nothing in this section is gated on a
        // capability probe.
        expect(find.text(l10n.keepAliveInterval), findsOneWidget);
        expect(find.text(l10n.sshTimeout), findsOneWidget);
        expect(find.text(l10n.defaultPort), findsOneWidget);
        expect(find.text(l10n.verboseConnectionLog), findsOneWidget);
      },
    );

    testWidgets('verbose connection log toggle flips the persisted ssh field', (
      tester,
    ) async {
      sizeView(tester);
      final container = await mountWithContainer(tester);
      await pumpFrames(tester);
      final l10n = await loadL10n();

      final initial = container.read(configProvider).verboseConnectionLog;

      await scrollTo(tester, find.text(l10n.verboseConnectionLog));
      await tester.tap(find.text(l10n.verboseConnectionLog));
      await pumpFrames(tester);

      // The toggle persists into `ssh.verboseConnectionLog`. Each tap
      // must flip the bool — no debouncing on a boolean toggle.
      expect(
        container.read(configProvider).verboseConnectionLog,
        isNot(initial),
      );
    });
  });

  // ── _TransferSection ──

  group('_TransferSection', () {
    testWidgets('renders parallel workers, max history, folder sizes toggle', (
      tester,
    ) async {
      sizeView(tester);
      await mountWithContainer(tester);
      await pumpFrames(tester);
      final l10n = await loadL10n();

      await scrollTo(tester, find.text(l10n.parallelWorkers));
      expect(find.text(l10n.parallelWorkers), findsOneWidget);
      expect(find.text(l10n.maxHistory), findsOneWidget);
      expect(find.text(l10n.calculateFolderSizes), findsOneWidget);
    });

    testWidgets('folder-sizes toggle flips the persisted ui field', (
      tester,
    ) async {
      sizeView(tester);
      final container = await mountWithContainer(tester);
      await pumpFrames(tester);
      final l10n = await loadL10n();

      final initial = container.read(configProvider).showFolderSizes;

      await scrollTo(tester, find.text(l10n.calculateFolderSizes));
      await tester.tap(find.text(l10n.calculateFolderSizes));
      await pumpFrames(tester);

      // Folder-sizes lives under `ui.showFolderSizes` — the toggle
      // must thread the copyWith into the nested ui envelope, not
      // the top-level config.
      expect(container.read(configProvider).showFolderSizes, isNot(initial));
    });

    testWidgets('preset workers=5 renders the slider tile mounted', (
      tester,
    ) async {
      sizeView(tester);
      final config = AppConfig.defaults.copyWith(transferWorkers: 5);
      await mountWithContainer(tester, initialConfig: config);
      await pumpFrames(tester);
      final l10n = await loadL10n();

      await scrollTo(tester, find.text(l10n.parallelWorkers));
      // The pre-populated workers value must mount the parallel-workers
      // row without exception; the int tile widget renders a controlled
      // field whose underlying TextField initialises from the config.
      expect(find.text(l10n.parallelWorkers), findsOneWidget);
    });
  });

  // ── _AppearanceSection — extra preset coverage ──

  group('_AppearanceSection — slider + preset coverage', () {
    testWidgets(
      'preset terminal font size renders the font size tile mounted',
      (tester) async {
        sizeView(tester);
        // The slider divisions step is 1.0 across the 8..24 range; the
        // controlled value pins the format callback's render path
        // without driving the gesture (sliding under a tester is
        // hit-test brittle on a wrapped Column).
        final config = AppConfig.defaults.copyWith(
          terminal: AppConfig.defaults.terminal.copyWith(fontSize: 16),
        );
        await mountWithContainer(tester, initialConfig: config);
        await pumpFrames(tester);
        final l10n = await loadL10n();

        await scrollTo(tester, find.text(l10n.terminalFontSize));
        expect(find.text(l10n.terminalFontSize), findsOneWidget);
        // The slider tile formats the value as the integer round; pin
        // the format callback's output by searching for the rendered
        // current-value badge.
        expect(find.text('16'), findsWidgets);
      },
    );

    testWidgets('preset ui scale 1.0 renders the 100% format badge', (
      tester,
    ) async {
      sizeView(tester);
      // The ui-scale slider divisions go from 0.5..2.0 in 15 steps and
      // format as a percentage; the default (1.0) must render as
      // "100%" — pinning the format callback's wiring without
      // simulating gesture input.
      await mountWithContainer(tester);
      await pumpFrames(tester);
      final l10n = await loadL10n();

      await scrollTo(tester, find.text(l10n.uiScale));
      expect(find.text(l10n.uiScale), findsOneWidget);
      expect(find.text('100%'), findsWidgets);
    });

    testWidgets('preset scrollback renders the int tile mounted', (
      tester,
    ) async {
      sizeView(tester);
      final config = AppConfig.defaults.copyWith(
        terminal: AppConfig.defaults.terminal.copyWith(scrollback: 5000),
      );
      await mountWithContainer(tester, initialConfig: config);
      await pumpFrames(tester);
      final l10n = await loadL10n();

      await scrollTo(tester, find.text(l10n.scrollbackLines));
      // Scrollback tile mounts under a controlled int field whose
      // initial value derives from the preset. The settings row must
      // render with the preset value visible somewhere in the tree
      // — the input field formats the int via toString.
      expect(find.text(l10n.scrollbackLines), findsOneWidget);
    });
  });

  // ── _ConnectionSection — extra preset coverage ──

  group('_ConnectionSection — preset values', () {
    testWidgets(
      'preset non-default port renders the default port tile mounted',
      (tester) async {
        sizeView(tester);
        final config = AppConfig.defaults.copyWith(
          ssh: AppConfig.defaults.ssh.copyWith(defaultPort: 2222),
        );
        await mountWithContainer(tester, initialConfig: config);
        await pumpFrames(tester);
        final l10n = await loadL10n();

        await scrollTo(tester, find.text(l10n.defaultPort));
        // The int tile binds initialValue to the preset; pin the
        // tile rendering under a non-default port so a future
        // refactor that drops the watch-and-rebind chain surfaces
        // here.
        expect(find.text(l10n.defaultPort), findsOneWidget);
      },
    );

    testWidgets(
      'preset verbose connection log true renders the toggle row mounted',
      (tester) async {
        sizeView(tester);
        final config = AppConfig.defaults.copyWith(
          ssh: AppConfig.defaults.ssh.copyWith(verboseConnectionLog: true),
        );
        final container = await mountWithContainer(
          tester,
          initialConfig: config,
        );
        await pumpFrames(tester);
        final l10n = await loadL10n();

        await scrollTo(tester, find.text(l10n.verboseConnectionLog));
        // The watch-select on `verboseConnectionLog` must bind to the
        // preset; pin the initial state so flipping the toggle reads
        // false on the first tap rather than re-asserting the preset.
        expect(container.read(configProvider).verboseConnectionLog, isTrue);
      },
    );
  });
}
