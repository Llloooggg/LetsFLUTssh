/// Widget tests focused on the `_FolderActions` extension that backs
/// the per-folder context menu — rename validation, the
/// create-folder-inside-parent path, the delete-confirm flow with the
/// session-count warning, and the no-op early-returns guarding empty
/// or unchanged folder names.
///
/// `_FolderActions` is a `part of session_panel.dart` extension on
/// [SessionPanelState], so every code path is reached by driving the
/// SessionPanel widget rather than calling the extension directly —
/// the underscore methods are private to the library.
///
/// FRB is bootstrapped because `SessionTree.build` routes through the
/// Rust-side `lfs_core::session_tree` (FRB sync), and `SessionPanel`
/// transitively reads providers that read DB state. The
/// [FakeSessionNotifier] fake stubs writes so a fresh rename / create /
/// delete lands in an in-memory list the tree builder reflects on the
/// next emit.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/session/session.dart';
import 'package:letsflutssh/core/session/session_tree.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/core/security/ssh_key.dart';
import 'package:letsflutssh/core/tags/tag.dart';
import 'package:letsflutssh/features/session_manager/session_panel.dart';
import 'package:letsflutssh/providers/key_provider.dart';
import 'package:letsflutssh/providers/session_provider.dart';
import 'package:letsflutssh/providers/tag_provider.dart';
import 'package:letsflutssh/theme/app_theme.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';

