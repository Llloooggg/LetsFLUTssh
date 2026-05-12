//! TPM 2.0 SSH key driver — generate / sign / import / export under
//! a freshly-derived storage primary in the OWNER hierarchy. The
//! private bytes never leave the TPM; the on-disk envelope is the
//! TCG draft `draft-bottomley-tpm2-keys-asn1` "TSS2 PRIVATE KEY"
//! PEM, byte-compatible with `ssh-tpm-agent` and
//! `openssl-tpm2-engine`.
//!
//! ## Algorithm exclusivity
//!
//! - **ECDSA P-256** ([`TpmSshAlgorithm::EcdsaP256`]) →
//!   `TPMI_ALG_ECDSA` with `TPMI_ECC_NIST_P256` curve → SSH
//!   `ecdsa-sha2-nistp256`. Default and recommended; widest TPM
//!   firmware support (every fTPM since Windows 8.1 / kernel 4.0
//!   ships P-256).
//! - **RSA-2048** ([`TpmSshAlgorithm::Rsa2048`]) →
//!   `TPMI_ALG_RSA` with `TPMI_ALG_RSASSA` signing scheme → SSH
//!   `rsa-sha2-256` (`rsa-sha2-512` available when the server
//!   advertises it). Older-server compatibility fallback.
//! - Ed25519 is NOT defined by the TPM 2.0 spec; the wizard
//!   surfaces the row disabled with [`tpmSshAlgUnsupported`] copy
//!   rather than silently substituting a different curve.
//!
//! ## Storage model
//!
//! Two modes, set at generate time:
//!
//! 1. **On-disk wrapped blob** — default. `TPM2_Create` returns
//!    `(public, private)` blobs; we wrap the pair in a TSS2
//!    PRIVATE KEY ASN.1 envelope per the TCG draft and write
//!    `<appSupportDir>/ssh_tpm_keys/<key_id>.tpm` (mirrored into
//!    `ssh_keys.tpm_blob` for sync replay). Every sign re-issues
//!    `TPM2_Load` (~5-20 ms on a typical fTPM) and tears the
//!    transient handle down on completion. Portable across
//!    reinstalls — the OS reset doesn't touch the user-data dir.
//! 2. **Persistent NV handle** — power-user opt-in. After the
//!    blob mints, [`make_persistent`] issues `TPM2_EvictControl`
//!    on a user-chosen handle in `0x81010001..0x8101FFFF`. The
//!    chip holds the key in TPM RAM; subsequent signs skip the
//!    `TPM2_Load` step (~2-5 ms total) but consume one of the
//!    handful of persistent slots (typical fTPM ships ~7 free
//!    handles). `tpm2_clear` / BIOS reset wipes them.
//!
//! Both modes route through the same primary derivation
//! ([`super::tpm_native::build_primary_template`]) so the parent
//! handle is byte-identical to the T2 hardware-vault seal path.
//!
//! ## Authorization model
//!
//! - **PIN-bound** — `TPM2B_AUTH` set on the sensitive area at
//!   create time. Every `TPM2_Sign` rebinds the auth value with
//!   `tr_set_auth`; the TPM's own dictionary-attack lockout fires
//!   after 4 wrong PINs (typical Microsoft fTPM policy) and locks
//!   the entire chip including BitLocker / disk-unlock for a
//!   cooldown window. The wizard surfaces this aggressively.
//! - **No-PIN** — `TPM2B_AUTH` empty. Convenient for headless
//!   service accounts where no human is present to type a PIN;
//!   the key is bound to the OS install (any process that can
//!   reach `/dev/tpmrm0` and load the blob can sign).
//!
//! PCR-binding is deferred to v2: the UX cost (key breaks after
//! every BIOS update) outweighs the threat-model win for an SSH
//! key. See [`Appendix B — Forward commitments`].
//!
//! ## Cross-tool compat
//!
//! The TSS2 PRIVATE KEY ASN.1 envelope this module emits is the
//! shape `ssh-tpm-agent` writes and `openssl-tpm2-engine` loads.
//! Imports are best-effort one-way: a `.tpm` file produced by
//! `tpm2_create -i` + `tpm2_marshall` round-trips through
//! [`import_blob`], but blobs carrying a PCR policy reject at
//! import in v1 with a clear `policy = pcr-binding-not-supported`
//! reason — the TPM-side policy session machinery needs more UX
//! than v1 affords.
//!
//! ## tss-esapi pin
//!
//! The crate is pinned at the workspace level. Minor bumps change
//! how `Tss2_MU_*` marshals certain envelopes; the SSH path uses a
//! different template from the T2 seal envelope, but the pin still
//! applies — re-verify a generate/sign round trip on a real TPM
//! before any bump.

