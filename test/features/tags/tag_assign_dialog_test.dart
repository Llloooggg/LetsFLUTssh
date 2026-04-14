import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/tags/tag.dart';
import 'package:letsflutssh/features/tags/tag_assign_dialog.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/providers/tag_provider.dart';
import 'package:letsflutssh/theme/app_theme.dart';
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
      expect(find.text('Manage Tags'), findsOneWidget);
    });

    testWidgets('shows checkboxes for each tag', (tester) async {
      fakeStore = FakeTagStore([testTag, testTag2]);
      await openDialog(tester);

      expect(find.text('Production'), findsOneWidget);
      expect(find.text('Staging'), findsOneWidget);
      expect(find.byType(CheckboxListTile), findsNWidgets(2));
    });

    testWidgets('checking a tag assigns it', (tester) async {
      fakeStore = FakeTagStore([testTag]);
      await openDialog(tester);

      // Tag should be unchecked initially.
      final checkbox = tester.widget<CheckboxListTile>(
        find.byType(CheckboxListTile),
      );
      expect(checkbox.value, isFalse);

      // Tap to assign.
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();

      // Verify the store received the call.
      final assigned = await fakeStore.getForSession('test-session');
      expect(assigned.map((t) => t.id), contains('t1'));
    });

    testWidgets('unchecking a tag unassigns it', (tester) async {
      fakeStore = FakeTagStore([testTag]);
      // Pre-assign the tag.
      await fakeStore.tagSession('test-session', testTag.id);
      await openDialog(tester);

      // Tag should be checked initially.
      final checkbox = tester.widget<CheckboxListTile>(
        find.byType(CheckboxListTile),
      );
      expect(checkbox.value, isTrue);

      // Tap to unassign.
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();

      // Verify the store no longer has the assignment.
      final assigned = await fakeStore.getForSession('test-session');
      expect(assigned, isEmpty);
    });

    testWidgets('shows correct initial state with pre-assigned tags checked', (
      tester,
    ) async {
      fakeStore = FakeTagStore([testTag, testTag2]);
      // Pre-assign only the first tag.
      await fakeStore.tagSession('test-session', testTag.id);
      await openDialog(tester);

      final checkboxes = tester.widgetList<CheckboxListTile>(
        find.byType(CheckboxListTile),
      );
      final values = checkboxes.map((cb) => cb.value).toList();

      // Production (t1) is assigned, Staging (t2) is not.
      // Tags are sorted by name: Production comes first.
      expect(values, [true, false]);
    });

    testWidgets('close button dismisses dialog', (tester) async {
      fakeStore = FakeTagStore();
      await openDialog(tester);

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      // Dialog title should be gone.
      expect(find.text('Edit Tags'), findsNothing);
    });
  });
}
