import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/tags/tag.dart';
import 'package:letsflutssh/providers/tag_provider.dart';
import 'package:letsflutssh/widgets/tag_dots.dart';

Widget _scope({required Widget child, required List<dynamic> overrides}) {
  return ProviderScope(
    overrides: overrides.cast(),
    child: MaterialApp(
      home: Scaffold(body: Center(child: child)),
    ),
  );
}

void main() {
  Tag tag(String name, {String? color}) => Tag(name: name, color: color);

  group('SessionTagDots', () {
    testWidgets('renders one dot per tag, capped at maxDots', (tester) async {
      final tags = [
        tag('prod', color: '#FF0000'),
        tag('eu', color: '#00FF00'),
        tag('secure', color: '#0000FF'),
        tag('legacy', color: '#FFFF00'),
      ];
      await tester.pumpWidget(
        _scope(
          child: const SessionTagDots(sessionId: 's1', maxDots: 3),
          overrides: [
            sessionTagsProvider('s1').overrideWith((_) async => tags),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Only dots for the first 3 tags are built — the 4th is dropped.
      final dots = find.byWidgetPredicate(
        (w) => w is Container && w.decoration is BoxDecoration,
      );
      expect(dots, findsNWidgets(3));
    });

    testWidgets('renders nothing when the session has no tags', (tester) async {
      await tester.pumpWidget(
        _scope(
          child: const SessionTagDots(sessionId: 'empty'),
          overrides: [
            sessionTagsProvider('empty').overrideWith((_) async => const []),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // No dots at all — empty state must collapse to a zero-size box so
      // it does not push siblings around in a tree row.
      expect(
        find.byWidgetPredicate(
          (w) => w is Container && w.decoration is BoxDecoration,
        ),
        findsNothing,
      );
    });

    testWidgets(
      'loading state renders zero-size box (does not flash placeholder)',
      (tester) async {
        // Provide a future that never resolves during the test so the
        // widget stays in its loading branch. The contract is: no
        // visible placeholder, no layout impact — the session tree must
        // look identical until tags actually arrive.
        await tester.pumpWidget(
          _scope(
            child: const SessionTagDots(sessionId: 'pending'),
            overrides: [
              sessionTagsProvider(
                'pending',
              ).overrideWith((_) => Completer<List<Tag>>().future),
            ],
          ),
        );
        await tester.pump();

        expect(
          find.byWidgetPredicate(
            (w) => w is Container && w.decoration is BoxDecoration,
          ),
          findsNothing,
        );
      },
    );

    testWidgets(
      'error state renders zero-size box (silent failure — tag fetch is cosmetic)',
      (tester) async {
        await tester.pumpWidget(
          _scope(
            child: const SessionTagDots(sessionId: 'broken'),
            overrides: [
              sessionTagsProvider(
                'broken',
              ).overrideWith((_) async => throw StateError('db offline')),
            ],
          ),
        );
        await tester.pumpAndSettle();

        // A tag fetch failure must not surface an error widget into the
        // session tree — tag dots are decoration, not a feature users
        // can act on. Contract: degrade to invisible.
        expect(
          find.byWidgetPredicate(
            (w) => w is Container && w.decoration is BoxDecoration,
          ),
          findsNothing,
        );
      },
    );

    testWidgets('dot colours come from each tag (not a single theme colour)', (
      tester,
    ) async {
      final tags = [tag('a', color: '#FF0000'), tag('b', color: '#00FF00')];
      await tester.pumpWidget(
        _scope(
          child: const SessionTagDots(sessionId: 's'),
          overrides: [sessionTagsProvider('s').overrideWith((_) async => tags)],
        ),
      );
      await tester.pumpAndSettle();

      final containers = tester
          .widgetList<Container>(
            find.byWidgetPredicate(
              (w) => w is Container && w.decoration is BoxDecoration,
            ),
          )
          .toList();
      final colours = containers
          .map((c) => (c.decoration as BoxDecoration).color)
          .toList();

      expect(
        colours.toSet().length,
        2,
        reason:
            'each tag drives its own dot colour — the row must not '
            'flatten into a single colour',
      );
    });
  });

  group('FolderTagDots', () {
    testWidgets('mirrors SessionTagDots contract via folderTagsProvider', (
      tester,
    ) async {
      await tester.pumpWidget(
        _scope(
          child: const FolderTagDots(folderId: 'f1'),
          overrides: [
            folderTagsProvider(
              'f1',
            ).overrideWith((_) async => [tag('x', color: '#FF00FF')]),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Single tag → single dot.
      expect(
        find.byWidgetPredicate(
          (w) => w is Container && w.decoration is BoxDecoration,
        ),
        findsOneWidget,
      );
    });
  });
}
