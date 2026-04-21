import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/biometric_auth.dart';
import 'package:letsflutssh/core/security/biometric_key_vault.dart';
import 'package:letsflutssh/core/security/lock_state.dart';
import 'package:letsflutssh/core/security/master_password.dart';
import 'package:letsflutssh/core/security/security_tier.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/providers/master_password_provider.dart';
import 'package:letsflutssh/providers/security_provider.dart';
import 'package:letsflutssh/widgets/lock_screen.dart';

class _FakeMasterPassword extends MasterPasswordManager {
  _FakeMasterPassword({required this.expectedPassword, required this.keyBytes});

  final String expectedPassword;
  final Uint8List keyBytes;
  int verifyAndDeriveCalls = 0;

  @override
  Future<Uint8List?> verifyAndDerive(
    String password, {
    bool useRateLimit = false,
  }) async {
    verifyAndDeriveCalls++;
    if (password != expectedPassword) return null;
    return keyBytes;
  }

  @override
  Future<bool> verify(String password) async =>
      (await verifyAndDerive(password)) != null;

  @override
  Future<Uint8List> deriveKey(String password) async {
    final key = await verifyAndDerive(password);
    if (key == null) {
      throw const MasterPasswordException('wrong password');
    }
    return key;
  }
}

class _NoBiometricVault extends BiometricKeyVault {
  @override
  Future<bool> isStored() async => false;

  @override
  Future<Uint8List?> read() async => null;
}

class _NoBiometricAuth extends BiometricAuth {
  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<BiometricAvailability> availability() async =>
      BiometricUnavailableReason.platformUnsupported;

  @override
  Future<bool> authenticate(String reason) async => false;
}

void main() {
  // Use an all-zero key — content doesn't matter for the contract, only
  // that the right bytes reach securityStateProvider.
  final zeroKey = Uint8List(32);

  testWidgets(
    'enter correct password → lockState flips to unlocked with derived key',
    (tester) async {
      final mp = _FakeMasterPassword(
        expectedPassword: 'letmein',
        keyBytes: zeroKey,
      );
      final container = ProviderContainer(
        overrides: [
          masterPasswordProvider.overrideWithValue(mp),
          biometricKeyVaultProvider.overrideWithValue(_NoBiometricVault()),
          biometricAuthProvider.overrideWithValue(_NoBiometricAuth()),
        ],
      );
      addTearDown(container.dispose);

      // Start locked.
      container.read(lockStateProvider.notifier).lock();
      expect(container.read(lockStateProvider), true);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            home: Scaffold(body: LockScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'letmein');
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();

      expect(
        mp.verifyAndDeriveCalls,
        1,
        reason:
            'unlock must run PBKDF2 exactly once — the old verify() + '
            'deriveKey() pair doubled unlock latency on mobile',
      );
      expect(
        container.read(lockStateProvider),
        false,
        reason: 'correct password must release the lock',
      );
      expect(
        container.read(securityStateProvider).level,
        SecurityTier.paranoid,
        reason: 'security level is promoted after unlock',
      );
      expect(
        container.read(securityStateProvider).encryptionKey,
        isNotNull,
        reason: 'derived key must land in securityStateProvider',
      );
    },
  );

  testWidgets('wrong password → stays locked and reveals the error label', (
    tester,
  ) async {
    final mp = _FakeMasterPassword(
      expectedPassword: 'real-secret',
      keyBytes: zeroKey,
    );
    final container = ProviderContainer(
      overrides: [
        masterPasswordProvider.overrideWithValue(mp),
        biometricKeyVaultProvider.overrideWithValue(_NoBiometricVault()),
        biometricAuthProvider.overrideWithValue(_NoBiometricAuth()),
      ],
    );
    addTearDown(container.dispose);
    container.read(lockStateProvider.notifier).lock();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          localizationsDelegates: S.localizationsDelegates,
          supportedLocales: S.supportedLocales,
          home: Scaffold(body: LockScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'nope');
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(mp.verifyAndDeriveCalls, 1);
    expect(container.read(lockStateProvider), true);

    // The localised error label must appear. We don't pin the exact
    // string (l10n is free to reword), just that the failure surfaces
    // visually — otherwise the user gets no feedback for a typo.
    final l10n = await S.delegate.load(const Locale('en'));
    expect(find.text(l10n.wrongPassword), findsOneWidget);
  });

  testWidgets(
    'empty password submission is a no-op (no verify call, lock stays)',
    (tester) async {
      final mp = _FakeMasterPassword(expectedPassword: 'x', keyBytes: zeroKey);
      final container = ProviderContainer(
        overrides: [
          masterPasswordProvider.overrideWithValue(mp),
          biometricKeyVaultProvider.overrideWithValue(_NoBiometricVault()),
          biometricAuthProvider.overrideWithValue(_NoBiometricAuth()),
        ],
      );
      addTearDown(container.dispose);
      container.read(lockStateProvider.notifier).lock();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            home: Scaffold(body: LockScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // No text entered — tap the button.
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();

      expect(
        mp.verifyAndDeriveCalls,
        0,
        reason: 'empty input must not trigger a verify round-trip',
      );
      expect(container.read(lockStateProvider), true);
    },
  );
}