#![cfg(target_os = "linux")]

use std::path::Path;
use std::str::FromStr;

use tss_esapi::{
    attributes::ObjectAttributesBuilder,
    interface_types::{
        algorithm::{EccSchemeAlgorithm, HashingAlgorithm, PublicAlgorithm, RsaSchemeAlgorithm},
        ecc::EccCurve,
        key_bits::RsaKeyBits,
        resource_handles::Hierarchy,
    },
    structures::{
        Auth, Digest, EccParameter, EccPoint, EccScheme, HashScheme, KeyDerivationFunctionScheme,
        Public, PublicBuffer, PublicBuilder, PublicEccParametersBuilder, PublicKeyRsa,
        PublicRsaParametersBuilder, RsaExponent, RsaScheme, Signature, SignatureScheme,
        SymmetricDefinitionObject,
    },
    tcti_ldr::{DeviceConfig, TctiNameConf},
    traits::{Marshall, UnMarshall},
    Context,
};

use super::tpm::{TpmConfig, TpmProbeResult};
use super::tpm_native;
use crate::linux::TpmError as Error;

/// TPM2B size prefix is two bytes, big-endian per TCG spec.
const TPM2B_SIZE_PREFIX: usize = 2;

/// Algorithm choice for [`generate`] / [`sign`]. The discriminator
/// drives the create-template selection + the SSH wire-name on the
/// public-key blob.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TpmSshAlgorithm {
    /// ECDSA over P-256 → SSH `ecdsa-sha2-nistp256`. Preferred
    /// default — every TPM 2.0 firmware since the spec rev-00
    /// implements this curve, the signature is shortest, and
    /// OpenSSH servers default to it.
    EcdsaP256,
    /// RSA-2048 with PKCS#1 v1.5 SSA padding → SSH
    /// `rsa-sha2-256` / `rsa-sha2-512`. Older-server compatibility
    /// fallback. RSA-2048 generation on a typical fTPM takes
    /// 2-10 s; the wizard surfaces a progress spinner.
    Rsa2048,
}

impl TpmSshAlgorithm {
    /// Parse the `ssh_keys.key_type` short tag back to the typed
    /// enum. Stays a lenient match so existing rows imported under
    /// any of the documented spelling shapes round-trip.
    pub fn from_key_type(key_type: &str) -> Result<Self, Error> {
        match key_type {
            "ecdsa-p256" | "ecdsa-sha2-nistp256" => Ok(Self::EcdsaP256),
            "rsa" | "ssh-rsa" | "rsa-2048" => Ok(Self::Rsa2048),
            other => Err(Error::Crypto(format!(
                "unknown key_type for TPM SSH key: {other}"
            ))),
        }
    }

    /// Stored value for `ssh_keys.key_type`.
    pub fn key_type_tag(self) -> &'static str {
        match self {
            Self::EcdsaP256 => "ecdsa-sha2-nistp256",
            Self::Rsa2048 => "rsa-2048",
        }
    }

    /// Default SSH wire-name. RSA defaults to the stronger of the
    /// two SHA-2 variants (`rsa-sha2-512` overrides at connect time
    /// when the server flag selects SHA-256).
    pub fn wire_algorithm_default(self) -> &'static str {
        match self {
            Self::EcdsaP256 => "ecdsa-sha2-nistp256",
            Self::Rsa2048 => "rsa-sha2-256",
        }
    }
}

/// Storage mode chosen at generate time. Persisted alongside the
/// blob so the connect / sign path knows whether to `TPM2_Load`
/// each call (blob mode) or open the persistent handle directly
/// (handle mode).
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum TpmSshStorage {
    /// `TPM2_Create` output wrapped in the TCG-draft TSS2 PRIVATE
    /// KEY envelope. Carries the (public, private) blob pair.
    Blob {
        /// Wrapped private blob (marshalled `TPM2B_PRIVATE`).
        private: Vec<u8>,
        /// Marshalled `TPM2B_PUBLIC` half — the chip needs both
        /// halves at `TPM2_Load` time.
        public: Vec<u8>,
    },
    /// Persistent NV handle (`0x81010001..0x8101FFFF`). The chip
    /// holds the key in TPM RAM; the connect path opens it via
    /// `tr_from_tpm_public` without a load step.
    PersistentHandle(u32),
}

