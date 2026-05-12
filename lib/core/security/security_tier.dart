import 'dart:convert';

import '../../src/rust/api/security_config.dart' as rust_sec_cfg;

/// Named security tiers.
///
/// The user-facing UI presents four numbered tiers (T0–T2) in a linear
/// "more backend = higher number" ladder, plus a separate `paranoid`
/// branch shown as an **alternative** — master password, no OS trust,
/// not on the numbered ladder. The enum never orders its values; any
/// `<` / `>` comparison is a bug. Use tier predicates (`isParanoid`,
/// `hasKeychain`, `hasHardwareVault`) instead.
///
/// Wizard and Settings both read this enum and render numbered badges
/// + Paranoid label separately.
/// **Bank-style model** (post-v3 schema): one tier per key-storage
/// strategy + an orthogonal `password` modifier on top. Pre-v3
/// configs that carried a dedicated `keychainWithPassword` value are
/// rewritten by the Rust-side `ConfigV2ToV3` migration on next
/// startup — stored as `tier: keychain` + `modifiers.password: true`.
/// The legacy enum value is gone; runtime callers branching on
/// "T1 + password" check `modifiers.password`, not the tier itself.
enum SecurityTier {
  /// T0 — bare DB on disk. Only file permissions (0600 POSIX /
  /// user-only ACL Windows) stand between the data and anyone with
  /// filesystem access. Shown with a red warning in the wizard.
  plaintext,

  /// T1 — DB key lives in the OS secure storage (Keychain, Credential
  /// Manager, libsecret, EncryptedSharedPreferences). With
  /// `modifiers.password = false` the app auto-unlocks on launch
  /// (passwordless T1); with `modifiers.password = true` the unlock
  /// path adds a UX-gate short password checked against a salted
  /// HMAC split across disk + keychain (the bank-style T1+pw — pre-v3
  /// installs persisted this combo as a dedicated
  /// `keychainWithPassword` tier value, now collapsed).
  keychain,

  /// T2 — DB key wrapped by a hardware-bound vault (Secure Enclave,
  /// StrongBox, TPM2, Windows Hello). The `password` modifier
  /// optionally adds a typed-password layer on top; `biometric`
  /// optionally lets the user release that password via a
  /// biometric prompt instead of typing it. The hardware enforces
  /// attempt rate limiting + lockout after N failures, so a short
  /// PIN-as-password is cryptographically meaningful.
  hardware,

  /// Alternative branch — master password + Argon2id slow KDF + DB
  /// key derived fresh at every unlock, never stored in the OS. For
  /// users who do not trust the OS / hardware. Biometric is forbidden
  /// by design (biometric = caching the derived key, which breaks the
  /// "no-OS-trust" contract).
  paranoid,
}

/// Wire-name conversions matching the Rust-side
/// `lfs_core::security::SecurityTier` snake_case discriminants.
/// Used by FRB shims that take a tier as a `String` argument
/// (`tier_machine_set_tier`, `tier_unlock_biometric_commit`) so the
/// Dart caller doesn't hand-roll the conversion at every call site.
extension SecurityTierWireName on SecurityTier {
  String get wireName => switch (this) {
    SecurityTier.plaintext => 'plaintext',
    SecurityTier.keychain => 'keychain',
    SecurityTier.hardware => 'hardware',
    SecurityTier.paranoid => 'paranoid',
  };

  /// Resolve a tier from its snake_case wire name. Returns
  /// [SecurityTier.plaintext] for an unknown discriminant — the
  /// orchestrator should never emit one, so the fall-through is
  /// defensive only. Centralised here so listeners + bootstrap
  /// shims share one mapping table instead of carrying their
  /// own inline switches. Uses a statement-body switch (not the
  /// fat-arrow expression form) so the
  /// `security_tier_ordering_guard_test` regex — which scans for
  /// `> SecurityTier.<member>` ordinal-comparison shapes and
  /// can't tell `=>` from `>` — does not trip on this file.
  ///
  /// The pre-v3 `keychain_with_password` wire string is no longer
  /// recognised here — the `ConfigV2ToV3` migration rewrites stored
  /// configs before the runtime ever parses them, so this branch
  /// only fires on a genuinely-malformed value from an external
  /// caller (typo, hand-edited config). Falling through to plaintext
  /// keeps the existing safety posture (route into the wizard
  /// rather than silently picking an unintended tier).
  static SecurityTier fromWireName(String wireName) {
    switch (wireName) {
      case 'plaintext':
        return SecurityTier.plaintext;
      case 'keychain':
        return SecurityTier.keychain;
      case 'hardware':
        return SecurityTier.hardware;
      case 'paranoid':
        return SecurityTier.paranoid;
      default:
        return SecurityTier.plaintext;
    }
  }
}

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

  /// Wire shape mirrored Rust-side in
  /// `lfs_core::security::SecurityTierModifiers::to_json_map`. The
  /// Dart facade composes the modifier block from the field set;
  /// the outer `SecurityConfig.toJson` reuses it via the compat
  /// wrapper so a future field bump only touches Rust.
  Map<String, dynamic> toJson() => {
    'password': password,
    'biometric': biometric,
  };

  /// Decode mirrors the Rust `from_json_map` strictness: missing
  /// fields fall back to defaults. Pre-v4 `biometric_shortcut` /
  /// `pin_length` fields are stripped by the `ConfigV3ToV4`
  /// migration before this reader sees them; if they linger in a
  /// hand-edited config we silently ignore them.
  factory SecurityTierModifiers.fromJson(Map<String, dynamic> json) {
    const d = SecurityTierModifiers.defaults;
    return SecurityTierModifiers(
      password: json['password'] as bool? ?? d.password,
      biometric: json['biometric'] as bool? ?? d.biometric,
    );
  }

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

  /// Encode the SecurityConfig blob persisted under
  /// `config.json::security` via
  /// `lfs_core::security::SecurityConfig::to_json_value`.
  Map<String, dynamic> toJson() {
    final str = rust_sec_cfg.securityConfigToJson(
      tierWireName: tier.wireName,
      password: modifiers.password,
      biometric: modifiers.biometric,
    );
    return jsonDecode(str) as Map<String, dynamic>;
  }

  /// Decode via `lfs_core::security::SecurityConfig::from_json_value`.
  /// The Rust parser is permissively accepting: an unknown /
  /// missing tier string falls through to `plaintext` so the caller
  /// routes into the wizard rather than silently picking an
  /// unintended tier.
  factory SecurityConfig.fromJson(Map<String, dynamic> json) {
    final decoded = rust_sec_cfg.securityConfigFromJson(json: jsonEncode(json));
    if (decoded == null) return SecurityConfig.defaults;
    return SecurityConfig(
      tier: SecurityTierWireName.fromWireName(decoded.tierWireName),
      modifiers: SecurityTierModifiers(
        password: decoded.password,
        biometric: decoded.biometric,
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SecurityConfig &&
          tier == other.tier &&
          modifiers == other.modifiers;

  @override
  int get hashCode => Object.hash(tier, modifiers);

  @override
  String toString() => 'SecurityConfig(${tier.wireName}, $modifiers)';
}
