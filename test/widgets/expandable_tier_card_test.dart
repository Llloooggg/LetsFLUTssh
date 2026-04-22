import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/security_tier.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/widgets/app_button.dart';
import 'package:letsflutssh/widgets/expandable_tier_card.dart';

Widget _wrap(Widget child) => MaterialApp(
  localizationsDelegates: S.localizationsDelegates,
  supportedLocales: S.supportedLocales,
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

Future<void> _noop({
  required SecurityTier tier,
  required SecurityTierModifiers modifiers,
  String? shortPassword,
  String? pin,
  String? masterPassword,
}) async {}

void main() {
  group('ExpandableTierCard', () {
    testWidgets('expands and collapses on header tap', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const ExpandableTierCard(
            tier: SecurityTier.keychain,
            currentTier: SecurityTier.plaintext,
            currentModifiers: SecurityTierModifiers(),
            tierAvailable: true,
            onSelect: _noop,
          ),
        ),
      );
      final l10n = S.of(tester.element(find.byType(ExpandableTierCard)));
      expect(find.text(l10n.securitySetupApply), findsNothing);

      await tester.tap(find.text(l10n.tierKeychainLabel));
      await tester.pump();
      expect(find.text(l10n.securitySetupApply), findsOneWidget);

      await tester.tap(find.text(l10n.tierKeychainLabel));
      await tester.pump();
      expect(find.text(l10n.securitySetupApply), findsNothing);
    });

    testWidgets('initiallyExpanded renders expanded from the start', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const ExpandableTierCard(
            tier: SecurityTier.keychain,
            currentTier: SecurityTier.plaintext,
            currentModifiers: SecurityTierModifiers(),
            tierAvailable: true,
            initiallyExpanded: true,
            onSelect: _noop,
          ),
        ),
      );
      final l10n = S.of(tester.element(find.byType(ExpandableTierCard)));
      expect(find.text(l10n.securitySetupApply), findsOneWidget);
    });

    testWidgets('current tier shows the Current badge', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const ExpandableTierCard(
            tier: SecurityTier.keychain,
            currentTier: SecurityTier.keychain,
            currentModifiers: SecurityTierModifiers(),
            tierAvailable: true,
            initiallyExpanded: true,
            onSelect: _noop,
          ),
        ),
      );
      final l10n = S.of(tester.element(find.byType(ExpandableTierCard)));
      expect(find.text(l10n.tierBadgeCurrent), findsOneWidget);
    });

    testWidgets('unavailable tier renders the reason and disables Apply', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const ExpandableTierCard(
            tier: SecurityTier.hardware,
            currentTier: SecurityTier.plaintext,
            currentModifiers: SecurityTierModifiers(),
            tierAvailable: false,
            unavailableReason: 'No TPM detected',
            initiallyExpanded: true,
            onSelect: _noop,
          ),
        ),
      );
      final l10n = S.of(tester.element(find.byType(ExpandableTierCard)));
      expect(find.text('No TPM detected'), findsOneWidget);

      // Apply button migrated to `AppButton.primary` — predicate
      // match covers the private subclass, `onTap` replaces
      // `onPressed`.
      final button = tester.widget<AppButton>(
        find.byWidgetPredicate((w) => w is AppButton),
      );
      expect(button.onTap, isNull, reason: 'Apply must be disabled');
      expect(find.text(l10n.securitySetupApply), findsOneWidget);
    });

    testWidgets('T0 card has no password toggle or password input', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const ExpandableTierCard(
            tier: SecurityTier.plaintext,
            currentTier: SecurityTier.keychain,
            currentModifiers: SecurityTierModifiers(),
            tierAvailable: true,
            initiallyExpanded: true,
            onSelect: _noop,
          ),
        ),
      );
      final l10n = S.of(tester.element(find.byType(ExpandableTierCard)));
      expect(find.text(l10n.modifierPasswordLabel), findsNothing);
    });

    testWidgets('onSelect fires with the resolved tier + modifiers', (
      tester,
    ) async {
      SecurityTier? capturedTier;
      SecurityTierModifiers? capturedMods;
      Future<void> capture({
        required SecurityTier tier,
        required SecurityTierModifiers modifiers,
        String? shortPassword,
        String? pin,
        String? masterPassword,
      }) async {
        capturedTier = tier;
        capturedMods = modifiers;
      }

      await tester.pumpWidget(
        _wrap(
          ExpandableTierCard(
            tier: SecurityTier.keychain,
            currentTier: SecurityTier.plaintext,
            currentModifiers: const SecurityTierModifiers(),
            tierAvailable: true,
            initiallyExpanded: true,
            onSelect: capture,
          ),
        ),
      );
      final l10n = S.of(tester.element(find.byType(ExpandableTierCard)));
      await tester.tap(find.text(l10n.securitySetupApply));
      await tester.pump();
      await tester.pump();
      expect(capturedTier, SecurityTier.keychain);
      expect(capturedMods?.password, isFalse);
    });
  });
}