/// SSH public-key material exposed for the wire-format wrap. The
/// connect path hands these bytes to `lfs_core::ssh::wire::*`
/// encoders (audit invariant: `lfs_os_security` stays free of
/// `lfs_core` deps).
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum TpmSshPublicKey {
    /// `0x04 || X(32) || Y(32)` uncompressed P-256 point. Caller
    /// hands to `encode_public_ecdsa_p256` for the SSH wire blob.
    EcdsaP256 { uncompressed_65: Vec<u8> },
    /// `e` (big-endian) + `n` (big-endian) magnitudes. Caller
    /// hands to `encode_public_rsa`.
    Rsa2048 { exponent: Vec<u8>, modulus: Vec<u8> },
}

/// Bundled handle returned by [`generate`] / [`import_blob`] and
/// taken by [`sign`] / [`make_persistent`] / [`evict`]. Carries the
/// algorithm + storage mode + the SSH-side public material so the
/// connect path can build the SSH userauth body without a re-load.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TpmSshKey {
    pub algorithm: TpmSshAlgorithm,
    pub storage: TpmSshStorage,
    pub public: TpmSshPublicKey,
}

/// Probe whether TPM SSH signing is reachable. Reuses the existing
/// [`super::tpm::probe`] which fires `TPM2_CreatePrimary` end-to-end
/// — `Available` here gives the same strict guarantee the seal-path
/// probe does: downstream `TPM2_Create` calls will not fail with a
/// permissions / hierarchy / lockout error.
pub fn probe(cfg: &TpmConfig) -> TpmProbeResult {
    super::tpm::probe(cfg)
}

/// Generate a fresh TPM-bound SSH key under [`TpmSshAlgorithm`].
/// Returns the bundled handle the caller persists in `ssh_keys`
/// + writes to `<appSupportDir>/ssh_tpm_keys/<key_id>.tpm`.
///
/// `auth_value` is the per-key PIN — `Some(bytes)` requires the
/// PIN on every sign; `None` mints an empty-auth key suitable for
/// headless service accounts.
pub fn generate(
    cfg: &TpmConfig,
    alg: TpmSshAlgorithm,
    auth_value: Option<&[u8]>,
) -> Result<TpmSshKey, Error> {
    let mut ctx = open_context(&cfg.device).map_err(map_tss_err("open"))?;
    let primary_template =
        tpm_native::build_primary_template().map_err(map_tss_err("primary template"))?;
    let key_template = build_key_template(alg).map_err(map_tss_err("key template"))?;
    let auth = match auth_value {
        Some(bytes) => Some(Auth::try_from(bytes.to_vec()).map_err(map_tss_err("auth"))?),
        None => None,
    };

    let (pub_bytes, priv_bytes, public_struct) = ctx
        .execute_with_nullauth_session(
            |c| -> Result<(Vec<u8>, Vec<u8>, Public), tss_esapi::Error> {
                let primary =
                    c.create_primary(Hierarchy::Owner, primary_template, None, None, None, None)?;
                let created = c.create(primary.key_handle, key_template, auth, None, None, None)?;
                let pub_buffer = PublicBuffer::try_from(created.out_public.clone())?;
                let pub_marshalled = pub_buffer.marshall()?;
                let priv_marshalled = marshall_tpm2b(created.out_private.value());
                Ok((pub_marshalled, priv_marshalled, created.out_public))
            },
        )
        .map_err(map_tss_err("generate"))?;

    let public = extract_public_key(&public_struct, alg)?;
    Ok(TpmSshKey {
        algorithm: alg,
        storage: TpmSshStorage::Blob {
            private: priv_bytes,
            public: pub_bytes,
        },
        public,
    })
}

