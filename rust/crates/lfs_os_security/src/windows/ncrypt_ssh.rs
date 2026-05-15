//! Windows Hello / NCrypt SSH key driver — TPM-bound key generation,
//! enumeration, signing, and deletion behind the Microsoft Platform
//! Crypto Provider (PCP).
//!
//! ## Why NOT KeyCredentialManager
//!
//! `Windows.Security.Credentials.KeyCredentialManager.RequestSignAsync`
//! produces **RSA-2048 PSS-SHA256**. SSH `rsa-sha2-256` / `rsa-sha2-512`
//! (RFC 8332) requires **PKCS#1 v1.5**. PSS bytes cannot be re-encoded
//! into v1.5 — the padding scheme is different at the bit level.
//! KCM is wire-incompatible with SSH userauth. The only Windows path
//! that emits an SSH-compatible signature is NCrypt + PCP with
//! `BCRYPT_PAD_PKCS1` (RSA) or no padding (ECDSA). The working
//! reference is `nCryptAgent` (https://github.com/unreality/nCryptAgent).
//!
//! ## CNG provider + UI policy
//!
//! Every SSH-bound key is minted under `Microsoft Platform Crypto
//! Provider` (`MS_PLATFORM_KEY_STORAGE_PROVIDER`). The provider
//! prefers TPM 2.0 hardware when present; on hosts without a TPM it
//! transparently falls back to a software KSP (`Microsoft Software
//! Key Storage Provider` semantics). The probe surfaces the two
//! cases as [`TpmTier::Hardware`] vs [`TpmTier::SoftwareKsp`]; the
//! UI labels the latter `Software-gated` per the capability ladder.
//!
//! UI policy is the load-bearing difference from
//! `super::hardware_vault`. The hardware-vault keys take
//! `NCRYPT_UI_POLICY` with the protect-key bit ON to fire Hello on
//! decrypt; the SSH path takes the same shape but fires Hello on
//! every SIGN — that's the security ceremony. Each
//! `NCRYPT_UI_FORCE_HIGH_PROTECTION_FLAG` requires that the user has
//! configured Windows Hello (PIN minimum); the property is set
//! before [`NCryptFinalizeKey`].
//!
//! ## Algorithms
//!
//! - **ECDSA P-256** → `NCRYPT_ECDSA_P256_ALGORITHM` → SSH
//!   `ecdsa-sha2-nistp256` (preferred default; smallest signature).
//! - **ECDSA P-384** → `NCRYPT_ECDSA_P384_ALGORITHM` → SSH
//!   `ecdsa-sha2-nistp384` (TPM-firmware-dependent — the create call
//!   surfaces a typed error when the host TPM cannot mint it).
//! - **RSA-2048 PKCS#1 v1.5** → `NCRYPT_RSA_ALGORITHM` (length 2048) →
//!   SSH `rsa-sha2-256` / `rsa-sha2-512`. Sign with
//!   `BCRYPT_PKCS1_PADDING_INFO { pszAlgId = BCRYPT_SHA256/512_ALGORITHM }`
//!   and the `BCRYPT_PAD_PKCS1` flag.
//!
//! ECDSA signatures come back as fixed-width raw `r || s` (64 bytes
//! for P-256, 96 for P-384, big-endian, no DER framing — this is the
//! `NCryptSignHash` contract for ECC keys). The SSH wrapper splits
//! them via [`lfs_core::ssh::wire::ecdsa_raw_concat_to_ssh_mpint`].
//! RSA signatures come back as the raw 256-byte block which the SSH
//! wrapper wraps with one length-prefix via
//! [`lfs_core::ssh::wire::rsa_pkcs1_v15_to_ssh_blob`].
//!
//! ## Lifecycle
//!
//! Persistent keys live under
//! `%APPDATA%\Microsoft\Crypto\PCPKSP\<user-sid>\` (NCrypt owns the
//! path; the SSH driver never touches the filesystem directly). The
//! CNG name format is `letsflutssh-ssh-<userhash>-<uuid>` — the
//! `userhash` prefix lets multi-user installs share the same CNG
//! namespace without colliding. `list` enumerates every key whose
//! name starts with the `letsflutssh-ssh-` prefix; `delete` is a
//! plain `NCryptDeleteKey`. Keys are device-bound — the chip refuses
//! to export the private bytes.

#![cfg(target_os = "windows")]

use std::ffi::c_void;

use windows::core::{Error as WinError, PCWSTR, PWSTR};
use windows::Win32::Foundation::{NTE_BAD_KEYSET, NTE_USER_CANCELLED};
use windows::Win32::Security::Cryptography::{
    NCryptCreatePersistedKey, NCryptDeleteKey, NCryptEnumKeys, NCryptExportKey, NCryptFinalizeKey,
    NCryptFreeBuffer, NCryptFreeObject, NCryptGetProperty, NCryptOpenKey,
    NCryptOpenStorageProvider, NCryptSetProperty, NCryptSignHash, BCRYPT_ECCKEY_BLOB,
    BCRYPT_ECCPUBLIC_BLOB, BCRYPT_ECDSA_PUBLIC_P256_MAGIC, BCRYPT_ECDSA_PUBLIC_P384_MAGIC,
    BCRYPT_PAD_PKCS1, BCRYPT_PKCS1_PADDING_INFO, BCRYPT_RSAKEY_BLOB, BCRYPT_RSAPUBLIC_BLOB,
    BCRYPT_SHA256_ALGORITHM, BCRYPT_SHA512_ALGORITHM, CERT_KEY_SPEC,
    MS_PLATFORM_KEY_STORAGE_PROVIDER, NCRYPT_ECDSA_P256_ALGORITHM, NCRYPT_ECDSA_P384_ALGORITHM,
    NCRYPT_FLAGS, NCRYPT_HANDLE, NCRYPT_KEY_HANDLE, NCRYPT_LENGTH_PROPERTY, NCRYPT_PROV_HANDLE,
    NCRYPT_RSA_ALGORITHM, NCRYPT_UI_FORCE_HIGH_PROTECTION_FLAG, NCRYPT_UI_POLICY,
    NCRYPT_UI_POLICY_PROPERTY, NCRYPT_UI_PROTECT_KEY_FLAG,
};

/// CNG persistent-key name prefix for **Hello-gated** SSH keys (UI
/// policy ON; every sign fires a Hello prompt). Every SSH-bound
/// NCrypt key the [`create`] path mints starts with this string;
/// [`list`] filters on the prefix when walking `NCryptEnumKeys` so
/// we don't surface keys minted by other apps against the same
/// provider.
const CNG_NAME_PREFIX: &str = "letsflutssh-ssh-";

/// CNG persistent-key name prefix for **silent TPM** keys (UI policy
/// absent; signs run unattended via the Microsoft Platform Crypto
/// Provider). Distinct from [`CNG_NAME_PREFIX`] so a single
/// `NCryptEnumKeys` walk can route by prefix when listing — Hello-
/// gated keys route to the Hello dispatcher, silent TPM keys to
/// the TPM dispatcher. Per Microsoft's NCrypt documentation and
/// the `nCryptAgent` reference impl, an NCrypt key minted under
/// `MS_PLATFORM_KEY_STORAGE_PROVIDER` without
/// `NCRYPT_UI_PROTECT_KEY_FLAG` set on `NCRYPT_UI_POLICY_PROPERTY`
/// runs unattended (no Hello / PIN prompt). Verified against:
///   - <https://learn.microsoft.com/en-us/windows/win32/api/ncrypt/nf-ncrypt-ncryptcreatepersistedkey>
///   - <https://github.com/unreality/nCryptAgent> (sign path)
const CNG_NAME_PREFIX_TPM: &str = "letsflutssh-tpm-";

/// `NCRYPT_IMPL_TYPE_PROPERTY` text constant — `windows-rs 0.62`
/// doesn't re-export it under the `Win32_Security_Cryptography`
/// feature set so we pin the literal locally. The property's
/// returned `u32` bitfield's `NCRYPT_IMPL_HARDWARE_FLAG (0x1)` bit
/// distinguishes TPM-backed keys from the software-KSP fallback.
const NCRYPT_IMPL_TYPE_PROPERTY_WSTR: &[u16] = &[
    'I' as u16, 'm' as u16, 'p' as u16, 'l' as u16, ' ' as u16, 'T' as u16, 'y' as u16, 'p' as u16,
    'e' as u16, 0u16,
];

