/// Pure decision helpers for `_ExpandableTierCardState`. The card
/// renders the same modifier-row logic against three different
/// (this-tier, currently-applied-tier, applied-modifiers) tuples
/// (plain-keychain card vs current-keychain-with-password vs
/// current-hardware…) and the rules are easier to read + test as
/// standalone functions than as instance getters that pull from
/// `widget.*` and pending state.
library;

import '../../core/security/security_tier.dart';

/// True when the card represents the currently-applied tier. The
/// "T1 card subsumes T1+password" rule is the only off-diagonal
/// match: the password modifier renders as a pending toggle on the
/// same card.
bool tierCardIsCurrent({
  required SecurityTier cardTier,
  required SecurityTier currentTier,
}) {
  // Bank-style: both passwordless T1 and T1+password resolve to the
  // same `keychain` tier (the password rides `modifiers.password`),
  // so the direct comparison covers both against the keychain card.
  return cardTier == currentTier;
}

/// Whether the currently-applied tier + modifiers already carry a
/// user-typed password. Paranoid and Hardware always do (mandatory
/// by tier — Hardware is password-gated by contract); Keychain
/// flips on `currentModifiers.password` (the bank-style signal for
/// a password-gated keychain). Used by the card to decide whether
/// to render a fresh password input (the user is changing tier or
/// adding a password) or skip it (the user already has one and the
/// post-Apply biometric step prompts via the shared dialog).
bool currentConfigHasPassword({
  required SecurityTier currentTier,
  required SecurityTierModifiers currentModifiers,
}) {
  if (currentTier == SecurityTier.paranoid) return true;
  if (currentTier == SecurityTier.hardware) return true;
  return currentModifiers.password;
}

/// Initial value of the card's password-modifier toggle.
///
/// Non-current cards: Hardware and Paranoid always start with
/// password on (both tiers carry a mandatory password — the toggle
/// is locked on, but the value still has to be coherent);
/// Keychain starts with password off so the user can opt in.
///
/// The current card: mirror the applied modifier so the toggle
/// reflects reality on first paint.
bool derivePasswordModifierForCard({
  required SecurityTier cardTier,
  required SecurityTier currentTier,
  required SecurityTierModifiers currentModifiers,
}) {
  final isCurrent = tierCardIsCurrent(
    cardTier: cardTier,
    currentTier: currentTier,
  );
  if (!isCurrent) {
    return cardTier == SecurityTier.paranoid ||
        cardTier == SecurityTier.hardware;
  }
  return currentConfigHasPassword(
    currentTier: currentTier,
    currentModifiers: currentModifiers,
  );
}

/// True when the password-modifier toggle should be rendered at
/// all. Plaintext + Paranoid + Hardware never expose it as
/// flippable — Plaintext has no password to gate, Paranoid and
/// Hardware carry a mandatory password by tier. Keychain is the
/// only card where the user picks.
bool tierCardPasswordToggleAvailable(SecurityTier cardTier) =>
    cardTier == SecurityTier.keychain;

/// True when the card needs a fresh short password from the user.
/// Keychain + password asks, but only when the card is *not*
/// already the current applied tier with the password modifier on
/// — that case is biometric-toggle-only, and the password is
/// re-prompted through the post-Apply biometric dialog. Hardware
/// also asks (its password is mandatory), with the same "skip on
/// current" rule.
bool requiresShortPasswordInput({
  required SecurityTier cardTier,
  required bool passwordModifierEnabled,
  required bool isCurrent,
  required bool currentHasPassword,
}) {
  if (cardTier != SecurityTier.keychain && cardTier != SecurityTier.hardware) {
    return false;
  }
  if (cardTier == SecurityTier.keychain && !passwordModifierEnabled) {
    return false;
  }
  if (isCurrent && currentHasPassword) return false;
  return true;
}

/// True when the Paranoid card needs a fresh master password from
/// the user. Same "skip on current" rule as
/// [requiresShortPasswordInput] — the master password gets re-
/// prompted through the post-Apply biometric dialog when the user
/// is editing modifiers on the live tier.
bool requiresMasterPasswordInput({
  required SecurityTier cardTier,
  required bool isCurrent,
}) {
  if (cardTier != SecurityTier.paranoid) return false;
  if (isCurrent) return false;
  return true;
}
