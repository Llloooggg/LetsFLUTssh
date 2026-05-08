//! Native TSS2 ESAPI seal/unseal — direct `libtss2-esys` calls via
//! the [`tss_esapi`] crate. Sibling to the `tpm2-tools` subprocess
//! backend in `tpm.rs`; selectable via `LFS_TPM_BACKEND=native`.
//! Stays opt-in until real-device verification flips the default.
//!
//! **Envelope format** — `[u32 BE pub_len][pub][u32 BE priv_len][priv]`,
//! holding `TPM2B_PUBLIC` + `TPM2B_PRIVATE` marshalled via
//! `Tss2_MU_TPM2B_*`. tss-esapi's `PublicBuffer::marshall` /
//! `PrivateBuffer::marshall` call the same `Tss2_MU_*` so envelopes
//! round-trip byte-identically with the subprocess backend.
//!
//! **Primary template** — [`build_primary_template`] mirrors
//! `tpm2 createprimary -C o`'s default storage-primary template
//! (RSA 2048, SHA-256 name hash, AES-128-CFB symmetric, restricted
//! decryption key) field-for-field so the derived primary key is
//! identical regardless of which backend created it.
//!
//! `unsafe_code = "forbid"` holds — tss-esapi's FFI into libtss2
//! is its own audit perimeter; this module has no `unsafe` blocks.

use tss_esapi::{
    attributes::ObjectAttributesBuilder,
    interface_types::{
        algorithm::{HashingAlgorithm, PublicAlgorithm, RsaSchemeAlgorithm, SymmetricMode},
        key_bits::{AesKeyBits, RsaKeyBits},
        resource_handles::Hierarchy,
    },
    structures::{
        Auth, Digest, KeyedHashScheme, Private, Public, PublicBuffer, PublicBuilder, PublicKeyRsa,
        PublicKeyedHashParameters, PublicRsaParametersBuilder, RsaExponent, RsaScheme,
        SensitiveData, SymmetricDefinitionObject,
    },
    tcti_ldr::{DeviceConfig, TctiNameConf},
    traits::{Marshall, UnMarshall},
    Context,
};

use std::path::Path;
use std::str::FromStr;

use super::tpm::{TpmConfig, TpmProbeResult, MAX_SEAL_BYTES};
use crate::linux::TpmError as Error;

/// TPM2B size prefix is two bytes, big-endian per TCG spec.
const TPM2B_SIZE_PREFIX: usize = 2;

/// Probe the TPM via a real `Esys_Startup` + `CreatePrimary`
/// round-trip — `Available` here gives the same strict guarantee
/// as the subprocess probe: downstream sealing will not fail
/// with a permissions / hierarchy / lockout error.
pub fn probe(cfg: &TpmConfig) -> TpmProbeResult {
    if !Path::new(&cfg.device).exists() {
        return TpmProbeResult::DeviceNodeMissing;
    }
    let mut ctx = match open_context(&cfg.device) {
        Ok(c) => c,
        // The subprocess path returns `BinaryMissing` here when
        // the `tpm2` CLI is absent. The native path's analogue
        // is "libtss2 failed to open the device" — surfaced as
        // ProbeFailed because there is no library-version
        // check the user can fix the way they would install
        // the missing CLI.
        Err(_) => return TpmProbeResult::ProbeFailed,
    };
    match ctx.execute_with_nullauth_session(|c| {
        c.create_primary(
            Hierarchy::Owner,
            build_primary_template().map_err(|_| {
                tss_esapi::Error::WrapperError(tss_esapi::WrapperErrorKind::InvalidParam)
            })?,
            None,
            None,
            None,
            None,
        )
    }) {
        Ok(_) => TpmProbeResult::Available,
        Err(_) => TpmProbeResult::ProbeFailed,
    }
}