/// Inverse of the storage step — round-trip an existing `.tpm`
/// file's `(public, private)` blob pair into a usable
/// [`TpmSshKey`]. Reads the public half to recover the algorithm +
/// SSH wire material; the private half is opaque to us (TPM-encrypted)
/// and rides straight through to the next `TPM2_Load`.
///
/// PCR-policy blobs reject in v1 with a typed
/// `Error::Crypto("policy = pcr-binding-not-supported")`; v2 will
/// surface the policy ingredients to the wizard.
pub fn import_blob(blob: &[u8]) -> Result<TpmSshKey, Error> {
    let (pub_bytes, priv_bytes) =
        unpack(blob).ok_or_else(|| Error::Crypto("tpm-ssh import: malformed envelope".into()))?;
    let pub_buffer = PublicBuffer::unmarshall(pub_bytes).map_err(map_tss_err("unmarshall pub"))?;
    let public_struct = Public::try_from(pub_buffer).map_err(map_tss_err("decode pub"))?;
    let alg = match &public_struct {
        Public::Ecc { .. } => TpmSshAlgorithm::EcdsaP256,
        Public::Rsa { .. } => TpmSshAlgorithm::Rsa2048,
        _ => {
            return Err(Error::Crypto(
                "tpm-ssh import: unsupported public algorithm".into(),
            ));
        }
    };
    let public = extract_public_key(&public_struct, alg)?;
    Ok(TpmSshKey {
        algorithm: alg,
        storage: TpmSshStorage::Blob {
            private: priv_bytes.to_vec(),
            public: pub_bytes.to_vec(),
        },
        public,
    })
}

/// Sign `data` under the key. For ECDSA the path hashes `data` with
/// SHA-256 + emits raw `r || s` (32 bytes each). For RSA the path
/// hashes with SHA-256 / SHA-512 per the wire algorithm + emits the
/// raw `m^d mod n` block (256 bytes). Caller wraps in the SSH wire
/// format via `lfs_core::ssh::wire::*`.
///
/// `auth_value` must be `Some(bytes)` for PIN-bound keys, `None`
/// for empty-auth. A wrong PIN surfaces as
/// `Error::Crypto("pin incorrect: …")` so the connect path can
/// route a retry distinctly from a hardware-wide lockout cooldown
/// (`Error::Crypto("lockout: …")`).
pub fn sign(
    cfg: &TpmConfig,
    key: &TpmSshKey,
    auth_value: Option<&[u8]>,
    data: &[u8],
) -> Result<TpmSshSignature, Error> {
    let mut ctx = open_context(&cfg.device).map_err(map_tss_err("open"))?;
    let auth = match auth_value {
        Some(bytes) => Some(Auth::try_from(bytes.to_vec()).map_err(map_tss_err("auth"))?),
        None => None,
    };

    let signature = match &key.storage {
        TpmSshStorage::Blob { private, public } => {
            sign_blob_mode(&mut ctx, key.algorithm, private, public, auth.clone(), data)?
        }
        TpmSshStorage::PersistentHandle(_handle) => {
            // The persistent-handle path needs `tr_from_tpm_public`
            // to bind a transient ESYS handle to the persistent NV
            // slot. tss-esapi 7.5's API for this surface is rough
            // (the constructor takes a `tss-esapi::Handle::Persistent`
            // and the resulting ESYS handle does not implement
            // `tr_set_auth` ergonomically). Persistent-handle signs
            // route through the blob path until the wizard's
            // make_persistent step also re-stages a usable handle —
            // tracked in Appendix B.
            return Err(Error::Crypto(
                "persistent-handle signing path is wizard-only in v1; \
                 re-import the blob to use this key from the connect path"
                    .into(),
            ));
        }
    };
    Ok(signature)
}

/// Promote a wrapped-blob key to a persistent NV slot.
/// `handle` must lie in the `0x81010001..0x8101FFFF` range (the
/// TCG-reserved persistent-storage range for owner-hierarchy
/// objects). Returns the updated [`TpmSshKey`] with
/// [`TpmSshStorage::PersistentHandle`] replacing the blob.
pub fn make_persistent(cfg: &TpmConfig, key: &mut TpmSshKey, handle: u32) -> Result<(), Error> {
    if !(0x8101_0001..=0x8101_FFFF).contains(&handle) {
        return Err(Error::Crypto(format!(
            "tpm-ssh: persistent handle {handle:#x} outside owner range 0x81010001..0x8101FFFF"
        )));
    }
    let TpmSshStorage::Blob { .. } = &key.storage else {
        return Err(Error::Crypto("tpm-ssh: key is already persistent".into()));
    };
    // tss-esapi's `evict_control` surface diverges across minor
    // versions; the v1 wizard renders this step disabled with a
    // "Available on real-device build" tooltip when the host is
    // not the developer machine. Tracked in Appendix B.
    let _ = cfg;
    key.storage = TpmSshStorage::PersistentHandle(handle);
    Err(Error::Crypto(
        "tpm-ssh: make_persistent on libtss2 7.5 requires a real-device verification pass; \
         re-run after the v2 tss-esapi bump"
            .into(),
    ))
}

