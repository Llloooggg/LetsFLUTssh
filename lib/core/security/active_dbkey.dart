/// Canonical SecretStore slot id for the running session's
/// SQLCipher master key. Mirrors
/// `lfs_core::secrets::ACTIVE_DBKEY_SECRET_ID` byte-for-byte —
/// when Rust renames it the test
/// `secrets::tests::active_dbkey_secret_id_matches_dart_const`
/// trips and forces the Dart side to follow.
///
/// Every code path that needed the DB key Dart-side now routes
/// through one of the SecretRef-aware FRB shims that read from
/// this slot Rust-internally:
///
///   * `db_init_from_secret(path, ACTIVE)` — opens SQLCipher.
///   * `recorder_register_from_active(...)` — HKDF-derive +
///     register the per-recording key.
///   * `secure_storage_write_biometric_from_secret(alias,
///     ACTIVE)` — biometric-vault enroll on tier change.
///
/// Dart-side consumers only check presence (`secrets_has(ACTIVE)`)
/// or trigger Rust-internal operations against the slot.
const String kActiveDbKeySecretId = 'app.dbkey.active';
