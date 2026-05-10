//! FRB adapter for `lfs_os_security::secure_key_storage`. Every
//! supported platform (Linux / macOS / iOS / Windows / Android)
//! routes through here — the Android JNI bridge to
//! AndroidKeyStore lives in `lfs_os_security::android::keystore`,
//! the cfg-gated dispatch table in `secure_key_storage.rs` picks
//! the right backend per `target_os`.

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
    res.map_err(|e| crate::api::frb_err::wire_str(crate::api::frb_err::kind::VAULT, &e))
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
/// downstream consumer (e.g. `db_init_from_secret` for SQLCipher
/// open or `db_rekey_from_secret` for rekey) has had its turn.
/// Returns `Err("secret not found: …")` when the id is absent from
/// the store.
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
        .map_err(|e| crate::api::frb_err::wire_str(crate::api::frb_err::kind::VAULT, &e))?
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
        .map_err(|e| crate::api::frb_err::wire_str(crate::api::frb_err::kind::VAULT, &e))?
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

#[cfg(test)]
mod tests {
    use super::*;

    // The read / write / delete / biometric endpoints route through
    // `lfs_os_security::secure_key_storage` — Apple Keychain on
    // macOS/iOS, Credential Manager on Windows, libsecret on Linux,
    // AndroidKeyStore on Android; covered by the per-platform
    // integration suites + manual smoke tests on the user's release
    // process. The standalone tests below pin the wire-shape `From`
    // mapping + the `SecretRef` missing-id contract.

    #[test]
    fn db_secure_storage_outcome_carries_bytes_through() {
        let v = DbSecureStorageOutcome::Found(vec![0xAB, 0xCD]);
        match v {
            DbSecureStorageOutcome::Found(bytes) => assert_eq!(bytes, vec![0xAB, 0xCD]),
            DbSecureStorageOutcome::NotFound => panic!("expected Found"),
        }
    }

    #[test]
    fn db_secure_storage_outcome_not_found_round_trip() {
        let v = DbSecureStorageOutcome::NotFound;
        // Pin the no-payload variant — caller `match`es on
        // NotFound to render the "no value stored" branch in the
        // Settings UI.
        match v {
            DbSecureStorageOutcome::NotFound => (),
            DbSecureStorageOutcome::Found(_) => panic!("expected NotFound"),
        }
    }

    #[tokio::test]
    async fn write_from_secret_returns_err_for_missing_secret_id() {
        // `secrets_get(id)` returns None for an unknown id; the shim
        // surfaces that as `Err("secret not found: <id>")` rather
        // than panic. Pin the contract so the Dart caller's error
        // handling stays load-bearing.
        let _ = lfs_core::app::init();
        let res = secure_storage_write_from_secret(
            "api-sks-test-alias".into(),
            "api-sks-test-ghost-id".into(),
        )
        .await;
        assert!(res.is_err());
        let msg = res.unwrap_err();
        assert!(
            msg.contains("secret not found"),
            "expected 'secret not found', got {msg}"
        );
    }

    #[tokio::test]
    async fn write_biometric_from_secret_returns_err_for_missing_secret_id() {
        let _ = lfs_core::app::init();
        let res = secure_storage_write_biometric_from_secret(
            "api-sks-test-alias".into(),
            "api-sks-test-ghost-id".into(),
        )
        .await;
        assert!(res.is_err());
        assert!(res.unwrap_err().contains("secret not found"));
    }
}
