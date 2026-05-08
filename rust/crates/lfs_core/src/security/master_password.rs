//! Master-password verifier + key derivation, file-format owner.
//!
//! Manages the on-disk `credentials.kdf` (Argon2id params + salt)
//! and `credentials.verify` (AES-GCM-encrypted known plaintext) pair
//! that backs the optional master-password tier. Plaintext password
//! bytes only ever live on the caller's stack for the duration of the
//! KDF call; the derived 32-byte key is the only artifact that
//! survives.
//!
//! # File format
//!
//! `credentials.kdf` (v1):
//! ```text
//!   offset 0   magic 'LFKD'          (4)
//!   offset 4   file version 0x01     (1)
//!   offset 5   KDF algorithm id      (1)  // 0x01 = Argon2id
//!   offset 6   KDF params            (10 for Argon2id)
//!   offset N   salt                  (32)
//! ```
//!
//! Verifier: `[12-byte AES-GCM nonce][ciphertext + 16-byte tag]` over
//! a fixed plaintext (`LetsFLUTssh-verify`). Decrypt-and-match returns
//! `Some(key)` on success, `None` on mismatch.
//!
//! # Why a separate file
//!
//! `credentials.kdf` carries cost params + salt; rewriting it on a
//! KDF-profile bump is an atomic rename. `credentials.verify` is the
//! oracle the unlock dialog needs to detect "wrong password" without
//! decrypting the entire SQLCipher store. Separating them means a
//! profile bump that re-derives the key only re-writes one file.

use std::fs;
use std::path::Path;

use rand::rngs::OsRng;
use rand::RngCore;
use zeroize::Zeroizing;

use crate::crypto;
use crate::error::Error;

/// File names under the platform's app-support directory. Mirror of
/// the Dart-side constants in `master_password.dart`.
pub const KDF_FILE_NAME: &str = "credentials.kdf";
pub const VERIFIER_FILE_NAME: &str = "credentials.verify";
pub const KEY_FILE_NAME: &str = "credentials.key";

const FILE_MAGIC: [u8; 4] = [0x4C, 0x46, 0x4B, 0x44]; // 'LFKD'
const FILE_VERSION: u8 = 0x01;
const HEADER_BASE_LEN: usize = 6; // magic(4) + version(1) + algoId(1)
const SALT_LENGTH: usize = 32;
const KEY_LENGTH: usize = 32;
const IV_LENGTH: usize = 12;

/// Known plaintext encrypted in `credentials.verify`. Decrypting and
/// comparing against this constant detects wrong passwords without
/// touching the encrypted SQLCipher store.
const VERIFIER_PLAINTEXT: &[u8] = b"LetsFLUTssh-verify";

const ARGON2ID_ALGO_ID: u8 = 0x01;
// OWASP-2024 floor is m=46MiB / t=2 / p=1; raised here to m=64MiB / t=3
// for desktop/mobile UX where the unlock dialog can absorb the extra
// derive cost. Existing installs keep their stored params (forward-
// compatible bumps); next change-password re-derives at the new floor.
const DEFAULT_MEMORY_KIB: u32 = 64 * 1024;
const DEFAULT_ITERATIONS: u32 = 3;
const DEFAULT_PARALLELISM: u8 = 1;

const ARGON2ID_MAX_MEMORY_KIB: u32 = 1024 * 1024;
const ARGON2ID_MAX_ITERATIONS: u32 = 16;
const ARGON2ID_MAX_PARALLELISM: u8 = 8;

/// Argon2id KDF profile. Mirror of `KdfParams` in Dart.
#[derive(Debug, Clone, Copy)]
pub struct KdfParams {
    pub memory_kib: u32,
    pub iterations: u32,
    pub parallelism: u8,
}

impl KdfParams {
    /// Defense-in-depth floor: 64 MiB / 3 iters / 1 lane (one tier
    /// above the OWASP-2024 minimum). Bumps are forward-compatible —
    /// old files keep their stored params, next change-password
    /// re-derives at the current default.
    pub fn defaults() -> Self {
        Self {
            memory_kib: DEFAULT_MEMORY_KIB,
            iterations: DEFAULT_ITERATIONS,
            parallelism: DEFAULT_PARALLELISM,
        }
    }

