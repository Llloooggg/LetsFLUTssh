//! FRB adapter for `lfs_core::keys` — keypair generation + import.
//!
//! Surfaces three functions to Dart: generate Ed25519, generate RSA,
//! and import an OpenSSH PEM. Each returns `KeyMaterial` (armored
//! private key + OpenSSH public-key string + algorithm tag).
//! Consumed by `lib/core/security/key_store.dart`.

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

/// Cheap pre-check: does this PEM body look encrypted?
///
/// Returns `true` when the PEM carries one of the standard
/// "encrypted" markers — legacy `Proc-Type: 4,ENCRYPTED`,
/// PKCS#8 encrypted armor, or an OpenSSH `openssh-key-v1` body
/// whose KDF-name field is anything other than `none`. Sync
/// because the work is a couple of `contains` checks plus, for
/// the OpenSSH case, a base64 decode of the (small) armored body
/// — well under a millisecond. The async hop overhead would dwarf
/// the actual work and the importer fans this out across every
/// IdentityFile in the user's `~/.ssh/config`.
#[flutter_rust_bridge::frb(sync)]
pub fn keys_is_encrypted_pem(pem: String) -> bool {
    lfs_core::keys::is_encrypted_pem(&pem)
}

/// Content-addressable fingerprint of a key text (CRLF→LF + trim
/// + SHA-256 hex). Used by the Dart key store as the M2M dedup id
/// — distinct from the OpenSSH host-key SHA256 base64 shape that
/// `ssh_format_host_key_fingerprint` returns. Returns the empty
/// string for empty / whitespace-only input.
#[flutter_rust_bridge::frb(sync)]
pub fn keys_normalized_text_fingerprint(text: String) -> String {
    lfs_core::keys::normalized_text_fingerprint(&text)
}

/// True when [`filename`] is "obviously not a private key" by
/// shape — `*.pub`, `config`, `authorized_keys*`, `known_hosts*`
/// siblings of a `~/.ssh` walk. Used by the SSH dir scanner to
/// skip the file-read + parse round-trip on entries that cannot
/// possibly be keys.
#[flutter_rust_bridge::frb(sync)]
pub fn keys_is_obvious_non_key_filename(filename: String) -> bool {
    lfs_core::keys::is_obvious_non_key_filename(&filename)
}

/// True when [`text`] looks like a PuTTY PPK file (v2 or v3
/// header). Cheap shape sniff used by the import dispatcher to
/// route `.ppk` content to the PPK parser before trying PEM.
#[flutter_rust_bridge::frb(sync)]
pub fn keys_looks_like_ppk(text: String) -> bool {
    lfs_core::keys::looks_like_ppk(&text)
}
