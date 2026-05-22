import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/theme/app_theme.dart';
import 'package:letsflutssh/widgets/core/app_collection_panel.dart';
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

  // A controllable backing list so tests can drive load, filter, and reload.
  late List<String> backing;

  Widget host({
    List<String> Function(List<String>, String)? filter,
    List<Widget> Function(BuildContext, WidgetRef, Future<void> Function())?
    actions,
  }) {
    return ProviderScope(
      child: MaterialApp(
        localizationsDelegates: S.localizationsDelegates,
        supportedLocales: S.supportedLocales,
        theme: AppTheme.dark(),
        home: Scaffold(
          body: CollectionManagerPanel<String>(
            load: (_) async => List<String>.from(backing),
            filter:
                filter ??
                (items, f) =>
                    items.where((i) => i.contains(f)).toList(growable: false),
            countLabel: (n) => 'count=$n',
            emptyMessage: 'EMPTY',
            noResultsMessage: 'NO RESULTS',
            toolbarActions: actions ?? (_, _, _) => const [],
            itemBuilder: (context, ref, item, reload) => Text('row:$item'),
          ),
        ),
      ),
    );
  }

  testWidgets('shows a spinner while loading, then the rows', (tester) async {
    backing = ['alpha', 'beta'];
    await tester.pumpWidget(host());
    // First frame: load future is in flight.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('row:alpha'), findsOneWidget);
    expect(find.text('row:beta'), findsOneWidget);
    expect(find.text('count=2'), findsOneWidget);
  });

  testWidgets('shows the empty message when nothing loads', (tester) async {
    backing = [];
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    expect(find.text('EMPTY'), findsOneWidget);
    expect(find.text('NO RESULTS'), findsNothing);
  });

  testWidgets('shows the no-results message when the filter excludes all', (
    tester,
  ) async {
    backing = ['alpha', 'beta'];
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('NO RESULTS'), findsOneWidget);
    expect(find.text('row:alpha'), findsNothing);
    // The count label still reflects the full (unfiltered) list.
    expect(find.text('count=2'), findsOneWidget);
  });

  testWidgets('filter narrows the visible rows', (tester) async {
    backing = ['alpha', 'beta', 'alpine'];
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'alp');
    await tester.pumpAndSettle();
    expect(find.text('row:alpha'), findsOneWidget);
    expect(find.text('row:alpine'), findsOneWidget);
    expect(find.text('row:beta'), findsNothing);
  });

  testWidgets('reload re-runs the loader after a mutation', (tester) async {
    backing = ['alpha'];
    await tester.pumpWidget(
      host(
        actions: (context, ref, reload) => [
          TextButton(
            onPressed: () {
              backing = ['alpha', 'gamma'];
              reload();
            },
            child: const Text('ADD'),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('row:gamma'), findsNothing);
    expect(find.text('count=1'), findsOneWidget);

    await tester.tap(find.text('ADD'));
    await tester.pumpAndSettle();
    expect(find.text('row:gamma'), findsOneWidget);
    expect(find.text('count=2'), findsOneWidget);
  });
}