/// Seal `secret` under a freshly-derived primary in the OWNER
/// hierarchy with `auth_value` as the unseal password. Returns
/// the same `[u32 BE pub_len][pub][u32 BE priv_len][priv]`
/// blob shape the subprocess path produces.
pub fn seal(cfg: &TpmConfig, secret: &[u8], auth_value: &[u8]) -> Result<Vec<u8>, Error> {
    if secret.len() > MAX_SEAL_BYTES {
        return Err(Error::Crypto(format!(
            "tpm seal rejected: secret {} bytes > {}",
            secret.len(),
            MAX_SEAL_BYTES
        )));
    }
    let mut ctx = open_context(&cfg.device).map_err(map_tss_err("open"))?;
    let primary_template = build_primary_template().map_err(map_tss_err("primary template"))?;
    let sealed_template = build_sealed_template().map_err(map_tss_err("sealed template"))?;
    let auth = Auth::try_from(auth_value.to_vec()).map_err(map_tss_err("auth"))?;
    let secret_data = SensitiveData::try_from(secret.to_vec()).map_err(map_tss_err("secret"))?;

    let (pub_bytes, priv_bytes) = ctx
        .execute_with_nullauth_session(|c| -> Result<(Vec<u8>, Vec<u8>), tss_esapi::Error> {
            let primary =
                c.create_primary(Hierarchy::Owner, primary_template, None, None, None, None)?;
            let sealed = c.create(
                primary.key_handle,
                sealed_template,
                Some(auth),
                Some(secret_data),
                None,
                None,
            )?;
            let pub_buffer = PublicBuffer::try_from(sealed.out_public)?;
            let pub_marshalled = pub_buffer.marshall()?;
            // tss-esapi 7.7 doesn't expose a `Marshall` impl for
            // `Private` (no `PrivateBuffer` analogue to
            // `PublicBuffer`). The TPM2B wire shape is the
            // simplest in the spec — `[u16 BE size][bytes]` —
            // so we hand-marshall to keep `unsafe_code = "forbid"`
            // intact rather than calling `Tss2_MU_TPM2B_PRIVATE_Marshal`
            // through unsafe FFI. Byte-identical to what
            // `tpm2 create -r` writes.
            let priv_marshalled = marshall_tpm2b(sealed.out_private.value());
            Ok((pub_marshalled, priv_marshalled))
        })
        .map_err(map_tss_err("seal"))?;

    Ok(pack(&pub_bytes, &priv_bytes))
}

/// Inverse of [`seal`]. Recreates the primary, loads the sealed
/// `(pub, priv)` pair, sets the auth value on the loaded handle,
/// and unseals. Returns the original secret bytes; format
/// mismatch / wrong auth / TPM-side failure all surface as `Err`.
pub fn unseal(cfg: &TpmConfig, blob: &[u8], auth_value: &[u8]) -> Result<Vec<u8>, Error> {
    let (pub_bytes, priv_bytes) =
        unpack(blob).ok_or_else(|| Error::Crypto("tpm unseal: malformed blob".to_string()))?;
    let mut ctx = open_context(&cfg.device).map_err(map_tss_err("open"))?;
    let primary_template = build_primary_template().map_err(map_tss_err("primary template"))?;
    let pub_buffer = PublicBuffer::unmarshall(pub_bytes).map_err(map_tss_err("unmarshall pub"))?;
    let public_struct = Public::try_from(pub_buffer).map_err(map_tss_err("decode pub"))?;
    // Inverse of the seal-side hand-marshall: read TPM2B size
    // header, take that many bytes, hand to `Private::try_from`.
    let priv_inner = unmarshall_tpm2b(priv_bytes)
        .ok_or_else(|| Error::Crypto("tpm-native: malformed TPM2B_PRIVATE".to_string()))?;
    let private_struct =
        Private::try_from(priv_inner.to_vec()).map_err(map_tss_err("decode priv"))?;
    let auth = Auth::try_from(auth_value.to_vec()).map_err(map_tss_err("auth"))?;

    let plaintext = ctx
        .execute_with_nullauth_session(|c| -> Result<Vec<u8>, tss_esapi::Error> {
            let primary =
                c.create_primary(Hierarchy::Owner, primary_template, None, None, None, None)?;
            let loaded = c.load(primary.key_handle, private_struct, public_struct)?;
            c.tr_set_auth(loaded.into(), auth)?;
            let unsealed = c.unseal(loaded.into())?;
            Ok(unsealed.to_vec())
        })
        .map_err(map_tss_err("unseal"))?;

    Ok(plaintext)
}

// ---- Internals ---------------------------------------------------------

