//! `C_Sign` round-trip for a stored PKCS#11 key.
//!
//! Inputs from the caller:
//! - Resolved [`Module`] (`pkcs11::module::load(path)`).
//! - Token slot id (the import wizard captured it; we re-resolve at
//!   sign time so a re-plug shifts to the new slot transparently).
//! - `CKA_ID` of the private-key object (captured at import).
//! - SSH-userauth `to_sign` buffer (already includes session id +
//!   the userauth header + the public-key blob — the caller is
//!   responsible for the SSH composition).
//! - PIN (`None` for protected-authentication-path tokens; the
//!   token's button prompt fires inside `with_session`).
//!
//! Output:
//! - The SSH-wire body for the userauth `signature` field — `mpint(r)
//!   || mpint(s)` for ECDSA, `string(sig)` for RSA / Ed25519. The
//!   caller wraps the result inside `string(algorithm) || string(sig_blob)`
//!   per the userauth contract.
//!
//! Threading: every PKCS#11 call here is sync. The Signer wrapper in
//! `lfs_core::ssh::pkcs11_signer` runs each `sign` invocation through
//! `tokio::task::spawn_blocking` so the runtime worker thread is the
//! one stuck on `C_Sign`, not the executor.

#![cfg(any(target_os = "linux", target_os = "macos", target_os = "windows"))]

use cryptoki::mechanism::eddsa::{EddsaParams, EddsaSignatureScheme};
use cryptoki::mechanism::Mechanism;
use cryptoki::object::{Attribute, AttributeType, KeyType, ObjectClass, ObjectHandle};
use cryptoki::session::Session as CkSession;
use sha2::{Digest, Sha256, Sha384, Sha512};

use super::error::Error;
use super::key::KeyClass;
use super::session::Session;

/// Caller-facing signing input. `algorithm` is the SSH algorithm
/// string (`rsa-sha2-256`, `rsa-sha2-512`, `ecdsa-sha2-nistp256`,
/// `ssh-ed25519`, etc.); we pick the matching PKCS#11 mechanism +
/// pre-hash from it.
///
/// `Session` does not derive `Debug` (the underlying `cryptoki::Session`
/// does not), so this struct lives without a Debug derive — the
/// fields a debug dump would want are scarce and either binary
/// (`cka_id`, `to_sign`) or could leak PIN material; not surfacing a
/// Debug impl is the right contract.
#[derive(Clone)]
pub struct SignRequest<'a> {
    pub session: &'a Session,
    pub pin: Option<&'a str>,
    pub cka_id: &'a [u8],
    pub algorithm: &'a str,
    pub to_sign: &'a [u8],
}

/// SSH-wire `signature` body. Caller wraps in
/// `string(algorithm) || string(sig_blob)` per the userauth contract.
#[derive(Debug, Clone)]
pub struct SignOutput {
    /// `r || s` mpints for ECDSA, `string(sig)` for RSA / Ed25519.
    pub ssh_sig_body: Vec<u8>,
}

/// Resolve the private-key handle by `CKA_ID`, choose the mechanism
/// + pre-hash, run `C_Sign`, normalise the output to the SSH wire shape.
pub fn sign_with_pkcs11(req: SignRequest<'_>) -> Result<SignOutput, Error> {
    req.session.with_session(req.pin, |ck| {
        let handles = ck
            .find_objects(&[
                Attribute::Class(ObjectClass::PRIVATE_KEY),
                Attribute::Id(req.cka_id.to_vec()),
            ])
            .map_err(Error::from)?;
        let key_handle = handles
            .into_iter()
            .next()
            .ok_or_else(|| Error::TokenUnplugged("no private key with matching CKA_ID".into()))?;

        // Discover the key type via a one-attr probe so we pick the
        // right `Mechanism` even when the algorithm string is
        // ambiguous (`rsa-sha2-256` could come from RSA-PSS or
        // RSA-PKCS — we always use PKCS#1 v1.5).
        let attrs = ck
            .get_attributes(key_handle, &[AttributeType::KeyType])
            .map_err(Error::from)?;
        let mut key_type: Option<KeyType> = None;
        for a in attrs {
            if let Attribute::KeyType(k) = a {
                key_type = Some(k);
            }
        }
        let kt = key_type.ok_or_else(|| Error::Other("private key missing KeyType".into()))?;

        // Pre-hash + mechanism selection per the table in the plan.
        if kt == KeyType::EC_EDWARDS {
            return sign_ed25519(ck, key_handle, req.to_sign);
        }
        if kt == KeyType::EC {
            return sign_ecdsa(ck, key_handle, req.algorithm, req.to_sign);
        }
        if kt == KeyType::RSA {
            return sign_rsa(ck, key_handle, req.algorithm, req.to_sign);
        }
        Err(Error::UnsupportedKeyType(format!(
            "CKK {} cannot be signed for SSH",
            *kt
        )))
    })
}

