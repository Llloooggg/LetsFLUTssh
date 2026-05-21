import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/widgets/ssh_keys/agent_signature_request_dialog.dart';

Widget _wrap(Widget child) => MaterialApp(
  localizationsDelegates: S.localizationsDelegates,
  supportedLocales: S.supportedLocales,
  home: Scaffold(body: child),
);

Future<AgentSignatureDecision?> _openDialog(
  WidgetTester tester, {
  String keyLabel = 'Lab key',
  String? requester,
}) async {
  AgentSignatureDecision? result;
  await tester.pumpWidget(
    _wrap(
      Builder(
        builder: (ctx) => TextButton(
          onPressed: () async {
            result = await AgentSignatureRequestDialog.show(
              ctx,
              keyLabel: keyLabel,
              requesterName: requester,
            );
          },
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  group('AgentSignatureRequestDialog', () {
    testWidgets('renders title + key label + requester name', (tester) async {
      await _openDialog(tester, keyLabel: 'Lab key', requester: 'git');
      expect(find.text('Signature request'), findsOneWidget);
      expect(find.text('Lab key'), findsAtLeastNWidgets(1));
      // Body mentions both placeholders.
      final body = find.textContaining('git');
      expect(body, findsOneWidget);
    });

    testWidgets(
      'uses fallback "external SSH client" text when requester is null',
      (tester) async {
        await _openDialog(tester, keyLabel: 'Lab key', requester: null);
        // English fallback string from app_en.arb.
        expect(find.textContaining('An external SSH client'), findsOneWidget);
      },
    );

    testWidgets('Authorize once pops AgentSignatureDecision.authorizeOnce', (
      tester,
    ) async {
      AgentSignatureDecision? captured;
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (ctx) => TextButton(
              onPressed: () async {
                captured = await AgentSignatureRequestDialog.show(
                  ctx,
                  keyLabel: 'Lab key',
                  requesterName: 'git',
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Authorize once'));
      await tester.pumpAndSettle();
      expect(captured, AgentSignatureDecision.authorizeOnce);
    });

    testWidgets('Authorize and remember pops authorizeAlways', (tester) async {
      AgentSignatureDecision? captured;
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (ctx) => TextButton(
              onPressed: () async {
                captured = await AgentSignatureRequestDialog.show(
                  ctx,
                  keyLabel: 'Lab key',
                  requesterName: 'ssh',
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Authorize and remember'));
      await tester.pumpAndSettle();
      expect(captured, AgentSignatureDecision.authorizeAlways);
    });

    testWidgets('Deny pops AgentSignatureDecision.deny', (tester) async {
      AgentSignatureDecision? captured;
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (ctx) => TextButton(
              onPressed: () async {
                captured = await AgentSignatureRequestDialog.show(
                  ctx,
                  keyLabel: 'Lab key',
                  requesterName: 'code',
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Deny'));
      await tester.pumpAndSettle();
      expect(captured, AgentSignatureDecision.deny);
    });
  });
}
