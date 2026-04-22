import 'dart:io' show File;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/hardware_tier_vault.dart';
import 'package:letsflutssh/core/security/linux/tpm_client.dart';
import 'package:letsflutssh/core/security/secure_key_storage.dart';
import 'package:letsflutssh/core/security/security_bootstrap.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/widgets/security_setup_dialog.dart';

class _FakeStorage implements FlutterSecureStorage {
  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {}

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => null;

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {}

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeTpm implements TpmClient {
  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<Uint8List?> seal(
    Uint8List secret, {
    required Uint8List authValue,
  }) async => Uint8List.fromList([...authValue, ...secret]);

  @override
  Future<Uint8List?> unseal(
    Uint8List blob, {
    required Uint8List authValue,
  }) async => blob;

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _wrap(Widget child) => MaterialApp(
  localizationsDelegates: S.localizationsDelegates,
  supportedLocales: S.supportedLocales,
  home: Scaffold(body: child),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> openDialog(
    WidgetTester tester, {
    required SecurityCapabilities caps,
  }) async {
    final keyStorage = SecureKeyStorage(storage: _FakeStorage());
    final hardwareVault = HardwareTierVault(
      tpmClient: _FakeTpm(),
      stateFileFactory: () async => File('/tmp/ignored_hw_vault.bin'),
    );

    await tester.pumpWidget(
      _wrap(
        Builder(
          builder: (ctx) => TextButton(
            child: const Text('Open'),
            onPressed: () async {
              await SecuritySetupDialog.show(
                ctx,
                keyStorage: keyStorage,
                hardwareVault: hardwareVault,
                capabilitiesOverride: caps,
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  const allCaps = SecurityCapabilities(
    keychainAvailable: true,
    hardwareVaultAvailable: true,
    biometricAvailable: true,
  );
  const noKeychain = SecurityCapabilities(hardwareVaultAvailable: true);
  const noHardware = SecurityCapabilities(keychainAvailable: true);

  group('SecuritySetupDialog — 3-tier ladder', () {
    testWidgets('renders T0/T1/T2 badges + Paranoid alternative section', (
      tester,
    ) async {
      await openDialog(tester, caps: allCaps);
      expect(find.text('T0'), findsOneWidget);
      expect(find.text('T1'), findsOneWidget);
      expect(find.text('T2'), findsOneWidget);
      expect(find.text('P'), findsOneWidget);
    });

    testWidgets('"Compare all tiers" button is present in the header', (
      tester,
    ) async {
      await openDialog(tester, caps: allCaps);
      final context = tester.element(find.byType(SecuritySetupDialog));
      expect(find.text(S.of(context).compareAllTiers), findsWidgets);
    });

    testWidgets('T1 row disabled-subtitle text when keychain missing', (
      tester,
    ) async {
      // Default `SecurityCapabilities.keychainProbe` is
      // `KeyringProbeResult.probeFailed` (the classified fallback
      // when no probe ran); the wizard prefers that classified copy
      // over the generic `tierKeychainUnavailable` string. If a
      // platform ever classifies the failure more specifically the
      // test fixture's `keychainProbe` override keeps this expectation
      // narrow.
      await openDialog(tester, caps: noKeychain);
      final context = tester.element(find.byType(SecuritySetupDialog));
      expect(find.text(S.of(context).keyringProbeFailed), findsOneWidget);
    });

    testWidgets(
      'T2 row disabled-subtitle text when hardware vault unavailable',
      (tester) async {
        // Same reasoning as the T1 test above: the default
        // `hardwareProbeCode` is `'unknown'`, which
        // `decodeHardwareProbeCode` maps to `HardwareProbeDetail.generic`
        // and `hardwareProbeDetailText` maps to
        // `firstLaunchSecurityHardwareUnavailableGeneric`. The
        // classified copy is preferred over the generic
        // `tierHardwareUnavailable` string.
        await openDialog(tester, caps: noHardware);
        final context = tester.element(find.byType(SecuritySetupDialog));
        expect(
          find.text(
            S.of(context).firstLaunchSecurityHardwareUnavailableGeneric,
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'submit button renders (Enable on first-launch, Apply from Settings)',
      (tester) async {
        await openDialog(tester, caps: allCaps);
        final context = tester.element(find.byType(SecuritySetupDialog));
        // The "Continue with Recommended" label lied when a
        // non-recommended tier was selected. Replaced with a plain
        // Enable (first-launch, no currentTier) / Apply (Settings
        // edit path) split. The test no longer cares which of the
        // two is visible — only that exactly one submit CTA renders.
        final enable = find.text(S.of(context).securitySetupEnable);
        final apply = find.text(S.of(context).securitySetupApply);
        expect(
          enable.evaluate().isNotEmpty || apply.evaluate().isNotEmpty,
          isTrue,
        );
      },
    );

    testWidgets('Recommended badge appears on the hardware-backed default', (
      tester,
    ) async {
      await openDialog(tester, caps: allCaps);
      final context = tester.element(find.byType(SecuritySetupDialog));
      expect(find.text(S.of(context).recommendedBadge), findsOneWidget);
    });

    testWidgets(
      'reduced wizard banner shown when neither T1 nor T2 is reachable',
      (tester) async {
        const noOsVault = SecurityCapabilities(biometricAvailable: false);
        await openDialog(tester, caps: noOsVault);
        final context = tester.element(find.byType(SecuritySetupDialog));
        expect(find.text(S.of(context).wizardReducedBanner), findsOneWidget);
        // T1 / T2 rows are hidden on the reduced branch — only T0 and
        // Paranoid remain.
        expect(find.text('T1'), findsNothing);
        expect(find.text('T2'), findsNothing);
        expect(find.text('T0'), findsOneWidget);
        expect(find.text('P'), findsOneWidget);
      },
    );

    testWidgets('tapping the T0 row forces the plaintext ack panel', (
      tester,
    ) async {
      await openDialog(tester, caps: allCaps);
      final context = tester.element(find.byType(SecuritySetupDialog));
      // T0 → the plaintext acknowledgement checkbox renders only when
      // the row is selected.
      await tester.tap(find.text('T0'));
      await tester.pumpAndSettle();
      expect(find.byType(Checkbox), findsOneWidget);
      // Apply / Enable stays disabled until the ack box is ticked.
      final submit =
          find.text(S.of(context).securitySetupEnable).evaluate().isNotEmpty
          ? find.text(S.of(context).securitySetupEnable)
          : find.text(S.of(context).securitySetupApply);
      final btn = tester.widget<FilledButton>(
        find.ancestor(of: submit, matching: find.byType(FilledButton)),
      );
      expect(btn.onPressed, isNull);
    });

    testWidgets('tapping the Paranoid row shows the master-password form', (
      tester,
    ) async {
      await openDialog(tester, caps: allCaps);
      final context = tester.element(find.byType(SecuritySetupDialog));
      await tester.tap(find.text('P'));
      await tester.pumpAndSettle();
      // Paranoid always shows the secret form with a strength meter
      // and the honesty note explaining master-password semantics.
      expect(
        find.text(S.of(context).paranoidMasterPasswordNote),
        findsOneWidget,
      );
    });
  });
}
