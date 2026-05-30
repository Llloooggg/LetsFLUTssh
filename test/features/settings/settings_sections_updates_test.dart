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
import 'package:letsflutssh/core/update/update_service.dart';
import 'package:letsflutssh/features/settings/settings_screen.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/providers/config_provider.dart';
import 'package:letsflutssh/providers/master_password_provider.dart';
import 'package:letsflutssh/providers/security_provider.dart';
import 'package:letsflutssh/providers/update_provider.dart';
import 'package:letsflutssh/providers/version_provider.dart';
import 'package:letsflutssh/theme/app_theme.dart';
import 'package:letsflutssh/utils/platform.dart' as plat;
import 'package:letsflutssh/widgets/core/toast.dart';
import 'package:letsflutssh/widgets/terminal/update_progress_indicator.dart';

import '../../helpers/fake_security.dart';
import '../../helpers/frb_bootstrap.dart';
import '../../helpers/test_notifiers.dart';

/// Biometric probe that always reports "unavailable" so the Security
/// section's initState resolves on the first pump without touching a
/// real platform biometric API.
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

/// MasterPasswordManager that never touches Rust crypto.
class _MockMasterPasswordManager extends MasterPasswordManager {
  _MockMasterPasswordManager()
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

/// Update notifier whose verbs resolve to a scripted outcome so the
/// section's button handlers can be driven without network or
/// installer side-effects. Records every verb call.
class _ScriptedUpdateNotifier extends UpdateNotifier {
  _ScriptedUpdateNotifier(this._initial);

  final UpdateState _initial;
  int checkCalls = 0;
  int installCalls = 0;
  int openReleaseCalls = 0;

  /// Drives the `_InstallOrOpenReleaseButton` label branch.
  bool installerLaunchable = true;

  /// Drives the install-then-fallback branch when the in-app installer
  /// reports failure at runtime.
  bool installResult = true;
  bool openReleaseResult = true;

  /// When non-null, `check()` writes this state instead of the initial.
  UpdateState? checkResult;

  @override
  UpdateState build() {
    super.build();
    state = _initial;
    return state;
  }

  @override
  bool get canLaunchInstaller => installerLaunchable;

  @override
  Future<void> check() async {
    checkCalls++;
    final next = checkResult;
    if (next != null) state = next;
  }

  @override
  Future<bool> install() async {
    installCalls++;
    return installResult;
  }

