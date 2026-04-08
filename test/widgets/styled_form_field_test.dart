import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/theme/app_theme.dart';
import 'package:letsflutssh/widgets/styled_form_field.dart';

void main() {
  Widget buildApp(Widget child) {
    return MaterialApp(
      localizationsDelegates: S.localizationsDelegates,
      supportedLocales: S.supportedLocales,
      theme: AppTheme.dark(),
      home: Scaffold(body: Center(child: child)),
    );
  }

  group('FieldLabel', () {
    testWidgets('renders uppercase text', (tester) async {
      await tester.pumpWidget(buildApp(const FieldLabel('host')));

      expect(find.text('HOST'), findsOneWidget);
    });

    testWidgets('uses Inter font with fgFaint color', (tester) async {
      await tester.pumpWidget(buildApp(const FieldLabel('test')));

      final text = tester.widget<Text>(find.text('TEST'));
      expect(text.style?.fontFamily, 'Inter');
      expect(text.style?.color, AppTheme.fgFaint);
    });

    testWidgets('has bottom padding of 4', (tester) async {
      await tester.pumpWidget(buildApp(const FieldLabel('x')));

      final padding = tester.widget<Padding>(find.byType(Padding));
      expect(padding.padding, const EdgeInsets.only(bottom: 4));
    });
  });

  group('StyledInput', () {
    testWidgets('renders TextFormField with controller', (tester) async {
      final ctrl = TextEditingController(text: 'hello');
      await tester.pumpWidget(buildApp(StyledInput(controller: ctrl)));

      expect(find.byType(TextFormField), findsOneWidget);
      expect(find.text('hello'), findsOneWidget);
    });

    testWidgets('shows hint text', (tester) async {
      final ctrl = TextEditingController();
      await tester.pumpWidget(
        buildApp(StyledInput(controller: ctrl, hint: '192.168.1.1')),
      );

      expect(find.text('192.168.1.1'), findsOneWidget);
    });

    testWidgets('obscures text when obscure is true', (tester) async {
      final ctrl = TextEditingController(text: 'secret');
      await tester.pumpWidget(
        buildApp(StyledInput(controller: ctrl, obscure: true)),
      );

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.obscureText, isTrue);
    });

    testWidgets('shows suffix icon when provided', (tester) async {
      final ctrl = TextEditingController();
      await tester.pumpWidget(
        buildApp(
          StyledInput(
            controller: ctrl,
            suffixIcon: const Icon(Icons.visibility),
          ),
        ),
      );

      expect(find.byIcon(Icons.visibility), findsOneWidget);
    });

    testWidgets('uses filled bg3 decoration', (tester) async {
      final ctrl = TextEditingController();
      await tester.pumpWidget(buildApp(StyledInput(controller: ctrl)));

      final field = tester.widget<TextField>(find.byType(TextField));
      final decoration = field.decoration!;
      expect(decoration.filled, isTrue);
      expect(decoration.fillColor, AppTheme.bg3);
    });

    testWidgets('shows label text when provided', (tester) async {
      final ctrl = TextEditingController();
      await tester.pumpWidget(
        buildApp(StyledInput(controller: ctrl, labelText: 'Password')),
      );

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.decoration?.labelText, 'Password');
    });

    testWidgets('calls validator', (tester) async {
      final ctrl = TextEditingController();
      final formKey = GlobalKey<FormState>();
      String? validationResult;

      await tester.pumpWidget(
        buildApp(
          Form(
            key: formKey,
            child: StyledInput(
              controller: ctrl,
              validator: (v) {
                validationResult = 'called';
                return v?.isEmpty == true ? 'Required' : null;
              },
            ),
          ),
        ),
      );

      formKey.currentState!.validate();
      await tester.pump();

      expect(validationResult, 'called');
      expect(find.text('Required'), findsOneWidget);
    });

    testWidgets('calls onSubmitted', (tester) async {
      String? submitted;
      final ctrl = TextEditingController();

      await tester.pumpWidget(
        buildApp(
          StyledInput(controller: ctrl, onSubmitted: (v) => submitted = v),
        ),
      );

      await tester.enterText(find.byType(TextFormField), 'test');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(submitted, 'test');
    });

    testWidgets('uses custom content padding', (tester) async {
      final ctrl = TextEditingController();
      const padding = EdgeInsets.all(20);

      await tester.pumpWidget(
        buildApp(StyledInput(controller: ctrl, contentPadding: padding)),
      );

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.decoration?.contentPadding, padding);
    });

    testWidgets('autofocus works', (tester) async {
      final ctrl = TextEditingController();
      await tester.pumpWidget(
        buildApp(StyledInput(controller: ctrl, autofocus: true)),
      );

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.autofocus, isTrue);
    });
  });

  group('StyledFormField', () {
    testWidgets('renders label and input', (tester) async {
      final ctrl = TextEditingController();
      await tester.pumpWidget(
        buildApp(StyledFormField(label: 'host', controller: ctrl)),
      );

      expect(find.text('HOST'), findsOneWidget);
      expect(find.byType(TextFormField), findsOneWidget);
    });

    testWidgets('passes hint to input', (tester) async {
      final ctrl = TextEditingController();
      await tester.pumpWidget(
        buildApp(
          StyledFormField(label: 'host', controller: ctrl, hint: '192.168.1.1'),
        ),
      );

      expect(find.text('192.168.1.1'), findsOneWidget);
    });

    testWidgets('fixedHeight wraps in SizedBox', (tester) async {
      final ctrl = TextEditingController();
      await tester.pumpWidget(
        buildApp(
          StyledFormField(label: 'port', controller: ctrl, fixedHeight: true),
        ),
      );

      final sizedBoxes = tester.widgetList<SizedBox>(find.byType(SizedBox));
      final match = sizedBoxes.where(
        (s) => s.height == AppTheme.controlHeightMd,
      );
      expect(match, isNotEmpty);
    });

    testWidgets('no fixedHeight has no SizedBox constraint', (tester) async {
      final ctrl = TextEditingController();
      await tester.pumpWidget(
        buildApp(StyledFormField(label: 'port', controller: ctrl)),
      );

      final sizedBoxes = tester.widgetList<SizedBox>(find.byType(SizedBox));
      final match = sizedBoxes.where(
        (s) => s.height == AppTheme.controlHeightMd,
      );
      expect(match, isEmpty);
    });

    testWidgets('passes obscure to input', (tester) async {
      final ctrl = TextEditingController(text: 'secret');
      await tester.pumpWidget(
        buildApp(
          StyledFormField(label: 'password', controller: ctrl, obscure: true),
        ),
      );

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.obscureText, isTrue);
    });

    testWidgets('passes suffixIcon to input', (tester) async {
      final ctrl = TextEditingController();
      await tester.pumpWidget(
        buildApp(
          StyledFormField(
            label: 'password',
            controller: ctrl,
            suffixIcon: const Icon(Icons.visibility_off),
          ),
        ),
      );

      expect(find.byIcon(Icons.visibility_off), findsOneWidget);
    });

    testWidgets('passes validator to input', (tester) async {
      final ctrl = TextEditingController();
      final formKey = GlobalKey<FormState>();

      await tester.pumpWidget(
        buildApp(
          Form(
            key: formKey,
            child: StyledFormField(
              label: 'host',
              controller: ctrl,
              validator: (v) => v?.isEmpty == true ? 'Required' : null,
            ),
          ),
        ),
      );

      formKey.currentState!.validate();
      await tester.pump();

      expect(find.text('Required'), findsOneWidget);
    });

    testWidgets('column has crossAxisAlignment start', (tester) async {
      final ctrl = TextEditingController();
      await tester.pumpWidget(
        buildApp(StyledFormField(label: 'test', controller: ctrl)),
      );

      final column = tester.widget<Column>(find.byType(Column).first);
      expect(column.crossAxisAlignment, CrossAxisAlignment.start);
    });
  });
}
