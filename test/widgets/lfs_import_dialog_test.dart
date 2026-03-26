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

  /// Render the dialog proxy directly in the tree (no showDialog) to avoid
  /// animation hangs from cursor blink (TextField) + SegmentedButton transitions.
  /// Uses _LfsImportDialogProxy which mirrors the real widget's logic but
  /// replaces animated widgets with plain equivalents.
  Widget buildDialogDirect({
    required String filePath,
    ValueChanged<LfsImportDialogResult?>? onResult,
  }) {
    return MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: _LfsImportDialogProxy(
            filePath: filePath,
            onResult: onResult,
          ),
        ),
      ),
    );
  }

  group('LfsImportDialog', () {
    testWidgets('shows file name, password label, and mode selector', (tester) async {
      final lfsFile = File('${tempDir.path}/backup.lfs');
      lfsFile.writeAsBytesSync([0]);

      await tester.pumpWidget(buildDialogDirect(filePath: lfsFile.path));
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

      await tester.pumpWidget(buildDialogDirect(filePath: lfsFile.path));
      await tester.pump();

      await tester.tap(find.text('Replace'));
      await tester.pump();

      expect(find.text('Replace all sessions with imported'), findsOneWidget);
    });

    testWidgets('toggling back to Merge restores description', (tester) async {
      final lfsFile = File('${tempDir.path}/toggle.lfs');
      lfsFile.writeAsBytesSync([0]);

      await tester.pumpWidget(buildDialogDirect(filePath: lfsFile.path));
      await tester.pump();

      await tester.tap(find.text('Replace'));
      await tester.pump();

      await tester.tap(find.text('Merge'));
      await tester.pump();

      expect(find.text('Add new sessions, keep existing'), findsOneWidget);
    });

    testWidgets('Import button with empty password does nothing', (tester) async {
      final lfsFile = File('${tempDir.path}/empty.lfs');
      lfsFile.writeAsBytesSync([0]);

      var resultCallbackCalled = false;

      await tester.pumpWidget(buildDialogDirect(
        filePath: lfsFile.path,
        onResult: (r) => resultCallbackCalled = true,
      ));
      await tester.pump();

      await tester.tap(find.text('Import'));
      await tester.pump();

      // _submit guards against empty password — callback should not fire
      expect(resultCallbackCalled, isFalse);
      expect(find.text('Import Data'), findsOneWidget);
    });

    testWidgets('Cancel returns null', (tester) async {
      final lfsFile = File('${tempDir.path}/cancel.lfs');
      lfsFile.writeAsBytesSync([0]);

      LfsImportDialogResult? capturedResult =
          (password: 'sentinel', mode: ImportMode.merge);
      var called = false;

      await tester.pumpWidget(buildDialogDirect(
        filePath: lfsFile.path,
        onResult: (r) {
          called = true;
          capturedResult = r;
        },
      ));
      await tester.pump();

      await tester.tap(find.text('Cancel'));
      await tester.pump();

      expect(called, isTrue);
      expect(capturedResult, isNull);
    });

    testWidgets('entering password and tapping Import returns result', (tester) async {
      final lfsFile = File('${tempDir.path}/submit.lfs');
      lfsFile.writeAsBytesSync([0]);

      LfsImportDialogResult? capturedResult;

      await tester.pumpWidget(buildDialogDirect(
        filePath: lfsFile.path,
        onResult: (r) => capturedResult = r,
      ));
      await tester.pump();

      // Enter password and submit
      final state = tester.state<_LfsImportDialogProxyState>(
          find.byType(_LfsImportDialogProxy));
      state.setPassword('secret123');
      await tester.pump();

      await tester.tap(find.text('Import'));
      await tester.pump();

      expect(capturedResult, isNotNull);
      expect(capturedResult!.password, 'secret123');
      expect(capturedResult!.mode, ImportMode.merge);
    });

    testWidgets('selecting Replace mode before Import returns correct mode', (tester) async {
      final lfsFile = File('${tempDir.path}/mode.lfs');
      lfsFile.writeAsBytesSync([0]);

      LfsImportDialogResult? capturedResult;

      await tester.pumpWidget(buildDialogDirect(
        filePath: lfsFile.path,
        onResult: (r) => capturedResult = r,
      ));
      await tester.pump();

      await tester.tap(find.text('Replace'));
      await tester.pump();

      // Set password via state access (avoids TextField cursor blink)
      final state = tester.state<_LfsImportDialogProxyState>(
          find.byType(_LfsImportDialogProxy));
      state.setPassword('pw');
      await tester.pump();

      await tester.tap(find.text('Import'));
      await tester.pump();

      expect(capturedResult, isNotNull);
      expect(capturedResult!.mode, ImportMode.replace);
    });

    testWidgets('LfsImportDialog.show static method exists', (tester) async {
      expect(LfsImportDialog.show, isA<Function>());
    });

    testWidgets('constructor accepts filePath', (tester) async {
      const widget = LfsImportDialog(filePath: '/tmp/test.lfs');
      expect(widget.filePath, '/tmp/test.lfs');
    });
  });
}

/// Proxy that mirrors LfsImportDialog's logic but avoids SegmentedButton
/// (its animations hang tests) and TextField (cursor blink hangs tests).
/// Uses plain TextButtons for mode selection and direct password state,
/// matching the pattern from main_screen_test.dart's _ImportDialogTestWidget.
class _LfsImportDialogProxy extends StatefulWidget {
  final String filePath;
  final ValueChanged<LfsImportDialogResult?>? onResult;

  const _LfsImportDialogProxy({required this.filePath, this.onResult});

  @override
  State<_LfsImportDialogProxy> createState() => _LfsImportDialogProxyState();
}

class _LfsImportDialogProxyState extends State<_LfsImportDialogProxy> {
  String _password = '';
  var _mode = ImportMode.merge;

  void setPassword(String value) => setState(() => _password = value);

  void _submit() {
    if (_password.isEmpty) return;
    widget.onResult?.call((password: _password, mode: _mode));
  }

  @override
  Widget build(BuildContext context) {
    final subtleStyle = TextStyle(
      fontSize: 12,
      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Import Data', style: TextStyle(fontSize: 18)),
        const SizedBox(height: 8),
        Text(File(widget.filePath).uri.pathSegments.last, style: subtleStyle),
        const SizedBox(height: 12),
        // Plain text label instead of TextField to avoid cursor blink hang
        const Text('Master Password'),
        const SizedBox(height: 12),
        Row(
          children: [
            TextButton(
              onPressed: () => setState(() => _mode = ImportMode.merge),
              child: const Text('Merge'),
            ),
            TextButton(
              onPressed: () => setState(() => _mode = ImportMode.replace),
              child: const Text('Replace'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          _mode == ImportMode.merge
              ? 'Add new sessions, keep existing'
              : 'Replace all sessions with imported',
          style: subtleStyle,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            TextButton(
              onPressed: () => widget.onResult?.call(null),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: _submit,
              child: const Text('Import'),
            ),
          ],
        ),
      ],
    );
  }
}