const NCRYPT_IMPL_HARDWARE_FLAG: u32 = 0x0000_0001;

/// SSH-side algorithm choice. Drives the NCrypt algorithm constant
/// at create + sign time and the SSH wire-name on the public-key
/// blob.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SshKeyAlgo {
    /// ECDSA P-256 → `ecdsa-sha2-nistp256`. Preferred default —
    /// every Windows-Hello-capable TPM since Windows 10 1607 supports
    /// it, the signature is shortest, and OpenSSH servers default to
    /// it.
    EcdsaP256,
    /// ECDSA P-384 → `ecdsa-sha2-nistp384`. Optional; the TPM
    /// firmware may not implement it (older Infineon firmware caps
    /// at P-256). The wizard offers this only when the probe step
    /// confirms support.
    EcdsaP384,
    /// RSA-2048 PKCS#1 v1.5 → `rsa-sha2-256` / `rsa-sha2-512`. For
    /// older OpenSSH servers that don't speak ECDSA; the sign path
    /// honours the agent-protocol §3.6.1 flags bit so SHA-512 is
    /// the default and SHA-256 picks up when the client asks for it.
    Rsa2048,
}

impl SshKeyAlgo {
    /// Map our stored `ssh_keys.key_type` string back to the typed
    /// enum. Reverse of [`Self::wire_algorithm_default`]'s rough
    /// shape — the connect / agent dispatcher rebinds the
    /// algorithm based on the row's `key_type` plus the agent
    /// flags.
    pub fn from_key_type(key_type: &str) -> Result<Self, Error> {
        match key_type {
            "ecdsa-p256" | "ecdsa-sha2-nistp256" => Ok(Self::EcdsaP256),
            "ecdsa-p384" | "ecdsa-sha2-nistp384" => Ok(Self::EcdsaP384),
            "rsa" | "ssh-rsa" | "rsa-2048" => Ok(Self::Rsa2048),
            other => Err(Error::Backend(format!(
                "unknown key_type for Hello row: {other}"
            ))),
        }
    }

    /// Short tag persisted on `ssh_keys.key_type`. The agent
    /// dispatcher reads this back via [`Self::from_key_type`] to
    /// pick the right algorithm bag at sign time.
    pub fn key_type_tag(self) -> &'static str {
        match self {
            Self::EcdsaP256 => "ecdsa-sha2-nistp256",
            Self::EcdsaP384 => "ecdsa-sha2-nistp384",
            Self::Rsa2048 => "rsa-2048",
        }
    }

    /// NCrypt algorithm constant for `NCryptCreatePersistedKey`.
    fn ncrypt_algorithm(self) -> PCWSTR {
        match self {
            Self::EcdsaP256 => NCRYPT_ECDSA_P256_ALGORITHM,
            Self::EcdsaP384 => NCRYPT_ECDSA_P384_ALGORITHM,
            Self::Rsa2048 => NCRYPT_RSA_ALGORITHM,
        }
    }

    /// Default SSH wire-name for the wizard's "Copy to authorized_keys"
    /// line. RSA defaults to `rsa-sha2-512` because the older
    /// `ssh-rsa` (SHA-1) is server-deprecated; the agent dispatcher
    /// may downgrade to `rsa-sha2-256` when the client asks via the
    /// protocol §3.6.1 flag.
    pub fn wire_algorithm_default(self) -> &'static str {
        match self {
            Self::EcdsaP256 => "ecdsa-sha2-nistp256",
            Self::EcdsaP384 => "ecdsa-sha2-nistp384",
            Self::Rsa2048 => "rsa-sha2-512",
        }
    }
}

/// TPM-tier classification returned by [`probe_availability`]. Drives
/// the wizard's honest-label rendering — `Hardware` shows the plain
/// "Windows Hello (TPM)" copy; `SoftwareKsp` adds the localized
/// "Software-gated" suffix.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TpmTier {
    /// `NCRYPT_IMPL_HARDWARE_FLAG` set on a probe key — the provider
    /// uses TPM 2.0 to back the private bytes. Strongest binding.
    Hardware,
    /// Provider opened but probe key landed without the hardware
    /// flag — keys live in the user's PCPKSP software fallback
    /// store. The Hello ceremony still fires (the UI policy gates
    /// the sign), but the private bytes are protected by user-mode
    /// software only.
    SoftwareKsp,
}

/// Why the Hello-SSH driver is unreachable on this host. Surfaced
/// by [`probe_availability`] and mapped to a localized reason in the
/// Dart wizard.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum UnavailableReason {
    /// `MS_PLATFORM_KEY_STORAGE_PROVIDER` could not be opened. Most
    /// commonly: no TPM (consumer Win10 SKU pre-1809 + missing TPM
    /// chip), GPO-blocked PCP, or Win < 10 1607.
    ProviderUnavailable(String),
    /// Hello is not configured on the host — `NCryptFinalizeKey` on
    /// the probe key surfaced `NTE_USER_CANCELLED` or
    /// `STATUS_HELLO_NOT_CONFIGURED`. The wizard routes the user at
    /// the documented "Settings → Sign-in options" remediation.
    HelloNotConfigured,
    /// Build target without Windows support (Linux, macOS, Android,
    /// iOS). Toolbar entry stays hidden.
    UnsupportedPlatform,
    /// Any other failure — carries the diagnostic string.
    Other(String),
}

impl std::fmt::Display for UnavailableReason {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::ProviderUnavailable(s) => write!(f, "Microsoft Platform Crypto Provider: {s}"),
            Self::HelloNotConfigured => write!(f, "Windows Hello not configured"),
            Self::UnsupportedPlatform => write!(f, "Windows-only feature"),
            Self::Other(s) => write!(f, "{s}"),
        }
    }
}

/// Handle returned by [`create`] / [`list`]. Carries the CNG
/// persistent-key name + the algorithm choice. The label is captured
/// at create time and echoed back on listing so the key-manager UI
/// can render the row without a second DB hop.
#[derive(Debug, Clone)]
pub struct HelloKeyHandle {
    pub credential_name: String,
    pub algo: SshKeyAlgo,
    pub label: String,
}

/// SSH-side error envelope. The connect / sign / generate paths
/// surface this as `Error::Hello(format!("{e}"))` at the `lfs_core`
/// boundary.
#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error("hello: unavailable: {0}")]
    Unavailable(UnavailableReason),

    #[error("hello: {0}")]
    Backend(String),

    #[error("hello: key not found")]
    KeyNotFound,

    #[error("hello: cancelled")]
    Cancelled,

    #[error("hello: TPM firmware does not support P-384")]
    P384NotSupported,
}

fn fmt_win(label: &str, e: WinError) -> Error {
    Error::Backend(format!("{label}: 0x{:08x}", e.code().0 as u32))
}

fn win_error_code(e: &WinError) -> u32 {
    e.code().0 as u32
}

// ── RAII wrappers ───────────────────────────────────────────────────

struct OwnedProvider(NCRYPT_PROV_HANDLE);
impl OwnedProvider {
    fn handle(&self) -> NCRYPT_PROV_HANDLE {
        self.0
    }
}
impl Drop for OwnedProvider {
    fn drop(&mut self) {
        if self.0 .0 != 0 {
            // SAFETY: `NCryptFreeObject` releases the kernel-owned NCrypt handle; we wrap the
            // integer in `NCRYPT_HANDLE` and call once at Drop time so the release pairs with the
            // open.
            let _ = unsafe { NCryptFreeObject(NCRYPT_HANDLE(self.0 .0)) };
        }
    }
}

struct OwnedKey(NCRYPT_KEY_HANDLE);
impl OwnedKey {
    fn handle(&self) -> NCRYPT_KEY_HANDLE {
        self.0
    }
    fn into_raw(mut self) -> NCRYPT_KEY_HANDLE {
        let h = self.0;
        self.0 = NCRYPT_KEY_HANDLE::default();
        h
    }
}
impl Drop for OwnedKey {
    fn drop(&mut self) {
        if self.0 .0 != 0 {
            // SAFETY: `NCryptFreeObject` releases the kernel-owned NCrypt handle; we wrap the
            // integer in `NCRYPT_HANDLE` and call once at Drop time so the release pairs with the
            // open.
            let _ = unsafe { NCryptFreeObject(NCRYPT_HANDLE(self.0 .0)) };
        }
    }
}

