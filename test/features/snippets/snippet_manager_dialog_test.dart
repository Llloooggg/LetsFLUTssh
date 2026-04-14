import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/snippets/snippet.dart';
import 'package:letsflutssh/core/snippets/snippet_store.dart';
import 'package:letsflutssh/features/snippets/snippet_manager_dialog.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/providers/snippet_provider.dart';
import 'package:letsflutssh/theme/app_theme.dart';
import 'package:letsflutssh/widgets/toast.dart';

/// In-memory fake for [SnippetStore] — no database.
class FakeSnippetStore extends SnippetStore {
  final List<Snippet> _snippets;

  FakeSnippetStore([List<Snippet>? initial]) : _snippets = [...?initial];

  @override
  Future<List<Snippet>> loadAll() async =>
      List.of(_snippets)..sort((a, b) => a.title.compareTo(b.title));

  @override
  Future<void> add(Snippet snippet) async => _snippets.add(snippet);

  @override
  Future<void> update(Snippet snippet) async {
    _snippets.removeWhere((s) => s.id == snippet.id);
    _snippets.add(snippet);
  }

  @override
  Future<void> delete(String id) async =>
      _snippets.removeWhere((s) => s.id == id);
}

void main() {
  late FakeSnippetStore fakeStore;

  final testSnippet = Snippet(
    id: 's1',
    title: 'Deploy App',
    command: 'sudo systemctl restart nginx',
    description: 'Restart the web server',
  );

  final snippetNoDesc = Snippet(
    id: 's2',
    title: 'Check Disk',
    command: 'df -h',
  );

  Widget buildApp() {
    return ProviderScope(
      overrides: [snippetStoreProvider.overrideWithValue(fakeStore)],
      child: MaterialApp(
        localizationsDelegates: S.localizationsDelegates,
        supportedLocales: S.supportedLocales,
        theme: AppTheme.dark(),
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => SnippetManagerDialog.show(context),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> openDialog(WidgetTester tester) async {
    await tester.pumpWidget(buildApp());
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  tearDown(() => Toast.clearAllForTest());

  group('SnippetManagerDialog', () {
    testWidgets('shows loading then transitions to content', (tester) async {
      fakeStore = FakeSnippetStore();
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      // After one frame the dialog is visible with the spinner.
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Let async load complete.
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('shows empty state when no snippets', (tester) async {
      fakeStore = FakeSnippetStore();
      await openDialog(tester);

      expect(find.text('No snippets yet'), findsOneWidget);
    });

    testWidgets('shows dialog title Snippets', (tester) async {
      fakeStore = FakeSnippetStore();
      await openDialog(tester);

      expect(find.text('Snippets'), findsOneWidget);
    });

    testWidgets('renders snippet entries with title and command', (
      tester,
    ) async {
      fakeStore = FakeSnippetStore([testSnippet]);
      await openDialog(tester);

      expect(find.text('Deploy App'), findsOneWidget);
      expect(find.text('sudo systemctl restart nginx'), findsOneWidget);
    });

    testWidgets('shows description when present', (tester) async {
      fakeStore = FakeSnippetStore([testSnippet]);
      await openDialog(tester);

      expect(find.text('Restart the web server'), findsOneWidget);
    });

    testWidgets('cancel button closes dialog', (tester) async {
      fakeStore = FakeSnippetStore();
      await openDialog(tester);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // Dialog title should be gone.
      expect(find.text('Snippets'), findsNothing);
    });

    testWidgets('delete button shows confirmation dialog', (tester) async {
      fakeStore = FakeSnippetStore([testSnippet]);
      await openDialog(tester);

      // Tap the delete icon button.
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();

      expect(find.text('Delete Snippet'), findsWidgets);
    });

    testWidgets('delete confirmation removes snippet', (tester) async {
      fakeStore = FakeSnippetStore([testSnippet]);
      await openDialog(tester);

      // Open delete confirmation.
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();

      // Confirm deletion.
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      // Snippet should be gone from the list and store.
      expect(find.text('Deploy App'), findsNothing);
      expect(fakeStore._snippets, isEmpty);

      // Dismiss the success toast and let the overlay dispose cleanly.
      Toast.clearAllForTest();
      await tester.pump();
    });

    testWidgets('delete cancel keeps snippet', (tester) async {
      fakeStore = FakeSnippetStore([testSnippet]);
      await openDialog(tester);

      // Open delete confirmation.
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();

      // Cancel deletion — there are two Cancel buttons (main dialog + confirm
      // dialog). The confirmation dialog's Cancel is on top, so tap the last.
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();

      // Snippet should still be visible.
      expect(find.text('Deploy App'), findsOneWidget);
      expect(fakeStore._snippets, hasLength(1));
    });

    testWidgets('add snippet button opens add dialog with fields', (
      tester,
    ) async {
      fakeStore = FakeSnippetStore();
      await openDialog(tester);

      await tester.tap(find.text('Add Snippet'));
      await tester.pumpAndSettle();

      // Add dialog contains Title, Command, and Description fields.
      expect(find.text('Title'), findsOneWidget);
      expect(find.text('Command'), findsOneWidget);
      expect(find.text('Description (optional)'), findsOneWidget);
    });

    testWidgets('add snippet with title and command saves and shows in list', (
      tester,
    ) async {
      fakeStore = FakeSnippetStore();
      await openDialog(tester);

      // Open add dialog.
      await tester.tap(find.text('Add Snippet'));
      await tester.pumpAndSettle();

      // Fill in title and command.
      await tester.enterText(
        find.widgetWithText(TextField, 'Title'),
        'My Snippet',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Command'),
        'echo hello',
      );

      // Save.
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      // New snippet should be visible in the list.
      expect(find.text('My Snippet'), findsOneWidget);
      expect(find.text('echo hello'), findsOneWidget);
      expect(fakeStore._snippets, hasLength(1));

      // Dismiss the success toast and let the overlay dispose cleanly.
      Toast.clearAllForTest();
      await tester.pump();
    });

    testWidgets('add snippet with empty title does not save', (tester) async {
      fakeStore = FakeSnippetStore();
      await openDialog(tester);

      // Open add dialog.
      await tester.tap(find.text('Add Snippet'));
      await tester.pumpAndSettle();

      // Fill in only the command, leave title empty.
      await tester.enterText(
        find.widgetWithText(TextField, 'Command'),
        'echo hello',
      );

      // Tap Save — dialog should stay open since title is empty.
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      // Add dialog should still be visible (title field still present).
      expect(find.text('Title'), findsOneWidget);
      // Nothing should have been saved.
      expect(fakeStore._snippets, isEmpty);
    });

    testWidgets('edit button opens edit dialog pre-filled', (tester) async {
      fakeStore = FakeSnippetStore([testSnippet]);
      await openDialog(tester);

      // Tap the edit icon button.
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();

      // Edit dialog should be open with pre-filled values.
      expect(find.text('Edit Snippet'), findsWidgets);

      // Fields should be pre-filled with the snippet's data.
      expect(find.widgetWithText(TextField, 'Title'), findsOneWidget);
      final titleField = tester.widget<TextField>(
        find.widgetWithText(TextField, 'Title'),
      );
      expect(titleField.controller?.text, 'Deploy App');

      final commandField = tester.widget<TextField>(
        find.widgetWithText(TextField, 'Command'),
      );
      expect(commandField.controller?.text, 'sudo systemctl restart nginx');

      final descField = tester.widget<TextField>(
        find.widgetWithText(TextField, 'Description (optional)'),
      );
      expect(descField.controller?.text, 'Restart the web server');
    });

    testWidgets('copy button shows command copied toast', (tester) async {
      fakeStore = FakeSnippetStore([snippetNoDesc]);
      await openDialog(tester);

      // Tap the copy icon button.
      await tester.tap(find.byIcon(Icons.content_copy));
      await tester.pumpAndSettle();

      // Toast should appear with the copied message.
      expect(find.text('Command copied to clipboard'), findsOneWidget);

      // Dismiss the toast and let the overlay dispose cleanly.
      Toast.clearAllForTest();
      await tester.pump();
    });
  });
}
