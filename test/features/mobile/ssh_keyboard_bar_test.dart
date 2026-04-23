import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/features/mobile/ssh_keyboard_bar.dart';
import 'package:letsflutssh/features/mobile/ssh_key_sequences.dart';
import 'package:letsflutssh/theme/app_theme.dart';
import '''package:letsflutssh/l10n/app_localizations.dart''';

void main() {
  // Suppress HapticFeedback calls in tests
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async => null,
        );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Widget buildApp({
    required void Function(String) onInput,
    GlobalKey<SshKeyboardBarState>? keyboardKey,
    VoidCallback? onPaste,
    VoidCallback? onSnippets,
    ValueChanged<bool>? onCopyModeChanged,
  }) {
    return MaterialApp(
      localizationsDelegates: S.localizationsDelegates,
      supportedLocales: S.supportedLocales,
      theme: AppTheme.dark(),
      home: Scaffold(
        body: SshKeyboardBar(
          key: keyboardKey,
          onInput: onInput,
          onPaste: onPaste,
          onSnippets: onSnippets,
          onCopyModeChanged: onCopyModeChanged,
        ),
      ),
    );
  }

  group('SshKeyboardBar', () {
    testWidgets('renders main row buttons', (tester) async {
      await tester.pumpWidget(buildApp(onInput: (_) {}));
      expect(find.text('Esc'), findsOneWidget);
      expect(find.text('Tab'), findsOneWidget);
      expect(find.text('Ctrl'), findsOneWidget);
      expect(find.text('Alt'), findsOneWidget);
      expect(find.text('Fn'), findsOneWidget);
      expect(find.text('|'), findsOneWidget);
      expect(find.text('~'), findsOneWidget);
      expect(find.text('/'), findsOneWidget);
      expect(find.text('-'), findsOneWidget);
    });

    testWidgets('renders arrow key icons', (tester) async {
      await tester.pumpWidget(buildApp(onInput: (_) {}));
      expect(find.byIcon(Icons.keyboard_arrow_left), findsOneWidget);
      expect(find.byIcon(Icons.keyboard_arrow_right), findsOneWidget);
      expect(find.byIcon(Icons.keyboard_arrow_up), findsOneWidget);
      expect(find.byIcon(Icons.keyboard_arrow_down), findsOneWidget);
    });

    testWidgets('Esc sends escape sequence', (tester) async {
      String? sent;
      await tester.pumpWidget(buildApp(onInput: (s) => sent = s));
      await tester.tap(find.text('Esc'));
      await tester.pump();
      expect(sent, SshKeySequences.escape);
    });

    testWidgets('Tab sends tab sequence', (tester) async {
      String? sent;
      await tester.pumpWidget(buildApp(onInput: (s) => sent = s));
      await tester.tap(find.text('Tab'));
      await tester.pump();
      expect(sent, SshKeySequences.tab);
    });

    testWidgets('pipe sends | character', (tester) async {
      String? sent;
      await tester.pumpWidget(buildApp(onInput: (s) => sent = s));
      await tester.tap(find.text('|'));
      await tester.pump();
      expect(sent, '|');
    });

    testWidgets('tilde sends ~ character', (tester) async {
      String? sent;
      await tester.pumpWidget(buildApp(onInput: (s) => sent = s));
      await tester.tap(find.text('~'));
      await tester.pump();
      expect(sent, '~');
    });

    testWidgets('slash sends / character', (tester) async {
      String? sent;
      await tester.pumpWidget(buildApp(onInput: (s) => sent = s));
      await tester.tap(find.text('/'));
      await tester.pump();
      expect(sent, '/');
    });

    testWidgets('dash sends - character', (tester) async {
      String? sent;
      await tester.pumpWidget(buildApp(onInput: (s) => sent = s));
      await tester.tap(find.text('-'));
      await tester.pump();
      expect(sent, '-');
    });

    testWidgets('arrow left sends correct sequence', (tester) async {
      String? sent;
      await tester.pumpWidget(buildApp(onInput: (s) => sent = s));
      await tester.tap(find.byIcon(Icons.keyboard_arrow_left));
      await tester.pump();
      expect(sent, SshKeySequences.arrowLeft);
    });

    testWidgets('arrow up sends correct sequence', (tester) async {
      String? sent;
      await tester.pumpWidget(buildApp(onInput: (s) => sent = s));
      await tester.tap(find.byIcon(Icons.keyboard_arrow_up));
      await tester.pump();
      expect(sent, SshKeySequences.arrowUp);
    });

    testWidgets('arrow down sends correct sequence', (tester) async {
      String? sent;
      await tester.pumpWidget(buildApp(onInput: (s) => sent = s));
      await tester.tap(find.byIcon(Icons.keyboard_arrow_down));
      await tester.pump();
      expect(sent, SshKeySequences.arrowDown);
    });

    testWidgets('arrow right sends correct sequence', (tester) async {
      String? sent;
      await tester.pumpWidget(buildApp(onInput: (s) => sent = s));
      await tester.tap(find.byIcon(Icons.keyboard_arrow_right));
      await tester.pump();
      expect(sent, SshKeySequences.arrowRight);
    });

    testWidgets('Fn toggles F-key row visibility', (tester) async {
      await tester.pumpWidget(buildApp(onInput: (_) {}));
      // Initially no F-keys visible
      expect(find.text('F1'), findsNothing);

      // Tap Fn to show
      await tester.tap(find.text('Fn'));
      await tester.pump();
      expect(find.text('F1'), findsOneWidget);
      expect(find.text('F12'), findsOneWidget);

      // Tap Fn again to hide
      await tester.tap(find.text('Fn'));
      await tester.pump();
      expect(find.text('F1'), findsNothing);
    });

    testWidgets('F1 sends correct sequence when Fn row is open', (
      tester,
    ) async {
      String? sent;
      await tester.pumpWidget(buildApp(onInput: (s) => sent = s));
      // Open Fn row
      await tester.tap(find.text('Fn'));
      await tester.pump();
      // Tap F1
      await tester.tap(find.text('F1'));
      await tester.pump();
      expect(sent, SshKeySequences.f1);
    });

    testWidgets('Ctrl modifier applies to next key (one-shot)', (tester) async {
      final sentData = <String>[];
      await tester.pumpWidget(buildApp(onInput: (s) => sentData.add(s)));

      // Tap Ctrl (one-shot)
      await tester.tap(find.text('Ctrl'));
      await tester.pump();

      // Tap a special char (|) — Ctrl applies to single char
      await tester.tap(find.text('|'));
      await tester.pump();

      // Ctrl+| should send ctrlKey('|')
      expect(sentData.last, SshKeySequences.ctrlKey('|'));
    });

    testWidgets('Alt modifier applies ESC prefix (one-shot)', (tester) async {
      final sentData = <String>[];
      await tester.pumpWidget(buildApp(onInput: (s) => sentData.add(s)));

      // Tap Alt (one-shot)
      await tester.tap(find.text('Alt'));
      await tester.pump();

      // Tap '~'
      await tester.tap(find.text('~'));
      await tester.pump();

      // Alt+~ should send ESC prefix
      expect(sentData.last, SshKeySequences.altKey('~'));
    });

    testWidgets('Ctrl deactivates after one-shot use', (tester) async {
      final sentData = <String>[];
      await tester.pumpWidget(buildApp(onInput: (s) => sentData.add(s)));

      // Activate Ctrl
      await tester.tap(find.text('Ctrl'));
      await tester.pump();

      // First key with Ctrl
      await tester.tap(find.text('/'));
      await tester.pump();

      // Second key without Ctrl
      await tester.tap(find.text('/'));
      await tester.pump();

      // Second should be raw '/'
      expect(sentData.last, '/');
    });

    testWidgets('Ctrl double-tap locks, triple-tap unlocks', (tester) async {
      final sentData = <String>[];
      await tester.pumpWidget(buildApp(onInput: (s) => sentData.add(s)));

      // First tap = once
      await tester.tap(find.text('Ctrl'));
      await tester.pump();

      // Second tap = locked
      await tester.tap(find.text('Ctrl'));
      await tester.pump();

      // Send two keys — both should have Ctrl
      await tester.tap(find.text('/'));
      await tester.pump();
      final firstWithCtrl = sentData.last;

      await tester.tap(find.text('/'));
      await tester.pump();
      final secondWithCtrl = sentData.last;

      expect(firstWithCtrl, SshKeySequences.ctrlKey('/'));
      expect(secondWithCtrl, SshKeySequences.ctrlKey('/'));

      // Third tap on Ctrl = off
      await tester.tap(find.text('Ctrl'));
      await tester.pump();

      await tester.tap(find.text('/'));
      await tester.pump();
      expect(sentData.last, '/');
    });
  });

  group('SshKeyboardBar — layout', () {
    testWidgets('main row keys are inside a horizontal ListView', (
      tester,
    ) async {
      await tester.pumpWidget(buildApp(onInput: (_) {}));
      // The main row should contain a horizontal ListView for scrollable keys
      final listViews = find.byType(ListView);
      expect(listViews, findsOneWidget);
      final listView = tester.widget<ListView>(listViews.first);
      expect(listView.scrollDirection, Axis.horizontal);
    });

    testWidgets('Fn button is outside scrollable area', (tester) async {
      await tester.pumpWidget(buildApp(onInput: (_) {}));
      // Fn should always be visible — it's in the outer Row, not inside ListView
      expect(find.text('Fn'), findsOneWidget);

      // Fn button should be a direct descendant of the main Row, not ListView
      final fnFinder = find.text('Fn');
      final fnWidget = tester.element(fnFinder);
      // Walk up to find if Fn is inside a ListView — it should NOT be
      bool insideListView = false;
      fnWidget.visitAncestorElements((element) {
        if (element.widget is ListView) {
          insideListView = true;
          return false;
        }
        // Stop at the main Container (height 48)
        if (element.widget is Container) return false;
        return true;
      });
      expect(insideListView, isFalse);
    });

    testWidgets('F-keys row appears with its own ListView when Fn active', (
      tester,
    ) async {
      await tester.pumpWidget(buildApp(onInput: (_) {}));

      // Initially one ListView (main row)
      expect(find.byType(ListView), findsOneWidget);

      // Tap Fn to show F-key row
      await tester.tap(find.text('Fn'));
      await tester.pump();

      // Now two ListViews (F-keys row + main row)
      expect(find.byType(ListView), findsNWidgets(2));
    });
  });

  group('SshKeyboardBar — applyModifiers for system keyboard', () {
    testWidgets('applyModifiers returns raw data when no modifier active', (
      tester,
    ) async {
      final key = GlobalKey<SshKeyboardBarState>();
      await tester.pumpWidget(buildApp(onInput: (_) {}, keyboardKey: key));

      expect(key.currentState!.applyModifiers('c'), 'c');
      expect(key.currentState!.applyModifiers('hello'), 'hello');
    });

    testWidgets('applyModifiers applies Ctrl to single char', (tester) async {
      final key = GlobalKey<SshKeyboardBarState>();
      await tester.pumpWidget(buildApp(onInput: (_) {}, keyboardKey: key));

      // Activate Ctrl (once)
      await tester.tap(find.text('Ctrl'));
      await tester.pump();

      final result = key.currentState!.applyModifiers('c');
      expect(result, SshKeySequences.ctrlKey('c'));
      // 0x03 = Ctrl+C (SIGINT)
      expect(result.codeUnitAt(0), 0x03);
    });

    testWidgets('applyModifiers consumes one-shot Ctrl', (tester) async {
      final key = GlobalKey<SshKeyboardBarState>();
      await tester.pumpWidget(buildApp(onInput: (_) {}, keyboardKey: key));

      // Activate Ctrl (once)
      await tester.tap(find.text('Ctrl'));
      await tester.pump();

      // First call applies Ctrl
      expect(
        key.currentState!.applyModifiers('c'),
        SshKeySequences.ctrlKey('c'),
      );
      await tester.pump(); // process setState

      // Second call — modifier consumed, raw char
      expect(key.currentState!.applyModifiers('c'), 'c');
    });

    testWidgets('applyModifiers applies Alt ESC prefix', (tester) async {
      final key = GlobalKey<SshKeyboardBarState>();
      await tester.pumpWidget(buildApp(onInput: (_) {}, keyboardKey: key));

      await tester.tap(find.text('Alt'));
      await tester.pump();

      expect(
        key.currentState!.applyModifiers('x'),
        SshKeySequences.altKey('x'),
      );
    });

    testWidgets('applyModifiers skips multi-char strings', (tester) async {
      final key = GlobalKey<SshKeyboardBarState>();
      await tester.pumpWidget(buildApp(onInput: (_) {}, keyboardKey: key));

      await tester.tap(find.text('Ctrl'));
      await tester.pump();

      // Multi-char string (e.g. paste) — modifiers don't apply
      expect(key.currentState!.applyModifiers('hello'), 'hello');
    });

    testWidgets('applyModifiers combines Ctrl and Alt (C-M-x)', (tester) async {
      // Regression guard: a prior implementation wrote both transforms
      // to the SAME `result` slot, reading the original `data` each
      // time, so the Ctrl branch overwrote the Alt one and Alt+Ctrl+X
      // produced bare Ctrl+X (`\x18`). Emacs `C-M-x` / readline
      // meta-control sequences must come out as `ESC + Ctrl-X`
      // (`\x1b\x18`), chaining the two transforms through a single
      // cascading `result`.
      final key = GlobalKey<SshKeyboardBarState>();
      await tester.pumpWidget(buildApp(onInput: (_) {}, keyboardKey: key));

      await tester.tap(find.text('Ctrl'));
      await tester.pump();
      await tester.tap(find.text('Alt'));
      await tester.pump();

      final result = key.currentState!.applyModifiers('x');
      expect(
        result,
        SshKeySequences.altKey(SshKeySequences.ctrlKey('x')),
        reason: 'Alt must wrap Ctrl, not replace it',
      );
      expect(result.length, 2, reason: 'ESC + control byte = two bytes');
      expect(result.codeUnitAt(0), 0x1b, reason: 'leading ESC from Alt');
      expect(result.codeUnitAt(1), 0x18, reason: 'trailing Ctrl-X from Ctrl');
    });

    testWidgets('applyModifiers with locked Ctrl persists across calls', (
      tester,
    ) async {
      final key = GlobalKey<SshKeyboardBarState>();
      await tester.pumpWidget(buildApp(onInput: (_) {}, keyboardKey: key));

      // Double-tap Ctrl to lock
      await tester.tap(find.text('Ctrl'));
      await tester.pump();
      await tester.tap(find.text('Ctrl'));
      await tester.pump();

      expect(
        key.currentState!.applyModifiers('a'),
        SshKeySequences.ctrlKey('a'),
      );
      await tester.pump();
      expect(
        key.currentState!.applyModifiers('c'),
        SshKeySequences.ctrlKey('c'),
      );
      await tester.pump();
      expect(
        key.currentState!.applyModifiers('d'),
        SshKeySequences.ctrlKey('d'),
      );
    });
  });

  group('Copy mode', () {
    testWidgets('renders copy button icon', (tester) async {
      await tester.pumpWidget(buildApp(onInput: (_) {}));
      expect(find.byIcon(Icons.copy), findsOneWidget);
    });

    testWidgets('tapping copy button toggles copy mode and fires callback', (
      tester,
    ) async {
      final modes = <bool>[];
      await tester.pumpWidget(
        buildApp(onInput: (_) {}, onCopyModeChanged: modes.add),
      );

      // Enter copy mode via the Copy icon in the normal row.
      await tester.tap(find.byIcon(Icons.copy));
      await tester.pump();
      expect(modes, [true]);

      // Exit via the Cancel (close) icon that now lives inside the
      // in-place copy-mode row — Icons.copy in this row is the Copy
      // action (fires onCopyPressed), not a toggle.
      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      expect(modes, [true, false]);
    });

    testWidgets('copyMode getter reflects state', (tester) async {
      final key = GlobalKey<SshKeyboardBarState>();
      await tester.pumpWidget(buildApp(onInput: (_) {}, keyboardKey: key));

      expect(key.currentState!.copyMode, isFalse);

      await tester.tap(find.byIcon(Icons.copy));
      await tester.pump();
      expect(key.currentState!.copyMode, isTrue);

      // The copy-mode row swaps the normal keys for a hint + Copy +
      // Cancel — Cancel (Icons.close) is the tap target that exits.
      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      expect(key.currentState!.copyMode, isFalse);
    });

    testWidgets('snippets button hidden when onSnippets is null', (
      tester,
    ) async {
      await tester.pumpWidget(buildApp(onInput: (_) {}));
      // Icons.code is the snippets affordance.  Main row has no other
      // Icons.code widget, so its absence proves the button is hidden.
      expect(find.byIcon(Icons.code), findsNothing);
    });

    testWidgets('tapping snippets button fires onSnippets callback', (
      tester,
    ) async {
      var fired = false;
      await tester.pumpWidget(
        buildApp(onInput: (_) {}, onSnippets: () => fired = true),
      );
      expect(find.byIcon(Icons.code), findsOneWidget);
      await tester.tap(find.byIcon(Icons.code));
      await tester.pump();
      expect(fired, isTrue);
    });

    testWidgets('exitCopyMode resets state and fires callback', (tester) async {
      final key = GlobalKey<SshKeyboardBarState>();
      final modes = <bool>[];
      await tester.pumpWidget(
        buildApp(
          onInput: (_) {},
          keyboardKey: key,
          onCopyModeChanged: modes.add,
        ),
      );

      // Activate select mode
      await tester.tap(find.byIcon(Icons.copy));
      await tester.pump();
      expect(key.currentState!.copyMode, isTrue);

      // Programmatic exit
      key.currentState!.exitCopyMode();
      await tester.pump();
      expect(key.currentState!.copyMode, isFalse);
      expect(modes, [true, false]);
    });

    testWidgets('exitCopyMode is no-op when already off', (tester) async {
      final key = GlobalKey<SshKeyboardBarState>();
      final modes = <bool>[];
      await tester.pumpWidget(
        buildApp(
          onInput: (_) {},
          keyboardKey: key,
          onCopyModeChanged: modes.add,
        ),
      );

      key.currentState!.exitCopyMode();
      await tester.pump();
      expect(modes, isEmpty);
    });
  });

  group('Paste button', () {
    testWidgets('renders paste icon in keyboard bar', (tester) async {
      await tester.pumpWidget(buildApp(onInput: (_) {}));
      expect(find.byIcon(Icons.paste), findsOneWidget);
    });

    testWidgets('tapping paste button fires onPaste callback', (tester) async {
      var pasteCalled = false;
      await tester.pumpWidget(
        buildApp(onInput: (_) {}, onPaste: () => pasteCalled = true),
      );

      await tester.tap(find.byIcon(Icons.paste));
      await tester.pump();
      expect(pasteCalled, isTrue);
    });

    testWidgets('paste button is outside scrollable area', (tester) async {
      await tester.pumpWidget(buildApp(onInput: (_) {}));

      final pasteFinder = find.byIcon(Icons.paste);
      final pasteElement = tester.element(pasteFinder);
      bool insideListView = false;
      pasteElement.visitAncestorElements((element) {
        if (element.widget is ListView) {
          insideListView = true;
          return false;
        }
        if (element.widget is Container) return false;
        return true;
      });
      expect(insideListView, isFalse);
    });
  });
}
