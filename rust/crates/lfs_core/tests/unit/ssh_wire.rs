/// Unit tests extracted from ssh/wire.rs
/// Declared via `#[path] mod tests;` in the source file.
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
fn rsa_sig_body_is_raw() {
    // The body is the raw signature — the caller adds the single
    // outer `string(...)`. Pre-wrapping here would double the
    // length prefix.
    let sig = [0xAAu8; 256];
    assert_eq!(rsa_pkcs1_v15_sig_body(&sig), &sig[..]);
}

#[test]
fn ed25519_sig_body_is_raw() {
    let sig = [0xCCu8; 64];
    assert_eq!(ed25519_sig_body(&sig).unwrap(), &sig[..]);
}

#[test]
fn ed25519_rejects_wrong_size() {
    let err = ed25519_sig_body(&[0u8; 32]).unwrap_err();
    assert!(matches!(err, Error::Auth(_)));
}

/// The userauth signature FIELD is one outer SSH string wrapping
/// `string(alg) || string(body)`. Decode it exactly as russh's
/// SERVER does — read one string, then parse the inner as an
/// `ssh_key::Signature` — and confirm it reproduces algorithm +
/// body for both RSA and Ed25519. The missing outer string was the
/// bug: the server read a wrong length and rejected the credential.
#[test]
fn userauth_signature_field_round_trips_through_server_decode() {
    use russh::keys::ssh_key::encoding::Decode;
    use russh::keys::ssh_key::{Algorithm, HashAlg, Signature};

    // RSA
    let rsa_raw = vec![0x42u8; 256];
    let field = encode_userauth_signature_field("rsa-sha2-256", &rsa_pkcs1_v15_sig_body(&rsa_raw));
    let mut r = field.as_slice();
    let inner = Vec::<u8>::decode(&mut r).unwrap();
    assert!(r.is_empty(), "exactly one outer string");
    let sig = Signature::decode(&mut inner.as_slice()).unwrap();
    assert!(matches!(
        sig.algorithm(),
        Algorithm::Rsa {
            hash: Some(HashAlg::Sha256)
        }
    ));
    assert_eq!(sig.as_bytes(), &rsa_raw[..]);

    // Ed25519
    let ed_raw = vec![0x11u8; 64];
    let field = encode_userauth_signature_field("ssh-ed25519", &ed25519_sig_body(&ed_raw).unwrap());
    let mut r = field.as_slice();
    let inner = Vec::<u8>::decode(&mut r).unwrap();
    assert!(r.is_empty(), "exactly one outer string");
    let sig = Signature::decode(&mut inner.as_slice()).unwrap();
    assert!(matches!(sig.algorithm(), Algorithm::Ed25519));
    assert_eq!(sig.as_bytes(), &ed_raw[..]);
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
fn ecdsa_p384_public_blob_matches_ssh_keygen_shape() {
    let mut point = vec![0x04u8];
    point.extend(std::iter::repeat_n(0xAA, 48)); // X
    point.extend(std::iter::repeat_n(0xBB, 48)); // Y
    let out = encode_public_ecdsa_p384(&point).unwrap();
    // string "ecdsa-sha2-nistp384"
    assert_eq!(&out[..4], &[0, 0, 0, 19]);
    assert_eq!(&out[4..23], b"ecdsa-sha2-nistp384");
    // string "nistp384"
    assert_eq!(&out[23..27], &[0, 0, 0, 8]);
    assert_eq!(&out[27..35], b"nistp384");
    // string Q (97 bytes)
    assert_eq!(&out[35..39], &[0, 0, 0, 97]);
    assert_eq!(out[39], 0x04);
    assert_eq!(out.len(), 4 + 19 + 4 + 8 + 4 + 97);
}

#[test]
fn ecdsa_p384_public_blob_rejects_wrong_point_format() {
    let bad = vec![0x02u8; 97];
    let err = encode_public_ecdsa_p384(&bad).unwrap_err();
    assert!(matches!(err, Error::Auth(_)));
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
