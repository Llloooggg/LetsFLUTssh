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
          currentTier: SecurityTier.keychainWithPassword,
        ),
        isTrue,
      );
    });

    test('keychainWithPassword card does NOT subsume plain keychain', () {
      // The off-diagonal match goes one direction only — the T1 card
      // owns both T1 + T1+password applied states.
      expect(
        tierCardIsCurrent(
          cardTier: SecurityTier.keychainWithPassword,
          currentTier: SecurityTier.keychain,
        ),
        isFalse,
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

    test('KeychainWithPassword always reports password = true', () {
      expect(
        currentConfigHasPassword(
          currentTier: SecurityTier.keychainWithPassword,
          currentModifiers: noMods,
        ),
        isTrue,
      );
    });

    test('plain Keychain / Hardware / Plaintext respect the modifier flag', () {
      for (final t in [
        SecurityTier.plaintext,
        SecurityTier.keychain,
        SecurityTier.hardware,
      ]) {
        expect(
          currentConfigHasPassword(currentTier: t, currentModifiers: noMods),
          isFalse,
          reason: '$t with no modifier',
        );
        expect(
          currentConfigHasPassword(
            currentTier: t,
            currentModifiers: passwordOn,
          ),
          isTrue,
          reason: '$t with password modifier',
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

    test('non-current T1 / T2 cards initialise password OFF', () {
      for (final t in [SecurityTier.keychain, SecurityTier.hardware]) {
        expect(
          derivePasswordModifierForCard(
            cardTier: t,
            currentTier: SecurityTier.plaintext,
            currentModifiers: noMods,
          ),
          isFalse,
          reason: '$t non-current default',
        );
      }
    });

    test('current card mirrors the applied modifier state', () {
      expect(
        derivePasswordModifierForCard(
          cardTier: SecurityTier.keychain,
          currentTier: SecurityTier.keychainWithPassword,
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
    test('only T1 / T2 expose the toggle', () {
      expect(tierCardPasswordToggleAvailable(SecurityTier.keychain), isTrue);
      expect(tierCardPasswordToggleAvailable(SecurityTier.hardware), isTrue);
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

    test('T1 / T2 with password modifier off never ask', () {
      for (final t in [SecurityTier.keychain, SecurityTier.hardware]) {
        expect(
          requiresShortPasswordInput(
            cardTier: t,
            passwordModifierEnabled: false,
            isCurrent: false,
            currentHasPassword: false,
          ),
          isFalse,
        );
      }
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
