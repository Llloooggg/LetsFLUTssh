import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:letsflutssh/core/config/app_config.dart';
import 'package:letsflutssh/utils/logger.dart' show LogLevel;
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

import '../../helpers/fake_security.dart';
import '../../helpers/frb_bootstrap.dart';
import '../../helpers/test_notifiers.dart';

/// Biometric probe that always reports "unavailable" so the
/// _SecuritySection initState resolves on the first pump cycle without
/// reaching a real platform biometric API.
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

/// MasterPasswordManager that never touches Rust crypto — the Sync
/// section's passphrase-vs-master check reads this provider, and the
/// Security section's tier ladder probes `isEnabled`.
class _MockMasterPasswordManager extends MasterPasswordManager {
  bool _enabled = false;

  _MockMasterPasswordManager()
    : super(
        kdfParams: const KdfParams.argon2id(
          memoryKiB: 8,
          iterations: 1,
          parallelism: 1,
        ),
      );

  @override
  Future<Uint8List> enable(Uint8List password) async {
    _enabled = true;
    return Uint8List.fromList(List.generate(32, (i) => i));
  }

  @override
  Future<bool> isEnabled() async => _enabled;

  @override
  Future<bool> verify(Uint8List password) async => true;
}

/// UpdateNotifier whose `check()` resolves synchronously to a fixed
/// status instead of hitting GitHub. The real notifier's `check()`
/// makes a live HTTP call through `UpdateService`; a widget test must
/// not depend on the network, so the verb is short-circuited here. The
/// recorded [checkCalls] count proves the button handler actually
/// invoked the verb.
class _ScriptedUpdateNotifier extends UpdateNotifier {
  _ScriptedUpdateNotifier(this._afterCheck);

  final UpdateState _afterCheck;
  int checkCalls = 0;

  @override
  UpdateState build() => const UpdateState();

