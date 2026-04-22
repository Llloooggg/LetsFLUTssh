import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/ssh/known_hosts.dart';
import 'package:letsflutssh/features/settings/known_hosts_manager.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/providers/connection_provider.dart';
import 'package:letsflutssh/theme/app_theme.dart';
import 'package:letsflutssh/widgets/app_dialog.dart';

void main() {
  late Directory tempDir;
  late KnownHostsManager manager;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = await Directory.systemTemp.createTemp('khm_dialog_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
    manager = KnownHostsManager();
    // Pre-load so the dialog's initState gets a cached future immediately —
    // avoids transient spinner state where pumpAndSettle hangs forever on
    // the indeterminate CircularProgressIndicator animation.
    await manager.load();
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Widget buildApp(KnownHostsManager mgr) {
    return ProviderScope(
      overrides: [knownHostsProvider.overrideWithValue(mgr)],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: S.localizationsDelegates,
        supportedLocales: S.supportedLocales,
        theme: AppTheme.dark(),
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => KnownHostsManagerDialog.show(context),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
  }

  /// Opens the dialog and waits past the loading spinner.
  ///
  /// We use `runAsync` so the real async [KnownHostsManager.load] microtask
  /// resolves, then `pump` to apply the resulting `setState(_loading=false)`.
  /// `pumpAndSettle` is unsafe here — the indeterminate
  /// `CircularProgressIndicator` animation never quiesces.
  Future<void> openDialog(WidgetTester tester) async {
    await tester.tap(find.text('Open'));
    await tester.pump(); // start dialog route + initState
    // Let the await on _manager.load() resolve in a real microtask.
    await tester.runAsync(() => Future<void>.value());
    // Apply the setState that ran inside _loadHosts.
    await tester.pump();
  }

  group('KnownHostsManagerDialog', () {
    testWidgets('shows content (no spinner) after load', (tester) async {
      await tester.pumpWidget(buildApp(manager));
      await openDialog(tester);

      // Dialog title should be visible — confirms dialog mounted.
      expect(find.text('Known Hosts'), findsOneWidget);
      // After load completes, spinner should be gone.
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('shows empty state when no hosts', (tester) async {
      await tester.pumpWidget(buildApp(manager));
      await openDialog(tester);

      expect(
        find.text('No known hosts yet. Connect to a server to add one.'),
        findsOneWidget,
      );
    });

    testWidgets('shows dialog title', (tester) async {
      await tester.pumpWidget(buildApp(manager));
      await openDialog(tester);

      expect(find.text('Known Hosts'), findsOneWidget);
    });

    testWidgets('search field appears once the list has at least one host', (
      tester,
    ) async {
      // The shared `AppCollectionToolbar` hides the search bar on
      // the empty branch — the centered empty-state below it owns
      // that signal already, and a useless search box above no
      // content was visual noise. Confirm the toolbar switches
      // back to showing the search bar once a host lands in the
      // list.
      //
      // `importFromString` awaits the real-zone `_loadFuture` from
      // setUp, which FakeAsync inside `testWidgets` can't advance
      // — must run it via `tester.runAsync`, same pattern as
      // `populate` below.
      await tester.runAsync(
        () => manager.importFromString(
          'example.com ssh-ed25519 AAAAAAAAAAAAAAAAAAAAAAAA\n',
        ),
      );
      await tester.pumpWidget(buildApp(manager));
      await openDialog(tester);

      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('clear all button is hidden when empty', (tester) async {
      // Clear-all is an action; on action surfaces we hide unavailable
      // controls rather than rendering them greyed-out (see the
      // disable-vs-hide rule in CLAUDE.md).
      await tester.pumpWidget(buildApp(manager));
      await openDialog(tester);

      final clearAllBtn = find.byWidgetPredicate(
        (w) =>
            w is IconButton &&
            w.icon is Icon &&
            (w.icon as Icon).icon == Icons.delete_sweep,
      );
      expect(clearAllBtn, findsNothing);
    });
  });

  group('KnownHostsManagerDialog — with populated hosts', () {
    // Valid base64 of 32 zero bytes — fingerprint() can decode it.
    final validKeyB64 = base64Encode(List<int>.filled(32, 0));

    // Populate via `runAsync` — importFromString awaits the real-zone
    // `_loadFuture` from setUp, which FakeAsync can't advance.
    Future<void> populate(
      WidgetTester tester,
      KnownHostsManager mgr, {
      Map<String, String>? hosts,
    }) async {
      final entries =
          hosts ??
          {
            'example.com:22': 'ssh-ed25519 $validKeyB64',
            'other.net:2222': 'ssh-rsa $validKeyB64',
            'broken.host:22': 'ssh-ed25519 !!!not-base64!!!',
          };
      final content = entries.entries
          .map((e) => '${e.key} ${e.value}')
          .join('\n');
      await tester.runAsync(() => mgr.importFromString(content));
    }

    testWidgets('renders host entries with fingerprints', (tester) async {
      await populate(tester, manager);
      await tester.pumpWidget(buildApp(manager));
      await openDialog(tester);

      expect(find.text('example.com:22'), findsOneWidget);
      expect(find.text('other.net:2222'), findsOneWidget);
      // Broken entry still renders — fingerprint falls back to '?'
      expect(find.text('broken.host:22'), findsOneWidget);
    });

    testWidgets('filter narrows list by host and key type', (tester) async {
      await populate(tester, manager);
      await tester.pumpWidget(buildApp(manager));
      await openDialog(tester);

      await tester.enterText(find.byType(TextField), 'example');
      await tester.pump();
      expect(find.text('example.com:22'), findsOneWidget);
      expect(find.text('other.net:2222'), findsNothing);

      await tester.enterText(find.byType(TextField), 'ssh-rsa');
      await tester.pump();
      expect(find.text('example.com:22'), findsNothing);
      expect(find.text('other.net:2222'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '');
      await tester.pump();
      expect(find.text('example.com:22'), findsOneWidget);
    });

    testWidgets('each entry row has delete + copy buttons', (tester) async {
      await populate(
        tester,
        manager,
        hosts: {
          'example.com:22': 'ssh-ed25519 $validKeyB64',
          'other.net:2222': 'ssh-rsa $validKeyB64',
        },
      );
      await tester.pumpWidget(buildApp(manager));
      await openDialog(tester);

      final deleteBtns = find.byWidgetPredicate(
        (w) =>
            w is IconButton &&
            w.icon is Icon &&
            (w.icon as Icon).icon == Icons.delete_outline,
      );
      expect(deleteBtns, findsNWidgets(2));

      final copyBtns = find.byWidgetPredicate(
        (w) =>
            w is IconButton &&
            w.icon is Icon &&
            (w.icon as Icon).icon == Icons.content_copy,
      );
      expect(copyBtns, findsNWidgets(2));
    });

    testWidgets('clear all button enabled when entries exist', (tester) async {
      await populate(tester, manager);
      await tester.pumpWidget(buildApp(manager));
      await openDialog(tester);

      final clearBtn = find.byWidgetPredicate(
        (w) =>
            w is IconButton &&
            w.icon is Icon &&
            (w.icon as Icon).icon == Icons.delete_sweep,
      );
      final btn = tester.widget<IconButton>(clearBtn);
      expect(btn.onPressed, isNotNull);
    });

    testWidgets('host count label reflects total', (tester) async {
      await populate(tester, manager);
      await tester.pumpWidget(buildApp(manager));
      await openDialog(tester);

      expect(find.textContaining('3'), findsWidgets);
    });
  });

  // ===========================================================================
  // Specs derived from known_hosts_manager.dart:
  //
  //  * Delete row shows a confirmation dialog first; confirming calls
  //    removeHost and the row disappears. Cancelling leaves the store
  //    untouched — no accidental deletion from a misclick.
  //  * Clear-all is gated by confirmation too. If the user confirms,
  //    every host is gone; if they cancel, every host stays.
  //  * Copy-fingerprint row button writes the fingerprint to the system
  //    clipboard via Clipboard.setData and surfaces a toast — the user
  //    has no other way to read the short SHA256 out of the UI.
  //  * Export on mobile writes nothing to disk (no save-file picker on
  //    phones) — it copies the full known_hosts text to the clipboard so
  //    the user can paste it elsewhere.
  //  * Export with zero hosts short-circuits to a "nothing to export"
  //    toast regardless of platform, because saving or copying an empty
  //    file is always a no-op and always a user mistake.
  // ===========================================================================
  group('KnownHostsManagerDialog — destructive actions', () {
    final validKeyB64 = base64Encode(List<int>.filled(32, 0));

    Future<void> populate(WidgetTester tester, KnownHostsManager mgr) async {
      final content =
          'example.com:22 ssh-ed25519 $validKeyB64\n'
          'other.net:2222 ssh-rsa $validKeyB64\n';
      await tester.runAsync(() => mgr.importFromString(content));
    }

    Future<void> openDialogAfterPopulate(WidgetTester tester) async {
      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.runAsync(() => Future<void>.value());
      await tester.pump();
    }

    testWidgets(
      'deleting a row shows confirm dialog; confirming removes that row only',
      (tester) async {
        await populate(tester, manager);
        await tester.pumpWidget(buildApp(manager));
        await openDialogAfterPopulate(tester);

        expect(find.text('example.com:22'), findsOneWidget);
        expect(find.text('other.net:2222'), findsOneWidget);

        // Tap the delete icon on the first row.
        final deleteBtns = find.byWidgetPredicate(
          (w) =>
              w is IconButton &&
              w.icon is Icon &&
              (w.icon as Icon).icon == Icons.delete_outline,
        );
        await tester.tap(deleteBtns.first);
        await tester.pumpAndSettle();

        // Confirm dialog is up.
        expect(find.text('Remove Host'), findsOneWidget);

        // Tap Delete (destructive action inside the confirm dialog).
        // AppButton.destructive returns a private subclass, so match
        // via `is AppButton` + label.
        await tester.tap(
          find.byWidgetPredicate(
            (w) => w is AppButton && w.label == 'Delete',
          ),
        );
        // removeHost awaits its own I/O-free Future — let the microtasks run,
        // then pump(3s+) so Toast.show's Timer fires and the tree can be
        // torn down cleanly at the end of the test.
        await tester.runAsync(() => Future<void>.value());
        await tester.pump();
        await tester.pump(const Duration(seconds: 4));

        // Alphabetical order: example.com comes before other.net, so the
        // first row was example.com. After confirm it must be gone; the
        // second row stays.
        expect(manager.entries.containsKey('example.com:22'), isFalse);
        expect(manager.entries.containsKey('other.net:2222'), isTrue);
        expect(find.text('example.com:22'), findsNothing);
        expect(find.text('other.net:2222'), findsOneWidget);
      },
    );

    testWidgets(
      'cancelling the remove-host confirmation leaves the store untouched',
      (tester) async {
        await populate(tester, manager);
        await tester.pumpWidget(buildApp(manager));
        await openDialogAfterPopulate(tester);

        final deleteBtns = find.byWidgetPredicate(
          (w) =>
              w is IconButton &&
              w.icon is Icon &&
              (w.icon as Icon).icon == Icons.delete_outline,
        );
        await tester.tap(deleteBtns.first);
        await tester.pumpAndSettle();

        expect(find.text('Remove Host'), findsOneWidget);
        // Outer KnownHostsManagerDialog also has a Cancel; `.last` picks
        // the inner confirm's Cancel (pushed on top of the tree).
        await tester.tap(
          find
              .byWidgetPredicate(
                (w) => w is AppButton && w.label == 'Cancel',
              )
              .last,
        );
        await tester.pumpAndSettle();

        // Both hosts still there.
        expect(find.text('example.com:22'), findsOneWidget);
        expect(find.text('other.net:2222'), findsOneWidget);
        expect(manager.entries, hasLength(2));
      },
    );

    testWidgets('clear-all confirm wipes every host; cancel keeps them', (
      tester,
    ) async {
      await populate(tester, manager);
      await tester.pumpWidget(buildApp(manager));
      await openDialogAfterPopulate(tester);

      // Cancel first.
      final clearBtn = find.byWidgetPredicate(
        (w) =>
            w is IconButton &&
            w.icon is Icon &&
            (w.icon as Icon).icon == Icons.delete_sweep,
      );
      await tester.tap(clearBtn);
      await tester.pumpAndSettle();
      expect(find.text('Clear All Known Hosts'), findsWidgets);
      // Two Cancel buttons exist once the confirm is up (outer dialog +
      // inner confirm). The confirm is pushed on top, so `.last` targets
      // it in widget-tree order.
      await tester.tap(
        find
            .byWidgetPredicate(
              (w) => w is AppButton && w.label == 'Cancel',
            )
            .last,
      );
      await tester.pumpAndSettle();
      expect(manager.entries, hasLength(2));

      // Now confirm.
      await tester.tap(clearBtn);
      await tester.pumpAndSettle();
      // The destructive button reuses "Clear All Known Hosts" as its
      // label. Match via `is AppButton` + label field because the
      // concrete widget is _DestructiveAction (private subclass) and
      // byType wouldn't match it.
      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is AppButton && w.label == 'Clear All Known Hosts',
        ),
      );
      await tester.runAsync(() => Future<void>.value());
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));

      expect(manager.entries, isEmpty);
    });

    testWidgets(
      'copy-fingerprint button writes the fingerprint to the clipboard',
      (tester) async {
        String? clipboardText;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, (call) async {
              if (call.method == 'Clipboard.setData') {
                final args = call.arguments as Map<Object?, Object?>?;
                clipboardText = args?['text'] as String?;
              }
              return null;
            });
        addTearDown(() {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(SystemChannels.platform, null);
        });

        await populate(tester, manager);
        await tester.pumpWidget(buildApp(manager));
        await openDialogAfterPopulate(tester);

        final copyBtns = find.byWidgetPredicate(
          (w) =>
              w is IconButton &&
              w.icon is Icon &&
              (w.icon as Icon).icon == Icons.content_copy,
        );
        await tester.tap(copyBtns.first);
        // runAsync so Clipboard.setData's platform-channel future actually
        // resolves (it's in the real zone, not FakeAsync's), then pump past
        // the 3s Toast timer so the tree tears down without a pending Timer.
        await tester.runAsync(() => Future<void>.value());
        await tester.pump();
        await tester.pump(const Duration(seconds: 4));

        // Fingerprint is the SHA256 of the decoded key bytes. Rather than
        // re-derive it here (which would duplicate the code under test),
        // assert that *something* was written and that it matches the
        // fingerprint the first row displays in its subtitle.
        expect(clipboardText, isNotNull);
        final expected = KnownHostsManager.fingerprint(
          base64Decode(validKeyB64),
        );
        expect(clipboardText, expected);
      },
    );
  });
}
