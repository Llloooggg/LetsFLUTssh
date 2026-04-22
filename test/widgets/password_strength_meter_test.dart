import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/widgets/password_strength_meter.dart';

Widget _wrap(Widget child) => MaterialApp(
  localizationsDelegates: S.localizationsDelegates,
  supportedLocales: S.supportedLocales,
  home: Scaffold(body: child),
);

void main() {
  group('PasswordStrengthMeter', () {
    testWidgets('hides itself when the field is empty', (tester) async {
      final ctrl = TextEditingController();
      addTearDown(ctrl.dispose);
      await tester.pumpWidget(_wrap(PasswordStrengthMeter(controller: ctrl)));
      expect(find.byType(FractionallySizedBox), findsNothing);
      expect(find.text('Weak'), findsNothing);
    });

    testWidgets('shows the weak label for a short password', (tester) async {
      final ctrl = TextEditingController(text: 'abc');
      addTearDown(ctrl.dispose);
      await tester.pumpWidget(_wrap(PasswordStrengthMeter(controller: ctrl)));
      expect(find.byType(FractionallySizedBox), findsOneWidget);
      expect(find.text('Weak'), findsOneWidget);
    });

    testWidgets('rebuilds when the controller value changes', (tester) async {
      final ctrl = TextEditingController();
      addTearDown(ctrl.dispose);
      await tester.pumpWidget(_wrap(PasswordStrengthMeter(controller: ctrl)));
      expect(find.byType(FractionallySizedBox), findsNothing);

      ctrl.text = 'abc';
      await tester.pump();
      expect(find.text('Weak'), findsOneWidget);

      ctrl.text = 'AbCd1234!@#\$';
      await tester.pump();
      // Expect a non-weak label; exact step depends on heuristic, but the
      // widget must have rebuilt and now renders one of the stronger
      // labels.
      expect(find.text('Weak'), findsNothing);
      expect(find.byType(FractionallySizedBox), findsOneWidget);
    });

    testWidgets('renders a very-strong label at high entropy', (tester) async {
      // 30+ characters of mixed classes — reliably lands at veryStrong
      // for every plausible heuristic.
      final ctrl = TextEditingController(
        text: 'Xz9!Qw4\$Mn7&Rb2#Kp5*Tg8^Lc3%Hv6@Yj1+Uo0-',
      );
      addTearDown(ctrl.dispose);
      await tester.pumpWidget(_wrap(PasswordStrengthMeter(controller: ctrl)));
      expect(find.text('Very strong'), findsOneWidget);
    });

    testWidgets('re-wires listener when the controller is swapped', (
      tester,
    ) async {
      final first = TextEditingController(text: 'abc');
      final second = TextEditingController(text: 'AbCd1234!@#\$');
      addTearDown(first.dispose);
      addTearDown(second.dispose);

      Widget build(TextEditingController c) =>
          _wrap(PasswordStrengthMeter(controller: c));

      await tester.pumpWidget(build(first));
      expect(find.text('Weak'), findsOneWidget);

      await tester.pumpWidget(build(second));
      await tester.pump();
      expect(find.text('Weak'), findsNothing);
    });
  });
}