fn open_context(device: &str) -> Result<Context, tss_esapi::Error> {
    // The TCG TCTI configuration grammar accepts both `device`
    // (default `/dev/tpmrm0`) and `device:/dev/tpmrm0` forms;
    // building the `TctiNameConf` directly from a `DeviceConfig`
    // sidesteps the string-parse path so a trailing slash or
    // case difference in the user's override does not silently
    // fall back to a different TCTI.
    let cfg = DeviceConfig::from_str(device).unwrap_or_default();
    let tcti = TctiNameConf::Device(cfg);
    Context::new(tcti)
}

/// `Public` template matching `tpm2 createprimary -C o`'s default —
/// the standard storage-primary template per TCG provisioning
/// guidance. Constructed field-for-field so the marshalled
/// `TPMT_PUBLIC` bytes (and therefore the TPM's primary-key
/// derivation) are byte-identical to what tpm2-tools produces.
fn build_primary_template() -> Result<Public, tss_esapi::Error> {
    let object_attributes = ObjectAttributesBuilder::new()
        .with_fixed_tpm(true)
        .with_fixed_parent(true)
        .with_sensitive_data_origin(true)
        .with_user_with_auth(true)
        .with_decrypt(true)
        .with_sign_encrypt(false)
        .with_restricted(true)
        .build()?;

    let symmetric = SymmetricDefinitionObject::Aes {
        key_bits: AesKeyBits::Aes128,
        mode: SymmetricMode::Cfb,
    };

    PublicBuilder::new()
        .with_public_algorithm(PublicAlgorithm::Rsa)
        .with_name_hashing_algorithm(HashingAlgorithm::Sha256)
        .with_object_attributes(object_attributes)
        .with_rsa_parameters(
            PublicRsaParametersBuilder::new()
                .with_symmetric(symmetric)
                .with_scheme(RsaScheme::create(RsaSchemeAlgorithm::Null, None)?)
                .with_key_bits(RsaKeyBits::Rsa2048)
                .with_exponent(RsaExponent::default())
                .with_is_signing_key(false)
                .with_is_decryption_key(true)
                .with_restricted(true)
                .build()?,
        )
        .with_rsa_unique_identifier(PublicKeyRsa::default())
        .build()
}

/// `Public` template for a sealed-data object — keyed-hash with
/// `KeyedHashScheme::Null` (sealed data has no scheme). Object
/// attributes mirror tpm2-tools `tpm2 create -i <data>` defaults:
/// `fixed_tpm | fixed_parent | user_with_auth`. `decrypt` and
/// `sign_encrypt` are off because the object holds raw bytes,
/// not a key. `sensitive_data_origin` is off because the
/// sensitive data comes from the caller, not from TPM-internal
/// derivation.
fn build_sealed_template() -> Result<Public, tss_esapi::Error> {
    let object_attributes = ObjectAttributesBuilder::new()
        .with_fixed_tpm(true)
        .with_fixed_parent(true)
        .with_user_with_auth(true)
        .with_decrypt(false)
        .with_sign_encrypt(false)
        .with_restricted(false)
        .with_sensitive_data_origin(false)
        .build()?;

    PublicBuilder::new()
        .with_public_algorithm(PublicAlgorithm::KeyedHash)
        .with_name_hashing_algorithm(HashingAlgorithm::Sha256)
        .with_object_attributes(object_attributes)
        .with_keyed_hash_parameters(PublicKeyedHashParameters::new(KeyedHashScheme::Null))
        .with_keyed_hash_unique_identifier(Digest::default())
        .build()
}

fn pack(pub_bytes: &[u8], priv_bytes: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(8 + pub_bytes.len() + priv_bytes.len());
    out.extend_from_slice(&(pub_bytes.len() as u32).to_be_bytes());
    out.extend_from_slice(pub_bytes);
    out.extend_from_slice(&(priv_bytes.len() as u32).to_be_bytes());
    out.extend_from_slice(priv_bytes);
    out
}

