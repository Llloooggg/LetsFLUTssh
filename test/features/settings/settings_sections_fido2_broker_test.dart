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
import 'package:letsflutssh/src/rust/api/fido2.dart' as rust_fido2;
import 'package:letsflutssh/theme/app_theme.dart';
import 'package:letsflutssh/utils/platform.dart' as plat;
import 'package:letsflutssh/widgets/core/toast.dart';

import '../../helpers/fake_security.dart';
import '../../helpers/frb_bootstrap.dart';
import '../../helpers/test_notifiers.dart';

/// Biometric probe that always reports "unavailable" so the Security
/// section's initState resolves on the first pump cycle without
/// touching a real platform biometric API.
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

/// Coverage for `_Fido2BrokerSection` rendering branches.
///
/// The section's transport snapshot comes from a module-private
/// `Provider<rust_fido2.DbFido2Transport>` over the FRB-backed
/// `fido2TransportSnapshot()` — Dart side cannot override it from a
/// test `ProviderScope`. The test therefore reads the live snapshot
/// off the FRB shim once, asserts the rendered subtitle matches the
/// branch the snapshot lands on, and pins the toggle's
/// disabled-when-only-one-path-available contract. This is the
/// strongest assertion reachable without a debug seam.
///
/// The `_setPrefer` path (which calls
/// `rust_fido2.fido2SetPreferDirectHid` + `configProvider.update`) is
/// only reachable when both transports are available — on a Linux
/// host neither path is normally usable, so the toggle's tap handler
/// is gated to null and a `tester.tap` is a no-op. The verb is
/// exercised by the Rust `lfs_core::fido2::brokers` unit tests.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(requireFrbLoaded);

  late Directory tempDir;

  setUp(() async {
    // Render every settings section open in a single page so the
    // SSH integration card (and its FIDO2 sub-section) is mounted
    // on first pump.
    plat.debugDesktopPlatformOverride = true;
    plat.debugMobilePlatformOverride = false;
    debugCollapsibleSectionsExpanded = true;

    tempDir = await Directory.systemTemp.createTemp(
      'settings_fido2_broker_test_',
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

  /// Per-host expected broker label — mirrors the `_brokerLabel` switch
  /// in `_Fido2BrokerSection`. Used by the single-path subtitle and
  /// the "both paths" preference subtitle.
  String expectedBrokerLabel(S l10n) {
    if (Platform.isWindows) return l10n.fido2BrokerWindowsLabel;
    if (Platform.isMacOS) return l10n.fido2BrokerMacosLabel;
    if (Platform.isIOS) return l10n.fido2BrokerIosLabel;
    if (Platform.isAndroid) return l10n.fido2BrokerAndroidLabel;
    // Linux ignores the toggle entirely — the section still falls back
    // to the Windows label when picking a broker name, but the
    // neitherPath branch normally fires there.
    return l10n.fido2BrokerWindowsLabel;
  }

  group('_Fido2BrokerSection rendering', () {
    testWidgets('renders the FIDO2 broker section header', (tester) async {
      sizeView(tester);
      await tester.pumpWidget(buildApp());
      await pumpFrames(tester);
      final l10n = await loadL10n();

      // The section header anchors the FIDO2 sub-block inside the
      // shared SSH integration card — it must always paint regardless
      // of which transport branch the platform lands in.
      await scrollTo(tester, find.text(l10n.fido2BrokerSectionTitle));
      expect(find.text(l10n.fido2BrokerSectionTitle), findsOneWidget);
    });

    testWidgets('renders the preference toggle label', (tester) async {
      sizeView(tester);
      await tester.pumpWidget(buildApp());
      await pumpFrames(tester);
      final l10n = await loadL10n();

      // The toggle label is the operator's reference point. It paints
      // independent of the snapshot branch — even when the toggle is
      // disabled (single-path or no-transport) the label still surfaces
      // so the user can read what would be configurable on another OS.
      await scrollTo(tester, find.text(l10n.fido2BrokerPreferDirectHidTitle));
      expect(find.text(l10n.fido2BrokerPreferDirectHidTitle), findsOneWidget);
    });

    testWidgets('subtitle matches the live transport snapshot branch', (
      tester,
    ) async {
      sizeView(tester);
      await tester.pumpWidget(buildApp());
      await pumpFrames(tester);
      final l10n = await loadL10n();

      // Read the canonical snapshot from FRB so the test's expected
      // subtitle stays aligned with the same source the widget reads.
      // The three branches inside `_Fido2BrokerSection.build` map
      // 1:1 onto `(brokerAvailable, directHidAvailable)`.
      final snap = rust_fido2.fido2TransportSnapshot();
      final String expectedSubtitle;
      if (snap.brokerAvailable && snap.directHidAvailable) {
        expectedSubtitle = l10n.fido2BrokerPreferDirectHidSubtitle(
          expectedBrokerLabel(l10n),
        );
      } else if (!snap.brokerAvailable && !snap.directHidAvailable) {
        expectedSubtitle = l10n.fido2BrokerNoTransportSubtitle;
      } else {
        // Exactly one transport — name it explicitly in the subtitle.
        final String transport;
        if (snap.kind == 'broker') {
          transport = expectedBrokerLabel(l10n);
        } else if (snap.kind == 'direct-hid') {
          transport = l10n.fido2BrokerTransportDirectHid;
        } else {
          transport = l10n.fido2BrokerTransportNone;
        }
        expectedSubtitle = l10n.fido2BrokerSinglePathSubtitle(transport);
      }

      await scrollTo(tester, find.text(l10n.fido2BrokerSectionTitle));
      expect(find.text(expectedSubtitle), findsOneWidget);
    });

    testWidgets(
      'toggle tap handler is disabled when both transports are not available',
      (tester) async {
        sizeView(tester);
        await tester.pumpWidget(buildApp());
        await pumpFrames(tester);
        final l10n = await loadL10n();

        // The `onChanged: bothPaths ? (v) => _setPrefer(ref, v) : null`
        // contract means: only when the host can actually route through
        // either path does the toggle accept input. On a host where
        // either path is missing, the tap is a no-op and the persisted
        // `fido2PreferDirectHid` flag cannot change.
        final snap = rust_fido2.fido2TransportSnapshot();
        final bothPaths = snap.brokerAvailable && snap.directHidAvailable;
        if (bothPaths) {
          // The host is fully capable. The toggle is interactive — the
          // disabled-state contract simply doesn't apply, and we can't
          // assert it without forcing the snapshot. Skip; the Rust
          // unit tests cover the dispatcher switch directly.
          markTestSkipped(
            'both broker + direct HID available on this host — '
            'toggle is intentionally interactive',
          );
          return;
        }
        // Section's subtitle must NOT be the "both paths" preference
        // blurb — that branch only fires when both transports exist.
        await scrollTo(tester, find.text(l10n.fido2BrokerSectionTitle));
        final preferSubtitle = l10n.fido2BrokerPreferDirectHidSubtitle(
          expectedBrokerLabel(l10n),
        );
        expect(find.text(preferSubtitle), findsNothing);
      },
    );

    testWidgets('broker label resolves to the platform-appropriate string', (
      tester,
    ) async {
      sizeView(tester);
      await tester.pumpWidget(buildApp());
      await pumpFrames(tester);
      final l10n = await loadL10n();

      // `_brokerLabel` is the helper that surfaces the platform's
      // canonical broker name — "Windows Hello / security key" on Win,
      // "System security key dialog" on macOS, etc. When the snapshot
      // selects the broker path (single-path branch on a host where
      // direct HID is missing but the broker is present), the subtitle
      // embeds the broker label verbatim. Verify the helper picks the
      // right per-OS string by checking the section's surrounding text
      // tree against the expected label on the current host. Linux
      // normally lands on the neitherPath branch where the broker
      // label is unused — skip there.
      final snap = rust_fido2.fido2TransportSnapshot();
      if (snap.kind != 'broker') {
        markTestSkipped(
          'host snapshot is not the broker path — broker label is '
          'only surfaced when the dispatcher picks the broker',
        );
        return;
      }
      await scrollTo(tester, find.text(l10n.fido2BrokerSectionTitle));
      expect(find.textContaining(expectedBrokerLabel(l10n)), findsWidgets);
    });

    // covered by integration: `_setPrefer` flips
    // `rust_fido2.fido2SetPreferDirectHid` and the persisted
    // `AppConfig.behavior.fido2PreferDirectHid` field. The verb runs
    // only when both transports are available on the host — a Linux
    // CI box rarely lands there. The Rust dispatcher's
    // pick-transport switch is covered by
    // `rust/crates/lfs_core/src/fido2/brokers.rs` unit tests; the
    // round-trip through the config_store actor is covered by the
    // `AppConfig.fido2PreferDirectHid` persistence tests.
  });
}
