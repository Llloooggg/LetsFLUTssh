//! FIDO2 hardware-bound SSH userauth glue.
//!
//! Bridges `lfs_core::fido2::get_assertion` to russh's
//! `auth::Signer` trait so an `sk-ssh-ed25519@openssh.com` /
//! `sk-ecdsa-sha2-nistp256@openssh.com` key authenticates against
//! a remote SSH server by routing the per-request signature
//! through the plugged-in hardware authenticator. Private key
//! material never lands on the Dart heap and never leaves the
//! device.
//!
//! ## Wire shape
//!
//! russh hands the signer the raw SSH userauth packet bytes to
//! sign. The signer must:
//!
//! 1. SHA-256 the input → `clientDataHash`.
//! 2. Call CTAP2 getAssertion(credential_id, rp_id=application,
//!    clientDataHash) — the device verifies user presence (touch)
//!    and optionally user verification (PIN) before signing.
//! 3. Wrap the CTAP signature in the SSH `sk-*` wire-format trailer:
//!    - **sk-ed25519:** `64-byte ed25519 sig || u8 flags || u32 counter`
//!    - **sk-ecdsa-p256:** `string mpint r || string mpint s || u8 flags || u32 counter`
//! 4. Encode the SSH userauth `signature` field — `string(algorithm) ||
//!    string(sig_blob)` — as a single length-prefixed string appended
//!    to the buffer russh handed in.
//!
//! Lifted from OpenSSH's `sshsk_sign` (sk-ed25519 / sk-ecdsa-p256
//! sections) verbatim; the only deviation is that we run the HID
//! transport from inside our process rather than `ssh-sk-helper`.

#[cfg(test)]
use russh::keys::ssh_key::EcdsaCurve;
use russh::keys::ssh_key::{self, Algorithm, HashAlg};
use sha2::{Digest, Sha256};

use crate::error::Error;
use crate::fido2;
use crate::ssh::wire;

/// Captured-at-import shape the connect path resolves before it
/// hands russh a `FidoSigner`. Cloned across the await chain because
/// russh's `Signer` is `&mut self` per signature attempt; each field
/// is small.
#[derive(Clone, Debug)]
pub struct FidoCredential {
    /// Opaque CTAP2 credential id captured at import from the
    /// `sk-*` public-key body.
    pub credential_id: Vec<u8>,
    /// SSH `application` field. Typically `ssh:` but the user can
    /// pin a different RP-id at generation time (`ssh-keygen
    /// -O application=...`).
    pub application: String,
    /// PIN to forward to the CTAP2 layer when the credential
    /// requires user verification. `None` when the credential is
    /// touch-only.
    pub pin: Option<String>,
}

/// SSH wire-format algorithm name for the `sk-*` variant matching
/// the captured public key. Used by [`encode_signature`] to compose
/// the userauth `signature` field; not exposed past this module.
fn algorithm_wire_name(algorithm: &Algorithm) -> Result<&'static str, Error> {
    match algorithm {
        Algorithm::SkEd25519 => Ok("sk-ssh-ed25519@openssh.com"),
        Algorithm::SkEcdsaSha2NistP256 => Ok("sk-ecdsa-sha2-nistp256@openssh.com"),
        // Anything else routed to the FIDO path is a bug — the
        // dispatcher in `ssh::mod` filters on key type before
        // building the signer. Be loud so the breakage is obvious.
        other => Err(Error::Auth(format!(
            "fido2 signer: unsupported algorithm {other:?}"
        ))),
    }
}

