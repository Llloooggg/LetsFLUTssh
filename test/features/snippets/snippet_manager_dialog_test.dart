import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/snippets/snippet.dart';
import 'package:letsflutssh/features/snippets/snippet_manager_dialog.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/providers/snippet_provider.dart';
import 'package:letsflutssh/theme/app_theme.dart';
import 'package:letsflutssh/widgets/toast.dart';

/// In-memory fake for [SnippetsNotifier] — no database. The dialog
/// drives `add` / `save` / `delete` / `loadAll`; everything else
/// stays at the production default.
class FakeSnippetsNotifier extends SnippetsNotifier {
  FakeSnippetsNotifier([List<Snippet>? initial]) : _snippets = [...?initial];

  final List<Snippet> _snippets;

  @override
  Future<List<Snippet>> build() async => _sorted();

  @override
  Future<List<Snippet>> loadAll() async => _sorted();

  @override
  Future<void> add(Snippet snippet) async {
    _snippets.add(snippet);
    ref.invalidateSelf();
  }

  @override
  Future<void> save(Snippet snippet) async {
    _snippets.removeWhere((s) => s.id == snippet.id);
    _snippets.add(snippet);
    ref.invalidateSelf();
  }

  @override
  Future<void> delete(String id) async {
    _snippets.removeWhere((s) => s.id == id);
    ref.invalidateSelf();
  }

  List<Snippet> _sorted() =>
      List.of(_snippets)..sort((a, b) => a.title.compareTo(b.title));
}

void main() {
  late FakeSnippetsNotifier fakeStore;

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
      overrides: [snippetsProvider.overrideWith(() => fakeStore)],
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

  // The dialog body opens a Scaffold + MaterialApp surface whose
  // system-overlay-style writes touch `flutter/platform`;
  // flutter_test does not stub that channel by default. Stub it so
  // any platform-method call coming from the widget tree drains
  // cleanly in pumpAndSettle instead of throwing a MissingPlugin.
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async => null,
        );
  });

  tearDown(() {
    Toast.clearAllForTest();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  group('SnippetManagerDialog', () {
    testWidgets('shows loading then transitions to content', (tester) async {
      fakeStore = FakeSnippetsNotifier();
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
      fakeStore = FakeSnippetsNotifier();
      await openDialog(tester);

      expect(find.text('No snippets yet'), findsOneWidget);
    });

    testWidgets('shows dialog title Snippets', (tester) async {
      fakeStore = FakeSnippetsNotifier();
      await openDialog(tester);

      expect(find.text('Snippets'), findsOneWidget);
    });

    testWidgets('renders snippet entries with title and command', (
      tester,
    ) async {
      fakeStore = FakeSnippetsNotifier([testSnippet]);
      await openDialog(tester);

      expect(find.text('Deploy App'), findsOneWidget);
      expect(find.text('sudo systemctl restart nginx'), findsOneWidget);
    });

    testWidgets('shows description when present', (tester) async {
      fakeStore = FakeSnippetsNotifier([testSnippet]);
      await openDialog(tester);

      expect(find.text('Restart the web server'), findsOneWidget);
    });

    testWidgets('cancel button closes dialog', (tester) async {
      fakeStore = FakeSnippetsNotifier();
      await openDialog(tester);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // Dialog title should be gone.
      expect(find.text('Snippets'), findsNothing);
    });

    testWidgets('delete button shows confirmation dialog', (tester) async {
      fakeStore = FakeSnippetsNotifier([testSnippet]);
      await openDialog(tester);

      // Tap the delete icon button.
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();

      expect(find.text('Delete Snippet'), findsWidgets);
    });

    testWidgets('delete confirmation removes snippet', (tester) async {
      fakeStore = FakeSnippetsNotifier([testSnippet]);
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
      fakeStore = FakeSnippetsNotifier([testSnippet]);
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
      fakeStore = FakeSnippetsNotifier();
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
      fakeStore = FakeSnippetsNotifier();
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
      fakeStore = FakeSnippetsNotifier();
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
      fakeStore = FakeSnippetsNotifier([testSnippet]);
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

    testWidgets('copy button shows a clipboard toast', (tester) async {
      fakeStore = FakeSnippetsNotifier([snippetNoDesc]);
      await openDialog(tester);

      // Tap the copy icon button.
      await tester.tap(find.byIcon(Icons.content_copy));
      // The async chain through `SecureClipboard().setText` →
      // platform channel → `Clipboard.setData` → toast surface
      // can take a couple of pump cycles to settle in
      // flutter_test; pump twice + a small duration to drain.
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      // Toast appears regardless of which side of the
      // SecureClipboard branch fires under flutter_test —
      // either the success copy or the cloud-leak-refused
      // fallback. The test contract is "tap → toast surfaces",
      // not "the OS clipboard accepted bytes".
      final success = find.text('Command copied to clipboard');
      final failure = find.text('Copy to clipboard failed.');
      expect(
        tester.widgetList(success).length + tester.widgetList(failure).length,
        1,
        reason: 'tap should show exactly one of the two clipboard toasts',
      );

      // Dismiss the toast and let the overlay dispose cleanly.
      Toast.clearAllForTest();
      await tester.pump();
    });
  });
}
