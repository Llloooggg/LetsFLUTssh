/// Data protection level for encrypted stores.
///
/// Detected at startup and stored in [securityLevelProvider].
/// Determines how sessions, SSH keys, and known hosts are persisted:
///
/// * [plaintext] — no encryption, data in cleartext JSON files.
/// * [keychain] — AES-256-GCM, key stored in OS keychain.
/// * [masterPassword] — AES-256-GCM, key derived via PBKDF2 from user password.
enum SecurityLevel {
  /// No encryption — data stored as plaintext JSON.
  plaintext,

  /// Encryption key stored in OS keychain (automatic, transparent).
  keychain,

  /// Encryption key derived from master password via PBKDF2-SHA256.
  masterPassword,
}