/// Ed25519 — raw, no pre-hash; mechanism CKM_EDDSA with the `Pure`
/// scheme. Output is the raw 64-byte signature wrapped as SSH wire
/// `string(sig)` (one length prefix).
fn sign_ed25519(
    ck: &CkSession,
    key_handle: ObjectHandle,
    to_sign: &[u8],
) -> Result<SignOutput, Error> {
    let mechanism = Mechanism::Eddsa(EddsaParams::new(EddsaSignatureScheme::Pure));
    let raw = ck
        .sign(&mechanism, key_handle, to_sign)
        .map_err(map_sign_err)?;
    if raw.len() != 64 {
        return Err(Error::SignRefused(format!(
            "ed25519 token returned {} bytes; expected 64",
            raw.len()
        )));
    }
    let mut out = Vec::with_capacity(raw.len() + 4);
    push_string(&mut out, &raw);
    Ok(SignOutput { ssh_sig_body: out })
}

/// ECDSA — pre-hash by the SSH algorithm string. CKM_ECDSA wants the
/// hash digest as input; the token signs the digest and returns raw
/// `r || s` concatenated, which we re-encode as two SSH mpints.
fn sign_ecdsa(
    ck: &CkSession,
    key_handle: ObjectHandle,
    algorithm: &str,
    to_sign: &[u8],
) -> Result<SignOutput, Error> {
    let digest = match algorithm {
        "ecdsa-sha2-nistp256" => sha256(to_sign),
        "ecdsa-sha2-nistp384" => sha384(to_sign),
        "ecdsa-sha2-nistp521" => sha512(to_sign),
        other => {
            return Err(Error::SignRefused(format!(
                "ecdsa algorithm {other:?} not recognised"
            )));
        }
    };
    let raw = ck
        .sign(&Mechanism::Ecdsa, key_handle, &digest)
        .map_err(map_sign_err)?;
    if raw.is_empty() || raw.len() % 2 != 0 {
        return Err(Error::SignRefused(format!(
            "ecdsa token returned odd-length raw signature ({} bytes)",
            raw.len()
        )));
    }
    let half = raw.len() / 2;
    let mut out = Vec::with_capacity(raw.len() + 16);
    push_mpint(&mut out, &raw[..half]);
    push_mpint(&mut out, &raw[half..]);
    Ok(SignOutput { ssh_sig_body: out })
}

/// RSA-PKCS#1 v1.5 — the token expects the DigestInfo prefix baked
/// in. We pre-build it client-side and call the raw `CKM_RSA_PKCS`
/// mechanism. Old `ssh-rsa` (SHA-1) is server-deprecated; we never
/// offer it.
fn sign_rsa(
    ck: &CkSession,
    key_handle: ObjectHandle,
    algorithm: &str,
    to_sign: &[u8],
) -> Result<SignOutput, Error> {
    let (digest_info, _expected_hashbytes) = match algorithm {
        "rsa-sha2-256" => (rsa_digestinfo_sha256(to_sign), 32),
        "rsa-sha2-512" => (rsa_digestinfo_sha512(to_sign), 64),
        other => {
            return Err(Error::SignRefused(format!(
                "rsa algorithm {other:?} not recognised (old ssh-rsa SHA-1 is refused)"
            )));
        }
    };
    let raw = ck
        .sign(&Mechanism::RsaPkcs, key_handle, &digest_info)
        .map_err(map_sign_err)?;
    let mut out = Vec::with_capacity(raw.len() + 4);
    push_string(&mut out, &raw);
    Ok(SignOutput { ssh_sig_body: out })
}

/// Map the SSH algorithm string to the [`KeyClass`] the public-key
/// blob captures at import. Caller uses this to assert the imported
/// row matches the requested-by-russh wire name.
pub fn key_class_for_algorithm(algo: &str) -> Option<KeyClass> {
    match algo {
        "rsa-sha2-256" | "rsa-sha2-512" => Some(KeyClass::Rsa),
        "ecdsa-sha2-nistp256" => Some(KeyClass::EcdsaP256),
        "ecdsa-sha2-nistp384" => Some(KeyClass::EcdsaP384),
        "ecdsa-sha2-nistp521" => Some(KeyClass::EcdsaP521),
        "ssh-ed25519" => Some(KeyClass::Ed25519),
        _ => None,
    }
}

fn map_sign_err(e: cryptoki::error::Error) -> Error {
    match Error::from(e) {
        // Preserve typed PIN errors so the connect path can re-prompt
        // rather than terminate the connect attempt.
        wrapped @ (Error::WrongPin { .. } | Error::PinLocked | Error::PinPadCancelled) => wrapped,
        Error::Other(s) => Error::SignRefused(s),
        other => other,
    }
}

