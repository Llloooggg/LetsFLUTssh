import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:letsflutssh/core/config/app_config.dart';
import 'package:letsflutssh/core/logs/log_store.dart';
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
import 'package:letsflutssh/utils/logger.dart' show LogLevel;
import 'package:letsflutssh/utils/platform.dart' as plat;
import 'package:letsflutssh/widgets/core/styled_form_field.dart';
import 'package:letsflutssh/widgets/core/toast.dart';

import '../../helpers/fake_security.dart';
import '../../helpers/frb_bootstrap.dart';
import '../../helpers/test_notifiers.dart';

/// Biometric probe that reports the platform as unsupported so the
/// _SecuritySection initState resolves on the first pump cycle without
/// reaching a real platform biometric API. Mirrors the harness used by
/// the existing settings section tests.
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

/// MasterPasswordManager that never touches Rust crypto. The Sync
/// section's passphrase-vs-master guard reads this provider, and the
/// Security section's tier ladder probes `isEnabled`. Defaults to
/// "not enabled" so the passphrase guard short-circuits to "safe".
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

  @override
  Future<bool> verify(Uint8List password) async => true;
}

/// UpdateNotifier whose verbs resolve synchronously to a scripted
/// state instead of hitting GitHub / a real installer. Records each
/// verb call so a test can prove the button handler routed to it.
class _ScriptedUpdateNotifier extends UpdateNotifier {
  _ScriptedUpdateNotifier(this._initial);

  final UpdateState _initial;
  int downloadCalls = 0;
  int installCalls = 0;
  int openReleaseCalls = 0;
  int checkCalls = 0;

