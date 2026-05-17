//! PKCS#11 key enumeration + public-blob extraction.
//!
//! The import wizard's "pick a key" step needs to surface every
//! signable object on a token (RSA, ECDSA P-256/384/521, Ed25519)
//! with a human label, a CKA_ID handle the connect path uses to
//! reach the private half on every sign, and the SSH-wire public-key
//! bytes the manager persists. GOST keys (`CKK_GOSTR3410`) are
//! surfaced as a fourth `KeyClass::Gost` variant so the picker can
//! render the row disabled with the "GOST cannot be used with SSH"
//! reason — listing-only, not selectable.

#![cfg(any(target_os = "linux", target_os = "macos", target_os = "windows"))]

use cryptoki::object::{Attribute, AttributeType, KeyType, ObjectClass, ObjectHandle};
use cryptoki::session::Session as CkSession;

use super::error::Error;

/// SSH-mappable subset of CKK_* key types.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum KeyClass {
    /// `CKK_RSA` (≥ 2048-bit modulus enforced by the picker). Maps to
    /// SSH `rsa-sha2-256` / `rsa-sha2-512`.
    Rsa,
    /// `CKK_EC` with `prime256v1` / `secp384r1` / `secp521r1` curves.
    /// Maps to `ecdsa-sha2-nistp{256,384,521}`.
    EcdsaP256,
    EcdsaP384,
    EcdsaP521,
    /// `CKK_EC_EDWARDS` with Ed25519 OID. Maps to `ssh-ed25519`.
    Ed25519,
    /// `CKK_GOSTR3410` — visible in the picker but disabled (no SSH
    /// wire suite). Carries the curve OID in `0` for the UI label.
    Gost(String),
}

/// Listing entry for a private-key object on the token.
#[derive(Debug, Clone)]
pub struct KeyMeta {
    pub class: KeyClass,
    pub label: String,
    pub id: Vec<u8>,
    /// SSH `authorized_keys`-shape public key body (binary). Empty
    /// for GOST keys (we cannot encode them).
    pub ssh_public_blob: Vec<u8>,
}

/// `ssh_keys.key_type` short tag matching the project's existing
/// convention (see `lfs_core::keys::short_key_type`). PKCS#11 rows
/// use the same algorithm short tag as software keys so the connect
/// path's wire-name mapping stays single-table.
impl KeyClass {
    pub fn ssh_key_type(&self) -> Option<&'static str> {
        match self {
            Self::Rsa => Some("rsa"),
            Self::EcdsaP256 => Some("ecdsa-p256"),
            Self::EcdsaP384 => Some("ecdsa-p384"),
            Self::EcdsaP521 => Some("ecdsa-p521"),
            Self::Ed25519 => Some("ed25519"),
            Self::Gost(_) => None,
        }
    }
}

/// Walk every public-key object on the session and return its
/// classified metadata. Private-key handles for the matching
/// `id` get resolved at sign-time inside `pkcs11_sign`.
///
/// We list public keys (not private) for two reasons:
/// 1. The public half carries the SSH-wire blob we need to persist
///    at import time. Private-key attribute reads frequently require
///    login for `CKA_*`; public keys are anonymous.
/// 2. A private-key handle without a matching public half is not
///    usable for SSH (the protocol needs the public blob in the
///    `SSH_MSG_USERAUTH_REQUEST`); skipping the private-key listing
///    avoids surfacing rows the user couldn't act on.
pub fn list_signable_keys(session: &CkSession) -> Result<Vec<KeyMeta>, Error> {
    let template = [Attribute::Class(ObjectClass::PUBLIC_KEY)];
    let handles = session.find_objects(&template).map_err(Error::from)?;
    let mut out = Vec::with_capacity(handles.len());
    for h in handles {
        match metadata_for(session, h) {
            Ok(Some(meta)) => out.push(meta),
            Ok(None) => continue,
            // Skip individual objects whose attribute fetch fails —
            // an unreadable key on a multi-key token must not nuke
            // the rest of the listing.
            Err(_e) => continue,
        }
    }
    Ok(out)
}