// ── Public entry points ─────────────────────────────────────────────

/// Probe whether Hello-bound SSH keys are reachable on this host.
/// Mints a throw-away ECDSA P-256 key under a `letsflutssh.probe.<uuid>`
/// name with UI policy ON, then deletes it. Inspects
/// `NCRYPT_IMPL_TYPE_PROPERTY` on the probe key to distinguish the
/// hardware vs software-KSP tier.
///
/// `NTE_USER_CANCELLED` on the probe finalise step is taken to mean
/// "Hello is not configured" — the OS surfaces the configure-Hello
/// dialog and the user dismisses it. The wizard re-routes at the
/// "Configure Windows Hello first" reason.
pub fn probe_availability() -> Result<TpmTier, UnavailableReason> {
    let provider_raw =
        open_provider().map_err(|e| UnavailableReason::ProviderUnavailable(e.to_string()))?;
    let provider = OwnedProvider(provider_raw);
    let name = mint_probe_name();
    let name_w = to_wide_z(&name);
    let mut key = NCRYPT_KEY_HANDLE::default();
    // SAFETY: `NCryptCreatePersistedKey` reads the provider handle + algorithm name + UTF-16 key
    // name (alive on the stack) and writes a new key handle into the out-parameter.
    unsafe {
        NCryptCreatePersistedKey(
            provider.handle(),
            &mut key,
            NCRYPT_ECDSA_P256_ALGORITHM,
            PCWSTR(name_w.as_ptr()),
            CERT_KEY_SPEC(0),
            NCRYPT_FLAGS(0),
        )
    }
    .map_err(|e| {
        UnavailableReason::Other(format!(
            "NCryptCreatePersistedKey: 0x{:08x}",
            win_error_code(&e)
        ))
    })?;
    let probe_key = OwnedKey(key);
    if let Err(e) = set_ui_policy(probe_key.handle()) {
        return Err(UnavailableReason::Other(e.to_string()));
    }
    // SAFETY: `NCryptFinalizeKey` commits the persisted key under the handle we own; no out-params.
    let finalize = unsafe { NCryptFinalizeKey(probe_key.handle(), NCRYPT_FLAGS(0)) };
    let tier = match finalize {
        Ok(()) => read_impl_tier(probe_key.handle()),
        Err(e) => {
            // Best-effort delete the half-created key — finalize
            // failed but the persisted name may still hold a slot.
            // SAFETY: `NCryptDeleteKey` consumes the key handle (which we own via
            // `OwnedNCryptKeyHandle`) and removes the persistent key; the handle is invalidated by
            // the call regardless of outcome.
            let _ = unsafe { NCryptDeleteKey(probe_key.into_raw(), 0) };
            return Err(map_finalize_error(&e));
        }
    };
    // Best-effort delete the probe key.
    // SAFETY: `NCryptDeleteKey` consumes the key handle (which we own via `OwnedNCryptKeyHandle`)
    // and removes the persistent key; the handle is invalidated by the call regardless of outcome.
    let _ = unsafe { NCryptDeleteKey(probe_key.into_raw(), 0) };
    Ok(tier)
}

/// Mint a fresh Hello-bound key under [`SshKeyAlgo`]. Fires the
/// Hello prompt at the finalise step (the UI policy is in place by
/// then). Returns the handle the caller persists in
/// `ssh_keys.hello_credential_name`; the public-half wire blob is
/// fetched via [`public_key_ssh_wire`] right after.
pub fn create(label: &str, algo: SshKeyAlgo) -> Result<HelloKeyHandle, Error> {
    let provider_raw = open_provider()?;
    let provider = OwnedProvider(provider_raw);
    let name = mint_credential_name();
    let name_w = to_wide_z(&name);
    let mut key = NCRYPT_KEY_HANDLE::default();
    // SAFETY: `NCryptCreatePersistedKey` reads the provider handle + algorithm name + UTF-16 key
    // name (alive on the stack) and writes a new key handle into the out-parameter.
    unsafe {
        NCryptCreatePersistedKey(
            provider.handle(),
            &mut key,
            algo.ncrypt_algorithm(),
            PCWSTR(name_w.as_ptr()),
            CERT_KEY_SPEC(0),
            NCRYPT_FLAGS(0),
        )
    }
    .map_err(|e| {
        if matches!(algo, SshKeyAlgo::EcdsaP384) && is_unsupported_alg(&e) {
            Error::P384NotSupported
        } else {
            fmt_win("NCryptCreatePersistedKey", e)
        }
    })?;
    let owned_key = OwnedKey(key);
    if matches!(algo, SshKeyAlgo::Rsa2048) {
        set_rsa_length(owned_key.handle())?;
    }
    set_ui_policy(owned_key.handle())?;
    // SAFETY: `NCryptFinalizeKey` commits the persisted key under the handle we own; no out-params.
    match unsafe { NCryptFinalizeKey(owned_key.handle(), NCRYPT_FLAGS(0)) } {
        Ok(()) => {}
        Err(e) => {
            let mapped = map_finalize_error(&e);
            return Err(match mapped {
                UnavailableReason::HelloNotConfigured => {
                    Error::Unavailable(UnavailableReason::HelloNotConfigured)
                }
                other => Error::Backend(other.to_string()),
            });
        }
    }
    Ok(HelloKeyHandle {
        credential_name: name,
        algo,
        label: label.to_string(),
    })
}

/// Public-key material in a transport-friendly shape — caller wraps
/// in the SSH wire format via the shared `lfs_core::ssh::wire`
/// encoders. We don't reach into `lfs_core` from here so the
/// `lfs_os_security` -> `lfs_core` edge stays absent (audit invariant:
/// `lfs_core` may depend on `lfs_os_security`, never the reverse).
#[derive(Debug, Clone)]
pub enum HelloPublicKey {
    /// `0x04 || X(32) || Y(32)` uncompressed P-256 point. Caller
    /// hands this to `lfs_core::ssh::wire::encode_public_ecdsa_p256`
    /// for the SSH wire blob.
    EcdsaP256 { uncompressed_65: Vec<u8> },
    /// `0x04 || X(48) || Y(48)` uncompressed P-384 point. Caller
    /// hands this to `lfs_core::ssh::wire::encode_public_ecdsa_p384`.
    EcdsaP384 { uncompressed_97: Vec<u8> },
    /// `e` + `n` big-endian magnitudes (no leading-zero discipline
    /// applied; the mpint encoder handles it). Caller hands these
    /// to `lfs_core::ssh::wire::encode_public_rsa`.
    Rsa2048 { exponent: Vec<u8>, modulus: Vec<u8> },
}

/// Pull the public half of the persisted key. Returns a typed
/// [`HelloPublicKey`] — the SSH-wire wrap happens in `lfs_core` so
/// this crate stays free of `lfs_core` deps (audit invariant).
///
/// CNG returns ECDSA keys as `BCRYPT_ECCKEY_BLOB + X || Y` and RSA
/// keys as `BCRYPT_RSAKEY_BLOB + e || n`; we parse the on-wire shape
/// and hand the magnitudes through verbatim.
pub fn public_key_material(handle: &HelloKeyHandle) -> Result<HelloPublicKey, Error> {
    let provider_raw = open_provider()?;
    let provider = OwnedProvider(provider_raw);
    let key = open_existing_key(provider.handle(), &handle.credential_name)?;
    match handle.algo {
        SshKeyAlgo::EcdsaP256 => {
            let blob = export_blob(key.handle(), BCRYPT_ECCPUBLIC_BLOB)?;
            let uncompressed = parse_ecdsa_uncompressed(&blob, SshKeyAlgo::EcdsaP256)?;
            Ok(HelloPublicKey::EcdsaP256 {
                uncompressed_65: uncompressed,
            })
        }
        SshKeyAlgo::EcdsaP384 => {
            let blob = export_blob(key.handle(), BCRYPT_ECCPUBLIC_BLOB)?;
            let uncompressed = parse_ecdsa_uncompressed(&blob, SshKeyAlgo::EcdsaP384)?;
            Ok(HelloPublicKey::EcdsaP384 {
                uncompressed_97: uncompressed,
            })
        }
        SshKeyAlgo::Rsa2048 => {
            let blob = export_blob(key.handle(), BCRYPT_RSAPUBLIC_BLOB)?;
            let (exponent, modulus) = parse_rsa_magnitudes(&blob)?;
            Ok(HelloPublicKey::Rsa2048 { exponent, modulus })
        }
    }
}