    /// Encode algo id + params to the 10-byte block stored after the
    /// header magic + version. Salt is appended separately by the
    /// caller (so a future profile bump that re-uses the salt can
    /// rewrite only this block).
    pub fn encode(&self) -> [u8; 10] {
        let mut out = [0u8; 10];
        out[0] = ARGON2ID_ALGO_ID;
        out[1..5].copy_from_slice(&self.memory_kib.to_be_bytes());
        out[5..9].copy_from_slice(&self.iterations.to_be_bytes());
        out[9] = self.parallelism;
        out
    }

    pub fn encoded_length(&self) -> usize {
        10
    }

    /// Decode params from a 10-byte slice. Rejects unknown algo ids,
    /// truncated buffers, and values outside the sanity ceilings — a
    /// crafted header asking for 4 GiB / a million iters would wedge
    /// unlock rather than fail cleanly.
    pub fn decode(bytes: &[u8]) -> Result<Self, String> {
        if bytes.is_empty() {
            return Err("KdfParams: empty input".into());
        }
        if bytes[0] != ARGON2ID_ALGO_ID {
            return Err(format!(
                "KdfParams: unknown algorithm id 0x{:02x}",
                bytes[0]
            ));
        }
        if bytes.len() < 10 {
            return Err("KdfParams: truncated Argon2id params".into());
        }
        let memory_kib = u32::from_be_bytes(bytes[1..5].try_into().unwrap());
        let iterations = u32::from_be_bytes(bytes[5..9].try_into().unwrap());
        let parallelism = bytes[9];
        if memory_kib == 0 || iterations == 0 || parallelism == 0 {
            return Err("KdfParams: Argon2id params must be > 0".into());
        }
        if memory_kib > ARGON2ID_MAX_MEMORY_KIB {
            return Err(format!(
                "KdfParams: Argon2id memory {memory_kib} KiB exceeds sanity cap {ARGON2ID_MAX_MEMORY_KIB} KiB"
            ));
        }
        if iterations > ARGON2ID_MAX_ITERATIONS {
            return Err(format!(
                "KdfParams: Argon2id iterations {iterations} exceeds sanity cap {ARGON2ID_MAX_ITERATIONS}"
            ));
        }
        if parallelism > ARGON2ID_MAX_PARALLELISM {
            return Err(format!(
                "KdfParams: Argon2id parallelism {parallelism} exceeds sanity cap {ARGON2ID_MAX_PARALLELISM}"
            ));
        }
        Ok(Self {
            memory_kib,
            iterations,
            parallelism,
        })
    }
}

#[derive(Debug, Clone)]
pub struct KdfRecord {
    pub params: KdfParams,
    pub salt: [u8; SALT_LENGTH],
}

fn encode_kdf_record(params: &KdfParams, salt: &[u8; SALT_LENGTH]) -> Vec<u8> {
    let pb = params.encode();
    let mut out = Vec::with_capacity(HEADER_BASE_LEN + pb.len() + SALT_LENGTH);
    out.extend_from_slice(&FILE_MAGIC);
    out.push(FILE_VERSION);
    // params[0] is the algo id — header echoes it so a reader can skip
    // ahead without fully parsing the block.
    out.push(pb[0]);
    out.extend_from_slice(&pb);
    out.extend_from_slice(salt);
    out
}