fn metadata_for(session: &CkSession, handle: ObjectHandle) -> Result<Option<KeyMeta>, Error> {
    let attrs = session
        .get_attributes(
            handle,
            &[
                AttributeType::KeyType,
                AttributeType::Label,
                AttributeType::Id,
                AttributeType::EcParams,
                AttributeType::EcPoint,
                AttributeType::Modulus,
                AttributeType::PublicExponent,
            ],
        )
        .map_err(Error::from)?;

    let mut key_type: Option<KeyType> = None;
    let mut label_bytes: Option<Vec<u8>> = None;
    let mut id_bytes: Option<Vec<u8>> = None;
    let mut ec_params: Option<Vec<u8>> = None;
    let mut ec_point: Option<Vec<u8>> = None;
    let mut modulus: Option<Vec<u8>> = None;
    let mut exponent: Option<Vec<u8>> = None;

    for attr in attrs {
        match attr {
            Attribute::KeyType(k) => key_type = Some(k),
            Attribute::Label(b) => label_bytes = Some(b),
            Attribute::Id(b) => id_bytes = Some(b),
            Attribute::EcParams(b) => ec_params = Some(b),
            Attribute::EcPoint(b) => ec_point = Some(b),
            Attribute::Modulus(b) => modulus = Some(b),
            Attribute::PublicExponent(b) => exponent = Some(b),
            _ => {}
        }
    }

    let Some(kt) = key_type else {
        return Ok(None);
    };

    let label = label_bytes
        .map(|b| String::from_utf8_lossy(&b).to_string())
        .unwrap_or_default();
    let id = id_bytes.unwrap_or_default();

    if kt == KeyType::RSA {
        let modulus = modulus.ok_or_else(|| Error::Other("rsa: no modulus attr".into()))?;
        let exponent =
            exponent.ok_or_else(|| Error::Other("rsa: no public exponent attr".into()))?;
        return Ok(Some(KeyMeta {
            class: KeyClass::Rsa,
            label,
            id,
            ssh_public_blob: encode_ssh_rsa_public(&modulus, &exponent),
        }));
    }
    if kt == KeyType::EC {
        let params = ec_params.ok_or_else(|| Error::Other("ec: no ec_params attr".into()))?;
        let raw_point = ec_point.ok_or_else(|| Error::Other("ec: no ec_point attr".into()))?;
        let class = classify_ec_curve(&params)?;
        let uncompressed = strip_octet_string_wrapper(&raw_point)?;
        let blob = match class {
            KeyClass::EcdsaP256 => {
                encode_ssh_ecdsa(&uncompressed, b"nistp256", b"ecdsa-sha2-nistp256")?
            }
            KeyClass::EcdsaP384 => {
                encode_ssh_ecdsa(&uncompressed, b"nistp384", b"ecdsa-sha2-nistp384")?
            }
            KeyClass::EcdsaP521 => {
                encode_ssh_ecdsa(&uncompressed, b"nistp521", b"ecdsa-sha2-nistp521")?
            }
            _ => return Ok(None),
        };
        return Ok(Some(KeyMeta {
            class,
            label,
            id,
            ssh_public_blob: blob,
        }));
    }
    if kt == KeyType::EC_EDWARDS {
        // Ed25519 raw key bytes live inside an OCTET STRING wrapper
        // when stored as `CKA_EC_POINT`. PKCS#11 v3.0 §6.4.2.
        let raw_point = ec_point.ok_or_else(|| Error::Other("ed: no ec_point attr".into()))?;
        let raw = strip_octet_string_wrapper(&raw_point)?;
        if raw.len() != 32 {
            return Err(Error::Other(format!(
                "ed25519 raw key wrong length: {}",
                raw.len()
            )));
        }
        let blob = encode_ssh_ed25519(&raw);
        return Ok(Some(KeyMeta {
            class: KeyClass::Ed25519,
            label,
            id,
            ssh_public_blob: blob,
        }));
    }
    // CKK_GOSTR3410 = 0x30; surface as a disabled row.
    if (*kt) == 0x30 {
        let oid_label = ec_params
            .as_ref()
            .map(|b| {
                b.iter()
                    .map(|x| format!("{x:02x}"))
                    .collect::<Vec<_>>()
                    .join(":")
            })
            .unwrap_or_else(|| "unknown".into());
        return Ok(Some(KeyMeta {
            class: KeyClass::Gost(oid_label),
            label,
            id,
            ssh_public_blob: Vec::new(),
        }));
    }
    // Anything else — unsupported, skip.
    Ok(None)
}

