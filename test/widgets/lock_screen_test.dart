import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/biometric_auth.dart';
import 'package:letsflutssh/widgets/app_button.dart';
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

class _StashedBiometricVault extends BiometricKeyVault {
  _StashedBiometricVault(this.key);
  final Uint8List key;

  @override
  Future<bool> isStored() async => true;

  @override
  Future<Uint8List?> read() async => key;
}

class _OkBiometricAuth extends BiometricAuth {
  int authenticateCalls = 0;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<BiometricAvailability> availability() async => null;

  @override
  Future<bool> authenticate(String reason) async {
    authenticateCalls++;
    return true;
  }
}

class _CancelledBiometricAuth extends BiometricAuth {
  int authenticateCalls = 0;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<BiometricAvailability> availability() async => null;

  @override
  Future<bool> authenticate(String reason) async {
    authenticateCalls++;
    return false;
  }
}

class _NullReadBiometricVault extends BiometricKeyVault {
  @override
  Future<bool> isStored() async => true;

  @override
  Future<Uint8List?> read() async => null;
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
      await tester.tap(find.byWidgetPredicate((w) => w is AppButton));
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
    await tester.tap(find.byWidgetPredicate((w) => w is AppButton));
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
      await tester.tap(find.byWidgetPredicate((w) => w is AppButton));
      await tester.pumpAndSettle();

      expect(
        mp.verifyAndDeriveCalls,
        0,
        reason: 'empty input must not trigger a verify round-trip',
      );
      expect(container.read(lockStateProvider), true);
    },
  );

  testWidgets('biometric auto-unlock releases the lock with the cached key', (
    tester,
  ) async {
    // Lock screen auto-fires biometric prompt on first frame (see
    // _tryBiometric in initState). When vault + platform both
    // succeed, the screen must flip to unlocked without the user
    // typing anything.
    final mp = _FakeMasterPassword(expectedPassword: 'x', keyBytes: zeroKey);
    final cachedKey = Uint8List.fromList(List.filled(32, 3));
    final auth = _OkBiometricAuth();
    final container = ProviderContainer(
      overrides: [
        masterPasswordProvider.overrideWithValue(mp),
        biometricKeyVaultProvider.overrideWithValue(
          _StashedBiometricVault(cachedKey),
        ),
        biometricAuthProvider.overrideWithValue(auth),
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

    expect(auth.authenticateCalls, 1);
    expect(container.read(lockStateProvider), false);
    expect(
      container.read(securityStateProvider).encryptionKey,
      equals(cachedKey),
    );
  });

  testWidgets('cancelled biometric keeps the lock + surfaces the error label', (
    tester,
  ) async {
    final mp = _FakeMasterPassword(expectedPassword: 'x', keyBytes: zeroKey);
    final cachedKey = Uint8List.fromList(List.filled(32, 4));
    final auth = _CancelledBiometricAuth();
    final container = ProviderContainer(
      overrides: [
        masterPasswordProvider.overrideWithValue(mp),
        biometricKeyVaultProvider.overrideWithValue(
          _StashedBiometricVault(cachedKey),
        ),
        biometricAuthProvider.overrideWithValue(auth),
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

    expect(auth.authenticateCalls, 1);
    expect(container.read(lockStateProvider), true);

    final l10n = await S.delegate.load(const Locale('en'));
    expect(find.text(l10n.biometricUnlockCancelled), findsOneWidget);
    // Retry button stays visible on cancel — the user-facing story
    // is "try again" not "type the password".
    expect(find.byIcon(Icons.fingerprint), findsOneWidget);
  });

  testWidgets(
    'biometric prompt succeeds but vault read returns null → failure label',
    (tester) async {
      // `BiometricKeyVault.read` can return null even after a successful
      // prompt — for example Apple's `biometryCurrentSet` invalidation
      // after re-enrolment. The lock screen has to surface that as a
      // visible failure (distinct from a user cancellation) instead of
      // silently staying locked.
      final mp = _FakeMasterPassword(expectedPassword: 'x', keyBytes: zeroKey);
      final auth = _OkBiometricAuth();
      final container = ProviderContainer(
        overrides: [
          masterPasswordProvider.overrideWithValue(mp),
          biometricKeyVaultProvider.overrideWithValue(
            _NullReadBiometricVault(),
          ),
          biometricAuthProvider.overrideWithValue(auth),
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

      expect(auth.authenticateCalls, 1);
      expect(container.read(lockStateProvider), true);

      final l10n = await S.delegate.load(const Locale('en'));
      expect(find.text(l10n.biometricUnlockFailed), findsOneWidget);
    },
  );

  testWidgets('biometric retry button re-runs the prompt after cancellation', (
    tester,
  ) async {
    final mp = _FakeMasterPassword(expectedPassword: 'x', keyBytes: zeroKey);
    final cachedKey = Uint8List.fromList(List.filled(32, 4));
    final auth = _CancelledBiometricAuth();
    final container = ProviderContainer(
      overrides: [
        masterPasswordProvider.overrideWithValue(mp),
        biometricKeyVaultProvider.overrideWithValue(
          _StashedBiometricVault(cachedKey),
        ),
        biometricAuthProvider.overrideWithValue(auth),
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

    // One call from auto-trigger, second from the manual retry.
    expect(auth.authenticateCalls, 1);
    await tester.tap(find.byIcon(Icons.fingerprint));
    await tester.pumpAndSettle();
    expect(auth.authenticateCalls, 2);
  });
}
