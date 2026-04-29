import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/snippets/snippet.dart';
import 'package:letsflutssh/features/snippets/snippet_picker.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/providers/snippet_provider.dart';
import 'package:letsflutssh/theme/app_theme.dart';
import 'package:letsflutssh/widgets/app_icon_button.dart';
import 'package:letsflutssh/widgets/toast.dart';

/// In-memory fake for [SnippetsNotifier] — no database. Owns the
/// session→snippet links so the picker's `sessionSnippetsProvider`
/// override can resolve against the same state.
class FakeSnippetsNotifier extends SnippetsNotifier {
  FakeSnippetsNotifier([List<Snippet>? initial])
    : _snippets = {for (final s in initial ?? []) s.id: s},
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
  });
}
