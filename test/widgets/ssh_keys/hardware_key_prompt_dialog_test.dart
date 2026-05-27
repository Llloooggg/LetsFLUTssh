import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/theme/app_theme.dart';
import 'package:letsflutssh/widgets/security/secure_password_field.dart';
import 'package:letsflutssh/widgets/ssh_keys/hardware_key_prompt_dialog.dart';

void main() {
  // Helper that mounts a launcher button so each test can open the
  // dialog through `HardwareKeyPromptDialog.show` (the real entry
  // point) and capture the popped result the connect path receives.
  Future<HardwareKeyPromptResult?> openDialog(
    WidgetTester tester, {
    required bool requiresPin,
    String deviceName = 'YubiKey 5C',
  }) async {
    HardwareKeyPromptResult? result;
    var popped = false;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: S.localizationsDelegates,
        supportedLocales: S.supportedLocales,
        theme: AppTheme.dark(),
        home: Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () async {
                result = await HardwareKeyPromptDialog.show(
                  ctx,
                  deviceName: deviceName,
                  requiresPin: requiresPin,
                );
                popped = true;
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    // `popped` lets callers distinguish "still open" from "closed with
    // a null result"; not all tests inspect it.
    expect(popped, isFalse, reason: 'dialog should still be open');
    return result;
  }

  group('HardwareKeyPromptDialog — PIN gating', () {
    testWidgets('touch-only credential renders no PIN field', (tester) async {
      // requiresPin:false means the credential is verified by tap
      // alone — surfacing a PIN field would imply an input the device
      // never asks for.
      await openDialog(tester, requiresPin: false);
      expect(find.byType(SecurePasswordField), findsNothing);
      expect(find.text('Tap your hardware key'), findsOneWidget);
      expect(find.text('YubiKey 5C'), findsOneWidget);
    });

    testWidgets('PIN-required credential renders the PIN field', (
      tester,
    ) async {
      await openDialog(tester, requiresPin: true);
      expect(find.byType(SecurePasswordField), findsOneWidget);
      expect(find.text('Hardware key PIN'), findsOneWidget);
    });

    testWidgets('OK with an empty PIN does not pop the dialog', (tester) async {
      // The primary action must stay inert until a PIN is typed —
      // popping with a null/empty PIN would hand the connect path a
      // credential the device will then reject, losing the user's
      // chance to correct it inside the same prompt.
      await openDialog(tester, requiresPin: true);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      // Dialog still mounted: title still on screen, no route popped.
      expect(find.text('Tap your hardware key'), findsOneWidget);

      // Clean up the still-open route so it doesn't leak into teardown.
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });
  });

  group('HardwareKeyPromptDialog — result contract', () {
    testWidgets('OK with a typed PIN pops with that PIN and not cancelled', (
      tester,
    ) async {
      HardwareKeyPromptResult? result;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: S.localizationsDelegates,
          supportedLocales: S.supportedLocales,
          theme: AppTheme.dark(),
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () async {
                  result = await HardwareKeyPromptDialog.show(
                    ctx,
                    deviceName: 'Key',
                    requiresPin: true,
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(SecurePasswordField), '123456');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.cancelled, isFalse);
      expect(result!.pin, '123456');
    });

    testWidgets('touch-only OK pops with a null PIN and not cancelled', (
      tester,
    ) async {
      HardwareKeyPromptResult? result;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: S.localizationsDelegates,
          supportedLocales: S.supportedLocales,
          theme: AppTheme.dark(),
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () async {
                  result = await HardwareKeyPromptDialog.show(
                    ctx,
                    deviceName: 'Key',
                    requiresPin: false,
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.cancelled, isFalse);
      expect(result!.pin, isNull);
    });

    testWidgets('Cancel pops with cancelled:true regardless of PIN field', (
      tester,
    ) async {
      HardwareKeyPromptResult? result;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: S.localizationsDelegates,
          supportedLocales: S.supportedLocales,
          theme: AppTheme.dark(),
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () async {
                  result = await HardwareKeyPromptDialog.show(
                    ctx,
                    deviceName: 'Key',
                    requiresPin: true,
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Type a PIN, then cancel: the cancel path must still report a
      // user abort, never smuggle the half-typed PIN back out.
      await tester.enterText(find.byType(SecurePasswordField), '99');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.cancelled, isTrue);
    });
  });
}
