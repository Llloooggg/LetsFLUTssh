import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/sftp/file_system.dart';
import 'package:letsflutssh/core/sftp/sftp_models.dart';
import 'package:letsflutssh/features/file_browser/file_browser_controller.dart';
import 'package:letsflutssh/features/file_browser/file_pane_dialogs.dart';

/// In-memory file system for testing dialogs.
class _MockFS implements FileSystem {
  final List<String> createdDirs = [];
  final List<String> removedFiles = [];
  final List<String> removedDirs = [];
  final List<(String, String)> renames = [];

  @override
  Future<String> initialDir() async => '/test';

  @override
  Future<List<FileEntry>> list(String path) async => [];

  @override
  Future<void> mkdir(String path) async => createdDirs.add(path);

  @override
  Future<void> remove(String path) async => removedFiles.add(path);

  @override
  Future<void> removeDir(String path) async => removedDirs.add(path);

  @override
  Future<void> rename(String oldPath, String newPath) async =>
      renames.add((oldPath, newPath));
}

void main() {
  group('FilePaneDialogs.showNewFolder', () {
    testWidgets('shows dialog with text field', (tester) async {
      final fs = _MockFS();
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.navigateTo('/test', addToHistory: false);

      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) {
          return ElevatedButton(
            onPressed: () => FilePaneDialogs.showNewFolder(context, ctrl),
            child: const Text('Go'),
          );
        }),
      ));

      await tester.tap(find.text('Go'));
      await tester.pumpAndSettle();

      expect(find.text('New Folder'), findsOneWidget);
      expect(find.text('Folder name'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Create'), findsOneWidget);

      ctrl.dispose();
    });

    testWidgets('creates folder on submit', (tester) async {
      final fs = _MockFS();
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.navigateTo('/test', addToHistory: false);

      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) {
          return ElevatedButton(
            onPressed: () => FilePaneDialogs.showNewFolder(context, ctrl),
            child: const Text('Go'),
          );
        }),
      ));

      await tester.tap(find.text('Go'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'newdir');
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      expect(fs.createdDirs, ['/test/newdir']);
      ctrl.dispose();
    });

    testWidgets('cancel does not create folder', (tester) async {
      final fs = _MockFS();
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.navigateTo('/test', addToHistory: false);

      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) {
          return ElevatedButton(
            onPressed: () => FilePaneDialogs.showNewFolder(context, ctrl),
            child: const Text('Go'),
          );
        }),
      ));

      await tester.tap(find.text('Go'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(fs.createdDirs, isEmpty);
      ctrl.dispose();
    });
  });

  group('FilePaneDialogs.showRename', () {
    testWidgets('shows dialog with current name', (tester) async {
      final fs = _MockFS();
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.navigateTo('/test', addToHistory: false);

      final entry = FileEntry(
        name: 'old.txt',
        path: '/test/old.txt',
        size: 100,
        modTime: DateTime.now(),
        isDir: false,
      );

      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) {
          return ElevatedButton(
            onPressed: () => FilePaneDialogs.showRename(context, ctrl, entry),
            child: const Text('Go'),
          );
        }),
      ));

      await tester.tap(find.text('Go'));
      await tester.pumpAndSettle();

      expect(find.text('Rename'), findsWidgets);
      // The text field should contain the old name
      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.controller?.text, 'old.txt');

      ctrl.dispose();
    });

    testWidgets('renames file on submit', (tester) async {
      final fs = _MockFS();
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.navigateTo('/test', addToHistory: false);

      final entry = FileEntry(
        name: 'old.txt',
        path: '/test/old.txt',
        size: 100,
        modTime: DateTime.now(),
        isDir: false,
      );

      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) {
          return ElevatedButton(
            onPressed: () => FilePaneDialogs.showRename(context, ctrl, entry),
            child: const Text('Go'),
          );
        }),
      ));

      await tester.tap(find.text('Go'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'new.txt');
      // Find the Rename button (there are two "Rename" texts - title and button)
      await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
      await tester.pumpAndSettle();

      expect(fs.renames, [('/test/old.txt', '/test/new.txt')]);
      ctrl.dispose();
    });
  });

  group('FilePaneDialogs.confirmDelete', () {
    testWidgets('shows confirmation for single file', (tester) async {
      final fs = _MockFS();
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.navigateTo('/test', addToHistory: false);

      final entry = FileEntry(
        name: 'file.txt',
        path: '/test/file.txt',
        size: 100,
        modTime: DateTime.now(),
        isDir: false,
      );

      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) {
          return ElevatedButton(
            onPressed: () => FilePaneDialogs.confirmDelete(context, ctrl, [entry]),
            child: const Text('Go'),
          );
        }),
      ));

      await tester.tap(find.text('Go'));
      await tester.pumpAndSettle();

      expect(find.text('Delete "file.txt"?'), findsOneWidget);

      ctrl.dispose();
    });

    testWidgets('shows confirmation for multiple files', (tester) async {
      final fs = _MockFS();
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.navigateTo('/test', addToHistory: false);

      final entries = [
        FileEntry(name: 'a.txt', path: '/test/a.txt', size: 10, modTime: DateTime.now(), isDir: false),
        FileEntry(name: 'b.txt', path: '/test/b.txt', size: 20, modTime: DateTime.now(), isDir: false),
      ];

      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) {
          return ElevatedButton(
            onPressed: () => FilePaneDialogs.confirmDelete(context, ctrl, entries),
            child: const Text('Go'),
          );
        }),
      ));

      await tester.tap(find.text('Go'));
      await tester.pumpAndSettle();

      expect(find.text('Delete 2 items?'), findsOneWidget);

      ctrl.dispose();
    });

    testWidgets('deletes files on confirm', (tester) async {
      final fs = _MockFS();
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.navigateTo('/test', addToHistory: false);

      final entry = FileEntry(
        name: 'file.txt',
        path: '/test/file.txt',
        size: 100,
        modTime: DateTime.now(),
        isDir: false,
      );

      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) {
          return ElevatedButton(
            onPressed: () => FilePaneDialogs.confirmDelete(context, ctrl, [entry]),
            child: const Text('Go'),
          );
        }),
      ));

      await tester.tap(find.text('Go'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(fs.removedFiles, ['/test/file.txt']);
      ctrl.dispose();
    });

    testWidgets('deletes directories via removeDir', (tester) async {
      final fs = _MockFS();
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.navigateTo('/test', addToHistory: false);

      final entry = FileEntry(
        name: 'mydir',
        path: '/test/mydir',
        size: 0,
        modTime: DateTime.now(),
        isDir: true,
      );

      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) {
          return ElevatedButton(
            onPressed: () => FilePaneDialogs.confirmDelete(context, ctrl, [entry]),
            child: const Text('Go'),
          );
        }),
      ));

      await tester.tap(find.text('Go'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(fs.removedDirs, ['/test/mydir']);
      ctrl.dispose();
    });

    testWidgets('cancel does not delete', (tester) async {
      final fs = _MockFS();
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.navigateTo('/test', addToHistory: false);

      final entry = FileEntry(
        name: 'file.txt',
        path: '/test/file.txt',
        size: 100,
        modTime: DateTime.now(),
        isDir: false,
      );

      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) {
          return ElevatedButton(
            onPressed: () => FilePaneDialogs.confirmDelete(context, ctrl, [entry]),
            child: const Text('Go'),
          );
        }),
      ));

      await tester.tap(find.text('Go'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(fs.removedFiles, isEmpty);
      expect(fs.removedDirs, isEmpty);
      ctrl.dispose();
    });
  });
}