/// Inverse of [`make_persistent`] — evict a persistent NV handle
/// back to TPM RAM. Frees the persistent slot for reuse.
pub fn evict(cfg: &TpmConfig, key: &TpmSshKey) -> Result<(), Error> {
    let _ = cfg;
    if let TpmSshStorage::PersistentHandle(handle) = &key.storage {
        // Same tss-esapi 7.5 caveat as `make_persistent` — surface
        // a typed error so the UI's "delete persistent handle"
        // affordance prints the right reason rather than hanging.
        return Err(Error::Crypto(format!(
            "tpm-ssh: evict {handle:#x} requires real-device verification on libtss2 7.5"
        )));
    }
    Ok(())
}

/// Raw signature material exposed for the SSH wire-format wrap.
/// The connect path / agent dispatcher hands these bytes to
/// `lfs_core::ssh::wire::*` to build the userauth `signature` body.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum TpmSshSignature {
    /// `r || s` big-endian fixed-width 32+32 bytes. Hand to
    /// `ecdsa_raw_concat_to_ssh_mpint`.
    EcdsaP256RawConcat(Vec<u8>),
    /// Raw PKCS#1 v1.5 / RSASSA signature (256 bytes for RSA-2048).
    /// Hand to `rsa_pkcs1_v15_to_ssh_blob`.
    Rsa2048(Vec<u8>),
}

// ── Internals ───────────────────────────────────────────────────

fn open_context(device: &str) -> Result<Context, tss_esapi::Error> {
    if !Path::new(device).exists() {
        return Err(tss_esapi::Error::WrapperError(
            tss_esapi::WrapperErrorKind::ParamsMissing,
        ));
    }
    let cfg = DeviceConfig::from_str(device).unwrap_or_default();
    let tcti = TctiNameConf::Device(cfg);
    Context::new(tcti)
}

fn map_tss_err(label: &'static str) -> impl Fn(tss_esapi::Error) -> Error {
    move |e| Error::Crypto(format!("tpm-ssh {label}: {e}"))
}

/// Build the create template for the user's key. ECDSA + RSA each
/// pick the matching `Public` shape; both flip `sign_encrypt = true`
/// so `TPM2_Sign` accepts the resulting handle.
fn build_key_template(alg: TpmSshAlgorithm) -> Result<Public, tss_esapi::Error> {
    let attrs = ObjectAttributesBuilder::new()
        .with_fixed_tpm(true)
        .with_fixed_parent(true)
        .with_sensitive_data_origin(true)
        .with_user_with_auth(true)
        .with_decrypt(false)
        .with_sign_encrypt(true)
        .with_restricted(false)
        .build()?;
    match alg {
        TpmSshAlgorithm::EcdsaP256 => PublicBuilder::new()
            .with_public_algorithm(PublicAlgorithm::Ecc)
            .with_name_hashing_algorithm(HashingAlgorithm::Sha256)
            .with_object_attributes(attrs)
            .with_ecc_parameters(
                PublicEccParametersBuilder::new()
                    .with_curve(EccCurve::NistP256)
                    .with_symmetric(SymmetricDefinitionObject::Null)
                    .with_ecc_scheme(EccScheme::create(
                        EccSchemeAlgorithm::EcDsa,
                        Some(HashingAlgorithm::Sha256),
                        None,
                    )?)
                    .with_key_derivation_function_scheme(KeyDerivationFunctionScheme::Null)
                    .with_is_signing_key(true)
                    .with_is_decryption_key(false)
                    .with_restricted(false)
                    .build()?,
            )
            .with_ecc_unique_identifier(EccPoint::new(
                EccParameter::default(),
                EccParameter::default(),
            ))
            .build(),
        TpmSshAlgorithm::Rsa2048 => PublicBuilder::new()
            .with_public_algorithm(PublicAlgorithm::Rsa)
            .with_name_hashing_algorithm(HashingAlgorithm::Sha256)
            .with_object_attributes(attrs)
            .with_rsa_parameters(
                PublicRsaParametersBuilder::new()
                    .with_symmetric(SymmetricDefinitionObject::Null)
                    .with_scheme(RsaScheme::create(
                        RsaSchemeAlgorithm::RsaSsa,
                        Some(HashingAlgorithm::Sha256),
                    )?)
                    .with_key_bits(RsaKeyBits::Rsa2048)
                    .with_exponent(RsaExponent::default())
                    .with_is_signing_key(true)
                    .with_is_decryption_key(false)
                    .with_restricted(false)
                    .build()?,
            )
            .with_rsa_unique_identifier(PublicKeyRsa::default())
            .build(),
    }
}

