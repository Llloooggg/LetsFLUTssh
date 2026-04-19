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
      await openDialog(tester, caps: noKeychain);
      final context = tester.element(find.byType(SecuritySetupDialog));
      expect(find.text(S.of(context).tierKeychainUnavailable), findsOneWidget);
    });

    testWidgets(
      'T2 row disabled-subtitle text when hardware vault unavailable',
      (tester) async {
        await openDialog(tester, caps: noHardware);
        final context = tester.element(find.byType(SecuritySetupDialog));
        expect(
          find.text(S.of(context).tierHardwareUnavailable),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'Continue-style button renders (plain or with-recommended variant)',
      (tester) async {
        await openDialog(tester, caps: allCaps);
        final context = tester.element(find.byType(SecuritySetupDialog));
        final plain = find.text(S.of(context).securitySetupContinue);
        final withRec = find.text(S.of(context).continueWithRecommended);
        expect(
          plain.evaluate().isNotEmpty || withRec.evaluate().isNotEmpty,
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
  });
}
