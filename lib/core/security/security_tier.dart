import '../../src/rust/api/security_config.dart' as rust_sec_cfg;

/// Named security tiers — re-export of the FRB-mirror enum so call
/// sites keep the short `SecurityTier.plaintext` / `.keychain` /
/// `.hardware` / `.paranoid` identifiers. The single source of truth
/// (variant set + wire-string grammar) lives in
/// `lfs_core::security::SecurityTier`; route any wire conversion
/// through [`rust_sec_cfg.securityTierToWire`] /
/// [`rust_sec_cfg.securityTierFromWire`] so a future variant whose
/// Dart name diverges from the wire grammar (a keyword collision
/// forces FRB to append `_`) keeps the on-wire byte canonical.
///
/// The user-facing UI presents four numbered tiers (T0–T2) in a linear
/// "more backend = higher number" ladder, plus a separate `paranoid`
/// branch shown as an **alternative** — master password, no OS trust,
/// not on the numbered ladder. The enum never orders its values; any
/// `<` / `>` comparison is a bug. Use tier predicates (`isParanoid`,
/// `hasKeychain`, `hasHardwareVault`) instead.
///
/// **Bank-style model** (post-v3 schema): one tier per key-storage
/// strategy + an orthogonal `password` modifier on top. Pre-v3
/// configs that carried a dedicated `keychainWithPassword` value are
/// rewritten by the Rust-side `ConfigV2ToV3` migration on next
/// startup — stored as `tier: keychain` + `modifiers.password: true`.
/// The legacy enum value is gone; runtime callers branching on
/// "T1 + password" check `modifiers.password`, not the tier itself.
typedef SecurityTier = rust_sec_cfg.DbSecurityTier;

/// Orthogonal per-tier switches — the bank-style modifier shape:
/// `password` and `biometric` are the two orthogonal switches the
/// wizard presents. `biometric` requires `password` (biometric is a
/// shortcut for entering the password, never its replacement).
///
/// Pre-v4 configs also carried `biometric_shortcut` (a deprecated
/// 1:1 alias for `biometric`) and `pin_length` (advisory in the
/// bank-style model, no runtime caller). The Rust-side
/// `ConfigV3ToV4` migration drops both fields on the next read;
/// the runtime struct no longer carries them.
///
/// The class is a plain Dart data holder — wire codec lives Rust-side
/// in `lfs_core::security::SecurityTierModifiers` and crosses the FRB
/// boundary via the typed [`rust_sec_cfg.DbSecurityTierModifiers`] +
/// `securityConfigFromJson` / `securityConfigToJson`. Callers that
/// persist the bag route through [`SecurityConfig`] (or the AppConfig
/// composite); the modifier alone never crosses FRB on its own outside
/// the wizard fan-out.
class SecurityTierModifiers {
  /// User-typed password gate on the unlock path. Bank-style primary
  /// auth. Structurally irrelevant on `plaintext`; on `paranoid` the
  /// password is mandatory (the whole tier is derived from it) and
  /// this flag is implied-true.
  final bool password;

  /// Biometric shortcut that releases the stored password from a
  /// biometric-gated OS slot. Invariant: `biometric → password`
  /// (biometric cannot replace the typed password, only spare the
  /// user from typing it). Disabled in the UI when `password` is off.
  final bool biometric;

  const SecurityTierModifiers({this.password = false, this.biometric = false});

  static const defaults = SecurityTierModifiers();

  SecurityTierModifiers copyWith({bool? password, bool? biometric}) =>
      SecurityTierModifiers(
        password: password ?? this.password,
        biometric: biometric ?? this.biometric,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SecurityTierModifiers &&
          password == other.password &&
          biometric == other.biometric;

  @override
  int get hashCode => Object.hash(password, biometric);
}

/// Complete security configuration — tier + modifiers.
///
/// Persisted as `"security_tier"` + `"security_modifiers"` fields
/// inside the existing `config.json`. The "not yet configured" state
/// is represented by `AppConfig.security == null`, not by any
/// distinguished `SecurityConfig` instance — const canonicalisation
/// would make a sentinel indistinguishable from a legitimate
/// Plaintext-after-wizard configuration.
///
/// Wire codec lives Rust-side; the persistence boundary
/// (`AppConfig._securityConfigToTyped` / `_securityConfigFromTyped`)
/// rebuilds this Dart shell from the typed
/// [`rust_sec_cfg.DbSecurityConfig`] mirror that FRB hands back.
class SecurityConfig {
  final SecurityTier tier;
  final SecurityTierModifiers modifiers;

  const SecurityConfig({required this.tier, required this.modifiers});

  /// Convenience default used by call sites that need *some* concrete
  /// `SecurityConfig` (e.g. a `SecurityState.initial`) before the
  /// wizard or inference resolves the real one. **Not** a "wizard has
  /// not run" signal — that's `AppConfig.security == null`.
  static const defaults = SecurityConfig(
    tier: SecurityTier.plaintext,
    modifiers: SecurityTierModifiers.defaults,
  );

  // --- Convenience predicates — use instead of ordinal comparisons. ---

  bool get isParanoid => tier == SecurityTier.paranoid;
  bool get isPlaintext => tier == SecurityTier.plaintext;

  /// True when the tier stores the DB key in the OS keychain.
  /// Used by code paths that need to decide between "read from
  /// keychain" and "derive fresh". The bank-style password
  /// modifier is orthogonal: `keychain` covers both passwordless
  /// T1 and T1 + typed password.
  bool get usesKeychain => tier == SecurityTier.keychain;

  /// True when the tier binds the key to a hardware-bound vault.
  bool get usesHardwareVault => tier == SecurityTier.hardware;

  /// True when the config carries any user-typed secret on the
  /// unlock path. Paranoid and Hardware are mandatory-password by
  /// definition — Hardware uses the typed password as the primary
  /// gate on top of the hardware-bound vault; biometric is the
  /// optional shortcut that releases that password from an
  /// OS-managed slot, never a replacement. Keychain flips on the
  /// explicit `modifiers.password` modifier (the bank-style T1+pw
  /// shape — pre-v3 installs persisted this as a dedicated
  /// `keychainWithPassword` tier value).
  bool get hasUserSecret {
    switch (tier) {
      case SecurityTier.paranoid:
      case SecurityTier.hardware:
        return true;
      case SecurityTier.keychain:
        return modifiers.password;
      case SecurityTier.plaintext:
        return false;
    }
  }

  /// True when the user must supply a typed password to provision
  /// or unlock [tier]. Mirrors [hasUserSecret] but is keyed on the
  /// tier alone (modifiers ignored) so the wizard / Settings
  /// pickers can decide ahead of the modifier bag whether a
  /// password slot is mandatory. Hardware and Paranoid always
  /// require a password; Keychain leaves the call to the modifier
  /// toggle; Plaintext has nothing to gate.
  static bool requiresPasswordForTier(SecurityTier tier) {
    switch (tier) {
      case SecurityTier.paranoid:
      case SecurityTier.hardware:
        return true;
      case SecurityTier.keychain:
      case SecurityTier.plaintext:
        return false;
    }
  }

  SecurityConfig copyWith({
    SecurityTier? tier,
    SecurityTierModifiers? modifiers,
  }) => SecurityConfig(
    tier: tier ?? this.tier,
    modifiers: modifiers ?? this.modifiers,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SecurityConfig &&
          tier == other.tier &&
          modifiers == other.modifiers;

  @override
  int get hashCode => Object.hash(tier, modifiers);

  @override
  String toString() =>
      'SecurityConfig(${rust_sec_cfg.securityTierToWire(value: tier)}, $modifiers)';
}
