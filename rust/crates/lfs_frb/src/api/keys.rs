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
        .map_err(|e| crate::api::frb_err::from_core(&e))?;
    Ok(km.into())
}

/// Generate a fresh RSA keypair at [bits] (≥ 2048). Slow — runs on
/// the blocking pool. UI should show a busy indicator.
pub async fn keys_generate_rsa(bits: u32, comment: String) -> Result<KeyMaterial, String> {
    let km =
        tokio::task::spawn_blocking(move || lfs_core::keys::generate_rsa(bits as usize, &comment))
            .await
            .map_err(|e| format!("rsa keygen task: {e}"))?
            .map_err(|e| crate::api::frb_err::from_core(&e))?;
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
    .map_err(|e| crate::api::frb_err::from_core(&e))?;
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
    .map_err(|e| crate::api::frb_err::from_core(&e))?;
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

/// Read `path` and return the OpenSSH-armored PEM if the file
/// looks like a private key. Wraps
/// [`lfs_core::keys::try_read_pem_from_path`] so a Dart caller
/// hands the path in and gets back either the canonical PEM or
/// `None` — no `dart:io` File read, no PPK / PEM bytes on the
/// Dart heap on the silent file-picker path.
///
/// The 32 KiB size ceiling, missing-file fallback, and
/// PPK-without-passphrase route to "not a key" all live Rust-side.
/// FRB encodes `Option<String>` as a nullable string in Dart, so a
/// `null` return cleanly maps to the prior Dart helper's `null`
/// contract.
pub async fn keys_try_read_pem_from_path(path: String) -> Option<String> {
    tokio::task::spawn_blocking(move || {
        let p = std::path::PathBuf::from(path);
        lfs_core::keys::try_read_pem_from_path(&p)
    })
    .await
    .ok()
    .flatten()
}

/// Read `path` as UTF-8 text, capped at 32 KiB. Manual-edit
/// fallback used by the key-manager dialog when
/// [`keys_try_read_pem_from_path`] could not auto-detect a PEM /
/// PPK shape — the user picked a non-standard file but still
/// wants to paste-and-edit the bytes in the dialog. Returns the
/// file content on success; an error string on missing file,
/// oversize, or non-UTF-8 input that the caller surfaces as the
/// "couldn't read file" toast.
pub async fn keys_read_text_for_manual_import(path: String) -> Result<String, String> {
    tokio::task::spawn_blocking(move || {
        let p = std::path::PathBuf::from(path);
        lfs_core::keys::read_text_for_manual_import(&p)
            .map_err(|e| crate::api::frb_err::from_core(&e))
    })
    .await
    .map_err(|e| format!("read text task: {e}"))?
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn is_encrypted_pem_recognises_proc_type_legacy() {
        let pem = "-----BEGIN RSA PRIVATE KEY-----\n\
Proc-Type: 4,ENCRYPTED\n\
DEK-Info: AES-128-CBC,abcdef\n\
\n\
ciphertext...\n\
-----END RSA PRIVATE KEY-----";
        assert!(keys_is_encrypted_pem(pem.to_string()));
    }

    #[test]
    fn is_encrypted_pem_passes_unencrypted_pem() {
        let pem = "-----BEGIN OPENSSH PRIVATE KEY-----\n\
b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAAB\n\
-----END OPENSSH PRIVATE KEY-----";
        assert!(!keys_is_encrypted_pem(pem.to_string()));
    }

    #[test]
    fn normalized_text_fingerprint_returns_empty_for_empty_input() {
        assert_eq!(keys_normalized_text_fingerprint("".into()), "");
        assert_eq!(keys_normalized_text_fingerprint("   \n  \t".into()), "");
    }

    #[test]
    fn normalized_text_fingerprint_normalises_crlf_and_whitespace() {
        // CRLF and trailing whitespace must collapse so the same
        // logical key text gets the same fingerprint regardless of
        // line endings the source file used.
        let lf = keys_normalized_text_fingerprint("hello\nworld\n".into());
        let crlf = keys_normalized_text_fingerprint("hello\r\nworld\r\n".into());
        let trailing = keys_normalized_text_fingerprint("hello\nworld\n   ".into());
        assert!(!lf.is_empty());
        assert_eq!(lf, crlf);
        assert_eq!(lf, trailing);
    }

    #[test]
    fn is_obvious_non_key_filename_filters_known_siblings() {
        assert!(keys_is_obvious_non_key_filename("id_ed25519.pub".into()));
        assert!(keys_is_obvious_non_key_filename("config".into()));
        assert!(keys_is_obvious_non_key_filename("authorized_keys".into()));
        assert!(keys_is_obvious_non_key_filename("known_hosts".into()));
    }

    #[test]
    fn is_obvious_non_key_filename_passes_actual_keys() {
        assert!(!keys_is_obvious_non_key_filename("id_ed25519".into()));
        assert!(!keys_is_obvious_non_key_filename("id_rsa".into()));
        assert!(!keys_is_obvious_non_key_filename("my_deploy_key".into()));
    }

    #[test]
    fn looks_like_ppk_recognises_v2_and_v3_headers() {
        assert!(keys_looks_like_ppk(
            "PuTTY-User-Key-File-2: ssh-ed25519\n".into()
        ));
        assert!(keys_looks_like_ppk(
            "PuTTY-User-Key-File-3: ssh-ed25519\n".into()
        ));
    }

    #[test]
    fn looks_like_ppk_passes_pem_and_other_text() {
        assert!(!keys_looks_like_ppk(
            "-----BEGIN RSA PRIVATE KEY-----\n".into()
        ));
        assert!(!keys_looks_like_ppk("plain text".into()));
        assert!(!keys_looks_like_ppk("".into()));
    }
}
