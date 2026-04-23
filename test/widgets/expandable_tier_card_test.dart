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
  bool? pendingBiometric,
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
        bool? pendingBiometric,
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

    testWidgets(
      'paranoid card captures the typed master password when both fields match',
      (tester) async {
        // Paranoid is always the "master password" path. Select must
        // pass the typed secret through [masterPassword]; the other
        // slots stay null. A refactor that routed the typed value into
        // the wrong field would silently store an unrecoverable DB
        // key. This test guards that exact flow.
        String? captured;
        SecurityTier? capturedTier;
        Future<void> capture({
          required SecurityTier tier,
          required SecurityTierModifiers modifiers,
          String? shortPassword,
          String? pin,
          String? masterPassword,
          bool? pendingBiometric,
        }) async {
          capturedTier = tier;
          captured = masterPassword;
        }

        await tester.pumpWidget(
          _wrap(
            ExpandableTierCard(
              tier: SecurityTier.paranoid,
              currentTier: SecurityTier.plaintext,
              currentModifiers: const SecurityTierModifiers(),
              tierAvailable: true,
              initiallyExpanded: true,
              onSelect: capture,
            ),
          ),
        );

        final textFields = find.byType(TextField);
        expect(textFields, findsNWidgets(2));
        await tester.enterText(textFields.at(0), 'correct horse battery');
        await tester.enterText(textFields.at(1), 'correct horse battery');
        await tester.pump();

        final l10n = S.of(tester.element(find.byType(ExpandableTierCard)));
        await tester.tap(find.text(l10n.securitySetupApply));
        await tester.pump();
        await tester.pump();
        expect(capturedTier, SecurityTier.paranoid);
        expect(captured, 'correct horse battery');
      },
    );

    testWidgets(
      'paranoid card with mismatched confirmation keeps Apply disabled',
      (tester) async {
        // `_inputsReady` gate — the Select callback must NOT fire
        // until primary + confirm agree. Prevents the "typed the
        // password twice differently" foot-gun.
        var calls = 0;
        Future<void> capture({
          required SecurityTier tier,
          required SecurityTierModifiers modifiers,
          String? shortPassword,
          String? pin,
          String? masterPassword,
          bool? pendingBiometric,
        }) async {
          calls++;
        }

        await tester.pumpWidget(
          _wrap(
            ExpandableTierCard(
              tier: SecurityTier.paranoid,
              currentTier: SecurityTier.plaintext,
              currentModifiers: const SecurityTierModifiers(),
              tierAvailable: true,
              initiallyExpanded: true,
              onSelect: capture,
            ),
          ),
        );

        final textFields = find.byType(TextField);
        await tester.enterText(textFields.at(0), 'left-hand');
        await tester.enterText(textFields.at(1), 'right-hand');
        await tester.pump();

        final l10n = S.of(tester.element(find.byType(ExpandableTierCard)));
        await tester.tap(find.text(l10n.securitySetupApply));
        await tester.pump();
        expect(calls, 0);
      },
    );

    testWidgets(
      'T1 card with password toggle off selects the plain keychain tier',
      (tester) async {
        SecurityTier? capturedTier;
        String? capturedShort;
        Future<void> capture({
          required SecurityTier tier,
          required SecurityTierModifiers modifiers,
          String? shortPassword,
          String? pin,
          String? masterPassword,
          bool? pendingBiometric,
        }) async {
          capturedTier = tier;
          capturedShort = shortPassword;
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
        expect(
          capturedShort,
          isNull,
          reason: 'password modifier off → shortPassword stays null',
        );
      },
    );

    testWidgets(
      'currentTier that matches the card locks Apply to "Current" badge',
      (tester) async {
        // Already-applied config must disable Select so the user does
        // not accidentally re-run a no-op tier switch. The Apply
        // button is still present (shared visual) but its onTap is
        // null — the Current badge is the active affordance.
        await tester.pumpWidget(
          _wrap(
            const ExpandableTierCard(
              tier: SecurityTier.plaintext,
              currentTier: SecurityTier.plaintext,
              currentModifiers: SecurityTierModifiers(),
              tierAvailable: true,
              initiallyExpanded: true,
              onSelect: _noop,
            ),
          ),
        );
        final button = tester.widget<AppButton>(
          find.byWidgetPredicate((w) => w is AppButton),
        );
        expect(button.onTap, isNull);
      },
    );

    testWidgets(
      'parent-pushed applied-state change resets pending password + re-locks Apply',
      (tester) async {
        // Regression gate for the "Apply stays active after nothing
        // changed" bug: after `onSelectTier` finishes and the parent
        // rebuilds with a fresh `currentTier` + `currentModifiers`,
        // the card must reseat `_passwordEnabled` + wipe the pending
        // password text so `_matchesCurrentConfig` reports match and
        // Apply clamps back to null. Without the reset the
        // pre-apply pending state lingers and Apply stays tappable
        // even though the displayed config is identical to what was
        // just applied.
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
        AppButton button() => tester.widget<AppButton>(
          find.byWidgetPredicate((w) => w is AppButton),
        );
        expect(
          button().onTap,
          isNull,
          reason: 'Initial match on current T1 must leave Apply disabled',
        );

        // Simulate user applying password on → parent rebuild lands
        // the card with currentTier=keychainWithPassword + password=true.
        await tester.pumpWidget(
          _wrap(
            const ExpandableTierCard(
              tier: SecurityTier.keychain,
              currentTier: SecurityTier.keychainWithPassword,
              currentModifiers: SecurityTierModifiers(password: true),
              tierAvailable: true,
              initiallyExpanded: true,
              onSelect: _noop,
            ),
          ),
        );
        await tester.pump();
        expect(
          button().onTap,
          isNull,
          reason: 'After applied-state change the card must re-match + lock',
        );
      },
    );
  });
}
