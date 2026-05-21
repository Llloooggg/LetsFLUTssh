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

  group('_SecuritySection — Re-check button interaction', () {
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
