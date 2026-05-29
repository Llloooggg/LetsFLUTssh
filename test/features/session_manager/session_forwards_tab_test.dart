import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/ssh/port_forward_rule.dart';
import 'package:letsflutssh/features/session_manager/session_forwards_tab.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/theme/app_theme.dart';
import 'package:letsflutssh/widgets/core/app_data_row.dart';
import 'package:letsflutssh/widgets/core/app_empty_state.dart';
import 'package:letsflutssh/widgets/core/app_picker_chip.dart';

import '../../helpers/frb_bootstrap.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The rule editor's Save runs the FRB-backed field validators; load
  // the real lib so the editor's accept path can complete instead of
  // throwing on an uninitialised bridge.
  setUpAll(requireFrbLoaded);

  Widget wrap(Widget child) {
    return MaterialApp(
      localizationsDelegates: S.localizationsDelegates,
      supportedLocales: S.supportedLocales,
      theme: AppTheme.dark(),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );
  }

  PortForwardRule localRule({
    String id = 'r1',
    String bindHost = '127.0.0.1',
    int bindPort = 8080,
    String remoteHost = 'svc.internal',
    int remotePort = 80,
    String description = '',
    bool enabled = true,
  }) {
    return PortForwardRule(
      id: id,
      kind: PortForwardKind.local,
      bindHost: bindHost,
      bindPort: bindPort,
      remoteHost: remoteHost,
      remotePort: remotePort,
      description: description,
      enabled: enabled,
    );
  }

  group('SessionForwardsTab — list rendering', () {
    testWidgets('empty rule list shows the empty-state, no rows', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(SessionForwardsTab(rules: const [], onChanged: (_) {})),
      );
      expect(find.byType(AppEmptyState), findsOneWidget);
      expect(find.text('No forward rules yet'), findsOneWidget);
      expect(find.byType(AppDataRow), findsNothing);
    });

    testWidgets('renders one AppDataRow per rule', (tester) async {
      await tester.pumpWidget(
        wrap(
          SessionForwardsTab(
            rules: [
              localRule(id: 'a', bindPort: 8080),
              localRule(id: 'b', bindPort: 9090),
            ],
            onChanged: (_) {},
          ),
        ),
      );
      expect(find.byType(AppDataRow), findsNWidgets(2));
      expect(find.byType(AppEmptyState), findsNothing);
    });

    testWidgets('a described rule shows its description as the title', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          SessionForwardsTab(
            rules: [localRule(description: 'web tunnel')],
            onChanged: (_) {},
          ),
        ),
      );
      expect(find.text('web tunnel'), findsOneWidget);
    });

    testWidgets('an undescribed rule falls back to bindHost:bindPort title', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          SessionForwardsTab(
            rules: [localRule(bindHost: '127.0.0.1', bindPort: 8080)],
            onChanged: (_) {},
          ),
        ),
      );
      expect(find.text('127.0.0.1:8080'), findsOneWidget);
    });
  });

  group('SessionForwardsTab — in-list mutation callbacks', () {
    testWidgets('toggle flips only the tapped rule and emits the new list', (
      tester,
    ) async {
      List<PortForwardRule>? emitted;
      final rule = localRule(enabled: true);
      await tester.pumpWidget(
        wrap(
          SessionForwardsTab(
            rules: [rule],
            onChanged: (next) => emitted = next,
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.toggle_on));
      await tester.pump();

      expect(emitted, isNotNull);
      expect(emitted!.single.id, rule.id);
      expect(emitted!.single.enabled, isFalse);
    });

    testWidgets('delete removes the tapped rule from the emitted list', (
      tester,
    ) async {
      List<PortForwardRule>? emitted;
      final keep = localRule(id: 'keep', bindPort: 1111);
      final drop = localRule(id: 'drop', bindPort: 2222);
      await tester.pumpWidget(
        wrap(
          SessionForwardsTab(
            rules: [keep, drop],
            onChanged: (next) => emitted = next,
          ),
        ),
      );

      // Second row's delete button (rows render in list order).
      await tester.tap(find.byIcon(Icons.delete_outline).last);
      await tester.pump();

      expect(emitted, isNotNull);
      expect(emitted!.map((r) => r.id), ['keep']);
    });

    testWidgets('add button opens the rule editor dialog', (tester) async {
      await tester.pumpWidget(
        wrap(SessionForwardsTab(rules: const [], onChanged: (_) {})),
      );

      await tester.tap(find.text('Add rule'));
      await tester.pumpAndSettle();

      // The editor exposes the three kind chips — proof the add modal
      // (not just the inline tab) is on screen.
      expect(find.byType(AppPickerChip), findsNWidgets(3));
      expect(find.text('Edit rule'), findsNothing);
    });
  });

  group('Forward rule editor — kind-driven fields', () {
    Future<void> openAddEditor(WidgetTester tester) async {
      await tester.pumpWidget(
        wrap(SessionForwardsTab(rules: const [], onChanged: (_) {})),
      );
      await tester.tap(find.text('Add rule'));
      await tester.pumpAndSettle();
    }

    testWidgets('local kind shows target host + port fields', (tester) async {
      await openAddEditor(tester);
      // Default kind is local → both Bind and Target fields present.
      // FieldLabel uppercases the label text it renders.
      expect(find.text('TARGET HOST'), findsOneWidget);
      expect(find.text('TARGET PORT'), findsOneWidget);
    });

    testWidgets('dynamic kind hides the target host + port fields', (
      tester,
    ) async {
      await openAddEditor(tester);
      await tester.tap(find.text('Dynamic'));
      await tester.pumpAndSettle();
      // Dynamic (SOCKS) forwards have no fixed target — those fields
      // would be meaningless and must disappear.
      expect(find.text('TARGET HOST'), findsNothing);
      expect(find.text('TARGET PORT'), findsNothing);
    });

    testWidgets('wildcard bind address surfaces the footgun warning', (
      tester,
    ) async {
      await openAddEditor(tester);
      final bindField = find.widgetWithText(TextField, '127.0.0.1');
      await tester.enterText(bindField, '0.0.0.0');
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Binding to 0.0.0.0 publishes the forward to every interface — '
          'usually you want 127.0.0.1.',
        ),
        findsOneWidget,
      );
    });
  });

  group('SessionForwardsDialog — edit/cancel contract', () {
    testWidgets('Cancel returns null and leaves the caller list intact', (
      tester,
    ) async {
      List<PortForwardRule>? result;
      var resolved = false;
      await tester.pumpWidget(
        wrap(
          Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () async {
                result = await SessionForwardsDialog.show(
                  ctx,
                  initial: [localRule()],
                );
                resolved = true;
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(resolved, isTrue);
      expect(result, isNull);
    });

    testWidgets('Save returns the current in-memory rule list', (tester) async {
      List<PortForwardRule>? result;
      final initial = [localRule(id: 'x')];
      await tester.pumpWidget(
        wrap(
          Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () async {
                result = await SessionForwardsDialog.show(
                  ctx,
                  initial: initial,
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.map((r) => r.id), ['x']);
    });

    testWidgets(
      'tapping an existing rule opens the editor in EDIT mode (title flips '
      'to "Edit rule") and saving routes through _replace, not _add',
      (tester) async {
        // Spec: a row tap calls `_showRuleEditor` with `existing=rule`,
        // which opens the editor preloaded with the rule's fields and
        // titled "Edit rule" (vs "Add rule" for the toolbar button).
        // Saving emits the updated list with the SAME rule id, not a
        // brand-new uuid — proving the dialog routed through _replace.
        List<PortForwardRule>? emitted;
        final rule = localRule(
          id: 'original-id',
          bindPort: 1234,
          description: 'old-description',
        );
        await tester.pumpWidget(
          wrap(
            SessionForwardsTab(
              rules: [rule],
              onChanged: (next) => emitted = next,
            ),
          ),
        );

        // Tap the row body (not the toggle / delete buttons) — the row's
        // title carries the description text we seeded.
        await tester.tap(find.text('old-description'));
        await tester.pumpAndSettle();

        // The edit-mode title flips to "Edit rule". (The tab's own
        // "Add rule" button still renders underneath the modal — not
        // asserting against that finder.)
        expect(
          find.text('Edit rule'),
          findsOneWidget,
          reason: 'edit-mode title proves the dialog opened in EDIT mode',
        );

        // Modify the description field then commit. The editor's
        // primary action is "OK", not "Save" — only the outer
        // session-edit dialog's Save persists. Tapping OK closes
        // the editor and routes back through `_replace`.
        await tester.enterText(
          find.widgetWithText(TextField, 'old-description'),
          'new-description',
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();

        expect(emitted, isNotNull);
        expect(emitted!.single.id, 'original-id');
        expect(emitted!.single.description, 'new-description');
        expect(emitted!.single.bindPort, 1234);
      },
    );
  });
}
