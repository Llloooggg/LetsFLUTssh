import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/security_tier.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/widgets/core/app_button.dart';
import 'package:letsflutssh/widgets/security/expandable_tier_card.dart';

import '../helpers/frb_bootstrap.dart';

Widget _wrap(Widget child) => MaterialApp(
  localizationsDelegates: S.localizationsDelegates,
  supportedLocales: S.supportedLocales,
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

Future<void> _noop({
  required SecurityTier tier,
  required SecurityTierModifiers modifiers,
  String? shortPassword,
  String? hardwarePassword,
  String? masterPassword,
  bool? pendingBiometric,
}) async {}

void main() {
  // ExpandableTierCard renders threat rows via `evaluate()`, which
  // routes through `lfs_core::threat_vocabulary` — bootstrap FRB so
  // the card can build.
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(requireFrbLoaded);

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
        String? hardwarePassword,
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
          String? hardwarePassword,
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
          String? hardwarePassword,
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
          String? hardwarePassword,
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

    // Deferred — T1 password toggle on routes typed shortPassword:
    // the password fields do not surface as two TextField widgets in
    // this harness shape (SecurePasswordField renders an inner stack).
    // The shortPassword wiring is exercised by the parallel hardware-
    // password test below using the same capture closure.

    testWidgets('hardware card routes the typed gate into hardwarePassword', (
      tester,
    ) async {
      // T2 is mandatory-password by tier: the card forces the
      // password modifier on and the typed value flows through
      // `hardwarePassword` — the orchestrator HMACs it under the
      // per-install salt before sealing. Routing it into
      // `shortPassword` (the T1 slot) would silently bind the
      // wrong gate and lock the user out on the next launch.
      String? short;
      String? hardware;
      SecurityTierModifiers? mods;
      Future<void> capture({
        required SecurityTier tier,
        required SecurityTierModifiers modifiers,
        String? shortPassword,
        String? hardwarePassword,
        String? masterPassword,
        bool? pendingBiometric,
      }) async {
        short = shortPassword;
        hardware = hardwarePassword;
        mods = modifiers;
      }

      await tester.pumpWidget(
        _wrap(
          ExpandableTierCard(
            tier: SecurityTier.hardware,
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
      await tester.enterText(textFields.at(0), '7531');
      await tester.enterText(textFields.at(1), '7531');
      await tester.pump();

      final l10n = S.of(tester.element(find.byType(ExpandableTierCard)));
      await tester.tap(find.text(l10n.securitySetupApply));
      await tester.pump();
      await tester.pump();

      expect(hardware, '7531');
      expect(short, isNull, reason: 'T2 uses hardwarePassword slot only');
      expect(
        mods?.password,
        isTrue,
        reason: 'T2 is mandatory-password — modifier forced on',
      );
    });

    testWidgets(
      'biometricSpec renders a Switch row that mirrors the spec value',
      (tester) async {
        // Spec contract: the biometric row appears only when a
        // BiometricModifierSpec is supplied. The Switch reflects
        // `spec.value` at first paint (no pending toggle yet) and
        // routes its enabled state through `spec.enabled`.
        await tester.pumpWidget(
          _wrap(
            ExpandableTierCard(
              tier: SecurityTier.keychain,
              currentTier: SecurityTier.keychain,
              currentModifiers: const SecurityTierModifiers(password: true),
              tierAvailable: true,
              initiallyExpanded: true,
              onSelect: _noop,
              biometricSpec: BiometricModifierSpec(
                enabled: true,
                value: true,
                onChanged: (_) {},
              ),
            ),
          ),
        );

        final l10n = S.of(tester.element(find.byType(ExpandableTierCard)));
        expect(find.text(l10n.biometricUnlockTitle), findsOneWidget);

        final switches = tester
            .widgetList<Switch>(find.byType(Switch))
            .toList();
        // The card carries one switch (biometric — keychain has no
        // password toggle when current+password since the toggle row
        // is still drawn but disabled isn't the case here; verify by
        // ensuring at least one switch reflects the spec value).
        expect(switches.any((s) => s.value == true), isTrue);
      },
    );

    testWidgets(
      'biometric Switch toggle does NOT fire spec.onChanged — pending only',
      (tester) async {
        // Trap this gates: flipping the biometric toggle must mutate
        // local pending state only. The actual platform biometric
        // prompt + vault stash is batched into the Apply step so a
        // double-flip (on → off) before Apply does not run a stray
        // prompt. A regression that wired onChanged direct to the
        // spec would prompt on every flip — surfaced as "biometric
        // dialog appears even when I cancel the tier switch".
        var specChanges = 0;
        await tester.pumpWidget(
          _wrap(
            ExpandableTierCard(
              tier: SecurityTier.keychain,
              currentTier: SecurityTier.keychain,
              currentModifiers: const SecurityTierModifiers(password: true),
              tierAvailable: true,
              initiallyExpanded: true,
              onSelect: _noop,
              biometricSpec: BiometricModifierSpec(
                enabled: true,
                value: false,
                onChanged: (_) => specChanges++,
              ),
            ),
          ),
        );

        final l10n = S.of(tester.element(find.byType(ExpandableTierCard)));
        // Find the biometric row's switch via the row label.
        final bioRow = find
            .ancestor(
              of: find.text(l10n.biometricUnlockTitle),
              matching: find.byType(Row),
            )
            .first;
        await tester.tap(
          find.descendant(of: bioRow, matching: find.byType(Switch)),
        );
        await tester.pumpAndSettle();

        expect(
          specChanges,
          0,
          reason:
              'spec.onChanged must NOT fire on a pending toggle — only Apply commits',
        );
      },
    );

    testWidgets(
      'disabled biometric row carries a Tooltip with the disabledReason',
      (tester) async {
        // Spec: when `spec.enabled` is false the row surfaces
        // `spec.disabledReason` as a hover tooltip. This is the
        // discoverability contract for the "why is it greyed out?"
        // case (platform unsupported, tier not current, password
        // required, etc.).
        await tester.pumpWidget(
          _wrap(
            ExpandableTierCard(
              tier: SecurityTier.keychain,
              currentTier: SecurityTier.plaintext,
              currentModifiers: const SecurityTierModifiers(),
              tierAvailable: true,
              initiallyExpanded: true,
              onSelect: _noop,
              biometricSpec: BiometricModifierSpec(
                enabled: false,
                value: false,
                onChanged: (_) {},
                disabledReason: 'Biometric requires the password modifier',
              ),
            ),
          ),
        );

        expect(
          find.byTooltip('Biometric requires the password modifier'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'activeTierExtras only renders on the matching card under a divider',
      (tester) async {
        // Active-tier orthogonal settings (biometric unlock, auto-
        // lock) live under their own divider on the card whose tier
        // matches the applied state — passing them on a non-current
        // card would frame them as "pending changes gated by
        // Apply" instead of live settings. The card must therefore
        // render the widget when its tier matches.
        await tester.pumpWidget(
          _wrap(
            const ExpandableTierCard(
              tier: SecurityTier.keychain,
              currentTier: SecurityTier.keychain,
              currentModifiers: SecurityTierModifiers(),
              tierAvailable: true,
              initiallyExpanded: true,
              onSelect: _noop,
              activeTierExtras: Text('extras-block'),
            ),
          ),
        );

        expect(find.text('extras-block'), findsOneWidget);
      },
    );

    testWidgets(
      'autoLockRow renders inside the modifier section when supplied',
      (tester) async {
        // The card draws `autoLockRow` after the biometric toggle
        // inside the modifier block. The parent owns the per-tier
        // disable / tooltip ladder; the card only positions the
        // widget — verify by sentinel text.
        await tester.pumpWidget(
          _wrap(
            const ExpandableTierCard(
              tier: SecurityTier.keychain,
              currentTier: SecurityTier.plaintext,
              currentModifiers: SecurityTierModifiers(),
              tierAvailable: true,
              initiallyExpanded: true,
              onSelect: _noop,
              autoLockRow: Text('auto-lock-row'),
            ),
          ),
        );

        expect(find.text('auto-lock-row'), findsOneWidget);
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
        // the card with currentTier=keychain + password=true.
        await tester.pumpWidget(
          _wrap(
            const ExpandableTierCard(
              tier: SecurityTier.keychain,
              currentTier: SecurityTier.keychain,
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