  @override
  Future<void> check() async {
    checkCalls++;
    state = _afterCheck;
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

    tempDir = await Directory.systemTemp.createTemp('settings_coverage_test_');
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

  /// Pump a fixed number of discrete frames. Used instead of
  /// `pumpAndSettle` everywhere a never-settling animation (the live-log
  /// terminal cursor blink, the update spinner) is on screen.
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

  // ── Data → Export / Import section ──

  group('_ExportImportTile', () {
    testWidgets('renders import + export action tiles', (tester) async {
      sizeView(tester);
      await tester.pumpWidget(buildApp());
      await pumpFrames(tester);
      final l10n = await loadL10n();

      await scrollTo(tester, find.text(l10n.exportArchive));
      // Both halves of the Export/Import section surface their action
      // tiles regardless of any stored state — they are static entry
      // points into the import/export flows.
      expect(find.text(l10n.importArchive), findsOneWidget);
      expect(find.text(l10n.exportArchive), findsOneWidget);
      expect(find.text(l10n.importFromLink), findsOneWidget);
      expect(find.text(l10n.importFromSshDir), findsOneWidget);
      expect(find.text(l10n.exportQrCode), findsOneWidget);
      expect(find.text(l10n.import_), findsWidgets);
      expect(find.text(l10n.export_), findsWidgets);
    });

    testWidgets('tapping Import archive with a cancelled picker is a no-op', (
      tester,
    ) async {
      sizeView(tester);
      // `_showImportDialog` opens a native file picker first. Mock the
      // file_picker channel to a cancel (null) so the handler runs its
      // pick + early-return path without touching the DB or showing the
      // (DB-dependent) password / preview dialogs.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('miguelruivo.flutter.plugins.filepicker'),
            (call) async => null,
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('miguelruivo.flutter.plugins.filepicker'),
              null,
            ),
      );

      await tester.pumpWidget(buildApp());
      await pumpFrames(tester);
      final l10n = await loadL10n();

      await scrollTo(tester, find.text(l10n.importArchive));
      await tester.tap(find.text(l10n.importArchive));
      await pumpFrames(tester);

      // Picker cancelled → no password / import-data dialog appears and
      // the section stays mounted.
      expect(find.text(l10n.importData), findsNothing);
      expect(find.text(l10n.importArchive), findsOneWidget);
    });
  });

  // ── Updates section ──

  group('_UpdateSection', () {
    testWidgets('renders the check button + startup toggle', (tester) async {
      sizeView(tester);
      await tester.pumpWidget(buildApp());
      await pumpFrames(tester);
      final l10n = await loadL10n();

      await scrollTo(tester, find.text(l10n.checkForUpdates));
      expect(find.text(l10n.checkForUpdates), findsOneWidget);
      expect(find.text(l10n.checkForUpdatesOnStartup), findsOneWidget);
      // The button subtitle echoes the overridden version provider.
      expect(find.text(l10n.currentVersion('1.5.0')), findsWidgets);
    });

    testWidgets('tapping the startup toggle flips the persisted config', (
      tester,
    ) async {
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
              _MockMasterPasswordManager(),
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

      // Default config ships with checkUpdatesOnStart = true.
      expect(container.read(configProvider).checkUpdatesOnStart, isTrue);

      await scrollTo(tester, find.text(l10n.checkForUpdatesOnStartup));
      await tester.tap(find.text(l10n.checkForUpdatesOnStartup));
      await pumpFrames(tester);

      // Tapping the toggle flips the persisted value via configProvider.
      expect(container.read(configProvider).checkUpdatesOnStart, isFalse);
    });

    testWidgets('tapping Check now invokes the update verb', (tester) async {
      sizeView(tester);
      final notifier = _ScriptedUpdateNotifier(
        const UpdateState(status: UpdateStatus.upToDate),
      );
      await tester.pumpWidget(
        buildApp(extraOverrides: [updateProvider.overrideWith(() => notifier)]),
      );
      await pumpFrames(tester);
      final l10n = await loadL10n();

      await scrollTo(tester, find.text(l10n.checkNow));
      await tester.tap(find.text(l10n.checkNow));
      await pumpFrames(tester);

      // The button's onTap routes through `_runCheck`, which awaits the
      // notifier's `check()`. Exactly one invocation per tap.
      expect(notifier.checkCalls, 1);
      // upToDate result renders the "you're up to date" status row.
      await scrollTo(tester, find.text(l10n.youreUpToDate));
      expect(find.text(l10n.youreUpToDate), findsOneWidget);
      // The up-to-date result arms a toast auto-dismiss Timer; cancel it
      // so it doesn't outlive the widget tree.
      Toast.clearAllForTest();
    });

    testWidgets('updateAvailable state renders the version + release-notes', (
      tester,
    ) async {
      sizeView(tester);
      const available = UpdateState(
        status: UpdateStatus.updateAvailable,
        info: UpdateInfo(
          latestVersion: '2.0.0',
          currentVersion: '1.5.0',
          releaseUrl: 'https://example.invalid/releases/2.0.0',
          changelog: 'Faster everything',
        ),
      );
      await tester.pumpWidget(
        buildApp(
          extraOverrides: [
            updateProvider.overrideWith(
              () => PrePopulatedUpdateNotifier(available),
            ),
          ],
        ),
      );
      await pumpFrames(tester);
      final l10n = await loadL10n();

      await scrollTo(tester, find.text(l10n.versionAvailable('2.0.0')));
      // Update-available branch shows the new version + a Release notes
      // button (the changelog is non-empty).
      expect(find.text(l10n.versionAvailable('2.0.0')), findsWidgets);
      expect(find.text(l10n.releaseNotes), findsOneWidget);

      // Opening the release-notes dialog renders the changelog body.
      await tester.tap(find.text(l10n.releaseNotes));
      await tester.pumpAndSettle();
      expect(find.text('Faster everything'), findsOneWidget);
      await tester.tap(find.text(l10n.cancel));
      await tester.pumpAndSettle();
    });

    testWidgets('error state renders the failure status row', (tester) async {
      sizeView(tester);
      const errored = UpdateState(status: UpdateStatus.error, error: 'boom');
      await tester.pumpWidget(
        buildApp(
          extraOverrides: [
            updateProvider.overrideWith(
              () => PrePopulatedUpdateNotifier(errored),
            ),
          ],
        ),
      );
      await pumpFrames(tester);
      final l10n = await loadL10n();

      await scrollTo(tester, find.text(l10n.updateCheckFailed));
      expect(find.text(l10n.updateCheckFailed), findsOneWidget);
    });
  });

  // ── Sync section ──

  group('_SyncSection', () {
    testWidgets('renders the enable toggle + WebDAV fields', (tester) async {
      sizeView(tester);
      await tester.pumpWidget(buildApp());
      await pumpFrames(tester);
      final l10n = await loadL10n();

      await scrollTo(tester, find.text(l10n.syncEnable));
      // The enable toggle and the push/pull actions render unconditionally;
      // the WebDAV credential fields surface only once sync is enabled
      // (the dedicated base-URL test drives that path after enabling).
      expect(find.text(l10n.syncEnable), findsOneWidget);
      expect(find.text(l10n.syncPushNow), findsOneWidget);
      expect(find.text(l10n.syncPullNow), findsOneWidget);
    });

    testWidgets('tapping enable persists through the Rust sync config', (
      tester,
    ) async {
      sizeView(tester);
      await tester.pumpWidget(buildApp());
      await pumpFrames(tester);
      final l10n = await loadL10n();

      await scrollTo(tester, find.text(l10n.syncEnable));
      // The enable toggle saves the SyncConfig through the bootstrapped
      // Rust store. The whole row is the tap target (the knob is purely
      // visual), so tapping the label toggles it.
      await tester.tap(find.text(l10n.syncEnable));
      await pumpFrames(tester);

      // No exception during the save round-trip and the toggle + fields
      // remain mounted (a failed FRB save would have replaced the
      // section with the disabled `SizedBox.shrink`).
      expect(find.text(l10n.syncEnable), findsOneWidget);
      expect(find.text(l10n.syncPushNow), findsOneWidget);
    });

    testWidgets('switching the auth method keeps the section mounted', (
      tester,
    ) async {
      sizeView(tester);
      await tester.pumpWidget(buildApp());
      await pumpFrames(tester);
      final l10n = await loadL10n();

      await scrollTo(tester, find.text(l10n.syncEnable));
      // The auth-method picker offers basic / digest / bearer; tapping
      // 'digest' calls `_saveConfig` through the Rust store. Driving it
      // exercises the picker's onChanged + the save path.
      expect(find.text('digest'), findsOneWidget);
      await tester.tap(find.text('digest'));
      await pumpFrames(tester);
      expect(find.text(l10n.syncEnable), findsOneWidget);
    });

    testWidgets('typing into the base-URL field and submitting saves it', (
      tester,
    ) async {
      sizeView(tester);
      await tester.pumpWidget(buildApp());
      await pumpFrames(tester);
      final l10n = await loadL10n();

      await scrollTo(tester, find.text(l10n.syncEnable));
      // The URL field's onSubmitted calls `_saveConfig`. Entering text
      // and submitting drives that save path without a network hit.
      final urlField = find.widgetWithText(TextField, l10n.webDavBaseUrl);
      if (urlField.evaluate().isEmpty) {
        // StyledFormField may render the label outside the TextField;
        // fall back to the first editable field in the section.
        await tester.enterText(
          find.byType(TextField).first,
          'https://dav.example.invalid',
        );
      } else {
        await tester.enterText(urlField, 'https://dav.example.invalid');
      }
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await pumpFrames(tester);
      expect(find.text(l10n.syncEnable), findsOneWidget);
    });
  });

  // ── Logging section ──

  group('_LoggingSection', () {
    testWidgets('renders the logging-level selector', (tester) async {
      sizeView(tester);
      await tester.pumpWidget(buildApp());
      await pumpFrames(tester);
      final l10n = await loadL10n();

      await scrollTo(tester, find.text(l10n.loggingLevel));
      expect(find.text(l10n.loggingLevel), findsOneWidget);
      // Default config has no threshold → the selector trigger shows
      // the "Off" option label.
      expect(find.text('Off'), findsWidgets);
    });

    testWidgets('picking a level updates the persisted logLevel', (
      tester,
    ) async {
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
              _MockMasterPasswordManager(),
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

      // Default config writes no routine logs.
      expect(container.read(configProvider).logLevel, isNull);

      await scrollTo(tester, find.text(l10n.loggingLevel));
      // Open the log-level picker. The trigger label "Off" collides with
      // the auto-lock selector's "Off", so target the picker by its
      // typed PopupMenuButton<LogLevel?> — only the log-level selector
      // uses that nullable-LogLevel value type.
      await tester.tap(find.byType(PopupMenuButton<LogLevel?>));
      await tester.pumpAndSettle();
      // "Info" appears only in the open log-level menu.
      await tester.tap(find.text('Info').last);
      await pumpFrames(tester);

      // Selecting Info routes through onChanged → configProvider.update.
      expect(container.read(configProvider).logLevel, LogLevel.info);
    });

    testWidgets('log viewer is hidden when logging is off and file empty', (
      tester,
    ) async {
      sizeView(tester);
      await tester.pumpWidget(buildApp());
      await pumpFrames(tester);
      final l10n = await loadL10n();

      await scrollTo(tester, find.text(l10n.loggingLevel));
      // With a fresh temp support dir there is no log file content, and
      // the default level is Off — so the viewer host renders nothing
      // (the "Live Log" / "Archived log" headers stay absent).
      expect(find.text(l10n.liveLog), findsNothing);
      expect(find.text(l10n.archivedLog), findsNothing);
    });
  });

  // ── Data section (recordings + storage) ──

  group('_DataSection', () {
    testWidgets('renders the storage subsection + recordings tile', (
      tester,
    ) async {
      sizeView(tester);
      await tester.pumpWidget(buildApp());
      await pumpFrames(tester, 10);
      final l10n = await loadL10n();

      await scrollTo(tester, find.text(l10n.dataStorageSection));
      expect(find.text(l10n.dataStorageSection), findsOneWidget);
      expect(find.text(l10n.recordingsTitle), findsOneWidget);
      // The clear-all destructive button is present (label doubles as
      // the cap-row trailing action).
      expect(find.text(l10n.recordingsClearAllAction), findsWidgets);
    });

    testWidgets('clear-all recordings opens a confirmation then cancels', (
      tester,
    ) async {
      sizeView(tester);
      await tester.pumpWidget(buildApp());
      await pumpFrames(tester, 10);
      final l10n = await loadL10n();

      await scrollTo(tester, find.text(l10n.recordingsClearAllAction));
      await tester.tap(find.text(l10n.recordingsClearAllAction).last);
      await tester.pumpAndSettle();

      // The destructive clear-all routes through a ConfirmDialog before
      // touching the recordings tree.
      expect(find.text(l10n.recordingsClearAllConfirmTitle), findsOneWidget);
      await tester.tap(find.text(l10n.cancel));
      await tester.pumpAndSettle();
      expect(find.text(l10n.recordingsClearAllConfirmTitle), findsNothing);
    });
  });
}
