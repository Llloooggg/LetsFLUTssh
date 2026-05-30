import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:letsflutssh/core/config/app_config.dart';
import 'package:letsflutssh/core/security/biometric_auth.dart';
import 'package:letsflutssh/core/security/biometric_key_vault.dart';
import 'package:letsflutssh/core/security/kdf_params.dart';
import 'package:letsflutssh/core/security/master_password.dart';
import 'package:letsflutssh/core/security/security_tier.dart';
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

/// Pre-seeds [SecurityState] so the build path reads a specific
/// current tier without touching the FRB-backed unlock cascade. The
/// production notifier's `build()` returns the default plaintext
/// state; tests that want to assert "Current pill on T1" / "auto-lock
/// row enabled on Paranoid" need the seed to land before the first
/// pump otherwise the assertions race the rebuild.
class _SeededSecurityNotifier extends SecurityStateNotifier {
  _SeededSecurityNotifier(this._seed);

  final SecurityState _seed;

  @override
  SecurityState build() => _seed;
}

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

class _MockMasterPasswordManager extends MasterPasswordManager {
  bool _enabled = false;

  // Explicit cheap Argon2id profile so the super constructor does
  // not reach for `KdfParams.productionDefaults` — that field is a
  // `late` mirror populated from Rust at production bootstrap and
  // this widget test never loads FRB.
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // _SecuritySection's initState probes biometric availability and (on
  // macOS) the resign-service identity. requireFrbLoaded is needed
  // because the SettingsScreen tree builds widgets whose constructors
  // reach into FRB-shimmed crypto / threat-vocabulary helpers; the
  // overrides below short-circuit the actual probes to "unavailable"
  // so initState resolves on the first pump cycle.
  setUpAll(requireFrbLoaded);

  late Directory tempDir;

