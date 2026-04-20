/// Canonical security threat vocabulary used by every UI surface
/// that talks to the user about security tradeoffs — per-tier info
/// popups, the global comparison table, wizard hints, and
/// ARCHITECTURE.md documentation.
///
/// Every threat has a single fixed string identifier that drives the
/// l10n key (`threatColdDiskTheft`, `threatColdDiskTheftDescription`,
/// …). The truth table in [evaluate] is the single source of truth
/// for which tier/modifier combos defeat which threats. Changes here
/// ripple through the UI automatically.
library;

/// Discrete threat categories the app reasons about. Order is
/// user-facing — every UI surface renders threats in this exact
/// sequence so the user can flip between tier popups and compare
/// positionally without having to re-scan the labels.
enum SecurityThreat {
  /// Cold-disk theft — powered-off machine, drive removed and read
  /// on another box (or the DB file copied off a running machine by
  /// someone with read access to the user's home directory).
  coldDiskTheft,

  /// Bystander at an already-unlocked machine — attacker walks up,
  /// opens the app. No authentication prompt = the data is visible.
  bystanderUnlockedMachine,

  /// Same-user malware — hostile process running as the same OS
  /// user has every grant the app has: FS access, keychain access,
  /// memory access. No tier protects against this on a compromised
  /// host.
  sameUserMalware,

  /// Live process memory dump — attacker with debugger / ptrace on
  /// the running app reads the unlocked DB key from RAM.
  liveProcessMemoryDump,

  /// Live RAM forensics on a locked machine — attacker freezes RAM
  /// (or dumps via DMA / Firewire / similar) and pulls still-resident
  /// key material out of the snapshot even though the app is locked.
  liveRamForensicsLocked,

  /// OS kernel or keychain compromise — kernel CVE, hardware chip
  /// backdoor, or keychain exfiltration. The OS is the attacker,
  /// not a resource the app can trust.
  osKernelOrKeychainBreach,

  /// Offline brute force on the user's password — attacker has the
  /// wrapped key or sealed blob and tries every password offline.
  /// Applies only to tiers where a user-typed secret exists.
  offlineBruteForce,
}

/// Binary per-threat status — ✓ or ✗. No weak/strong-password notes,
/// no "not applicable" marker. Every threat has a yes-or-no answer
/// on every tier: if the tier has no user secret, offline brute
/// force stays a ✗ (nothing is stopping the attacker) rather than a
/// philosophical "not applicable" that reads as if the threat
/// disappeared.
///
/// The binary shape is what the per-tier split-threat block in
/// Settings + wizard renders: ✓ rows land in the "Protects against"
/// half, ✗ rows in the "Does not protect" half.
enum ThreatStatus {
  /// ✓ — this (tier + modifier) combination defeats the threat.
  protects,

  /// ✗ — the threat is not defended against.
  doesNotProtect,
}

/// Normalised tier identifier used by the evaluator. Independent of
/// the Dart `SecurityTier` enum so the threat model can be reasoned
/// about without dragging in the full SecurityConfig shape — the UI
/// can evaluate hypothetical combinations (e.g. "what would I get if
/// I picked T2 with a password?") without building a `SecurityConfig`
/// first.
enum ThreatTier { plaintext, keychain, hardware, paranoid }

/// Input to [evaluate]. Encapsulates the bank-style modifier shape
/// (password + biometric) that the 3-tier model lands in after the
/// Phase F settings rewrite. Biometric is structurally a shortcut
/// for entering the password; evaluator treats it as equivalent to
/// "password on" for truth-table purposes and uses the `biometric`
/// flag only for UI hints.
class ThreatModel {
  final ThreatTier tier;
  final bool password;
  final bool biometric;

  const ThreatModel({
    required this.tier,
    this.password = false,
    this.biometric = false,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ThreatModel &&
          tier == other.tier &&
          password == other.password &&
          biometric == other.biometric;

  @override
  int get hashCode => Object.hash(tier, password, biometric);

  @override
  String toString() =>
      'ThreatModel($tier, password=$password, '
      'biometric=$biometric)';
}

/// Encode the canonical truth table from
/// `docs/ARCHITECTURE.md §3.6`:
///
/// | Threat                               | T0 | T1 | T1+pw | T2 | T2+pw | Paranoid |
/// |--------------------------------------|----|----|-------|----|-------|----------|
/// | Cold disk theft                      | ✗  | ✓  | ✓     | ✓  | ✓     | ✓        |
/// | Bystander at unlocked machine        | ✗  | ✗  | ✓     | ✗  | ✓     | ✓        |
/// | Same-user malware                    | ✗  | ✗  | ✗     | ✗  | ✗     | ✗        |
/// | Live process memory dump             | ✗  | ✗  | ✗     | ✗  | ✗     | ✗        |
/// | Live RAM forensics on locked machine | ✗  | ✗  | ✗     | ✗  | ✗     | ✓        |
/// | OS kernel / keychain breach          | ✗  | ✗  | ✗     | ✗  | ✗     | ✓        |
/// | Offline brute force on password      | ✗  | ✗  | ✓     | ✗  | ✓     | ✓        |
///
/// *Why offline brute force is ✗ without a user password:* the
/// threat asks "can an attacker who stole your disk get the data by
/// trying passwords?" With no user password the wrapped key is
/// gated by the OS keychain alone — an attacker with disk access
/// also has keychain access on the same host (same user), so the
/// brute-force step is unnecessary. The honest answer is "no
/// protection here", not "not applicable". This matches the
/// Settings / wizard guidance where every tier shows the same seven
/// threats and the ✓ / ✗ migration is the whole visualization.
///
/// Pure function — no I/O, no locale lookups, no platform probes.
/// Every UI surface consumes this map and renders ✓ / ✗ per threat.
Map<SecurityThreat, ThreatStatus> evaluate(ThreatModel model) {
  final hasUserSecret =
      model.tier == ThreatTier.paranoid ||
      (model.password &&
          (model.tier == ThreatTier.keychain ||
              model.tier == ThreatTier.hardware));

  ThreatStatus yes(bool condition) =>
      condition ? ThreatStatus.protects : ThreatStatus.doesNotProtect;

  return <SecurityThreat, ThreatStatus>{
    SecurityThreat.coldDiskTheft: yes(model.tier != ThreatTier.plaintext),
    SecurityThreat.bystanderUnlockedMachine: yes(hasUserSecret),
    // Same-user malware + live process memory dump: no tier protects.
    // The unlocked DB key sits in the app process; a malicious
    // same-user process has every grant the app has.
    SecurityThreat.sameUserMalware: ThreatStatus.doesNotProtect,
    SecurityThreat.liveProcessMemoryDump: ThreatStatus.doesNotProtect,
    // Live RAM forensics on a locked machine + OS kernel / keychain
    // breach: only Paranoid holds up. Paranoid derives the key per
    // unlock and zeroises after use; numbered tiers rely on the OS
    // to keep the wrapped key secret.
    SecurityThreat.liveRamForensicsLocked: yes(
      model.tier == ThreatTier.paranoid,
    ),
    SecurityThreat.osKernelOrKeychainBreach: yes(
      model.tier == ThreatTier.paranoid,
    ),
    // Offline brute force: defence requires a user-typed secret.
    // Without one the "brute force the password" step collapses to
    // nothing (there is no password) and the disk attacker goes
    // straight through — reported ✗, not "not applicable".
    SecurityThreat.offlineBruteForce: yes(hasUserSecret),
  };
}
