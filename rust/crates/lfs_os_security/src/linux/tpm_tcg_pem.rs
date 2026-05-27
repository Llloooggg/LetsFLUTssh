//! TCG ASN.1 envelope for TPM 2.0 wrapped key pairs, per the
//! `draft-bottomley-tpm2-keys-asn1` IETF draft. Same shape
//! `openssl-tpm2-engine` and `ssh-tpm-agent` consume — interop is
//! a stated goal of both the T2 hardware-tier vault path and the
//! T-4 SSH-signing path.
//!
//! ## Shape
//!
//! Encoder/decoder cover the minimal subset both call sites need:
//!
//! ```asn1
//! TPMKey ::= SEQUENCE {
//!     type        OBJECT IDENTIFIER,    -- id-loadablekey (2.23.133.10.1.3)
//!     emptyAuth   [0] EXPLICIT BOOLEAN OPTIONAL,
//!     parent      INTEGER,              -- TPM_RH_OWNER (0x40000001) for storage primary
//!     pubkey      OCTET STRING,         -- marshalled TPM2B_PUBLIC
//!     privkey     OCTET STRING          -- marshalled TPM2B_PRIVATE
//! }
//! ```
//!
//! Optional fields the draft defines (`policy`, `secret`,
//! `authPolicy`, `description`, `rsaParent`) are not emitted by
//! either call site today (PCR-binding / external secret-injection
//! / parent-template overrides are v2 features). The parser
//! tolerates their presence by reading the type+length and skipping
//! the body so a `.tpm` file produced by `tpm2_create -r` +
//! `tpm2tss_genkey` round-trips through [`decode`] cleanly.
//!
//! ## DER discipline
//!
//! Hand-rolled minimal DER writer — the schema fans out to one
//! SEQUENCE, one OID, one INTEGER, two OCTET STRINGs and one
//! optional `[0] EXPLICIT BOOLEAN`. Pulling a full ASN.1 crate
//! (`der`, `simple_asn1`, `yasna`) for this surface would add a
//! compile-time dep with version-resolution coupling to the
//! pkcs8 / russh tree the workspace already pins precariously; the
//! writer here is ~120 LOC including tests and produces
//! byte-identical output to OpenSSL's `i2d_TSSPRIVKEY`.

#![cfg(target_os = "linux")]

use crate::linux::TpmError as Error;

/// `id-loadablekey` OID — `2.23.133.10.1.3`. The "TSS2 loadable key"
/// arm of the TCG ASN.1 draft; covers wrapped (public, private) blob
/// pairs created via `TPM2_Create` under a storage parent. The two
/// sibling arms (`id-importablekey`, `id-sealedkey`) are not emitted
/// or consumed here — neither call site needs them.
const OID_LOADABLE_KEY: &[u8] = &[0x67, 0x81, 0x05, 0x0a, 0x01, 0x03];

/// `TPM_RH_OWNER` parent handle constant per TCG Architecture Spec
/// §16.4.5. Both call sites parent their wrapped key under the
/// storage primary in the owner hierarchy, so the encoder stamps
/// this value unconditionally.
pub const TPM_RH_OWNER: u32 = 0x4000_0001;

/// DER tag bytes the encoder/decoder uses. Pulled out as constants
/// so the parser's tag-match branches read against named values
/// rather than ad-hoc hex.
const TAG_BOOLEAN: u8 = 0x01;
const TAG_INTEGER: u8 = 0x02;
const TAG_OCTET_STRING: u8 = 0x04;
const TAG_OID: u8 = 0x06;
const TAG_SEQUENCE: u8 = 0x30;
const TAG_CONTEXT_0_EXPLICIT: u8 = 0xA0;

