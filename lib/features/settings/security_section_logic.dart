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
import 'dart:typed_data';

import '../../core/security/biometric_auth.dart';
import '../../core/security/security_tier.dart';
import '../../l10n/app_localizations.dart';
import '../../src/rust/api/macos_resign.dart' show MacosResignOutcome;
import '../../src/rust/api/security_config.dart' as rust_sec_cfg;
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
  // Bank-style v3: "T1 + password" is `keychain` + `modifiers
  // .password`, not a dedicated tier value. Paranoid is always
  // password-true by construction, but we still check the tier
  // explicitly so a malformed config (paranoid with the modifier
  // somehow false) doesn't silently disable auto-lock gating.
  final hasPassword = level == SecurityTier.paranoid || modifiers.password;
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
  // Pre-v3 the T1+password tier had its own enum value, so the
  // keychain card had to special-case "current is T1+pw" via a
  // distinct tier comparison. Post-v3 collapse: T1+pw is just
  // keychain + modifiers.password=true, so `tier == currentLevel`
  // covers it directly.
  final isCurrent = tier == currentLevel;

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

  // Bank-style v3: paranoid is always password-true by
  // construction, the formerly-dedicated T1+password tier is now
  // just `currentModifiers.password` on the keychain tier.
  final hasPassword =
      currentLevel == SecurityTier.paranoid || currentModifiers.password;
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
/// previous config carries a password that can be cryptographically
/// checked: keychain + password (gate verifier file), hardware
/// (always password-gated — the hw-vault unseal is the verifier),
/// and paranoid (KDF-derived key against the master verifier).
/// Plaintext and plain keychain do not — the gate-down transition
/// for those has nothing to verify against, so the helper returns
/// false and the apply pipeline skips the prompt.
///
/// Same-tier transitions (keychain+pw → keychain+pw, hardware →
/// hardware, paranoid → paranoid) return false: the user is
/// reconfiguring modifiers, not dropping the password, so the
/// prompt would be redundant. A keychain+pw → keychain (drop the
/// modifier alone) IS a verifiable drop and triggers the prompt
/// — the tier value stays but the password gate goes away.
bool isVerifiablePasswordDrop({
  required SecurityTier currentTier,
  required SecurityTierModifiers currentModifiers,
  required SecurityTier nextTier,
  required SecurityTierModifiers nextModifiers,
}) {
  // Pre-v3 model carried T1+password as its own tier value, so this
  // helper used to switch on tier alone. Bank-style v3 puts password
  // on the modifier — a keychain+pw → keychain transition keeps the
  // tier intact and only drops the modifier, so the modifier delta
  // is what gates the prompt now.
  final wasKeychainWithPassword =
      currentTier == SecurityTier.keychain && currentModifiers.password;
  final isKeychainWithPassword =
      nextTier == SecurityTier.keychain && nextModifiers.password;
  if (wasKeychainWithPassword && !isKeychainWithPassword) return true;
  if (currentTier == SecurityTier.hardware &&
      nextTier != SecurityTier.hardware) {
    return true;
  }
  if (currentTier == SecurityTier.paranoid &&
      nextTier != SecurityTier.paranoid) {
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
    case SecurityTier.hardware:
      return 'hardware';
    case SecurityTier.paranoid:
      return 'paranoid';
  }
}

/// Which password verifier the apply pipeline must drive when the user
/// confirms a verifiable password drop. Driven by
/// [passwordVerifierKindFor]; the dispatcher in
/// `_TierApply._confirmCurrentPasswordIfDropping` switches on the
/// enum and routes to the matching provider's `verify` method.
///
/// Only Paranoid, KeychainWithPassword, and Hardware carry a
/// verifiable password — see [isVerifiablePasswordDrop] — so the
/// gate caller has already narrowed the input to those tiers by
/// the time this is reached.
enum PasswordVerifierKind {
  /// `masterPasswordProvider.verify(entered)` — Paranoid.
  masterPassword,

  /// `keychainPasswordGateProvider.verify(entered)` — KeychainWithPassword.
  keychainGate,

  /// `hardwareTierVaultProvider.read(entered)` non-null — Hardware.
  /// The hw-vault unseal succeeds only when the typed password
  /// HMAC matches the seal-time HMAC, so a non-null result is the
  /// verifier.
  hardwareVault,
}

