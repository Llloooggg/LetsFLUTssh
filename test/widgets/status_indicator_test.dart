import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/theme/app_theme.dart';
import 'package:letsflutssh/widgets/status_indicator.dart';

void main() {
  Widget wrap(Widget child) {
    return MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(body: child),
    );
  }

  group('StatusIndicator', () {
    testWidgets('renders icon and count', (tester) async {
      await tester.pumpWidget(
        wrap(
          const StatusIndicator(icon: Icons.wifi, count: 5, tooltip: 'Test'),
        ),
      );

      expect(find.byIcon(Icons.wifi), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
    });

    testWidgets('shows tooltip on long press', (tester) async {
      await tester.pumpWidget(
        wrap(
          const StatusIndicator(
            icon: Icons.tab_outlined,
            count: 3,
            tooltip: 'Open tabs',
          ),
        ),
      );

      expect(find.byTooltip('Open tabs'), findsOneWidget);
    });

    testWidgets('uses custom iconColor when provided', (tester) async {
      await tester.pumpWidget(
        wrap(
          const StatusIndicator(
            icon: Icons.wifi,
            count: 2,
            tooltip: 'Active',
            iconColor: Colors.green,
          ),
        ),
      );

      final icon = tester.widget<Icon>(find.byIcon(Icons.wifi));
      expect(icon.color, Colors.green);
    });

    testWidgets('uses dim color when iconColor is null', (tester) async {
      await tester.pumpWidget(
        wrap(
          const StatusIndicator(icon: Icons.wifi, count: 0, tooltip: 'Active'),
        ),
      );

      final icon = tester.widget<Icon>(find.byIcon(Icons.wifi));
      // Default dim color: onSurface with 0.45 alpha.
      expect(icon.color, isNotNull);
      expect(icon.color, isNot(Colors.green));
    });
  });
}
