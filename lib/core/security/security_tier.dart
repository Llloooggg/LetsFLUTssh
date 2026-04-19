/// Named security tiers.
///
/// The user-facing UI presents four numbered tiers (L0–L3) in a linear
/// "more backend = higher number" ladder, plus a separate `paranoid`
/// branch shown as an **alternative** — master password, no OS trust,
/// not on the numbered ladder. The enum never orders its values; any
/// `<` / `>` comparison is a bug. Use tier predicates (`isParanoid`,
/// `hasKeychain`, `hasHardwareVault`) instead.
///
/// Wizard and Settings both read this enum and render numbered badges
/// + Paranoid label separately.
enum SecurityTier {
  /// L0 — bare DB on disk. Only file permissions (0600 POSIX /
  /// user-only ACL Windows) stand between the data and anyone with
  /// filesystem access. Shown with a red warning in the wizard.
  plaintext,

  /// L1 — DB key lives in the OS secure storage (Keychain, Credential
  /// Manager, libsecret, EncryptedSharedPreferences). No user secret
  /// input; app auto-unlocks on launch.
  keychain,

  /// L2 — L1 + a short user-typed password checked on open. The
  /// password is a UX gate against a coworker at the desk, **not** a
  /// cryptographic layer (no Argon2id, no key wrapping on top of the
  /// keychain storage). Compared against a salted HMAC held split
  /// across disk + keychain.
  keychainWithPassword,

  /// L3 — DB key wrapped by a hardware-bound vault (Secure Enclave,
  /// StrongBox, TPM2, Windows Hello). Unlock requires a 4–6 digit PIN
  /// or (optionally) a live biometric prompt; the hardware enforces
  /// attempt rate limiting and lockout after N failures, so the short
  /// PIN is cryptographically meaningful.
  hardware,

  /// Alternative branch — master password + Argon2id slow KDF + DB
  /// key derived fresh at every unlock, never stored in the OS. For
  /// users who do not trust the OS / hardware. Biometric is forbidden
  /// by design (biometric = caching the derived key, which breaks the
  /// "no-OS-trust" contract).
  paranoid,
}

/// Orthogonal per-tier switches.
///
/// The bank-style modifier shape that Phase E/F lands on: `password`
/// and `biometric` are the two orthogonal switches the wizard
/// presents. `biometric` requires `password` (biometric is a shortcut
/// for entering the password, never its replacement).
///
/// `biometricShortcut` + `pinLength` are retained for the transition
/// window: existing persisted configs carry those fields, and some
/// call sites still read them. `biometricShortcut` is kept in sync
/// with `biometric` by the wizard so both readers see the same flag.
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

  /// Deprecated alias for [biometric]. Kept so existing call sites
  /// that read `biometricShortcut` continue to work until Phase F
  /// rewrites them. The wizard keeps both fields in sync on write.
  final bool biometricShortcut;

  /// PIN length for the hardware tier in the v1 model (4-6 digits).
  /// In the bank-style model passwords are arbitrary text, so this
  /// value is advisory — the wizard in the current transition window
  /// still renders a digit cell grid at this length when the user
  /// picks T2.
  final int pinLength;

  const SecurityTierModifiers({
    this.password = false,
    this.biometric = false,
    this.biometricShortcut = false,
    this.pinLength = 6,
  });

  static const defaults = SecurityTierModifiers();

  SecurityTierModifiers copyWith({
    bool? password,
    bool? biometric,
    bool? biometricShortcut,
    int? pinLength,
  }) => SecurityTierModifiers(
    password: password ?? this.password,
    biometric: biometric ?? this.biometric,
    biometricShortcut: biometricShortcut ?? this.biometricShortcut,
    pinLength: pinLength ?? this.pinLength,
  );

  Map<String, dynamic> toJson() => {
    'password': password,
    'biometric': biometric,
    'biometric_shortcut': biometricShortcut,
    'pin_length': pinLength,
  };

  factory SecurityTierModifiers.fromJson(Map<String, dynamic> json) {
    const d = SecurityTierModifiers.defaults;
    final rawPin = (json['pin_length'] as num?)?.toInt() ?? d.pinLength;
    final biometricShortcut =
        json['biometric_shortcut'] as bool? ?? d.biometricShortcut;
    return SecurityTierModifiers(
      password: json['password'] as bool? ?? d.password,
      // `biometric` falls back to `biometric_shortcut` on legacy
      // configs so a v1-persisted install reads as bank-style after
      // reload without a migration step.
      biometric: json['biometric'] as bool? ?? biometricShortcut,
      biometricShortcut: biometricShortcut,
      // Defensive: clamp to the supported range so a tampered config
      // cannot crash the PIN widget with an out-of-range cell count.
      pinLength: rawPin < 4 || rawPin > 8 ? d.pinLength : rawPin,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SecurityTierModifiers &&
          password == other.password &&
          biometric == other.biometric &&
          biometricShortcut == other.biometricShortcut &&
          pinLength == other.pinLength;

  @override
  int get hashCode =>
      Object.hash(password, biometric, biometricShortcut, pinLength);
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

  /// True when the tier stores the DB key in an OS keychain slot of
  /// any kind (L1 or L2). Used by code paths that need to decide
  /// between "read from keychain" and "derive fresh".
  bool get usesKeychain =>
      tier == SecurityTier.keychain ||
      tier == SecurityTier.keychainWithPassword;

  /// True when the tier binds the key to a hardware-bound vault.
  bool get usesHardwareVault => tier == SecurityTier.hardware;

  /// True when the tier has any user-typed secret (password, PIN, or
  /// master password) on the unlock path.
  bool get hasUserSecret =>
      tier == SecurityTier.keychainWithPassword ||
      tier == SecurityTier.hardware ||
      tier == SecurityTier.paranoid;

  SecurityConfig copyWith({
    SecurityTier? tier,
    SecurityTierModifiers? modifiers,
  }) => SecurityConfig(
    tier: tier ?? this.tier,
    modifiers: modifiers ?? this.modifiers,
  );

  Map<String, dynamic> toJson() => {
    'tier': _tierToString(tier),
    'modifiers': modifiers.toJson(),
  };

  factory SecurityConfig.fromJson(Map<String, dynamic> json) {
    final tierStr = json['tier'] as String?;
    final parsed = _tierFromString(tierStr);
    final modifiersJson = json['modifiers'];
    final modifiers = modifiersJson is Map<String, dynamic>
        ? SecurityTierModifiers.fromJson(modifiersJson)
        : SecurityTierModifiers.defaults;
    return SecurityConfig(tier: parsed, modifiers: modifiers);
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
  String toString() => 'SecurityConfig(${_tierToString(tier)}, $modifiers)';
}

String _tierToString(SecurityTier tier) {
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

SecurityTier _tierFromString(String? s) {
  switch (s) {
    case 'plaintext':
      return SecurityTier.plaintext;
    case 'keychain':
      return SecurityTier.keychain;
    case 'keychain_with_password':
      return SecurityTier.keychainWithPassword;
    case 'hardware':
      return SecurityTier.hardware;
    case 'paranoid':
      return SecurityTier.paranoid;
    default:
      // Unknown or missing string → treat as plaintext so the caller
      // sees `SecurityConfig.none` (plaintext + defaults) and routes
      // into the wizard. Never silently guess a non-plaintext tier
      // from corrupt config.
      return SecurityTier.plaintext;
  }
}
