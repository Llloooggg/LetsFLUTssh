import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/snippets/snippet.dart';
import 'package:letsflutssh/features/snippets/snippet_picker.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/providers/snippet_provider.dart';
import 'package:letsflutssh/theme/app_theme.dart';
import 'package:letsflutssh/widgets/core/app_icon_button.dart';
import 'package:letsflutssh/widgets/core/toast.dart';

import '../../helpers/frb_bootstrap.dart';

/// In-memory fake for [SnippetsNotifier] — no database. Owns the
/// session→snippet links so the picker's `sessionSnippetsProvider`
/// override can resolve against the same state.
class FakeSnippetsNotifier extends SnippetsNotifier {
  FakeSnippetsNotifier([List<Snippet>? initial])
    : _snippets = {for (final s in initial ?? <Snippet>[]) s.id: s},
      _sessionLinks = {};

  final Map<String, Snippet> _snippets;
  final Map<String, Set<String>> _sessionLinks;

  bool _attached = false;

  @override
  Future<List<Snippet>> build() async {
    _attached = true;
    return _sorted();
  }

  @override
  Future<List<Snippet>> loadAll() async => _sorted();

  @override
  Future<void> add(Snippet snippet) async {
    _snippets[snippet.id] = snippet;
    ref.invalidateSelf();
  }

  @override
  Future<void> save(Snippet snippet) async {
    _snippets[snippet.id] = snippet;
    ref.invalidateSelf();
  }

  @override
  Future<void> delete(String id) async {
    _snippets.remove(id);
    ref.invalidateSelf();
  }

  @override
  Future<void> linkToSession(String snippetId, String sessionId) async {
    _sessionLinks.putIfAbsent(sessionId, () => {}).add(snippetId);
    // `ref` is unsafe to access before the notifier is attached to a
    // ProviderContainer (tests that pre-seed link state happen before
    // `pumpWidget`). Skip the family-provider invalidation in that
    // case — the dialog's first read picks up the current state
    // anyway.
    if (_attached) ref.invalidate(sessionSnippetsProvider(sessionId));
  }

  @override
  Future<void> unlinkFromSession(String snippetId, String sessionId) async {
    _sessionLinks[sessionId]?.remove(snippetId);
    if (_attached) ref.invalidate(sessionSnippetsProvider(sessionId));
  }

  @override
  Future<Set<String>> linkedSnippetIds(String sessionId) async {
    return Set.of(_sessionLinks[sessionId] ?? {});
  }

  /// Snapshot view consumed by the test-side `sessionSnippetsProvider`
  /// override.
  List<Snippet> snippetsForSession(String sessionId) {
    final ids = _sessionLinks[sessionId] ?? {};
    return _snippets.values.where((s) => ids.contains(s.id)).toList()
      ..sort((a, b) => a.title.compareTo(b.title));
  }

  List<Snippet> _sorted() =>
      _snippets.values.toList()..sort((a, b) => a.title.compareTo(b.title));
}

