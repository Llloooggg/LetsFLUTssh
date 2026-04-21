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
///
/// Grouping, top-to-bottom:
///   1. Offline-disk-access family (cold disk theft, keyring file
///      exfiltration, offline brute force) — attacker has disk bytes.
///   2. Physical-access family (bystander at an unlocked machine) —
///      attacker has the running session.
///   3. Online-process family (same-user malware, live process
///      memory dump) — attacker runs code alongside the app.
///   4. Privileged/forensic family (live RAM forensics on a locked
///      machine, OS kernel or keychain breach) — attacker has
///      kernel-level reach.
///
/// The four groups stay adjacent so a user scanning four tier cards
/// side-by-side sees the same threat in the same row on every card.
enum SecurityThreat {
  /// Cold-disk theft — powered-off machine, drive removed and read
  /// on another box (or the DB file copied off a running machine by
  /// someone with read access to the user's home directory).
  coldDiskTheft,

  /// Keyring / keychain file exfiltration — the attacker reads the
  /// platform's credential-store file directly off the disk
  /// (`~/.local/share/keyrings/*.keyring` on Linux, Credential
  /// Manager `.vcrd` files on Windows, `login.keychain-db` on
  /// macOS) and tries to recover the wrapped DB key from it. T1
  /// relies on this file being safe, so a disk attacker wins even
  /// without bruteforcing a password. T2 defeats it regardless of
  /// password: the hardware module refuses to export key material,
  /// so the on-disk blob is useless without the chip. This is the
  /// structural reason T2 without password beats T1 without password
  /// despite both surfacing a ✓ on `coldDiskTheft`.
  keyringFileTheft,

  /// Offline brute force on the user's password — attacker has the
  /// wrapped key or sealed blob and tries every password offline.
  /// Applies only to tiers where a user-typed secret exists.
  offlineBruteForce,

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
/// | Threat                                | T0 | T1 | T1+pw | T2 | T2+pw | Paranoid |
/// |---------------------------------------|----|----|-------|----|-------|----------|
/// | Cold disk theft                       | ✗  | ✓  | ✓     | ✓  | ✓     | ✓        |
/// | Keyring / keychain file exfiltration  | ✗  | ✗  | ✓     | ✓  | ✓     | ✓        |
/// | Offline brute force on password       | ✗  | ✗  | ✓     | ✓  | ✓     | ✓        |
/// | Bystander at unlocked machine         | ✗  | ✗  | ✓     | ✗  | ✓     | ✓        |
/// | Same-user malware                     | ✗  | ✗  | ✗     | ✗  | ✗     | ✗        |
/// | Live process memory dump              | ✗  | ✗  | ✗     | ✗  | ✗     | ✗        |
/// | Live RAM forensics on locked machine  | ✗  | ✗  | ✗     | ✗  | ✗     | ✓        |
/// | OS kernel / keychain breach           | ✗  | ✗  | ✗     | ✗  | ✗     | ✓        |
///
/// *Why keyring file exfiltration splits T1 from T2 without password:*
/// T1 keeps the DB wrapping key inside the OS keychain file (libsecret
/// `login.keyring`, Windows `Credential Manager .vcrd`, macOS
/// `login.keychain-db`) — a powered-off disk attacker can read the
/// file and recover the key offline. T2 stores the wrapped blob on
/// disk but the unwrap key lives inside the TPM / Secure Enclave /
/// StrongBox; exporting it is refused by the hardware regardless of
/// whether an auth value is set. The on-disk blob is useless without
/// the physical chip. This is the structural advantage T2 keeps over
/// T1 even when neither has a password.
///
/// *Why T2 without password still defeats offline brute force:* with
/// no user secret there is nothing to brute-force — the auth value
/// is the empty byte string — but an attacker also has nothing to
/// attack offline, because the unwrap requires the hardware. The ✓
/// here says "this threat as formulated (trying passwords offline) is
/// impossible on this tier", not "the threat is not applicable". On
/// T1 without password there is also no password to try, yet the
/// attacker wins via keyring-file exfiltration instead — which is why
/// the two threats stay separate rows.
///
/// *Why offline brute force is ✗ without a user password:* on T1
/// without password the threat collapses to plain keyring-file theft
/// (no password to brute force, the attacker reads the key from the
/// keyring file directly). On T2 without password the attacker has
/// no avenue at all (no key on disk + no brute-force step) — ✓.
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
    // Keyring file exfiltration splits T1 from T2 regardless of
    // password: T1 relies on an OS keychain file that a disk attacker
    // can read; T2 relies on a hw module that refuses key export.
    // Paranoid does not use the keychain at all so the ✓ is trivial.
    SecurityThreat.keyringFileTheft: yes(
      model.tier == ThreatTier.hardware ||
          model.tier == ThreatTier.paranoid ||
          (model.tier == ThreatTier.keychain && model.password),
    ),
    // Offline brute force: ✓ only when the attacker has no on-disk
    // asset to grind. T2 without password: blob on disk but the
    // unwrap key is in the chip, so there is nothing to brute-force
    // offline. T1 without password: the key itself is in the keyring
    // file, so "brute force" collapses to "read the file". ✗. T1+pw
    // and T2+pw: brute-forcing the password is the only angle, and
    // Argon2id turns it into a wall-clock problem. ✓.
    SecurityThreat.offlineBruteForce: yes(
      hasUserSecret || model.tier == ThreatTier.hardware,
    ),
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
  };
}
