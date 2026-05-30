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
import 'package:letsflutssh/src/rust/api/sync.dart' as rust_sync;
import 'package:letsflutssh/theme/app_theme.dart';
import 'package:letsflutssh/utils/platform.dart' as plat;
import 'package:letsflutssh/widgets/core/styled_form_field.dart';
import 'package:letsflutssh/widgets/core/toast.dart';

import '../../helpers/fake_security.dart';
import '../../helpers/frb_bootstrap.dart';
import '../../helpers/test_notifiers.dart';

/// Biometric probe that always reports "unavailable" so the security
/// section's initState resolves on the first pump cycle.
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

/// MasterPasswordManager whose `isEnabled` toggle controls whether the
/// passphrase-vs-master verify arm exercises the FRB verifyAndDerive
/// path or short-circuits. The verify flag drives the "matches the
/// master password" branch which surfaces the inline error toast.
class _ConfigurableMasterPasswordManager extends MasterPasswordManager {
  bool enabled;
  Uint8List? derivedKey;

  _ConfigurableMasterPasswordManager({this.enabled = false, this.derivedKey})
    : super(
        kdfParams: const KdfParams.argon2id(
          memoryKiB: 8,
          iterations: 1,
          parallelism: 1,
        ),
      );

  @override
  Future<bool> isEnabled() async => enabled;

  @override
  Future<Uint8List?> verifyAndDerive(Uint8List password) async => derivedKey;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(requireFrbLoaded);

  late Directory tempDir;

  setUp(() async {
    plat.debugDesktopPlatformOverride = true;
    plat.debugMobilePlatformOverride = false;
    debugCollapsibleSectionsExpanded = true;

    tempDir = await Directory.systemTemp.createTemp('settings_sync_extra_');
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

    // Pin the Rust config store + sync orchestrator to the temp dir.
    await bootstrapRustConfigStore();
    // Reset the sync config so each test starts from a clean
    // DbSyncConfig (no persisted timestamps or staged secrets).
    const fresh = rust_sync.DbSyncConfig(
      enabled: false,
      webdavUrl: '',
      webdavUsername: '',
      webdavPasswordRef: 'sync.webdav.password',
      webdavAuthMethod: 'basic',
      passphraseRef: 'sync.passphrase',
      remotePath: 'letsflutssh.lfs',
      lastPushedAtMs: 0,
      lastPulledAtMs: 0,
      lastPushedSha256: '',
      lastPushedEtag: '',
      lastPulledEtag: '',
      lastPulledSha256: '',
    );
    await rust_sync.syncConfigSet(value: fresh);
    await rust_sync.syncSecretDrop(id: 'sync.webdav.password');
    await rust_sync.syncSecretDrop(id: 'sync.passphrase');
  });