/// Decoded TPMKey body. Both arms (`empty_auth` + the rest) are
/// straight pass-through to the caller; the encoder asks for the
/// same shape and round-trips byte-for-byte.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TpmKey {
    /// `[0] EXPLICIT BOOLEAN OPTIONAL`. `Some(true)` for a key
    /// created with `TPM2B_AUTH` empty — ssh-tpm-agent / openssl
    /// keys flip this on for the no-PIN flow. `Some(false)` /
    /// `None` are equivalent on read (DER default-value rule).
    pub empty_auth: Option<bool>,
    /// `INTEGER`. Caller stamps [`TPM_RH_OWNER`] for the storage
    /// primary path; the parser accepts any value so future parent
    /// override modes (`TPM_RH_PLATFORM`, persistent handle) round-
    /// trip.
    pub parent: u32,
    /// Marshalled `TPM2B_PUBLIC` per the TCG Marshal/Unmarshal
    /// header — the same bytes `Tss2_MU_TPM2B_PUBLIC_Marshal` writes.
    pub public: Vec<u8>,
    /// Marshalled `TPM2B_PRIVATE` per the TCG Marshal/Unmarshal
    /// header — `[u16 BE size][bytes]`. Same bytes
    /// `Tss2_MU_TPM2B_PRIVATE_Marshal` writes; the no-`PrivateBuffer`
    /// workaround in `tpm_native` produces a byte-identical frame
    /// by hand.
    pub private: Vec<u8>,
}

/// Encode `key` to TCG ASN.1 DER. Output is the inner DER body —
/// callers wrap in their own envelope (LFHV for the T2 vault, raw
/// PEM armour for the T-4 SSH on-disk artefact).
#[must_use]
pub fn encode(key: &TpmKey) -> Vec<u8> {
    let mut body = Vec::with_capacity(48 + key.public.len() + key.private.len());
    write_oid(&mut body, OID_LOADABLE_KEY);
    if let Some(value) = key.empty_auth {
        let mut inner = Vec::with_capacity(3);
        write_boolean(&mut inner, value);
        write_tlv(&mut body, TAG_CONTEXT_0_EXPLICIT, &inner);
    }
    write_integer(&mut body, key.parent);
    write_octet_string(&mut body, &key.public);
    write_octet_string(&mut body, &key.private);

    let mut out = Vec::with_capacity(body.len() + 8);
    write_tlv(&mut out, TAG_SEQUENCE, &body);
    out
}

/// Decode TCG ASN.1 DER bytes back to a [`TpmKey`]. Rejects
/// truncated input, wrong outer tag, wrong OID arm, and
/// length-overflow shapes. Unknown context tags (`[1]..[5]` from
/// the draft) get their TLV skipped so a `.tpm` file produced by
/// an external tool with a `description` or `policy` slot present
/// round-trips through the parser without losing the
/// (public, private) pair.
pub fn decode(bytes: &[u8]) -> Result<TpmKey, Error> {
    let (seq, rest) = read_tlv(bytes, TAG_SEQUENCE)?;
    if !rest.is_empty() {
        return Err(Error::Crypto(
            "tcg-pem: trailing bytes after SEQUENCE".into(),
        ));
    }
    let mut cursor = seq;
    let (oid, after_oid) = read_tlv(cursor, TAG_OID)?;
    if oid != OID_LOADABLE_KEY {
        return Err(Error::Crypto(format!(
            "tcg-pem: wrong key OID arm (got {} bytes, expected id-loadablekey)",
            oid.len()
        )));
    }
    cursor = after_oid;

    let mut fields = TcgFields::default();
    while !cursor.is_empty() {
        cursor = decode_field(cursor, &mut fields)?;
    }

    let parent = fields
        .parent
        .ok_or_else(|| Error::Crypto("tcg-pem: missing parent INTEGER".into()))?;
    let public = fields
        .public
        .ok_or_else(|| Error::Crypto("tcg-pem: missing public OCTET STRING".into()))?;
    let private = fields
        .private
        .ok_or_else(|| Error::Crypto("tcg-pem: missing private OCTET STRING".into()))?;
    Ok(TpmKey {
        empty_auth: fields.empty_auth,
        parent,
        public,
        private,
    })
}

