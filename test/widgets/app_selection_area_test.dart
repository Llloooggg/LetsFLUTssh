import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/widgets/app_selection_area.dart';

void main() {
  group('AppSelectionArea', () {
    testWidgets('wraps its child under a SelectionArea', (tester) async {
      // The widget is a drop-in for SelectionArea — the contract the
      // callers rely on is that everything inside still participates in
      // the platform selection mechanism. Without this gate a future
      // refactor that accidentally stripped the wrapper would silently
      // make the whole screen unselectable.
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: AppSelectionArea(child: Text('selectable'))),
        ),
      );
      expect(find.byType(SelectionArea), findsOneWidget);
      expect(find.text('selectable'), findsOneWidget);
    });

    testWidgets('exposes the provided child via the widget tree', (
      tester,
    ) async {
      const key = Key('inner');
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppSelectionArea(
              child: Padding(
                key: key,
                padding: EdgeInsets.all(8),
                child: Text('content'),
              ),
            ),
          ),
        ),
      );
      expect(find.byKey(key), findsOneWidget);
    });

    testWidgets(
      'contextMenuBuilder drops the Select All entry and keeps the rest',
      (tester) async {
        // Reach into the SelectionArea the widget built and invoke its
        // contextMenuBuilder ourselves with a synthetic state. That is
        // the behavioural contract of AppSelectionArea — the whole
        // reason the wrapper exists — so we pin it directly instead of
        // depending on platform long-press gesture machinery.
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(body: AppSelectionArea(child: Text('content'))),
          ),
        );
        final area = tester.widget<SelectionArea>(find.byType(SelectionArea));
        final builder = area.contextMenuBuilder!;
        final state = _FakeSelectableRegionState(
          buttonItems: <ContextMenuButtonItem>[
            ContextMenuButtonItem(
              type: ContextMenuButtonType.copy,
              onPressed: () {},
            ),
            ContextMenuButtonItem(
              type: ContextMenuButtonType.selectAll,
              onPressed: () {},
            ),
          ],
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(builder: (ctx) => builder(ctx, state)),
            ),
          ),
        );
        final toolbar = tester.widget<AdaptiveTextSelectionToolbar>(
          find.byType(AdaptiveTextSelectionToolbar),
        );
        expect(toolbar.buttonItems, hasLength(1));
        expect(toolbar.buttonItems!.first.type, ContextMenuButtonType.copy);
      },
    );

    testWidgets(
      'contextMenuBuilder returns SizedBox.shrink when only Select All was present',
      (tester) async {
        // If the platform left Select All as the only entry (e.g. an
        // empty SelectionArea on Android that had not collected any
        // other actions), filtering it out must not leave a zero-item
        // AdaptiveTextSelectionToolbar on screen — that would render
        // an empty floating bar. A SizedBox.shrink is the explicit "no
        // menu" signal.
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(body: AppSelectionArea(child: Text('x'))),
          ),
        );
        final area = tester.widget<SelectionArea>(find.byType(SelectionArea));
        final builder = area.contextMenuBuilder!;
        final state = _FakeSelectableRegionState(
          buttonItems: <ContextMenuButtonItem>[
            ContextMenuButtonItem(
              type: ContextMenuButtonType.selectAll,
              onPressed: () {},
            ),
          ],
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(builder: (ctx) => builder(ctx, state)),
            ),
          ),
        );
        expect(find.byType(AdaptiveTextSelectionToolbar), findsNothing);
      },
    );
  });
}

class _FakeSelectableRegionState implements SelectableRegionState {
  _FakeSelectableRegionState({required this.buttonItems});

  final List<ContextMenuButtonItem> buttonItems;

  @override
  TextSelectionToolbarAnchors get contextMenuAnchors =>
      const TextSelectionToolbarAnchors(primaryAnchor: Offset.zero);

  @override
  List<ContextMenuButtonItem> get contextMenuButtonItems => buttonItems;

  @override
  String toString({DiagnosticLevel minLevel = DiagnosticLevel.info}) =>
      '_FakeSelectableRegionState';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
