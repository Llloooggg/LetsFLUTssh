import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/app/already_running_app.dart';

void main() {
  testWidgets('AlreadyRunningApp renders its blocker content', (tester) async {
    await tester.pumpWidget(const AlreadyRunningApp());
    // The widget is the bare MaterialApp raised when the single-instance
    // lock is already held; assert the user-visible copy + the OK
    // button are both present so a future restyle cannot silently
    // orphan the one actionable affordance on the screen.
    expect(
      find.text('Another instance of LetsFLUTssh is already running.'),
      findsOneWidget,
    );
    expect(find.widgetWithText(FilledButton, 'OK'), findsOneWidget);
    expect(find.byIcon(Icons.block), findsOneWidget);
  });

  testWidgets('AlreadyRunningApp uses a dark MaterialApp theme', (
    tester,
  ) async {
    // The blocker runs before the app's AppTheme resolves, so it hand-
    // rolls `ThemeData.dark` instead of going through the shared
    // OneDark palette. Pin the brightness so a refactor that swapped
    // the theme for a light variant would be caught before release.
    await tester.pumpWidget(const AlreadyRunningApp());
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.theme?.brightness, Brightness.dark);
    expect(app.debugShowCheckedModeBanner, isFalse);
  });
}
