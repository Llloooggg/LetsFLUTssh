import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/app/app_toolbar.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    localizationsDelegates: S.localizationsDelegates,
    supportedLocales: S.supportedLocales,
    home: Scaffold(
      // Scaffold carries a Drawer so the `showMenuButton` branch can
      // call `Scaffold.of(context).openDrawer()` without throwing.
      // No AppBar — auto-injected menu icon would clash with the
      // toolbar's own `Icons.menu` assertion.
      drawer: const Drawer(),
      body: child,
    ),
  );
}

void main() {
  testWidgets('desktop shape: sidebar toggle button renders chevron_left '
      'when sidebar open', (tester) async {
    await tester.pumpWidget(
      _wrap(
        AppToolbar(
          sidebarOpen: true,
          onToggleSidebar: () {},
          onTools: () {},
          onSettings: () {},
        ),
      ),
    );
    expect(find.byIcon(Icons.chevron_left), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsNothing);
    expect(find.byIcon(Icons.menu), findsNothing);
  });

  testWidgets('desktop shape: chevron_right when sidebar closed', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        AppToolbar(
          sidebarOpen: false,
          onToggleSidebar: () {},
          onTools: () {},
          onSettings: () {},
        ),
      ),
    );
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
  });

  testWidgets(
    'mobile shape: showMenuButton swaps the sidebar toggle for a drawer '
    'opener',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          AppToolbar(
            sidebarOpen: true,
            onToggleSidebar: () {},
            showMenuButton: true,
            onTools: () {},
            onSettings: () {},
          ),
        ),
      );
      // Mobile shell mounts the toolbar inside a Scaffold with a
      // drawer; the menu icon fires `Scaffold.of(context).openDrawer()`
      // instead of the sidebar-toggle callback. Pin that the branch
      // actually takes the menu-icon path under showMenuButton=true.
      expect(find.byIcon(Icons.menu), findsOneWidget);
      expect(find.byIcon(Icons.chevron_left), findsNothing);
      expect(find.byIcon(Icons.chevron_right), findsNothing);
    },
  );

  testWidgets('isTerminalTab renders duplicate-tab + duplicate-down icons', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        AppToolbar(
          sidebarOpen: true,
          onToggleSidebar: () {},
          isTerminalTab: true,
          onDuplicateTab: () {},
          onDuplicateDown: () {},
          onTools: () {},
          onSettings: () {},
        ),
      ),
    );
    expect(find.byIcon(Icons.content_copy), findsOneWidget);
    expect(find.byIcon(Icons.horizontal_split), findsOneWidget);
  });

  testWidgets('onTools + onSettings fire via their dense AppButtons', (
    tester,
  ) async {
    var toolsTaps = 0;
    var settingsTaps = 0;
    await tester.pumpWidget(
      _wrap(
        AppToolbar(
          sidebarOpen: true,
          onToggleSidebar: () {},
          onTools: () => toolsTaps++,
          onSettings: () => settingsTaps++,
        ),
      ),
    );
    await tester.tap(find.text('Tools'));
    await tester.pump();
    await tester.tap(find.text('Settings'));
    await tester.pump();
    expect(toolsTaps, 1);
    expect(settingsTaps, 1);
  });
}
