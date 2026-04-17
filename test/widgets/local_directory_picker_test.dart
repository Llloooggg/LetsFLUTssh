import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/widgets/local_directory_picker.dart';
import 'package:path/path.dart' as p;

Widget _host(String initialPath) {
  return MaterialApp(
    localizationsDelegates: S.localizationsDelegates,
    supportedLocales: S.supportedLocales,
    home: Scaffold(
      body: LocalDirectoryPicker(initialPath: initialPath, title: 'Pick'),
    ),
  );
}

/// Pump [widget] and wait for the directory listing to come back.
///
/// The picker renders a [CircularProgressIndicator] while `dart:io`
/// walks the directory. CPI animates forever, so `pumpAndSettle` never
/// reaches steady state on its own — we drive one real async step via
/// [WidgetTester.runAsync] (which processes the `Directory.list` stream)
/// and then pump frames until the spinner is gone.
Future<void> _pumpUntilLoaded(WidgetTester tester, Widget widget) async {
  await tester.pumpWidget(widget);
  await _waitForAsyncLoad(tester);
}

Future<void> _tapAndReload(WidgetTester tester, Finder f) async {
  await tester.tap(f);
  await _waitForAsyncLoad(tester);
}

/// Drive the picker's async `dart:io` work to completion.
///
/// `CircularProgressIndicator` animates forever, so plain
/// `pumpAndSettle` never settles. Instead we yield real wall time via
/// [WidgetTester.runAsync] (which lets `Directory.list` stream complete)
/// and then pump a few frames for the pending `setState` to flush.
Future<void> _waitForAsyncLoad(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
  }
}

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('ldp-');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  testWidgets('renders the initial path in the path bar', (tester) async {
    await _pumpUntilLoaded(tester, _host(tmp.path));

    // Path bar renders the resolved current directory verbatim so the
    // user can see what they are about to save into.
    expect(find.text(tmp.path), findsOneWidget);
  });

  testWidgets('lists visible subdirectories sorted case-insensitive', (
    tester,
  ) async {
    // Create a mixed bag: visible subdirs in un-sorted order + a hidden
    // one. The UI must sort case-insensitively and drop the hidden dir.
    Directory(p.join(tmp.path, 'Banana')).createSync();
    Directory(p.join(tmp.path, 'apple')).createSync();
    Directory(p.join(tmp.path, 'cherry')).createSync();
    Directory(p.join(tmp.path, '.hidden')).createSync();

    await _pumpUntilLoaded(tester, _host(tmp.path));

    // The three visible folders show up; the dot-prefixed one is filtered.
    expect(find.text('apple'), findsOneWidget);
    expect(find.text('Banana'), findsOneWidget);
    expect(find.text('cherry'), findsOneWidget);
    expect(find.text('.hidden'), findsNothing);

    // And they come out in case-insensitive alphabetical order — not the
    // FS iteration order, which can be arbitrary.
    final texts = tester
        .widgetList<Text>(find.byType(Text))
        .map((w) => w.data)
        .whereType<String>()
        .where((s) => ['apple', 'Banana', 'cherry'].contains(s))
        .toList();
    expect(texts, ['apple', 'Banana', 'cherry']);
  });

  testWidgets('tapping a subfolder descends into it', (tester) async {
    final child = Directory(p.join(tmp.path, 'subdir'))..createSync();
    Directory(p.join(child.path, 'inner')).createSync();

    await _pumpUntilLoaded(tester, _host(tmp.path));

    await _tapAndReload(tester, find.text('subdir'));

    // Path bar now reflects the new working dir, and its sole child is visible.
    expect(find.text(child.path), findsOneWidget);
    expect(find.text('inner'), findsOneWidget);
  });

  testWidgets('up-arrow navigates to the parent directory', (tester) async {
    final child = Directory(p.join(tmp.path, 'leaf'))..createSync();

    await _pumpUntilLoaded(tester, _host(child.path));

    await _tapAndReload(tester, find.byIcon(Icons.arrow_upward));

    expect(find.text(tmp.path), findsOneWidget);
    // "leaf" is now listed as a child of tmp, not as the current dir.
    expect(find.text('leaf'), findsOneWidget);
  });

  testWidgets('empty folder shows the "empty folder" placeholder', (
    tester,
  ) async {
    // tmp has no subdirs at all — the list must render the i18n empty
    // label, not a blank area (which would be indistinguishable from
    // a stuck loading spinner).
    await _pumpUntilLoaded(tester, _host(tmp.path));

    expect(find.text('Empty folder'), findsOneWidget);
  });

  testWidgets('nonexistent path surfaces "no such file or directory"', (
    tester,
  ) async {
    final ghost = p.join(tmp.path, 'does-not-exist');
    await _pumpUntilLoaded(tester, _host(ghost));

    // The contract for a missing path is an explicit error message, not
    // a silent empty list — otherwise the user cannot tell why nothing
    // is shown.
    expect(find.text('No such file or directory'), findsOneWidget);
  });
}