/// Raw NCrypt sign output — caller wraps in the SSH wire-format via
/// the shared `lfs_core::ssh::wire` helpers. Keeps this crate free
/// of `lfs_core` deps (audit invariant).
#[derive(Debug, Clone)]
pub enum HelloSignature {
    /// `r || s` big-endian fixed-width raw bytes. Hand to
    /// `ecdsa_raw_concat_to_ssh_mpint` for the SSH userauth body.
    /// 64 bytes for P-256, 96 bytes for P-384.
    EcdsaRaw(Vec<u8>),
    /// Raw PKCS#1 v1.5 signature (256 bytes for RSA-2048). Hand to
    /// `rsa_pkcs1_v15_to_ssh_blob`.
    RsaPkcs1V15(Vec<u8>),
}

/// Sign `data` for SSH userauth. `algorithm` selects the RSA hash
/// (`rsa-sha2-256` / `rsa-sha2-512`); ECDSA paths derive the hash
/// from the curve (P-256 → SHA-256, P-384 → SHA-384).
///
/// Returns the raw NCrypt sign output — caller hands it to the
/// `lfs_core::ssh::wire` helpers to compose the SSH userauth
/// `signature` body.
///
/// The Hello prompt fires inside `NCryptSignHash` per the UI policy
/// set at create time. `NTE_USER_CANCELLED` maps to
/// [`Error::Cancelled`] so the UI can route a "cancelled" reason
/// distinct from a hardware failure.
pub fn sign_for_ssh(
    handle: &HelloKeyHandle,
    data: &[u8],
    algorithm: &str,
) -> Result<HelloSignature, Error> {
    let provider_raw = open_provider()?;
    let provider = OwnedProvider(provider_raw);
    let key = open_existing_key(provider.handle(), &handle.credential_name)?;

    match handle.algo {
        SshKeyAlgo::EcdsaP256 => {
            let hashed = sha256(data);
            let raw = sign_hash_ecdsa(key.handle(), &hashed)?;
            Ok(HelloSignature::EcdsaRaw(raw))
        }
        SshKeyAlgo::EcdsaP384 => {
            let hashed = sha384(data);
            let raw = sign_hash_ecdsa(key.handle(), &hashed)?;
            Ok(HelloSignature::EcdsaRaw(raw))
        }
        SshKeyAlgo::Rsa2048 => {
            let (pad_alg, hashed) = match algorithm {
                "rsa-sha2-256" => (BCRYPT_SHA256_ALGORITHM, sha256(data)),
                "rsa-sha2-512" => (BCRYPT_SHA512_ALGORITHM, sha512(data)),
                other => {
                    return Err(Error::Backend(format!(
                        "rsa-pkcs1v15 sign expected rsa-sha2-256/512, got {other}"
                    )))
                }
            };
            let sig = sign_hash_rsa_pkcs1(key.handle(), &hashed, pad_alg)?;
            Ok(HelloSignature::RsaPkcs1V15(sig))
        }
    }
}

/// Enumerate every persisted Hello-SSH key under the
/// `letsflutssh-ssh-` prefix. The algorithm is recovered from the
/// `pszAlgid` field on the enum entry.
pub fn list() -> Result<Vec<HelloKeyHandle>, Error> {
    let provider_raw = open_provider()?;
    let provider = OwnedProvider(provider_raw);
    let mut enum_state: *mut c_void = std::ptr::null_mut();
    let mut out = Vec::new();
    loop {
        let mut key_name_ptr: *mut windows::Win32::Security::Cryptography::NCryptKeyName =
            std::ptr::null_mut();
        // SAFETY: `NCryptEnumKeys` reads the provider handle + caller-owned enum-state pointer and
        // writes a +1-allocated `NCryptKeyName` pointer into the out-parameter; the buffer is
        // freed by `NCryptFreeBuffer` below.
        let result = unsafe {
            NCryptEnumKeys(
                provider.handle(),
                PCWSTR::null(),
                &mut key_name_ptr,
                &mut enum_state,
                NCRYPT_FLAGS(0),
            )
        };
        if let Err(err) = result {
            // `NTE_NO_MORE_ITEMS` (0x8009002A) — end of enumeration.
            // Anything else propagates.
            let code = win_error_code(&err);
            if code == 0x8009_002A {
                break;
            } else {
                return Err(Error::Backend(format!("NCryptEnumKeys: 0x{code:08x}")));
            }
        }
        if key_name_ptr.is_null() {
            break;
        }
        // SAFETY: `key_name_ptr` is a non-null `*const NCryptKeyName` the kernel allocated and
        // handed back; we keep the pointer alive until the matching `NCryptFreeBuffer` below.
        let entry = unsafe { &*key_name_ptr };
        // SAFETY: `entry` came from NCryptEnumKeys which guarantees
        // both `pszName` and `pszAlgid` point at NUL-terminated wide
        // strings owned by the allocator behind the same handle. The
        // `NCryptFreeBuffer` below tears the whole entry down — we
        // copy out before that fires.
        let name = unsafe { pwstr_to_string(entry.pszName) };
        // SAFETY: `pwstr_to_string` walks the OS-allocated NUL-terminated UTF-16 buffer pointed at
        // by the NCrypt struct; the pointer remains valid until the matching `NCryptFreeBuffer`
        // runs.
        let alg_name = unsafe { pwstr_to_string(entry.pszAlgid) };
        if name.starts_with(CNG_NAME_PREFIX) {
            if let Some(algo) = algo_from_alg_name(&alg_name) {
                out.push(HelloKeyHandle {
                    credential_name: name,
                    algo,
                    label: String::new(),
                });
            }
        }
        // `NCryptEnumKeys` allocates the key-name struct + its
        // strings; we must release with `NCryptFreeBuffer` per the
        // docs, otherwise each iteration leaks a few hundred bytes.
        // SAFETY: `NCryptFreeBuffer` releases the OS-allocated buffer pointer the matching NCrypt
        // API handed us; no other reference to it remains.
        let _ = unsafe { NCryptFreeBuffer(key_name_ptr as *mut c_void) };
    }
    if !enum_state.is_null() {
        // SAFETY: `NCryptFreeBuffer` releases the OS-allocated buffer pointer the matching NCrypt
        // API handed us; no other reference to it remains.
        let _ = unsafe { NCryptFreeBuffer(enum_state) };
    }
    Ok(out)
}

/// Handle for the **silent TPM** variant — same TPM-bound key
/// material under the Microsoft Platform Crypto Provider, but with
/// `NCRYPT_UI_POLICY_PROPERTY` left at the provider default so
/// `NCryptSignHash` runs unattended. The two handle types stay
/// distinct so the connect / agent dispatcher cannot accidentally
/// route a silent key through the Hello-prompt path or vice versa.
#[derive(Debug, Clone)]
pub struct TpmSilentKeyHandle {
    pub credential_name: String,
    pub algo: SshKeyAlgo,
    pub label: String,
}