/// Pick the verifier the password-drop confirm dialog routes through
/// for [currentTier]. Paranoid uses the master-password manager;
/// KeychainWithPassword uses the keychain gate; Hardware uses the
/// hw-vault unseal. Any other tier reaches here only via misuse —
/// `isVerifiablePasswordDrop` is the gate that keeps T0 / T1 from
/// invoking the prompt at all — so the helper falls back to
/// keychainGate as a safe default; the surrounding dispatcher would
/// have already short-circuited on `false` from the gate.
PasswordVerifierKind passwordVerifierKindFor(SecurityTier currentTier) {
  if (currentTier == SecurityTier.paranoid) {
    return PasswordVerifierKind.masterPassword;
  }
  if (currentTier == SecurityTier.hardware) {
    return PasswordVerifierKind.hardwareVault;
  }
  return PasswordVerifierKind.keychainGate;
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
/// * [promptAndVerifyHardwarePassword] — same-tier biometric flip on
///   T2. The Hardware tier is always password-gated; the only way
///   to revalidate without a tier rekey is to unseal the hardware
///   vault under the typed password and stage the resulting key.
/// * [promptAndVerifyMasterPassword] — same-tier biometric flip on
///   Paranoid. Master-password manager owns both the verifier file
///   and the KDF; verifyAndDerive returns the key directly.
enum BiometricKeySource {
  pullFromAppliedTier,
  promptAndVerifyKeychainGate,
  promptAndVerifyHardwarePassword,
  promptAndVerifyMasterPassword,
}

/// Decide which path the biometric-enable flow takes given the
/// current and target tier. Cross-tier transitions never need to
/// re-prompt — the new tier's password is fresh from the card and
/// drives the rekey. Same-tier flips only need a re-prompt when the
/// tier carries a verifiable password (T1+pw, T2, Paranoid); other
/// same-tier flips (T1 without password, plaintext) have no
/// verifiable secret to gate against, so they fall back to reading
/// the post-apply DB key.
BiometricKeySource biometricKeySourceFor({
  required SecurityTier currentTier,
  required SecurityTierModifiers currentModifiers,
  required SecurityTier nextTier,
  required SecurityTierModifiers nextModifiers,
}) {
  // Cross-tier transitions still pull from the freshly-applied
  // tier; the new card's password drives the rekey directly.
  if (currentTier != nextTier) return BiometricKeySource.pullFromAppliedTier;
  // Same-tier flip on bank-style T1+pw — re-prompt against the
  // gate verifier file. The modifier-aware predicate replaces the
  // pre-v3 dedicated `keychainWithPassword` enum check.
  if (currentTier == SecurityTier.keychain &&
      currentModifiers.password &&
      nextModifiers.password) {
    return BiometricKeySource.promptAndVerifyKeychainGate;
  }
  // Same-tier flip on T2 — the Hardware tier is always
  // password-gated, so a same-tier biometric enable always has a
  // verifiable secret to re-prompt against. The hw-vault unseal
  // itself is the verifier.
  if (currentTier == SecurityTier.hardware) {
    return BiometricKeySource.promptAndVerifyHardwarePassword;
  }
  if (currentTier == SecurityTier.paranoid) {
    return BiometricKeySource.promptAndVerifyMasterPassword;
  }
  return BiometricKeySource.pullFromAppliedTier;
}

/// What every tier-apply method writes into the marker file before
/// kicking off `SecurityTierSwitcher.switchTierFromSecret`. Bundles
/// the snake-case tier name + modifier JSON so a crash-recovery path can
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
  // Modifier codec lives Rust-side in
  // `lfs_core::security::SecurityTierModifiers::to_json_map`; decode
  // the canonical Rust-emitted string into a map for the composite
  // log payload.
  final modsStr = rust_sec_cfg.securityTierModifiersToJson(
    password: modifiers.password,
    biometric: modifiers.biometric,
  );
  return jsonEncode({
    'tier': securityTierLogName(tier),
    'mods': jsonDecode(modsStr),
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

/// True when [outcome] means the inside-out re-sign step landed a
/// usable signing identity on the bundle. The other two values
/// (`bundleNotWritable`, `cancelledOrFailed`) represent the
/// user-actionable failure surface and route through the toast
/// path. Pulled out of `_enableMacosKeychain` so the success
/// classification is one testable surface.
bool isResignAcceptable(MacosResignOutcome outcome) =>
    outcome == MacosResignOutcome.succeeded;

/// True when [target] is one of the tiers the macOS Remove-Identity
/// flow allows the user to land on after the cert is dropped: T0
/// (plaintext, no keychain dependency) or Paranoid (master password,
/// no OS trust). Picking any other tier would re-bind to a cert that
/// is about to disappear, so the wizard's `forcedCaps` shape must be
/// matched by an equally narrow accept-set on the result side.
bool isPostIdentityRemovalTierAccepted(SecurityTier target) =>
    target == SecurityTier.plaintext || target == SecurityTier.paranoid;

/// Apply the Plaintext tier: rekey the DB to plaintext (null key)
/// and run the per-tier vault-clear plan. Pulled out for parity with
/// the other tier runners and tested for the canonical seam order.
Future<void> applyPlaintextTier({
  required SecurityTierModifiers modifiers,
  required Future<void> Function(
    Uint8List? key,
    SecurityTier level,
    SecurityTierModifiers mods,
  )
  applyAlwaysRekey,
  required Future<void> Function(
    SecurityTier target,
    SecurityTierModifiers modifiers,
  )
  runClearPlan,
}) async {
  await applyAlwaysRekey(null, SecurityTier.plaintext, modifiers);
  await runClearPlan(SecurityTier.plaintext, modifiers);
}

/// Apply the Keychain (no password) tier — SecretRef variant.
///
/// [stageRandomKey] mints a fresh `SecretStore` id and stages the
/// AES-256 DB key under it Rust-side (typical implementation:
/// `mintTierSwitchSecretId()` then
/// `cryptoAesGcmRandomKeyToSecret`). [keychainWriteFromSecret]
/// pulls the bytes from `SecretStore` and writes the OS keychain
/// entry — no FRB byte-crossing. [applyAlwaysRekeyFromSecret]
/// runs the rekey through `SecurityTierSwitcher.switchTierFromSecret`.
/// On keychain-write failure the staged secret is dropped so the
/// SecretStore stays clean.
///
/// Throws [StateError] on keychain-write failure (no gate to roll
/// back at this tier).
Future<void> applyKeychainTier({
  required SecurityTierModifiers modifiers,
  required String Function() stageRandomKey,
  required Future<bool> Function(String secretId) keychainWriteFromSecret,
  required Future<void> Function(
    String secretId,
    SecurityTier level,
    SecurityTierModifiers mods,
  )
  applyAlwaysRekeyFromSecret,
  required void Function(String secretId) dropStaged,
  required Future<void> Function(
    SecurityTier target,
    SecurityTierModifiers modifiers,
  )
  runClearPlan,
}) async {
  final secretId = stageRandomKey();
  if (!await keychainWriteFromSecret(secretId)) {
    dropStaged(secretId);
    throw StateError('keychain write failed');
  }
  await applyAlwaysRekeyFromSecret(secretId, SecurityTier.keychain, modifiers);
  await runClearPlan(SecurityTier.keychain, modifiers);
}

/// Apply the Hardware tier — SecretRef variant. Seals the staged
/// SecretStore key under the hardware vault keyed by the typed
/// [password] (T2 is always password-gated; biometric is the
/// optional shortcut layer), rekeys, runs the vault clear plan.
/// Throws [StateError] when [password] is null/empty — the apply
/// pipeline must not reach the hardware seal without one. Also
/// throws on seal failure; staged secret is dropped before the
/// throw.
Future<void> applyHardwareTier({
  required SecurityTierModifiers modifiers,
  required String? password,
  required String Function() stageRandomKey,
  required Future<bool> Function({
    required String secretId,
    required String? pin,
  })
  hardwareStoreFromSecret,
  required Future<void> Function(
    String secretId,
    SecurityTier level,
    SecurityTierModifiers mods,
  )
  applyAlwaysRekeyFromSecret,
  required void Function(String secretId) dropStaged,
  required Future<void> Function(
    SecurityTier target,
    SecurityTierModifiers modifiers,
  )
  runClearPlan,
}) async {
  if (password == null || password.isEmpty) {
    throw StateError('hardware password missing');
  }
  final secretId = stageRandomKey();
  final sealed = await hardwareStoreFromSecret(
    secretId: secretId,
    pin: password,
  );
  if (!sealed) {
    dropStaged(secretId);
    throw StateError('hardware seal failed');
  }
  await applyAlwaysRekeyFromSecret(secretId, SecurityTier.hardware, modifiers);
  await runClearPlan(SecurityTier.hardware, modifiers);
}

/// Apply the Paranoid tier. Enables the master-password manager,
/// which derives the DB key from the user's master password; rekeys
/// under that key; runs the vault clear plan. Throws [StateError]
/// when the master password is null/empty — the manager refuses to
/// enable without one.
/// Apply the Paranoid tier — SecretRef variant. The master-password
/// manager's `enableToSecret` derives the AES key Argon2id-from
/// the passphrase and stages it Rust-side under the caller-minted
/// `secretId`, then `applyAlwaysRekeyFromSecret` runs the rekey.
/// Throws [StateError] on missing / empty master password.
Future<void> applyParanoidTier({
  required String? masterPassword,
  required SecurityTierModifiers modifiers,
  required String Function() mintSecretId,
  required Future<void> Function(Uint8List pw, String secretId)
  masterEnableToSecret,
  required Future<void> Function(
    String secretId,
    SecurityTier level,
    SecurityTierModifiers mods,
  )
  applyAlwaysRekeyFromSecret,
  required void Function(String secretId) dropStaged,
  required Future<void> Function(
    SecurityTier target,
    SecurityTierModifiers modifiers,
  )
  runClearPlan,
}) async {
  if (masterPassword == null || masterPassword.isEmpty) {
    throw StateError('master password missing');
  }
  // Convert here so the caller's `masterEnableToSecret` seam — which
  // drops straight onto the FRB `Vec<u8>` boundary — never sees the
  // typed `String`. The Dart `String` becomes GC-eligible the moment
  // this function returns.
  final passwordBytes = Uint8List.fromList(utf8.encode(masterPassword));
  final secretId = mintSecretId();
  try {
    await masterEnableToSecret(passwordBytes, secretId);
  } catch (_) {
    dropStaged(secretId);
    rethrow;
  }
  await applyAlwaysRekeyFromSecret(secretId, SecurityTier.paranoid, modifiers);
  await runClearPlan(SecurityTier.paranoid, modifiers);
}

/// Apply the KeychainWithPassword tier: stage the gate password,
/// generate + write a fresh DB key into the keychain, rekey the DB,
/// and run the per-tier vault-clear plan. Pulled out of
/// `_TierApply._applyKeychainWithPasswordTier` so the rollback path
/// (gate clear when keychain write fails) is unit-tested without
/// booting Riverpod.
///
/// Throws [StateError] when:
/// * the result carries no short password (empty / missing) — the
///   apply pipeline must never reach the gate setter without one.
/// * the keychain write fails — the staged gate password is rolled
///   back via [gateClear] before the throw, so a re-attempt starts
///   from a clean gate slot.
Future<void> applyKeychainWithPasswordTier({
  required String? shortPassword,
  required SecurityTierModifiers modifiers,
  required Future<void> Function(Uint8List pw) gateSetPassword,
  required Future<void> Function() gateClear,
  required String Function() stageRandomKey,
  required Future<bool> Function(String secretId) keychainWriteFromSecret,
  required Future<void> Function(
    String secretId,
    SecurityTier level,
    SecurityTierModifiers mods,
  )
  applyAlwaysRekeyFromSecret,
  required void Function(String secretId) dropStaged,
  required Future<void> Function(
    SecurityTier target,
    SecurityTierModifiers modifiers,
  )
  runClearPlan,
}) async {
  if (shortPassword == null || shortPassword.isEmpty) {
    throw StateError('short password missing');
  }
  // Convert here so the gate seam — which lands on the FRB
  // `Vec<u8>` boundary — never sees the typed `String`.
  final passwordBytes = Uint8List.fromList(utf8.encode(shortPassword));
  await gateSetPassword(passwordBytes);
  final secretId = stageRandomKey();
  final stored = await keychainWriteFromSecret(secretId);
  if (!stored) {
    dropStaged(secretId);
    await gateClear();
    throw StateError('keychain write failed');
  }
  // Bank-style v3: T1+password is `keychain` + `modifiers
  // .password=true`; the rekey + clear-plan dispatch both bind on
  // the same tier value as plain keychain.
  await applyAlwaysRekeyFromSecret(secretId, SecurityTier.keychain, modifiers);
  await runClearPlan(SecurityTier.keychain, modifiers);
}

/// Outcome of [confirmCurrentPasswordIfDropping]. Distinguishes the
/// three failure modes (not required / cancelled / wrong) so the
/// caller can route only the wrong-password case to the user-visible
/// toast — cancel and not-required are silent.
enum ConfirmPasswordResult {
  /// The current → target transition does not drop a verifiable
  /// password, so no prompt was shown. The caller proceeds with
  /// the apply.
  notRequired,

  /// The prompt resolved to null — user dismissed the dialog. The
  /// caller aborts the apply silently.
  cancelled,

  /// The verifier rejected the entered password. The caller surfaces
  /// the "current password incorrect" toast and aborts.
  wrongPassword,

  /// The verifier accepted the password. The caller proceeds with
  /// the apply.
  ok,
}

/// Run the password-confirm gate for a tier transition. Pulled out
/// of `_TierApply._confirmCurrentPasswordIfDropping` so the four-
/// outcome state machine is unit-testable without booting a dialog
/// or a riverpod container.
///
/// Routes through:
/// 1. [isVerifiablePasswordDrop] — short-circuit `notRequired` when
///    the transition has nothing verifiable to drop.
/// 2. [promptCurrentPassword] — shows the inline current-password
///    dialog and returns the typed string. `null` → `cancelled`.
/// 3. [passwordVerifierKindFor] — decide which verifier to use
///    based on the current tier.
/// 4. The matching `verify*` seam — `false` → `wrongPassword`,
///    `true` → `ok`.
Future<ConfirmPasswordResult> confirmCurrentPasswordIfDropping({
  required SecurityTier currentTier,
  required SecurityTierModifiers currentModifiers,
  required SecurityTier targetTier,
  required SecurityTierModifiers targetModifiers,
  required Future<String?> Function() promptCurrentPassword,
  required Future<bool> Function(Uint8List) verifyMaster,
  required Future<bool> Function(Uint8List) verifyKeychainGate,
  required Future<bool> Function(String) verifyHardwareVault,
}) async {
  if (!isVerifiablePasswordDrop(
    currentTier: currentTier,
    currentModifiers: currentModifiers,
    nextTier: targetTier,
    nextModifiers: targetModifiers,
  )) {
    return ConfirmPasswordResult.notRequired;
  }
  final entered = await promptCurrentPassword();
  if (entered == null) return ConfirmPasswordResult.cancelled;
  final ok = switch (passwordVerifierKindFor(currentTier)) {
    // Master + keychain verifiers marshal Uint8List over FRB —
    // convert here so the typed `String` from the dialog stays in
    // this scope only.
    PasswordVerifierKind.masterPassword => await verifyMaster(
      Uint8List.fromList(utf8.encode(entered)),
    ),
    PasswordVerifierKind.keychainGate => await verifyKeychainGate(
      Uint8List.fromList(utf8.encode(entered)),
    ),
    // Hardware unseal takes the String directly — the HMAC is
    // computed Rust-side from the typed bytes + per-install salt.
    PasswordVerifierKind.hardwareVault => await verifyHardwareVault(entered),
  };
  return ok ? ConfirmPasswordResult.ok : ConfirmPasswordResult.wrongPassword;
}

/// Run the [plan] decided by [tierVaultClearPlanFor] through the
/// supplied vault-clear seams. Each seam is the existing provider
/// method (`secureKeyStorage.deleteKey`, `keychainGate.clear`,
/// `hardwareVault.clear`, `masterPassword.disable`, `biometricVault.clear`)
/// plus the master-password gate (`masterPassword.isEnabled` —
/// `disable` on a disabled manager is a no-op but the FRB
/// round-trip is non-trivial, so the gate keeps the call
/// quiet on tiers without the manager).
///
/// Pulled out of `_runVaultClearPlan` so the per-slot dispatch can
/// be unit-tested against every plan combination without touching
/// the Riverpod runtime — production passes the real provider
/// methods, tests pass recording lambdas.
Future<void> runVaultClearPlan({
  required TierVaultClearPlan plan,
  required Future<void> Function() clearKeychainKey,
  required Future<void> Function() clearKeychainGate,
  required Future<void> Function() clearHardwareVault,
  required Future<bool> Function() isMasterPasswordEnabled,
  required Future<void> Function() disableMasterPassword,
  required Future<void> Function() clearBiometricVault,
}) async {
  if (plan.clearKeychainKey) await clearKeychainKey();
  if (plan.clearKeychainGate) await clearKeychainGate();
  if (plan.clearHardwareVault) await clearHardwareVault();
  if (plan.clearMasterPassword) {
    if (await isMasterPasswordEnabled()) {
      await disableMasterPassword();
    }
  }
  if (plan.clearBiometricVault) await clearBiometricVault();
}

/// The clear plan for a tier-apply targeting [target]. Mirrors the
/// inline cleanup steps inside `_apply{Plaintext,Keychain,
/// KeychainWithPassword,Hardware,Paranoid}Tier` — extracted so the
/// matrix is one unit-testable surface instead of five inlined
/// `await ref.read(...).clear()` chains that drifted independently.
TierVaultClearPlan tierVaultClearPlanFor(
  SecurityTier target,
  SecurityTierModifiers modifiers,
) {
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
      // T1 — apply just wrote a fresh DB key into the keychain.
      // The password gate file survives only when the bank-style
      // password modifier is on (the pre-v3 `keychainWithPassword`
      // tier value is now this branch with `modifiers.password ==
      // true`); everything else clears.
      return TierVaultClearPlan(
        clearKeychainKey: false,
        clearKeychainGate: !modifiers.password,
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
