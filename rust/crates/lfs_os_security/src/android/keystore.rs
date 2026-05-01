//! AndroidKeyStore-backed key/value storage via direct JNI to
//! `java.security.KeyStore` provider `"AndroidKeyStore"`.
//!
//! Mirrors the `flutter_secure_storage` Android EncryptedSharedPreferences
//! pattern but owns the call chain end-to-end in Rust. Storage
//! shape:
//!
//! 1. **Wrapping key** — AES-256-GCM key generated inside
//!    AndroidKeyStore via `KeyGenerator.getInstance("AES",
//!    "AndroidKeyStore")` + `KeyGenParameterSpec.Builder(alias,
//!    PURPOSE_ENCRYPT | PURPOSE_DECRYPT)` with
//!    `setBlockModes("GCM")`, `setEncryptionPaddings("NoPadding")`,
//!    `setKeySize(256)`. The key never leaves the keystore;
//!    AndroidKeyStore wraps it under a hardware-backed root key
//!    when the device has a TEE / StrongBox.
//! 2. **Wrapped value** — caller's bytes encrypted with the
//!    wrapping key via `Cipher.getInstance("AES/GCM/NoPadding")`.
//!    Output is `[12-byte IV][ciphertext+16-byte tag]`,
//!    persisted to a 0600 file under `getFilesDir()` keyed on
//!    the alias. (Avoiding `EncryptedSharedPreferences` is
//!    deliberate: it pulls in androidx-security-crypto which
//!    duplicates everything we already do in lfs_core.)
//!
//! **Status: SCAFFOLD ONLY** — every public function below
//! returns `SecureStorageError::PlatformUnsupported` so the
//! Dart wrapper short-circuits to the existing
//! `flutter_secure_storage` MethodChannel path. The JNI call
//! sequences are documented inline as TODO blocks for the
//! future Android dev-loop session that fills them in. Doing
//! so without a real device or emulator is reckless: every
//! `env.call_method(obj, "name", "(args)Lreturn;", &[...])`
//! is a string-based signature lookup that surfaces mismatches
//! only at runtime, and the AndroidKeyStore class hierarchy
//! has subtle version-gating (StrongBox is API 28+,
//! `setUnlockedDeviceRequired` is API 28+, etc.) that needs
//! integration testing per `minSdkVersion` to validate.
//!
//! What this scaffold delivers:
//!
//! - JavaVM bootstrap path validated end-to-end
//!   (`super::jni_bootstrap`).
//! - Module structure + cfg gates so the Android target
//!   compiles cleanly under rust-cross-check matrix.
//! - Type-safe `keystore_alias_for` helper that mirrors the
//!   Dart-side alias derivation, ready for the JNI call sites
//!   to consume.
//! - Documented JNI call chain per operation, ready to
//!   convert into real `env.call_method` invocations once a
//!   device is available to verify each method ID resolves.

use crate::secure_key_storage::SecureStorageError;

/// Alias prefix used by `flutter_secure_storage`'s Android
/// implementation. Matched here so existing on-device entries
/// survive when the JNI path eventually retires the plugin.
pub const KEY_ALIAS_PREFIX: &str = "FlutterSecureStorageKeyAlias_";

/// Map a logical `alias` (the same one passed to `read`/`write`)
/// to the AndroidKeyStore key alias the wrapping key lives
/// under.
pub fn keystore_alias_for(alias: &str) -> String {
    format!("{KEY_ALIAS_PREFIX}{alias}")
}

/// TODO(Android dev-loop): JNI call chain for `read`:
///
/// 1. `KeyStore ks = KeyStore.getInstance("AndroidKeyStore")`
///    `ks.load(null)`
/// 2. `SecretKey wrap = (SecretKey) ks.getKey(keystore_alias, null)`
///    Return `SecureStorageError::NotFound` if `getKey` returns
///    null.
/// 3. Read the wrapped-value file under
///    `getFilesDir()/lfs_secure_storage/<alias>.bin`.
///    Return `SecureStorageError::NotFound` if missing.
/// 4. Split first 12 bytes as IV, rest as ciphertext+tag.
/// 5. `Cipher c = Cipher.getInstance("AES/GCM/NoPadding")`
///    `c.init(Cipher.DECRYPT_MODE, wrap, new GCMParameterSpec(128, iv))`
/// 6. `byte[] plain = c.doFinal(ciphertext)`
/// 7. Return `Some(plain)`.
pub async fn read(_alias: &str) -> Result<Option<Vec<u8>>, SecureStorageError> {
    Err(SecureStorageError::PlatformUnsupported)
}

/// TODO(Android dev-loop): JNI call chain for `read_biometric`.
/// Same as [`read`] but the wrapping key is loaded with
/// `setUserAuthenticationRequired(true)` + biometric-bound
/// `setUserAuthenticationParameters(0, KeyProperties.AUTH_BIOMETRIC_STRONG)`.
/// `Cipher.init` will throw `UserNotAuthenticatedException`;
/// the BiometricPrompt invocation lives in
/// `super::biometric_auth` (separate per-file arc).
pub async fn read_biometric(_alias: &str) -> Result<Option<Vec<u8>>, SecureStorageError> {
    Err(SecureStorageError::PlatformUnsupported)
}

/// TODO(Android dev-loop): JNI call chain for `write` /
/// `write_biometric`:
///
/// 1. `KeyStore ks = KeyStore.getInstance("AndroidKeyStore")`
///    `ks.load(null)`
/// 2. If `keystore_alias` is not present in `ks`:
///    `KeyGenerator kg = KeyGenerator.getInstance("AES", "AndroidKeyStore")`
///    Build `KeyGenParameterSpec`:
///      - `setBlockModes("GCM")`
///      - `setEncryptionPaddings("NoPadding")`
///      - `setKeySize(256)`
///      - if `biometric`: `setUserAuthenticationRequired(true)`
///        + `setUserAuthenticationParameters(0,
///        KeyProperties.AUTH_BIOMETRIC_STRONG)` (API 30+) OR
///        `setUserAuthenticationValidityDurationSeconds(-1)`
///        (API 23-29 fallback)
///    `kg.init(spec); kg.generateKey()`
/// 3. Load the wrapping key.
/// 4. `Cipher c = Cipher.getInstance("AES/GCM/NoPadding")`
///    `c.init(Cipher.ENCRYPT_MODE, wrap)`  (auto-generates IV)
/// 5. `byte[] ct = c.doFinal(value)`
///    `byte[] iv = c.getIV()`
/// 6. Write `iv || ct` to
///    `getFilesDir()/lfs_secure_storage/<alias>.bin` with
///    `MODE_PRIVATE` (0600 equivalent).
pub async fn write(
    _alias: &str,
    _value: &[u8],
    _biometric: bool,
) -> Result<(), SecureStorageError> {
    Err(SecureStorageError::PlatformUnsupported)
}

/// TODO(Android dev-loop): JNI call chain for `delete`:
///
/// 1. `ks.deleteEntry(keystore_alias)` — silently succeeds on
///    missing alias.
/// 2. Remove the wrapped-value file (best-effort; missing file
///    is not an error).
pub async fn delete(_alias: &str, _biometric: bool) -> Result<(), SecureStorageError> {
    Err(SecureStorageError::PlatformUnsupported)
}
