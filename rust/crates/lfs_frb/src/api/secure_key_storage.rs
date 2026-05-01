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

pub async fn secure_storage_delete(alias: String) -> Result<(), String> {
    map_unit(lfs_os_security::secure_key_storage::delete(&alias).await)
}

pub async fn secure_storage_read_biometric(
    alias: String,
) -> Result<DbSecureStorageOutcome, String> {
    map_read(lfs_os_security::secure_key_storage::read_biometric(&alias).await)
}

pub async fn secure_storage_write_biometric(alias: String, value: Vec<u8>) -> Result<(), String> {
    map_unit(lfs_os_security::secure_key_storage::write_biometric(&alias, &value).await)
}

pub async fn secure_storage_delete_biometric(alias: String) -> Result<(), String> {
    map_unit(lfs_os_security::secure_key_storage::delete_biometric(&alias).await)
}