/// Decode the on-disk `credentials.kdf` record. Surface for tests +
/// the migration path; internal callers go through [`read_kdf_record`].
pub fn decode_kdf_record(bytes: &[u8]) -> Result<KdfRecord, String> {
    if bytes.len() < HEADER_BASE_LEN + 1 + SALT_LENGTH {
        return Err("credentials.kdf: truncated header".into());
    }
    if bytes[..FILE_MAGIC.len()] != FILE_MAGIC {
        return Err("credentials.kdf: bad magic".into());
    }
    let version = bytes[FILE_MAGIC.len()];
    if version != FILE_VERSION {
        return Err(format!(
            "credentials.kdf: unsupported version 0x{:02x}",
            version
        ));
    }
    let params_start = HEADER_BASE_LEN;
    let params = KdfParams::decode(&bytes[params_start..])?;
    let salt_start = params_start + params.encoded_length();
    if bytes.len() < salt_start + SALT_LENGTH {
        return Err("credentials.kdf: truncated salt".into());
    }
    let mut salt = [0u8; SALT_LENGTH];
    salt.copy_from_slice(&bytes[salt_start..salt_start + SALT_LENGTH]);
    Ok(KdfRecord { params, salt })
}

/// Pinned `getApplicationSupportDirectory()` path. Set once at
/// startup via [`pin_support_dir`] so per-tier orchestrators +
/// FRB shims share one canonical lookup; subsequent pins are
/// no-ops. Tests construct paths inline and don't pin.
static SUPPORT_DIR: std::sync::OnceLock<std::path::PathBuf> = std::sync::OnceLock::new();

/// Pin the support directory. Production calls this once after
/// the Dart `path_provider` plugin resolves the path. Returns
/// the canonical path the actor adopted (the first pin wins;
/// later calls are no-ops + return the existing pin).
pub fn pin_support_dir(support_dir: std::path::PathBuf) -> std::path::PathBuf {
    SUPPORT_DIR.get_or_init(|| support_dir.clone()).clone()
}

/// Read the pinned support dir. Panics in the unreachable
/// "no pin was set" case — production callers fire
/// [`pin_support_dir`] at startup before any other op
/// routes through the singleton.
///
/// FRB-callable paths MUST use [`try_pinned_support_dir`]
/// instead so a single ordering misorder surfaces as a typed
/// error rather than panicking across the FRB worker. This
/// `pinned_support_dir` overload stays for internal Rust call
/// sites already gated by their own ordering invariants.
pub fn pinned_support_dir() -> &'static Path {
    SUPPORT_DIR.get().expect(
        "pin_support_dir must be called before any master_password op routes through the singleton",
    )
}

/// FRB-safe variant of [`pinned_support_dir`]: returns a typed
/// error instead of panicking when no pin is set. Used by FRB
/// shims so a misordered call lands as `Error::Platform`, not
/// a worker-thread abort.
pub fn try_pinned_support_dir() -> Result<&'static Path, Error> {
    SUPPORT_DIR.get().map(|p| p.as_path()).ok_or_else(|| {
        Error::Platform(
            "support_dir not pinned: pin_support_dir must be called at startup".to_string(),
        )
    })
}

/// True when `credentials.kdf` exists under [`support_dir`] —
/// the master-password tier is enabled.
pub fn is_enabled(support_dir: &Path) -> bool {
    support_dir.join(KDF_FILE_NAME).exists()
}

/// Generate fresh salt + derive a key under [`params`], persist the
/// KDF record + verifier files atomically, and return the derived
/// key. The caller re-encrypts SessionStore / KeyStore /
/// KnownHostsManager with this key.
pub fn enable(
    support_dir: &Path,
    password: &[u8],
    params: &KdfParams,
) -> Result<Zeroizing<Vec<u8>>, String> {
    let mut salt = [0u8; SALT_LENGTH];
    OsRng.fill_bytes(&mut salt);
    let key = derive_key(password, &salt, params)?;
    let kdf_bytes = encode_kdf_record(params, &salt);
    let verifier = encrypt_verifier(&key, &kdf_bytes)?;
    write_atomic(&support_dir.join(KDF_FILE_NAME), &kdf_bytes)?;
    write_atomic(&support_dir.join(VERIFIER_FILE_NAME), &verifier)?;
    Ok(key)
}

/// Verify the old password, then re-key under [`new_password`] using
/// [`params`] (typically the current production defaults). Atomically
/// replaces both files. Returns the new derived key.
pub fn change_password(
    support_dir: &Path,
    old_password: &[u8],
    new_password: &[u8],
    params: &KdfParams,
) -> Result<Zeroizing<Vec<u8>>, String> {
    if verify_and_derive(support_dir, old_password)?.is_none() {
        return Err("Current password is incorrect".into());
    }
    enable(support_dir, new_password, params)
}

