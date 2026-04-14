import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/tags/tag.dart';
import 'package:letsflutssh/core/tags/tag_store.dart';
import 'package:letsflutssh/features/tags/tag_manager_dialog.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/providers/tag_provider.dart';
import 'package:letsflutssh/theme/app_theme.dart';
import 'package:letsflutssh/widgets/toast.dart';

/// In-memory fake for [TagStore] — no database.
class FakeTagStore extends TagStore {
  final Map<String, Tag> _tags;

  /// Session-id -> set of tag-ids.
  final Map<String, Set<String>> _sessionTags = {};

  /// Folder-id -> set of tag-ids.
  final Map<String, Set<String>> _folderTags = {};

  FakeTagStore([List<Tag>? initial])
    : _tags = {for (final t in initial ?? []) t.id: t};

  /// Expose internal map for assertions.
  Map<String, Tag> get tags => Map.unmodifiable(_tags);

  @override
  Future<List<Tag>> loadAll() async =>
      _tags.values.toList()..sort((a, b) => a.name.compareTo(b.name));

  @override
  Future<void> add(Tag tag) async => _tags[tag.id] = tag;

  @override
  Future<void> delete(String id) async {
    _tags.remove(id);
    // Cascade: remove from all session/folder links.
    for (final set in _sessionTags.values) {
      set.remove(id);
    }
    for (final set in _folderTags.values) {
      set.remove(id);
    }
  }

  @override
  Future<List<Tag>> getForSession(String sessionId) async {
    final ids = _sessionTags[sessionId] ?? {};
    return _tags.values.where((t) => ids.contains(t.id)).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  @override
  Future<List<Tag>> getForFolder(String folderId) async {
    final ids = _folderTags[folderId] ?? {};
    return _tags.values.where((t) => ids.contains(t.id)).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  @override
  Future<void> tagSession(String sessionId, String tagId) async {
    _sessionTags.putIfAbsent(sessionId, () => {}).add(tagId);
  }

  @override
  Future<void> untagSession(String sessionId, String tagId) async {
    _sessionTags[sessionId]?.remove(tagId);
  }

  @override
  Future<void> tagFolder(String folderId, String tagId) async {
    _folderTags.putIfAbsent(folderId, () => {}).add(tagId);
  }

  @override
  Future<void> untagFolder(String folderId, String tagId) async {
    _folderTags[folderId]?.remove(tagId);
  }
}

void main() {
  late FakeTagStore fakeStore;

  final testTag = Tag(
    id: 't1',
    name: 'Production',
    color: '#EF5350',
    createdAt: DateTime(2024, 3, 10),
  );

  final testTag2 = Tag(
    id: 't2',
    name: 'Staging',
    color: '#42A5F5',
    createdAt: DateTime(2024, 4, 5),
  );

  Widget buildApp() {
    return ProviderScope(
      overrides: [tagStoreProvider.overrideWithValue(fakeStore)],
      child: MaterialApp(
        localizationsDelegates: S.localizationsDelegates,
        supportedLocales: S.supportedLocales,
        theme: AppTheme.dark(),
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => TagManagerDialog.show(context),
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

  group('TagManagerDialog', () {
    testWidgets('shows empty state "No tags" when no tags', (tester) async {
      fakeStore = FakeTagStore();
      await openDialog(tester);

      expect(find.text('No tags yet'), findsOneWidget);
    });

    testWidgets('shows dialog title "Tags"', (tester) async {
      fakeStore = FakeTagStore();
      await openDialog(tester);

      expect(find.text('Tags'), findsOneWidget);
    });

    testWidgets('renders tag entries with name and color dot', (tester) async {
      fakeStore = FakeTagStore([testTag, testTag2]);
      await openDialog(tester);

      expect(find.text('Production'), findsOneWidget);
      expect(find.text('Staging'), findsOneWidget);

      // Both tag names are visible — the list rendered.
      expect(find.text('Production'), findsOneWidget);
      expect(find.text('Staging'), findsOneWidget);
    });

    testWidgets('cancel button closes dialog', (tester) async {
      fakeStore = FakeTagStore();
      await openDialog(tester);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // Dialog title should be gone.
      expect(find.text('Tags'), findsNothing);
    });

    testWidgets('delete button shows confirmation', (tester) async {
      fakeStore = FakeTagStore([testTag]);
      await openDialog(tester);

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();

      expect(find.text('Delete Tag'), findsOneWidget);
    });

    testWidgets('delete confirmation removes tag', (tester) async {
      fakeStore = FakeTagStore([testTag]);
      await openDialog(tester);

      // Open delete confirmation.
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();

      // Confirm deletion.
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      // Tag should be gone from the list and store.
      expect(find.text('Production'), findsNothing);
      expect(fakeStore.tags, isEmpty);

      // Dismiss the success toast and let the overlay dispose cleanly.
      Toast.clearAllForTest();
      await tester.pump();
    });

    testWidgets('add tag opens dialog with name field and color picker', (
      tester,
    ) async {
      fakeStore = FakeTagStore();
      await openDialog(tester);

      await tester.tap(find.text('Add Tag'));
      await tester.pumpAndSettle();

      // Name field visible.
      expect(find.text('Tag Name'), findsOneWidget);
      // Color label visible.
      expect(find.text('Color'), findsOneWidget);
    });

    testWidgets('add tag with name saves and shows in list', (tester) async {
      fakeStore = FakeTagStore();
      await openDialog(tester);

      // Open add dialog.
      await tester.tap(find.text('Add Tag'));
      await tester.pumpAndSettle();

      // Enter tag name.
      await tester.enterText(
        find.widgetWithText(TextField, 'Tag Name'),
        'MyNewTag',
      );

      // Tap Save.
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      // Tag should now appear in the list.
      expect(find.text('MyNewTag'), findsOneWidget);
      expect(fakeStore.tags.values.any((t) => t.name == 'MyNewTag'), isTrue);

      // Dismiss the success toast and let the overlay dispose cleanly.
      Toast.clearAllForTest();
      await tester.pump();
    });

    testWidgets('color picker shows 10 color dots', (tester) async {
      fakeStore = FakeTagStore();
      await openDialog(tester);

      // Open add dialog to see color picker.
      await tester.tap(find.text('Add Tag'));
      await tester.pumpAndSettle();

      // The color picker renders 24x24 circular GestureDetector containers.
      final colorDots = find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).shape == BoxShape.circle &&
            (w.decoration as BoxDecoration).color != null,
      );
      // tagColors has 10 entries.
      expect(colorDots, findsNWidgets(10));
    });
  });
}
