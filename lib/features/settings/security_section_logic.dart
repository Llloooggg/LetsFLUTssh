/// Pure decision helpers extracted from `_SecuritySectionState`. The
/// section's biometric / auto-lock priority ladders are wide
/// (platform reason → tier-not-current → tier-unavailable →
/// password-missing → ready) and need to be exercised against every
/// combination of tier × modifier × probe state. Keeping the rules in
/// a stateful widget made every test a `pumpWidget` round-trip; this
/// module returns them as `String?` / `BiometricModifierSpec?` so the
/// callers stay one-liners and unit tests cover each branch directly.
library;

import 'dart:convert';

import '../../core/security/biometric_auth.dart';
import '../../core/security/security_tier.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/expandable_tier_card.dart';

/// Localised tooltip explaining why biometric is unreachable on this
/// platform, or `null` when the device is biometric-capable. `probed`
/// gates the read so the very first paint (before the async
/// `BiometricAuth.availability()` round-trip resolves) does not
/// surface a "no sensor" message that may be wrong on hardware that
/// just hasn't probed yet.
String? biometricPlatformReason({
  required S l10n,
  required BiometricAvailability availability,
  required bool probed,
}) {
  if (!probed) return null;
  switch (availability) {
    case BiometricUnavailableReason.platformUnsupported:
    case BiometricUnavailableReason.noSensor:
      return l10n.biometricSensorNotAvailable;
    case BiometricUnavailableReason.notEnrolled:
      return l10n.biometricNotEnrolled;
    case BiometricUnavailableReason.systemServiceMissing:
      return l10n.biometricSystemServiceMissing;
    case null:
      return null;
  }
}

/// Reason auto-lock cannot engage on the supplied tier + modifiers,
/// or `null` when the dropdown is fully usable. Auto-lock erases the
/// cached DB wrapping key after N minutes of idle and forces a
/// re-unlock; that re-unlock needs a user-typed secret, so a tier
/// without a password modifier (or without an inherent password like
/// Paranoid / KeychainWithPassword) has nothing to re-unlock against.
String? autoLockDisabledReason({
  required S l10n,
  required SecurityTier level,
  required SecurityTierModifiers modifiers,
}) {
  final hasPassword =
      level == SecurityTier.paranoid ||
      level == SecurityTier.keychainWithPassword ||
      modifiers.password;
  if (hasPassword) return null;
  return l10n.autoLockRequiresPassword;
}

/// Build the `BiometricModifierSpec` for the tier card identified by
/// [tier]. Returns `null` when biometric is not exposed on the tier
/// (Plaintext / Paranoid). The four-priority ladder mirrors the doc
/// comment on the original method:
///
/// 1. Biometric platform unavailable — never let a "select tier
///    first" tooltip mask the fact that the device cannot do
///    biometric at all.
/// 2. Tier available but not the current applied tier → "select this
///    tier first".
/// 3. Tier itself unavailable → reuse the yellow-pill reason from the
///    tier card so the section stays internally coherent.
/// 4. Tier ready, modifier missing a password → "biometric requires
///    password".
/// Otherwise the toggle is enabled with `value = biometricEnabled`.
BiometricModifierSpec? biometricSpecFor({
  required S l10n,
  required SecurityTier tier,
  required SecurityTier currentLevel,
  required SecurityTierModifiers currentModifiers,
  required bool tierAvailable,
  required String? tierUnavailableReason,
  required BiometricAvailability availability,
  required bool probed,
  required bool biometricEnabled,
}) {
  if (tier != SecurityTier.keychain && tier != SecurityTier.hardware) {
    return null;
  }
  final isCurrent =
      tier == currentLevel ||
      (tier == SecurityTier.keychain &&
          currentLevel == SecurityTier.keychainWithPassword);

  final platformReason = biometricPlatformReason(
    l10n: l10n,
    availability: availability,
    probed: probed,
  );
  if (platformReason != null) {
    return BiometricModifierSpec(
      enabled: false,
      value: biometricEnabled,
      onChanged: (_) {},
      disabledReason: platformReason,
    );
  }

  if (tierAvailable && !isCurrent) {
    return BiometricModifierSpec(
      enabled: false,
      value: biometricEnabled,
      onChanged: (_) {},
      disabledReason: l10n.biometricRequiresActiveTier,
    );
  }

  if (!tierAvailable) {
    return BiometricModifierSpec(
      enabled: false,
      value: biometricEnabled,
      onChanged: (_) {},
      disabledReason: tierUnavailableReason,
    );
  }

  final hasPassword =
      currentLevel == SecurityTier.paranoid ||
      currentLevel == SecurityTier.keychainWithPassword ||
      currentModifiers.password;
  if (!hasPassword) {
    return BiometricModifierSpec(
      enabled: false,
      value: biometricEnabled,
      onChanged: (_) {},
      disabledReason: l10n.biometricRequiresPassword,
    );
  }

  return BiometricModifierSpec(
    enabled: probed,
    value: biometricEnabled,
    onChanged: (_) {},
    disabledReason: null,
  );
}