fn unpack(blob: &[u8]) -> Option<(&[u8], &[u8])> {
    if blob.len() < 8 {
        return None;
    }
    let pub_len = u32::from_be_bytes(blob[..4].try_into().unwrap()) as usize;
    if 4 + pub_len + 4 > blob.len() {
        return None;
    }
    let pub_bytes = &blob[4..4 + pub_len];
    let priv_len_off = 4 + pub_len;
    let priv_len =
        u32::from_be_bytes(blob[priv_len_off..priv_len_off + 4].try_into().unwrap()) as usize;
    let priv_off = priv_len_off + 4;
    if priv_off + priv_len > blob.len() {
        return None;
    }
    let priv_bytes = &blob[priv_off..priv_off + priv_len];
    Some((pub_bytes, priv_bytes))
}

fn map_tss_err(label: &'static str) -> impl Fn(tss_esapi::Error) -> Error {
    move |e| Error::Crypto(format!("tpm-native {label}: {e}"))
}

/// TCG TPM2B wire shape: `[u16 BE size][bytes]`. Used for
/// `TPM2B_PRIVATE` since tss-esapi 7.7 has no `PrivateBuffer`
/// (analogous to `PublicBuffer`) that would expose `Marshall`.
fn marshall_tpm2b(bytes: &[u8]) -> Vec<u8> {
    let size = bytes.len() as u16;
    let mut out = Vec::with_capacity(TPM2B_SIZE_PREFIX + bytes.len());
    out.extend_from_slice(&size.to_be_bytes());
    out.extend_from_slice(bytes);
    out
}

/// Inverse of [`marshall_tpm2b`]. Returns the inner-bytes slice
/// (excluding the size header) on a well-formed TPM2B; returns
/// `None` if the header overflows the buffer or the declared
/// size exceeds the remaining bytes.
fn unmarshall_tpm2b(buf: &[u8]) -> Option<&[u8]> {
    if buf.len() < TPM2B_SIZE_PREFIX {
        return None;
    }
    let size = u16::from_be_bytes(buf[..TPM2B_SIZE_PREFIX].try_into().unwrap()) as usize;
    let end = TPM2B_SIZE_PREFIX.checked_add(size)?;
    if end > buf.len() {
        return None;
    }
    Some(&buf[TPM2B_SIZE_PREFIX..end])
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn primary_template_builds() {
        // No TPM needed — purely tests that the template builder
        // accepts our parameter combination. Real-device
        // verification is the NI-2 gate.
        let _ = build_primary_template().expect("primary template");
    }

    #[test]
    fn sealed_template_builds() {
        let _ = build_sealed_template().expect("sealed template");
    }

    #[test]
    fn pack_unpack_round_trips() {
        let pub_bytes = vec![1, 2, 3, 4];
        let priv_bytes = vec![5, 6, 7, 8, 9];
        let packed = pack(&pub_bytes, &priv_bytes);
        let (got_pub, got_priv) = unpack(&packed).expect("unpack");
        assert_eq!(got_pub, pub_bytes.as_slice());
        assert_eq!(got_priv, priv_bytes.as_slice());
    }

    #[test]
    fn tpm2b_round_trips() {
        let inner = vec![0xde, 0xad, 0xbe, 0xef];
        let marshalled = marshall_tpm2b(&inner);
        // Size prefix is exactly 2 bytes BE.
        assert_eq!(marshalled[..2], [0x00, 0x04]);
        assert_eq!(&marshalled[2..], inner.as_slice());
        let recovered = unmarshall_tpm2b(&marshalled).expect("unmarshall");
        assert_eq!(recovered, inner.as_slice());
    }

    #[test]
    fn tpm2b_rejects_truncated_header() {
        assert!(unmarshall_tpm2b(&[]).is_none());
        assert!(unmarshall_tpm2b(&[0x00]).is_none());
    }

    #[test]
    fn tpm2b_rejects_size_beyond_buffer() {
        // Declares 100 bytes of payload but only 4 follow.
        let buf = vec![0x00, 0x64, 1, 2, 3, 4];
        assert!(unmarshall_tpm2b(&buf).is_none());
    }

    #[test]
    fn tpm2b_handles_empty_payload() {
        let marshalled = marshall_tpm2b(&[]);
        assert_eq!(marshalled, vec![0x00, 0x00]);
        let recovered = unmarshall_tpm2b(&marshalled).expect("unmarshall");
        assert!(recovered.is_empty());
    }
}