/// Mint a fresh **silent TPM**-bound key under [`SshKeyAlgo`]. Same
/// CNG flow as [`create`] but **without** the
/// `NCRYPT_UI_POLICY_PROPERTY` set — the resulting key signs without
/// firing any OS-level prompt. Intended for headless service-account
/// contexts where typing a Hello PIN per sign is impossible. Returns
/// the handle the caller persists in `ssh_keys.cng_key_name`.
///
/// The Dart wizard labels the row "TPM 2.0 (silent)" so users
/// understand the security contract differs from Hello-gated keys —
/// anyone with desktop access to the logged-in user can sign.
pub fn create_silent(label: &str, algo: SshKeyAlgo) -> Result<TpmSilentKeyHandle, Error> {
    let provider_raw = open_provider()?;
    let provider = OwnedProvider(provider_raw);
    let name = mint_credential_name_tpm();
    let name_w = to_wide_z(&name);
    let mut key = NCRYPT_KEY_HANDLE::default();
    // SAFETY: `NCryptCreatePersistedKey` reads the provider handle + algorithm name + UTF-16 key
    // name (alive on the stack) and writes a new key handle into the out-parameter.
    unsafe {
        NCryptCreatePersistedKey(
            provider.handle(),
            &mut key,
            algo.ncrypt_algorithm(),
            PCWSTR(name_w.as_ptr()),
            CERT_KEY_SPEC(0),
            NCRYPT_FLAGS(0),
        )
    }
    .map_err(|e| {
        if matches!(algo, SshKeyAlgo::EcdsaP384) && is_unsupported_alg(&e) {
            Error::P384NotSupported
        } else {
            fmt_win("NCryptCreatePersistedKey", e)
        }
    })?;
    let owned_key = OwnedKey(key);
    if matches!(algo, SshKeyAlgo::Rsa2048) {
        set_rsa_length(owned_key.handle())?;
    }
    // No `set_ui_policy` call — that is the load-bearing difference
    // from [`create`]. With the UI policy property absent, the
    // provider runs in its default "unattended" mode and
    // `NCryptSignHash` does not prompt the user.
    // SAFETY: `NCryptFinalizeKey` commits the persisted key under the handle we own; no out-params.
    unsafe { NCryptFinalizeKey(owned_key.handle(), NCRYPT_FLAGS(0)) }
        .map_err(|e| fmt_win("NCryptFinalizeKey(silent)", e))?;
    Ok(TpmSilentKeyHandle {
        credential_name: name,
        algo,
        label: label.to_string(),
    })
}

/// Public-key material for a silent TPM-bound key. Same shape as
/// [`public_key_material`] but typed against [`TpmSilentKeyHandle`]
/// so the call sites don't accidentally cross handle variants.
pub fn public_key_material_silent(handle: &TpmSilentKeyHandle) -> Result<HelloPublicKey, Error> {
    let provider_raw = open_provider()?;
    let provider = OwnedProvider(provider_raw);
    let key = open_existing_key(provider.handle(), &handle.credential_name)?;
    match handle.algo {
        SshKeyAlgo::EcdsaP256 => {
            let blob = export_blob(key.handle(), BCRYPT_ECCPUBLIC_BLOB)?;
            let uncompressed = parse_ecdsa_uncompressed(&blob, SshKeyAlgo::EcdsaP256)?;
            Ok(HelloPublicKey::EcdsaP256 {
                uncompressed_65: uncompressed,
            })
        }
        SshKeyAlgo::EcdsaP384 => {
            let blob = export_blob(key.handle(), BCRYPT_ECCPUBLIC_BLOB)?;
            let uncompressed = parse_ecdsa_uncompressed(&blob, SshKeyAlgo::EcdsaP384)?;
            Ok(HelloPublicKey::EcdsaP384 {
                uncompressed_97: uncompressed,
            })
        }
        SshKeyAlgo::Rsa2048 => {
            let blob = export_blob(key.handle(), BCRYPT_RSAPUBLIC_BLOB)?;
            let (exponent, modulus) = parse_rsa_magnitudes(&blob)?;
            Ok(HelloPublicKey::Rsa2048 { exponent, modulus })
        }
    }
}

/// Sign `data` for SSH userauth via a silent TPM-bound key.
/// Behaviour matches [`sign_for_ssh`] except that `NCryptSignHash`
/// runs unattended — no Hello prompt fires.
pub fn sign_for_ssh_silent(
    handle: &TpmSilentKeyHandle,
    data: &[u8],
    algorithm: &str,
) -> Result<HelloSignature, Error> {
    let provider_raw = open_provider()?;
    let provider = OwnedProvider(provider_raw);
    let key = open_existing_key(provider.handle(), &handle.credential_name)?;
    match handle.algo {
        SshKeyAlgo::EcdsaP256 => {
            let hashed = sha256(data);
            let raw = sign_hash_ecdsa(key.handle(), &hashed)?;
            Ok(HelloSignature::EcdsaRaw(raw))
        }
        SshKeyAlgo::EcdsaP384 => {
            let hashed = sha384(data);
            let raw = sign_hash_ecdsa(key.handle(), &hashed)?;
            Ok(HelloSignature::EcdsaRaw(raw))
        }
        SshKeyAlgo::Rsa2048 => {
            let (pad_alg, hashed) = match algorithm {
                "rsa-sha2-256" => (BCRYPT_SHA256_ALGORITHM, sha256(data)),
                "rsa-sha2-512" => (BCRYPT_SHA512_ALGORITHM, sha512(data)),
                other => {
                    return Err(Error::Backend(format!(
                        "rsa-pkcs1v15 silent-tpm sign expected rsa-sha2-256/512, got {other}"
                    )))
                }
            };
            let sig = sign_hash_rsa_pkcs1(key.handle(), &hashed, pad_alg)?;
            Ok(HelloSignature::RsaPkcs1V15(sig))
        }
    }
}

/// Enumerate persisted silent-TPM keys (`letsflutssh-tpm-` prefix).
/// Mirrors [`list`] but filters by the TPM prefix instead.
pub fn list_silent() -> Result<Vec<TpmSilentKeyHandle>, Error> {
    let provider_raw = open_provider()?;
    let provider = OwnedProvider(provider_raw);
    let mut enum_state: *mut c_void = std::ptr::null_mut();
    let mut out = Vec::new();
    loop {
        let mut key_name_ptr: *mut windows::Win32::Security::Cryptography::NCryptKeyName =
            std::ptr::null_mut();
        // SAFETY: `NCryptEnumKeys` reads the provider handle + caller-owned enum-state pointer and
        // writes a +1-allocated `NCryptKeyName` pointer into the out-parameter; the buffer is
        // freed by `NCryptFreeBuffer` below.
        let result = unsafe {
            NCryptEnumKeys(
                provider.handle(),
                PCWSTR::null(),
                &mut key_name_ptr,
                &mut enum_state,
                NCRYPT_FLAGS(0),
            )
        };
        if let Err(err) = result {
            let code = win_error_code(&err);
            if code == 0x8009_002A {
                break;
            } else {
                return Err(Error::Backend(format!("NCryptEnumKeys: 0x{code:08x}")));
            }
        }
        if key_name_ptr.is_null() {
            break;
        }
        // SAFETY: `key_name_ptr` is a non-null `*const NCryptKeyName` the kernel allocated and
        // handed back; we keep the pointer alive until the matching `NCryptFreeBuffer` below.
        let entry = unsafe { &*key_name_ptr };
        // SAFETY: `pwstr_to_string` walks the OS-allocated NUL-terminated UTF-16 buffer pointed at
        // by the NCrypt struct; the pointer remains valid until the matching `NCryptFreeBuffer`
        // runs.
        let name = unsafe { pwstr_to_string(entry.pszName) };
        // SAFETY: `pwstr_to_string` walks the OS-allocated NUL-terminated UTF-16 buffer pointed at
        // by the NCrypt struct; the pointer remains valid until the matching `NCryptFreeBuffer`
        // runs.
        let alg_name = unsafe { pwstr_to_string(entry.pszAlgid) };
        if name.starts_with(CNG_NAME_PREFIX_TPM) {
            if let Some(algo) = algo_from_alg_name(&alg_name) {
                out.push(TpmSilentKeyHandle {
                    credential_name: name,
                    algo,
                    label: String::new(),
                });
            }
        }
        // SAFETY: `NCryptFreeBuffer` releases the OS-allocated buffer pointer the matching NCrypt
        // API handed us; no other reference to it remains.
        let _ = unsafe { NCryptFreeBuffer(key_name_ptr as *mut c_void) };
    }
    if !enum_state.is_null() {
        // SAFETY: `NCryptFreeBuffer` releases the OS-allocated buffer pointer the matching NCrypt
        // API handed us; no other reference to it remains.
        let _ = unsafe { NCryptFreeBuffer(enum_state) };
    }
    Ok(out)
}

/// Drop the silent TPM-bound CNG key matched by
/// `handle.credential_name`. Missing key returns `Ok(())` (mirrors
/// [`delete`]).
pub fn delete_silent(handle: &TpmSilentKeyHandle) -> Result<(), Error> {
    let provider_raw = open_provider()?;
    let provider = OwnedProvider(provider_raw);
    let key = match open_existing_key(provider.handle(), &handle.credential_name) {
        Ok(k) => k,
        Err(Error::KeyNotFound) => return Ok(()),
        Err(e) => return Err(e),
    };
    let raw = key.into_raw();
    // SAFETY: `NCryptDeleteKey` consumes the key handle (which we own via `OwnedNCryptKeyHandle`)
    // and removes the persistent key; the handle is invalidated by the call regardless of outcome.
    unsafe { NCryptDeleteKey(raw, 0) }.map_err(|e| fmt_win("NCryptDeleteKey(silent)", e))
}

