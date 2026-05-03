/// Pure decision helpers extracted from `_SecuritySectionState`. The
/// section's biometric / auto-lock priority ladders are wide
/// (platform reason → tier-not-current → tier-unavailable →
/// password-missing → ready) and need to be exercised against every
/// combination of tier × modifier × probe state. Keeping the rules in
/// a stateful widget made every test a `pumpWidget` round-trip; this
/// module returns them as `String?` / `BiometricModifierSpec?` so the
/// callers stay one-liners and unit tests cover each branch directly.
library;

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