/// Accumulator for the optional / ordered fields [`decode`] reads out
/// of the TCG SEQUENCE body.
#[derive(Default)]
struct TcgFields {
    empty_auth: Option<bool>,
    parent: Option<u32>,
    public: Option<Vec<u8>>,
    private: Option<Vec<u8>>,
}

/// Decode one TLV at `cursor`, fold it into `fields`, and return the
/// slice past it. The first OCTET STRING is `public`, the second
/// `private`; a third is an error. Unknown context-specific arms are
/// skipped so `.tpm` files carrying optional draft fields round-trip.
fn decode_field<'a>(cursor: &'a [u8], fields: &mut TcgFields) -> Result<&'a [u8], Error> {
    let tag = cursor[0];
    match tag {
        TAG_CONTEXT_0_EXPLICIT => {
            let (inner, next) = read_tlv(cursor, TAG_CONTEXT_0_EXPLICIT)?;
            let (bool_body, leftover) = read_tlv(inner, TAG_BOOLEAN)?;
            if !leftover.is_empty() {
                return Err(Error::Crypto(
                    "tcg-pem: trailing bytes in [0] EXPLICIT BOOLEAN".into(),
                ));
            }
            if bool_body.len() != 1 {
                return Err(Error::Crypto("tcg-pem: BOOLEAN length != 1".into()));
            }
            fields.empty_auth = Some(bool_body[0] != 0);
            Ok(next)
        }
        TAG_INTEGER => {
            let (int_body, next) = read_tlv(cursor, TAG_INTEGER)?;
            fields.parent = Some(parse_unsigned_integer(int_body)?);
            Ok(next)
        }
        TAG_OCTET_STRING => {
            let (octet_body, next) = read_tlv(cursor, TAG_OCTET_STRING)?;
            if fields.public.is_none() {
                fields.public = Some(octet_body.to_vec());
            } else if fields.private.is_none() {
                fields.private = Some(octet_body.to_vec());
            } else {
                return Err(Error::Crypto(
                    "tcg-pem: too many OCTET STRING fields".into(),
                ));
            }
            Ok(next)
        }
        other => {
            // Unknown context-specific arm — skip its TLV so the
            // parser tolerates `.tpm` files written by external
            // tools carrying optional draft fields.
            let (_, next) = read_tlv(cursor, other)?;
            Ok(next)
        }
    }
}

// ── DER primitives ──────────────────────────────────────────────

/// Write a (tag, length, body) triple. Length uses DER short / long
/// form per X.690 §8.1.3: `< 128` short, otherwise leading
/// `0x80 | len_octets` byte.
fn write_tlv(out: &mut Vec<u8>, tag: u8, body: &[u8]) {
    out.push(tag);
    write_length(out, body.len());
    out.extend_from_slice(body);
}

fn write_length(out: &mut Vec<u8>, len: usize) {
    if len < 0x80 {
        out.push(len as u8);
        return;
    }
    // Long-form: emit BE bytes with no leading zeros, then the
    // count octet `0x80 | n`.
    let bytes = len.to_be_bytes();
    let first_nonzero = bytes
        .iter()
        .position(|&b| b != 0)
        .unwrap_or(bytes.len() - 1);
    let trimmed = &bytes[first_nonzero..];
    out.push(0x80 | (trimmed.len() as u8));
    out.extend_from_slice(trimmed);
}

fn write_oid(out: &mut Vec<u8>, oid_bytes: &[u8]) {
    write_tlv(out, TAG_OID, oid_bytes);
}

fn write_boolean(out: &mut Vec<u8>, value: bool) {
    // DER §11.1: TRUE is `0xFF`, FALSE is `0x00`. BER would allow
    // any non-zero for TRUE but DER pins the byte.
    let byte = if value { 0xFF } else { 0x00 };
    write_tlv(out, TAG_BOOLEAN, &[byte]);
}

