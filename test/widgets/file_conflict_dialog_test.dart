import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:letsflutssh/core/transfer/conflict_resolver.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/theme/app_theme.dart';
import 'package:letsflutssh/widgets/file_conflict_dialog.dart';

/// Opens [FileConflictDialog] behind an "Open" button, returns the
/// decision captured when the dialog closes. Exercises the English
/// copy so the test can match button labels by their ARB strings.
Future<ConflictDecision> _openDialog(
  WidgetTester tester, {
  required String tapLabel,
  bool toggleApplyToAll = false,
  bool showApplyToAll = true,
  bool dismissScrim = false,
}) async {
  ConflictDecision? captured;
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: S.localizationsDelegates,
      supportedLocales: S.supportedLocales,
      theme: AppTheme.dark(),
      home: Scaffold(
        body: Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () async {
              captured = await FileConflictDialog.show(
                ctx,
                targetPath: '/srv/www/report.txt',
                isRemoteTarget: true,
                showApplyToAll: showApplyToAll,
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

  if (toggleApplyToAll) {
    await tester.tap(find.text('Apply to all remaining'));
    await tester.pumpAndSettle();
  }

  if (dismissScrim) {
    await tester.tapAt(const Offset(5, 5));
  } else {
    await tester.tap(find.text(tapLabel));
  }
  await tester.pumpAndSettle();
  return captured!;
}

void main() {
  testWidgets('renders file name and target directory', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: S.localizationsDelegates,
        supportedLocales: S.supportedLocales,
        theme: AppTheme.dark(),
        home: Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () => FileConflictDialog.show(
                ctx,
                targetPath: '/srv/www/report.txt',
                isRemoteTarget: true,
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    // Title uses the EN ARB string.
    expect(find.text('File already exists'), findsOneWidget);
    // Message interpolates fileName + targetDir.
    expect(find.textContaining('report.txt'), findsAtLeastNWidgets(1));
    expect(find.textContaining('/srv/www'), findsOneWidget);
    // All four action labels are present.
    expect(find.text('Skip'), findsOneWidget);
    expect(find.text('Keep both'), findsOneWidget);
    expect(find.text('Replace'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
  });

  testWidgets('Skip returns skip action with applyToAll=false', (tester) async {
    final d = await _openDialog(tester, tapLabel: 'Skip');
    expect(d.action, ConflictAction.skip);
    expect(d.applyToAll, isFalse);
  });

  testWidgets('Keep both returns keepBoth action', (tester) async {
    final d = await _openDialog(tester, tapLabel: 'Keep both');
    expect(d.action, ConflictAction.keepBoth);
  });

  testWidgets('Replace returns replace action', (tester) async {
    final d = await _openDialog(tester, tapLabel: 'Replace');
    expect(d.action, ConflictAction.replace);
  });

  testWidgets('Cancel button returns cancel action', (tester) async {
    final d = await _openDialog(tester, tapLabel: 'Cancel');
    expect(d.action, ConflictAction.cancel);
  });

  testWidgets('applyToAll checkbox flows through the decision', (tester) async {
    final d = await _openDialog(
      tester,
      tapLabel: 'Replace',
      toggleApplyToAll: true,
    );
    expect(d.action, ConflictAction.replace);
    expect(d.applyToAll, isTrue);
  });

  testWidgets('dismissing via the scrim yields a cancel decision', (
    tester,
  ) async {
    final d = await _openDialog(tester, tapLabel: '', dismissScrim: true);
    expect(d.action, ConflictAction.cancel);
  });

  testWidgets('hides applyToAll checkbox when showApplyToAll is false', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: S.localizationsDelegates,
        supportedLocales: S.supportedLocales,
        theme: AppTheme.dark(),
        home: Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () => FileConflictDialog.show(
                ctx,
                targetPath: '/srv/www/report.txt',
                isRemoteTarget: true,
                showApplyToAll: false,
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Apply to all remaining'), findsNothing);
  });
}