import '../../helpers/fake_session_notifier.dart';
import '../../helpers/frb_bootstrap.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(requireFrbLoaded);

  late FakeSessionNotifier fake;

  setUp(() {
    fake = FakeSessionNotifier(
      sessions: [
        Session(
          id: 's1',
          label: 'web',
          folder: 'Production',
          server: const ServerAddress(host: '10.0.0.1', user: 'root'),
        ),
        Session(
          id: 's2',
          label: 'db',
          folder: 'Production/DB',
          server: const ServerAddress(host: '10.0.1.1', user: 'admin'),
        ),
      ],
      emptyFolders: {'Archive'},
    );
  });

  tearDown(() async {
    await fake.dispose();
  });

  Widget pumpPanel({Widget? extra}) {
    final tree = SessionTree.build(fake.state, emptyFolders: fake.emptyFolders);
    return ProviderScope(
      overrides: [
        ...fake.overrides(),
        sessionsLoadingProvider.overrideWithValue(false),
        sessionSearchProvider.overrideWith(SessionSearchNotifier.new),
        filteredSessionTreeProvider.overrideWithValue(tree),
        sessionTagsProvider.overrideWith((ref, sessionId) async => <Tag>[]),
        sshKeysStreamProvider.overrideWith(
          (_) => Stream.value(const <SshKeyEntry>[]),
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: S.localizationsDelegates,
        supportedLocales: S.supportedLocales,
        theme: AppTheme.dark(),
        home: Scaffold(
          body: SizedBox(
            width: 320,
            height: 600,
            child: SessionPanel(onConnect: (_) {}),
          ),
        ),
      ),
    );
  }

  Future<void> rightClickAt(WidgetTester tester, Offset position) async {
    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await gesture.addPointer(location: position);
    await gesture.down(position);
    await gesture.up();
    await gesture.removePointer();
    await tester.pumpAndSettle();
  }

  Future<void> rightClickText(WidgetTester tester, String label) async {
    final finder = find.text(label);
    expect(finder, findsWidgets);
    await rightClickAt(tester, tester.getCenter(finder.first));
  }

  testWidgets(
    'rename folder dialog: empty name → Rename click is a guarded no-op',
    (tester) async {
      // Contract — `_renameFolder` reads the dialog's return value and
      // early-returns when the trimmed name is empty. The folder list
      // must stay unchanged: no rename emit lands on the fake's
      // mutator. The dialog still closes (the button pop returns ""),
      // and the existing `Production` folder remains.
      await tester.pumpWidget(pumpPanel());
      await tester.pumpAndSettle();

      await rightClickText(tester, 'Production');
      await tester.tap(find.text('Rename Folder'));
      await tester.pumpAndSettle();

      // Clear the prefilled name, then submit — the trimmed-empty
      // guard short-circuits the mutator call.
      final field = find.byType(TextField).last;
      await tester.enterText(field, '   ');
      await tester.pump();
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();

      // The session that lives in `Production` still has that folder
      // path. No rename was applied.
      final s1 = fake.state.firstWhere((s) => s.id == 's1');
      expect(s1.folder, 'Production');
    },
  );

  testWidgets('rename folder dialog: unchanged name returns without mutating', (
    tester,
  ) async {
    // Contract — `_renameFolder` guards `result.trim() == currentName`
    // so the user can dismiss with the prefilled name and not
    // generate a no-op rename event. The fake's `renameFolder`
    // would still rebuild every child path on a true call; pinning
    // the early return keeps the count + IDs intact.
    await tester.pumpWidget(pumpPanel());
    await tester.pumpAndSettle();

    await rightClickText(tester, 'Production');
    await tester.tap(find.text('Rename Folder'));
    await tester.pumpAndSettle();

    // Leave the prefilled `Production` and submit.
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();

    // No change — the child session's folder path is still scoped
    // under the original `Production` parent.
    final child = fake.state.firstWhere((s) => s.id == 's2');
    expect(child.folder, 'Production/DB');
  });

  testWidgets('new folder inside a parent prefixes the parent path', (
    tester,
  ) async {
    // Contract — `_createFolder` joins parent + child as
    // `parentFolder/result.trim()` when the parent path is
    // non-empty (and uses the bare name at root). The resulting
    // path lands on `addEmptyFolder` so the tree picks it up.
    await tester.pumpWidget(pumpPanel());
    await tester.pumpAndSettle();

    await rightClickText(tester, 'Production');
    await tester.tap(find.text('New Folder'));
    await tester.pumpAndSettle();

    final field = find.byType(TextField).last;
    await tester.enterText(field, 'Sub');
    await tester.pump();
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    // The new path lives under the parent — `Production/Sub` is now
    // in the fake's empty-folder set.
    expect(fake.emptyFolders.contains('Production/Sub'), isTrue);
  });

  testWidgets(
    'delete folder confirm dialog surfaces the inside-session count',
    (tester) async {
      // Contract — `_confirmDeleteFolder` looks up
      // `countSessionsInFolder` and shows the styled
      // `willDeleteSessionsInside(N)` line ONLY when N > 0. Without
      // that, the user could delete a populated folder without
      // realising they'd lose the rows under it. `Production` carries
      // 2 sessions (web + Production/DB.db) so the count is 2.
      await tester.pumpWidget(pumpPanel());
      await tester.pumpAndSettle();

      await rightClickText(tester, 'Production');
      await tester.tap(find.text('Delete Folder'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Delete folder "Production"?'),
        findsOneWidget,
      );
      // 2 child sessions land in the inside-count line.
      expect(
        find.textContaining('This will also delete 2 sessions inside.'),
        findsOneWidget,
      );

      // Confirm → the fake removes both child rows.
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(
        fake.state.where((s) => s.folder.startsWith('Production')),
        isEmpty,
      );
    },
  );

  testWidgets(
    'delete folder confirm dialog hides the inside-count line for empty folders',
    (tester) async {
      // Contract — `Archive` is an empty folder (no sessions inside),
      // so `countSessionsInFolder` returns 0 and the styled count
      // line is suppressed. The user still confirms the delete.
      await tester.pumpWidget(pumpPanel());
      await tester.pumpAndSettle();

      await rightClickText(tester, 'Archive');
      await tester.tap(find.text('Delete Folder'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Delete folder "Archive"?'), findsOneWidget);
      // No "X sessions inside" callout — Archive is empty.
      expect(find.textContaining('sessions inside'), findsNothing);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      // Cancel leaves the folder in place.
      expect(fake.emptyFolders.contains('Archive'), isTrue);
    },
  );

  testWidgets(
    'rename folder applies a new name and rewrites child session folders',
    (tester) async {
      // Contract — `_renameFolder` builds `parentPath/result.trim()`
      // when the parent is non-empty (and bare name at root), then
      // hands the pair to `renameFolder`. The fake's mutator rewrites
      // every session whose `folder` field starts with the old path.
      await tester.pumpWidget(pumpPanel());
      await tester.pumpAndSettle();

      await rightClickText(tester, 'Production');
      await tester.tap(find.text('Rename Folder'));
      await tester.pumpAndSettle();

      final field = find.byType(TextField).last;
      await tester.enterText(field, 'Prod');
      await tester.pump();
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();

      final s1 = fake.state.firstWhere((s) => s.id == 's1');
      final s2 = fake.state.firstWhere((s) => s.id == 's2');
      expect(s1.folder, 'Prod');
      // Nested path under the renamed parent rewrites in-place.
      expect(s2.folder, 'Prod/DB');
    },
  );
}