fn write_integer(out: &mut Vec<u8>, value: u32) {
    // INTEGER is signed; if the high bit of the top byte is set,
    // prepend a 0x00 padding byte so the encoded value stays
    // non-negative. Leading zeros otherwise stripped per DER.
    let bytes = value.to_be_bytes();
    let mut start = 0;
    while start < bytes.len() - 1 && bytes[start] == 0 && bytes[start + 1] & 0x80 == 0 {
        start += 1;
    }
    let trimmed = &bytes[start..];
    let mut buf = Vec::with_capacity(trimmed.len() + 1);
    if trimmed[0] & 0x80 != 0 {
        buf.push(0x00);
    }
    buf.extend_from_slice(trimmed);
    write_tlv(out, TAG_INTEGER, &buf);
}

fn write_octet_string(out: &mut Vec<u8>, bytes: &[u8]) {
    write_tlv(out, TAG_OCTET_STRING, bytes);
}

/// Read a single TLV with the expected tag. Returns `(body,
/// remaining_bytes_after_tlv)` so the caller can chain reads off
/// the trailing slice without tracking a cursor.
fn read_tlv(input: &[u8], expected_tag: u8) -> Result<(&[u8], &[u8]), Error> {
    if input.is_empty() {
        return Err(Error::Crypto(format!(
            "tcg-pem: expected tag {expected_tag:#x}, got empty input"
        )));
    }
    let tag = input[0];
    if tag != expected_tag {
        return Err(Error::Crypto(format!(
            "tcg-pem: tag mismatch (expected {expected_tag:#x}, got {tag:#x})"
        )));
    }
    let (len, header_len) = read_length(&input[1..])?;
    let total_header = 1 + header_len;
    let body_end = total_header
        .checked_add(len)
        .ok_or_else(|| Error::Crypto("tcg-pem: length overflow".into()))?;
    if body_end > input.len() {
        return Err(Error::Crypto(format!(
            "tcg-pem: declared length {len} exceeds buffer ({} bytes available after header)",
            input.len() - total_header.min(input.len())
        )));
    }
    Ok((&input[total_header..body_end], &input[body_end..]))
}

/// Read a DER length per X.690 §8.1.3. Returns `(length,
/// header_bytes_consumed)`. Refuses indefinite-length (`0x80`)
/// because DER bans it; refuses long-form lengths that would
/// overflow `usize` so a hostile envelope cannot wrap-around.
fn read_length(input: &[u8]) -> Result<(usize, usize), Error> {
    if input.is_empty() {
        return Err(Error::Crypto("tcg-pem: missing length byte".into()));
    }
    let first = input[0];
    if first < 0x80 {
        return Ok((first as usize, 1));
    }
    if first == 0x80 {
        return Err(Error::Crypto(
            "tcg-pem: indefinite-length forbidden in DER".into(),
        ));
    }
    let n = (first & 0x7F) as usize;
    if n == 0 || n > std::mem::size_of::<usize>() {
        return Err(Error::Crypto(format!(
            "tcg-pem: long-form length octet count {n} out of range"
        )));
    }
    if input.len() < 1 + n {
        return Err(Error::Crypto("tcg-pem: truncated long-form length".into()));
    }
    let mut value: usize = 0;
    for &b in &input[1..1 + n] {
        value = value
            .checked_shl(8)
            .and_then(|v| v.checked_add(b as usize))
            .ok_or_else(|| Error::Crypto("tcg-pem: long-form length overflow".into()))?;
    }
    Ok((value, 1 + n))
}