/// Compose the SSH `sk-*` signature trailer the OpenSSH server
/// expects. `raw_signature` is the bytes the device returned
/// verbatim — Ed25519 is the 64-byte raw signature; ECDSA P-256 is
/// the DER-encoded `SEQUENCE { r, s }` normalised here into the SSH
/// `mpint(r) || mpint(s)` shape via [`crate::ssh::wire`].
///
/// `pub` so the in-process ssh-agent endpoint (`crate::ssh_agent`)
/// can reach the bare SK trailer without re-implementing the
/// SHA-256 -> CTAP2 -> trailer dance: the agent protocol's
/// `Signature` response shape wants the SK trailer directly, with
/// the algorithm name as a sibling field rather than length-prefixed
/// in-band.
pub fn encode_sk_signature(
    algorithm: &Algorithm,
    raw_signature: &[u8],
    flags: u8,
    counter: u32,
) -> Result<Vec<u8>, Error> {
    match algorithm {
        Algorithm::SkEd25519 => {
            if raw_signature.len() != 64 {
                return Err(Error::Auth(format!(
                    "fido2 signer: sk-ed25519 raw signature must be 64 bytes, got {}",
                    raw_signature.len()
                )));
            }
            let mut out = Vec::with_capacity(64 + 5);
            out.extend_from_slice(raw_signature);
            out.push(flags);
            out.extend_from_slice(&counter.to_be_bytes());
            Ok(out)
        }
        Algorithm::SkEcdsaSha2NistP256 => {
            // CTAP2 returns ECDSA-P256 as DER `SEQUENCE { INTEGER r,
            // INTEGER s }`. Delegate to the shared wire helper for
            // the `mpint(r) || mpint(s)` shape, then append the SSH
            // sk-* trailer (flags || counter).
            let rs = wire::ecdsa_der_to_ssh_mpint(raw_signature)?;
            let mut out = Vec::with_capacity(rs.len() + 5);
            out.extend_from_slice(&rs);
            out.push(flags);
            out.extend_from_slice(&counter.to_be_bytes());
            Ok(out)
        }
        other => Err(Error::Auth(format!(
            "fido2 signer: unsupported algorithm {other:?}"
        ))),
    }
}

/// Encode `(string algorithm_name || string sk_signature_blob)` as
/// a single length-prefixed SSH string. Matches the agent's
/// `write_signature` shape so russh's userauth packet writer can
/// inline it as the trailer of the userauth request.
pub(crate) fn encode_signature(
    algorithm: &Algorithm,
    sk_signature_blob: &[u8],
) -> Result<Vec<u8>, Error> {
    let name = algorithm_wire_name(algorithm)?;
    // Outer string contains `string(name) || string(sig_blob)`. The
    // 8 bytes account for the two inner length prefixes.
    let inner_len = name.len() + sk_signature_blob.len() + 8;
    let mut buf = Vec::with_capacity(inner_len + 4);
    buf.extend_from_slice(&(inner_len as u32).to_be_bytes());
    wire::push_ssh_string(&mut buf, name.as_bytes());
    wire::push_ssh_string(&mut buf, sk_signature_blob);
    Ok(buf)
}

/// Build the SK signature trailer for `to_sign` without the
/// outer `string(algorithm) || string(sig_blob)` wrapping that
/// the userauth path needs. Used by the in-process ssh-agent
/// endpoint — the agent wire response carries algorithm and
/// data as two separate fields, so the userauth concatenation
/// would double-wrap.
///
/// Returns `signature_blob || flags(u8) || counter(u32)` for
/// `sk-ed25519` and `mpint(r) || mpint(s) || flags || counter`
/// for `sk-ecdsa-p256`.
pub async fn sign_sk_blob_only(
    algorithm: &Algorithm,
    credential: &FidoCredential,
    to_sign: &[u8],
) -> Result<Vec<u8>, Error> {
    let _ = algorithm_wire_name(algorithm)?;

    let mut hasher = Sha256::new();
    hasher.update(to_sign);
    let challenge = hasher.finalize();

    let assertion = fido2::get_assertion(
        &credential.credential_id,
        &credential.application,
        challenge.as_slice(),
        credential.pin.as_deref(),
    )
    .await?;

    let flags = assertion.ssh_flags();
    let counter = assertion.ssh_counter();
    encode_sk_signature(algorithm, &assertion.signature, flags, counter)
}

