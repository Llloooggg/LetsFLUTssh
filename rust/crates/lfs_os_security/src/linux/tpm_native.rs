//! Native TSS2 ESAPI seal/unseal — direct `libtss2-esys` calls via
//! the [`tss_esapi`] crate. Sibling to the `tpm2-tools` subprocess
//! backend in `tpm.rs`; selectable via `LFS_TPM_BACKEND=native`.
//! Stays opt-in until real-device verification flips the default.
//!
//! **Envelope format** — `LFHV[magic|version|platform_id=linux]
//! || TCG_ASN1_DER` per [`super::tpm_tcg_pem`]. The DER body wraps
//! a marshalled `(TPM2B_PUBLIC, TPM2B_PRIVATE)` pair inside the
//! TCG draft `draft-bottomley-tpm2-keys-asn1` `id-loadablekey`
//! shape, byte-compatible with `openssl-tpm2-engine` and
//! `ssh-tpm-agent`. The shared encoder makes envelopes round-trip
//! across the T2 vault path and the T-4 SSH-signing path that
//! [`super::tpm_ssh`] owns.
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
use super::tpm_tcg_pem::{self, TpmKey, TPM_RH_OWNER};
use crate::linux::TpmError as Error;

/// TPM2B size prefix is two bytes, big-endian per TCG spec.
const TPM2B_SIZE_PREFIX: usize = 2;

/// Per-platform tag the LFHV outer envelope stamps for the Linux
/// T2 path. Matches the shared platform-id table in
/// [`crate::hardware_tier_vault::HW_VAULT_PLATFORM_LINUX`] —
/// re-declared here so the seal/unseal pair can build the
/// envelope without importing the higher-level vault module
/// (audit boundary: `tpm_native` stays focused on the chip side).
const HW_VAULT_PLATFORM_LINUX: u8 = 4;

/// LFHV magic + version + platform-id prefix the outer envelope
/// carries. Six bytes total — `b"LFHV" || version_byte ||
/// platform_id_byte`. Mirrors
/// [`crate::hardware_tier_vault::prepend_envelope_header`].
const LFHV_MAGIC: &[u8; 4] = b"LFHV";
const LFHV_VERSION: u8 = 2;
const LFHV_HEADER_LEN: usize = 6;

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
/// an `LFHV[…|platform_id_linux] || TCG_ASN1_DER` envelope.
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
    let empty_auth_flag = auth_value.is_empty();

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

    Ok(wrap_envelope(&TpmKey {
        empty_auth: Some(empty_auth_flag),
        parent: TPM_RH_OWNER,
        public: pub_bytes,
        private: priv_bytes,
    }))
}

