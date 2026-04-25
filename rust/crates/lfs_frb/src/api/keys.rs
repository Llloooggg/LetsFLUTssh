//! FRB adapter for `lfs_core::keys` — keypair generation + import.
//!
//! Surfaces three functions to Dart: generate Ed25519, generate RSA,
//! and import an OpenSSH PEM. Each returns the same shape: armored
//! private key, OpenSSH public-key string, and the algorithm tag.
//! Used by `lib/core/security/key_store.dart` to mint/import keys
//! without depending on dartssh2's `SSHKeyPair` or `pinenacl`.

#[derive(Debug, Clone)]
pub struct KeyMaterial {
    pub private_pem: String,
    pub public_openssh: String,
    pub key_type: String,
}

impl From<lfs_core::keys::KeyMaterial> for KeyMaterial {
    fn from(km: lfs_core::keys::KeyMaterial) -> Self {
        Self {
            private_pem: km.private_pem,
            public_openssh: km.public_openssh,
            key_type: km.key_type,
        }
    }
}

/// Generate a fresh Ed25519 keypair tagged with [comment]
/// (the trailing comment in `authorized_keys` format).
pub async fn keys_generate_ed25519(comment: String) -> Result<KeyMaterial, String> {
    // Run on the blocking pool — keygen is CPU-bound and we don't
    // want to stall the FRB tokio worker thread for the duration.
    let km = tokio::task::spawn_blocking(move || lfs_core::keys::generate_ed25519(&comment))
        .await
        .map_err(|e| format!("ed25519 keygen task: {e}"))?
        .map_err(|e| e.to_string())?;
    Ok(km.into())
}

/// Generate a fresh RSA keypair at [bits] (≥ 2048). Slow — runs on
/// the blocking pool. UI should show a busy indicator.
pub async fn keys_generate_rsa(bits: u32, comment: String) -> Result<KeyMaterial, String> {
    let km =
        tokio::task::spawn_blocking(move || lfs_core::keys::generate_rsa(bits as usize, &comment))
            .await
            .map_err(|e| format!("rsa keygen task: {e}"))?
            .map_err(|e| e.to_string())?;
    Ok(km.into())
}

/// Parse + re-encode an OpenSSH PEM-armored private key. `passphrase`
/// is required iff the key is encrypted. Returns the canonical form +
/// matching public key string.
pub async fn keys_import_openssh(
    pem: String,
    passphrase: Option<String>,
    comment: String,
) -> Result<KeyMaterial, String> {
    let km = tokio::task::spawn_blocking(move || {
        lfs_core::keys::import_openssh(&pem, passphrase.as_deref(), &comment)
    })
    .await
    .map_err(|e| format!("import task: {e}"))?
    .map_err(|e| e.to_string())?;
    Ok(km.into())
}

/// Parse a PuTTY .ppk (v2 or v3) file and re-encode in OpenSSH
/// format. `passphrase` is required iff the file is encrypted.
/// Returns the canonical form + matching public key string —
/// callers can store this in the key manager exactly the way they
/// store an OpenSSH PEM.
pub async fn keys_import_ppk(
    ppk_text: String,
    passphrase: Option<String>,
    comment: String,
) -> Result<KeyMaterial, String> {
    let km = tokio::task::spawn_blocking(move || {
        lfs_core::keys::import_ppk(&ppk_text, passphrase.as_deref(), &comment)
    })
    .await
    .map_err(|e| format!("import-ppk task: {e}"))?
    .map_err(|e| e.to_string())?;
    Ok(km.into())
}
