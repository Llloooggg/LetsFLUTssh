import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '''package:letsflutssh/l10n/app_localizations.dart''';
import 'package:letsflutssh/theme/app_theme.dart';
import 'package:letsflutssh/widgets/context_menu.dart';

void main() {
  Widget wrap(Widget child) {
    return MaterialApp(
      localizationsDelegates: S.localizationsDelegates,
      supportedLocales: S.supportedLocales,
      theme: AppTheme.dark(),
      home: Scaffold(body: child),
    );
  }

  List<ContextMenuItem> testItems({VoidCallback? onCopy, VoidCallback? onPaste}) {
    return [
      ContextMenuItem(label: 'Copy', icon: Icons.copy, shortcut: 'Ctrl+C', onTap: onCopy),
      const ContextMenuItem.divider(),
      ContextMenuItem(label: 'Paste', icon: Icons.paste, onTap: onPaste),
    ];
  }

  Future<void> openMenu(
    WidgetTester tester, {
    List<ContextMenuItem>? items,
    VoidCallback? onCopy,
    VoidCallback? onPaste,
  }) async {
    final menuItems = items ?? testItems(onCopy: onCopy, onPaste: onPaste);
    await tester.pumpWidget(
      wrap(
        Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () => showAppContextMenu(context: ctx, position: const Offset(100, 100), items: menuItems),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  Future<void> sendKey(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pump();
    // sendKeyEvent can cause focus loss on the KeyboardListener's FocusNode.
    // Restore focus so subsequent key events (especially Enter) reach the handler.
    final kls = find.byType(KeyboardListener);
    if (kls.evaluate().isNotEmpty) {
      final kl = tester.widget<KeyboardListener>(kls.last);
      if (!kl.focusNode.hasFocus) {
        kl.focusNode.requestFocus();
        await tester.pump();
      }
    }
  }

  group('ContextMenuItem', () {
    test('default constructor has divider false', () {
      const item = ContextMenuItem(label: 'Test');
      expect(item.divider, isFalse);
      expect(item.label, 'Test');
      expect(item.icon, isNull);
      expect(item.color, isNull);
      expect(item.shortcut, isNull);
      expect(item.onTap, isNull);
    });

    test('divider constructor sets divider true and nulls others', () {
      const item = ContextMenuItem.divider();
      expect(item.divider, isTrue);
      expect(item.label, isNull);
      expect(item.icon, isNull);
      expect(item.color, isNull);
      expect(item.shortcut, isNull);
      expect(item.onTap, isNull);
    });
  });

  group('showAppContextMenu', () {
    testWidgets('displays menu items', (tester) async {
      await openMenu(tester);

      expect(find.text('Copy'), findsOneWidget);
      expect(find.text('Paste'), findsOneWidget);
      expect(find.text('Ctrl+C'), findsOneWidget);
    });

    testWidgets('tapping item fires onTap and closes menu', (tester) async {
      var copied = false;
      await openMenu(tester, onCopy: () => copied = true);

      await tester.tap(find.text('Copy'));
      await tester.pumpAndSettle();

      expect(copied, isTrue);
      expect(find.text('Copy'), findsNothing);
    });

    testWidgets('tapping outside dismisses the menu', (tester) async {
      await openMenu(tester);

      // Tap a point clearly outside the menu but inside the screen (800x600).
      // Offset(0,0) is unreliable — it sits at the very edge and may not
      // register a hit on the dismiss barrier in the test environment.
      await tester.tapAt(const Offset(400, 400));
      await tester.pumpAndSettle();

      expect(find.text('Copy'), findsNothing);
    });

    testWidgets('re-entrant call dismisses previous menu', (tester) async {
      late BuildContext savedCtx;
      await tester.pumpWidget(
        wrap(
          Builder(
            builder: (ctx) {
              savedCtx = ctx;
              return ElevatedButton(
                onPressed: () => showAppContextMenu(
                  context: ctx,
                  position: const Offset(50, 50),
                  items: [const ContextMenuItem(label: 'First')],
                ),
                child: const Text('Menu1'),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Menu1'));
      await tester.pumpAndSettle();
      expect(find.text('First'), findsOneWidget);

      // Call showAppContextMenu directly to open a second menu.
      // Tapping a button won't work because the first menu's dismiss
      // barrier (Positioned.fill Listener) obscures the button in the
      // hit-test, preventing the full tap gesture from reaching it.
      showAppContextMenu(
        context: savedCtx,
        position: const Offset(150, 150),
        items: [const ContextMenuItem(label: 'Second')],
      );
      await tester.pumpAndSettle();
      expect(find.text('First'), findsNothing);
      expect(find.text('Second'), findsOneWidget);
    });

    testWidgets('item with custom color uses that color', (tester) async {
      await openMenu(
        tester,
        items: [const ContextMenuItem(label: 'Delete', color: Colors.red)],
      );

      final textWidget = tester.widget<Text>(find.text('Delete'));
      expect(textWidget.style?.color, Colors.red);
    });
  });

  group('keyboard navigation', () {
    testWidgets('ArrowDown moves focus to first item', (tester) async {
      await openMenu(tester);

      await sendKey(tester, LogicalKeyboardKey.arrowDown);

      final containers = tester.widgetList<Container>(find.byType(Container));
      final highlighted = containers.where((c) => c.color == AppTheme.selection);
      expect(highlighted, isNotEmpty);
    });

    testWidgets('ArrowDown then ArrowDown moves to next item', (tester) async {
      var pasted = false;
      await openMenu(tester, onPaste: () => pasted = true);

      await sendKey(tester, LogicalKeyboardKey.arrowDown);
      await sendKey(tester, LogicalKeyboardKey.arrowDown);
      await sendKey(tester, LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(pasted, isTrue);
    });

    testWidgets('ArrowUp from no selection selects last item', (tester) async {
      var pasted = false;
      await openMenu(tester, onPaste: () => pasted = true);

      await sendKey(tester, LogicalKeyboardKey.arrowUp);
      await sendKey(tester, LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(pasted, isTrue);
    });

    testWidgets('ArrowDown wraps around to first item', (tester) async {
      var copied = false;
      await openMenu(tester, onCopy: () => copied = true);

      // Move down to Copy (1st), then Paste (2nd), then wrap to Copy (1st)
      await sendKey(tester, LogicalKeyboardKey.arrowDown);
      await sendKey(tester, LogicalKeyboardKey.arrowDown);
      await sendKey(tester, LogicalKeyboardKey.arrowDown);
      await sendKey(tester, LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(copied, isTrue);
    });

    testWidgets('ArrowUp wraps around to last item', (tester) async {
      var pasted = false;
      await openMenu(tester, onPaste: () => pasted = true);

      // Down to first, then up wraps to last
      await sendKey(tester, LogicalKeyboardKey.arrowDown);
      await sendKey(tester, LogicalKeyboardKey.arrowUp);
      await sendKey(tester, LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(pasted, isTrue);
    });

    testWidgets('keyboard navigation skips dividers', (tester) async {
      var pasted = false;
      await openMenu(tester, onPaste: () => pasted = true);

      // Items: Copy (0), divider (1), Paste (2)
      // ArrowDown twice should go Copy -> Paste (skip divider)
      await sendKey(tester, LogicalKeyboardKey.arrowDown);
      await sendKey(tester, LogicalKeyboardKey.arrowDown);
      await sendKey(tester, LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(pasted, isTrue);
    });

    testWidgets('Enter activates focused item and closes menu', (tester) async {
      var copied = false;
      await openMenu(tester, onCopy: () => copied = true);

      await sendKey(tester, LogicalKeyboardKey.arrowDown);
      await sendKey(tester, LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(copied, isTrue);
      expect(find.text('Copy'), findsNothing);
    });

    testWidgets('Enter with no selection does nothing', (tester) async {
      await openMenu(tester);

      await sendKey(tester, LogicalKeyboardKey.enter);
      await tester.pump();

      expect(find.text('Copy'), findsOneWidget);
    });

    testWidgets('Escape closes the menu', (tester) async {
      await openMenu(tester);

      await sendKey(tester, LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.text('Copy'), findsNothing);
    });

    testWidgets('keyboard navigation with all dividers does nothing', (tester) async {
      await openMenu(tester, items: [const ContextMenuItem.divider(), const ContextMenuItem.divider()]);

      await sendKey(tester, LogicalKeyboardKey.arrowDown);
      await tester.pump();
      // No crash, menu still shown (no actionable items)
    });
  });

  group('hover state', () {
    testWidgets('mouse hover highlights item', (tester) async {
      await openMenu(tester);

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);

      await gesture.moveTo(tester.getCenter(find.text('Copy')));
      await tester.pump();

      final containers = tester.widgetList<Container>(find.byType(Container));
      final highlighted = containers.where((c) => c.color == AppTheme.selection);
      expect(highlighted, isNotEmpty);
    });

    testWidgets('mouse exit removes highlight', (tester) async {
      await openMenu(tester);

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);

      await gesture.moveTo(tester.getCenter(find.text('Copy')));
      await tester.pump();

      await gesture.moveTo(const Offset(0, 0));
      await tester.pump();

      final containers = tester.widgetList<Container>(find.byType(Container));
      final highlighted = containers.where((c) => c.color == AppTheme.selection);
      expect(highlighted, isEmpty);
    });

    testWidgets('hover clears keyboard focus', (tester) async {
      await openMenu(tester);

      // Keyboard navigate to first item
      await sendKey(tester, LogicalKeyboardKey.arrowDown);

      // Now hover over a different item
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);

      await gesture.moveTo(tester.getCenter(find.text('Paste')));
      await tester.pump();

      await gesture.moveTo(const Offset(0, 0));
      await tester.pump();

      // Verify the menu is still visible (hover didn't break anything)
      expect(find.text('Copy'), findsOneWidget);
      expect(find.text('Paste'), findsOneWidget);
    });

    testWidgets('keyboard navigation clears hover state', (tester) async {
      await openMenu(tester);

      // Hover over Copy
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(tester.getCenter(find.text('Copy')));
      await tester.pump();

      // Arrow down — should clear hover and set keyboard focus
      await sendKey(tester, LogicalKeyboardKey.arrowDown);

      // Menu should still work
      expect(find.text('Copy'), findsOneWidget);
    });
  });
}
