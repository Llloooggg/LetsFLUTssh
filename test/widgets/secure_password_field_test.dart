import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/widgets/secure_password_field.dart';

void main() {
  testWidgets('applies IME hardening defaults to the underlying TextField', (
    tester,
  ) async {
    final controller = TextEditingController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SecurePasswordField(controller: controller)),
      ),
    );

    final tf = tester.widget<TextField>(find.byType(TextField));
    expect(tf.obscureText, isTrue);
    expect(tf.autocorrect, isFalse);
    expect(tf.enableSuggestions, isFalse);
    expect(tf.enableIMEPersonalizedLearning, isFalse);
    expect(tf.smartDashesType, SmartDashesType.disabled);
    expect(tf.smartQuotesType, SmartQuotesType.disabled);
    expect(tf.textCapitalization, TextCapitalization.none);
    expect(tf.keyboardType, TextInputType.visiblePassword);
    expect(tf.autofillHints, const [AutofillHints.password]);

    addTearDown(controller.dispose);
  });

  testWidgets('wipes the controller on dispose', (tester) async {
    final controller = TextEditingController(text: 'hunter2');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SecurePasswordField(controller: controller)),
      ),
    );

    expect(controller.text, 'hunter2');

    // Replace with a widget that does not hold the field, triggering
    // State.dispose on SecurePasswordField.
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
    );

    expect(controller.text, isEmpty);

    addTearDown(controller.dispose);
  });

  testWidgets('passes through numeric overrides for PIN entry', (tester) async {
    final controller = TextEditingController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SecurePasswordField(
            controller: controller,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            maxLength: 6,
          ),
        ),
      ),
    );

    final tf = tester.widget<TextField>(find.byType(TextField));
    expect(tf.keyboardType, TextInputType.number);
    expect(tf.inputFormatters, isNotNull);
    expect(tf.maxLength, 6);
    // Hardening flags still apply even with numeric override.
    expect(tf.autocorrect, isFalse);
    expect(tf.enableIMEPersonalizedLearning, isFalse);

    addTearDown(controller.dispose);
  });

  testWidgets('allows revealing text via obscureText: false', (tester) async {
    final controller = TextEditingController(text: 'visible');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SecurePasswordField(controller: controller, obscureText: false),
        ),
      ),
    );

    final tf = tester.widget<TextField>(find.byType(TextField));
    expect(tf.obscureText, isFalse);

    addTearDown(controller.dispose);
  });
}