/// `CKA_EC_PARAMS` carries a DER-encoded ANSI X9.62 OID. We recognise
/// the three NIST curves SSH uses and refuse everything else (the
/// caller treats `Ok(None)` as "not surfaced").
fn classify_ec_curve(der: &[u8]) -> Result<KeyClass, Error> {
    // P-256 OID: 06 08 2A 86 48 CE 3D 03 01 07
    const P256: &[u8] = &[0x06, 0x08, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x03, 0x01, 0x07];
    // P-384 OID: 06 05 2B 81 04 00 22
    const P384: &[u8] = &[0x06, 0x05, 0x2B, 0x81, 0x04, 0x00, 0x22];
    // P-521 OID: 06 05 2B 81 04 00 23
    const P521: &[u8] = &[0x06, 0x05, 0x2B, 0x81, 0x04, 0x00, 0x23];
    if der == P256 {
        Ok(KeyClass::EcdsaP256)
    } else if der == P384 {
        Ok(KeyClass::EcdsaP384)
    } else if der == P521 {
        Ok(KeyClass::EcdsaP521)
    } else {
        Err(Error::UnsupportedKeyType(format!(
            "unrecognised EC curve OID: {} bytes",
            der.len()
        )))
    }
}

/// `CKA_EC_POINT` is a DER OCTET STRING wrapping the raw point bytes
/// (PKCS#11 v2.40 §2.3.5). Strip the `04 LEN` prefix; the inner
/// payload is the uncompressed point (`0x04 || X || Y` for P-curves,
/// raw key for Ed25519).
fn strip_octet_string_wrapper(der: &[u8]) -> Result<Vec<u8>, Error> {
    if der.len() < 2 || der[0] != 0x04 {
        // Some tokens (older SoftHSM 1.x) returned the raw point bytes
        // directly without the OCTET STRING wrapper. Accept this shape
        // verbatim as a fallback so the import flow is forgiving.
        return Ok(der.to_vec());
    }
    let mut idx = 1usize;
    let first = der[idx];
    idx += 1;
    let len = if first & 0x80 == 0 {
        first as usize
    } else {
        let nbytes = (first & 0x7f) as usize;
        if nbytes == 0 || nbytes > 4 || idx + nbytes > der.len() {
            return Err(Error::Other("bad OCTET STRING length encoding".into()));
        }
        let mut acc = 0usize;
        for _ in 0..nbytes {
            acc = (acc << 8) | (der[idx] as usize);
            idx += 1;
        }
        acc
    };
    if idx + len > der.len() {
        return Err(Error::Other("OCTET STRING truncated".into()));
    }
    Ok(der[idx..idx + len].to_vec())
}

// SSH wire-format encoders — local copies of the shapes
// `lfs_core::ssh::wire` ships. We do not depend on `lfs_core` from
// `lfs_os_security` (the dep arrow runs the other way), so we
// inline the three encoders we need. The shape contract is identical
// to `wire.rs`; tests in this module pin the byte layout.

fn encode_ssh_rsa_public(modulus: &[u8], exponent: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(modulus.len() + exponent.len() + 24);
    push_string(&mut out, b"ssh-rsa");
    push_mpint(&mut out, exponent);
    push_mpint(&mut out, modulus);
    out
}

fn encode_ssh_ed25519(raw_32: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(52);
    push_string(&mut out, b"ssh-ed25519");
    push_string(&mut out, raw_32);
    out
}

