import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/master_password.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/widgets/unlock_dialog.dart';

// UnlockDialog is Paranoid-only and no longer probes the biometric
// providers at all — the tier's "no OS trust" premise rules out a
// biometric-gated vault (see the dialog's class docstring). The
// previous test harness stubbed both providers to drive the
// biometric-priority flow; with that flow removed, there is nothing
// to override and no biometric stubs to carry.

void main() {
  late Directory tempDir;
  late MasterPasswordManager manager;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = await Directory.systemTemp.createTemp('unlock_dlg_test_');
    manager = MasterPasswordManager(basePath: tempDir.path);
    // `WipeAllService` (reached via the forgot-password path) calls
    // `getApplicationSupportDirectory()`. Mock the platform channel
    // to point at the same temp dir the test already owns; without
    // this the wipe throws and the forgot-password branch silently
    // aborts, leaving the unlock dialog on screen.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  Widget buildApp({
    required void Function(BuildContext) onPressed,
    List<Override>? overrides,
  }) {
    return ProviderScope(
      overrides: overrides ?? const <Override>[],
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

      expect(find.text('Reset everything'), findsOneWidget);
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

    testWidgets('no biometric retry button — Paranoid does not expose it', (
      tester,
    ) async {
      // Paranoid tier does not offer biometric unlock by design: the
      // tier's premise is "no OS trust" and a biometric-gated vault
      // would pull the DB key back into the OS keychain layer the
      // tier avoids. The dialog must therefore never render the
      // fingerprint retry affordance, regardless of what the
      // platform biometric stack says.
      await openDialog(
        tester,
        onPressed: (ctx) {
          UnlockDialog.show(ctx, manager: manager);
        },
      );

      expect(find.byIcon(Icons.fingerprint), findsNothing);
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

    testWidgets('forgot password tap opens confirmation', (tester) async {
      // The full forgot-password flow now routes through
      // `WipeAllService.wipeAll()` + `requestSecurityReinit(ref)`
      // which requires native channel mocks + a full app shell
      // (the reinit listener lives on `_LetsFLUTsshAppState`).
      // The unit test here validates what it can from inside a
      // stub-driven harness — the confirmation dialog opens on
      // "Forgot Password?" tap and surfaces the shared
      // `resetAllDataConfirmAction` button.
      await openStubDialog(tester);

      await tester.tap(find.text('Forgot Password?'));
      await tester.pumpAndSettle();

      expect(find.text('Reset everything'), findsOneWidget);
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