fn mint_credential_name_tpm() -> String {
    use rand::RngCore;
    let mut bytes = [0u8; 8];
    rand::rngs::OsRng.fill_bytes(&mut bytes);
    let suffix: String = bytes.iter().map(|b| format!("{b:02x}")).collect();
    let user_hash = user_hash_prefix();
    format!("{CNG_NAME_PREFIX_TPM}{user_hash}-{suffix}")
}

/// Drop the on-TPM key matched by `handle.credential_name`. Missing
/// key returns `Ok(())` — the API contract mirrors the Apple SE
/// path where the OS GCs orphans on next launch.
pub fn delete(handle: &HelloKeyHandle) -> Result<(), Error> {
    let provider_raw = open_provider()?;
    let provider = OwnedProvider(provider_raw);
    let key = match open_existing_key(provider.handle(), &handle.credential_name) {
        Ok(k) => k,
        Err(Error::KeyNotFound) => return Ok(()),
        Err(e) => return Err(e),
    };
    let raw = key.into_raw();
    // SAFETY: `NCryptDeleteKey` consumes the key handle (which we own via `OwnedNCryptKeyHandle`)
    // and removes the persistent key; the handle is invalidated by the call regardless of outcome.
    unsafe { NCryptDeleteKey(raw, 0) }.map_err(|e| fmt_win("NCryptDeleteKey", e))
}

// ── Internals ───────────────────────────────────────────────────────

fn open_provider() -> Result<NCRYPT_PROV_HANDLE, Error> {
    let mut provider = NCRYPT_PROV_HANDLE::default();
    // SAFETY: `NCryptOpenStorageProvider` is a CNG API that writes a provider handle into the
    // out-parameter on success; the kernel does not retain the pointer past the call. The handle
    // is wrapped in `OwnedNCryptProvHandle` for RAII release.
    unsafe { NCryptOpenStorageProvider(&mut provider, MS_PLATFORM_KEY_STORAGE_PROVIDER, 0) }
        .map_err(|e| {
            Error::Unavailable(UnavailableReason::ProviderUnavailable(format!(
                "0x{:08x}",
                win_error_code(&e)
            )))
        })?;
    Ok(provider)
}

fn open_existing_key(
    provider: NCRYPT_PROV_HANDLE,
    credential_name: &str,
) -> Result<OwnedKey, Error> {
    let name_w = to_wide_z(credential_name);
    let mut key = NCRYPT_KEY_HANDLE::default();
    // SAFETY: `NCryptOpenKey` reads the provider handle + UTF-16 name (alive on the stack) and
    // writes a +1 key handle into the out-parameter; the key is wrapped in `OwnedNCryptKeyHandle`
    // for RAII release.
    let result = unsafe {
        NCryptOpenKey(
            provider,
            &mut key,
            PCWSTR(name_w.as_ptr()),
            CERT_KEY_SPEC(0),
            NCRYPT_FLAGS(0),
        )
    };
    match result {
        Ok(()) => Ok(OwnedKey(key)),
        Err(e) if win_error_code(&e) == win_error_code(&WinError::from(NTE_BAD_KEYSET)) => {
            Err(Error::KeyNotFound)
        }
        Err(e) => Err(fmt_win("NCryptOpenKey", e)),
    }
}

fn set_ui_policy(key: NCRYPT_KEY_HANDLE) -> Result<(), Error> {
    let policy = NCRYPT_UI_POLICY {
        dwVersion: 1,
        dwFlags: NCRYPT_UI_PROTECT_KEY_FLAG | NCRYPT_UI_FORCE_HIGH_PROTECTION_FLAG,
        // The caller can localize the Hello dialog via these
        // strings; we leave them null today and pick up the OS
        // default ("Authenticate with Windows Hello to allow this
        // app to sign data"). Localising via Dart would require a
        // round-trip on every sign — out of scope.
        pszCreationTitle: PCWSTR::null(),
        pszFriendlyName: PCWSTR::null(),
        pszDescription: PCWSTR::null(),
    };
    // SAFETY: `&policy` points at a stack-local `NCRYPT_UI_POLICY` POD whose layout matches the
    // documented Win32 struct; the resulting byte slice borrows from the same stack frame and is
    // consumed by the immediately following NCrypt call.
    let bytes = unsafe {
        std::slice::from_raw_parts(
            (&policy as *const NCRYPT_UI_POLICY) as *const u8,
            std::mem::size_of::<NCRYPT_UI_POLICY>(),
        )
    };
    // SAFETY: `NCryptSetProperty` reads the key handle + property name + caller-owned byte slice
    // (alive on the stack); the kernel does not retain the pointer past the call.
    unsafe {
        NCryptSetProperty(
            NCRYPT_HANDLE(key.0),
            NCRYPT_UI_POLICY_PROPERTY,
            bytes,
            NCRYPT_FLAGS(0),
        )
    }
    .map_err(|e| fmt_win("NCryptSetProperty(UI_POLICY)", e))
}

fn set_rsa_length(key: NCRYPT_KEY_HANDLE) -> Result<(), Error> {
    let length: u32 = 2048;
    let bytes = length.to_le_bytes();
    // SAFETY: `NCryptSetProperty` reads the key handle + property name + caller-owned byte slice
    // (alive on the stack); the kernel does not retain the pointer past the call.
    unsafe {
        NCryptSetProperty(
            NCRYPT_HANDLE(key.0),
            NCRYPT_LENGTH_PROPERTY,
            &bytes,
            NCRYPT_FLAGS(0),
        )
    }
    .map_err(|e| fmt_win("NCryptSetProperty(LENGTH)", e))
}

fn export_blob(key: NCRYPT_KEY_HANDLE, blob_type: PCWSTR) -> Result<Vec<u8>, Error> {
    let mut required: u32 = 0;
    // SAFETY: `NCryptExportKey` reads the key handle + blob-type name (alive on the stack) and
    // writes into the caller-owned output buffer + length; called twice — once with null output to
    // query length, once with the sized buffer.
    unsafe {
        NCryptExportKey(
            key,
            None,
            blob_type,
            None,
            None,
            &mut required,
            NCRYPT_FLAGS(0),
        )
    }
    .map_err(|e| fmt_win("NCryptExportKey(probe)", e))?;
    let mut buf = vec![0u8; required as usize];
    let mut written: u32 = 0;
    // SAFETY: `NCryptExportKey` reads the key handle + blob-type name (alive on the stack) and
    // writes into the caller-owned output buffer + length; called twice — once with null output to
    // query length, once with the sized buffer.
    unsafe {
        NCryptExportKey(
            key,
            None,
            blob_type,
            None,
            Some(&mut buf),
            &mut written,
            NCRYPT_FLAGS(0),
        )
    }
    .map_err(|e| fmt_win("NCryptExportKey", e))?;
    buf.truncate(written as usize);
    Ok(buf)
}

/// Parse a CNG `BCRYPT_ECCKEY_BLOB` + its trailing X/Y bytes and
/// return the uncompressed `0x04 || X || Y` point. Caller hands the
/// bytes to `lfs_core::ssh::wire::encode_public_ecdsa_*` for the
/// SSH wire blob.
fn parse_ecdsa_uncompressed(blob: &[u8], algo: SshKeyAlgo) -> Result<Vec<u8>, Error> {
    let header_size = std::mem::size_of::<BCRYPT_ECCKEY_BLOB>();
    if blob.len() < header_size {
        return Err(Error::Backend(format!(
            "ecc blob too short: {} < {header_size}",
            blob.len()
        )));
    }
    let header_bytes = &blob[..header_size];
    let magic = u32::from_le_bytes([
        header_bytes[0],
        header_bytes[1],
        header_bytes[2],
        header_bytes[3],
    ]);
    let cb_key = u32::from_le_bytes([
        header_bytes[4],
        header_bytes[5],
        header_bytes[6],
        header_bytes[7],
    ]) as usize;
    let (expected_magic, expected_size) = match algo {
        SshKeyAlgo::EcdsaP256 => (BCRYPT_ECDSA_PUBLIC_P256_MAGIC, 32usize),
        SshKeyAlgo::EcdsaP384 => (BCRYPT_ECDSA_PUBLIC_P384_MAGIC, 48usize),
        SshKeyAlgo::Rsa2048 => unreachable!("RSA blob parsed elsewhere"),
    };
    if magic != expected_magic {
        return Err(Error::Backend(format!(
            "ecc blob magic mismatch: 0x{magic:08x} vs 0x{expected_magic:08x}"
        )));
    }
    if cb_key != expected_size {
        return Err(Error::Backend(format!(
            "ecc blob cbKey mismatch: {cb_key} vs {expected_size}"
        )));
    }
    let coords = &blob[header_size..];
    if coords.len() < 2 * expected_size {
        return Err(Error::Backend(format!(
            "ecc blob X+Y truncated: {} < {}",
            coords.len(),
            2 * expected_size
        )));
    }
    let mut uncompressed = Vec::with_capacity(1 + 2 * expected_size);
    uncompressed.push(0x04);
    uncompressed.extend_from_slice(&coords[..2 * expected_size]);
    Ok(uncompressed)
}