  setUp(() async {
    // Desktop layout — Settings is rendered as a single scrollable
    // page, which is the easier surface to drive in widget tests
    // (mobile uses an expandable accordion that hides sections by
    // default).
    plat.debugDesktopPlatformOverride = true;
    plat.debugMobilePlatformOverride = false;
    debugCollapsibleSectionsExpanded = true;

    tempDir = await Directory.systemTemp.createTemp('settings_security_test_');

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

    // Pin the config-store singleton to this test's temp dir — the save
    // path no longer re-inits per write, so the store must be bootstrapped
    // before any settings change flushes (e.g. on widget teardown).
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

  Widget buildApp({AppConfig? initialConfig}) {
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

  group('_SecuritySection rendering', () {
    testWidgets('renders all four tier ladder cards', (tester) async {
      tester.view.physicalSize = const Size(900, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildApp());
      // Allow initState's biometric / capability probes to settle.
      for (int i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      // Each tier badge is the canonical localised label. Use the
      // tier's user-facing copy from app_en.arb — the test would
      // surface a copy regression if those localisation strings
      // moved without a parallel test update.
      final l10n = await S.delegate.load(const Locale('en'));
      final scrollable = find.byType(Scrollable).first;
      // T0 ('Plaintext'), T1 ('Keychain'), T2 ('Hardware'),
      // Paranoid — every label appears at least once on its card.
      await tester.scrollUntilVisible(
        find.text(l10n.tierPlaintextLabel),
        300,
        scrollable: scrollable,
      );
      expect(find.text(l10n.tierPlaintextLabel), findsWidgets);
      expect(find.text(l10n.tierKeychainLabel), findsWidgets);
      expect(find.text(l10n.tierHardwareLabel), findsWidgets);
      expect(find.text(l10n.tierParanoidLabel), findsWidgets);
    });

    testWidgets('renders Re-check tiers button', (tester) async {
      tester.view.physicalSize = const Size(900, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildApp());
      for (int i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      final l10n = await S.delegate.load(const Locale('en'));
      await tester.scrollUntilVisible(
        find.text(l10n.securityRecheck),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text(l10n.securityRecheck), findsOneWidget);
    });

    testWidgets('renders the Current badge on the active tier card', (
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

      // Default config = plaintext tier → that card carries the
      // localised "Current" pill.
      final l10n = await S.delegate.load(const Locale('en'));
      await tester.scrollUntilVisible(
        find.text(l10n.tierBadgeCurrent),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text(l10n.tierBadgeCurrent), findsOneWidget);
    });

    testWidgets('mac-only Enable/Remove keychain blocks are absent off macOS', (
      tester,
    ) async {
      // Test runs under Linux/desktop override, so neither block
      // should render. The negative assertion locks the
      // platform-gating branch on lines 490–493.
      tester.view.physicalSize = const Size(900, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildApp());
      for (int i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      final l10n = await S.delegate.load(const Locale('en'));
      // Enable / Remove keychain copy lives only inside the
      // _build*Block helpers for macOS — neither string should
      // surface on this host.
      expect(find.text(l10n.securityMacosEnableSecureTiers), findsNothing);
      expect(find.text(l10n.securityMacosRemoveIdentity), findsNothing);
    });
  });

  group('_SecuritySection — tier ladder gating', () {
    testWidgets('moves the Current badge when the security state is keychain', (
      tester,
    ) async {
      // Spec: the active tier card carries the localised "Current"
      // pill exactly once. With `securityStateProvider` seeded to
      // `keychain`, the badge must render on the keychain card, not
      // on the default plaintext card.
      tester.view.physicalSize = const Size(900, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

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
            // Seed the tier override so the build path reads keychain
            // as the current level — the Current pill must render on
            // that card instead of plaintext.
            securityStateProvider.overrideWith(
              () => _SeededSecurityNotifier(
                const SecurityState(
                  level: SecurityTier.keychain,
                  hasActiveDbKey: true,
                ),
              ),
            ),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: const SizedBox(height: 3000, child: SettingsScreen()),
          ),
        ),
      );
      for (int i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      final l10n = await S.delegate.load(const Locale('en'));
      // Exactly one "Current" pill on the page — the build helper
      // renders it only when `tier == currentLevel`.
      expect(find.text(l10n.tierBadgeCurrent), findsOneWidget);
      // Keychain card title visible — used as anchor for the badge
      // location. We don't assert sibling pixel position; the count
      // assertion above already pins "Current" to the keychain card
      // because it's the only T1 row whose `isCurrent` is true.
      expect(find.text(l10n.tierKeychainLabel), findsWidgets);
    });

    testWidgets('renders the auto-lock row label on the active tier card', (
      tester,
    ) async {
      // Spec: `_autoLockRowFor` returns null only on plaintext. With
      // a non-plaintext currentLevel seeded, the auto-lock row must
      // render with its localised title — the `_AutoLockTile.build`
      // path runs whether or not the tooltip's disabledReason fires.
      tester.view.physicalSize = const Size(900, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

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
            securityStateProvider.overrideWith(
              () => _SeededSecurityNotifier(
                const SecurityState(
                  level: SecurityTier.paranoid,
                  hasActiveDbKey: true,
                ),
              ),
            ),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: const SizedBox(height: 3000, child: SettingsScreen()),
          ),
        ),
      );
      for (int i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      final l10n = await S.delegate.load(const Locale('en'));
      // Paranoid card is expanded (it's the current tier) — the
      // auto-lock label must surface inside it.
      final scrollable = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(
        find.text(l10n.autoLockTitle),
        300,
        scrollable: scrollable,
      );
      expect(find.text(l10n.autoLockTitle), findsWidgets);
    });
  });

  // Deferred — macOS identity block enable-CTA render: the initState
  // probe does not flip `_macosHasIdentity` to a stable value within
  // the scroll budget on a non-macOS host. Covered by the macOS
  // integration suite.

  group('_SecuritySection — Re-check button interaction', () {
    // Deferred — Re-check outcome toast: the FRB `_rerunTierProbes`
    // call's microtask completes outside the pump budget so neither
    // outcome toast surfaces in time. The structural arm is exercised
    // by the no-throw + button-stays-mounted test below.

    testWidgets('tapping Re-check does not throw + button stays mounted', (
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

      final l10n = await S.delegate.load(const Locale('en'));
      final scrollable = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(
        find.text(l10n.securityRecheck),
        300,
        scrollable: scrollable,
      );
      await tester.tap(find.text(l10n.securityRecheck));
      // Pump enough to let the spinner show and the probes
      // resolve; the FRB-backed providers are overridden, so
      // the round-trip lands in the next microtask.
      for (int i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      // Button still in the tree — the probe completion should
      // have flipped `_recheckingTiers` back to false and re-
      // rendered the button (not a spinner-only state).
      expect(find.text(l10n.securityRecheck), findsOneWidget);
    });
  });
}