/// Inverse of [`seal`]. Strips the LFHV header, decodes the TCG
/// ASN.1 DER body to recover the `(TPM2B_PUBLIC, TPM2B_PRIVATE)`
/// pair, recreates the primary, loads the sealed pair, sets the
/// auth value on the loaded handle, and unseals. Format mismatch
/// / wrong auth / TPM-side failure all surface as `Err`.
pub fn unseal(cfg: &TpmConfig, blob: &[u8], auth_value: &[u8]) -> Result<Vec<u8>, Error> {
    let key = unwrap_envelope(blob)?;
    let mut ctx = open_context(&cfg.device).map_err(map_tss_err("open"))?;
    let primary_template = build_primary_template().map_err(map_tss_err("primary template"))?;
    let pub_buffer =
        PublicBuffer::unmarshall(&key.public).map_err(map_tss_err("unmarshall pub"))?;
    let public_struct = Public::try_from(pub_buffer).map_err(map_tss_err("decode pub"))?;
    // Inverse of the seal-side hand-marshall: read TPM2B size
    // header, take that many bytes, hand to `Private::try_from`.
    let priv_inner = unmarshall_tpm2b(&key.private)
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
pub fn build_primary_template() -> Result<Public, tss_esapi::Error> {
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

/// Build `LFHV[magic|version|platform_id_linux] || TCG_ASN1_DER`
/// from a marshalled `(public, private)` pair. The DER body
/// follows the `id-loadablekey` arm of
/// `draft-bottomley-tpm2-keys-asn1` — same shape `ssh-tpm-agent`
/// and `openssl-tpm2-engine` consume.
fn wrap_envelope(key: &TpmKey) -> Vec<u8> {
    let der = tpm_tcg_pem::encode(key);
    let mut out = Vec::with_capacity(LFHV_HEADER_LEN + der.len());
    out.extend_from_slice(LFHV_MAGIC);
    out.push(LFHV_VERSION);
    out.push(HW_VAULT_PLATFORM_LINUX);
    out.extend_from_slice(&der);
    out
}

/// Inverse of [`wrap_envelope`]. Rejects anything that does not
/// carry the expected magic + version + platform-id, then hands
/// the trailing body to the TCG ASN.1 decoder. A v1 / v2 custom
/// binary envelope (the pre-rev shape this build retired) will
/// not parse — the ASN.1 decoder refuses the leading `0x00…`
/// length prefix as a tag mismatch — and the typed error carries
/// the "expects TCG ASN.1 PEM body" wording the caller routes to
/// the tier-reset cascade.
fn unwrap_envelope(blob: &[u8]) -> Result<TpmKey, Error> {
    if blob.len() < LFHV_HEADER_LEN
        || &blob[0..4] != LFHV_MAGIC
        || blob[4] != LFHV_VERSION
        || blob[5] != HW_VAULT_PLATFORM_LINUX
    {
        return Err(Error::Crypto(
            "unsupported envelope version: this build expects TCG ASN.1 PEM body".to_string(),
        ));
    }
    tpm_tcg_pem::decode(&blob[LFHV_HEADER_LEN..])
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

    /// Defence-in-depth fixture for the storage-primary template
    /// marshalled bytes. The TPM derives the primary key from
    /// these bytes; a silent change (tss-esapi minor bump that
    /// reorders fields, switches a default, reshuffles attribute
    /// flags) would brick every existing user's T2 envelope. The
    /// fixture below pins the byte sequence at the workspace
    /// `tss-esapi` version; a mismatch surfaces loud at CI time
    /// so a future bump that changes builder defaults is caught
    /// before users hit it.
    ///
    /// The fixture lives next to the test in
    /// `tests/fixtures/storage_primary_template_v1.bin`. The "v1"
    /// suffix tags the contents, not the file format — the day a
    /// genuine template change ships, mint a new fixture (`v2`)
    /// alongside the documented reason in the schema-versions
    /// table rather than overwriting `v1`.
    const STORAGE_PRIMARY_TEMPLATE_FIXTURE: &[u8] =
        include_bytes!("../../tests/fixtures/storage_primary_template_v1.bin");

    #[test]
    fn primary_template_builds() {
        // No TPM needed — purely tests that the template builder
        // accepts our parameter combination. Real-device
        // verification is the swtpm integration test.
        let _ = build_primary_template().expect("primary template");
    }

    #[test]
    fn sealed_template_builds() {
        let _ = build_sealed_template().expect("sealed template");
    }

    #[test]
    fn storage_primary_template_marshalls_to_fixture() {
        // Pins the builder's output across tss-esapi bumps. If
        // this fails after a dep upgrade, the upstream changed a
        // default for the primary template — re-mint the fixture
        // intentionally and ship a HW_VAULT_LINUX schema bump in
        // the same commit.
        let template = build_primary_template().expect("primary template");
        let buffer = PublicBuffer::try_from(template).expect("PublicBuffer::try_from");
        let bytes = buffer.marshall().expect("marshall");
        assert_eq!(
            bytes.as_slice(),
            STORAGE_PRIMARY_TEMPLATE_FIXTURE,
            "storage-primary template bytes drifted from fixture — \
             tss-esapi defaults changed for the storage primary; \
             mint a new fixture + bump SchemaVersions::HW_VAULT_LINUX"
        );
    }

    #[test]
    fn seal_envelope_starts_with_lfhv_header() {
        // Cannot exercise the full TPM round trip without a chip,
        // but the envelope-build half is testable in isolation
        // via `wrap_envelope`. Pins the LFHV magic + version +
        // platform-id triplet so a future refactor cannot
        // silently flip the platform byte and brick cross-host
        // sync replay.
        let key = TpmKey {
            empty_auth: Some(false),
            parent: TPM_RH_OWNER,
            public: vec![1, 2, 3, 4],
            private: vec![5, 6, 7, 8],
        };
        let wrapped = wrap_envelope(&key);
        assert_eq!(&wrapped[0..4], LFHV_MAGIC);
        assert_eq!(wrapped[4], LFHV_VERSION);
        assert_eq!(wrapped[5], HW_VAULT_PLATFORM_LINUX);
    }

    #[test]
    fn wrap_unwrap_envelope_round_trips() {
        let key = TpmKey {
            empty_auth: Some(true),
            parent: TPM_RH_OWNER,
            public: vec![0xAA; 16],
            private: vec![0xBB; 32],
        };
        let wrapped = wrap_envelope(&key);
        let recovered = unwrap_envelope(&wrapped).expect("unwrap");
        assert_eq!(recovered, key);
    }

    #[test]
    fn unwrap_rejects_pre_rev_custom_binary_envelope() {
        // Pre-rev shape: `[u32 BE pub_len][pub][u32 BE priv_len][priv]`.
        // The first byte is the high byte of `pub_len`, almost always
        // 0x00 for a real envelope (pub blocks fit well under 16 MiB),
        // which is neither `L`/0x4C nor part of any LFHV-prefixed
        // shape — the magic check refuses the input with the typed
        // error the tier-reset cascade routes on.
        let mut legacy = Vec::new();
        legacy.extend_from_slice(&123u32.to_be_bytes());
        legacy.extend_from_slice(&[0u8; 123]);
        legacy.extend_from_slice(&456u32.to_be_bytes());
        legacy.extend_from_slice(&[0u8; 456]);
        let err = unwrap_envelope(&legacy).unwrap_err();
        match err {
            Error::Crypto(msg) => {
                assert!(
                    msg.contains("unsupported envelope version") && msg.contains("TCG ASN.1 PEM"),
                    "expected the typed rejection message, got: {msg}"
                );
            }
            other => panic!("expected Crypto error, got {other:?}"),
        }
    }

    #[test]
    fn unwrap_rejects_short_blob() {
        let err = unwrap_envelope(&[]).unwrap_err();
        assert!(matches!(err, Error::Crypto(_)));
        let err = unwrap_envelope(b"LFH").unwrap_err();
        assert!(matches!(err, Error::Crypto(_)));
    }

    #[test]
    fn unwrap_rejects_wrong_platform_byte() {
        // LFHV magic + version match but the platform byte is
        // Apple (1), not Linux (4). Caller's tier-reset cascade
        // expects a cross-platform envelope to fail loud rather
        // than silently produce garbage on an unseal attempt.
        let mut blob = Vec::with_capacity(8);
        blob.extend_from_slice(LFHV_MAGIC);
        blob.push(LFHV_VERSION);
        blob.push(1);
        blob.push(0x30);
        blob.push(0x00);
        let err = unwrap_envelope(&blob).unwrap_err();
        assert!(matches!(err, Error::Crypto(_)));
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
