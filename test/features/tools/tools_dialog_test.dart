import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/features/tools/tools_dialog.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/theme/app_theme.dart';
import 'package:letsflutssh/utils/platform.dart' as plat;

void main() {
  setUp(() {
    plat.debugMobilePlatformOverride = false;
    plat.debugDesktopPlatformOverride = true;
  });

  tearDown(() {
    plat.debugMobilePlatformOverride = null;
    plat.debugDesktopPlatformOverride = null;
  });

  Widget buildApp() {
    return ProviderScope(
      child: MaterialApp(
        localizationsDelegates: S.localizationsDelegates,
        supportedLocales: S.supportedLocales,
        theme: AppTheme.dark(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => ToolsDialog.show(context),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('renders sidebar with SSH Keys, Snippets, Tags', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('SSH Keys'), findsOneWidget);
    expect(find.text('Snippets'), findsOneWidget);
    expect(find.text('Tags'), findsOneWidget);
  });

  testWidgets('header shows Tools title', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Tools'), findsOneWidget);
  });

  testWidgets('SSH Keys panel shown by default', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    // Key manager panel shows key-related content
    expect(find.text('No keys'), findsOneWidget);
  });

  testWidgets('tapping Snippets switches to snippet panel', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Snippets'));
    await tester.pumpAndSettle();

    expect(find.text('No snippets'), findsOneWidget);
  });

  testWidgets('tapping Tags switches to tag panel', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Tags'));
    await tester.pumpAndSettle();

    expect(find.text('No tags'), findsOneWidget);
  });

  testWidgets('close button dismisses dialog', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Tools'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(find.text('Tools'), findsNothing);
  });
}
