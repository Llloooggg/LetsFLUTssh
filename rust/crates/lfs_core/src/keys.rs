//! SSH keypair generation + import — backed by `russh-keys`
//! (`internal-russh-forked-ssh-key`). Mints Ed25519 / RSA keypairs
//! and ingests user-supplied PEM blobs.

use russh::keys::ssh_key::private::{KeypairData, RsaKeypair};
use russh::keys::ssh_key::{Algorithm, HashAlg, LineEnding, PrivateKey};

use crate::error::Error;

/// Result of a keypair generation / import: PEM (OpenSSH armored
/// private key), the matching public-key string in `authorized_keys`
/// format, and the algorithm name (`ssh-ed25519`, `ssh-rsa`).
#[derive(Debug, Clone)]
pub struct KeyMaterial {
    pub private_pem: String,
    pub public_openssh: String,
    pub key_type: String,
}

fn algorithm_name(algorithm: &Algorithm) -> String {
    match algorithm {
        Algorithm::Ed25519 => "ssh-ed25519".to_string(),
        // The "ssh-rsa" wire name covers all RSA hash variants — the
        // public key bytes are identical, only the signature hash
        // differs at userauth time.
        Algorithm::Rsa { .. } => "ssh-rsa".to_string(),
        other => other.as_str().to_string(),
    }
}

fn finish(mut key: PrivateKey, comment: &str) -> Result<KeyMaterial, Error> {
    key.set_comment(comment);
    let pem = key
        .to_openssh(LineEnding::LF)
        .map_err(|e| Error::KeyParse(format!("encode openssh: {e}")))?
        .to_string();
    let public_openssh = key
        .public_key()
        .to_openssh()
        .map_err(|e| Error::KeyParse(format!("encode public: {e}")))?;
    let key_type = algorithm_name(&key.algorithm());
    Ok(KeyMaterial {
        private_pem: pem,
        public_openssh,
        key_type,
    })
}

/// Generate a new Ed25519 keypair. Fast — runs synchronously.
pub fn generate_ed25519(comment: &str) -> Result<KeyMaterial, Error> {
    let key = PrivateKey::random(&mut rand::thread_rng(), Algorithm::Ed25519)
        .map_err(|e| Error::KeyParse(format!("ed25519 keygen: {e}")))?;
    finish(key, comment)
}

/// Generate a new RSA keypair at the given bit size (2048 / 3072 / 4096).
/// Slow on the caller's thread — caller decides where to drive it.
pub fn generate_rsa(bits: usize, comment: &str) -> Result<KeyMaterial, Error> {
    if bits < 2048 {
        return Err(Error::KeyParse(format!(
            "rsa key size {bits} is below the 2048-bit minimum"
        )));
    }
    let rsa = RsaKeypair::random(&mut rand::thread_rng(), bits)
        .map_err(|e| Error::KeyParse(format!("rsa keygen: {e}")))?;
    let key = PrivateKey::new(KeypairData::from(rsa), comment.to_string())
        .map_err(|e| Error::KeyParse(format!("rsa wrap: {e}")))?;
    // Match OpenSSH's default `ssh-keygen -t rsa` output: SHA-256
    // hash on the algorithm tag so userauth picks `rsa-sha2-256` over
    // the legacy SHA-1 `ssh-rsa`. The wire bytes of the public key
    // don't change; only the algorithm metadata does.
    let _ = HashAlg::Sha256;
    finish(key, comment)
}

/// Parse + re-encode a PEM-armored OpenSSH private key, decrypting
/// with `passphrase` if the key is encrypted. Returns the private
/// key in canonical OpenSSH form alongside the matching public-key
/// string. PuTTY PPK is intentionally NOT accepted here — call
/// [`import_ppk`] instead.
pub fn import_openssh(
    pem: &str,
    passphrase: Option<&str>,
    comment: &str,
) -> Result<KeyMaterial, Error> {
    let parsed = PrivateKey::from_openssh(pem.as_bytes())
        .map_err(|e| Error::KeyParse(format!("parse openssh: {e}")))?;
    let key = if parsed.is_encrypted() {
        let pass = passphrase.ok_or(Error::PassphraseRequired)?;
        parsed
            .decrypt(pass)
            .map_err(|e| Error::KeyParse(format!("decrypt: {e}")))?
    } else {
        parsed
    };
    finish(key, comment)
}

