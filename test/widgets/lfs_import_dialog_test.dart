import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/features/settings/export_import.dart';
import 'package:letsflutssh/widgets/lfs_import_dialog.dart';
import 'package:letsflutssh/theme/app_theme.dart';
import '''package:letsflutssh/l10n/app_localizations.dart''';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('lfs_dialog_test_');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  /// Render the real LfsImportDialog directly in the widget tree
  /// (bypassing showDialog to avoid overlay/animation issues).
  /// Uses SingleChildScrollView to prevent overflow from AlertDialog content.
  Widget buildRealDialog(String filePath) {
    return MaterialApp(
      localizationsDelegates: S.localizationsDelegates,
      supportedLocales: S.supportedLocales,
      theme: AppTheme.dark(),
      home: Scaffold(
        body: SingleChildScrollView(child: LfsImportDialog(filePath: filePath)),
      ),
    );
  }

  group('LfsImportDialog — real widget', () {
    testWidgets('renders title, file name, password field, and mode selector', (tester) async {
      final lfsFile = File('${tempDir.path}/backup.lfs');
      lfsFile.writeAsBytesSync([0]);

      await tester.pumpWidget(buildRealDialog(lfsFile.path));
      await tester.pump();

      expect(find.text('Import Data'), findsOneWidget);
      expect(find.text('backup.lfs'), findsOneWidget);
      expect(find.text('Master Password'), findsOneWidget);
      expect(find.text('Merge'), findsOneWidget);
      expect(find.text('Replace'), findsOneWidget);
      expect(find.text('Add new sessions, keep existing'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Import'), findsOneWidget);
    });

    testWidgets('toggling to Replace changes description', (tester) async {
      final lfsFile = File('${tempDir.path}/data.lfs');
      lfsFile.writeAsBytesSync([0]);

      await tester.pumpWidget(buildRealDialog(lfsFile.path));
      await tester.pump();

      await tester.tap(find.text('Replace'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Replace all sessions with imported'), findsOneWidget);
    });

    testWidgets('toggling back to Merge restores description', (tester) async {
      final lfsFile = File('${tempDir.path}/toggle.lfs');
      lfsFile.writeAsBytesSync([0]);

      await tester.pumpWidget(buildRealDialog(lfsFile.path));
      await tester.pump();

      await tester.tap(find.text('Replace'));
      await tester.pump();
      await tester.pump();

      await tester.tap(find.text('Merge'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Add new sessions, keep existing'), findsOneWidget);
    });

    testWidgets('empty password: Import button triggers _submit guard', (tester) async {
      final lfsFile = File('${tempDir.path}/empty.lfs');
      lfsFile.writeAsBytesSync([0]);

      await tester.pumpWidget(buildRealDialog(lfsFile.path));
      await tester.pump();

      // Tap Import without entering password — _submit checks isEmpty
      await tester.tap(find.text('Import'));
      await tester.pump();

      // Dialog should still be visible (no Navigator.pop happened)
      expect(find.text('Import Data'), findsOneWidget);
    });

    testWidgets('default mode is Merge', (tester) async {
      final lfsFile = File('${tempDir.path}/init.lfs');
      lfsFile.writeAsBytesSync([0]);

      await tester.pumpWidget(buildRealDialog(lfsFile.path));
      await tester.pump();

      // Default mode is merge — the merge description is shown
      expect(find.text('Add new sessions, keep existing'), findsOneWidget);
      expect(find.text('Merge'), findsOneWidget);
      expect(find.text('Replace'), findsOneWidget);
    });

    testWidgets('TextField is obscured for password', (tester) async {
      final lfsFile = File('${tempDir.path}/obscure.lfs');
      lfsFile.writeAsBytesSync([0]);

      await tester.pumpWidget(buildRealDialog(lfsFile.path));
      await tester.pump();

      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.obscureText, isTrue);
    });

    testWidgets('TextField has autofocus', (tester) async {
      final lfsFile = File('${tempDir.path}/focus.lfs');
      lfsFile.writeAsBytesSync([0]);

      await tester.pumpWidget(buildRealDialog(lfsFile.path));
      await tester.pump();

      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.autofocus, isTrue);
    });

    testWidgets('file name extracted from path correctly', (tester) async {
      final lfsFile = File('${tempDir.path}/my_archive_2024.lfs');
      lfsFile.writeAsBytesSync([0]);

      await tester.pumpWidget(buildRealDialog(lfsFile.path));
      await tester.pump();

      expect(find.text('my_archive_2024.lfs'), findsOneWidget);
    });
  });

  group('LfsImportDialog — static API', () {
    testWidgets('show() static method exists and is callable', (tester) async {
      expect(LfsImportDialog.show, isA<Function>());
    });

    testWidgets('constructor accepts filePath', (tester) async {
      const widget = LfsImportDialog(filePath: '/tmp/test.lfs');
      expect(widget.filePath, '/tmp/test.lfs');
    });
  });

  group('LfsImportDialog — dialog route (Navigator.pop coverage)', () {
    testWidgets('Import with password returns result with password and mode', (tester) async {
      final lfsFile = File('${tempDir.path}/test.lfs');
      lfsFile.writeAsBytesSync([0]);

      LfsImportDialogResult? result;
      bool dialogCompleted = false;

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: S.localizationsDelegates,
          supportedLocales: S.supportedLocales,
          theme: AppTheme.dark(),
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  result = await LfsImportDialog.show(context, filePath: lfsFile.path);
                  dialogCompleted = true;
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Dialog is visible
      expect(find.text('Import Data'), findsOneWidget);

      // Enter password and tap Import
      await tester.enterText(find.byType(TextField), 'secret123');
      await tester.tap(find.text('Import'));
      await tester.pumpAndSettle();

      expect(dialogCompleted, isTrue);
      expect(result, isNotNull);
      expect(result!.password, 'secret123');
      expect(result!.mode, ImportMode.merge);
    });

    testWidgets('onSubmitted with non-empty password returns result', (tester) async {
      final lfsFile = File('${tempDir.path}/submit.lfs');
      lfsFile.writeAsBytesSync([0]);

      LfsImportDialogResult? result;
      bool dialogCompleted = false;

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: S.localizationsDelegates,
          supportedLocales: S.supportedLocales,
          theme: AppTheme.dark(),
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  result = await LfsImportDialog.show(context, filePath: lfsFile.path);
                  dialogCompleted = true;
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Enter password and press Enter (onSubmitted)
      await tester.enterText(find.byType(TextField), 'mypass');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(dialogCompleted, isTrue);
      expect(result, isNotNull);
      expect(result!.password, 'mypass');
      expect(result!.mode, ImportMode.merge);
    });

    testWidgets('onSubmitted with empty password keeps dialog open', (tester) async {
      final lfsFile = File('${tempDir.path}/empty_submit.lfs');
      lfsFile.writeAsBytesSync([0]);

      bool dialogCompleted = false;

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: S.localizationsDelegates,
          supportedLocales: S.supportedLocales,
          theme: AppTheme.dark(),
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  await LfsImportDialog.show(context, filePath: lfsFile.path);
                  dialogCompleted = true;
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Press Enter without entering password (onSubmitted with empty string)
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      // Dialog should still be open
      expect(dialogCompleted, isFalse);
      expect(find.text('Import Data'), findsOneWidget);
    });

    testWidgets('Cancel button returns null', (tester) async {
      final lfsFile = File('${tempDir.path}/cancel.lfs');
      lfsFile.writeAsBytesSync([0]);

      LfsImportDialogResult? result;
      bool dialogCompleted = false;

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: S.localizationsDelegates,
          supportedLocales: S.supportedLocales,
          theme: AppTheme.dark(),
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  result = await LfsImportDialog.show(context, filePath: lfsFile.path);
                  dialogCompleted = true;
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Tap Cancel
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(dialogCompleted, isTrue);
      expect(result, isNull);
    });
  });
}