/// Drop the KDF + verifier files. Caller is responsible for
/// re-encrypting stores with a fresh random key + writing
/// `credentials.key`.
pub fn disable(support_dir: &Path) -> Result<(), String> {
    for name in [KDF_FILE_NAME, VERIFIER_FILE_NAME] {
        let path = support_dir.join(name);
        if path.exists() {
            fs::remove_file(&path).map_err(|e| format!("delete {name}: {e}"))?;
        }
    }
    Ok(())
}

/// Drop everything: KDF + verifier + key file. Destructive — used
/// only by the forgotten-password flow once the user confirms the
/// data loss.
pub fn reset(support_dir: &Path) -> Result<(), String> {
    for name in [KDF_FILE_NAME, VERIFIER_FILE_NAME, KEY_FILE_NAME] {
        let path = support_dir.join(name);
        if path.exists() {
            fs::remove_file(&path).map_err(|e| format!("delete {name}: {e}"))?;
        }
    }
    Ok(())
}

/// Run the KDF against the on-disk salt + params and return the
/// derived key without checking the verifier. Used when the caller
/// needs a key to encrypt new data and already trusts the password.
pub fn derive_key_from_disk(
    support_dir: &Path,
    password: &[u8],
) -> Result<Zeroizing<Vec<u8>>, String> {
    let record = read_kdf_record(support_dir)?;
    derive_key(password, &record.salt, &record.params)
}

/// Single-KDF unlock: derive the key, decrypt-and-match the verifier,
/// return `Some(key)` on success or `Ok(None)` on a wrong password.
/// `Err` is reserved for "the tier is not enabled" / "files are
/// corrupt". One Argon2id pass instead of two — the legacy Dart path
/// ran KDF inside both `verify` and `deriveKey`.
pub fn verify_and_derive(
    support_dir: &Path,
    password: &[u8],
) -> Result<Option<Zeroizing<Vec<u8>>>, String> {
    let record = read_kdf_record(support_dir)?;
    let verifier_path = support_dir.join(VERIFIER_FILE_NAME);
    if !verifier_path.exists() {
        return Err("Master password is not enabled".into());
    }
    let verifier = crate::path::read_bytes_secure(&verifier_path)
        .map_err(|e| format!("read {VERIFIER_FILE_NAME}: {e}"))?;
    let key = derive_key(password, &record.salt, &record.params)?;
    // Bind the kdf header (magic + version + algo id + params +
    // salt) into the AES-GCM AAD so a tampered credentials.kdf
    // header (memory_kib bumped to 1 GiB to DoS-lock the user)
    // fails verification instead of silently driving Argon2id
    // through the attacker-supplied params. Old verifiers (no
    // AAD) still verify because legacy_verify_against_verifier
    // is tried as a one-shot fallback when the AAD-bound match
    // fails — next change-password re-emits with the AAD-bound
    // shape.
    let kdf_header = encode_kdf_record(&record.params, &record.salt);
    let ok = verify_against_verifier(&key, &verifier, &kdf_header);
    Ok(if ok { Some(key) } else { None })
}

fn read_kdf_record(support_dir: &Path) -> Result<KdfRecord, String> {
    let path = support_dir.join(KDF_FILE_NAME);
    if !path.exists() {
        return Err("Master password is not enabled".into());
    }
    let bytes =
        crate::path::read_bytes_secure(&path).map_err(|e| format!("read {KDF_FILE_NAME}: {e}"))?;
    decode_kdf_record(&bytes)
}

fn derive_key(
    password: &[u8],
    salt: &[u8],
    params: &KdfParams,
) -> Result<Zeroizing<Vec<u8>>, String> {
    crypto::argon2id_derive(
        password,
        salt,
        params.memory_kib,
        params.iterations,
        params.parallelism as u32,
        KEY_LENGTH as u32,
    )
    .map_err(|e| format!("argon2id: {e}"))
}

