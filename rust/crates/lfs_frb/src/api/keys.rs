//! FRB adapter for `lfs_core::keys` — keypair generation + import.
//!
//! Surfaces three functions to Dart: generate Ed25519, generate RSA,
//! and import an OpenSSH PEM. Each returns `KeyMaterial` (armored
//! private key + OpenSSH public-key string + algorithm tag).
//! Consumed by `lib/core/security/key_store.dart`.

use crate::api::frb_err;
use std::collections::HashMap;

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
        .map_err(|e| frb_err::wire(frb_err::kind::GENERIC, &format!("ed25519 keygen task: {e}")))?
        .map_err(|e| crate::api::frb_err::from_core(&e))?;
    Ok(km.into())
}

/// Generate a fresh RSA keypair at [bits] (≥ 2048). Slow — runs on
/// the blocking pool. UI should show a busy indicator.
pub async fn keys_generate_rsa(bits: u32, comment: String) -> Result<KeyMaterial, String> {
    let km =
        tokio::task::spawn_blocking(move || lfs_core::keys::generate_rsa(bits as usize, &comment))
            .await
            .map_err(|e| frb_err::wire(frb_err::kind::GENERIC, &format!("rsa keygen task: {e}")))?
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
    .map_err(|e| frb_err::wire(frb_err::kind::GENERIC, &format!("import task: {e}")))?
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
    .map_err(|e| frb_err::wire(frb_err::kind::GENERIC, &format!("import-ppk task: {e}")))?
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
/// `null` return maps cleanly to the caller's nullable contract.
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
    .map_err(|e| frb_err::wire(frb_err::kind::GENERIC, &format!("read text task: {e}")))?
}

/// Read `path` as raw bytes for OpenSSH cert import, capped at
/// 16 KiB. The Dart key-manager dialog wired this to replace the
/// `File(path).readAsBytes()` shape — the size ceiling, regular-
/// file gate, and I/O error envelope now live Rust-side. Returned
/// bytes feed `keys_parse_openssh_cert` + `keys_cert_matches_key`
/// without crossing the FRB boundary a second time.
pub async fn keys_read_cert_bytes_for_import(path: String) -> Result<Vec<u8>, String> {
    tokio::task::spawn_blocking(move || {
        let p = std::path::PathBuf::from(path);
        lfs_core::keys::read_cert_bytes_for_import(&p)
            .map_err(|e| crate::api::frb_err::from_core(&e))
    })
    .await
    .map_err(|e| frb_err::wire(frb_err::kind::GENERIC, &format!("read cert task: {e}")))?
}

/// FRB mirror of [`lfs_core::keys::SkKeyMetadata`]. Returned by
/// [`keys_parse_sk_private_key`] to the Dart key-manager when the
/// user imports an OpenSSH `sk-*` private key file
/// (`id_ed25519_sk`, `id_ecdsa_sk`). Carries the credential id,
/// application string, algorithm short tag, single-line public-key
/// body, and the user-verification flag — every field the connect
/// path needs to authenticate against the hardware authenticator.
#[derive(Debug, Clone)]
pub struct DbSkKeyMetadata {
    pub credential_id: Vec<u8>,
    pub application: String,
    pub key_type: String,
    pub public_openssh: String,
    pub has_user_verification: bool,
}

impl From<lfs_core::keys::SkKeyMetadata> for DbSkKeyMetadata {
    fn from(m: lfs_core::keys::SkKeyMetadata) -> Self {
        Self {
            credential_id: m.credential_id,
            application: m.application,
            key_type: m.key_type,
            public_openssh: m.public_openssh,
            has_user_verification: m.has_user_verification,
        }
    }
}

/// Parse an OpenSSH-armored `sk-*` private key file and surface
/// the metadata the connect path needs. Sync — the parse is a
/// single OpenSSH PEM decode + base64 walk, no I/O.
#[flutter_rust_bridge::frb(sync)]
pub fn keys_parse_sk_private_key(pem: String) -> Result<DbSkKeyMetadata, String> {
    lfs_core::keys::parse_sk_private_key(&pem)
        .map(DbSkKeyMetadata::from)
        .map_err(|e| crate::api::frb_err::from_core(&e))
}

/// FRB mirror of [`lfs_core::keys::CertSummary`]. The Dart key-
/// manager UI consumes this to render the principals chip list,
/// validity row, expired badge, and critical-options summary on
/// the row paired with a stored SSH key.
#[derive(Debug, Clone)]
pub struct DbCertSummary {
    pub principals: Vec<String>,
    pub valid_after_unix: i64,
    pub valid_before_unix: i64,
    /// `force-command`, `source-address`, etc. — opaque key/value
    /// pairs the server enforces. `HashMap` rather than a
    /// preserved-order list because FRB has no `BTreeMap` codec;
    /// Dart iterates by key for display so order does not matter.
    pub critical_options: HashMap<String, String>,
    pub fingerprint: String,
}