fn parse_unsigned_integer(body: &[u8]) -> Result<u32, Error> {
    if body.is_empty() {
        return Err(Error::Crypto("tcg-pem: empty INTEGER body".into()));
    }
    // DER INTEGER is signed two's complement. A negative value is
    // only one where the very first byte's high bit is set; the
    // encoder above always emits a sign-padding 0x00 ahead of a
    // magnitude byte whose high bit would otherwise look negative,
    // so a real negative value never carries that padding. Reject
    // any leading byte with the high bit set on the raw body.
    if body[0] & 0x80 != 0 {
        return Err(Error::Crypto("tcg-pem: negative INTEGER for parent".into()));
    }
    // Strip the conventional 0x00 sign-padding byte before
    // measuring width — `[0x00, 0x80]` encodes +128 in 2 bytes,
    // and we want to read it as a 1-byte magnitude.
    let stripped: &[u8] = if body.len() > 1 && body[0] == 0x00 {
        &body[1..]
    } else {
        body
    };
    if stripped.len() > 4 {
        return Err(Error::Crypto(format!(
            "tcg-pem: parent INTEGER too wide ({} bytes > 4)",
            stripped.len()
        )));
    }
    let mut value: u32 = 0;
    for &b in stripped {
        value = (value << 8) | (b as u32);
    }
    Ok(value)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample_key() -> TpmKey {
        TpmKey {
            empty_auth: Some(true),
            parent: TPM_RH_OWNER,
            public: vec![0xAA; 64],
            private: vec![0xBB; 80],
        }
    }

    #[test]
    fn encode_decode_round_trips() {
        let key = sample_key();
        let der = encode(&key);
        let decoded = decode(&der).expect("decode");
        assert_eq!(decoded, key);
    }

    #[test]
    fn encode_decode_round_trips_without_empty_auth() {
        let key = TpmKey {
            empty_auth: None,
            parent: TPM_RH_OWNER,
            public: vec![1, 2, 3, 4],
            private: vec![5, 6, 7, 8, 9],
        };
        let der = encode(&key);
        let decoded = decode(&der).expect("decode");
        assert_eq!(decoded, key);
    }

    #[test]
    fn encode_starts_with_sequence_tag() {
        let der = encode(&sample_key());
        assert_eq!(der[0], TAG_SEQUENCE);
    }

    #[test]
    fn decode_rejects_wrong_outer_tag() {
        let mut der = encode(&sample_key());
        der[0] = TAG_OCTET_STRING;
        assert!(decode(&der).is_err());
    }

    #[test]
    fn decode_rejects_missing_pub_octet_string() {
        // Construct a SEQUENCE { OID, INTEGER, OCTET STRING } —
        // only one OCTET STRING, so the parser cannot resolve the
        // private slot.
        let mut body = Vec::new();
        write_oid(&mut body, OID_LOADABLE_KEY);
        write_integer(&mut body, TPM_RH_OWNER);
        write_octet_string(&mut body, &[1, 2, 3]);
        let mut der = Vec::new();
        write_tlv(&mut der, TAG_SEQUENCE, &body);
        assert!(decode(&der).is_err());
    }

    #[test]
    fn decode_rejects_wrong_oid_arm() {
        // Replace the loadablekey OID with the importablekey OID
        // (2.23.133.10.1.4) — same prefix, last byte 0x04 instead
        // of 0x03. Decoder rejects because the encoder/parser
        // contract here only covers the loadablekey arm.
        let mut body = Vec::new();
        write_oid(&mut body, &[0x67, 0x81, 0x05, 0x0a, 0x01, 0x04]);
        write_integer(&mut body, TPM_RH_OWNER);
        write_octet_string(&mut body, &[1, 2, 3]);
        write_octet_string(&mut body, &[4, 5, 6]);
        let mut der = Vec::new();
        write_tlv(&mut der, TAG_SEQUENCE, &body);
        assert!(decode(&der).is_err());
    }

    #[test]
    fn decode_rejects_trailing_bytes_after_sequence() {
        let mut der = encode(&sample_key());
        der.push(0x00);
        assert!(decode(&der).is_err());
    }

    #[test]
    fn decode_rejects_indefinite_length() {
        // Outer SEQUENCE with indefinite-length form (0x80). DER
        // bans this — BER would allow it.
        let der = [TAG_SEQUENCE, 0x80, 0x00, 0x00];
        assert!(decode(&der).is_err());
    }

    #[test]
    fn decode_rejects_truncated_length() {
        // Long-form length byte declares 4 trailing length octets,
        // but the buffer only carries 2.
        let der = [TAG_SEQUENCE, 0x84, 0x00, 0x00];
        assert!(decode(&der).is_err());
    }

    #[test]
    fn decode_tolerates_unknown_context_tags() {
        // Inject a `[3] EXPLICIT OCTET STRING` between the parent
        // INTEGER and the public OCTET STRING — the draft's
        // `authPolicy` slot. Parser skips the unknown TLV cleanly
        // and the round trip recovers the (pub, priv) pair.
        let mut body = Vec::new();
        write_oid(&mut body, OID_LOADABLE_KEY);
        let mut empty_auth_inner = Vec::new();
        write_boolean(&mut empty_auth_inner, true);
        write_tlv(&mut body, TAG_CONTEXT_0_EXPLICIT, &empty_auth_inner);
        write_integer(&mut body, TPM_RH_OWNER);
        // Unknown [3] EXPLICIT arm — body is irrelevant to us.
        write_tlv(&mut body, 0xA3, &[0x04, 0x02, 0xDE, 0xAD]);
        write_octet_string(&mut body, &[0x10, 0x20, 0x30]);
        write_octet_string(&mut body, &[0x40, 0x50]);
        let mut der = Vec::new();
        write_tlv(&mut der, TAG_SEQUENCE, &body);

        let key = decode(&der).expect("decode");
        assert_eq!(key.empty_auth, Some(true));
        assert_eq!(key.parent, TPM_RH_OWNER);
        assert_eq!(key.public, vec![0x10, 0x20, 0x30]);
        assert_eq!(key.private, vec![0x40, 0x50]);
    }

    #[test]
    fn integer_encoder_pads_high_bit_set() {
        // Parent INTEGER 0x80 (high bit set as a u8) must round-
        // trip through a leading 0x00 padding byte; otherwise DER
        // would read it as a negative two's-complement.
        let key = TpmKey {
            empty_auth: None,
            parent: 0x80,
            public: vec![1],
            private: vec![2],
        };
        let der = encode(&key);
        let decoded = decode(&der).expect("decode");
        assert_eq!(decoded.parent, 0x80);
    }

    #[test]
    fn integer_encoder_strips_leading_zero_when_safe() {
        // Parent INTEGER 0x40000001 (TPM_RH_OWNER) — no leading
        // zero needed because the high bit of 0x40 is clear.
        let key = TpmKey {
            empty_auth: None,
            parent: TPM_RH_OWNER,
            public: vec![1],
            private: vec![2],
        };
        let der = encode(&key);
        // Locate the INTEGER inside the SEQUENCE: scan past the
        // SEQUENCE header, the OID TLV, then the INTEGER TLV.
        let (seq_body, _) = read_tlv(&der, TAG_SEQUENCE).unwrap();
        let (_, after_oid) = read_tlv(seq_body, TAG_OID).unwrap();
        let (int_body, _) = read_tlv(after_oid, TAG_INTEGER).unwrap();
        // 0x40000001 fits in 4 bytes with no padding.
        assert_eq!(int_body, [0x40, 0x00, 0x00, 0x01]);
    }

    #[test]
    fn long_form_length_round_trips_large_blobs() {
        // 256-byte OCTET STRING forces the long-form length
        // encoding for the inner TLV and pushes the outer SEQUENCE
        // past the 0x80 short-form threshold too. Catches any
        // off-by-one in `write_length` / `read_length`.
        let key = TpmKey {
            empty_auth: None,
            parent: TPM_RH_OWNER,
            public: vec![0xCC; 256],
            private: vec![0xDD; 256],
        };
        let der = encode(&key);
        let decoded = decode(&der).expect("decode");
        assert_eq!(decoded.public.len(), 256);
        assert_eq!(decoded.private.len(), 256);
    }
}
