import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/master_password.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/widgets/unlock_dialog.dart';

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

  Widget buildApp({required void Function(BuildContext) onPressed}) {
    return MaterialApp(
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
    );
  }

  /// Open the dialog — enable master password first via runAsync
  /// (PBKDF2 isolate needs real async).
  Future<void> openDialog(
    WidgetTester tester, {
    required void Function(BuildContext) onPressed,
  }) async {
    await tester.runAsync(() => manager.enable('testpass'));
    await tester.pumpWidget(buildApp(onPressed: onPressed));
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
  });
}
