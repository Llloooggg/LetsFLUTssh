import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/security_tier.dart';
import 'package:letsflutssh/widgets/expandable_tier_card_logic.dart';

void main() {
  const noMods = SecurityTierModifiers();
  const passwordOn = SecurityTierModifiers(password: true);

  group('tierCardIsCurrent', () {
    test('exact match → true', () {
      for (final t in SecurityTier.values) {
        expect(
          tierCardIsCurrent(cardTier: t, currentTier: t),
          isTrue,
          reason: '$t == $t',
        );
      }
    });

    test('keychain card subsumes keychainWithPassword applied', () {
      expect(
        tierCardIsCurrent(
          cardTier: SecurityTier.keychain,
          currentTier: SecurityTier.keychain,
        ),
        isTrue,
      );
    });

    test('keychain card matches the keychain tier regardless of modifier', () {
      // Bank-style v3: L1+password is `keychain` + `modifiers
      // .password = true` (no dedicated tier value). The keychain
      // card matches both the passwordless and the with-password
      // applied state — the modifier is rendered as a separate
      // toggle inside the same card.
      expect(
        tierCardIsCurrent(
          cardTier: SecurityTier.keychain,
          currentTier: SecurityTier.keychain,
        ),
        isTrue,
      );
    });

    test('unrelated tier pairs → false', () {
      expect(
        tierCardIsCurrent(
          cardTier: SecurityTier.hardware,
          currentTier: SecurityTier.plaintext,
        ),
        isFalse,
      );
      expect(
        tierCardIsCurrent(
          cardTier: SecurityTier.paranoid,
          currentTier: SecurityTier.keychain,
        ),
        isFalse,
      );
    });
  });

  group('currentConfigHasPassword', () {
    test('Paranoid always reports password = true', () {
      expect(
        currentConfigHasPassword(
          currentTier: SecurityTier.paranoid,
          currentModifiers: noMods,
        ),
        isTrue,
      );
    });

    test('keychain reports password only when the modifier flag is on', () {
      // Bank-style v3: the L1+password case folded into keychain
      // + `modifiers.password = true`; no tier-only signal exists
      // for it. Without the modifier the predicate stays false
      // even on the keychain tier.
      expect(
        currentConfigHasPassword(
          currentTier: SecurityTier.keychain,
          currentModifiers: noMods,
        ),
        isFalse,
      );
      expect(
        currentConfigHasPassword(
          currentTier: SecurityTier.keychain,
          currentModifiers: passwordOn,
        ),
        isTrue,
      );
    });

    test('plain Keychain / Plaintext respect the modifier flag', () {
      // Hardware is mandatory-password by tier — its dedicated
      // case sits above this test. Keychain and Plaintext are the
      // only tiers whose password state depends on the modifier
      // (Keychain) or is always false (Plaintext).
      for (final t in [SecurityTier.plaintext, SecurityTier.keychain]) {
        expect(
          currentConfigHasPassword(currentTier: t, currentModifiers: noMods),
          isFalse,
          reason: '$t with no modifier',
        );
      }
      expect(
        currentConfigHasPassword(
          currentTier: SecurityTier.keychain,
          currentModifiers: passwordOn,
        ),
        isTrue,
        reason: 'keychain + password modifier on',
      );
    });

    test('Hardware always reports password = true', () {
      // T2 is always password-gated by tier; the modifier flag is
      // pinned on by the wizard / Settings card. The predicate
      // returns true regardless of the modifier bag passed in to
      // keep callers consistent if a stale `password=false` slips
      // through (the v6→v7 migration also stamps the modifier on
      // for pre-flip Hardware configs).
      for (final mods in [noMods, passwordOn]) {
        expect(
          currentConfigHasPassword(
            currentTier: SecurityTier.hardware,
            currentModifiers: mods,
          ),
          isTrue,
          reason: 'hardware tier is mandatory-password',
        );
      }
    });
  });

  group('derivePasswordModifierForCard', () {
    test('non-current Paranoid card initialises password ON', () {
      expect(
        derivePasswordModifierForCard(
          cardTier: SecurityTier.paranoid,
          currentTier: SecurityTier.keychain,
          currentModifiers: noMods,
        ),
        isTrue,
      );
    });

    test('non-current Keychain card initialises password OFF', () {
      expect(
        derivePasswordModifierForCard(
          cardTier: SecurityTier.keychain,
          currentTier: SecurityTier.plaintext,
          currentModifiers: noMods,
        ),
        isFalse,
        reason: 'keychain non-current default',
      );
    });

    test('non-current Hardware card initialises password ON', () {
      // T2 is mandatory-password by tier; the card forces the
      // modifier on so the password input + secret-form panel
      // render correctly even on a non-current card.
      expect(
        derivePasswordModifierForCard(
          cardTier: SecurityTier.hardware,
          currentTier: SecurityTier.plaintext,
          currentModifiers: noMods,
        ),
        isTrue,
      );
    });

    test('current card mirrors the applied modifier state', () {
      expect(
        derivePasswordModifierForCard(
          cardTier: SecurityTier.keychain,
          currentTier: SecurityTier.keychain,
          currentModifiers: passwordOn,
        ),
        isTrue,
      );
      expect(
        derivePasswordModifierForCard(
          cardTier: SecurityTier.keychain,
          currentTier: SecurityTier.keychain,
          currentModifiers: noMods,
        ),
        isFalse,
      );
    });
  });

  group('tierCardPasswordToggleAvailable', () {
    test('only Keychain exposes the toggle', () {
      // Plaintext has no password to gate; Hardware and Paranoid
      // are mandatory-password by tier — their cards render the
      // password modifier as locked-on without a flippable
      // toggle.
      expect(tierCardPasswordToggleAvailable(SecurityTier.keychain), isTrue);
      expect(tierCardPasswordToggleAvailable(SecurityTier.hardware), isFalse);
      expect(tierCardPasswordToggleAvailable(SecurityTier.plaintext), isFalse);
      expect(tierCardPasswordToggleAvailable(SecurityTier.paranoid), isFalse);
    });
  });

  group('requiresShortPasswordInput', () {
    test('non-T1/T2 tiers never ask for a short password', () {
      for (final t in [SecurityTier.plaintext, SecurityTier.paranoid]) {
        expect(
          requiresShortPasswordInput(
            cardTier: t,
            passwordModifierEnabled: true,
            isCurrent: false,
            currentHasPassword: false,
          ),
          isFalse,
          reason: '$t never asks',
        );
      }
    });

    test('Keychain with password modifier off never asks', () {
      // Hardware no longer takes the modifier flag — the tier
      // itself is mandatory-password, so the card always asks
      // (subject to the same "skip on current" rule).
      expect(
        requiresShortPasswordInput(
          cardTier: SecurityTier.keychain,
          passwordModifierEnabled: false,
          isCurrent: false,
          currentHasPassword: false,
        ),
        isFalse,
      );
    });

    test('non-current Hardware card asks regardless of the modifier flag', () {
      // The modifier flag is force-pinned on for Hardware, but
      // the helper still has to hold even if a stale caller
      // passes `passwordModifierEnabled=false`.
      for (final flag in [true, false]) {
        expect(
          requiresShortPasswordInput(
            cardTier: SecurityTier.hardware,
            passwordModifierEnabled: flag,
            isCurrent: false,
            currentHasPassword: false,
          ),
          isTrue,
          reason: 'non-current Hardware always asks',
        );
      }
    });

    test('current Hardware card hides the input (avoid double-prompt)', () {
      expect(
        requiresShortPasswordInput(
          cardTier: SecurityTier.hardware,
          passwordModifierEnabled: true,
          isCurrent: true,
          currentHasPassword: true,
        ),
        isFalse,
      );
    });

    test('current T1+password card hides the input (avoid double-prompt)', () {
      expect(
        requiresShortPasswordInput(
          cardTier: SecurityTier.keychain,
          passwordModifierEnabled: true,
          isCurrent: true,
          currentHasPassword: true,
        ),
        isFalse,
      );
    });

    test('non-current T1 + password modifier on → ask', () {
      expect(
        requiresShortPasswordInput(
          cardTier: SecurityTier.keychain,
          passwordModifierEnabled: true,
          isCurrent: false,
          currentHasPassword: false,
        ),
        isTrue,
      );
    });

    test('current T1 turning password ON → ask (currentHasPassword=false)', () {
      expect(
        requiresShortPasswordInput(
          cardTier: SecurityTier.keychain,
          passwordModifierEnabled: true,
          isCurrent: true,
          currentHasPassword: false,
        ),
        isTrue,
      );
    });
  });

  group('requiresMasterPasswordInput', () {
    test('only Paranoid card ever asks', () {
      for (final t in SecurityTier.values) {
        if (t == SecurityTier.paranoid) continue;
        expect(
          requiresMasterPasswordInput(cardTier: t, isCurrent: false),
          isFalse,
          reason: '$t never asks',
        );
      }
    });

    test('Paranoid card asks when not the current tier', () {
      expect(
        requiresMasterPasswordInput(
          cardTier: SecurityTier.paranoid,
          isCurrent: false,
        ),
        isTrue,
      );
    });

    test(
      'Paranoid card hides the master password when already on Paranoid',
      () {
        expect(
          requiresMasterPasswordInput(
            cardTier: SecurityTier.paranoid,
            isCurrent: true,
          ),
          isFalse,
        );
      },
    );
  });
}
