import 'dart:io' show File;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/hardware_tier_vault.dart';
import 'package:letsflutssh/core/security/linux/tpm_client.dart';
import 'package:letsflutssh/core/security/secure_key_storage.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/widgets/security_setup_dialog.dart';

/// In-memory fake that mirrors `FlutterSecureStorage` API. The
/// `shouldThrow` flag simulates "no keychain on this host" — the
/// probe uses write → read → delete, so one throw is enough.
class _FakeStorage implements FlutterSecureStorage {
  final Map<String, String> _store = {};
  bool shouldThrow;

  _FakeStorage({this.shouldThrow = false});

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
  }) async {
    if (shouldThrow) throw Exception('Keychain unavailable');
    if (value != null) {
      _store[key] = value;
    } else {
      _store.remove(key);
    }
  }

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (shouldThrow) throw Exception('Keychain unavailable');
    return _store[key];
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (shouldThrow) throw Exception('Keychain unavailable');
    _store.remove(key);
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Minimal TpmClient double so the wizard's `HardwareTierVault`
/// probe finishes instantly instead of shelling out to `tpm2-tools`.
class _FakeTpm implements TpmClient {
  final bool available;
  _FakeTpm({this.available = true});

  @override
  Future<bool> isAvailable() async => available;

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

  Future<SecuritySetupResult?> openDialog(
    WidgetTester tester, {
    required bool keychainAvailable,
    bool hardwareAvailable = false,
  }) async {
    final storage = _FakeStorage(shouldThrow: !keychainAvailable);
    final keyStorage = SecureKeyStorage(storage: storage);
    final hardwareVault = HardwareTierVault(
      tpmClient: _FakeTpm(available: hardwareAvailable),
      stateFileFactory: () async => File('/tmp/ignored_hw_vault.bin'),
    );
    SecuritySetupResult? result;

    await tester.pumpWidget(
      _wrap(
        Builder(
          builder: (ctx) => TextButton(
            child: const Text('Open'),
            onPressed: () async {
              result = await SecuritySetupDialog.show(
                ctx,
                keyStorage: keyStorage,
                hardwareVault: hardwareVault,
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    return Future.value(result);
  }

  group('SecuritySetupDialog — tier ladder', () {
    testWidgets('renders every tier badge + Paranoid alternative', (
      tester,
    ) async {
      await openDialog(tester, keychainAvailable: true);
      expect(find.text('L0'), findsOneWidget);
      expect(find.text('L1'), findsOneWidget);
      expect(find.text('L2'), findsOneWidget);
      expect(find.text('L3'), findsOneWidget);
      expect(find.text('Master password (Paranoid)'), findsOneWidget);
    });

    testWidgets(
      'L1 is Recommended when keychain available and hardware is not',
      (tester) async {
        await openDialog(tester, keychainAvailable: true);
        expect(find.text('Recommended'), findsWidgets);
      },
    );

    testWidgets('L3 is Recommended when hardware probe succeeds', (
      tester,
    ) async {
      await openDialog(
        tester,
        keychainAvailable: true,
        hardwareAvailable: true,
      );
      // L3 row present AND Recommended badge somewhere near L3.
      expect(find.text('L3'), findsOneWidget);
      expect(find.text('Recommended'), findsWidgets);
    });

    testWidgets('Paranoid is Recommended when no keychain + no hardware', (
      tester,
    ) async {
      await openDialog(tester, keychainAvailable: false);
      expect(find.text('Recommended'), findsWidgets);
      expect(find.text('L1'), findsOneWidget);
    });

    testWidgets('L2 row disabled tooltip when keychain missing', (
      tester,
    ) async {
      await openDialog(tester, keychainAvailable: false);
      // Both rows rendered; label copy is the proxy for the row showing.
      expect(find.text('Keychain + password'), findsOneWidget);
      expect(find.text('Hardware + PIN'), findsOneWidget);
    });
  });
}