fn sha256(input: &[u8]) -> Vec<u8> {
    let mut h = Sha256::new();
    h.update(input);
    h.finalize().to_vec()
}

fn sha384(input: &[u8]) -> Vec<u8> {
    let mut h = Sha384::new();
    h.update(input);
    h.finalize().to_vec()
}

fn sha512(input: &[u8]) -> Vec<u8> {
    let mut h = Sha512::new();
    h.update(input);
    h.finalize().to_vec()
}

/// Build the PKCS#1 v1.5 DigestInfo wrapper for SHA-256 over `input`.
/// Prefix per RFC 3447 §9.2.
fn rsa_digestinfo_sha256(input: &[u8]) -> Vec<u8> {
    // SEQUENCE { SEQUENCE { OID sha-256, NULL }, OCTET STRING (32) }
    const PREFIX: &[u8] = &[
        0x30, 0x31, 0x30, 0x0d, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x01,
        0x05, 0x00, 0x04, 0x20,
    ];
    let mut out = Vec::with_capacity(PREFIX.len() + 32);
    out.extend_from_slice(PREFIX);
    out.extend_from_slice(&sha256(input));
    out
}

fn rsa_digestinfo_sha512(input: &[u8]) -> Vec<u8> {
    // SEQUENCE { SEQUENCE { OID sha-512, NULL }, OCTET STRING (64) }
    const PREFIX: &[u8] = &[
        0x30, 0x51, 0x30, 0x0d, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x03,
        0x05, 0x00, 0x04, 0x40,
    ];
    let mut out = Vec::with_capacity(PREFIX.len() + 64);
    out.extend_from_slice(PREFIX);
    out.extend_from_slice(&sha512(input));
    out
}

fn push_string(buf: &mut Vec<u8>, payload: &[u8]) {
    buf.extend_from_slice(&(payload.len() as u32).to_be_bytes());
    buf.extend_from_slice(payload);
}

fn push_mpint(buf: &mut Vec<u8>, magnitude: &[u8]) {
    let mut start = 0;
    while start + 1 < magnitude.len()
        && magnitude[start] == 0x00
        && magnitude[start + 1] & 0x80 == 0
    {
        start += 1;
    }
    let trimmed = &magnitude[start..];
    let needs_pad = !trimmed.is_empty() && trimmed[0] & 0x80 != 0;
    let len = if trimmed.is_empty() {
        0
    } else {
        trimmed.len() + usize::from(needs_pad)
    };
    buf.extend_from_slice(&(len as u32).to_be_bytes());
    if needs_pad {
        buf.push(0x00);
    }
    buf.extend_from_slice(trimmed);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn algorithm_map_round_trips() {
        assert!(matches!(
            key_class_for_algorithm("ecdsa-sha2-nistp256"),
            Some(KeyClass::EcdsaP256)
        ));
        assert!(matches!(
            key_class_for_algorithm("ssh-ed25519"),
            Some(KeyClass::Ed25519)
        ));
        assert!(matches!(
            key_class_for_algorithm("rsa-sha2-512"),
            Some(KeyClass::Rsa)
        ));
        assert!(key_class_for_algorithm("ssh-rsa").is_none());
        assert!(key_class_for_algorithm("unknown").is_none());
    }

    #[test]
    fn rsa_digestinfo_prefix_matches_rfc_3447() {
        let info = rsa_digestinfo_sha256(b"abc");
        assert_eq!(info[0..2], [0x30, 0x31]);
        assert_eq!(info[18], 0x20); // SHA-256 length = 32
        assert_eq!(info.len(), 51);

        let info = rsa_digestinfo_sha512(b"abc");
        assert_eq!(info[0..2], [0x30, 0x51]);
        assert_eq!(info[18], 0x40); // SHA-512 length = 64
        assert_eq!(info.len(), 83);
    }

    #[test]
    fn ecdsa_raw_concat_to_mpints_round_trip() {
        // Use the push_mpint helper to assert the SSH wire shape the
        // sign function emits.
        let mut raw = [0u8; 64];
        raw[0] = 0x80; // MSB set on r → pad
        let mut out = Vec::new();
        push_mpint(&mut out, &raw[..32]);
        push_mpint(&mut out, &raw[32..]);
        assert_eq!(&out[..4], &[0, 0, 0, 33]); // r mpint w/ pad
        assert_eq!(out[4], 0x00);
        assert_eq!(out[5], 0x80);
        // s collapses to single 0x00 (all-zeros).
        assert_eq!(&out[37..41], &[0, 0, 0, 1]);
        assert_eq!(out[41], 0x00);
    }
}
