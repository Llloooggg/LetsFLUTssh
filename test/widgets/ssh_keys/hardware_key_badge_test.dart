/// Widget tests for [HardwareKeyBadge] — the hardware-bound key pill on
/// SSH key rows. A badge with no [HardwareKeyBadgeInfo] is a static pill;
/// one with info is tappable and reveals the captured metadata.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/widgets/ssh_keys/hardware_key_badge.dart';

void main() {
  Future<void> pump(WidgetTester tester, HardwareKeyBadge badge) {
    return tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: S.localizationsDelegates,
        supportedLocales: S.supportedLocales,
        home: Scaffold(body: Center(child: badge)),
      ),
    );
  }

  testWidgets('a badge without info is a static pill (no tooltip)', (
    tester,
  ) async {
    await pump(tester, const HardwareKeyBadge(label: 'sk-ed25519'));
    expect(find.text('sk-ed25519'), findsOneWidget);
    expect(find.byType(Tooltip), findsNothing);
  });

  testWidgets('a badge with info is tappable and reveals its lines', (
    tester,
  ) async {
    await pump(
      tester,
      const HardwareKeyBadge(
        label: 'TPM',
        icon: Icons.memory,
        info: HardwareKeyBadgeInfo(
          title: 'TPM-backed key',
          lines: [
            HardwareKeyInfoLine('Device-bound — cannot be exported.'),
            HardwareKeyInfoLine.warn('Lost device = lost key.'),
            HardwareKeyInfoLine.mono('0x81000001'),
          ],
        ),
      ),
    );
    // Tappable affordance present.
    expect(find.byType(Tooltip), findsOneWidget);
    // The popover is not open until tapped.
    expect(find.text('TPM-backed key'), findsNothing);

    await tester.tap(find.byType(HardwareKeyBadge));
    await tester.pumpAndSettle();

    expect(find.text('TPM-backed key'), findsOneWidget);
    expect(find.text('Device-bound — cannot be exported.'), findsOneWidget);
    expect(find.text('Lost device = lost key.'), findsOneWidget);
    expect(find.text('0x81000001'), findsOneWidget);
  });
}