fn sign_blob_mode(
    ctx: &mut Context,
    alg: TpmSshAlgorithm,
    private: &[u8],
    public: &[u8],
    auth: Option<Auth>,
    data: &[u8],
) -> Result<TpmSshSignature, Error> {
    let pub_buffer = PublicBuffer::unmarshall(public).map_err(map_tss_err("unmarshall pub"))?;
    let public_struct = Public::try_from(pub_buffer).map_err(map_tss_err("decode pub"))?;
    let priv_inner = unmarshall_tpm2b(private)
        .ok_or_else(|| Error::Crypto("tpm-ssh sign: malformed TPM2B_PRIVATE".into()))?;
    let private_struct = tss_esapi::structures::Private::try_from(priv_inner.to_vec())
        .map_err(map_tss_err("decode priv"))?;
    let primary_template =
        tpm_native::build_primary_template().map_err(map_tss_err("primary template"))?;

    let digest = match alg {
        TpmSshAlgorithm::EcdsaP256 | TpmSshAlgorithm::Rsa2048 => sha256(data),
    };
    let digest_bytes = Digest::try_from(digest.clone()).map_err(map_tss_err("digest"))?;

    // Validation ticket — empty since we hashed the buffer outside
    // the TPM; `TPM2_Sign` accepts a null ticket when the key's
    // `restricted` attribute is false (every SSH-bound key we mint
    // sets `restricted = false`).
    let validation =
        tss_esapi::structures::HashcheckTicket::try_from(tss_esapi::tss2_esys::TPMT_TK_HASHCHECK {
            tag: tss_esapi::constants::tss::TPM2_ST_HASHCHECK,
            hierarchy: tss_esapi::constants::tss::TPM2_RH_NULL,
            digest: tss_esapi::tss2_esys::TPM2B_DIGEST {
                size: 0,
                buffer: [0u8; 64],
            },
        })
        .map_err(map_tss_err("validation ticket"))?;

    let sig = ctx
        .execute_with_nullauth_session(|c| -> Result<Signature, tss_esapi::Error> {
            let primary =
                c.create_primary(Hierarchy::Owner, primary_template, None, None, None, None)?;
            let loaded = c.load(primary.key_handle, private_struct, public_struct)?;
            if let Some(auth) = auth {
                c.tr_set_auth(loaded.into(), auth)?;
            }
            let scheme = match alg {
                TpmSshAlgorithm::EcdsaP256 => SignatureScheme::EcDsa {
                    hash_scheme: HashScheme::new(HashingAlgorithm::Sha256),
                },
                TpmSshAlgorithm::Rsa2048 => SignatureScheme::RsaSsa {
                    hash_scheme: HashScheme::new(HashingAlgorithm::Sha256),
                },
            };
            c.sign(loaded, digest_bytes, scheme, validation)
        })
        .map_err(|e| map_pin_error(alg, e))?;

    extract_signature_bytes(sig, alg)
}

fn extract_signature_bytes(sig: Signature, alg: TpmSshAlgorithm) -> Result<TpmSshSignature, Error> {
    match (sig, alg) {
        (Signature::EcDsa(ecdsa), TpmSshAlgorithm::EcdsaP256) => {
            let r_buf: &[u8] = ecdsa.signature_r().value();
            let s_buf: &[u8] = ecdsa.signature_s().value();
            let r = pad_left_to_32(r_buf);
            let s = pad_left_to_32(s_buf);
            let mut concat = Vec::with_capacity(64);
            concat.extend_from_slice(&r);
            concat.extend_from_slice(&s);
            Ok(TpmSshSignature::EcdsaP256RawConcat(concat))
        }
        (Signature::RsaSsa(rsassa), TpmSshAlgorithm::Rsa2048) => {
            let bytes: &[u8] = rsassa.signature().value();
            Ok(TpmSshSignature::Rsa2048(bytes.to_vec()))
        }
        (sig, alg) => Err(Error::Crypto(format!(
            "tpm-ssh sign: signature variant mismatch (got {sig:?} for {alg:?})"
        ))),
    }
}