  /// Drives the `_InstallOrOpenReleaseButton` label branch — true
  /// renders "Install Now", false renders "Open Release Page".
  bool installerLaunchable = true;

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
  }

  @override
  Future<void> download({bool autoInstall = false}) async {
    downloadCalls++;
  }

  @override
  Future<bool> install() async {
    installCalls++;
    return true;
  }

  @override
  Future<bool> openReleasePage() async {
    openReleaseCalls++;
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(requireFrbLoaded);

  late Directory tempDir;

  setUp(() async {
    // Desktop layout renders Settings as a single scrollable page and
    // `debugCollapsibleSectionsExpanded` forces every collapsible
    // section open, so every section widget is in the tree at once.
    plat.debugDesktopPlatformOverride = true;
    plat.debugMobilePlatformOverride = false;
    debugCollapsibleSectionsExpanded = true;

    tempDir = await Directory.systemTemp.createTemp('settings_deep_test_');
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

    // The Sync section reads `sync_config_get()` synchronously in
    // initState and the data-section toggles flush through the Rust
    // config_store actor — both need the store pinned to this temp dir
    // before the screen mounts.
    await bootstrapRustConfigStore();
  });

  tearDown(() async {
    plat.debugDesktopPlatformOverride = null;
    plat.debugMobilePlatformOverride = null;
    debugCollapsibleSectionsExpanded = false;
    Toast.clearAllForTest();
    // The log viewer mounts the process-wide LogStore singleton and
    // seeds it from the on-disk log; wipe it so entries do not leak
    // into the next test's viewer.
    LogStore.instance.clearAll();

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

  /// Variant that surfaces the ProviderContainer so a test can read
  /// the persisted config back after a UI mutation.
  Widget buildAppWithContainer({
    required void Function(ProviderContainer) onContainer,
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
      child: Consumer(
        builder: (context, ref, _) {
          onContainer(ProviderScope.containerOf(context));
          return MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: const SizedBox(height: 3000, child: SettingsScreen()),
          );
        },
      ),
    );
  }

  Future<S> loadL10n() => S.delegate.load(const Locale('en'));

  /// Pump a fixed number of discrete frames. Used instead of
  /// `pumpAndSettle` everywhere a never-settling animation (the
  /// live-log terminal cursor blink, the update spinner) is on screen.
  Future<void> pumpFrames(WidgetTester tester, [int n = 8]) async {
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

  /// The editable field inside a [StyledFormField] is a [TextFormField]
  /// (which builds an inner [TextField]); the visible label is an
  /// uppercased sibling, not a descendant, so `widgetWithText` cannot
  /// reach it. Address the field by its owning StyledFormField's
  /// `label` to disambiguate it from every other section's inputs.
  Finder styledFieldFor(String label) => find.descendant(
    of: find.byWidgetPredicate((w) => w is StyledFormField && w.label == label),
    matching: find.byType(EditableText),
  );

  /// The uppercased label rendered above a StyledFormField input.
  Finder fieldLabel(String label) => find.text(label.toUpperCase());

  // ── Sync section — deeper interaction branches ──

  group('_SyncSection deep', () {
    testWidgets(
      'enabling sync persists enabled=true through the Rust sync config',
      (tester) async {
        sizeView(tester);
        await tester.pumpWidget(buildApp());
        await pumpFrames(tester);
        final l10n = await loadL10n();

        await scrollTo(tester, find.text(l10n.syncEnable));
        // The enable toggle saves the SyncConfig through the
        // bootstrapped Rust store; the whole row is the tap target.
        await tester.tap(find.text(l10n.syncEnable));
        await pumpFrames(tester);

        // After enabling, the section re-reads the config and the
        // WebDAV credential fields plus the auth-method picker stay
        // mounted (a failed FRB save would have collapsed the section
        // to a SizedBox.shrink and lost these fields). StyledFormField
        // renders its label as an uppercased sibling above the input.
        expect(fieldLabel(l10n.webDavBaseUrl), findsOneWidget);
        expect(fieldLabel(l10n.webDavUsername), findsOneWidget);
        expect(fieldLabel(l10n.syncRemotePath), findsOneWidget);
        // Auth-method picker offers all three wire values.
        expect(find.text('basic'), findsOneWidget);
        expect(find.text('digest'), findsOneWidget);
        expect(find.text('bearer'), findsOneWidget);
      },
    );

    testWidgets('typing base URL + username then submitting saves them', (
      tester,
    ) async {
      sizeView(tester);
      await tester.pumpWidget(buildApp());
      await pumpFrames(tester);
      final l10n = await loadL10n();

      await scrollTo(tester, fieldLabel(l10n.webDavBaseUrl));
      // Address each StyledFormField's editable by its owning label.
      await tester.enterText(
        styledFieldFor(l10n.webDavBaseUrl),
        'https://dav.example.invalid/dav',
      );
      // onSubmitted routes through `_saveConfig` — the value is trimmed
      // and written to the Rust store.
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await pumpFrames(tester);

      await tester.enterText(styledFieldFor(l10n.webDavUsername), 'alice');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await pumpFrames(tester);

      // The persisted text survives the save round-trip — `_refreshConfig`
      // re-reads the stored config and re-seeds the controllers, so the
      // typed values are still in the fields.
      expect(find.text('https://dav.example.invalid/dav'), findsOneWidget);
      expect(find.text('alice'), findsOneWidget);
    });

    testWidgets('switching the auth method to bearer keeps the section', (
      tester,
    ) async {
      sizeView(tester);
      await tester.pumpWidget(buildApp());
      await pumpFrames(tester);
      final l10n = await loadL10n();

      await scrollTo(tester, find.text(l10n.syncEnable));
      // Tapping 'bearer' fires the picker onChanged → setState +
      // `_saveConfig`. The save round-trips through the Rust store; the
      // section stays mounted and the bearer chip is still selectable.
      await tester.tap(find.text('bearer'));
      await pumpFrames(tester);
      expect(find.text('bearer'), findsOneWidget);
      expect(find.text(l10n.syncEnable), findsOneWidget);
    });

    testWidgets('Push now with sync unreachable surfaces an error toast', (
      tester,
    ) async {
      sizeView(tester);
      await tester.pumpWidget(buildApp());
      await pumpFrames(tester);
      final l10n = await loadL10n();

      // Enable sync first so a push attempt actually reaches the
      // orchestrator instead of being short-circuited as "disabled".
      await scrollTo(tester, find.text(l10n.syncEnable));
      await tester.tap(find.text(l10n.syncEnable));
      await pumpFrames(tester);

      await scrollTo(tester, find.text(l10n.syncPushNow));
      await tester.tap(find.text(l10n.syncPushNow));
      // The push verb hits the network (no WebDAV server configured) and
      // either throws (→ error toast) or returns a skipped result (→
      // info toast). Either way the verb resolves and clears `_busy`.
      await pumpFrames(tester, 12);

      // The button is re-enabled and the section is still mounted — the
      // finally block flipped `_busy` back to false and re-read config.
      expect(find.text(l10n.syncPushNow), findsOneWidget);
      // Whatever toast fired, cancel its auto-dismiss timer before the
      // tree tears down.
      Toast.clearAllForTest();
    });

    testWidgets('Pull now with sync unreachable resolves and re-enables', (
      tester,
    ) async {
      sizeView(tester);
      await tester.pumpWidget(buildApp());
      await pumpFrames(tester);
      final l10n = await loadL10n();

      await scrollTo(tester, find.text(l10n.syncEnable));
      await tester.tap(find.text(l10n.syncEnable));
      await pumpFrames(tester);

      await scrollTo(tester, find.text(l10n.syncPullNow));
      await tester.tap(find.text(l10n.syncPullNow));
      await pumpFrames(tester, 12);

      expect(find.text(l10n.syncPullNow), findsOneWidget);
      Toast.clearAllForTest();
    });

    testWidgets('timestamp rows render the never-run placeholder', (
      tester,
    ) async {
      sizeView(tester);
      await tester.pumpWidget(buildApp());
      await pumpFrames(tester);
      final l10n = await loadL10n();

      await scrollTo(tester, find.text(l10n.syncPushNow));
      // A fresh config has never pushed or pulled, so both timestamp
      // rows render the "never run" placeholder substituted into their
      // labels.
      expect(find.text(l10n.syncLastPushed(l10n.syncNeverRun)), findsOneWidget);
      expect(find.text(l10n.syncLastPulled(l10n.syncNeverRun)), findsOneWidget);
    });
  });

  // ── Logging section — level switching + viewer ──

  group('_LoggingSection deep', () {
    testWidgets('picking Warn then Error round-trips through configProvider', (
      tester,
    ) async {
      sizeView(tester);
      late ProviderContainer container;
      await tester.pumpWidget(
        buildAppWithContainer(onContainer: (c) => container = c),
      );
      await pumpFrames(tester);
      final l10n = await loadL10n();

      // Default config writes no routine logs.
      expect(container.read(configProvider).logLevel, isNull);

      await scrollTo(tester, find.text(l10n.loggingLevel));
      // The log-level picker is the only PopupMenuButton<LogLevel?> in
      // the tree — the auto-lock "Off" selector is a PopupMenuButton<int>.
      // The AppPopupSelect menu opens with `noAnimation`, so a single
      // frame surfaces the items. `pumpAndSettle` is avoided throughout:
      // once a level is set the live-log viewer mounts a never-settling
      // cursor blink that would deadlock it.
      await tester.tap(find.byType(PopupMenuButton<LogLevel?>));
      await pumpFrames(tester);
      await tester.tap(find.text('Warn').last);
      await pumpFrames(tester);
      expect(container.read(configProvider).logLevel, LogLevel.warn);

      await scrollTo(tester, find.text(l10n.loggingLevel));
      await tester.tap(find.byType(PopupMenuButton<LogLevel?>));
      await pumpFrames(tester);
      await tester.tap(find.text('Error').last);
      await pumpFrames(tester);
      expect(container.read(configProvider).logLevel, LogLevel.error);
    });
  });

  // ── Data section — recordings storage + clear-all arms ──

  group('_DataSection deep', () {
    testWidgets('recordings tile renders the cap + clear-all rows', (
      tester,
    ) async {
      sizeView(tester);
      await tester.pumpWidget(buildApp());
      await pumpFrames(tester, 12);
      final l10n = await loadL10n();

      await scrollTo(tester, find.text(l10n.recordingsTitle));
      // Storage subsection: the usage/cap row + the "Cap" sub-row with
      // the destructive clear-all action button.
      expect(find.text(l10n.recordingsTitle), findsOneWidget);
      expect(find.text(l10n.recordingsCapLabel), findsOneWidget);
      expect(find.text(l10n.recordingsClearAllAction), findsWidgets);
    });

    testWidgets('clear-all recordings confirm wipes through the Rust verb', (
      tester,
    ) async {
      sizeView(tester);
      await tester.pumpWidget(buildApp());
      await pumpFrames(tester, 12);
      final l10n = await loadL10n();

      await scrollTo(tester, find.text(l10n.recordingsClearAllAction));
      await tester.tap(find.text(l10n.recordingsClearAllAction).last);
      await tester.pumpAndSettle();

      // The destructive action opens a ConfirmDialog first.
      expect(find.text(l10n.recordingsClearAllConfirmTitle), findsOneWidget);
      // Confirming runs `recorder_clear_all_recordings` against the
      // (empty) recordings root and surfaces a success toast; the
      // dialog dismisses and the tile stays mounted.
      await tester.tap(find.text(l10n.recordingsClearAllAction).last);
      await pumpFrames(tester, 12);
      expect(find.text(l10n.recordingsClearAllConfirmTitle), findsNothing);
      expect(find.text(l10n.recordingsTitle), findsOneWidget);
      Toast.clearAllForTest();
    });

    testWidgets('changing the recordings cap round-trips through config', (
      tester,
    ) async {
      sizeView(tester);
      late ProviderContainer container;
      await tester.pumpWidget(
        buildAppWithContainer(onContainer: (c) => container = c),
      );
      await pumpFrames(tester, 12);
      final l10n = await loadL10n();

      // Default cap is the 500 MiB preset; pick a different one and
      // confirm the persisted config picked it up.
      final before = container.read(configProvider).recordingsStorageCapBytes;

      await scrollTo(tester, find.text(l10n.recordingsTitle));
      // The cap dropdown is the AppPopupSelect on the recordings row;
      // its trigger renders the currently-selected preset label.
      // Open it (tap the trigger) and pick the 1 GiB preset.
      await tester.tap(find.text(l10n.recordingsCapPreset500Mb).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.recordingsCapPreset1Gb).last);
      await pumpFrames(tester, 12);

      const oneGib = 1024 * 1024 * 1024;
      expect(container.read(configProvider).recordingsStorageCapBytes, oneGib);
      expect(
        container.read(configProvider).recordingsStorageCapBytes,
        isNot(before),
      );
      Toast.clearAllForTest();
    });
  });

  // ── Updates section — scripted notifier states ──

  group('_UpdateSection deep', () {
    testWidgets('downloading state renders the linear progress indicator', (
      tester,
    ) async {
      sizeView(tester);
      const downloading = UpdateState(
        status: UpdateStatus.downloading,
        progress: 0.4,
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
              () => PrePopulatedUpdateNotifier(downloading),
            ),
          ],
        ),
      );
      await pumpFrames(tester);

      // The downloading branch swaps the status row for the shared
      // progress indicator (also used by the first-launch dialog).
      expect(find.byType(LinearProgressIndicator), findsWidgets);
    });

    testWidgets('update-available drives skip / download / changelog buttons', (
      tester,
    ) async {
      sizeView(tester);
      final notifier = _ScriptedUpdateNotifier(
        const UpdateState(
          status: UpdateStatus.updateAvailable,
          info: UpdateInfo(
            latestVersion: '2.0.0',
            currentVersion: '1.5.0',
            releaseUrl: 'https://example.invalid/releases/2.0.0',
            assetUrl: 'https://example.invalid/releases/2.0.0/app.AppImage',
            changelog: 'Faster everything',
          ),
        ),
      );
      late ProviderContainer container;
      await tester.pumpWidget(
        buildAppWithContainer(
          onContainer: (c) => container = c,
          extraOverrides: [updateProvider.overrideWith(() => notifier)],
        ),
      );
      await pumpFrames(tester);
      final l10n = await loadL10n();

      // Desktop + an asset URL → the primary action is in-app install.
      await scrollTo(tester, find.text(l10n.downloadAndInstall));
      await tester.tap(find.text(l10n.downloadAndInstall));
      await pumpFrames(tester);
      expect(notifier.downloadCalls, 1);

      // Skip-this-version persists the skipped version into config.
      await scrollTo(tester, find.text(l10n.skipThisVersion));
      await tester.tap(find.text(l10n.skipThisVersion));
      await pumpFrames(tester);
      expect(container.read(configProvider).skippedVersion, '2.0.0');

      // Once skipped the button flips to "Unskip"; tapping clears it.
      await scrollTo(tester, find.text(l10n.unskip));
      await tester.tap(find.text(l10n.unskip));
      await pumpFrames(tester);
      expect(container.read(configProvider).skippedVersion, isNull);
    });

    testWidgets('downloaded state shows install action + opens changelog', (
      tester,
    ) async {
      sizeView(tester);
      final notifier = _ScriptedUpdateNotifier(
        const UpdateState(
          status: UpdateStatus.downloaded,
          downloadedPath: '/tmp/app-2.0.0.AppImage',
          info: UpdateInfo(
            latestVersion: '2.0.0',
            currentVersion: '1.5.0',
            releaseUrl: 'https://example.invalid/releases/2.0.0',
            changelog: 'Faster everything',
          ),
        ),
      )..installerLaunchable = true;
      await tester.pumpWidget(
        buildApp(extraOverrides: [updateProvider.overrideWith(() => notifier)]),
      );
      await pumpFrames(tester);
      final l10n = await loadL10n();

      // downloaded → the "Download complete" row + an Install Now
      // button (installer launchable) plus the changelog button.
      await scrollTo(tester, find.text(l10n.downloadComplete));
      expect(find.text(l10n.downloadComplete), findsOneWidget);
      expect(find.text(l10n.installNow), findsOneWidget);

      // The changelog button opens the release-notes dialog.
      await tester.tap(find.text(l10n.releaseNotes));
      await tester.pumpAndSettle();
      expect(find.text('Faster everything'), findsOneWidget);
      await tester.tap(find.text(l10n.cancel));
      await tester.pumpAndSettle();

      // Install Now routes to the notifier's install verb.
      await scrollTo(tester, find.text(l10n.installNow));
      await tester.tap(find.text(l10n.installNow));
      await pumpFrames(tester);
      expect(notifier.installCalls, 1);
    });

    testWidgets(
      'downloaded with no launchable installer offers Open Release Page',
      (tester) async {
        sizeView(tester);
        final notifier = _ScriptedUpdateNotifier(
          const UpdateState(
            status: UpdateStatus.downloaded,
            downloadedPath: '/tmp/app-2.0.0.AppImage',
            info: UpdateInfo(
              latestVersion: '2.0.0',
              currentVersion: '1.5.0',
              releaseUrl: 'https://example.invalid/releases/2.0.0',
            ),
          ),
        )..installerLaunchable = false;
        await tester.pumpWidget(
          buildApp(
            extraOverrides: [updateProvider.overrideWith(() => notifier)],
          ),
        );
        await pumpFrames(tester);
        final l10n = await loadL10n();

        // No launchable installer → the button label is the
        // browser-fallback action and routes to openReleasePage.
        await scrollTo(tester, find.text(l10n.openReleasePage));
        expect(find.text(l10n.installNow), findsNothing);
        await tester.tap(find.text(l10n.openReleasePage));
        await pumpFrames(tester);
        expect(notifier.openReleaseCalls, 1);
      },
    );

    testWidgets('signature-failure error renders the security warning', (
      tester,
    ) async {
      sizeView(tester);
      final notifier = _ScriptedUpdateNotifier(
        const UpdateState(
          status: UpdateStatus.error,
          error: InvalidReleaseSignatureException('bad sig'),
        ),
      );
      await tester.pumpWidget(
        buildApp(extraOverrides: [updateProvider.overrideWith(() => notifier)]),
      );
      await pumpFrames(tester);
      final l10n = await loadL10n();

      // A signature mismatch gets the security-styled presentation —
      // not the generic "update check failed" row — with a reinstall
      // action pointing at the Releases page.
      await scrollTo(tester, find.text(l10n.updateSecurityWarningTitle));
      expect(find.text(l10n.updateSecurityWarningTitle), findsOneWidget);
      await tester.tap(find.text(l10n.updateReinstallAction));
      await pumpFrames(tester);
      expect(notifier.openReleaseCalls, 1);
    });
  });

  // ── About subsection ──

  group('_AboutSection deep', () {
    testWidgets('renders app + source rows and copies on tap', (tester) async {
      sizeView(tester);
      await tester.pumpWidget(buildApp());
      await pumpFrames(tester);
      final l10n = await loadL10n();

      await scrollTo(tester, find.text(l10n.sourceCode));
      // The About section mirrors the version provider into its
      // subtitle and exposes the source-code row.
      expect(find.text(l10n.aboutSubtitle('1.5.0')), findsOneWidget);
      expect(find.text(l10n.sourceCode), findsOneWidget);

      // Tapping the source row copies the GitHub URL and toasts.
      await tester.tap(find.text(l10n.sourceCode));
      await pumpFrames(tester);
      expect(find.text(l10n.urlCopied), findsOneWidget);
      Toast.clearAllForTest();
    });
  });

  // ── Security section — desktop, keychain/biometric unavailable ──

  group('_SecuritySection deep', () {
    testWidgets('renders the four-tier ladder with the Current pill on T0', (
      tester,
    ) async {
      sizeView(tester);
      await tester.pumpWidget(buildApp());
      await pumpFrames(tester);
      final l10n = await loadL10n();

      await scrollTo(tester, find.text(l10n.tierPlaintextLabel));
      // Every tier badge renders; default config is the plaintext tier
      // so that card carries the localized "Current" pill.
      expect(find.text(l10n.tierPlaintextLabel), findsWidgets);
      expect(find.text(l10n.tierKeychainLabel), findsWidgets);
      expect(find.text(l10n.tierHardwareLabel), findsWidgets);
      expect(find.text(l10n.tierParanoidLabel), findsWidgets);
      expect(find.text(l10n.tierBadgeCurrent), findsOneWidget);
    });

    testWidgets('hardware tier card surfaces a disabled-with-reason state', (
      tester,
    ) async {
      sizeView(tester);
      await tester.pumpWidget(buildApp());
      // The hardware probe runs through FRB; pump generously so the
      // classified probe resolves and the card paints its reason.
      await pumpFrames(tester, 12);
      final l10n = await loadL10n();

      await scrollTo(tester, find.text(l10n.tierHardwareLabel));
      // On a CI / WSL host with no TPM / Secure Enclave the hardware
      // tier resolves unavailable; the card stays expandable but the
      // Select button is disabled. The Select-tier label still renders
      // on the reachable T0/Paranoid cards, so the ladder is live.
      expect(find.text(l10n.tierHardwareLabel), findsWidgets);
      // The re-check button is the section's always-present control.
      await scrollTo(tester, find.text(l10n.securityRecheck));
      expect(find.text(l10n.securityRecheck), findsOneWidget);
    });

    testWidgets('macOS-only identity blocks are absent off macOS', (
      tester,
    ) async {
      sizeView(tester);
      await tester.pumpWidget(buildApp());
      await pumpFrames(tester);
      final l10n = await loadL10n();

      await scrollTo(tester, find.text(l10n.securityRecheck));
      // Test runs under the Linux/desktop override, so neither the
      // Enable-secure-tiers nor the Remove-identity macOS block paints.
      expect(find.text(l10n.securityMacosEnableSecureTiers), findsNothing);
      expect(find.text(l10n.securityMacosRemoveIdentity), findsNothing);
    });
  });
}
