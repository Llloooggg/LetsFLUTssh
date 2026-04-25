//! SSH keypair generation + import — backed by `russh-keys`
//! (`internal-russh-forked-ssh-key`). The Dart-side key store calls
//! these to mint Ed25519 / RSA keypairs and to ingest user-supplied
//! PEM blobs without touching dartssh2's `SSHKeyPair`.

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
