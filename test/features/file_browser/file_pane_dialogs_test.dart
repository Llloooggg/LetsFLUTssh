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
  @override
  Future<int> dirSize(String path) async => 0;
}

/// FS that throws on mkdir.
class _ErrorMkdirFS implements FileSystem {
  @override
  Future<String> initialDir() async => '/test';
  @override
  Future<List<FileEntry>> list(String path) async => [];
  @override
  Future<void> mkdir(String path) async => throw Exception('mkdir failed');
  @override
  Future<void> remove(String path) async {}
  @override
  Future<void> removeDir(String path) async {}
  @override
  Future<void> rename(String oldPath, String newPath) async {}
  @override
  Future<int> dirSize(String path) async => 0;

}

/// FS that throws on rename.
class _ErrorRenameFS implements FileSystem {
  @override
  Future<String> initialDir() async => '/test';
  @override
  Future<List<FileEntry>> list(String path) async => [];
  @override
  Future<void> mkdir(String path) async {}
  @override
  Future<void> remove(String path) async {}
  @override
  Future<void> removeDir(String path) async {}
  @override
  Future<void> rename(String oldPath, String newPath) async =>
      throw Exception('rename failed');
  @override
  Future<int> dirSize(String path) async => 0;
}

/// FS that throws on remove/removeDir.
class _ErrorDeleteFS implements FileSystem {
  @override
  Future<String> initialDir() async => '/test';
  @override
  Future<List<FileEntry>> list(String path) async => [];
  @override
  Future<void> mkdir(String path) async {}
  @override
  Future<void> remove(String path) async =>
      throw Exception('delete failed');
  @override
  Future<void> removeDir(String path) async =>
      throw Exception('delete failed');
  @override
  Future<void> rename(String oldPath, String newPath) async {}
  @override
  Future<int> dirSize(String path) async => 0;

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

  group('FilePaneDialogs.showNewFolder — error handling', () {
    testWidgets('shows error toast when mkdir fails', (tester) async {
      final fs = _ErrorMkdirFS();
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.navigateTo('/test', addToHistory: false);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(builder: (context) {
            return ElevatedButton(
              onPressed: () => FilePaneDialogs.showNewFolder(context, ctrl),
              child: const Text('Go'),
            );
          }),
        ),
      ));

      await tester.tap(find.text('Go'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'faildir');
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      // Error toast should show
      expect(find.textContaining('Failed to create folder'), findsOneWidget);

      // Wait for toast to auto-dismiss
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      ctrl.dispose();
    });

    testWidgets('empty name does not create folder', (tester) async {
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

      // Submit with empty name
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      expect(fs.createdDirs, isEmpty);
      ctrl.dispose();
    });

    testWidgets('submit via Enter key creates folder', (tester) async {
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

      await tester.enterText(find.byType(TextField), 'enterdir');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(fs.createdDirs, ['/test/enterdir']);
      ctrl.dispose();
    });
  });

  group('FilePaneDialogs.showRename — error handling', () {
    testWidgets('shows error toast when rename fails', (tester) async {
      final fs = _ErrorRenameFS();
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
        home: Scaffold(
          body: Builder(builder: (context) {
            return ElevatedButton(
              onPressed: () => FilePaneDialogs.showRename(context, ctrl, entry),
              child: const Text('Go'),
            );
          }),
        ),
      ));

      await tester.tap(find.text('Go'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'new.txt');
      await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Failed to rename'), findsOneWidget);

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      ctrl.dispose();
    });

    testWidgets('same name does not trigger rename', (tester) async {
      final fs = _MockFS();
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.navigateTo('/test', addToHistory: false);

      final entry = FileEntry(
        name: 'same.txt',
        path: '/test/same.txt',
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

      // Don't change the name, just submit
      await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
      await tester.pumpAndSettle();

      expect(fs.renames, isEmpty);
      ctrl.dispose();
    });

    testWidgets('submit via Enter key renames', (tester) async {
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

      await tester.enterText(find.byType(TextField), 'entered.txt');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(fs.renames, [('/test/old.txt', '/test/entered.txt')]);
      ctrl.dispose();
    });
  });

  group('FilePaneDialogs.confirmDelete — error handling', () {
    testWidgets('shows error toast when delete fails', (tester) async {
      final fs = _ErrorDeleteFS();
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.navigateTo('/test', addToHistory: false);

      final entry = FileEntry(
        name: 'fail.txt',
        path: '/test/fail.txt',
        size: 100,
        modTime: DateTime.now(),
        isDir: false,
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(builder: (context) {
            return ElevatedButton(
              onPressed: () => FilePaneDialogs.confirmDelete(context, ctrl, [entry]),
              child: const Text('Go'),
            );
          }),
        ),
      ));

      await tester.tap(find.text('Go'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Failed to delete'), findsOneWidget);

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      ctrl.dispose();
    });

    testWidgets('shows success toast after successful delete', (tester) async {
      final fs = _MockFS();
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.navigateTo('/test', addToHistory: false);

      final entry = FileEntry(
        name: 'success.txt',
        path: '/test/success.txt',
        size: 100,
        modTime: DateTime.now(),
        isDir: false,
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(builder: (context) {
            return ElevatedButton(
              onPressed: () => FilePaneDialogs.confirmDelete(context, ctrl, [entry]),
              child: const Text('Go'),
            );
          }),
        ),
      ));

      await tester.tap(find.text('Go'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Deleted success.txt'), findsOneWidget);

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      ctrl.dispose();
    });

    testWidgets('deletes multiple items with success toast', (tester) async {
      final fs = _MockFS();
      final ctrl = FilePaneController(fs: fs, label: 'Test');
      await ctrl.navigateTo('/test', addToHistory: false);

      final entries = [
        FileEntry(name: 'a.txt', path: '/test/a.txt', size: 10, modTime: DateTime.now(), isDir: false),
        FileEntry(name: 'b.txt', path: '/test/b.txt', size: 20, modTime: DateTime.now(), isDir: false),
      ];

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(builder: (context) {
            return ElevatedButton(
              onPressed: () => FilePaneDialogs.confirmDelete(context, ctrl, entries),
              child: const Text('Go'),
            );
          }),
        ),
      ));

      await tester.tap(find.text('Go'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Deleted 2 items'), findsOneWidget);
      expect(fs.removedFiles, ['/test/a.txt', '/test/b.txt']);

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

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
        home: Scaffold(
          body: Builder(builder: (context) {
            return ElevatedButton(
              onPressed: () => FilePaneDialogs.confirmDelete(context, ctrl, [entry]),
              child: const Text('Go'),
            );
          }),
        ),
      ));

      await tester.tap(find.text('Go'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      // Pump past Toast auto-dismiss timer + animation
      await tester.pump(const Duration(seconds: 4));
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
        home: Scaffold(
          body: Builder(builder: (context) {
            return ElevatedButton(
              onPressed: () => FilePaneDialogs.confirmDelete(context, ctrl, [entry]),
              child: const Text('Go'),
            );
          }),
        ),
      ));

      await tester.tap(find.text('Go'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      // Pump past Toast auto-dismiss timer + animation
      await tester.pump(const Duration(seconds: 4));
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
