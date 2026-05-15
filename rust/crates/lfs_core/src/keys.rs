//! SSH keypair generation + import — backed by `russh-keys`
//! (`internal-russh-forked-ssh-key`). Mints Ed25519 / RSA keypairs
//! and ingests user-supplied PEM blobs.

use std::collections::BTreeMap;
use std::sync::Arc;

use russh::keys::ssh_key::private::{KeypairData, RsaKeypair};
use russh::keys::ssh_key::{Algorithm, HashAlg, LineEnding, PrivateKey, PublicKey};
use russh::keys::Certificate;

use crate::app::AppState;
use crate::bus::Event;
use crate::error::Error;

/// Publish [`Event::KeysChanged`] on the global bus. Called by the
/// FRB layer (and any in-process orchestrator that mutates the
/// `ssh_keys` / `ssh_key_certificates` tables) after every
/// successful write so the Dart `sshKeysStreamProvider` re-fetches
/// in one microtask-coalesced reload rather than per-call.
///
/// Symmetric with [`crate::sessions::notify_changed`] — same shape,
/// same publish discipline. Coalescing happens on the Dart side:
/// the stream pipelines its re-fetches off the bus, so a flurry of
/// rapid writes (archive apply, bulk import) emits one event per
/// write but the consumer collapses them into the next snapshot.
pub fn notify_changed(app: &Arc<AppState>) {
    app.bus.publish(Event::KeysChanged);
}

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
    let key = PrivateKey::random(&mut rand::rngs::OsRng, Algorithm::Ed25519)
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
    let rsa = RsaKeypair::random(&mut rand::rngs::OsRng, bits)
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
    // Reject PPK v3 files whose Argon2id memory cost exceeds the cap.
    // A hostile `.ppk` could declare an arbitrarily large `Argon2-Memory`
    // value; without a pre-parse cap, russh-keys would forward it to the
    // Argon2 derive call and the runtime would try to allocate that
    // many KiB before the file is even validated. 1 GiB matches the
    // ceiling enforced on the LFSE archive envelope's KDF params.
    //
    // `Ok(None)` means no `Argon2-Memory` line (v2 PPK) — nothing to
    // enforce. `Err(_)` means the line exists but the value does not
    // parse as a u32; surface as a typed parse error so a hostile
    // value larger than `u32::MAX` cannot silently bypass the cap.
    if let Some(memory_kib) = parse_ppk_argon2_memory(trimmed)? {
        const PPK_ARGON2_MEMORY_CAP_KIB: u32 = 1024 * 1024; // 1 GiB
        if memory_kib > PPK_ARGON2_MEMORY_CAP_KIB {
            return Err(Error::KeyParse(format!(
                "ppk: Argon2-Memory {memory_kib} KiB exceeds {PPK_ARGON2_MEMORY_CAP_KIB} KiB cap"
            )));
        }
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

/// Find `Argon2-Memory: N` in a PPK v3 header and return the
/// declared memory cost in KiB.
///
/// - `Ok(None)` — no `Argon2-Memory` line (v2 PPK). Callers treat
///   absence as "no cap to enforce".
/// - `Ok(Some(n))` — line present with a value that parses as a
///   `u32` (KiB).
/// - `Err(Error::KeyParse)` — line present but the value does not
///   parse as a `u32`. Trap: folding this signal into the absence
///   case lets a hostile `.ppk` declare a value above `u32::MAX`
///   (`99999999999999999999`) and silently bypass the cap. The
///   typed error makes the caller reject the file before
///   russh-keys forwards the line to the Argon2 derive.
///
/// Pure header sniff, no `russh_keys` invocation.
fn parse_ppk_argon2_memory(ppk_text: &str) -> Result<Option<u32>, Error> {
    for line in ppk_text.lines() {
        if let Some(rest) = line.strip_prefix("Argon2-Memory:") {
            let value = rest.trim();
            return value
                .parse::<u32>()
                .map(Some)
                .map_err(|_| Error::KeyParse("ppk: Argon2-Memory not a valid u32".into()));
        }
    }
    Ok(None)
}

/// Parsed metadata for an `sk-*` SSH private key. The "private" file
/// produced by `ssh-keygen -t ed25519-sk` carries the credential id,
/// flags byte, application string, and public-key body — the actual
/// secret never leaves the authenticator. We persist all four so the
/// connect path can resolve the credential without re-prompting.
#[derive(Debug, Clone)]
pub struct SkKeyMetadata {
    /// Opaque CTAP2 credential id (the U2F key handle). Variable
    /// length up to 255 bytes per PROTOCOL.u2f.
    pub credential_id: Vec<u8>,
    /// FIDO/U2F application string. Typically `ssh:`; can be
    /// customised at `ssh-keygen` time via `-O application=...`.
    pub application: String,
    /// Algorithm tag. Wire form is the OpenSSH SSH-key algorithm
    /// string (`sk-ssh-ed25519@openssh.com` /
    /// `sk-ecdsa-sha2-nistp256@openssh.com`); the DB stores the
    /// short tag (`sk-ed25519` / `sk-ecdsa-p256`).
    pub key_type: String,
    /// Public-key body in single-line OpenSSH form. The connect path
    /// hands this back to russh for the userauth handshake.
    pub public_openssh: String,
    /// True when the credential was minted with `-O verify-required` —
    /// the device demands a PIN before signing. UI prompts the user
    /// at connect time.
    pub has_user_verification: bool,
}

/// Parse an OpenSSH-armored `sk-*` private key file
/// (`id_ed25519_sk`, `id_ecdsa_sk`). The file carries the public
/// point + application + key handle + flags — the device holds the
/// real signing key. Returns the metadata the connect path needs to
/// route through `lfs_core::fido2::get_assertion`.
pub fn parse_sk_private_key(pem: &str) -> Result<SkKeyMetadata, Error> {
    use russh::keys::ssh_key::private::KeypairData;

    let parsed = PrivateKey::from_openssh(pem.as_bytes())
        .map_err(|e| Error::KeyParse(format!("parse sk openssh: {e}")))?;
    if parsed.is_encrypted() {
        return Err(Error::KeyParse(
            "sk-* private keys are not passphrase-encrypted".into(),
        ));
    }
    let public_openssh = parsed
        .public_key()
        .to_openssh()
        .map_err(|e| Error::KeyParse(format!("encode public: {e}")))?;
    match parsed.key_data() {
        KeypairData::SkEd25519(k) => Ok(SkKeyMetadata {
            credential_id: k.key_handle().to_vec(),
            application: k.public().application().to_string(),
            key_type: "sk-ed25519".to_string(),
            public_openssh,
            // SSH_SK_USER_VERIFICATION_REQD = 0x04 per OpenSSH
            // PROTOCOL.u2f; the flag is OR'd into the byte at
            // generation time when the user passed `-O
            // verify-required`.
            has_user_verification: k.flags() & 0x04 != 0,
        }),
        KeypairData::SkEcdsaSha2NistP256(k) => Ok(SkKeyMetadata {
            credential_id: k.key_handle().to_vec(),
            application: k.public().application().to_string(),
            key_type: "sk-ecdsa-p256".to_string(),
            public_openssh,
            has_user_verification: k.flags() & 0x04 != 0,
        }),
        _ => Err(Error::KeyParse(
            "not an sk-* private key (missing FIDO2 credential body)".into(),
        )),
    }
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

/// Read `path` and return the OpenSSH-armored PEM if the file
/// looks like a private key.
///
/// Mirrors the Dart-era `KeyFileHelper.tryReadPemKey`:
/// - Returns `None` for missing files, files larger than 32 KiB
///   (the documented PEM ceiling — anything bigger is something
///   else), I/O errors, and PPK / PEM blobs that fail to decode.
/// - For PPK input, decodes through [`import_ppk`] without a
///   passphrase. Encrypted / unsupported PPKs collapse to `None`
///   so the silent file-picker path returns "not a key" and the
///   caller can fall back to the passphrase-aware key-manager UI.
/// - For PEM input, returns the original bytes when the
///   ASCII-armor `PRIVATE KEY` marker is present; otherwise `None`.
///
/// Keeping this in Rust means a picked file's bytes never
/// materialise on the Dart heap — the FRB caller hands the path
/// in and gets back either the canonical PEM or `None`.
pub fn try_read_pem_from_path(path: &std::path::Path) -> Option<String> {
    const MAX_KEY_FILE_SIZE: u64 = 32 * 1024;
    let meta = std::fs::metadata(path).ok()?;
    if !meta.is_file() {
        return None;
    }
    if meta.len() > MAX_KEY_FILE_SIZE {
        return None;
    }
    let content = std::fs::read_to_string(path).ok()?;
    if looks_like_ppk(&content) {
        return import_ppk(&content, None, "").ok().map(|km| km.private_pem);
    }
    if content.contains("PRIVATE KEY") {
        return Some(content);
    }
    None
}

/// Typed view of an OpenSSH certificate produced by
/// [`parse_openssh_cert`]. Fields mirror the ssh-key crate's
/// [`Certificate`] surface but use owned `String` / `Vec` so the
/// summary can cross task boundaries without referencing the
/// short-lived `Certificate` instance.
///
/// `valid_after_unix` / `valid_before_unix` are seconds since
/// epoch — the certificate's wire-format validity window. The Dart
/// caller converts to `DateTime` for display. `critical_options` is
/// a `BTreeMap` so iteration order is stable for hashing /
/// fingerprint composition.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CertSummary {
    /// Hosts / users the cert is valid for. Empty list means
    /// "valid for any principal" per OpenSSH's wire-format
    /// convention.
    pub principals: Vec<String>,
    pub valid_after_unix: i64,
    pub valid_before_unix: i64,
    /// `force-command`, `source-address`, etc. — opaque key/value
    /// pairs the server enforces.
    pub critical_options: BTreeMap<String, String>,
    /// SHA-256 of the binary cert blob in OpenSSH
    /// `SHA256:<base64-no-pad>` shape. Matches `ssh-keygen -lf
    /// <cert.pub>` output byte-for-byte.
    pub fingerprint: String,
}

/// Parse an OpenSSH-format certificate (`id_*-cert.pub` /
/// armored `-----BEGIN OPENSSH CERTIFICATE-----`) and project the
/// fields the Dart key-manager UI surfaces — principals, validity
/// window, critical options, and a stable display fingerprint.
///
/// **Fingerprint shape.** SHA-256 of the binary cert blob in
/// `SHA256:<base64-no-pad>` form — the same shape
/// [`crate::ssh::format_fingerprint`] produces for host keys and
/// what `ssh-keygen -l -f <cert.pub>` prints. Recomputed inside
/// Rust rather than passed through from the caller so a tampered
/// cert blob cannot inject a fake display fingerprint.
///
/// **Why not return the raw `Certificate`.** Crossing the FRB
/// boundary needs an owned, `Send + 'static` shape; the russh-fork
/// `Certificate` does not need to leak out and a typed summary
/// keeps the DB column shape uncoupled from the russh ABI. If a
/// future use case needs the full cert (e.g. verifying server-side
/// CA fingerprints) it can call into russh-keys directly from
/// `lfs_core::ssh`.
pub fn parse_openssh_cert(bytes: &[u8]) -> Result<CertSummary, Error> {
    let trimmed: Vec<u8> = bytes
        .iter()
        .copied()
        .skip_while(|b| b.is_ascii_whitespace())
        .collect();
    let cert_str =
        std::str::from_utf8(&trimmed).map_err(|e| Error::KeyParse(format!("cert utf8: {e}")))?;
    let cert =
        Certificate::from_openssh(cert_str).map_err(|e| Error::KeyParse(format!("cert: {e}")))?;

    let mut critical_options: BTreeMap<String, String> = BTreeMap::new();
    for (name, value) in cert.critical_options().iter() {
        critical_options.insert(name.clone(), value.clone());
    }

    // The cert blob has no built-in SHA-256 helper on the
    // forked-ssh-key surface; re-encode via `to_bytes` then hash.
    // The blob output is the SSH-wire-format binary equivalent of
    // the base64 body — matches the bytes `ssh-keygen -l` digests.
    let blob = cert
        .to_bytes()
        .map_err(|e| Error::KeyParse(format!("cert encode: {e}")))?;
    let fingerprint = crate::ssh::format_fingerprint(&blob);

    Ok(CertSummary {
        principals: cert.valid_principals().to_vec(),
        // `valid_after` / `valid_before` are unix seconds in OpenSSH;
        // the russh-keys getter returns `u64`. Cast to `i64` for the
        // Dart `DateTime.fromMillisecondsSinceEpoch` shape — i64 can
        // hold every wire value (the max is 0xFFFFFFFFFFFFFFFF only
        // in theory; real certs cap well inside the i64 range).
        valid_after_unix: cert.valid_after() as i64,
        valid_before_unix: cert.valid_before() as i64,
        critical_options,
        fingerprint,
    })
}

/// Verify that `cert_bytes` (OpenSSH `*-cert.pub` text) is signed
/// for the same public key as `pubkey_openssh` (OpenSSH `*.pub`
/// text — the user-stored key the cert is supposed to pair to).
///
/// Compares SHA-256 fingerprints of the SSH wire-format public-key
/// blob: the cert's bound key (extracted via `Certificate::public_key`)
/// against the user-supplied key (parsed via `PublicKey::from_openssh`).
/// Returns `Ok(true)` only when both fingerprints match byte-for-byte.
///
/// Why fingerprint-based, not key-bytes-based: the user-supplied
/// OpenSSH text may carry a trailing comment, CRLF/LF differences,
/// or trailing whitespace that the wire-format key does not. Routing
/// both through `fingerprint(HashAlg::Sha256)` strips that noise
/// without loosening the cryptographic check.
///
/// Returns `Err` only on parse failure (malformed cert, malformed
/// public key). A successful parse with a mismatch returns
/// `Ok(false)` so callers can surface a tailored "wrong key" toast
/// rather than a generic parse error.
pub fn cert_matches_key(cert_bytes: &[u8], pubkey_openssh: &str) -> Result<bool, Error> {
    let trimmed: Vec<u8> = cert_bytes
        .iter()
        .copied()
        .skip_while(|b| b.is_ascii_whitespace())
        .collect();
    let cert_str =
        std::str::from_utf8(&trimmed).map_err(|e| Error::KeyParse(format!("cert utf8: {e}")))?;
    let cert =
        Certificate::from_openssh(cert_str).map_err(|e| Error::KeyParse(format!("cert: {e}")))?;
    let key = PublicKey::from_openssh(pubkey_openssh.trim())
        .map_err(|e| Error::KeyParse(format!("pubkey: {e}")))?;
    let cert_fp = cert.public_key().fingerprint(HashAlg::Sha256).to_string();
    let key_fp = key.fingerprint(HashAlg::Sha256).to_string();
    Ok(cert_fp == key_fp)
}

/// Read `path` as UTF-8 text, capped at 32 KiB. Used by the
/// key-manager dialog as the manual-edit fallback when
/// [`try_read_pem_from_path`] could not auto-detect a PEM / PPK
/// shape — the user picked a file we don't recognise but still
/// wants to paste-and-edit the bytes in the dialog.
///
/// Returns `Err` for missing files, files larger than the
/// ceiling, I/O errors, and non-UTF-8 content. Caller surfaces
/// any error as the dialog's "couldn't read file" toast.
pub fn read_text_for_manual_import(path: &std::path::Path) -> Result<String, Error> {
    const MAX_KEY_FILE_SIZE: u64 = 32 * 1024;
    let meta = std::fs::metadata(path).map_err(|e| Error::KeyParse(format!("stat: {e}")))?;
    if !meta.is_file() {
        return Err(Error::KeyParse(String::from("not a regular file")));
    }
    if meta.len() > MAX_KEY_FILE_SIZE {
        return Err(Error::KeyParse(format!(
            "file too large ({} bytes, max {})",
            meta.len(),
            MAX_KEY_FILE_SIZE
        )));
    }
    std::fs::read_to_string(path).map_err(|e| Error::KeyParse(format!("read: {e}")))
}

/// Read `path` as raw bytes for OpenSSH certificate import,
/// capped at 16 KiB. Real certificates are ~1-2 KiB; the
/// ceiling protects against picking up a misnamed multi-MB
/// file (binary, video, archive) the user mistook for a `.pub`
/// cert blob. Returns `Err` for missing files, oversize input,
/// non-regular entries (symlink targets that resolve to a
/// directory, /dev/* nodes), and I/O failures. The caller
/// surfaces the error as the dialog's "couldn't read cert"
/// toast and pivots to the manual-paste path.
pub fn read_cert_bytes_for_import(path: &std::path::Path) -> Result<Vec<u8>, Error> {
    const MAX_CERT_FILE_SIZE: u64 = 16 * 1024;
    let meta = std::fs::metadata(path).map_err(|e| Error::KeyParse(format!("stat: {e}")))?;
    if !meta.is_file() {
        return Err(Error::KeyParse(String::from("not a regular file")));
    }
    if meta.len() > MAX_CERT_FILE_SIZE {
        return Err(Error::KeyParse(format!(
            "file too large ({} bytes, max {})",
            meta.len(),
            MAX_CERT_FILE_SIZE
        )));
    }
    std::fs::read(path).map_err(|e| Error::KeyParse(format!("read: {e}")))
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

    // ── try_read_pem_from_path ───────────────────────────────────

    #[test]
    fn try_read_pem_from_path_returns_pem_for_valid_armor() {
        let dir = tempfile::TempDir::new().unwrap();
        let path = dir.path().join("id_ed25519");
        let content = "-----BEGIN OPENSSH PRIVATE KEY-----\nbm90LXJlYWw=\n-----END OPENSSH PRIVATE KEY-----\n";
        std::fs::write(&path, content).unwrap();
        assert_eq!(try_read_pem_from_path(&path).as_deref(), Some(content));
    }

    #[test]
    fn try_read_pem_from_path_returns_none_for_missing_file() {
        let dir = tempfile::TempDir::new().unwrap();
        let path = dir.path().join("nope");
        assert!(try_read_pem_from_path(&path).is_none());
    }

    #[test]
    fn try_read_pem_from_path_rejects_oversized_file() {
        // 33 KiB → over the documented 32 KiB ceiling. The file's
        // body is irrelevant; the size check trips before any
        // PEM / PPK detection.
        let dir = tempfile::TempDir::new().unwrap();
        let path = dir.path().join("oversized");
        std::fs::write(&path, vec![b'x'; 33 * 1024]).unwrap();
        assert!(try_read_pem_from_path(&path).is_none());
    }

    #[test]
    fn try_read_pem_from_path_rejects_non_pem_content() {
        // A small file with no `PRIVATE KEY` armor — picker
        // legitimately picked something else (config, log, random
        // text). Helper says "not a key" and the silent path moves
        // on without surfacing a parse error.
        let dir = tempfile::TempDir::new().unwrap();
        let path = dir.path().join("random.txt");
        std::fs::write(&path, b"hello world").unwrap();
        assert!(try_read_pem_from_path(&path).is_none());
    }

    #[test]
    fn try_read_pem_from_path_rejects_directory() {
        // A directory at the picked path → must collapse to None
        // rather than blowing up — the file picker on iOS / Android
        // can hand us a directory under a sandbox alias.
        let dir = tempfile::TempDir::new().unwrap();
        assert!(try_read_pem_from_path(dir.path()).is_none());
    }

    // ── parse_openssh_cert ───────────────────────────────────────
    //
    // Real OpenSSH ed25519 cert blob — taken from the
    // `internal-russh-forked-ssh-key` test corpus
    // (`tests/examples/id_ed25519-cert.pub`). The corresponding
    // upstream test asserts `valid_principals[0] == "host.example.com"`
    // and one principal entry; we re-assert those invariants here so
    // a russh-fork bump that silently changes the parser surface is
    // caught at our DAO boundary, not at runtime.
    const ED25519_CERT_FIXTURE: &str = "ssh-ed25519-cert-v01@openssh.com AAAAIHNzaC1lZDI1NTE5LWNlcnQtdjAxQG9wZW5zc2guY29tAAAAIAYkJPGaYen7NK8MwZwWmNAyRaFNsc86AU9NObU2cM2uAAAAILM+rvN+ot98qgEN796jTiQfZfG1KaT0PtFDJ/XFSqtiAAAAAAAAAAAAAAACAAAAB2VkMjU1MTkAAAAUAAAAEGhvc3QuZXhhbXBsZS5jb20AAAAAYkx3NwAAAAB8DuY3AAAAAAAAAAAAAAAAAAAAMwAAAAtzc2gtZWQyNTUxOQAAACCzPq7zfqLffKoBDe/eo04kH2XxtSmk9D7RQyf1xUqrYgAAAFMAAAALc3NoLWVkMjU1MTkAAABApVXBNiYPlPoa1BYH5G4NP9XtjTMZlm7HO5GdbLSvvAw5Vdob7Ka+23hB7isJKHYtzFGGSKXAqxp/Zi8REbCaAw== user@example.com";

    // Cert with a `force-command` critical option. Confirms we
    // surface the option name + value verbatim; pulled from the
    // forked-ssh-key crit-options round-trip test.
    const ED25519_CERT_WITH_CRIT_OPTIONS: &str = "ssh-ed25519-cert-v01@openssh.com AAAAIHNzaC1lZDI1NTE5LWNlcnQtdjAxQG9wZW5zc2guY29tAAAAIBW/4zLqXWROWmN1sPgdySnH1GUsEFBjFrRwKKw71BoBAAAAIH1MFwI1oRdEifXgBQvWQfCBBtA/Pi8YCUE/I3wXFJo2AAAAAAAAAAAAAAABAAAAA2ZvbwAAAAAAAAAAAAAAAH//////////AAAAIwAAABFoZWxsb0BleGFtcGxlLmNvbQAAAAoAAAAGZm9vYmFyAAAAAAAAAAAAAAAzAAAAC3NzaC1lZDI1NTE5AAAAIH1MFwI1oRdEifXgBQvWQfCBBtA/Pi8YCUE/I3wXFJo2AAAAUwAAAAtzc2gtZWQyNTUxOQAAAEDRoPdI48KyoaLgaDZsSGs80qBeYQOXBd84CX8GYzFt/L21rxF1EeuPOkgsx7Q39WllXp+FgMMojsHftK/DJHEN";

    #[test]
    fn parse_openssh_cert_extracts_principals() {
        let parsed = parse_openssh_cert(ED25519_CERT_FIXTURE.as_bytes()).unwrap();
        assert_eq!(parsed.principals, vec!["host.example.com".to_string()]);
    }

    #[test]
    fn parse_openssh_cert_extracts_validity_window() {
        let parsed = parse_openssh_cert(ED25519_CERT_FIXTURE.as_bytes()).unwrap();
        // Validity is encoded in the fixture as unix seconds; we
        // assert window monotonicity (after < before) rather than
        // exact values so a russh-fork bump that switches encoding
        // surfaces here before downstream UI assertions.
        assert!(parsed.valid_after_unix > 0);
        assert!(parsed.valid_before_unix > parsed.valid_after_unix);
    }

    #[test]
    fn parse_openssh_cert_extracts_critical_options() {
        let parsed = parse_openssh_cert(ED25519_CERT_WITH_CRIT_OPTIONS.as_bytes()).unwrap();
        assert_eq!(parsed.critical_options.len(), 1);
        assert_eq!(
            parsed
                .critical_options
                .get("hello@example.com")
                .map(String::as_str),
            Some("foobar"),
        );
    }

    #[test]
    fn parse_openssh_cert_no_crit_options_returns_empty_map() {
        let parsed = parse_openssh_cert(ED25519_CERT_FIXTURE.as_bytes()).unwrap();
        assert!(parsed.critical_options.is_empty());
    }

    #[test]
    fn parse_openssh_cert_fingerprint_is_stable_sha256_base64_shape() {
        // SHA-256 in `SHA256:<base64-no-pad>` form — 43 chars of
        // base64-no-pad after the prefix (32 bytes → 43 base64).
        let parsed = parse_openssh_cert(ED25519_CERT_FIXTURE.as_bytes()).unwrap();
        assert!(parsed.fingerprint.starts_with("SHA256:"));
        let body = &parsed.fingerprint["SHA256:".len()..];
        assert_eq!(body.len(), 43);
        // Re-parse must produce the same fingerprint; deterministic
        // hash of canonical-encoded blob bytes.
        let parsed2 = parse_openssh_cert(ED25519_CERT_FIXTURE.as_bytes()).unwrap();
        assert_eq!(parsed.fingerprint, parsed2.fingerprint);
    }

    #[test]
    fn parse_openssh_cert_rejects_random_bytes() {
        let result = parse_openssh_cert(b"not-a-certificate");
        assert!(matches!(result, Err(Error::KeyParse(_))));
    }

    #[test]
    fn parse_openssh_cert_rejects_non_utf8() {
        let result = parse_openssh_cert(&[0xFF, 0xFE, 0x00, 0xC0]);
        assert!(matches!(result, Err(Error::KeyParse(_))));
    }

    #[test]
    fn parse_openssh_cert_strips_leading_whitespace() {
        // Real-world paste often arrives with a stray leading
        // newline; the parser must still resolve the cert content.
        let padded = format!("\n  {ED25519_CERT_FIXTURE}");
        let parsed = parse_openssh_cert(padded.as_bytes()).unwrap();
        assert_eq!(parsed.principals, vec!["host.example.com".to_string()]);
    }

    #[test]
    fn parse_ppk_argon2_memory_returns_none_when_line_missing() {
        // v2 PPK header — no `Argon2-Memory` line. The caller treats
        // `Ok(None)` as "no cap to enforce".
        let v2 = "PuTTY-User-Key-File-2: ssh-rsa\nEncryption: none\n";
        assert_eq!(parse_ppk_argon2_memory(v2).unwrap(), None);
    }

    #[test]
    fn parse_ppk_argon2_memory_parses_valid_u32() {
        let header = "PuTTY-User-Key-File-3: ssh-ed25519\nArgon2-Memory: 8192\n";
        assert_eq!(parse_ppk_argon2_memory(header).unwrap(), Some(8192));
    }

    #[test]
    fn parse_ppk_argon2_memory_rejects_value_above_u32_max() {
        // `99999999999999999999` is larger than `u32::MAX`. Trap:
        // folding the parse failure into the "no cap to enforce"
        // branch via `parse::<u32>().ok()` silently bypasses the
        // 1 GiB cap. The typed parse error makes the caller reject.
        let hostile = "PuTTY-User-Key-File-3: ssh-ed25519\nArgon2-Memory: 99999999999999999999\n";
        let err = parse_ppk_argon2_memory(hostile).unwrap_err();
        match err {
            Error::KeyParse(msg) => {
                assert!(msg.contains("Argon2-Memory"), "unexpected message: {msg}");
            }
            other => panic!("expected KeyParse, got {other:?}"),
        }
    }

    #[test]
    fn parse_ppk_argon2_memory_rejects_non_numeric_value() {
        let bad = "PuTTY-User-Key-File-3: ssh-ed25519\nArgon2-Memory: abcd\n";
        assert!(matches!(
            parse_ppk_argon2_memory(bad),
            Err(Error::KeyParse(_))
        ));
    }

    #[test]
    fn import_ppk_rejects_argon2_memory_above_u32_max() {
        // End-to-end: a hostile `.ppk` whose `Argon2-Memory` value
        // exceeds `u32::MAX` must short-circuit with a typed
        // `KeyParse` error before russh-keys touches the file.
        let hostile = "PuTTY-User-Key-File-3: ssh-ed25519\nArgon2-Memory: 9999999999999\nEncryption: aes256-cbc\n";
        let err = import_ppk(hostile, Some("pw"), "comment").unwrap_err();
        match err {
            Error::KeyParse(msg) => {
                assert!(msg.contains("Argon2-Memory"), "unexpected message: {msg}");
            }
            other => panic!("expected KeyParse, got {other:?}"),
        }
    }
}