fn encrypt_verifier(key: &[u8], kdf_header: &[u8]) -> Result<Vec<u8>, String> {
    use rand::RngCore;
    let mut nonce = [0u8; IV_LENGTH];
    rand::rngs::OsRng.fill_bytes(&mut nonce);
    let body = crypto::aes_gcm_encrypt_raw(key, &nonce, VERIFIER_PLAINTEXT, kdf_header)
        .map_err(|e| format!("aes-gcm encrypt-raw: {e}"))?;
    let mut out = Vec::with_capacity(IV_LENGTH + body.len());
    out.extend_from_slice(&nonce);
    out.extend_from_slice(&body);
    Ok(out)
}

fn verify_against_verifier(key: &[u8], verifier: &[u8], kdf_header: &[u8]) -> bool {
    if verifier.len() < IV_LENGTH + 1 {
        return false;
    }
    // Try the AAD-bound shape first (current emit). Fall back
    // to the legacy AAD-less envelope so installs whose
    // credentials.verify pre-dates this change still verify;
    // the next change-password re-emits under the AAD-bound
    // shape.
    let nonce = &verifier[..IV_LENGTH];
    let body = &verifier[IV_LENGTH..];
    if let Ok(pt) = crypto::aes_gcm_decrypt_raw(key, nonce, body, kdf_header) {
        return crypto::constant_time_eq(&pt, VERIFIER_PLAINTEXT);
    }
    match crypto::aes_gcm_decrypt(key, verifier) {
        Ok(pt) => crypto::constant_time_eq(&pt, VERIFIER_PLAINTEXT),
        Err(_) => false,
    }
}