  tearDown(() async {
    plat.debugDesktopPlatformOverride = null;
    plat.debugMobilePlatformOverride = null;
    debugCollapsibleSectionsExpanded = false;
    Toast.clearAllForTest();

    await rust_sync.syncSecretDrop(id: 'sync.webdav.password');
    await rust_sync.syncSecretDrop(id: 'sync.passphrase');

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
    MasterPasswordManager? masterPassword,
    List<Override> extraOverrides = const [],
  }) {
    final config = initialConfig ?? AppConfig.defaults;
    return ProviderScope(
      overrides: [
        configProvider.overrideWith(() => PrePopulatedConfigNotifier(config)),
        appVersionProvider.overrideWith(() => FixedVersionNotifier('1.5.0')),
        masterPasswordProvider.overrideWithValue(
          masterPassword ?? _ConfigurableMasterPasswordManager(),
        ),
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

  Finder styledFieldFor(String label) => find.descendant(
    of: find.byWidgetPredicate((w) => w is StyledFormField && w.label == label),
    matching: find.byType(EditableText),
  );

  // ── _saveSecret arm: typed password persists into SecretStore ──

  // submitting a non-empty password test deferred — the
  // syncSecretPut FRB call settles past the pump cadence here so the
  // post-write `_passwordStaged` flip doesn't observe.

  // 'submitting an empty password drops the SecretStore entry' test
  // deferred — the empty-submit chain hangs the test runner past the
  // 10-min CI timeout because something in the syncSecretDrop call
  // path keeps a pump-loop alive. The underlying syncSecretDrop FRB
  // shim is exercised Rust-side.

  // ── _confirmPassphraseNotMaster arm: master disabled → save succeeds ──

  testWidgets(
    'submitting a passphrase with master password disabled saves it',
    (tester) async {
      sizeView(tester);
      // Master disabled → `_confirmPassphraseNotMaster` short-circuits
      // to true without reaching FRB, so the passphrase save persists.
      await tester.pumpWidget(
        buildApp(
          masterPassword: _ConfigurableMasterPasswordManager(enabled: false),
        ),
      );
      await pumpFrames(tester);
      final l10n = await loadL10n();

      await scrollTo(tester, find.text(l10n.syncEnable));
      await tester.enterText(
        styledFieldFor(l10n.syncPassphrase),
        'a-different-passphrase',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await pumpFrames(tester);

      expect(rust_sync.syncSecretHas(id: 'sync.passphrase'), isTrue);
    },
  );

  // ── _confirmPassphraseNotMaster arm: master matches → save blocked ──

  testWidgets(
    'submitting a passphrase that matches the master password does NOT save',
    (tester) async {
      sizeView(tester);
      // Master enabled + verifyAndDerive returns a key → the typed
      // passphrase collides with the master, save is blocked and the
      // SecretStore stays empty.
      await tester.pumpWidget(
        buildApp(
          masterPassword: _ConfigurableMasterPasswordManager(
            enabled: true,
            derivedKey: Uint8List.fromList(List.generate(32, (i) => i)),
          ),
        ),
      );
      await pumpFrames(tester);
      final l10n = await loadL10n();

      await scrollTo(tester, find.text(l10n.syncEnable));
      await tester.enterText(
        styledFieldFor(l10n.syncPassphrase),
        'collides-with-master',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await pumpFrames(tester);

      // Blocked save → SecretStore still holds nothing under the
      // passphrase id.
      expect(rust_sync.syncSecretHas(id: 'sync.passphrase'), isFalse);
      Toast.clearAllForTest();
    },
  );

  // ── _AuthMethodPicker hover + digest selection ──

  testWidgets('tapping the digest chip routes through the picker onChanged', (
    tester,
  ) async {
    sizeView(tester);
    await tester.pumpWidget(buildApp());
    await pumpFrames(tester);
    final l10n = await loadL10n();

    await scrollTo(tester, find.text(l10n.syncEnable));
    // Default config is 'basic'. Tapping the digest chip flips
    // `_authMethod` and re-saves through the Rust config_store actor.
    await tester.tap(find.text('digest'));
    await pumpFrames(tester);

    // The Rust store reflects the new method.
    final cfg = rust_sync.syncConfigGet();
    expect(cfg.webdavAuthMethod, 'digest');
  });

  // Deferred — settings-sync section deepening (pre-seeded password
  // drop, bearer chip, idempotent basic chip, empty remote-path
  // fallback, URL trim, enable-toggle persistence, formatted last-
  // pushed timestamp): the section's `_saveConfig` / `_saveSecret`
  // arms route through Rust verbs whose actor does not drain inside
  // the `pumpFrames` budget, leaving the test wedged for minutes per
  // case. Covered end-to-end by the WebDAV integration suite.

  // ── _AuthMethodPicker idempotent: tapping the current method stays on it ──

  testWidgets(
    'tapping the basic chip while basic is selected keeps it as the auth method',
    (tester) async {
      // Spec: the picker dispatches `onChanged(m)` unconditionally —
      // re-selecting the same value re-saves the same config without
      // mutating it. The downstream Rust config stays consistent.
      sizeView(tester);
      await tester.pumpWidget(buildApp());
      await pumpFrames(tester);
      final l10n = await loadL10n();

      await scrollTo(tester, find.text(l10n.syncEnable));
      // Default config seeds 'basic'; tapping it again must keep
      // the auth method at 'basic'.
      await tester.tap(find.text('basic'));
      await pumpFrames(tester);

      final cfg = rust_sync.syncConfigGet();
      expect(cfg.webdavAuthMethod, 'basic');
    },
  );

  // ── _AuthMethodPicker bearer arm ──

  testWidgets(
    'tapping the bearer chip flips the persisted auth method to bearer',
    (tester) async {
      // Spec: the picker exposes three values — basic / digest / bearer
      // — that map 1:1 to the `lfs_core::sync` wire grammar. The bearer
      // arm covers token-style WebDAV auth (Nextcloud app tokens etc.).
      sizeView(tester);
      await tester.pumpWidget(buildApp());
      await pumpFrames(tester);
      final l10n = await loadL10n();

      await scrollTo(tester, find.text(l10n.syncEnable));
      await tester.tap(find.text('bearer'));
      await pumpFrames(tester);

      final cfg = rust_sync.syncConfigGet();
      expect(cfg.webdavAuthMethod, 'bearer');
    },
  );

  // ── Initial-render contract: all three auth chips visible ──

  testWidgets('auth-method picker mounts all three chips on first render', (
    tester,
  ) async {
    // Spec: the picker hard-codes `['basic', 'digest', 'bearer']` —
    // the closed set the orchestrator accepts. A re-skin that drops
    // any chip would silently break the corresponding wire variant
    // for the user.
    sizeView(tester);
    await tester.pumpWidget(buildApp());
    await pumpFrames(tester);
    final l10n = await loadL10n();

    await scrollTo(tester, find.text(l10n.syncEnable));
    expect(find.text('basic'), findsOneWidget);
    expect(find.text('digest'), findsOneWidget);
    expect(find.text('bearer'), findsOneWidget);
  });

  // ── _SyncTimestampRow renders "Never run" for a zero timestamp ──

  testWidgets(
    'last-pushed / last-pulled rows render the "never run" sentinel on a fresh config',
    (tester) async {
      // Spec: `_formatMs` is skipped when the stored timestamp is 0;
      // the row falls back to the localized `syncNeverRun` text. The
      // setUp resets the sync config so both timestamps start at 0.
      sizeView(tester);
      await tester.pumpWidget(buildApp());
      await pumpFrames(tester);
      final l10n = await loadL10n();

      await scrollTo(tester, find.text(l10n.syncEnable));
      // Both the "Last pushed" and "Last pulled" rows render with the
      // localized "Never run" placeholder when no timestamp is set.
      expect(find.text(l10n.syncLastPushed(l10n.syncNeverRun)), findsOneWidget);
      expect(find.text(l10n.syncLastPulled(l10n.syncNeverRun)), findsOneWidget);
    },
  );

  // ── Push / pull verb dispatch ──
  // covered by integration: `syncStatusProvider.notifier.push()` /
  // `.pull()` hit a real WebDAV endpoint; the `_showResultToast` per-kind
  // arms (pushed / pull_applied / up_to_date / skipped / default) are
  // observable only end-to-end with a real server (or a Rust-side mock
  // that overrides the orchestrator's HTTP layer, which lives in
  // `lfs_core::sync::orchestrator`).
}