/// Parse a CNG `BCRYPT_RSAKEY_BLOB` + trailing `e || n` and return
/// `(exponent, modulus)` big-endian magnitudes. Caller hands them to
/// `lfs_core::ssh::wire::encode_public_rsa`.
fn parse_rsa_magnitudes(blob: &[u8]) -> Result<(Vec<u8>, Vec<u8>), Error> {
    let header_size = std::mem::size_of::<BCRYPT_RSAKEY_BLOB>();
    if blob.len() < header_size {
        return Err(Error::Backend(format!(
            "rsa blob too short: {} < {header_size}",
            blob.len()
        )));
    }
    // BCRYPT_RSAKEY_BLOB layout (little-endian):
    //   u32 Magic
    //   u32 BitLength
    //   u32 cbPublicExp
    //   u32 cbModulus
    //   u32 cbPrime1
    //   u32 cbPrime2
    let cb_public_exp = u32::from_le_bytes([blob[8], blob[9], blob[10], blob[11]]) as usize;
    let cb_modulus = u32::from_le_bytes([blob[12], blob[13], blob[14], blob[15]]) as usize;
    let body_start = header_size;
    if blob.len() < body_start + cb_public_exp + cb_modulus {
        return Err(Error::Backend("rsa blob body truncated".into()));
    }
    let exponent = blob[body_start..body_start + cb_public_exp].to_vec();
    let modulus =
        blob[body_start + cb_public_exp..body_start + cb_public_exp + cb_modulus].to_vec();
    Ok((exponent, modulus))
}

fn sign_hash_ecdsa(key: NCRYPT_KEY_HANDLE, hash: &[u8]) -> Result<Vec<u8>, Error> {
    let mut required: u32 = 0;
    // SAFETY: `NCryptSignHash` reads the key handle + padding info + caller-owned hash buffer
    // (alive on the stack) and writes into the caller-owned output buffer + length.
    unsafe { NCryptSignHash(key, None, hash, None, &mut required, NCRYPT_FLAGS(0)) }
        .map_err(map_sign_error)?;
    let mut buf = vec![0u8; required as usize];
    let mut written: u32 = 0;
    // SAFETY: `NCryptSignHash` reads the key handle + padding info + caller-owned hash buffer
    // (alive on the stack) and writes into the caller-owned output buffer + length.
    unsafe {
        NCryptSignHash(
            key,
            None,
            hash,
            Some(&mut buf),
            &mut written,
            NCRYPT_FLAGS(0),
        )
    }
    .map_err(map_sign_error)?;
    buf.truncate(written as usize);
    Ok(buf)
}

fn sign_hash_rsa_pkcs1(
    key: NCRYPT_KEY_HANDLE,
    hash: &[u8],
    pad_alg: PCWSTR,
) -> Result<Vec<u8>, Error> {
    let padding_info = BCRYPT_PKCS1_PADDING_INFO { pszAlgId: pad_alg };
    let padding_ptr = (&padding_info as *const BCRYPT_PKCS1_PADDING_INFO) as *const c_void;
    let mut required: u32 = 0;
    // SAFETY: `NCryptSignHash` reads the key handle + padding info + caller-owned hash buffer
    // (alive on the stack) and writes into the caller-owned output buffer + length.
    unsafe {
        NCryptSignHash(
            key,
            Some(padding_ptr),
            hash,
            None,
            &mut required,
            NCRYPT_FLAGS(BCRYPT_PAD_PKCS1.0),
        )
    }
    .map_err(map_sign_error)?;
    let mut buf = vec![0u8; required as usize];
    let mut written: u32 = 0;
    // SAFETY: `NCryptSignHash` reads the key handle + padding info + caller-owned hash buffer
    // (alive on the stack) and writes into the caller-owned output buffer + length.
    unsafe {
        NCryptSignHash(
            key,
            Some(padding_ptr),
            hash,
            Some(&mut buf),
            &mut written,
            NCRYPT_FLAGS(BCRYPT_PAD_PKCS1.0),
        )
    }
    .map_err(map_sign_error)?;
    buf.truncate(written as usize);
    Ok(buf)
}

fn map_sign_error(e: WinError) -> Error {
    let code = win_error_code(&e);
    if code == win_error_code(&WinError::from(NTE_USER_CANCELLED)) {
        Error::Cancelled
    } else {
        fmt_win("NCryptSignHash", e)
    }
}

fn map_finalize_error(e: &WinError) -> UnavailableReason {
    let code = win_error_code(e);
    // `NTE_USER_CANCELLED` on finalize means the user dismissed the
    // Hello "configure now" prompt — treat as not-configured so the
    // wizard routes at the right remediation. Other codes surface
    // as generic backend errors.
    if code == win_error_code(&WinError::from(NTE_USER_CANCELLED)) {
        UnavailableReason::HelloNotConfigured
    } else {
        UnavailableReason::Other(format!("NCryptFinalizeKey: 0x{code:08x}"))
    }
}

fn is_unsupported_alg(e: &WinError) -> bool {
    // `NTE_NOT_SUPPORTED = 0x80090029` — TPM firmware refused the
    // algorithm. Triggers the P-384 → P-256 fallback on older
    // Infineon firmware that caps at P-256.
    win_error_code(e) == 0x8009_0029
}

fn read_impl_tier(key: NCRYPT_KEY_HANDLE) -> TpmTier {
    let mut required: u32 = 0;
    // SAFETY: `PCWSTR` wraps a pointer into a UTF-16 buffer alive on the stack for the duration of
    // the Win32 call; the kernel does not retain the pointer past return.
    let result = unsafe {
        NCryptGetProperty(
            NCRYPT_HANDLE(key.0),
            PCWSTR(NCRYPT_IMPL_TYPE_PROPERTY_WSTR.as_ptr()),
            None,
            &mut required,
            windows::Win32::Security::OBJECT_SECURITY_INFORMATION(0),
        )
    };
    if result.is_err() || (required as usize) < 4 {
        return TpmTier::SoftwareKsp;
    }
    let mut buf = vec![0u8; required as usize];
    let mut written: u32 = 0;
    // SAFETY: `PCWSTR` wraps a pointer into a UTF-16 buffer alive on the stack for the duration of
    // the Win32 call; the kernel does not retain the pointer past return.
    let read = unsafe {
        NCryptGetProperty(
            NCRYPT_HANDLE(key.0),
            PCWSTR(NCRYPT_IMPL_TYPE_PROPERTY_WSTR.as_ptr()),
            Some(&mut buf),
            &mut written,
            windows::Win32::Security::OBJECT_SECURITY_INFORMATION(0),
        )
    };
    if read.is_err() || (written as usize) < 4 {
        return TpmTier::SoftwareKsp;
    }
    let flags = u32::from_le_bytes([buf[0], buf[1], buf[2], buf[3]]);
    if flags & NCRYPT_IMPL_HARDWARE_FLAG != 0 {
        TpmTier::Hardware
    } else {
        TpmTier::SoftwareKsp
    }
}

fn algo_from_alg_name(name: &str) -> Option<SshKeyAlgo> {
    match name {
        "ECDSA_P256" => Some(SshKeyAlgo::EcdsaP256),
        "ECDSA_P384" => Some(SshKeyAlgo::EcdsaP384),
        "RSA" => Some(SshKeyAlgo::Rsa2048),
        _ => None,
    }
}