fn write_atomic(path: &Path, bytes: &[u8]) -> Result<(), String> {
    // Canonical write-tmp + harden + rename lives in
    // `crate::path::write_bytes_atomic` so every secret-bearing
    // artefact under app-support shares one on-disk perms contract.
    crate::path::write_bytes_atomic(path, bytes)
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    fn fast_params() -> KdfParams {
        // Argon2id minimums per the crate's `Params::new` constraints
        // — memory floor is 8 KiB. Keeps unit tests under a second
        // each instead of the production 400ms+ profile.
        KdfParams {
            memory_kib: 8,
            iterations: 1,
            parallelism: 1,
        }
    }

    #[test]
    fn encode_decode_kdf_record_round_trip() {
        let params = KdfParams::defaults();
        let salt = [7u8; SALT_LENGTH];
        let bytes = encode_kdf_record(&params, &salt);
        let decoded = decode_kdf_record(&bytes).unwrap();
        assert_eq!(decoded.params.memory_kib, params.memory_kib);
        assert_eq!(decoded.params.iterations, params.iterations);
        assert_eq!(decoded.params.parallelism, params.parallelism);
        assert_eq!(decoded.salt, salt);
    }

    #[test]
    fn decode_rejects_bad_magic() {
        let mut bytes = encode_kdf_record(&KdfParams::defaults(), &[1u8; SALT_LENGTH]);
        bytes[0] = 0x00;
        let err = decode_kdf_record(&bytes).unwrap_err();
        assert!(err.contains("bad magic"));
    }

    #[test]
    fn decode_rejects_unknown_version() {
        let mut bytes = encode_kdf_record(&KdfParams::defaults(), &[1u8; SALT_LENGTH]);
        bytes[FILE_MAGIC.len()] = 0xFF;
        let err = decode_kdf_record(&bytes).unwrap_err();
        assert!(err.contains("unsupported version"));
    }

    #[test]
    fn decode_rejects_oversize_memory() {
        let bad = KdfParams {
            memory_kib: ARGON2ID_MAX_MEMORY_KIB + 1,
            iterations: 2,
            parallelism: 1,
        };
        let bytes = encode_kdf_record(&bad, &[0u8; SALT_LENGTH]);
        let err = decode_kdf_record(&bytes).unwrap_err();
        assert!(err.contains("memory"));
    }

    #[test]
    fn enable_persists_and_verify_round_trips() {
        let dir = TempDir::new().unwrap();
        let params = fast_params();
        let key = enable(dir.path(), b"secret", &params).unwrap();
        assert!(is_enabled(dir.path()));
        let got = verify_and_derive(dir.path(), b"secret").unwrap().unwrap();
        assert_eq!(got, key);
    }

    #[test]
    fn verify_returns_none_on_wrong_password() {
        let dir = TempDir::new().unwrap();
        enable(dir.path(), b"right", &fast_params()).unwrap();
        let got = verify_and_derive(dir.path(), b"wrong").unwrap();
        assert!(got.is_none());
    }

    #[test]
    fn change_password_rotates_and_old_stops_working() {
        let dir = TempDir::new().unwrap();
        let params = fast_params();
        enable(dir.path(), b"v1", &params).unwrap();
        let new_key = change_password(dir.path(), b"v1", b"v2", &params).unwrap();
        assert!(verify_and_derive(dir.path(), b"v1").unwrap().is_none());
        let again = verify_and_derive(dir.path(), b"v2").unwrap().unwrap();
        assert_eq!(again, new_key);
    }

    #[test]
    fn change_password_rejects_wrong_old() {
        let dir = TempDir::new().unwrap();
        enable(dir.path(), b"right", &fast_params()).unwrap();
        let err = change_password(dir.path(), b"wrong", b"new", &fast_params()).unwrap_err();
        assert!(err.contains("incorrect"));
    }

    #[test]
    fn disable_drops_kdf_and_verifier_only() {
        let dir = TempDir::new().unwrap();
        enable(dir.path(), b"x", &fast_params()).unwrap();
        std::fs::write(dir.path().join(KEY_FILE_NAME), b"keep").unwrap();
        disable(dir.path()).unwrap();
        assert!(!dir.path().join(KDF_FILE_NAME).exists());
        assert!(!dir.path().join(VERIFIER_FILE_NAME).exists());
        assert!(dir.path().join(KEY_FILE_NAME).exists());
    }

    #[test]
    fn reset_drops_everything() {
        let dir = TempDir::new().unwrap();
        enable(dir.path(), b"x", &fast_params()).unwrap();
        std::fs::write(dir.path().join(KEY_FILE_NAME), b"to-go").unwrap();
        reset(dir.path()).unwrap();
        assert!(!dir.path().join(KDF_FILE_NAME).exists());
        assert!(!dir.path().join(VERIFIER_FILE_NAME).exists());
        assert!(!dir.path().join(KEY_FILE_NAME).exists());
    }

    #[test]
    fn verify_and_derive_errors_when_disabled() {
        let dir = TempDir::new().unwrap();
        let err = verify_and_derive(dir.path(), b"anything").unwrap_err();
        assert!(err.contains("not enabled"));
    }

    #[test]
    fn derive_key_from_disk_matches_verify() {
        let dir = TempDir::new().unwrap();
        let params = fast_params();
        let key = enable(dir.path(), b"p", &params).unwrap();
        let again = derive_key_from_disk(dir.path(), b"p").unwrap();
        assert_eq!(again, key);
    }

    #[cfg(unix)]
    #[test]
    fn enable_writes_files_with_owner_only_perms() {
        // The Dart `writeBytesAtomic` always called `hardenFilePerms`
        // on the temp file before rename — without the matching
        // chmod 0600 in the Rust write_atomic, the credentials.kdf
        // and credentials.verify files would land at the default
        // umask (typically 0644, world-readable). That would be a
        // security regression for installs migrated from the Dart
        // writer. Confirm the Rust write keeps 0600 parity.
        use std::os::unix::fs::PermissionsExt;
        let dir = TempDir::new().unwrap();
        enable(dir.path(), b"x", &fast_params()).unwrap();
        for name in [KDF_FILE_NAME, VERIFIER_FILE_NAME] {
            let p = dir.path().join(name);
            let mode = std::fs::metadata(&p).unwrap().permissions().mode() & 0o777;
            assert_eq!(mode, 0o600, "{name} did not land at 0600 (got {mode:o})");
        }
    }
}