impl From<lfs_core::keys::CertSummary> for DbCertSummary {
    fn from(s: lfs_core::keys::CertSummary) -> Self {
        let mut critical_options = HashMap::with_capacity(s.critical_options.len());
        for (k, v) in s.critical_options {
            critical_options.insert(k, v);
        }
        Self {
            principals: s.principals,
            valid_after_unix: s.valid_after_unix,
            valid_before_unix: s.valid_before_unix,
            critical_options,
            fingerprint: s.fingerprint,
        }
    }
}

/// Parse an OpenSSH-format certificate (`*-cert.pub` /
/// armored `-----BEGIN OPENSSH CERTIFICATE-----`) and return a
/// typed summary the Dart key-manager UI can render. Sync — the
/// parse is a single base64 decode + ssh-key crate walk; the FRB
/// hop overhead would dwarf the actual work and the importer fans
/// this out across every selected cert file during a bulk import.
///
/// Returns a localizable error string on parse failure — the Dart
/// side surfaces it as the `errCertParse` toast.
#[flutter_rust_bridge::frb(sync)]
pub fn keys_parse_openssh_cert(bytes: Vec<u8>) -> Result<DbCertSummary, String> {
    lfs_core::keys::parse_openssh_cert(&bytes)
        .map(DbCertSummary::from)
        .map_err(|e| crate::api::frb_err::from_core(&e))
}

/// Check that the OpenSSH certificate in `cert_bytes` is signed for
/// the public key in `pubkey_openssh`. Routes through
/// [`lfs_core::keys::cert_matches_key`] — SHA-256 fingerprint compare
/// over the SSH wire-format public-key blob, so trailing comments /
/// CRLF / extra whitespace in the user-supplied pubkey text are
/// stripped before the check.
///
/// `Ok(false)` is the user-visible "wrong key" branch; the Dart
/// import flow surfaces it as the `errCertPairFingerprintMismatch`
/// toast and refuses to persist. `Err(String)` only on parse failure
/// (cert / pubkey malformed) — Dart routes to `errCertParse`.
#[flutter_rust_bridge::frb(sync)]
pub fn keys_cert_matches_key(cert_bytes: Vec<u8>, pubkey_openssh: String) -> Result<bool, String> {
    lfs_core::keys::cert_matches_key(&cert_bytes, &pubkey_openssh)
        .map_err(|e| crate::api::frb_err::from_core(&e))
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

    const ED25519_CERT_FIXTURE: &str = "ssh-ed25519-cert-v01@openssh.com AAAAIHNzaC1lZDI1NTE5LWNlcnQtdjAxQG9wZW5zc2guY29tAAAAIAYkJPGaYen7NK8MwZwWmNAyRaFNsc86AU9NObU2cM2uAAAAILM+rvN+ot98qgEN796jTiQfZfG1KaT0PtFDJ/XFSqtiAAAAAAAAAAAAAAACAAAAB2VkMjU1MTkAAAAUAAAAEGhvc3QuZXhhbXBsZS5jb20AAAAAYkx3NwAAAAB8DuY3AAAAAAAAAAAAAAAAAAAAMwAAAAtzc2gtZWQyNTUxOQAAACCzPq7zfqLffKoBDe/eo04kH2XxtSmk9D7RQyf1xUqrYgAAAFMAAAALc3NoLWVkMjU1MTkAAABApVXBNiYPlPoa1BYH5G4NP9XtjTMZlm7HO5GdbLSvvAw5Vdob7Ka+23hB7isJKHYtzFGGSKXAqxp/Zi8REbCaAw== user@example.com";

    #[test]
    fn parse_openssh_cert_round_trips_to_summary() {
        let summary = keys_parse_openssh_cert(ED25519_CERT_FIXTURE.as_bytes().to_vec())
            .expect("ED25519_CERT_FIXTURE must parse as a valid OpenSSH cert");
        assert_eq!(summary.principals, vec!["host.example.com".to_string()]);
        assert!(summary.fingerprint.starts_with("SHA256:"));
        assert!(summary.valid_before_unix > summary.valid_after_unix);
    }

    #[test]
    fn parse_openssh_cert_surfaces_localizable_error_on_garbage() {
        let result = keys_parse_openssh_cert(b"not-a-cert".to_vec());
        assert!(result.is_err());
    }
}
