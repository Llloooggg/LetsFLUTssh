import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/features/tools/tools_screen.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/theme/app_theme.dart';

void main() {
  Widget buildApp() {
    return MaterialApp(
      localizationsDelegates: S.localizationsDelegates,
      supportedLocales: S.supportedLocales,
      theme: AppTheme.dark(),
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => ToolsScreen.show(context),
            child: const Text('Open'),
          ),
        ),
      ),
    );
  }

  group('ToolsScreen', () {
    testWidgets('shows Tools title', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Tools'), findsOneWidget);
    });

    testWidgets('shows all four tool tiles', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('SSH Keys'), findsOneWidget);
      expect(find.text('Snippets'), findsOneWidget);
      expect(find.text('Tags'), findsOneWidget);
      expect(find.text('Known Hosts'), findsOneWidget);
    });

    testWidgets('renders tool icons', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.vpn_key), findsOneWidget);
      expect(find.byIcon(Icons.code), findsOneWidget);
      expect(find.byIcon(Icons.label_outline), findsOneWidget);
      expect(find.byIcon(Icons.verified_user), findsOneWidget);
    });
  });
}
