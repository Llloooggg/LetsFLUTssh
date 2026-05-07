//! FRB adapter for `lfs_os_security::secure_key_storage`. The
//! Dart wrapper routes desktop platforms (Linux / macOS / iOS /
//! Windows) through here; Android stays on the existing
//! `flutter_secure_storage` MethodChannel until the JNI bridge
//! to AndroidKeystore lands.

#[derive(Debug, Clone)]
pub enum DbSecureStorageOutcome {
    /// Bytes returned. Empty `Vec` means "key existed with
    /// zero-length value", not "missing".
    Found(Vec<u8>),
    NotFound,
}

fn map_read(
    res: Result<Option<Vec<u8>>, lfs_os_security::secure_key_storage::SecureStorageError>,
) -> Result<DbSecureStorageOutcome, String> {
    match res {
        Ok(Some(bytes)) => Ok(DbSecureStorageOutcome::Found(bytes)),
        Ok(None) => Ok(DbSecureStorageOutcome::NotFound),
        Err(e) => Err(e.to_string()),
    }
}

fn map_unit(
    res: Result<(), lfs_os_security::secure_key_storage::SecureStorageError>,
) -> Result<(), String> {
    res.map_err(|e| e.to_string())
}

pub async fn secure_storage_read(alias: String) -> Result<DbSecureStorageOutcome, String> {
    map_read(lfs_os_security::secure_key_storage::read(&alias).await)
}

pub async fn secure_storage_write(alias: String, value: Vec<u8>) -> Result<(), String> {
    map_unit(lfs_os_security::secure_key_storage::write(&alias, &value).await)
}

/// Variant of [`secure_storage_write`] that pulls the bytes from
/// [`lfs_core::secrets::SecretStore`] under [`secret_id`] instead of
/// taking them across the FRB boundary. Used by callers that have
/// staged the value through
/// [`super::crypto::crypto_aes_gcm_random_key_to_secret`] (or
/// equivalent) so the bytes never touch the Dart heap on the way to
/// the OS keychain. The SecretStore entry remains after the write —
/// the caller drops it explicitly via `secrets_drop` once every
/// downstream consumer (e.g. drift's sqlcipher pragma) has had its
/// turn through `secrets_take`. Returns `Err("secret not found: …")`
/// when the id is absent from the store.
pub async fn secure_storage_write_from_secret(
    alias: String,
    secret_id: String,
) -> Result<(), String> {
    let bytes = lfs_core::app::instance()
        .secrets
        .get(&secret_id)
        .ok_or_else(|| format!("secret not found: {secret_id}"))?;
    map_unit(lfs_os_security::secure_key_storage::write(&alias, &bytes).await)
}

pub async fn secure_storage_delete(alias: String) -> Result<(), String> {
    map_unit(lfs_os_security::secure_key_storage::delete(&alias).await)
}

pub async fn secure_storage_read_biometric(
    alias: String,
) -> Result<DbSecureStorageOutcome, String> {
    map_read(lfs_os_security::secure_key_storage::read_biometric(&alias).await)
}

/// SecretRef variant of [`secure_storage_read`]. Reads the OS
/// keychain entry under `alias` and stores the bytes in
/// [`lfs_core::secrets::SecretStore`] under `secret_id` — the
/// bytes never cross the FRB boundary. Returns:
/// * `Ok(true)` when the alias was present and bytes landed under
///   `secret_id`.
/// * `Ok(false)` when the alias was absent or the read returned
///   empty (no SecretStore mutation).
/// * `Err(_)` on platform-level failures.
pub async fn secure_storage_read_to_secret(
    alias: String,
    secret_id: String,
) -> Result<bool, String> {
    match lfs_os_security::secure_key_storage::read(&alias)
        .await
        .map_err(|e| e.to_string())?
    {
        Some(bytes) if !bytes.is_empty() => {
            lfs_core::app::instance().secrets.put(&secret_id, &bytes);
            Ok(true)
        }
        _ => Ok(false),
    }
}

/// SecretRef variant of [`secure_storage_read_biometric`]. Same
/// semantics as [`secure_storage_read_to_secret`] but routes
/// through the biometric-gated keychain entry — the OS surfaces
/// the matching biometric prompt as part of the read.
pub async fn secure_storage_read_biometric_to_secret(
    alias: String,
    secret_id: String,
) -> Result<bool, String> {
    match lfs_os_security::secure_key_storage::read_biometric(&alias)
        .await
        .map_err(|e| e.to_string())?
    {
        Some(bytes) if !bytes.is_empty() => {
            lfs_core::app::instance().secrets.put(&secret_id, &bytes);
            Ok(true)
        }
        _ => Ok(false),
    }
}

/// SecretRef-only biometric write. Pulls the bytes from
/// `SecretStore` under `secret_id` (entry preserved so downstream
/// consumers can still read) and writes the biometric-gated
/// keychain entry. Mirrors the no-FRB-byte-crossing shape of
/// [`secure_storage_write_from_secret`].
pub async fn secure_storage_write_biometric_from_secret(
    alias: String,
    secret_id: String,
) -> Result<(), String> {
    let bytes = lfs_core::app::instance()
        .secrets
        .get(&secret_id)
        .ok_or_else(|| format!("secret not found: {secret_id}"))?;
    map_unit(lfs_os_security::secure_key_storage::write_biometric(&alias, &bytes).await)
}

pub async fn secure_storage_delete_biometric(alias: String) -> Result<(), String> {
    map_unit(lfs_os_security::secure_key_storage::delete_biometric(&alias).await)
}

/// Linux secret-service reachability probe — returns `true` when
/// `org.freedesktop.secrets` is up on the session bus, `false` when
/// the daemon is not installed / not running. Non-Linux hosts return
/// `true` unconditionally; the Dart caller probes those backends via
/// a live keychain round-trip instead. Routes through
/// `lfs_os_security::secure_key_storage::secret_service_reachable`,
/// which uses `secret-service` crate's `SecretService::connect`
/// (zbus session-bus connection) — the same probe libsecret would
/// run before every read/write call.
pub async fn secure_storage_secret_service_reachable() -> bool {
    lfs_os_security::secure_key_storage::secret_service_reachable().await
}
