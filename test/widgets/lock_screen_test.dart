import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/app/tier_unlocked_listener.dart';
import 'package:letsflutssh/core/security/biometric_auth.dart';
import 'package:letsflutssh/widgets/app_button.dart';
import 'package:letsflutssh/core/security/biometric_key_vault.dart';
import 'package:letsflutssh/providers/lock_state.dart';
import 'package:letsflutssh/core/security/master_password.dart';
import 'package:letsflutssh/core/security/tier_unlock_attempt.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/providers/master_password_provider.dart';
import 'package:letsflutssh/providers/security_provider.dart';
import 'package:letsflutssh/widgets/lock_screen.dart';

/// Test-only listener that resolves `awaitNextUnlock` immediately
/// with `unlocked`. The real listener + production
/// `LockStateNotifier` both subscribe to `AppBus`, which requires
/// the FRB native lib (not loaded in flutter_test); a real
/// `awaitNextUnlock` future would never complete. The fake
/// short-circuits so the lock-screen tests can pump through the
/// orchestrator round-trip; the parallel `BusEvent::UnlockCascadeReady`
/// flip the production notifier consumes is staged by the fake
/// master-password manager on a successful `unlockAttempt`.
class _ImmediateListener extends TierUnlockedListener {
  _ImmediateListener(super.ref);

  @override
  void start() {}

  @override
  Future<TierUnlockOutcome> awaitNextUnlock({bool onlyUnlocked = false}) =>
      Future.value(TierUnlockOutcome.unlocked);

  @override
  void cancelPending() {}

  @override
  void stop() {}
}

class _FakeMasterPassword extends MasterPasswordManager {
  _FakeMasterPassword({
    required this.expectedPassword,
    required this.keyBytes,
    this.onStaged,
  });

  final String expectedPassword;
  final Uint8List keyBytes;

  /// Called inside `unlockAttempt` when the password matches —
  /// mirrors the side-effect chain Rust's `run_post_unlock_cascade`
  /// drives off a staged key (publishes the store-changed events
  /// and `BusEvent::UnlockCascadeReady`). The lock-screen tests use
  /// this hook to stage the overlay flip through
  /// `LockStateNotifier.debugForceUnlocked` since the real bus event
  /// can't fire without the FRB native lib.
  final void Function()? onStaged;

  int unlockAttemptCalls = 0;

  bool _matches(Uint8List password) {
    final expected = utf8.encode(expectedPassword);
    if (expected.length != password.length) return false;
    for (var i = 0; i < expected.length; i++) {
      if (expected[i] != password[i]) return false;
    }
    return true;
  }

  @override
  Future<TierUnlockAttempt> unlockAttempt(Uint8List password) async {
    unlockAttemptCalls++;
    if (_matches(password)) {
      onStaged?.call();
      return TierUnlockAttempt.staged;
    }
    return TierUnlockAttempt.wrongSecret;
  }

  @override
  Future<Uint8List?> verifyAndDerive(Uint8List password) async {
    return _matches(password) ? keyBytes : null;
  }

  @override
  Future<bool> verify(Uint8List password) async => _matches(password);
}

class _NoBiometricVault extends BiometricKeyVault {
  @override
  Future<bool> isStored() async => false;

  @override
  Future<bool> readToActive() async => false;
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

// Biometric success / cancellation stubs were removed along with the
// LockScreen biometric surface — Paranoid (the tier driving this
// screen) opts out of biometric by design, so no fingerprint auto-
// trigger and no retry button survive. The `_NoBiometric*` stubs
// above are still used by the password-path tests to override the
// providers that the old LockScreen used to consume; keeping them
// around rather than dropping overrides entirely makes those tests
// robust to a future tier that does route biometric through this
// screen.

void main() {
  // Use an all-zero key — content doesn't matter for the contract, only
  // that the right bytes reach securityStateProvider.
  final zeroKey = Uint8List(32);

  testWidgets(
    'enter correct password → lockState flips to unlocked with derived key',
    (tester) async {
      late final ProviderContainer container;
      final mp = _FakeMasterPassword(
        expectedPassword: 'letmein',
        keyBytes: zeroKey,
        // Mirror Rust's `run_post_unlock_cascade` → `UnlockCascadeReady`
        // bus event that `LockStateNotifier` flips on in production.
        // The FRB native lib isn't loaded under flutter_test so the
        // real event never lands; staging the same transition through
        // the test seam keeps the contract under observation.
        onStaged: () =>
            container.read(lockStateProvider.notifier).debugForceUnlocked(),
      );
      container = ProviderContainer(
        overrides: [
          masterPasswordProvider.overrideWithValue(mp),
          biometricKeyVaultProvider.overrideWithValue(_NoBiometricVault()),
          biometricAuthProvider.overrideWithValue(_NoBiometricAuth()),
          tierUnlockedListenerProvider.overrideWith(
            (ref) => _ImmediateListener(ref),
          ),
        ],
      );
      addTearDown(container.dispose);

      // Start locked.
      container.read(lockStateProvider.notifier).debugForceLocked();
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
        mp.unlockAttemptCalls,
        1,
        reason:
            'unlock must dispatch a single Paranoid orchestrator '
            'attempt — the old verify() + deriveKey() pair doubled '
            'unlock latency on mobile',
      );
      expect(
        container.read(lockStateProvider),
        false,
        reason:
            'correct password must release the lock — production flips '
            'on `BusEvent::UnlockCascadeReady` from Rust, the fake '
            'stages the same flip through `onStaged`.',
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
        tierUnlockedListenerProvider.overrideWith(
          (ref) => _ImmediateListener(ref),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(lockStateProvider.notifier).debugForceLocked();

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

    expect(mp.unlockAttemptCalls, 1);
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
          tierUnlockedListenerProvider.overrideWith(
            (ref) => _ImmediateListener(ref),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.read(lockStateProvider.notifier).debugForceLocked();

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
        mp.unlockAttemptCalls,
        0,
        reason: 'empty input must not trigger an orchestrator round-trip',
      );
      expect(container.read(lockStateProvider), true);
    },
  );

  testWidgets(
    'lock screen has no biometric affordance — Paranoid opts out by design',
    (tester) async {
      // Paranoid is the only tier that drives LockScreen (other
      // tiers have no mid-session re-auth surface yet), and Paranoid
      // does not expose biometric unlock — see ARCHITECTURE §3.6 →
      // Biometric unlock. The lock screen must therefore render no
      // fingerprint button, nothing to auto-trigger, nothing to
      // retry. Pin that invariant.
      final mp = _FakeMasterPassword(expectedPassword: 'x', keyBytes: zeroKey);
      final container = ProviderContainer(
        overrides: [masterPasswordProvider.overrideWithValue(mp)],
      );
      addTearDown(container.dispose);
      container.read(lockStateProvider.notifier).debugForceLocked();

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

      expect(find.byIcon(Icons.fingerprint), findsNothing);
      expect(container.read(lockStateProvider), true);
    },
  );
}