fn encode_ssh_ecdsa(point: &[u8], curve: &[u8], algo: &[u8]) -> Result<Vec<u8>, Error> {
    if point.is_empty() || point[0] != 0x04 {
        return Err(Error::Other("ecdsa point not uncompressed".into()));
    }
    let mut out = Vec::with_capacity(96);
    push_string(&mut out, algo);
    push_string(&mut out, curve);
    push_string(&mut out, point);
    Ok(out)
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
    fn classify_p256_p384_p521() {
        let p256 = [0x06, 0x08, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x03, 0x01, 0x07];
        assert!(matches!(classify_ec_curve(&p256), Ok(KeyClass::EcdsaP256)));
        let p384 = [0x06, 0x05, 0x2B, 0x81, 0x04, 0x00, 0x22];
        assert!(matches!(classify_ec_curve(&p384), Ok(KeyClass::EcdsaP384)));
        let p521 = [0x06, 0x05, 0x2B, 0x81, 0x04, 0x00, 0x23];
        assert!(matches!(classify_ec_curve(&p521), Ok(KeyClass::EcdsaP521)));
    }

    #[test]
    fn classify_rejects_random_oid() {
        let bad = [0x06, 0x03, 0x01, 0x02, 0x03];
        let err = classify_ec_curve(&bad).unwrap_err();
        assert!(matches!(err, Error::UnsupportedKeyType(_)));
    }

    #[test]
    fn strip_octet_string_strips_short_form() {
        let v = vec![0x04, 0x03, 0xAA, 0xBB, 0xCC];
        assert_eq!(
            strip_octet_string_wrapper(&v).unwrap(),
            vec![0xAA, 0xBB, 0xCC]
        );
    }

    #[test]
    fn strip_octet_string_strips_long_form() {
        // OCTET STRING 81 81 <129 bytes>
        let mut v = vec![0x04, 0x81, 0x81];
        v.extend(vec![0x55u8; 129]);
        assert_eq!(strip_octet_string_wrapper(&v).unwrap(), vec![0x55u8; 129]);
    }

    #[test]
    fn strip_octet_string_passes_through_raw_payload() {
        // Older SoftHSM 1.x — no OCTET STRING wrapper. We accept
        // the payload verbatim.
        let raw = vec![0xAA, 0xBB, 0xCC];
        assert_eq!(strip_octet_string_wrapper(&raw).unwrap(), raw);
    }

    #[test]
    fn rsa_encoder_matches_ssh_keygen_layout() {
        // ssh-keygen format: "ssh-rsa" + mpint(e) + mpint(n)
        let modulus = [0x80, 0x12]; // high bit set => pad
        let exponent = [0x01, 0x00, 0x01];
        let out = encode_ssh_rsa_public(&modulus, &exponent);
        // string "ssh-rsa" (7 bytes)
        assert_eq!(&out[..4], &[0, 0, 0, 7]);
        assert_eq!(&out[4..11], b"ssh-rsa");
        // mpint(e) — 0x010001 has high bit clear, length 3, no pad
        assert_eq!(&out[11..15], &[0, 0, 0, 3]);
        assert_eq!(&out[15..18], &[0x01, 0x00, 0x01]);
        // mpint(n) — 0x8012 high bit on, length 3 with leading 0x00 pad
        assert_eq!(&out[18..22], &[0, 0, 0, 3]);
        assert_eq!(out[22], 0x00);
        assert_eq!(out[23], 0x80);
        assert_eq!(out[24], 0x12);
    }

    #[test]
    fn ed25519_encoder_matches_ssh_keygen_layout() {
        let raw = [0x55u8; 32];
        let out = encode_ssh_ed25519(&raw);
        assert_eq!(&out[..4], &[0, 0, 0, 11]);
        assert_eq!(&out[4..15], b"ssh-ed25519");
        assert_eq!(&out[15..19], &[0, 0, 0, 32]);
        assert_eq!(&out[19..], &raw[..]);
    }

    #[test]
    fn ecdsa_encoder_rejects_non_uncompressed_point() {
        let bad_point = vec![0x02u8; 65];
        let err = encode_ssh_ecdsa(&bad_point, b"nistp256", b"ecdsa-sha2-nistp256").unwrap_err();
        assert!(matches!(err, Error::Other(_)));
    }
}
