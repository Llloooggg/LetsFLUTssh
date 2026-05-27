/// Widget tests for [TerminalSearchBar] — the in-terminal find input.
/// Covers the debounced query callback, Enter → next, the match-gated
/// prev/next buttons, the close button, and the host-supplied match
/// label.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/widgets/core/app_icon_button.dart';
import 'package:letsflutssh/widgets/terminal/terminal_search_bar.dart';

void main() {
  Future<void> pump(
    WidgetTester tester, {
    void Function(String)? onQueryChanged,
    VoidCallback? onNext,
    VoidCallback? onPrevious,
    VoidCallback? onClose,
    String? matchLabel,
    bool hasMatches = false,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: S.localizationsDelegates,
        supportedLocales: S.supportedLocales,
        home: Scaffold(
          body: TerminalSearchBar(
            onQueryChanged: onQueryChanged ?? (_) {},
            onNext: onNext ?? () {},
            onPrevious: onPrevious ?? () {},
            onClose: onClose ?? () {},
            matchLabel: matchLabel,
            hasMatches: hasMatches,
          ),
        ),
      ),
    );
  }

  AppIconButton iconButton(WidgetTester tester, IconData icon) {
    return tester.widget<AppIconButton>(
      find.byWidgetPredicate((w) => w is AppIconButton && w.icon == icon),
    );
  }

  testWidgets('query change is debounced then forwarded', (tester) async {
    String? query;
    await pump(tester, onQueryChanged: (q) => query = q);
    await tester.enterText(find.byType(TextField), 'needle');
    // Debounce not yet elapsed.
    await tester.pump(const Duration(milliseconds: 100));
    expect(query, isNull);
    // After the 200ms debounce window the host is notified once.
    await tester.pump(const Duration(milliseconds: 150));
    expect(query, 'needle');
  });

  testWidgets('submitting the field jumps to the next match', (tester) async {
    var nextCalls = 0;
    await pump(tester, onNext: () => nextCalls++);
    await tester.enterText(find.byType(TextField), 'x');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(nextCalls, 1);
  });

  testWidgets('prev/next are disabled until there are matches', (tester) async {
    await pump(tester, hasMatches: false);
    expect(iconButton(tester, Icons.keyboard_arrow_up).onTap, isNull);
    expect(iconButton(tester, Icons.keyboard_arrow_down).onTap, isNull);
  });

  testWidgets('prev/next fire their callbacks when matches exist', (
    tester,
  ) async {
    var prev = 0;
    var next = 0;
    await pump(
      tester,
      hasMatches: true,
      onPrevious: () => prev++,
      onNext: () => next++,
    );
    await tester.tap(find.byIcon(Icons.keyboard_arrow_up));
    await tester.tap(find.byIcon(Icons.keyboard_arrow_down));
    await tester.pump();
    expect(prev, 1);
    expect(next, 1);
  });

  testWidgets('the close button fires onClose', (tester) async {
    var closed = 0;
    await pump(tester, onClose: () => closed++);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(closed, 1);
  });

  testWidgets('the host match label is surfaced as the field suffix', (
    tester,
  ) async {
    await pump(tester, matchLabel: '2/7', hasMatches: true);
    expect(find.text('2/7'), findsOneWidget);
  });
}