void main() {
  // SnippetPicker calls `renderSnippet`, which routes through
  // `lfs_core::snippet_template::render` — bootstrap FRB so the
  // widget can render snippets without throwing.
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(requireFrbLoaded);

  late FakeSnippetsNotifier fakeStore;

  final snippet1 = Snippet(id: 's1', title: 'List files', command: 'ls -la');

  final snippet2 = Snippet(id: 's2', title: 'Disk usage', command: 'df -h');

  Widget buildApp({String? sessionId}) {
    return ProviderScope(
      overrides: [
        snippetsProvider.overrideWith(() => fakeStore),
        sessionSnippetsProvider.overrideWith(
          (ref, id) async => fakeStore.snippetsForSession(id),
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: S.localizationsDelegates,
        supportedLocales: S.supportedLocales,
        theme: AppTheme.dark(),
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () =>
                  SnippetPicker.show(context, sessionId: sessionId),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> openDialog(WidgetTester tester, {String? sessionId}) async {
    await tester.pumpWidget(buildApp(sessionId: sessionId));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  tearDown(() => Toast.clearAllForTest());

  group('SnippetPicker', () {
    testWidgets('shows "Snippets" title', (tester) async {
      fakeStore = FakeSnippetsNotifier();
      await openDialog(tester);

      expect(find.text('Snippets'), findsOneWidget);
    });

    testWidgets('shows empty state when no snippets', (tester) async {
      fakeStore = FakeSnippetsNotifier();
      await openDialog(tester);

      expect(find.text('No snippets yet'), findsOneWidget);
    });

    testWidgets('shows snippet tiles with title and command', (tester) async {
      fakeStore = FakeSnippetsNotifier([snippet1, snippet2]);
      await openDialog(tester);

      expect(find.text('List files'), findsOneWidget);
      expect(find.text('ls -la'), findsOneWidget);
      expect(find.text('Disk usage'), findsOneWidget);
      expect(find.text('df -h'), findsOneWidget);
    });

    testWidgets('tapping a snippet returns the command', (tester) async {
      fakeStore = FakeSnippetsNotifier([snippet1]);
      String? result;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            snippetsProvider.overrideWith(() => fakeStore),
            sessionSnippetsProvider.overrideWith(
              (ref, id) async => fakeStore.snippetsForSession(id),
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () async {
                    result = await SnippetPicker.show(context);
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('List files'));
      await tester.pumpAndSettle();

      expect(result, 'ls -la');
      // Dialog should be closed.
      expect(find.text('Snippets'), findsNothing);
    });

    testWidgets('cancel button closes dialog with null', (tester) async {
      fakeStore = FakeSnippetsNotifier([snippet1]);
      String? result = 'sentinel';
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            snippetsProvider.overrideWith(() => fakeStore),
            sessionSnippetsProvider.overrideWith(
              (ref, id) async => fakeStore.snippetsForSession(id),
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () async {
                    result = await SnippetPicker.show(context);
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(result, isNull);
      expect(find.text('Snippets'), findsNothing);
    });

    testWidgets('with sessionId: shows pinned snippets section header', (
      tester,
    ) async {
      fakeStore = FakeSnippetsNotifier([snippet1, snippet2]);
      await fakeStore.linkToSession('s1', 'session-1');
      await openDialog(tester, sessionId: 'session-1');

      expect(find.text('PINNED'), findsOneWidget);
      expect(find.text('ALL'), findsOneWidget);
    });

    testWidgets('with sessionId: pin button pins a snippet', (tester) async {
      fakeStore = FakeSnippetsNotifier([snippet1]);
      await openDialog(tester, sessionId: 'session-1');

      // No pinned section initially.
      expect(find.text('PINNED'), findsNothing);

      // Tap the pin button (push_pin_outlined for unpinned).
      await tester.tap(find.byIcon(Icons.push_pin_outlined));
      await tester.pumpAndSettle();

      // After pinning, the pinned section should appear.
      expect(find.text('PINNED'), findsOneWidget);
      final linked = await fakeStore.linkedSnippetIds('session-1');
      expect(linked, contains('s1'));
    });

    testWidgets('with sessionId: unpin button unpins a snippet', (
      tester,
    ) async {
      fakeStore = FakeSnippetsNotifier([snippet1]);
      await fakeStore.linkToSession('s1', 'session-1');
      await openDialog(tester, sessionId: 'session-1');

      // Pinned section is visible.
      expect(find.text('PINNED'), findsOneWidget);

      // Tap the filled push_pin icon (trailing `AppIconButton`) to
      // unpin. There are two push_pin icons per pinned snippet (list
      // icon + button), so scope the tap to the AppIconButton wrapper
      // to avoid hitting the leading list marker.
      await tester.tap(
        find.widgetWithIcon(AppIconButton, Icons.push_pin).first,
      );
      await tester.pumpAndSettle();

      // After unpinning, the pinned section should be gone.
      expect(find.text('PINNED'), findsNothing);
      final linked = await fakeStore.linkedSnippetIds('session-1');
      expect(linked, isEmpty);
    });

    testWidgets('copy button shows "Command copied" toast', (tester) async {
      fakeStore = FakeSnippetsNotifier([snippet1]);
      await openDialog(tester);

      await tester.tap(find.byIcon(Icons.content_copy));
      await tester.pumpAndSettle();

      expect(find.text('Command copied to clipboard'), findsOneWidget);

      Toast.clearAllForTest();
      await tester.pump();
    });

    testWidgets('without sessionId: no pin buttons shown', (tester) async {
      fakeStore = FakeSnippetsNotifier([snippet1]);
      await openDialog(tester);

      // No pin/unpin icons should appear.
      expect(find.byIcon(Icons.push_pin_outlined), findsNothing);
      // The code icon is used for unpinned snippets without sessionId.
      expect(find.byIcon(Icons.code), findsOneWidget);
      // Copy button should still be present.
      expect(find.byIcon(Icons.content_copy), findsOneWidget);
    });

    testWidgets('search filter hides non-matching snippets and shows '
        'noResults when nothing matches', (tester) async {
      // Spec: typing in the search bar narrows the visible list to
      // snippets whose title / command / description contains the
      // needle (`filterSnippets` contract); when neither pinned nor
      // unpinned filtered lists have anything, the empty-results
      // state replaces the list.
      fakeStore = FakeSnippetsNotifier([snippet1, snippet2]);
      await openDialog(tester);

      // Baseline: both snippets visible.
      expect(find.text('List files'), findsOneWidget);
      expect(find.text('Disk usage'), findsOneWidget);

      // Narrow to a token only one snippet's command carries.
      await tester.enterText(find.byType(TextField), 'df');
      await tester.pumpAndSettle();
      expect(find.text('List files'), findsNothing);
      expect(find.text('Disk usage'), findsOneWidget);

      // Narrow further to a token no snippet matches: the empty-
      // results message replaces the list (distinct from the
      // "no snippets at all" empty-state).
      await tester.enterText(find.byType(TextField), 'zzz-no-match');
      await tester.pumpAndSettle();
      expect(find.text('No results'), findsOneWidget);
      expect(find.text('No snippets yet'), findsNothing);
    });

    testWidgets(
      'templateContext resolves built-in {{host}} token without prompting',
      (tester) async {
        // Spec: when every `{{token}}` resolves against the supplied
        // context, the picker pops with the substituted command
        // immediately — the fill dialog never opens.
        final hostSnippet = Snippet(
          id: 's-host',
          title: 'Ping host',
          command: 'ping {{host}}',
        );
        fakeStore = FakeSnippetsNotifier([hostSnippet]);
        String? result;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              snippetsProvider.overrideWith(() => fakeStore),
              sessionSnippetsProvider.overrideWith(
                (ref, id) async => fakeStore.snippetsForSession(id),
              ),
            ],
            child: MaterialApp(
              localizationsDelegates: S.localizationsDelegates,
              supportedLocales: S.supportedLocales,
              theme: AppTheme.dark(),
              home: Scaffold(
                body: Builder(
                  builder: (context) => ElevatedButton(
                    onPressed: () async {
                      result = await SnippetPicker.show(
                        context,
                        templateContext: const {'host': '10.0.0.1'},
                      );
                    },
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Ping host'));
        await tester.pumpAndSettle();

        expect(result, 'ping 10.0.0.1');
        // Fill dialog never opened — its title would surface otherwise.
        expect(find.text('Fill in snippet parameters'), findsNothing);
      },
    );

    // Deferred — unresolved-token fill dialog (Run + Cancel arms): the
    // `fillSnippetUnresolved` dialog disposes mid-pump and trips an
    // ancestor-lookup-after-dispose check in the test harness. The
    // `_promptForTokens` code path is covered by the token-context
    // tests above and exercised end-to-end in the snippet integration
    // suite.

    // Deferred — copy button clipboard payload: `pumpAndSettle` after
    // the copy tap never settles in this harness shape (Toast's
    // microtask pump tick survives indefinitely). The clipboard
    // round-trip is exercised end-to-end in `terminal_clipboard_test`.

    testWidgets('pinned snippets render before unpinned ones in the list '
        '(PINNED section above ALL section)', (tester) async {
      // Spec: `_buildBody` writes the pinned section first, then the
      // ALL section header, then the filtered unpinned entries. The
      // visual y-coordinate of the PINNED header must therefore be
      // less than the ALL header's — pins always sit on top.
      fakeStore = FakeSnippetsNotifier([snippet1, snippet2]);
      await fakeStore.linkToSession('s2', 'session-1');
      await openDialog(tester, sessionId: 'session-1');

      final pinnedY = tester.getTopLeft(find.text('PINNED')).dy;
      final allY = tester.getTopLeft(find.text('ALL')).dy;
      expect(pinnedY, lessThan(allY));

      // The pinned snippet (snippet2 — `df -h`) renders before the
      // unpinned one (snippet1 — `ls -la`) in vertical order.
      final pinnedSnippetY = tester.getTopLeft(find.text('Disk usage')).dy;
      final unpinnedSnippetY = tester.getTopLeft(find.text('List files')).dy;
      expect(pinnedSnippetY, lessThan(unpinnedSnippetY));
    });

    testWidgets('after `_load` resolves the spinner is gone — the load gate '
        'flips even when no snippets exist', (tester) async {
      // Spec: `_load` calls `loadAll()` AND (when sessionId is set)
      // `sessionSnippetsProvider.future`, then unconditionally flips
      // `_loading` to false. Pins the gate's release on the
      // sessionId-set branch with an empty store — the empty-state
      // surfaces because the loading gate exited, not because the
      // gate never blocked the build.
      fakeStore = FakeSnippetsNotifier();
      await openDialog(tester, sessionId: 'session-1');

      expect(find.byType(CircularProgressIndicator), findsNothing);
      // Empty store + sessionId set → the noSnippets empty-state
      // takes over (rather than the noResults filter-empty state).
      expect(find.text('No snippets yet'), findsOneWidget);
    });

    testWidgets('toggling pin without a sessionId is impossible — the trailing '
        'pin button is omitted entirely', (tester) async {
      // Spec: `_snippetTile` gates the leading pin AppIconButton on
      // `widget.sessionId != null`. Without a session id, the
      // trailing slot only contains the copy button, not the pin
      // toggle. Even forcing a tap on the leading list icon does
      // nothing — there is no pin handler wired.
      fakeStore = FakeSnippetsNotifier([snippet1]);
      await openDialog(tester);

      // Only the copy button — no `AppIconButton` with a push_pin icon.
      expect(find.widgetWithIcon(AppIconButton, Icons.push_pin), findsNothing);
      expect(
        find.widgetWithIcon(AppIconButton, Icons.push_pin_outlined),
        findsNothing,
      );
      // The leading row icon is `Icons.code` (no sessionId → never pinned).
      expect(find.byIcon(Icons.code), findsOneWidget);
    });

    testWidgets('with sessionId: filter narrows both PINNED and ALL sections '
        'independently', (tester) async {
      // Spec: `_buildBody` filters the pinned and unpinned lists
      // through the same `_matches` predicate. A needle that hits only
      // an unpinned snippet hides the pinned section header entirely.
      fakeStore = FakeSnippetsNotifier([snippet1, snippet2]);
      await fakeStore.linkToSession('s1', 'session-1');
      await openDialog(tester, sessionId: 'session-1');

      // Baseline: pinned snippet1 + unpinned snippet2, both headers.
      expect(find.text('PINNED'), findsOneWidget);
      expect(find.text('ALL'), findsOneWidget);

      // Filter to a token only the unpinned snippet's command holds.
      await tester.enterText(find.byType(TextField).first, 'df');
      await tester.pumpAndSettle();

      // Pinned section drops out (snippet1 doesn't match); ALL header
      // is also gone because section headers only render when there
      // is at least one pinned hit.
      expect(find.text('PINNED'), findsNothing);
      expect(find.text('ALL'), findsNothing);
      // The unpinned filtered snippet is still rendered (sectionless).
      expect(find.text('Disk usage'), findsOneWidget);
    });
  });
}
