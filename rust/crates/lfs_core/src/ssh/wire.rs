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
//! 3. **Raw signature blob** — RSA PKCS#1 v1.5 from PKCS#11 / NCrypt,
//!    Ed25519 from every backend. Wrapped verbatim by
//!    [`rsa_pkcs1_v15_to_ssh_blob`] / [`ed25519_to_ssh_blob`].
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

/// Wrap a raw RSA PKCS#1 v1.5 signature into the SSH userauth
/// `signature` blob shape — a single `string(sig)`. RSA signatures
/// are emitted verbatim by the backend (no DER normalisation needed)
/// so the wrapper is one length-prefix prepend.
pub fn rsa_pkcs1_v15_to_ssh_blob(sig: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(sig.len() + 4);
    push_ssh_string(&mut out, sig);
    out
}

/// Wrap a 64-byte Ed25519 signature into the SSH `signature` blob
/// shape. Asserts the length at runtime — every Ed25519 backend
/// returns exactly 64 bytes per RFC 8032.
pub fn ed25519_to_ssh_blob(sig: &[u8]) -> Result<Vec<u8>, Error> {
    if sig.len() != 64 {
        return Err(Error::Auth(format!(
            "ssh wire: ed25519 signature must be 64 bytes, got {}",
            sig.len()
        )));
    }
    let mut out = Vec::with_capacity(sig.len() + 4);
    push_ssh_string(&mut out, sig);
    Ok(out)
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
mod tests {
    use super::*;

    #[test]
    fn push_mpint_handles_msb_set() {
        let mut out = Vec::new();
        push_ssh_mpint(&mut out, &[0x80, 0x01]);
        // length prefix (4 BE) || 0x00 pad || payload
        assert_eq!(out, vec![0, 0, 0, 3, 0x00, 0x80, 0x01]);
    }

    #[test]
    fn push_mpint_strips_redundant_leading_zero() {
        let mut out = Vec::new();
        push_ssh_mpint(&mut out, &[0x00, 0x01, 0x02]);
        // The leading 0x00 was redundant (0x01 has MSB clear) — strip.
        assert_eq!(out, vec![0, 0, 0, 2, 0x01, 0x02]);
    }

    #[test]
    fn push_mpint_zero_value_encodes_as_empty() {
        let mut out = Vec::new();
        push_ssh_mpint(&mut out, &[]);
        assert_eq!(out, vec![0, 0, 0, 0]);
    }

    #[test]
    fn push_mpint_all_zero_input_collapses_to_single_byte() {
        let mut out = Vec::new();
        push_ssh_mpint(&mut out, &[0x00, 0x00, 0x00]);
        assert_eq!(out, vec![0, 0, 0, 1, 0x00]);
    }

    #[test]
    fn ecdsa_der_round_trip_simple_sequence() {
        // SEQUENCE { INTEGER 0x01, INTEGER 0x02 } → mpint(1) || mpint(2)
        let der = [0x30, 0x06, 0x02, 0x01, 0x01, 0x02, 0x01, 0x02];
        let out = ecdsa_der_to_ssh_mpint(&der).unwrap();
        assert_eq!(
            out,
            vec![
                0, 0, 0, 1, 0x01, // mpint r
                0, 0, 0, 1, 0x02, // mpint s
            ]
        );
    }

    #[test]
    fn ecdsa_der_preserves_high_bit_padding() {
        // SEQUENCE { INTEGER 0x80, INTEGER 0x02 }. The DER decoder
        // saw the high bit on 0x80 and prepended 0x00; mpint output
        // must keep the pad byte so the value stays positive.
        let der = [0x30, 0x06, 0x02, 0x01, 0x80, 0x02, 0x01, 0x02];
        let out = ecdsa_der_to_ssh_mpint(&der).unwrap();
        assert_eq!(
            out,
            vec![
                0, 0, 0, 2, 0x00, 0x80, // mpint r
                0, 0, 0, 1, 0x02, // mpint s
            ]
        );
    }

    #[test]
    fn ecdsa_der_rejects_trailing_bytes() {
        let bad = [0x30, 0x06, 0x02, 0x01, 0x01, 0x02, 0x01, 0x02, 0xff];
        let err = ecdsa_der_to_ssh_mpint(&bad).unwrap_err();
        assert!(matches!(err, Error::Auth(_)));
    }

    #[test]
    fn ecdsa_der_rejects_truncated_header() {
        let err = ecdsa_der_to_ssh_mpint(&[0x30]).unwrap_err();
        assert!(matches!(err, Error::Auth(_)));
    }

    #[test]
    fn ecdsa_der_does_not_panic_on_random_input() {
        // Property-style sweep — feed every 4-byte byte tuple with
        // SEQUENCE-tagged prefix and assert the parser never panics.
        for a in 0u8..=255 {
            for b in [0u8, 1, 0x7f, 0x80, 0xff] {
                let buf = [0x30, 0x02, 0x02, a, b];
                let _ = ecdsa_der_to_ssh_mpint(&buf);
            }
        }
        // Pure-random short slices.
        let mut state: u32 = 0x9E37_79B9;
        for _ in 0..2048 {
            state = state.wrapping_mul(1_103_515_245).wrapping_add(12345);
            let len = (state as usize % 32) + 1;
            let mut buf = Vec::with_capacity(len);
            for i in 0..len {
                buf.push(((state >> (i % 16)) & 0xff) as u8);
            }
            let _ = ecdsa_der_to_ssh_mpint(&buf);
        }
    }

    #[test]
    fn ecdsa_raw_concat_round_trips() {
        let raw = vec![0x11u8; 32]
            .into_iter()
            .chain(vec![0x22u8; 32])
            .collect::<Vec<_>>();
        let out = ecdsa_raw_concat_to_ssh_mpint(&raw).unwrap();
        // r (32 × 0x11) — first byte's MSB is clear, no pad
        assert_eq!(&out[..4], &[0, 0, 0, 32]);
        assert_eq!(&out[4..36], &[0x11u8; 32][..]);
        assert_eq!(&out[36..40], &[0, 0, 0, 32]);
        assert_eq!(&out[40..72], &[0x22u8; 32][..]);
    }

    #[test]
    fn ecdsa_raw_concat_adds_pad_for_msb_set_component() {
        let mut raw = vec![0u8; 64];
        raw[0] = 0x80; // r component starts with high bit set
        let out = ecdsa_raw_concat_to_ssh_mpint(&raw).unwrap();
        // r becomes 33 bytes (1 pad + 32 magnitude), s stays empty
        // mpint canonical: an all-zero magnitude after the high-bit
        // sentinel still emits as a non-empty mpint when the MSB is
        // set on the first byte of the original window.
        // Length prefix r:
        assert_eq!(&out[..4], &[0, 0, 0, 33]);
        assert_eq!(out[4], 0x00);
        assert_eq!(out[5], 0x80);
        // remaining bytes of r are zeros
        assert!(out[6..37].iter().all(|&b| b == 0));
        // s component: all zeros — collapses to single 0x00 byte mpint.
        assert_eq!(&out[37..41], &[0, 0, 0, 1]);
        assert_eq!(out[41], 0x00);
    }

    #[test]
    fn ecdsa_raw_concat_rejects_odd_length() {
        let err = ecdsa_raw_concat_to_ssh_mpint(&[0u8; 31]).unwrap_err();
        assert!(matches!(err, Error::Auth(_)));
    }

    #[test]
    fn ecdsa_raw_concat_rejects_empty() {
        let err = ecdsa_raw_concat_to_ssh_mpint(&[]).unwrap_err();
        assert!(matches!(err, Error::Auth(_)));
    }

    #[test]
    fn rsa_pkcs1_v15_wraps_with_length() {
        let sig = [0xAAu8; 256];
        let out = rsa_pkcs1_v15_to_ssh_blob(&sig);
        assert_eq!(&out[..4], &[0, 0, 1, 0]); // 256 BE
        assert_eq!(&out[4..], &sig[..]);
    }

    #[test]
    fn ed25519_wraps_64_bytes() {
        let sig = [0xCCu8; 64];
        let out = ed25519_to_ssh_blob(&sig).unwrap();
        assert_eq!(&out[..4], &[0, 0, 0, 64]);
        assert_eq!(&out[4..], &sig[..]);
    }

    #[test]
    fn ed25519_rejects_wrong_size() {
        let err = ed25519_to_ssh_blob(&[0u8; 32]).unwrap_err();
        assert!(matches!(err, Error::Auth(_)));
    }

    #[test]
    fn ecdsa_public_blob_matches_ssh_keygen_shape() {
        // Known vector — a synthetic P-256 point. ssh-keygen emits
        // the same three SSH strings in the same order.
        let mut point = vec![0x04u8];
        point.extend(std::iter::repeat_n(0xAA, 32)); // X
        point.extend(std::iter::repeat_n(0xBB, 32)); // Y
        let out = encode_public_ecdsa_p256(&point).unwrap();
        // string "ecdsa-sha2-nistp256"
        assert_eq!(&out[..4], &[0, 0, 0, 19]);
        assert_eq!(&out[4..23], b"ecdsa-sha2-nistp256");
        // string "nistp256"
        assert_eq!(&out[23..27], &[0, 0, 0, 8]);
        assert_eq!(&out[27..35], b"nistp256");
        // string Q (65 bytes)
        assert_eq!(&out[35..39], &[0, 0, 0, 65]);
        assert_eq!(out[39], 0x04);
        assert_eq!(out.len(), 4 + 19 + 4 + 8 + 4 + 65);
    }

    #[test]
    fn ecdsa_public_blob_rejects_wrong_point_format() {
        let bad = vec![0x02u8; 65]; // compressed point — outside SSH scope
        let err = encode_public_ecdsa_p256(&bad).unwrap_err();
        assert!(matches!(err, Error::Auth(_)));
    }

    #[test]
    fn ed25519_public_blob_round_trip() {
        let raw = [0x55u8; 32];
        let out = encode_public_ed25519(&raw).unwrap();
        assert_eq!(&out[..4], &[0, 0, 0, 11]);
        assert_eq!(&out[4..15], b"ssh-ed25519");
        assert_eq!(&out[15..19], &[0, 0, 0, 32]);
        assert_eq!(&out[19..], &raw[..]);
    }

    #[test]
    fn rsa_public_blob_emits_e_then_n() {
        // ssh-keygen writes ssh-rsa keys as `string("ssh-rsa") || mpint(e) || mpint(n)`.
        // The canonical exponent (65537) starts with 0x01 so no pad.
        // The modulus is fixture-only.
        let exponent = [0x01, 0x00, 0x01];
        let modulus = [0xC1, 0x23];
        let out = encode_public_rsa(&modulus, &exponent);
        // "ssh-rsa"
        assert_eq!(&out[..4], &[0, 0, 0, 7]);
        assert_eq!(&out[4..11], b"ssh-rsa");
        // mpint(e)
        assert_eq!(&out[11..15], &[0, 0, 0, 3]);
        assert_eq!(&out[15..18], &exponent[..]);
        // mpint(n) — high bit on 0xC1 → pad with 0x00 → length 3
        assert_eq!(&out[18..22], &[0, 0, 0, 3]);
        assert_eq!(out[22], 0x00);
        assert_eq!(out[23], 0xC1);
        assert_eq!(out[24], 0x23);
    }
}
