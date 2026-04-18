import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/biometric_auth.dart';
import 'package:letsflutssh/core/security/biometric_key_vault.dart';
import 'package:letsflutssh/core/security/master_password.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/providers/security_provider.dart';
import 'package:letsflutssh/widgets/unlock_dialog.dart';

/// Biometric vault with no stashed key — forces the dialog onto the
/// password path the existing tests expect.
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

/// Biometric vault + auth that both succeed — drives the biometric-priority
/// path (auto-trigger on first frame, pop with cached key).
class _StashedBiometricVault extends BiometricKeyVault {
  final Uint8List key;

  _StashedBiometricVault(this.key);

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
  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<BiometricAvailability> availability() async => null;

  @override
  Future<bool> authenticate(String reason) async => false;
}

void main() {
  late Directory tempDir;
  late MasterPasswordManager manager;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('unlock_dlg_test_');
    manager = MasterPasswordManager(basePath: tempDir.path);
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  List<Override> defaultOverrides() => <Override>[
    biometricKeyVaultProvider.overrideWithValue(_NoBiometricVault()),
    biometricAuthProvider.overrideWithValue(_NoBiometricAuth()),
  ];

  Widget buildApp({
    required void Function(BuildContext) onPressed,
    List<Override>? overrides,
  }) {
    return ProviderScope(
      overrides: overrides ?? defaultOverrides(),
      child: MaterialApp(
        localizationsDelegates: S.localizationsDelegates,
        supportedLocales: S.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => onPressed(context),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
  }

  /// Open the dialog — enable master password first via runAsync
  /// (PBKDF2 isolate needs real async).
  Future<void> openDialog(
    WidgetTester tester, {
    required void Function(BuildContext) onPressed,
    List<Override>? overrides,
  }) async {
    await tester.runAsync(() => manager.enable('testpass'));
    await tester.pumpWidget(
      buildApp(onPressed: onPressed, overrides: overrides),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  // Note: tests that trigger PBKDF2 via the UI (wrong password, correct
  // password) are not feasible as widget tests because Isolate.run() does not
  // complete in Flutter's FakeAsync test environment. The PBKDF2 verify/derive
  // logic is covered by master_password_test.dart unit tests instead.

  group('UnlockDialog', () {
    testWidgets('shows title and description', (tester) async {
      await openDialog(
        tester,
        onPressed: (ctx) {
          UnlockDialog.show(ctx, manager: manager);
        },
      );

      expect(find.text('Master Password'), findsOneWidget);
      expect(
        find.text('Enter master password to unlock your saved credentials.'),
        findsOneWidget,
      );
    });

    testWidgets('shows password field', (tester) async {
      await openDialog(
        tester,
        onPressed: (ctx) {
          UnlockDialog.show(ctx, manager: manager);
        },
      );

      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('shows unlock button', (tester) async {
      await openDialog(
        tester,
        onPressed: (ctx) {
          UnlockDialog.show(ctx, manager: manager);
        },
      );

      expect(find.text('Unlock'), findsOneWidget);
    });

    testWidgets('shows forgot password button', (tester) async {
      await openDialog(
        tester,
        onPressed: (ctx) {
          UnlockDialog.show(ctx, manager: manager);
        },
      );

      expect(find.text('Forgot Password?'), findsOneWidget);
    });

    testWidgets('empty password does not submit', (tester) async {
      await openDialog(
        tester,
        onPressed: (ctx) {
          UnlockDialog.show(ctx, manager: manager);
        },
      );

      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();

      // Dialog should still be open
      expect(find.text('Master Password'), findsOneWidget);
    });

    testWidgets('visibility toggle works', (tester) async {
      await openDialog(
        tester,
        onPressed: (ctx) {
          UnlockDialog.show(ctx, manager: manager);
        },
      );

      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.obscureText, isTrue);

      await tester.tap(find.byIcon(Icons.visibility_off));
      await tester.pumpAndSettle();

      final updated = tester.widget<TextField>(find.byType(TextField));
      expect(updated.obscureText, isFalse);
    });

    testWidgets('forgot password shows confirmation dialog', (tester) async {
      await openDialog(
        tester,
        onPressed: (ctx) {
          UnlockDialog.show(ctx, manager: manager);
        },
      );

      await tester.tap(find.text('Forgot Password?'));
      await tester.pumpAndSettle();

      expect(find.text('Reset & Delete Credentials'), findsOneWidget);
    });

    testWidgets('forgot password cancel keeps unlock dialog', (tester) async {
      await openDialog(
        tester,
        onPressed: (ctx) {
          UnlockDialog.show(ctx, manager: manager);
        },
      );

      await tester.tap(find.text('Forgot Password?'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Master Password'), findsOneWidget);
    });

    testWidgets('dialog is not dismissible by back button', (tester) async {
      await openDialog(
        tester,
        onPressed: (ctx) {
          UnlockDialog.show(ctx, manager: manager);
        },
      );

      // PopScope(canPop: false) should prevent dismissal
      final popScope = tester.widget<PopScope>(find.byType(PopScope));
      expect(popScope.canPop, isFalse);
    });

    testWidgets('biometric retry button hidden when biometric unavailable', (
      tester,
    ) async {
      await openDialog(
        tester,
        onPressed: (ctx) {
          UnlockDialog.show(ctx, manager: manager);
        },
      );

      // No stashed key + unavailable auth → action surface hides the
      // retry button instead of rendering a dead control.
      expect(find.byIcon(Icons.fingerprint), findsNothing);
    });
  });

  group('UnlockDialog biometric priority', () {
    testWidgets(
      'auto-triggers biometric on first frame and pops with cached key',
      (tester) async {
        final cachedKey = Uint8List.fromList(List.filled(32, 9));
        final auth = _OkBiometricAuth();
        final stub = _StubMasterPasswordManager(
          basePath: tempDir.path,
          acceptPassword: false,
        );

        await tester.pumpWidget(
          buildApp(
            onPressed: (ctx) {
              UnlockDialog.show(ctx, manager: stub);
            },
            overrides: [
              biometricKeyVaultProvider.overrideWithValue(
                _StashedBiometricVault(cachedKey),
              ),
              biometricAuthProvider.overrideWithValue(auth),
            ],
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        expect(
          auth.authenticateCalls,
          1,
          reason: 'biometric prompt must auto-fire on first frame',
        );
        // Dialog popped → back at the open button.
        expect(find.text('Master Password'), findsNothing);
      },
    );

    testWidgets('cancelled biometric shows retry button + error label', (
      tester,
    ) async {
      final cachedKey = Uint8List.fromList(List.filled(32, 9));
      final stub = _StubMasterPasswordManager(
        basePath: tempDir.path,
        acceptPassword: false,
      );

      await tester.pumpWidget(
        buildApp(
          onPressed: (ctx) {
            UnlockDialog.show(ctx, manager: stub);
          },
          overrides: [
            biometricKeyVaultProvider.overrideWithValue(
              _StashedBiometricVault(cachedKey),
            ),
            biometricAuthProvider.overrideWithValue(_CancelledBiometricAuth()),
          ],
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Dialog still open — biometric cancelled, not success.
      expect(find.text('Master Password'), findsOneWidget);
      // Retry button is visible (action surface remembers biometric
      // was offered).
      expect(find.byIcon(Icons.fingerprint), findsOneWidget);
      // Cancellation surfaces as a visible error, not silent.
      expect(find.text('Biometric unlock cancelled.'), findsOneWidget);
    });
  });

  group('UnlockDialog stub-driven', () {
    Future<_StubMasterPasswordManager> openStubDialog(
      WidgetTester tester, {
      bool acceptPassword = false,
      Uint8List? derivedKey,
    }) async {
      final stub = _StubMasterPasswordManager(
        basePath: tempDir.path,
        acceptPassword: acceptPassword,
        derivedKey: derivedKey,
      );
      await tester.pumpWidget(
        buildApp(
          onPressed: (ctx) {
            UnlockDialog.show(ctx, manager: stub);
          },
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      return stub;
    }

    testWidgets('wrong password shows error text and re-enables field', (
      tester,
    ) async {
      await openStubDialog(tester, acceptPassword: false);

      await tester.enterText(find.byType(TextField), 'bad-pass');
      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();

      // Error text is visible
      expect(find.text('Wrong password. Please try again.'), findsOneWidget);

      // Dialog is still open
      expect(find.text('Master Password'), findsOneWidget);

      // Field is enabled again
      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.enabled, isTrue);
    });

    testWidgets('correct password derives key and pops with key', (
      tester,
    ) async {
      await openStubDialog(
        tester,
        acceptPassword: true,
        derivedKey: Uint8List.fromList(List.filled(32, 7)),
      );

      await tester.enterText(find.byType(TextField), 'good-pass');
      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();

      // Dialog is gone
      expect(find.text('Master Password'), findsNothing);
    });

    testWidgets('forgot password confirm calls reset and pops with null', (
      tester,
    ) async {
      final stub = await openStubDialog(tester);

      await tester.tap(find.text('Forgot Password?'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Reset & Delete Credentials'));
      await tester.pumpAndSettle();

      expect(stub.resetCalled, isTrue);
      expect(find.text('Master Password'), findsNothing);
    });

    testWidgets('visibility toggle shows visibility icon when not obscured', (
      tester,
    ) async {
      await openStubDialog(tester);

      // Initial state: obscured, shows visibility_off
      expect(find.byIcon(Icons.visibility_off), findsOneWidget);
      expect(find.byIcon(Icons.visibility), findsNothing);

      await tester.tap(find.byIcon(Icons.visibility_off));
      await tester.pumpAndSettle();

      // After toggle: not obscured, shows visibility
      expect(find.byIcon(Icons.visibility), findsOneWidget);
      expect(find.byIcon(Icons.visibility_off), findsNothing);
    });
  });
}

/// Test stub that bypasses the PBKDF2 isolate so widget tests can drive
/// the unlock-success/failure paths without depending on real async work.
class _StubMasterPasswordManager extends MasterPasswordManager {
  bool acceptPassword;
  Uint8List? derivedKey;
  bool resetCalled = false;

  _StubMasterPasswordManager({
    required String basePath,
    this.acceptPassword = false,
    this.derivedKey,
  }) : super(basePath: basePath);

  @override
  Future<bool> verify(String password) async => acceptPassword;

  @override
  Future<Uint8List> deriveKey(String password) async =>
      derivedKey ?? Uint8List(32);

  @override
  Future<Uint8List?> verifyAndDerive(
    String password, {
    bool useRateLimit = false,
  }) async {
    if (!acceptPassword) return null;
    return derivedKey ?? Uint8List(32);
  }

  @override
  Future<void> reset() async {
    resetCalled = true;
  }
}