fn mint_credential_name() -> String {
    use rand::RngCore;
    let mut bytes = [0u8; 8];
    rand::rngs::OsRng.fill_bytes(&mut bytes);
    let suffix: String = bytes.iter().map(|b| format!("{b:02x}")).collect();
    // User-prefix protects shared-workstation installs from name
    // collisions across user profiles. The hash is `username -> SHA-256
    // -> first 8 hex` so the same workstation user always gets the
    // same prefix segment.
    let user_hash = user_hash_prefix();
    format!("{CNG_NAME_PREFIX}{user_hash}-{suffix}")
}

fn mint_probe_name() -> String {
    use rand::RngCore;
    let mut bytes = [0u8; 8];
    rand::rngs::OsRng.fill_bytes(&mut bytes);
    let suffix: String = bytes.iter().map(|b| format!("{b:02x}")).collect();
    format!("letsflutssh-probe-{suffix}")
}

fn user_hash_prefix() -> String {
    use sha2::{Digest, Sha256};
    let user = std::env::var("USERNAME").unwrap_or_else(|_| "default".into());
    let mut hasher = Sha256::new();
    hasher.update(user.as_bytes());
    let digest = hasher.finalize();
    let mut hex = String::with_capacity(8);
    for b in digest.iter().take(4) {
        use std::fmt::Write as _;
        let _ = write!(hex, "{b:02x}");
    }
    hex
}

fn to_wide_z(s: &str) -> Vec<u16> {
    let mut out: Vec<u16> = s.encode_utf16().collect();
    out.push(0);
    out
}

unsafe fn pwstr_to_string(ptr: PWSTR) -> String {
    if ptr.0.is_null() {
        return String::new();
    }
    let mut len = 0usize;
    // SAFETY: walking a NUL-terminated UTF-16 buffer the OS handed us; the kernel guarantees a NUL
    // at or before any documented max length so the loop terminates on a valid byte read.
    while unsafe { *ptr.0.add(len) } != 0 {
        len += 1;
    }
    // SAFETY: `slice::from_raw_parts` constructs a slice from a pointer + length; the pointer is
    // owned by the calling FFI and valid for the slice length for the borrow's duration.
    let slice = unsafe { std::slice::from_raw_parts(ptr.0, len) };
    String::from_utf16_lossy(slice)
}

fn sha256(data: &[u8]) -> Vec<u8> {
    use sha2::{Digest, Sha256};
    let mut hasher = Sha256::new();
    hasher.update(data);
    hasher.finalize().to_vec()
}

fn sha384(data: &[u8]) -> Vec<u8> {
    use sha2::{Digest, Sha384};
    let mut hasher = Sha384::new();
    hasher.update(data);
    hasher.finalize().to_vec()
}

fn sha512(data: &[u8]) -> Vec<u8> {
    use sha2::{Digest, Sha512};
    let mut hasher = Sha512::new();
    hasher.update(data);
    hasher.finalize().to_vec()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn algo_round_trips_through_key_type_tag() {
        for algo in [
            SshKeyAlgo::EcdsaP256,
            SshKeyAlgo::EcdsaP384,
            SshKeyAlgo::Rsa2048,
        ] {
            let tag = algo.key_type_tag();
            let recovered = SshKeyAlgo::from_key_type(tag).expect("round trip");
            assert_eq!(recovered, algo);
        }
    }

    #[test]
    fn key_type_recovery_rejects_unknown() {
        let err = SshKeyAlgo::from_key_type("ed25519").unwrap_err();
        assert!(matches!(err, Error::Backend(_)));
    }

    #[test]
    fn credential_name_carries_prefix() {
        let a = mint_credential_name();
        let b = mint_credential_name();
        assert!(a.starts_with(CNG_NAME_PREFIX));
        assert!(b.starts_with(CNG_NAME_PREFIX));
        // 16-char user prefix differs only across users; suffix
        // randomness guarantees uniqueness.
        assert_ne!(a, b);
    }

    #[test]
    fn algo_from_alg_name_matches_ncrypt_strings() {
        assert_eq!(
            algo_from_alg_name("ECDSA_P256"),
            Some(SshKeyAlgo::EcdsaP256)
        );
        assert_eq!(
            algo_from_alg_name("ECDSA_P384"),
            Some(SshKeyAlgo::EcdsaP384)
        );
        assert_eq!(algo_from_alg_name("RSA"), Some(SshKeyAlgo::Rsa2048));
        assert_eq!(algo_from_alg_name("nope"), None);
    }

    #[test]
    fn unavailable_reason_renders_human_text() {
        assert!(UnavailableReason::HelloNotConfigured
            .to_string()
            .contains("Hello"));
        assert!(UnavailableReason::ProviderUnavailable("oops".into())
            .to_string()
            .contains("Microsoft Platform"));
    }

    #[test]
    fn rsa_blob_parser_returns_exponent_and_modulus_magnitudes() {
        let mut blob = Vec::new();
        blob.extend_from_slice(&826_364_754u32.to_le_bytes()); // BCRYPT_RSAPUBLIC_MAGIC
        blob.extend_from_slice(&2048u32.to_le_bytes()); // BitLength
        blob.extend_from_slice(&3u32.to_le_bytes()); // cbPublicExp
        blob.extend_from_slice(&2u32.to_le_bytes()); // cbModulus
        blob.extend_from_slice(&0u32.to_le_bytes()); // cbPrime1
        blob.extend_from_slice(&0u32.to_le_bytes()); // cbPrime2
        blob.extend_from_slice(&[0x01, 0x00, 0x01]); // exponent (65537 BE)
        blob.extend_from_slice(&[0xC1, 0x23]); // modulus (high bit set)
        let (exponent, modulus) = parse_rsa_magnitudes(&blob).unwrap();
        assert_eq!(exponent, vec![0x01, 0x00, 0x01]);
        assert_eq!(modulus, vec![0xC1, 0x23]);
    }

    #[test]
    fn rsa_blob_parser_rejects_truncated_body() {
        let mut blob = Vec::new();
        blob.extend_from_slice(&826_364_754u32.to_le_bytes());
        blob.extend_from_slice(&2048u32.to_le_bytes());
        blob.extend_from_slice(&3u32.to_le_bytes());
        blob.extend_from_slice(&2u32.to_le_bytes());
        blob.extend_from_slice(&0u32.to_le_bytes());
        blob.extend_from_slice(&0u32.to_le_bytes());
        // No body bytes — exponent/modulus missing.
        let err = parse_rsa_magnitudes(&blob).unwrap_err();
        assert!(matches!(err, Error::Backend(_)));
    }

    #[test]
    fn ecdsa_blob_parser_returns_uncompressed_point_p256() {
        let mut blob = Vec::new();
        blob.extend_from_slice(&BCRYPT_ECDSA_PUBLIC_P256_MAGIC.to_le_bytes());
        blob.extend_from_slice(&32u32.to_le_bytes()); // cbKey
        blob.extend(std::iter::repeat_n(0xAA, 32)); // X
        blob.extend(std::iter::repeat_n(0xBB, 32)); // Y
        let out = parse_ecdsa_uncompressed(&blob, SshKeyAlgo::EcdsaP256).unwrap();
        assert_eq!(out.len(), 65);
        assert_eq!(out[0], 0x04);
        assert!(out[1..33].iter().all(|&b| b == 0xAA));
        assert!(out[33..65].iter().all(|&b| b == 0xBB));
    }

    #[test]
    fn ecdsa_blob_parser_rejects_magic_mismatch() {
        let mut blob = Vec::new();
        blob.extend_from_slice(&0xDEAD_BEEFu32.to_le_bytes());
        blob.extend_from_slice(&32u32.to_le_bytes());
        blob.extend(vec![0u8; 64]);
        let err = parse_ecdsa_uncompressed(&blob, SshKeyAlgo::EcdsaP256).unwrap_err();
        assert!(matches!(err, Error::Backend(_)));
    }

    #[test]
    #[ignore]
    fn probe_round_trip_completes() {
        // Hardware probe — runs only on a Windows host with PCP +
        // Hello configured. Self-hosted runners pass `--ignored`.
        let _ = probe_availability();
    }
}
