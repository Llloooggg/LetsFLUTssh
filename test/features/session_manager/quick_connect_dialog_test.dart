import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/features/session_manager/quick_connect_dialog.dart';
import 'package:letsflutssh/theme/app_theme.dart';
import 'package:letsflutssh/widgets/dropdown_select_button.dart';
import '''package:letsflutssh/l10n/app_localizations.dart''';

void main() {
  SSHConfig? dialogResult;

  Widget buildApp() {
    dialogResult = null;
    return MaterialApp(
      localizationsDelegates: S.localizationsDelegates,
      supportedLocales: S.supportedLocales,
      theme: AppTheme.dark(),
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              dialogResult = await QuickConnectDialog.show(context);
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );
  }

  Finder fieldByHint(String hint) => find.widgetWithText(TextFormField, hint);

  group('QuickConnectDialog', () {
    testWidgets('shows bottom sheet with title', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Quick Connect'), findsOneWidget);
    });

    testWidgets('has Host, Port, Username, Password fields', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('HOST *'), findsOneWidget);
      expect(find.text('PORT'), findsOneWidget);
      expect(find.text('USERNAME *'), findsOneWidget);
      expect(find.text('PASSWORD'), findsOneWidget);
    });

    testWidgets('port defaults to 22', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('22'), findsWidgets); // hint + value
    });

    testWidgets('has Key File and Key Passphrase fields', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Select Key File'), findsOneWidget);
      expect(find.text('KEY PASSPHRASE'), findsOneWidget);
    });

    testWidgets('has Cancel and Connect buttons', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Connect'), findsOneWidget);
    });

    testWidgets('Cancel closes bottom sheet', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Quick Connect'), findsNothing);
    });

    testWidgets('Connect validates required fields', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      expect(find.text('Required'), findsWidgets);
    });

    testWidgets('password visibility toggle works', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.visibility), findsWidgets);

      await tester.tap(find.byIcon(Icons.visibility).first);
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.visibility_off), findsWidgets);
    });

    testWidgets('PEM text toggle expands key text field', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Key Text (PEM)'), findsNothing);

      await tester.tap(find.text('Paste PEM key text'));
      await tester.pumpAndSettle();

      expect(find.text('Key Text (PEM)'), findsOneWidget);
    });

    testWidgets('Connect with valid fields returns SSHConfig', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(fieldByHint('192.168.1.1'), 'myhost.com');
      await tester.enterText(fieldByHint('root'), 'admin');
      await tester.enterText(fieldByHint('22'), '2222');
      await tester.enterText(fieldByHint('••••••••'), 'secret');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      expect(dialogResult, isNotNull);
      expect(dialogResult!.host, 'myhost.com');
      expect(dialogResult!.user, 'admin');
      expect(dialogResult!.port, 2222);
      expect(dialogResult!.password, 'secret');
    });

    testWidgets('Connect without required fields does not close', (
      tester,
    ) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      expect(dialogResult, isNull);
      expect(find.text('Quick Connect'), findsOneWidget);
    });

    testWidgets('key file button renders as a DropdownSelectButton', (
      tester,
    ) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // After the button-widget unification the picker moved off
      // raw Material `OutlinedButton.icon` to our themed
      // `DropdownSelectButton` (left-aligned row, `bg3` fill,
      // matches `StyledFormField`'s visual column).
      expect(
        find.widgetWithText(DropdownSelectButton, 'Select Key File'),
        findsOneWidget,
      );
    });

    testWidgets('passphrase visibility toggle works', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      final visIcons = find.byIcon(Icons.visibility);
      expect(visIcons, findsWidgets);

      await tester.tap(visIcons.last);
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.visibility_off), findsWidgets);
    });

    testWidgets('Connect with PEM key data', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(fieldByHint('192.168.1.1'), 'h');
      await tester.enterText(fieldByHint('root'), 'u');

      await tester.tap(find.text('Paste PEM key text'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Key Text (PEM)'),
        'PEM-DATA',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      expect(dialogResult, isNotNull);
      expect(dialogResult!.keyData, 'PEM-DATA');
    });
  });
}