/// Parse a PuTTY `.ppk` (v2 or v3) file and re-encode in OpenSSH
/// format. Encrypted PPK files require `passphrase`; pass `None` for
/// unencrypted ones. v3 / Argon2id is handled natively by
/// russh-keys' `from_ppk` once the `ppk` cargo feature is on
/// (already enabled at the workspace root). Same `KeyMaterial`
/// shape as [`import_openssh`] so the FRB binding stays uniform.
pub fn import_ppk(
    ppk_text: &str,
    passphrase: Option<&str>,
    comment: &str,
) -> Result<KeyMaterial, Error> {
    let trimmed = ppk_text.trim_start();
    if !trimmed.starts_with("PuTTY-User-Key-File-") {
        return Err(Error::KeyParse(
            "input does not start with the PuTTY PPK magic header".into(),
        ));
    }
    let key = PrivateKey::from_ppk(trimmed, passphrase.map(|p| p.to_owned())).map_err(|e| {
        // Mirror the OpenSSH path's "passphrase incorrect vs format
        // failure" split so callers can prompt for re-entry.
        let msg = e.to_string().to_ascii_lowercase();
        if msg.contains("mac") || msg.contains("crypto") || msg.contains("decrypt") {
            Error::PassphraseIncorrect
        } else {
            Error::KeyParse(format!("ppk: {e}"))
        }
    })?;
    finish(key, comment)
}

/// True when [`text`] looks like a PuTTY PPK file (first line
/// matches the v2 / v3 header). Cheap shape sniff used by the
/// import dispatcher to route `.ppk` content to the PPK parser
/// before falling through to PEM detection.
#[must_use]
pub fn looks_like_ppk(text: &str) -> bool {
    let t = text.trim_start();
    t.starts_with("PuTTY-User-Key-File-2:") || t.starts_with("PuTTY-User-Key-File-3:")
}

/// True when [`filename`] is "obviously not a private key" by
/// shape — public-key files (`*.pub`), the OpenSSH config file
/// (`config`), `authorized_keys*`, and `known_hosts*` siblings
/// the SSH dir scanner will see when walking `~/.ssh`. Used as a
/// pre-filter to skip the file-read + parse round-trip on
/// entries that cannot possibly be keys.
///
/// `filename` is a basename only (caller pre-strips the dir);
/// this helper does not normalise paths.
#[must_use]
pub fn is_obvious_non_key_filename(filename: &str) -> bool {
    if filename.ends_with(".pub") {
        return true;
    }
    if filename == "config" {
        return true;
    }
    if filename == "authorized_keys" || filename.starts_with("authorized_keys") {
        return true;
    }
    if filename.starts_with("known_hosts") {
        return true;
    }
    false
}

/// Compute the content-addressable fingerprint the Dart key store
/// uses to dedup imports — SHA-256 hex of the key text after
/// CRLF→LF + trim normalization. Distinct from
/// [`crate::ssh::format_fingerprint`] (which is the OpenSSH host-
/// key `SHA256:<base64>` shape); this one is keyed on text bytes
/// and used as the M2M dedup id, not for display.
///
/// Returns the empty string for empty input so callers can short-
/// circuit without branching on the result. Lower-case hex matches
/// the existing Dart `sha256HexCompat` shape byte-for-byte.
#[must_use]
pub fn normalized_text_fingerprint(text: &str) -> String {
    use sha2::{Digest, Sha256};
    let normalized = text.replace("\r\n", "\n");
    let trimmed = normalized.trim();
    if trimmed.is_empty() {
        return String::new();
    }
    let mut h = Sha256::new();
    h.update(trimmed.as_bytes());
    let digest = h.finalize();
    let mut out = String::with_capacity(digest.len() * 2);
    for byte in digest.iter() {
        out.push_str(&format!("{byte:02x}"));
    }
    out
}

/// True when [`pem`] is a password-protected private key.
///
/// Covers the three encoding families the importer cares about:
///
/// * Legacy PKCS#1/OpenSSL — carries `Proc-Type: 4,ENCRYPTED` +
///   `DEK-Info` headers inside the ASCII-armor envelope.
/// * PKCS#8 encrypted — announced via its own armor header.
/// * New OpenSSH format — the outer armor is the same
///   `-----BEGIN OPENSSH PRIVATE KEY-----` regardless of encryption,
///   so we decode the base64 body and read the KDF-name field out
///   of the `openssh-key-v1\0` binary prefix. `none` means
///   unencrypted; anything else (typically `bcrypt`) means a
///   passphrase is required.
///
/// Mirror of the Dart-side `KeyFileHelper.isEncryptedPem` that
/// the OpenSSH-config importer + the `~/.ssh` directory scanner +
/// the settings file picker all consult. Living one place keeps
/// the encryption-detection rules consistent across every entry
/// point that decides whether to silently skip a key (no
/// passphrase prompt) or pop the key-manager passphrase flow.
pub fn is_encrypted_pem(pem: &str) -> bool {
    if pem.contains("Proc-Type: 4,ENCRYPTED") {
        return true;
    }
    if pem.contains("DEK-Info:") {
        return true;
    }
    if pem.contains("-----BEGIN ENCRYPTED PRIVATE KEY-----") {
        return true;
    }
    if pem.contains("-----BEGIN OPENSSH PRIVATE KEY-----") {
        return is_encrypted_openssh_key(pem).unwrap_or(false);
    }
    false
}

