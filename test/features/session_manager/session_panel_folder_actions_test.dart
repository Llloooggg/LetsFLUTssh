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
    'folder context menu — copy folder path lands on the controller clipboard '
    'state (clipboard entry then becomes available for paste)',
    (tester) async {
      // Contract — `StandardMenuAction.copy.item` on a folder row
      // calls `_ctrl.copyFolderPath(folderPath)`. After the call the
      // session-panel controller reports `hasClipboardEntry == true`
      // so a subsequent right-click on a sibling folder shows the
      // Paste row (the visibility gate `_ctrl.hasClipboardEntry`).
      // Pins the controller mutation contract — a forgotten clipboard
      // write would surface here because the Paste row never appears.
      await tester.pumpWidget(pumpPanel());
      await tester.pumpAndSettle();

      await rightClickText(tester, 'Production');
      await tester.tap(find.text('Copy'));
      await tester.pumpAndSettle();

      // Right-click another folder — the Paste item must now appear
      // because the controller has a clipboard entry.
      await rightClickText(tester, 'Archive');
      expect(find.text('Paste'), findsOneWidget);
    },
  );

  testWidgets(
    'folder context menu — Edit Tags is a no-op when folderIdByPath returns '
    'null (fresh fake without DB-side folder rows)',
    (tester) async {
      // Contract — the editTags item reads `folderIdByPath` and
      // only opens `TagAssignDialog.showForFolder` for a non-null
      // id. The fake's mutator returns null for unknown paths, so
      // the action must short-circuit silently — no dialog opens
      // and no exception propagates. Pins the null-guard: a
      // future change that forgot the null check would crash on
      // the implicit-bang inside TagAssignDialog.
      await tester.pumpWidget(pumpPanel());
      await tester.pumpAndSettle();

      await rightClickText(tester, 'Production');
      await tester.tap(find.text('Edit Tags'));
      await tester.pumpAndSettle();

      // No tag-assign dialog opened. The localized dialog title
      // would surface otherwise.
      expect(find.text('Edit Tags'), findsNothing);
    },
  );

  testWidgets(
    'folder context menu — non-root folder surfaces the full vocabulary: '
    'New Connection / New Folder / Copy / Cut / Rename Folder / Edit Tags / '
    'Delete Folder',
    (tester) async {
      // Contract — `_showFolderContextMenu` builds the menu from a
      // fixed shape; the `folderPath.isNotEmpty` block is where the
      // copy / cut / rename / editTags / delete vocabulary surfaces.
      // Pins the inventory so a future re-ordering / drop of one of
      // the action items would regress here. Root-folder coverage of
      // the inverse (suppressed block) belongs in the session-panel
      // integration test that can drive the right-click on an empty
      // tree region — the unit harness can't synthesise that gesture
      // reliably.
      await tester.pumpWidget(pumpPanel());
      await tester.pumpAndSettle();

      await rightClickText(tester, 'Production');

      // Full per-folder vocabulary surfaces.
      expect(find.text('New Connection'), findsOneWidget);
      expect(find.text('New Folder'), findsOneWidget);
      expect(find.text('Copy'), findsOneWidget);
      expect(find.text('Cut'), findsOneWidget);
      expect(find.text('Rename Folder'), findsOneWidget);
      expect(find.text('Edit Tags'), findsOneWidget);
      expect(find.text('Delete Folder'), findsOneWidget);
    },
  );

  testWidgets(
    'rename folder dialog: cancel button leaves the folder + sessions intact',
    (tester) async {
      // Contract — `_showFolderNameDialog`'s Cancel button pops the
      // dialog with null. `_renameFolder` early-returns on null so
      // no mutator call lands. Pins the cancel path against an
      // accidental no-op rename that still rebuilt child paths.
      await tester.pumpWidget(pumpPanel());
      await tester.pumpAndSettle();

      await rightClickText(tester, 'Production');
      await tester.tap(find.text('Rename Folder'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      final s1 = fake.state.firstWhere((s) => s.id == 's1');
      final s2 = fake.state.firstWhere((s) => s.id == 's2');
      expect(s1.folder, 'Production');
      expect(s2.folder, 'Production/DB');
    },
  );

  testWidgets(
    'new folder dialog: typing the name of an existing sibling surfaces the '
    '"already exists" error from the onChange duplicate guard',
    (tester) async {
      // Contract — `_showFolderNameDialog` builds the duplicate
      // check inside its onChanged: when the typed name combined
      // with the parent path matches an existing folder, the
      // `errorText` flips to `folderAlreadyExists(name)`. Pins the
      // duplicate-guard — without it, the user could create
      // siblings sharing a path and the tree would collapse them.
      //
      // Fixture has `Production` and `Production/DB`. Opening
      // New Folder on `Production` and typing `DB` joins to
      // `Production/DB`, which is in the existing-folders set →
      // error renders.
      await tester.pumpWidget(pumpPanel());
      await tester.pumpAndSettle();

      await rightClickText(tester, 'Production');
      await tester.tap(find.text('New Folder'));
      await tester.pumpAndSettle();

      final field = find.byType(TextField).last;
      await tester.enterText(field, 'DB');
      await tester.pumpAndSettle();

      // The error template includes the typed name.
      expect(find.textContaining('already exists'), findsOneWidget);
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

  testWidgets(
    'cut on a folder + paste into a sibling moves the folder via the explicit '
    'target path (mutator.moveFolder is called with the right pair)',
    (tester) async {
      // Contract — the context-menu Cut entry routes to
      // `_ctrl.cutFolderPath(folderPath)`. Right-clicking a sibling
      // folder and tapping Paste lands on `pasteCopiedSession` with an
      // `explicitTarget` of the sibling path; the cut-pending branch
      // routes to `mutator.moveFolder(folderPath, target)`. Pins the
      // cut-pending arm of the folder-side paste — the copy/duplicate
      // path covered separately produces a `-copy` row, while a cut
      // rewrites the existing folder in place.
      await tester.pumpWidget(pumpPanel());
      await tester.pumpAndSettle();

      // Cut `Production` then right-click `Archive` and paste — moves
      // Production under Archive.
      await rightClickText(tester, 'Production');
      await tester.tap(find.text('Cut'));
      await tester.pumpAndSettle();

      await rightClickText(tester, 'Archive');
      // The paste row only appears when the controller has a clipboard
      // entry — pin that the cut produced one, then exercise paste.
      expect(find.text('Paste'), findsOneWidget);
      await tester.tap(find.text('Paste'));
      await tester.pumpAndSettle();

      // The fake's `moveFolder` rebuilds child paths under the new
      // parent — the previously-`Production/DB` row becomes
      // `Archive/Production/DB`; `Production` itself becomes
      // `Archive/Production`.
      final s1 = fake.state.firstWhere((s) => s.id == 's1');
      final s2 = fake.state.firstWhere((s) => s.id == 's2');
      expect(s1.folder, 'Archive/Production');
      expect(s2.folder, 'Archive/Production/DB');
    },
  );

  testWidgets(
    'copy then cut on a different folder replaces the clipboard entry — only '
    'the latest target lands on paste (mutually-exclusive clipboard slots)',
    (tester) async {
      // Contract — `_copiedSessionId`, `_copiedFolderPath`, and
      // `_cutPending` live as a single mutually-exclusive slot on the
      // controller (`copyFolderPath` clears the cut bit, `cutFolderPath`
      // sets it). A user who copies one folder, then cuts another,
      // must see only the cut target on subsequent paste. Pins the
      // mutual-exclusion guarantee — a stale-copy bug would surface as
      // a duplicate-instead-of-move on the next paste.
      await tester.pumpWidget(pumpPanel());
      await tester.pumpAndSettle();

      // Copy `Production` first.
      await rightClickText(tester, 'Production');
      await tester.tap(find.text('Copy'));
      await tester.pumpAndSettle();

      // Cut `Archive` next — overrides the clipboard slot.
      await rightClickText(tester, 'Archive');
      await tester.tap(find.text('Cut'));
      await tester.pumpAndSettle();

      // Right-click `Production` and paste — the explicit target is
      // `Production`. The cut-pending branch on `Archive` fires
      // `moveFolder('Archive', 'Production')` which under the fake's
      // `renameFolder` rewrites the empty-folder slot from `Archive` to
      // `Production/Archive`. `Production` itself + the session under
      // it stay put — the cut only moves the clipboarded path.
      await rightClickText(tester, 'Production');
      expect(find.text('Paste'), findsOneWidget);
      await tester.tap(find.text('Paste'));
      await tester.pumpAndSettle();

      // Production's own session row was not touched — only the cut
      // target moved. (If the stale copy from before the cut had
      // leaked through, the `Production` slot would have been
      // duplicated under `Production/Production` instead.)
      final s1 = fake.state.firstWhere((s) => s.id == 's1');
      expect(s1.folder, 'Production');
      // The cut routed `Archive` under the right-clicked `Production`.
      // `Archive` no longer exists at root; the rewritten slot lives
      // at `Production/Archive` (fake.renameFolder semantics).
      expect(fake.emptyFolders.contains('Archive'), isFalse);
      expect(fake.emptyFolders.contains('Production/Archive'), isTrue);
    },
  );

  testWidgets(
    'new folder dialog: Cancel before typing returns null and `addEmptyFolder` '
    'is not called',
    (tester) async {
      // Contract — `_createFolder` early-returns on null or
      // trimmed-empty results. The dialog's Cancel button pops with
      // null; `addEmptyFolder` must not land on the mutator. Pins the
      // cancel arm of the new-folder dialog — distinct from the
      // rename-cancel test above because the create path joins the
      // parent path differently and a regression here would silently
      // emit an empty-named folder ("Production/").
      await tester.pumpWidget(pumpPanel());
      await tester.pumpAndSettle();

      final beforeFolders = Set<String>.of(fake.emptyFolders);

      await rightClickText(tester, 'Production');
      await tester.tap(find.text('New Folder'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // No mutation — the empty-folder set is identical to the snapshot.
      expect(fake.emptyFolders, beforeFolders);
    },
  );

  testWidgets(
    'folder context menu — Paste row is hidden when the controller has no '
    'clipboard entry (action surface follows disable-vs-hide)',
    (tester) async {
      // Contract — the Paste item is gated on
      // `_ctrl.hasClipboardEntry`. CLAUDE.md's disable-vs-hide rule
      // says action surfaces hide unusable entries (vs config surfaces
      // which disable + explain); the context menu is an action
      // surface, so a fresh controller without a copy / cut renders
      // the menu without the Paste row at all. Pins the hide arm —
      // without it, the user would see a dead "Paste" entry on first
      // right-click.
      await tester.pumpWidget(pumpPanel());
      await tester.pumpAndSettle();

      await rightClickText(tester, 'Production');
      // Other vocabulary still present (sanity check the menu opened).
      expect(find.text('Copy'), findsOneWidget);
      // Paste row absent because the controller has no clipboard entry.
      expect(find.text('Paste'), findsNothing);
    },
  );
}
