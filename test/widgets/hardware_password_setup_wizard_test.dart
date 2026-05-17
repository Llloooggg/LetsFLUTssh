import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/widgets/hardware_password_setup_wizard.dart';

Widget _wrap(Widget child) => MaterialApp(
  localizationsDelegates: S.localizationsDelegates,
  supportedLocales: S.supportedLocales,
  home: Scaffold(body: child),
);

Widget _host(
  void Function(HardwarePasswordWizardOutcome?) onResult, {
  required HardwareResealCall reseal,
}) => _wrap(
  Builder(
    builder: (ctx) => TextButton(
      onPressed: () async {
        onResult(
          await HardwarePasswordSetupWizard.show(
            ctx,
            supportDir: '/tmp/fake-support-dir',
            reseal: reseal,
          ),
        );
      },
      child: const Text('Open'),
    ),
  ),
);

/// Reseal stub that records the bytes it was handed + returns
/// immediately. Tests assert against the recorded arguments + the
/// wizard's pop value.
class _RecordingReseal {
  final List<String> seenSupportDirs = [];
  final List<String> seenPasswords = [];
  final Future<void> Function(String supportDir, String newPassword)? onCall;

  _RecordingReseal({this.onCall});

  Future<void> call({
    required String supportDir,
    required String newPassword,
  }) async {
    seenSupportDirs.add(supportDir);
    seenPasswords.add(newPassword);
    if (onCall != null) await onCall!(supportDir, newPassword);
  }
}

void main() {
  group('HardwarePasswordSetupWizard', () {
    testWidgets('step 1 shows the intro prompt + both action buttons', (
      tester,
    ) async {
      final reseal = _RecordingReseal();
      await tester.pumpWidget(_host((_) {}, reseal: reseal.call));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      final l10n = S.of(
        tester.element(find.byType(HardwarePasswordSetupWizard)),
      );
      expect(find.text(l10n.t2MigrationPromptTitle), findsOneWidget);
      expect(find.text(l10n.t2MigrationPromptBody), findsOneWidget);
      expect(find.text(l10n.t2MigrationContinue), findsOneWidget);
      expect(find.text(l10n.t2MigrationWipeAndRestart), findsOneWidget);
    });

    testWidgets('wipe button on step 1 pops with wipeRequested', (
      tester,
    ) async {
      HardwarePasswordWizardOutcome? result =
          HardwarePasswordWizardOutcome.resealed; // sentinel
      final reseal = _RecordingReseal();
      await tester.pumpWidget(_host((r) => result = r, reseal: reseal.call));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final l10n = S.of(
        tester.element(find.byType(HardwarePasswordSetupWizard)),
      );
      await tester.tap(find.text(l10n.t2MigrationWipeAndRestart));
      await tester.pumpAndSettle();
      expect(result, HardwarePasswordWizardOutcome.wipeRequested);
      expect(
        reseal.seenPasswords,
        isEmpty,
        reason: 'wipe path must never call reseal',
      );
    });

    testWidgets('continue advances to step 2 with two password fields', (
      tester,
    ) async {
      final reseal = _RecordingReseal();
      await tester.pumpWidget(_host((_) {}, reseal: reseal.call));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final l10n = S.of(
        tester.element(find.byType(HardwarePasswordSetupWizard)),
      );
      await tester.tap(find.text(l10n.t2MigrationContinue));
      await tester.pumpAndSettle();

      expect(find.text(l10n.t2MigrationSetPasswordTitle), findsOneWidget);
      // Two password input fields land under their own labels.
      expect(find.text(l10n.masterPasswordLabel.toUpperCase()), findsOneWidget);
      expect(find.text(l10n.confirmPassword.toUpperCase()), findsOneWidget);
    });

    testWidgets(
      'mismatched passwords surface inline error and skip the reseal call',
      (tester) async {
        final reseal = _RecordingReseal();
        await tester.pumpWidget(_host((_) {}, reseal: reseal.call));
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        final l10n = S.of(
          tester.element(find.byType(HardwarePasswordSetupWizard)),
        );
        await tester.tap(find.text(l10n.t2MigrationContinue));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextFormField).first, 'aaa');
        await tester.enterText(find.byType(TextFormField).last, 'bbb');
        await tester.tap(find.text(l10n.t2MigrationContinue));
        await tester.pumpAndSettle();
        expect(find.text(l10n.passwordsDoNotMatch), findsOneWidget);
        expect(reseal.seenPasswords, isEmpty);
      },
    );

    testWidgets(
      'matching passwords fire the reseal call and pop with resealed',
      (tester) async {
        HardwarePasswordWizardOutcome? result;
        final reseal = _RecordingReseal();
        await tester.pumpWidget(_host((r) => result = r, reseal: reseal.call));
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        final l10n = S.of(
          tester.element(find.byType(HardwarePasswordSetupWizard)),
        );
        await tester.tap(find.text(l10n.t2MigrationContinue));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextFormField).first, 'newpass1');
        await tester.enterText(find.byType(TextFormField).last, 'newpass1');
        await tester.tap(find.text(l10n.t2MigrationContinue));
        await tester.pumpAndSettle();
        expect(result, HardwarePasswordWizardOutcome.resealed);
        expect(reseal.seenSupportDirs, ['/tmp/fake-support-dir']);
        expect(reseal.seenPasswords, ['newpass1']);
      },
    );

    testWidgets(
      'reseal throw surfaces a retry-friendly error and keeps the dialog up',
      (tester) async {
        final reseal = _RecordingReseal(
          onCall: (_, _) async => throw StateError('platform vault sad'),
        );
        await tester.pumpWidget(_host((_) {}, reseal: reseal.call));
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        final l10n = S.of(
          tester.element(find.byType(HardwarePasswordSetupWizard)),
        );
        await tester.tap(find.text(l10n.t2MigrationContinue));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextFormField).first, 'newpass1');
        await tester.enterText(find.byType(TextFormField).last, 'newpass1');
        await tester.tap(find.text(l10n.t2MigrationContinue));
        await tester.pumpAndSettle();
        // The localized failure message lands inline; the dialog
        // stays mounted so the user can pick a different password
        // or wipe.
        expect(find.text(l10n.t2MigrationResealFailed), findsOneWidget);
        expect(find.byType(HardwarePasswordSetupWizard), findsOneWidget);
      },
    );

    testWidgets('barrier-dismiss is disabled (non-dismissible)', (
      tester,
    ) async {
      final reseal = _RecordingReseal();
      await tester.pumpWidget(_host((_) {}, reseal: reseal.call));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.byType(HardwarePasswordSetupWizard), findsOneWidget);
    });
  });
}