/// True when the [current] → [next] transition drops a *verifiable*
/// password — meaning the tier change wants the user to re-enter the
/// existing password before we discard it. Verifiable means the
/// previous tier carries a password that can be cryptographically
/// checked: KeychainWithPassword (gate verifier file) and Paranoid
/// (KDF-derived key against the master verifier). Plaintext / plain
/// Keychain / Hardware do not — the gate-down transition for those
/// has nothing to verify against, so the helper returns false and
/// the apply pipeline skips the prompt.
///
/// Same-tier transitions (T2-with-pw → T2-with-pw, Paranoid →
/// Paranoid) return false too: the user is reconfiguring modifiers,
/// not dropping the password, so the prompt would be redundant.
bool isVerifiablePasswordDrop(SecurityTier current, SecurityTier next) {
  if (current == SecurityTier.keychainWithPassword &&
      next != SecurityTier.keychainWithPassword) {
    return true;
  }
  if (current == SecurityTier.paranoid && next != SecurityTier.paranoid) {
    return true;
  }
  return false;
}

/// Branch the `_SecuritySectionState.onSelectTier` dispatcher needs to
/// take for a given Apply-button payload, distilled away from the
/// stateful widget so the decision can be unit-tested in isolation.
///
/// * [biometricOnly] — same tier, same `password` modifier, the only
///   pending change is the biometric toggle. The full rekey pipeline
///   would re-prompt for the password and re-derive the DB key for
///   nothing — this branch routes through the cheap biometric vault
///   rewrite alone.
/// * [fullRekey] — anything else: tier is changing, password modifier
///   is flipping, or biometric is `null` (Apply on the same tier with
///   no biometric pending — usually a metadata-only reconfirm). The
///   apply pipeline runs end-to-end including the always-rekey step.
enum TierTransitionKind { biometricOnly, fullRekey }

/// Classify the Apply-button payload into one of [TierTransitionKind]
/// outcomes. `pendingBiometric == null` means the card did not include
/// a biometric flip — even when tier + password match the current
/// state, no biometric-only fast path applies.
TierTransitionKind classifyTierTransition({
  required SecurityTier currentLevel,
  required SecurityTierModifiers currentModifiers,
  required SecurityTier targetTier,
  required SecurityTierModifiers targetModifiers,
  required bool? pendingBiometric,
}) {
  final biometricOnly =
      targetTier == currentLevel &&
      targetModifiers.password == currentModifiers.password &&
      pendingBiometric != null;
  return biometricOnly
      ? TierTransitionKind.biometricOnly
      : TierTransitionKind.fullRekey;
}

/// Snake-case marker for [tier] used in logs / telemetry. Stays
/// stable across renames so log greps survive UI label changes;
/// matches the same-named function in `lfs_core::security` so
/// Dart-side and Rust-side log entries share one vocabulary.
String securityTierLogName(SecurityTier tier) {
  switch (tier) {
    case SecurityTier.plaintext:
      return 'plaintext';
    case SecurityTier.keychain:
      return 'keychain';
    case SecurityTier.keychainWithPassword:
      return 'keychain_with_password';
    case SecurityTier.hardware:
      return 'hardware';
    case SecurityTier.paranoid:
      return 'paranoid';
  }
}

/// Where the biometric-enable flow should source the DB key it caches
/// in the biometric-gated vault. Driven by [biometricKeySourceFor],
/// which the `_BiometricFlow._captureKeyForBiometricEnable` extension
/// dispatches on.
///
/// * [pullFromAppliedTier] — the Apply just rekeyed the database
///   under the freshly-derived key (tier change, or same-tier with
///   no verifiable password to re-prompt against). Read it back from
///   `securityStateProvider.encryptionKey` after `_applyTierChange`
///   resolves.
/// * [promptAndVerifyKeychainGate] — same-tier biometric flip on
///   T1+pw. The gate verifier is the only way to revalidate the
///   user's password without a tier rekey, so prompt + verify, then
///   read the stored key out of the keychain.
/// * [promptAndVerifyMasterPassword] — same-tier biometric flip on
///   Paranoid. Master-password manager owns both the verifier file
///   and the KDF; verifyAndDerive returns the key directly.
enum BiometricKeySource {
  pullFromAppliedTier,
  promptAndVerifyKeychainGate,
  promptAndVerifyMasterPassword,
}