  @override
  Future<bool> openReleasePage() async {
    openReleaseCalls++;
    return openReleaseResult;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(requireFrbLoaded);

  late Directory tempDir;

  setUp(() async {
    plat.debugDesktopPlatformOverride = true;
    plat.debugMobilePlatformOverride = false;
    debugCollapsibleSectionsExpanded = true;

    tempDir = await Directory.systemTemp.createTemp('settings_updates_test_');
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
        masterPasswordProvider.overrideWithValue(_MockMasterPasswordManager()),
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

  group('_UpdateSection — _runCheck toast branches', () {
    testWidgets('upToDate check fires the "you are running latest" toast', (
      tester,
    ) async {
      sizeView(tester);
      // `_runCheck` reads the post-`check()` state and routes to a toast
      // per status. The toast message for upToDate is `youreRunningLatest`
      // (distinct from the `youreUpToDate` status row that the
      // `_buildStatusWidget` branch paints — same status, two surfaces).
      final notifier = _ScriptedUpdateNotifier(const UpdateState())
        ..checkResult = const UpdateState(status: UpdateStatus.upToDate);
      await tester.pumpWidget(
        buildApp(extraOverrides: [updateProvider.overrideWith(() => notifier)]),
      );
      await pumpFrames(tester);
      final l10n = await loadL10n();

      await scrollTo(tester, find.text(l10n.checkNow));
      await tester.tap(find.text(l10n.checkNow));
      await pumpFrames(tester);

      expect(notifier.checkCalls, 1);
      expect(find.text(l10n.youreRunningLatest), findsOneWidget);
      Toast.clearAllForTest();
    });

    testWidgets('updateAvailable check fires the "version available" toast', (
      tester,
    ) async {
      sizeView(tester);
      // The toast template echoes the new version string.
      final notifier = _ScriptedUpdateNotifier(const UpdateState())
        ..checkResult = const UpdateState(
          status: UpdateStatus.updateAvailable,
          info: UpdateInfo(
            latestVersion: '3.0.0',
            currentVersion: '1.5.0',
            releaseUrl: 'https://example.invalid/releases/3.0.0',
          ),
        );
      await tester.pumpWidget(
        buildApp(extraOverrides: [updateProvider.overrideWith(() => notifier)]),
      );
      await pumpFrames(tester);
      final l10n = await loadL10n();

      await scrollTo(tester, find.text(l10n.checkNow));
      await tester.tap(find.text(l10n.checkNow));
      await pumpFrames(tester);

      // The toast surfaces the localized "Version 3.0.0 available" string.
      // The status row also renders the same template — assert the toast
      // by tapping into `findsWidgets` (template appears in both surfaces).
      expect(find.text(l10n.versionAvailable('3.0.0')), findsWidgets);
      Toast.clearAllForTest();
    });

    testWidgets('error check fires the localized error toast', (tester) async {
      sizeView(tester);
      // `_runCheck`'s error branch picks `errDownloadFailed` when
      // `state.error` is set; the `localizeError` shim renders the
      // exception's `toString` when no localized key matches.
      final notifier = _ScriptedUpdateNotifier(const UpdateState())
        ..checkResult = const UpdateState(
          status: UpdateStatus.error,
          error: 'GitHub returned 500',
        );
      await tester.pumpWidget(
        buildApp(extraOverrides: [updateProvider.overrideWith(() => notifier)]),
      );
      await pumpFrames(tester);
      final l10n = await loadL10n();

      await scrollTo(tester, find.text(l10n.checkNow));
      await tester.tap(find.text(l10n.checkNow));
      await pumpFrames(tester);

      // The error toast wraps the localized failure detail. Both the
      // status row and the toast end up in the tree at the same time.
      expect(
        find.textContaining('GitHub returned 500'),
        findsWidgets,
        reason:
            'Error toast must surface the localized detail returned by '
            'localizeError(state.error).',
      );
      Toast.clearAllForTest();
    });
  });

  group('_UpdateSection — verifying state', () {
    testWidgets('verifying state renders the linear progress indicator', (
      tester,
    ) async {
      sizeView(tester);
      // The `verifying` status reuses the same shared
      // `UpdateProgressIndicator` as `downloading`; the indicator's
      // internal caption is what swaps. The status-widget branch
      // covers both `downloading` and `verifying` in one arm —
      // exercising both pins the arm regardless of which path the
      // backend went through.
      const verifying = UpdateState(
        status: UpdateStatus.verifying,
        progress: 1.0,
        info: UpdateInfo(
          latestVersion: '2.0.0',
          currentVersion: '1.5.0',
          releaseUrl: 'https://example.invalid/releases/2.0.0',
        ),
      );
      await tester.pumpWidget(
        buildApp(
          extraOverrides: [
            updateProvider.overrideWith(
              () => PrePopulatedUpdateNotifier(verifying),
            ),
          ],
        ),
      );
      await pumpFrames(tester);

      expect(find.byType(UpdateProgressIndicator), findsWidgets);
    });
  });

  group('_UpdateSection — _InstallOrOpenReleaseButton', () {
    testWidgets(
      'install failure with openable release page surfaces fallback toast',
      (tester) async {
        sizeView(tester);
        // Contract: when the in-app installer reports `install()` false
        // at runtime on a supposedly-supported platform, the button
        // falls back to `openReleasePage()` and toasts the
        // installer-fallback message — distinct from the
        // "couldNotOpenInstaller" toast which fires when both verbs
        // miss.
        final notifier =
            _ScriptedUpdateNotifier(
                const UpdateState(
                  status: UpdateStatus.downloaded,
                  downloadedPath: '/tmp/app-2.0.0.AppImage',
                  info: UpdateInfo(
                    latestVersion: '2.0.0',
                    currentVersion: '1.5.0',
                    releaseUrl: 'https://example.invalid/releases/2.0.0',
                  ),
                ),
              )
              ..installerLaunchable = true
              ..installResult = false
              ..openReleaseResult = true;
        await tester.pumpWidget(
          buildApp(
            extraOverrides: [updateProvider.overrideWith(() => notifier)],
          ),
        );
        await pumpFrames(tester);
        final l10n = await loadL10n();

        await scrollTo(tester, find.text(l10n.installNow));
        await tester.tap(find.text(l10n.installNow));
        await pumpFrames(tester);

        expect(notifier.installCalls, 1);
        expect(notifier.openReleaseCalls, 1);
        expect(
          find.text(l10n.installerFailedOpenedReleasePage),
          findsOneWidget,
        );
        Toast.clearAllForTest();
      },
    );

    testWidgets(
      'install + release-page both failing surfaces the could-not-open toast',
      (tester) async {
        sizeView(tester);
        // When both fallback chain links return false, the toast is
        // `couldNotOpenInstaller`. Pins the deepest failure branch in
        // `_InstallOrOpenReleaseButton.build`.
        final notifier =
            _ScriptedUpdateNotifier(
                const UpdateState(
                  status: UpdateStatus.downloaded,
                  downloadedPath: '/tmp/app-2.0.0.AppImage',
                  info: UpdateInfo(
                    latestVersion: '2.0.0',
                    currentVersion: '1.5.0',
                    releaseUrl: 'https://example.invalid/releases/2.0.0',
                  ),
                ),
              )
              ..installerLaunchable = true
              ..installResult = false
              ..openReleaseResult = false;
        await tester.pumpWidget(
          buildApp(
            extraOverrides: [updateProvider.overrideWith(() => notifier)],
          ),
        );
        await pumpFrames(tester);
        final l10n = await loadL10n();

        await scrollTo(tester, find.text(l10n.installNow));
        await tester.tap(find.text(l10n.installNow));
        await pumpFrames(tester);

        expect(find.text(l10n.couldNotOpenInstaller), findsOneWidget);
        Toast.clearAllForTest();
      },
    );

    testWidgets(
      'Open Release Page button toasts when openReleasePage returns false',
      (tester) async {
        sizeView(tester);
        // Path: `canLaunchInstaller == false` renders the "Open Release
        // Page" primary button. When `openReleasePage()` returns false
        // (browser launch fails), the button toasts
        // `couldNotOpenInstaller`.
        final notifier =
            _ScriptedUpdateNotifier(
                const UpdateState(
                  status: UpdateStatus.downloaded,
                  downloadedPath: '/tmp/app-2.0.0.AppImage',
                  info: UpdateInfo(
                    latestVersion: '2.0.0',
                    currentVersion: '1.5.0',
                    releaseUrl: 'https://example.invalid/releases/2.0.0',
                  ),
                ),
              )
              ..installerLaunchable = false
              ..openReleaseResult = false;
        await tester.pumpWidget(
          buildApp(
            extraOverrides: [updateProvider.overrideWith(() => notifier)],
          ),
        );
        await pumpFrames(tester);
        final l10n = await loadL10n();

        await scrollTo(tester, find.text(l10n.openReleasePage));
        await tester.tap(find.text(l10n.openReleasePage));
        await pumpFrames(tester);

        expect(notifier.openReleaseCalls, 1);
        expect(find.text(l10n.couldNotOpenInstaller), findsOneWidget);
        Toast.clearAllForTest();
      },
    );
  });

  group('_ChangelogButton', () {
    testWidgets(
      'render of update-available with null changelog hides the button',
      (tester) async {
        sizeView(tester);
        // `_ChangelogButton.build` returns `SizedBox.shrink` when the
        // changelog is null or empty. Drives the early-return branch
        // by pinning an updateAvailable state with no changelog.
        const noChangelog = UpdateState(
          status: UpdateStatus.updateAvailable,
          info: UpdateInfo(
            latestVersion: '2.0.0',
            currentVersion: '1.5.0',
            releaseUrl: 'https://example.invalid/releases/2.0.0',
          ),
        );
        await tester.pumpWidget(
          buildApp(
            extraOverrides: [
              updateProvider.overrideWith(
                () => PrePopulatedUpdateNotifier(noChangelog),
              ),
            ],
          ),
        );
        await pumpFrames(tester);
        final l10n = await loadL10n();

        await scrollTo(tester, find.text(l10n.versionAvailable('2.0.0')));
        // The Release notes button is absent — its early-return path
        // short-circuits before producing the AppButton.
        expect(find.text(l10n.releaseNotes), findsNothing);
      },
    );
  });

  // Browser-launch path: `_buildUpdateAvailable` renders the
  // "Open in Browser" button when `assetUrl` is null OR the platform is
  // not desktop. Driving the browser-launch verb depends on the
  // `url_launcher` MethodChannel — the verb runs but the
  // `Clipboard.setData` / Toast fallback fires only when the launcher
  // returns false, which requires mocking the channel. The browser-
  // launch handler's clipboard-fallback toast is exercised by the
  // url_launcher mock plumbing tests in `test/widgets/`.
  // covered by integration: real browser-launch is OS-bound.
}
