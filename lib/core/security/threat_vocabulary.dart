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
///   3. Privileged/forensic family (live RAM forensics on a locked
///      machine, OS kernel or keychain breach) — attacker has
///      kernel-level reach.
///
/// *Threats deliberately not listed:* same-user malware (a hostile
/// process running as the same OS user holds every grant the app
/// has) and live process memory dump (ptrace / debugger attached to
/// the running app) are ✗ on every tier — no config we ship defends
/// against them, so showing the rows would only tell the user "none
/// of these options change the answer here". The honest framing is
/// to omit them from the per-tier comparison and cover them in the
/// threat-model prose in SECURITY.md instead. If a future tier /
/// modifier ever moves the needle (e.g. a locked-on-idle mode that
/// wipes the derived key after N seconds of inactivity), the rows
/// return.
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
/// | Offline brute force on password       | ✗  | ✗  | ✓     | ✗  | ✓     | ✓        |
/// | Bystander at unlocked machine         | ✗  | ✗  | ✓     | ✗  | ✓     | ✓        |
/// | Live RAM forensics on locked machine  | ✗  | ✗  | ✗     | ✗  | ✓     | ✓        |
/// | OS kernel / keychain breach           | ✗  | ✗  | ✗     | ✗  | ✓     | ✓        |
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
/// *Why offline brute force is symmetric across T1 and T2:* the
/// threat as formulated is "the attacker has an on-disk blob and
/// tries passwords against it offline". Without a user password on
/// either tier the attack does not apply — but the same attacker
/// still wins via a different path (keyring file exfil on T1, the
/// hardware module refuses everything on T2). The honest rendering
/// is a symmetric ✗ on both T1-no-pw and T2-no-pw; the
/// keyring-file-theft row above carries the real T1-vs-T2 split that
/// makes T2-no-pw actually more protected than T1-no-pw. Earlier
/// versions of this table showed T2-no-pw ✓ here on the logic of
/// "no on-disk brute-force target" — clever but confusing: users read
/// the password modifier as the only way ✓ appears on the brute-force
/// row, and the lopsided ✓ broke that mental model.
///
/// *Why T2+password now defeats RAM forensics + OS kernel breach
/// (but T1+password does not):* auto-lock unconditionally wipes the
/// DB key and closes the encrypted store (see `AutoLockDetector`).
/// What remains on disk differs by tier:
///
///   * **T1+password**: the wrapping key sits in the OS keychain
///     daemon — a separate process outside our wipe's reach. A RAM
///     dump of a locked machine still yields the daemon's plaintext
///     copy; an OS kernel / keychain breach reads the daemon's
///     memory or the on-disk keychain file directly. Still ✗.
///   * **T2+password**: the wrapping key never leaves the TPM /
///     Secure Enclave / StrongBox / Windows Hello NCrypt handle
///     (NCRYPT_EXPORT_POLICY refuses export). A RAM dump sees only
///     the sealed blob (ciphertext from the attacker's view).
///     Kernel breach can ask the chip to unseal, but rate-limit
///     lockout throttles that into infeasibility. Becomes ✓.
///   * **Paranoid**: key is derived per unlock from the master
///     password via Argon2id; no at-rest key anywhere. ✓ regardless.
///
/// The always-wipe-on-lock policy is the enabler — without it the
/// DB key sat in app RAM for as long as any SSH session was active,
/// collapsing T2+pw and T1+pw onto the same ✗ row. The per-session
/// [SessionCredentialCache] satisfies the UX requirement (live
/// reconnects keep working through a lock) without keeping the DB
/// key warm.
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
    // Offline brute force: ✓ only when a user password is set.
    // Symmetric across T1 and T2 — both tiers need the password
    // modifier to turn the brute-force threat into an Argon2id
    // wall-clock problem. Without a password the threat vector is
    // formally N/A, but we render ✗ to keep the binary contract and
    // because the same disk attacker wins via the keyring-file-theft
    // row above on T1 (even though not on T2 — the hw-isolation
    // advantage lives in keyringFileTheft, not here).
    SecurityThreat.offlineBruteForce: yes(hasUserSecret),
    SecurityThreat.bystanderUnlockedMachine: yes(hasUserSecret),
    // Live RAM forensics on a locked machine + OS kernel / keychain
    // breach: Paranoid derives the key per unlock and zeroises
    // after use; T2 relies on chip opacity (key never leaves the
    // TPM / Secure Enclave / StrongBox, sealed blob on disk is
    // meaningless without the physical chip + auth value). T1
    // fails both because the keychain daemon is a separate process
    // whose memory / on-disk file sit outside our wipe.
    SecurityThreat.liveRamForensicsLocked: yes(
      model.tier == ThreatTier.paranoid ||
          (model.tier == ThreatTier.hardware && model.password),
    ),
    SecurityThreat.osKernelOrKeychainBreach: yes(
      model.tier == ThreatTier.paranoid ||
          (model.tier == ThreatTier.hardware && model.password),
    ),
  };
}