/// Decide which path the biometric-enable flow takes given the
/// current and target tier. Cross-tier transitions never need to
/// re-prompt — the new tier's password is fresh from the card and
/// drives the rekey. Same-tier flips only need a re-prompt when the
/// tier carries a verifiable password (T1+pw, Paranoid); other
/// same-tier flips (T1 without password, T2, plaintext) have no
/// verifiable secret to gate against, so they fall back to reading
/// the post-apply DB key.
BiometricKeySource biometricKeySourceFor({
  required SecurityTier currentTier,
  required SecurityTier nextTier,
}) {
  if (currentTier != nextTier) return BiometricKeySource.pullFromAppliedTier;
  if (currentTier == SecurityTier.keychainWithPassword) {
    return BiometricKeySource.promptAndVerifyKeychainGate;
  }
  if (currentTier == SecurityTier.paranoid) {
    return BiometricKeySource.promptAndVerifyMasterPassword;
  }
  return BiometricKeySource.pullFromAppliedTier;
}

/// What every tier-apply method writes into the marker file before
/// kicking off `SecurityTierSwitcher.switchTier`. Bundles the snake-
/// case tier name + modifier JSON so a crash-recovery path can
/// reconstruct the target config and drive the right unlock prompt
/// (password? biometric? no gate?) at next launch.
///
/// Pure JSON — no rekey side-effects, no provider reads — so the
/// payload shape can be unit-tested directly against the Rust-side
/// recovery path's parser.
String buildTierMarkerPayload(
  SecurityTier tier,
  SecurityTierModifiers modifiers,
) {
  return jsonEncode({
    'tier': securityTierLogName(tier),
    'mods': modifiers.toJson(),
  });
}

/// Decision matrix for which tier vaults the apply pipeline must
/// clear after rekeying onto [target]. Each apply method first
/// commits the new key to the target tier's own vault (keychain
/// blob, keychain-with-password gate, hardware seal, master-password
/// verifier), then wipes everything else so a stale wrapper from a
/// previous tier cannot resurrect under a different unlock path.
///
/// The `false` slot per row corresponds to the vault the apply
/// method **just wrote into** — wiping it would race with the
/// commit that just landed. Every other vault returns `true`.
class TierVaultClearPlan {
  /// True → `secureKeyStorageProvider.deleteKey()` runs.
  final bool clearKeychainKey;

  /// True → `keychainPasswordGateProvider.clear()` runs.
  final bool clearKeychainGate;

  /// True → `hardwareTierVaultProvider.clear()` runs.
  final bool clearHardwareVault;

  /// True → `masterPasswordProvider.disable()` runs (gated on
  /// `isEnabled()` since `disable()` on an already-disabled manager
  /// is a no-op but the call still does an FRB round-trip).
  final bool clearMasterPassword;

  /// True → `biometricKeyVaultProvider.clear()` runs.
  final bool clearBiometricVault;

  const TierVaultClearPlan({
    required this.clearKeychainKey,
    required this.clearKeychainGate,
    required this.clearHardwareVault,
    required this.clearMasterPassword,
    required this.clearBiometricVault,
  });
}

/// The clear plan for a tier-apply targeting [target]. Mirrors the
/// inline cleanup steps inside `_apply{Plaintext,Keychain,
/// KeychainWithPassword,Hardware,Paranoid}Tier` — extracted so the
/// matrix is one unit-testable surface instead of five inlined
/// `await ref.read(...).clear()` chains that drifted independently.
TierVaultClearPlan tierVaultClearPlanFor(SecurityTier target) {
  switch (target) {
    case SecurityTier.plaintext:
      // T0 — every vault wiped. The DB drops to plaintext, so no
      // wrapper needs to survive.
      return const TierVaultClearPlan(
        clearKeychainKey: true,
        clearKeychainGate: true,
        clearHardwareVault: true,
        clearMasterPassword: true,
        clearBiometricVault: true,
      );
    case SecurityTier.keychain:
      // T1 — apply just wrote a fresh DB key into the keychain;
      // every other vault gets cleared.
      return const TierVaultClearPlan(
        clearKeychainKey: false,
        clearKeychainGate: true,
        clearHardwareVault: true,
        clearMasterPassword: true,
        clearBiometricVault: true,
      );
    case SecurityTier.keychainWithPassword:
      // T1+pw — apply wrote both the keychain key + the password
      // gate; everything else clears.
      return const TierVaultClearPlan(
        clearKeychainKey: false,
        clearKeychainGate: false,
        clearHardwareVault: true,
        clearMasterPassword: true,
        clearBiometricVault: true,
      );
    case SecurityTier.hardware:
      // T2 — apply sealed under SE/TPM; keychain key + gate go,
      // master-password disables (was on Paranoid before), bio
      // clears.
      return const TierVaultClearPlan(
        clearKeychainKey: true,
        clearKeychainGate: true,
        clearHardwareVault: false,
        clearMasterPassword: true,
        clearBiometricVault: true,
      );
    case SecurityTier.paranoid:
      // Paranoid — apply just enabled the master password; every
      // OS-trust-bearing vault wipes.
      return const TierVaultClearPlan(
        clearKeychainKey: true,
        clearKeychainGate: true,
        clearHardwareVault: true,
        clearMasterPassword: false,
        clearBiometricVault: true,
      );
  }
}