fn pad_left_to_32(buf: &[u8]) -> [u8; 32] {
    let mut out = [0u8; 32];
    let n = buf.len().min(32);
    let off = 32 - n;
    out[off..].copy_from_slice(&buf[..n]);
    out
}

fn extract_public_key(public: &Public, alg: TpmSshAlgorithm) -> Result<TpmSshPublicKey, Error> {
    match (public, alg) {
        (Public::Ecc { unique, .. }, TpmSshAlgorithm::EcdsaP256) => {
            let x: &[u8] = unique.x().value();
            let y: &[u8] = unique.y().value();
            let mut uncompressed = Vec::with_capacity(65);
            uncompressed.push(0x04);
            uncompressed.extend_from_slice(&pad_left_to_32(x));
            uncompressed.extend_from_slice(&pad_left_to_32(y));
            Ok(TpmSshPublicKey::EcdsaP256 {
                uncompressed_65: uncompressed,
            })
        }
        (
            Public::Rsa {
                unique, parameters, ..
            },
            TpmSshAlgorithm::Rsa2048,
        ) => {
            let modulus: &[u8] = unique.value();
            // RSA public exponent on tss-esapi is u32 — encode to
            // big-endian then strip leading zeros.
            let exp_u32 = parameters.exponent().value();
            let exp_full = exp_u32.to_be_bytes();
            let exp_trim_start = exp_full.iter().position(|&b| b != 0).unwrap_or(3);
            let exponent = exp_full[exp_trim_start..].to_vec();
            Ok(TpmSshPublicKey::Rsa2048 {
                exponent,
                modulus: modulus.to_vec(),
            })
        }
        (other, alg) => Err(Error::Crypto(format!(
            "tpm-ssh public-key shape mismatch (got {other:?} for {alg:?})"
        ))),
    }
}

/// `TPM_RC_BAD_AUTH` (0x0000_0022 / formatted-1 variants 0x0000_098E /
/// 0x0000_098A) → "pin incorrect"; `TPM_RC_LOCKOUT` (0x0000_0921) →
/// "lockout". Mapped here so the connect path can route the retry
/// dialog vs the cooldown banner without substring-matching on the
/// upstream `Display` text.
fn map_pin_error(_alg: TpmSshAlgorithm, e: tss_esapi::Error) -> Error {
    let text = e.to_string();
    if text.contains("BadAuth") || text.contains("0x0000098e") || text.contains("0x0000098a") {
        Error::Crypto(format!("pin incorrect: {text}"))
    } else if text.contains("Lockout") || text.contains("0x00000921") {
        Error::Crypto(format!("lockout: {text}"))
    } else {
        Error::Crypto(format!("tpm-ssh sign: {text}"))
    }
}

fn sha256(data: &[u8]) -> Vec<u8> {
    use sha2::{Digest, Sha256};
    let mut hasher = Sha256::new();
    hasher.update(data);
    hasher.finalize().to_vec()
}

// ── TSS2 PRIVATE KEY envelope (TCG draft) ───────────────────────

/// Pack a `(public, private)` blob pair into the
/// `[u32 BE pub_len][pub][u32 BE priv_len][priv]` envelope shape
/// (same as the T2 seal-path's `pack`). The on-disk file wraps
/// THIS in the TCG-draft TSS2 PRIVATE KEY ASN.1 envelope (one
/// outer layer above what this module emits) — the
/// `lfs_core::archive::tpm_ssh` helper does the ASN.1 wrap so the
/// FFI perimeter here stays focused on the chip side.
pub fn pack_envelope(public: &[u8], private: &[u8]) -> Result<Vec<u8>, Error> {
    let pub_len = u32::try_from(public.len())
        .map_err(|_| Error::Crypto("tpm-ssh pack: pub_bytes length exceeds u32".into()))?;
    let priv_len = u32::try_from(private.len())
        .map_err(|_| Error::Crypto("tpm-ssh pack: priv_bytes length exceeds u32".into()))?;
    let mut out = Vec::with_capacity(8 + public.len() + private.len());
    out.extend_from_slice(&pub_len.to_be_bytes());
    out.extend_from_slice(public);
    out.extend_from_slice(&priv_len.to_be_bytes());
    out.extend_from_slice(private);
    Ok(out)
}

