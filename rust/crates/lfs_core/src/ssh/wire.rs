//! SSH wire-format primitives shared across every hardware-bound
//! signer (FIDO2 `sk-*` today, PKCS#11 / TPM 2.0 / Secure Enclave /
//! Windows NCrypt / Android Hardware Keystore as they land).
//!
//! Every helper here speaks the byte layout RFC 4253 §6.6 prescribes
//! for the userauth `signature` and public-key blob fields:
//!
//! - `string` — `u32 BE length || raw bytes`
//! - `mpint` — `string` of the integer's big-endian magnitude with
//!   a leading `0x00` byte iff the MSB of the first real byte is set
//!   (SSH mpints are signed)
//!
//! Signatures arrive from hardware backends in three shapes:
//!
//! 1. **ASN.1 DER `SEQUENCE { INTEGER r, INTEGER s }`** — CTAP2, Apple
//!    Secure Enclave, anything calling OpenSSL `ECDSA_sign`. Routed
//!    through [`ecdsa_der_to_ssh_mpint`].
//! 2. **Fixed-width raw `r || s`** — Windows NCrypt `NCryptSignHash`,
//!    Android Keystore `Signature.sign` when configured for the
//!    `NONEwithECDSA` form. Routed through
//!    [`ecdsa_raw_concat_to_ssh_mpint`].
//! 3. **Raw signature** — RSA PKCS#1 v1.5 from PKCS#11 / NCrypt / TPM,
//!    Ed25519 from every backend. The body is the raw signature;
//!    [`rsa_pkcs1_v15_sig_body`] / [`ed25519_sig_body`] return it for
//!    the caller to wrap once as `string(algorithm) || string(body)`.
//!
//! The public-key encoders ([`encode_public_ecdsa_p256`],
//! [`encode_public_ed25519`], [`encode_public_rsa`]) build the
//! authorized_keys-compatible blob the FRB import surface persists
//! verbatim alongside the credential metadata.

use crate::error::Error;

/// Length budget on a single DER length field. RFC 4253 SSH messages
/// cap at 256 KiB; an ECDSA signature component fits in 66 bytes, so
/// a length running to four bytes (≥16 MiB) is malformed input by
/// definition — reject before allocating.
const DER_MAX_LENGTH_BYTES: usize = 4;

/// Push an SSH `string` (`u32 BE length || bytes`) onto `buf`.
pub fn push_ssh_string(buf: &mut Vec<u8>, payload: &[u8]) {
    buf.extend_from_slice(&(payload.len() as u32).to_be_bytes());
    buf.extend_from_slice(payload);
}

