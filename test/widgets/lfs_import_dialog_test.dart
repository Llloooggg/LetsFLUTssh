import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/features/settings/export_import.dart';
import 'package:letsflutssh/widgets/lfs_import_dialog.dart';
import 'package:letsflutssh/theme/app_theme.dart';

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
      theme: AppTheme.dark(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: LfsImportDialog(filePath: filePath),
        ),
      ),
    );
  }

  group('LfsImportDialog — real widget', () {
    testWidgets('renders title, file name, password field, and mode selector',
        (tester) async {
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

    testWidgets('empty password: Import button triggers _submit guard',
        (tester) async {
      final lfsFile = File('${tempDir.path}/empty.lfs');
      lfsFile.writeAsBytesSync([0]);

      await tester.pumpWidget(buildRealDialog(lfsFile.path));
      await tester.pump();

      // Tap Import without entering password — _submit checks isEmpty
      await tester.tap(find.widgetWithText(FilledButton, 'Import'));
      await tester.pump();

      // Dialog should still be visible (no Navigator.pop happened)
      expect(find.text('Import Data'), findsOneWidget);
    });

    testWidgets('SegmentedButton has correct initial selection', (tester) async {
      final lfsFile = File('${tempDir.path}/init.lfs');
      lfsFile.writeAsBytesSync([0]);

      await tester.pumpWidget(buildRealDialog(lfsFile.path));
      await tester.pump();

      // Default mode is merge
      final segmented = tester.widget<SegmentedButton<ImportMode>>(
        find.byType(SegmentedButton<ImportMode>),
      );
      expect(segmented.selected, {ImportMode.merge});
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
}
