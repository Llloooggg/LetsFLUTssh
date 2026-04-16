import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/tags/tag.dart';
import 'package:letsflutssh/features/tags/tag_assign_dialog.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/providers/tag_provider.dart';
import 'package:letsflutssh/theme/app_theme.dart';
import 'package:letsflutssh/widgets/data_checkboxes.dart';
import 'package:letsflutssh/widgets/toast.dart';

import 'tag_manager_dialog_test.dart';

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
              onPressed: () => TagAssignDialog.showForSession(
                context,
                sessionId: 'test-session',
              ),
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

  /// Finds the data checkbox row whose label reads [text]. The select-all
  /// header and the per-tag rows all render as [DataCheckboxRow], so the
  /// label match is what disambiguates them.
  Finder tagRow(String text) => find.ancestor(
    of: find.text(text),
    matching: find.byType(DataCheckboxRow),
  );

  tearDown(() => Toast.clearAllForTest());

  group('TagAssignDialog', () {
    testWidgets('shows "Edit Tags" title', (tester) async {
      fakeStore = FakeTagStore();
      await openDialog(tester);

      expect(find.text('Edit Tags'), findsOneWidget);
    });

    testWidgets('shows empty state when no tags exist', (tester) async {
      fakeStore = FakeTagStore();
      await openDialog(tester);

      expect(find.text('No tags yet'), findsOneWidget);
      // Manage Tags lives in the footer; the body shows the empty-state
      // icon + message (no duplicate button in the body).
      expect(find.text('Manage Tags'), findsOneWidget);
    });

    testWidgets('renders each tag as a data checkbox row', (tester) async {
      fakeStore = FakeTagStore([testTag, testTag2]);
      await openDialog(tester);

      expect(tagRow('Production'), findsOneWidget);
      expect(tagRow('Staging'), findsOneWidget);
    });

    testWidgets('tapping an unassigned tag row assigns it', (tester) async {
      fakeStore = FakeTagStore([testTag]);
      await openDialog(tester);

      await tester.tap(tagRow('Production'));
      await tester.pumpAndSettle();

      final assigned = await fakeStore.getForSession('test-session');
      expect(assigned.map((t) => t.id), contains('t1'));
    });

    testWidgets('tapping an assigned tag row unassigns it', (tester) async {
      fakeStore = FakeTagStore([testTag]);
      await fakeStore.tagSession('test-session', testTag.id);
      await openDialog(tester);

      await tester.tap(tagRow('Production'));
      await tester.pumpAndSettle();

      final assigned = await fakeStore.getForSession('test-session');
      expect(assigned, isEmpty);
    });

    testWidgets('pre-assigned tag shows checked, other unchecked', (
      tester,
    ) async {
      fakeStore = FakeTagStore([testTag, testTag2]);
      await fakeStore.tagSession('test-session', testTag.id);
      await openDialog(tester);

      // Tags are sorted by name → Production first.
      final productionRow = tester.widget<DataCheckboxRow>(
        tagRow('Production'),
      );
      final stagingRow = tester.widget<DataCheckboxRow>(tagRow('Staging'));
      expect(productionRow.value, isTrue);
      expect(stagingRow.value, isFalse);
    });

    testWidgets('select-all toggles every tag at once', (tester) async {
      fakeStore = FakeTagStore([testTag, testTag2]);
      await openDialog(tester);

      // The select-all row is labelled "Select all" and shows the
      // "0 / 2" counter.
      final selectAll = tagRow('Select All');
      expect(selectAll, findsOneWidget);

      await tester.tap(selectAll);
      await tester.pumpAndSettle();

      final assigned = await fakeStore.getForSession('test-session');
      expect(assigned.map((t) => t.id).toSet(), {'t1', 't2'});
    });

    testWidgets('select-all with all assigned clears every tag', (
      tester,
    ) async {
      fakeStore = FakeTagStore([testTag, testTag2]);
      await fakeStore.tagSession('test-session', testTag.id);
      await fakeStore.tagSession('test-session', testTag2.id);
      await openDialog(tester);

      await tester.tap(tagRow('Select All'));
      await tester.pumpAndSettle();

      final assigned = await fakeStore.getForSession('test-session');
      expect(assigned, isEmpty);
    });

    testWidgets('search field only appears past the threshold', (tester) async {
      // Two tags — well under the threshold, no search box.
      fakeStore = FakeTagStore([testTag, testTag2]);
      await openDialog(tester);
      expect(find.byIcon(Icons.search), findsNothing);

      // Close the dialog so the next pump rebuilds clean.
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      // Seven tags — search field appears.
      final many = [
        for (var i = 0; i < 7; i++)
          Tag(id: 't$i', name: 'Tag $i', createdAt: DateTime(2024, 1, i + 1)),
      ];
      fakeStore = FakeTagStore(many);
      await openDialog(tester);
      expect(find.byIcon(Icons.search), findsOneWidget);
    });

    testWidgets('close button dismisses dialog', (tester) async {
      fakeStore = FakeTagStore();
      await openDialog(tester);

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      expect(find.text('Edit Tags'), findsNothing);
    });
  });
}
