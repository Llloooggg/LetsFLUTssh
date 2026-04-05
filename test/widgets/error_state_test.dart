import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:letsflutssh/widgets/error_state.dart';
import 'package:letsflutssh/theme/app_theme.dart';

void main() {
  Widget wrap(Widget child) {
    return MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(body: child),
    );
  }

  group('ErrorState', () {
    testWidgets('shows icon and message', (tester) async {
      await tester.pumpWidget(
        wrap(const ErrorState(message: 'Something went wrong')),
      );

      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.text('Something went wrong'), findsOneWidget);
    });

    testWidgets('shows no buttons when no callbacks provided', (tester) async {
      await tester.pumpWidget(wrap(const ErrorState(message: 'Error')));

      expect(find.byType(ElevatedButton), findsNothing);
      expect(find.byType(OutlinedButton), findsNothing);
    });

    testWidgets('shows retry button when onRetry provided', (tester) async {
      var retried = false;
      await tester.pumpWidget(
        wrap(ErrorState(message: 'Error', onRetry: () => retried = true)),
      );

      expect(find.byType(ElevatedButton), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      expect(retried, isTrue);
    });

    testWidgets('shows custom retry label', (tester) async {
      await tester.pumpWidget(
        wrap(
          ErrorState(message: 'Error', onRetry: () {}, retryLabel: 'Reconnect'),
        ),
      );

      expect(find.text('Reconnect'), findsOneWidget);
    });

    testWidgets('shows both buttons when both callbacks provided', (
      tester,
    ) async {
      var secondaryCalled = false;
      await tester.pumpWidget(
        wrap(
          ErrorState(
            message: 'Error',
            onRetry: () {},
            retryLabel: 'Reconnect',
            onSecondary: () => secondaryCalled = true,
            secondaryLabel: 'Close',
          ),
        ),
      );

      expect(find.byType(ElevatedButton), findsOneWidget);
      expect(find.byType(OutlinedButton), findsOneWidget);
      expect(find.text('Reconnect'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);

      await tester.tap(find.text('Close'));
      expect(secondaryCalled, isTrue);
    });

    testWidgets('shows only secondary button when only onSecondary provided', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          ErrorState(
            message: 'Error',
            onSecondary: () {},
            secondaryLabel: 'Dismiss',
          ),
        ),
      );

      expect(find.byType(ElevatedButton), findsNothing);
      expect(find.byType(OutlinedButton), findsOneWidget);
      expect(find.text('Dismiss'), findsOneWidget);
    });
  });
}