/// Push an SSH `mpint` (length-prefixed signed integer) onto `buf`.
///
/// Strips one leading 0x00 byte when dropping it would not flip the
/// sign — preserves the SSH-on-the-wire shape OpenSSH itself emits.
/// Re-adds a leading 0x00 when the high bit of the first byte is set
/// so the value stays positive. An empty / all-zero input encodes as
/// the canonical zero (single 0x00 byte) — matches RFC 4251 §5.
pub fn push_ssh_mpint(buf: &mut Vec<u8>, magnitude: &[u8]) {
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

/// Parse ASN.1 DER `SEQUENCE { INTEGER r, INTEGER s }` and emit
/// `mpint(r) || mpint(s)` — the body that goes inside the SSH
/// signature blob for ECDSA-P256 / P384 / P521 sk-* paths. The output
/// does NOT carry an outer SSH `string` prefix — caller wraps in
/// `string(...)` if the userauth shape demands it.
///
/// Strict shape — accepts only the bytes OpenSSH itself parses:
/// definite-length encoding, no trailing bytes, integer length fields
/// up to four bytes (anything wider is structurally malformed for an
/// EC signature component).
pub fn ecdsa_der_to_ssh_mpint(der: &[u8]) -> Result<Vec<u8>, Error> {
    let (r, s) = parse_ecdsa_der(der)?;
    let mut out = Vec::with_capacity(r.len() + s.len() + 16);
    push_ssh_string(&mut out, &r);
    push_ssh_string(&mut out, &s);
    Ok(out)
}

/// Split fixed-width raw `r || s` (NCrypt / Android Keystore shape)
/// and emit `mpint(r) || mpint(s)`. Input length MUST be even; an
/// odd length returns `Error::Auth` rather than panicking.
pub fn ecdsa_raw_concat_to_ssh_mpint(rs: &[u8]) -> Result<Vec<u8>, Error> {
    if rs.len() % 2 != 0 || rs.is_empty() {
        return Err(Error::Auth(format!(
            "ssh wire: ecdsa raw r||s must be non-empty and even-length, got {} bytes",
            rs.len()
        )));
    }
    let half = rs.len() / 2;
    let mut out = Vec::with_capacity(rs.len() + 16);
    push_ssh_mpint(&mut out, &rs[..half]);
    push_ssh_mpint(&mut out, &rs[half..]);
    Ok(out)
}

/// Return the SSH signature *body* for an RSA PKCS#1 v1.5 signature —
/// the raw signature bytes verbatim. For RSA the body is the signature
/// itself (no DER normalisation, no mpint shaping), so this is the
/// identity, kept for call-site symmetry with the ECDSA helpers.
///
/// Like [`ecdsa_der_to_ssh_mpint`], the output is the bare body — no
/// SSH `string` prefix. The caller passes it to
/// [`encode_userauth_signature_field`], which adds the algorithm name
/// and the outer wrapping.
pub fn rsa_pkcs1_v15_sig_body(sig: &[u8]) -> Vec<u8> {
    sig.to_vec()
}

/// Return the SSH signature *body* for an Ed25519 signature — the raw
/// 64 bytes. Asserts the length at runtime (every Ed25519 backend
/// returns exactly 64 bytes per RFC 8032). Like the ECDSA / RSA
/// helpers the output is the bare body; the caller passes it to
/// [`encode_userauth_signature_field`].
pub fn ed25519_sig_body(sig: &[u8]) -> Result<Vec<u8>, Error> {
    if sig.len() != 64 {
        return Err(Error::Auth(format!(
            "ssh wire: ed25519 signature must be 64 bytes, got {}",
            sig.len()
        )));
    }
    let mut out = Vec::with_capacity(sig.len());
    out.extend_from_slice(sig);
    Ok(out)
}

/// Build the SSH userauth `signature` field: ONE outer SSH `string`
/// wrapping the signature blob `string(algorithm) || string(body)`.
///
/// Every `russh::Signer` appends this to the `to_sign` buffer russh
/// hands it. The server (and `russh`'s own bare-key path, via
/// `sign_with_hash_alg(..).encode(buffer)`) reads the field as a
/// SINGLE SSH string and then decodes the inner blob as an
/// `ssh_key::Signature`. The outer wrap is mandatory: omitting it
/// makes the length prefix wrong and the server rejects the
/// credential. The 8 bytes cover the two inner `string` prefixes.
pub fn encode_userauth_signature_field(wire_alg: &str, sig_body: &[u8]) -> Vec<u8> {
    let inner_len = wire_alg.len() + sig_body.len() + 8;
    let mut out = Vec::with_capacity(inner_len + 4);
    out.extend_from_slice(&(inner_len as u32).to_be_bytes());
    push_ssh_string(&mut out, wire_alg.as_bytes());
    push_ssh_string(&mut out, sig_body);
    out
}

/// Wrap an uncompressed ECDSA-P256 public point (`0x04 || X(32) ||
/// Y(32)`) into the SSH `ecdsa-sha2-nistp256` public-key blob:
///
/// ```text
/// string "ecdsa-sha2-nistp256"
/// string "nistp256"
/// string Q (uncompressed point — 0x04 || X || Y)
/// ```
///
/// Rejects inputs that are not 65 bytes or whose leading byte is not
/// `0x04` (compressed / hybrid point formats are not in SSH scope).
pub fn encode_public_ecdsa_p256(uncompressed_65: &[u8]) -> Result<Vec<u8>, Error> {
    if uncompressed_65.len() != 65 || uncompressed_65[0] != 0x04 {
        return Err(Error::Auth(format!(
            "ssh wire: ecdsa-p256 public point must be 65 bytes starting with 0x04, got len {} first 0x{:02x}",
            uncompressed_65.len(),
            uncompressed_65.first().copied().unwrap_or(0)
        )));
    }
    let mut out = Vec::with_capacity(96);
    push_ssh_string(&mut out, b"ecdsa-sha2-nistp256");
    push_ssh_string(&mut out, b"nistp256");
    push_ssh_string(&mut out, uncompressed_65);
    Ok(out)
}

/// Wrap an uncompressed ECDSA-P384 public point (`0x04 || X(48) ||
/// Y(48)`) into the SSH `ecdsa-sha2-nistp384` public-key blob:
///
/// ```text
/// string "ecdsa-sha2-nistp384"
/// string "nistp384"
/// string Q (uncompressed point — 0x04 || X || Y)
/// ```
///
/// Rejects inputs that are not 97 bytes or whose leading byte is not
/// `0x04`.
pub fn encode_public_ecdsa_p384(uncompressed_97: &[u8]) -> Result<Vec<u8>, Error> {
    if uncompressed_97.len() != 97 || uncompressed_97[0] != 0x04 {
        return Err(Error::Auth(format!(
            "ssh wire: ecdsa-p384 public point must be 97 bytes starting with 0x04, got len {} first 0x{:02x}",
            uncompressed_97.len(),
            uncompressed_97.first().copied().unwrap_or(0)
        )));
    }
    let mut out = Vec::with_capacity(128);
    push_ssh_string(&mut out, b"ecdsa-sha2-nistp384");
    push_ssh_string(&mut out, b"nistp384");
    push_ssh_string(&mut out, uncompressed_97);
    Ok(out)
}

/// Wrap a 32-byte raw Ed25519 public key into the SSH `ssh-ed25519`
/// public-key blob:
///
/// ```text
/// string "ssh-ed25519"
/// string A (32 raw bytes)
/// ```
pub fn encode_public_ed25519(raw_32: &[u8]) -> Result<Vec<u8>, Error> {
    if raw_32.len() != 32 {
        return Err(Error::Auth(format!(
            "ssh wire: ed25519 public key must be 32 bytes, got {}",
            raw_32.len()
        )));
    }
    let mut out = Vec::with_capacity(52);
    push_ssh_string(&mut out, b"ssh-ed25519");
    push_ssh_string(&mut out, raw_32);
    Ok(out)
}

/// Wrap an RSA public key (modulus `n`, exponent `e`) into the SSH
/// `ssh-rsa` public-key blob:
///
/// ```text
/// string "ssh-rsa"
/// mpint  e
/// mpint  n
/// ```
///
/// Magnitudes go in big-endian unsigned; [`push_ssh_mpint`] handles
/// the leading-zero discipline.
pub fn encode_public_rsa(modulus: &[u8], exponent: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(modulus.len() + exponent.len() + 24);
    push_ssh_string(&mut out, b"ssh-rsa");
    push_ssh_mpint(&mut out, exponent);
    push_ssh_mpint(&mut out, modulus);
    out
}

// ---- internal DER parser ----------------------------------------

fn parse_ecdsa_der(der: &[u8]) -> Result<(Vec<u8>, Vec<u8>), Error> {
    let mut idx = 0;
    if der.len() < 2 || der[idx] != 0x30 {
        return Err(Error::Auth("ssh wire: bad DER (SEQUENCE tag)".into()));
    }
    idx += 1;
    let seq_len = read_der_length(der, &mut idx)?;
    if idx + seq_len != der.len() {
        return Err(Error::Auth("ssh wire: bad DER (SEQUENCE length)".into()));
    }
    let r = read_der_integer(der, &mut idx)?;
    let s = read_der_integer(der, &mut idx)?;
    if idx != der.len() {
        return Err(Error::Auth("ssh wire: bad DER (trailing bytes)".into()));
    }
    Ok((r, s))
}

fn read_der_length(buf: &[u8], idx: &mut usize) -> Result<usize, Error> {
    if *idx >= buf.len() {
        return Err(Error::Auth("ssh wire: truncated DER length".into()));
    }
    let first = buf[*idx];
    *idx += 1;
    if first & 0x80 == 0 {
        return Ok(first as usize);
    }
    let nbytes = (first & 0x7f) as usize;
    if nbytes == 0 || nbytes > DER_MAX_LENGTH_BYTES || *idx + nbytes > buf.len() {
        return Err(Error::Auth("ssh wire: bad DER length encoding".into()));
    }
    let mut len = 0usize;
    for _ in 0..nbytes {
        len = (len << 8) | (buf[*idx] as usize);
        *idx += 1;
    }
    Ok(len)
}

fn read_der_integer(buf: &[u8], idx: &mut usize) -> Result<Vec<u8>, Error> {
    if *idx >= buf.len() || buf[*idx] != 0x02 {
        return Err(Error::Auth("ssh wire: bad DER (INTEGER tag)".into()));
    }
    *idx += 1;
    let len = read_der_length(buf, idx)?;
    if *idx + len > buf.len() || len == 0 {
        return Err(Error::Auth("ssh wire: truncated DER INTEGER".into()));
    }
    let mut bytes = buf[*idx..*idx + len].to_vec();
    *idx += len;
    while bytes.len() > 1 && bytes[0] == 0x00 && bytes[1] & 0x80 == 0 {
        bytes.remove(0);
    }
    if !bytes.is_empty() && bytes[0] & 0x80 != 0 {
        bytes.insert(0, 0x00);
    }
    Ok(bytes)
}
#[cfg(test)]
#[path = "../../tests/unit/ssh_wire.rs"]
mod tests;