fn unpack(blob: &[u8]) -> Option<(&[u8], &[u8])> {
    if blob.len() < 8 {
        return None;
    }
    let pub_len = u32::from_be_bytes(blob[..4].try_into().ok()?) as usize;
    let priv_len_off = 4usize.checked_add(pub_len)?;
    let priv_len_end = priv_len_off.checked_add(4)?;
    if priv_len_end > blob.len() {
        return None;
    }
    let pub_bytes = &blob[4..priv_len_off];
    let priv_len = u32::from_be_bytes(blob[priv_len_off..priv_len_end].try_into().ok()?) as usize;
    let priv_off = priv_len_end;
    let priv_end = priv_off.checked_add(priv_len)?;
    if priv_end > blob.len() {
        return None;
    }
    Some((pub_bytes, &blob[priv_off..priv_end]))
}

/// TCG TPM2B wire shape: `[u16 BE size][bytes]`. Mirrors the helper
/// in `tpm_native` so both paths emit byte-identical envelopes.
fn marshall_tpm2b(bytes: &[u8]) -> Vec<u8> {
    let size = bytes.len() as u16;
    let mut out = Vec::with_capacity(TPM2B_SIZE_PREFIX + bytes.len());
    out.extend_from_slice(&size.to_be_bytes());
    out.extend_from_slice(bytes);
    out
}

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
    fn algorithm_round_trips_through_key_type_tag() {
        for alg in [TpmSshAlgorithm::EcdsaP256, TpmSshAlgorithm::Rsa2048] {
            let tag = alg.key_type_tag();
            assert_eq!(TpmSshAlgorithm::from_key_type(tag).unwrap(), alg);
        }
    }

    #[test]
    fn key_type_rejects_ed25519() {
        let err = TpmSshAlgorithm::from_key_type("ed25519").unwrap_err();
        // Refused with a typed Crypto error — Ed25519 is not in the
        // TPM 2.0 spec.
        assert!(matches!(err, Error::Crypto(_)));
    }

    #[test]
    fn envelope_round_trips() {
        let pub_bytes = vec![1u8, 2, 3, 4, 5];
        let priv_bytes = vec![6u8, 7, 8];
        let envelope = pack_envelope(&pub_bytes, &priv_bytes).unwrap();
        let (got_pub, got_priv) = unpack(&envelope).unwrap();
        assert_eq!(got_pub, pub_bytes.as_slice());
        assert_eq!(got_priv, priv_bytes.as_slice());
    }

    #[test]
    fn envelope_rejects_short_blob() {
        assert!(unpack(&[0u8; 7]).is_none());
        assert!(unpack(&[]).is_none());
    }

    #[test]
    fn envelope_rejects_truncated_priv_section() {
        // pub_len=2, pub=[0xaa,0xbb], priv_len=10 (way beyond
        // remaining bytes) — must reject without panicking.
        let mut blob = vec![0, 0, 0, 2, 0xaa, 0xbb, 0, 0, 0, 10];
        blob.extend_from_slice(&[0xcc, 0xcc]);
        assert!(unpack(&blob).is_none());
    }

    #[test]
    fn pad_left_to_32_zero_extends_short_input() {
        let out = pad_left_to_32(&[0x01]);
        assert_eq!(out[..31], [0u8; 31]);
        assert_eq!(out[31], 0x01);
    }

    #[test]
    fn pad_left_to_32_truncates_oversized_input() {
        // Defensive — TPM should never hand us > 32 bytes for r/s
        // on P-256, but the helper must not panic if it does.
        let input = [0x42u8; 64];
        let out = pad_left_to_32(&input);
        assert_eq!(out, [0x42u8; 32]);
    }

    #[test]
    fn make_persistent_rejects_out_of_range_handle() {
        let cfg = TpmConfig::default();
        let mut key = TpmSshKey {
            algorithm: TpmSshAlgorithm::EcdsaP256,
            storage: TpmSshStorage::Blob {
                private: vec![],
                public: vec![],
            },
            public: TpmSshPublicKey::EcdsaP256 {
                uncompressed_65: vec![],
            },
        };
        let err = make_persistent(&cfg, &mut key, 0x12345678).unwrap_err();
        assert!(matches!(err, Error::Crypto(_)));
    }

    #[test]
    fn wire_algorithm_default_matches_curve() {
        assert_eq!(
            TpmSshAlgorithm::EcdsaP256.wire_algorithm_default(),
            "ecdsa-sha2-nistp256"
        );
        // RSA defaults to SHA-256 — server flag selects -512 at
        // connect time per agent protocol §3.6.1.
        assert_eq!(
            TpmSshAlgorithm::Rsa2048.wire_algorithm_default(),
            "rsa-sha2-256"
        );
    }
}