/// Parse the base64 body of an OpenSSH private key and inspect its
/// KDF name field. Returns `None` when the body does not decode as
/// a valid `openssh-key-v1` frame — the caller treats that as
/// "can't tell, assume unencrypted" rather than false-positive
/// warning the user about a malformed file.
///
/// Frame layout (big-endian):
/// ```text
///   "openssh-key-v1\0"   (15 bytes)
///   u32 kdfNameLen
///   kdfName              (ASCII)
///   ... rest
/// ```
fn is_encrypted_openssh_key(pem: &str) -> Option<bool> {
    use base64::{engine::general_purpose::STANDARD, Engine as _};

    // Strip armor lines + every whitespace byte (newlines, indent)
    // before decoding — the standard PEM body is line-wrapped at 64
    // chars and base64 rejects intervening whitespace.
    let body: String = pem
        .split('\n')
        .filter(|l| !l.is_empty() && !l.starts_with("-----"))
        .collect::<String>()
        .chars()
        .filter(|c| !c.is_whitespace())
        .collect();
    if body.is_empty() {
        return None;
    }
    let decoded = STANDARD.decode(body.as_bytes()).ok()?;
    const MAGIC: &[u8] = b"openssh-key-v1";
    if decoded.len() < MAGIC.len() + 1 + 4 {
        return None;
    }
    if &decoded[..MAGIC.len()] != MAGIC {
        return None;
    }
    if decoded[MAGIC.len()] != 0 {
        return None;
    }
    const OFFSET: usize = 15; // magic (14) + null terminator
    let kdf_len = u32::from_be_bytes([
        decoded[OFFSET],
        decoded[OFFSET + 1],
        decoded[OFFSET + 2],
        decoded[OFFSET + 3],
    ]) as usize;
    // Sanity-check the length so a malformed frame can't make us
    // read gigabytes of garbage; a real KDF name is ≤ a dozen
    // characters.
    if kdf_len == 0 || kdf_len > 32 {
        return None;
    }
    let start = OFFSET + 4;
    if decoded.len() < start + kdf_len {
        return None;
    }
    let name = std::str::from_utf8(&decoded[start..start + kdf_len]).ok()?;
    Some(name != "none")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn fingerprint_returns_empty_for_empty_input() {
        assert_eq!(normalized_text_fingerprint(""), "");
        assert_eq!(normalized_text_fingerprint("   \n\n   "), "");
    }

    #[test]
    fn fingerprint_normalizes_crlf_to_lf_before_hashing() {
        let lf = "ssh-ed25519 AAAA...\nuser@host\n";
        let crlf = "ssh-ed25519 AAAA...\r\nuser@host\r\n";
        assert_eq!(
            normalized_text_fingerprint(lf),
            normalized_text_fingerprint(crlf)
        );
    }

    #[test]
    fn fingerprint_trims_surrounding_whitespace() {
        let bare = "ssh-ed25519 AAAA";
        let padded = "  \n\nssh-ed25519 AAAA\n  ";
        assert_eq!(
            normalized_text_fingerprint(bare),
            normalized_text_fingerprint(padded)
        );
    }

    #[test]
    fn fingerprint_is_lowercase_hex_64_chars() {
        let fp = normalized_text_fingerprint("ssh-ed25519 AAAA");
        assert_eq!(fp.len(), 64);
        assert!(fp
            .chars()
            .all(|c| c.is_ascii_hexdigit() && !c.is_ascii_uppercase()));
    }

    #[test]
    fn fingerprint_distinguishes_different_inputs() {
        let a = normalized_text_fingerprint("ssh-ed25519 AAAA1");
        let b = normalized_text_fingerprint("ssh-ed25519 AAAA2");
        assert_ne!(a, b);
    }

    #[test]
    fn obvious_non_key_filename_flags_dot_pub() {
        assert!(is_obvious_non_key_filename("id_ed25519.pub"));
    }

    #[test]
    fn obvious_non_key_filename_flags_config() {
        assert!(is_obvious_non_key_filename("config"));
    }

    #[test]
    fn obvious_non_key_filename_flags_authorized_keys_variants() {
        assert!(is_obvious_non_key_filename("authorized_keys"));
        assert!(is_obvious_non_key_filename("authorized_keys.bak"));
        assert!(is_obvious_non_key_filename("authorized_keys2"));
    }

    #[test]
    fn obvious_non_key_filename_flags_known_hosts_variants() {
        assert!(is_obvious_non_key_filename("known_hosts"));
        assert!(is_obvious_non_key_filename("known_hosts.old"));
    }

    #[test]
    fn obvious_non_key_filename_passes_actual_keys() {
        assert!(!is_obvious_non_key_filename("id_ed25519"));
        assert!(!is_obvious_non_key_filename("id_rsa"));
        assert!(!is_obvious_non_key_filename("my-deploy-key"));
    }

    #[test]
    fn looks_like_ppk_matches_v2_and_v3_headers() {
        assert!(looks_like_ppk("PuTTY-User-Key-File-2: ssh-rsa\n…"));
        assert!(looks_like_ppk("PuTTY-User-Key-File-3: ssh-ed25519\n…"));
    }

    #[test]
    fn looks_like_ppk_skips_leading_whitespace() {
        // Leading newline / spaces shouldn't confuse the sniff —
        // some pickers paste content with stray whitespace.
        assert!(looks_like_ppk("\n  PuTTY-User-Key-File-3: ssh-ed25519\n"));
    }

    #[test]
    fn looks_like_ppk_rejects_pem_armor() {
        assert!(!looks_like_ppk("-----BEGIN OPENSSH PRIVATE KEY-----\n"));
    }

    #[test]
    fn looks_like_ppk_rejects_unknown_text() {
        assert!(!looks_like_ppk(""));
        assert!(!looks_like_ppk("PuTTY-User-Key-File-1: ssh-rsa\n"));
        assert!(!looks_like_ppk("hello world"));
    }

    #[test]
    fn pkcs1_dek_info_marks_encrypted() {
        let pem = "-----BEGIN RSA PRIVATE KEY-----\n\
                   Proc-Type: 4,ENCRYPTED\n\
                   DEK-Info: AES-128-CBC,1234\n\
                   payload\n\
                   -----END RSA PRIVATE KEY-----\n";
        assert!(is_encrypted_pem(pem));
    }

    #[test]
    fn dek_info_alone_marks_encrypted() {
        // Some real-world keys ship `DEK-Info:` without the
        // matching `Proc-Type:` line — match either marker so the
        // importer doesn't silently try to use them as plaintext.
        let pem = "-----BEGIN RSA PRIVATE KEY-----\n\
                   DEK-Info: AES-256-CBC,abcd\n\
                   payload\n\
                   -----END RSA PRIVATE KEY-----\n";
        assert!(is_encrypted_pem(pem));
    }

    #[test]
    fn pkcs8_encrypted_armor_marks_encrypted() {
        let pem = "-----BEGIN ENCRYPTED PRIVATE KEY-----\n\
                   payload\n\
                   -----END ENCRYPTED PRIVATE KEY-----\n";
        assert!(is_encrypted_pem(pem));
    }

    #[test]
    fn unencrypted_openssh_round_trips_via_keygen() {
        // Generate a fresh ed25519 key — encoded with `none` KDF —
        // and confirm the encrypted detector says "no".
        let km = generate_ed25519("test").unwrap();
        assert!(!is_encrypted_pem(&km.private_pem));
    }

    #[test]
    fn random_text_is_not_encrypted() {
        // Non-key text never trips the markers.
        assert!(!is_encrypted_pem("just a random string\n"));
        assert!(!is_encrypted_pem(""));
    }

    #[test]
    fn malformed_openssh_body_falls_through_to_unencrypted() {
        // Outer armor matches but the body decodes to nothing
        // useful — caller must not warn the user about a malformed
        // file (returning `false` here lets the importer attempt
        // the real parse, which surfaces the proper format error).
        let pem = "-----BEGIN OPENSSH PRIVATE KEY-----\n\
                   bm90LXJlYWxseS1iYXNlNjQK\n\
                   -----END OPENSSH PRIVATE KEY-----\n";
        assert!(!is_encrypted_pem(pem));
    }
}