/// Build the SSH-format signature for [`to_sign`] using the device
/// holding [`credential`]. Hashes the data with SHA-256, dispatches
/// to `lfs_core::fido2::get_assertion`, and composes the wire
/// signature russh expects to find at the tail of the userauth
/// request buffer.
pub async fn sign_for_userauth(
    algorithm: &Algorithm,
    credential: &FidoCredential,
    to_sign: &[u8],
) -> Result<Vec<u8>, Error> {
    let _ = algorithm_wire_name(algorithm)?; // early reject on bad algo

    let mut hasher = Sha256::new();
    hasher.update(to_sign);
    let challenge = hasher.finalize();

    let assertion = fido2::get_assertion(
        &credential.credential_id,
        &credential.application,
        challenge.as_slice(),
        credential.pin.as_deref(),
    )
    .await?;

    let raw_sig = if matches!(algorithm, Algorithm::SkEd25519) {
        // CTAP2 packs the Ed25519 signature as 64 raw bytes — pass
        // them straight through.
        assertion.signature.clone()
    } else {
        // ECDSA path stays in DER until `encode_sk_signature`
        // normalises into the SSH mpint shape.
        assertion.signature.clone()
    };

    let flags = assertion.ssh_flags();
    let counter = assertion.ssh_counter();
    let sk_blob = encode_sk_signature(algorithm, &raw_sig, flags, counter)?;
    encode_signature(algorithm, &sk_blob)
}

/// True when the SSH `Algorithm` is an `sk-*` variant; the connect
/// path uses this to dispatch to the FIDO signer rather than the
/// PEM-based one.
#[must_use]
pub fn is_sk_algorithm(algorithm: &Algorithm) -> bool {
    matches!(
        algorithm,
        Algorithm::SkEd25519 | Algorithm::SkEcdsaSha2NistP256
    )
}

/// Map a stored `key_type` short tag to the matching ssh-key
/// `Algorithm`. Mirrors the wire conventions captured at import:
/// `sk-ed25519` ↔ `Algorithm::SkEd25519` and `sk-ecdsa-p256` ↔
/// `Algorithm::SkEcdsaSha2NistP256`. Returns `None` for software
/// keys so the dispatcher falls through to the PEM path.
#[must_use]
pub fn algorithm_from_key_type(key_type: &str) -> Option<Algorithm> {
    match key_type {
        "sk-ed25519" | "sk-ssh-ed25519@openssh.com" => Some(Algorithm::SkEd25519),
        "sk-ecdsa-p256" | "sk-ecdsa-sha2-nistp256@openssh.com" => {
            Some(Algorithm::SkEcdsaSha2NistP256)
        }
        _ => None,
    }
}

/// HashAlg for an sk-* algorithm. Both Ed25519 and ECDSA-P256
/// variants are inherently SHA-2 wrap; the SSH userauth path
/// hashes the data before calling us, so this is only used for
/// the russh `auth_sign` parameter (kept `None` so russh doesn't
/// double-hash on RSA-shaped variants — sk-* keys never use RSA).
#[must_use]
pub fn hash_alg_for(_algorithm: &Algorithm) -> Option<HashAlg> {
    None
}

/// Extract the `application` string from a stored sk-* public key
/// (single-line OpenSSH-armored form). Used by the import path so
/// the DB row carries the same `application` field the server will
/// see at userauth time. Returns `None` when the line is not a
/// well-formed sk-* public key.
#[must_use]
pub fn extract_application_from_openssh_pub(pubkey_line: &str) -> Option<String> {
    let public = ssh_key::PublicKey::from_openssh(pubkey_line.trim()).ok()?;
    match public.key_data() {
        ssh_key::public::KeyData::SkEd25519(k) => Some(k.application().to_string()),
        ssh_key::public::KeyData::SkEcdsaSha2NistP256(k) => Some(k.application().to_string()),
        _ => None,
    }
}
#[cfg(test)]
#[path = "../../tests/unit/ssh_sk.rs"]
mod tests;
