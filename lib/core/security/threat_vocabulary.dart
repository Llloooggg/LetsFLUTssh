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

/// Marker returned per threat by [evaluate]. Maps directly to a UI
/// glyph: ✓ protects, ✗ doesNotProtect, — notApplicable, ! notes.
enum ThreatStatus {
  /// ✓ — this (tier + modifier) combination defeats the threat.
  protects,

  /// ✗ — the threat is not defended against.
  doesNotProtect,

  /// — the threat is structurally irrelevant for this combination
  /// (e.g. offline brute force against a tier that has no user
  /// secret to brute force).
  notApplicable,

  /// ! — weak short password is acceptable only because another
  /// defence (hardware rate limiter, wrapped-key binding) carries
  /// the security. Shown as a yellow annotation, not a red ✗.
  noteWeakPasswordAcceptable,

  /// ! — the tier's security depends critically on a strong long
  /// password (Paranoid). Weak password on this tier is a real
  /// vulnerability, not a cosmetic one.
  noteStrongPasswordRecommended,
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
/// `docs/ARCHITECTURE.md §3.6` / the in-app comparison table:
///
/// | Threat                               | T0 | T1 | T1+pw | T1+pw+bio | T2 | T2+pw | T2+pw+bio | Paranoid |
/// |--------------------------------------|----|----|-------|-----------|----|-------|-----------|----------|
/// | Cold disk theft                      | ✗  | ✓  | ✓     | ✓         | ✓  | ✓     | ✓         | ✓        |
/// | Bystander at unlocked machine        | ✗  | ✗  | ✓     | ✓         | ✗  | ✓     | ✓         | ✓        |
/// | Same-user malware                    | ✗  | ✗  | ✗     | ✗         | ✗  | ✗     | ✗         | ✗        |
/// | Live process memory dump             | ✗  | ✗  | ✗     | ✗         | ✗  | ✗     | ✗         | ✗        |
/// | Live RAM forensics on locked machine | ✗  | ✗  | ✗     | ✗         | ✗  | ✗     | ✗         | ✓        |
/// | OS kernel / keychain breach          | ✗  | ✗  | ✗     | ✗         | ✗  | ✗     | ✗         | ✓        |
/// | Offline brute force on weak password | —  | —  | weak  | weak      | —  | str¹  | str¹      | weak²    |
///
/// ¹ T2+pw — wrapped key is bound to the hw chip, so an attacker
///   can't pull the sealed blob off disk and attack it offline. Short
///   passwords are acceptable because the rate limiter lives in the
///   hardware.
/// ² Paranoid — the password IS the entire secret. Argon2id slows
///   brute force but does not block a determined attacker against a
///   short password. A long passphrase is the actual defence.
///
/// Pure function — no I/O, no locale lookups, no platform probes.
/// Every UI surface consumes this map and renders the configured
/// glyph per threat.
Map<SecurityThreat, ThreatStatus> evaluate(ThreatModel model) {
  final hasSecret =
      model.tier == ThreatTier.paranoid ||
      (model.password &&
          (model.tier == ThreatTier.keychain ||
              model.tier == ThreatTier.hardware));

  final coldDiskTheft = switch (model.tier) {
    ThreatTier.plaintext => ThreatStatus.doesNotProtect,
    _ => ThreatStatus.protects,
  };

  final bystander = switch (model.tier) {
    ThreatTier.plaintext => ThreatStatus.doesNotProtect,
    ThreatTier.paranoid => ThreatStatus.protects,
    ThreatTier.keychain || ThreatTier.hardware =>
      model.password ? ThreatStatus.protects : ThreatStatus.doesNotProtect,
  };

  // Same-user malware + live process memory dump: no tier protects.
  // The unlocked DB key sits in the app process; a malicious same-user
  // process has every grant the app has.
  const sameUserMalware = ThreatStatus.doesNotProtect;
  const liveProcessDump = ThreatStatus.doesNotProtect;

  // Live RAM forensics on a locked machine + OS kernel / keychain
  // breach: only Paranoid holds up. Paranoid derives the key per
  // unlock and zeroises after use; numbered tiers rely on the OS to
  // keep the wrapped key secret.
  final liveRam = model.tier == ThreatTier.paranoid
      ? ThreatStatus.protects
      : ThreatStatus.doesNotProtect;
  final osBreach = model.tier == ThreatTier.paranoid
      ? ThreatStatus.protects
      : ThreatStatus.doesNotProtect;

  final ThreatStatus offline;
  if (!hasSecret) {
    offline = ThreatStatus.notApplicable;
  } else if (model.tier == ThreatTier.paranoid) {
    offline = ThreatStatus.noteStrongPasswordRecommended;
  } else if (model.tier == ThreatTier.hardware) {
    // Wrapped key bound to hw chip — no offline attack surface.
    offline = ThreatStatus.noteWeakPasswordAcceptable;
  } else {
    // T1+password — weak password is still weak (no hw binding).
    offline = ThreatStatus.noteWeakPasswordAcceptable;
  }

  return <SecurityThreat, ThreatStatus>{
    SecurityThreat.coldDiskTheft: coldDiskTheft,
    SecurityThreat.bystanderUnlockedMachine: bystander,
    SecurityThreat.sameUserMalware: sameUserMalware,
    SecurityThreat.liveProcessMemoryDump: liveProcessDump,
    SecurityThreat.liveRamForensicsLocked: liveRam,
    SecurityThreat.osKernelOrKeychainBreach: osBreach,
    SecurityThreat.offlineBruteForce: offline,
  };
}
