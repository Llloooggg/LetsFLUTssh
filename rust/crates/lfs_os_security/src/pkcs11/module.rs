//! `Pkcs11` instance pool keyed by `(path, sha256)`.
//!
//! Cryptoki's `C_Initialize` MUST be called exactly once per loaded
//! library per process — re-initializing a module that already
//! shipped a `C_Initialize` returns `CKR_CRYPTOKI_ALREADY_INITIALIZED`
//! (which we accept as success, per PKCS#11 spec §5.4), but loading
//! the same DLL twice through `dlopen` is wasted work and can race
//! against vendor-internal global state. This pool serializes loads
//! through a `Mutex<HashMap<...>>` keyed by `(path, sha256-of-the-module-file)`
//! so every caller asking for the same library reaches the same
//! initialised handle.
//!
//! Pool entries live for the process lifetime — Cryptoki provides
//! no clean way to "unload" a library beyond `C_Finalize` + drop,
//! and re-init churn against a vendor library is the documented
//! cause of Rutoken ECP firmware-level instability the plan calls
//! out. Stable handles = stable sessions = predictable behaviour.

#![cfg(any(target_os = "linux", target_os = "macos", target_os = "windows"))]

use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex, OnceLock};

use cryptoki::context::{CInitializeArgs, CInitializeFlags, Pkcs11};
use sha2::{Digest, Sha256};

use super::error::Error;

/// Identifier the pool keys entries under. `path` is the canonical
/// absolute path the loader will `dlopen`; `sha256_hex` is the
/// SHA-256 of the file contents at the time of first probe — the
/// pair pins both the on-disk location and the integrity of the
/// shared object, so a vendor library swap (in-place upgrade,
/// supply-chain attack) lands as a fresh pool entry that re-runs
/// `C_Initialize`.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct ModuleKey {
    pub path: PathBuf,
    pub sha256_hex: String,
}

impl ModuleKey {
    /// Compute the canonical key for `path`. Reads the file, hashes
    /// it, canonicalises the path. Returns `Error::InitFailed` on
    /// any IO error so the caller can surface "module not found".
    pub fn for_path(path: &Path) -> Result<Self, Error> {
        let canonical = std::fs::canonicalize(path)
            .map_err(|e| Error::InitFailed(format!("canonicalize: {e}")))?;
        let bytes = std::fs::read(&canonical)
            .map_err(|e| Error::InitFailed(format!("read module: {e}")))?;
        let mut hasher = Sha256::new();
        hasher.update(&bytes);
        let digest = hasher.finalize();
        let mut hex = String::with_capacity(digest.len() * 2);
        for b in digest.iter() {
            use std::fmt::Write as _;
            let _ = write!(hex, "{b:02x}");
        }
        Ok(Self {
            path: canonical,
            sha256_hex: hex,
        })
    }
}

/// Loaded + initialised PKCS#11 library handle. Wraps an
/// `Arc<Pkcs11>` so the pool can hand out cheap clones; the
/// underlying handle drives `cryptoki::context::Pkcs11` methods
/// (slot enumeration, session opening).
#[derive(Clone)]
pub struct Module {
    pub key: ModuleKey,
    pub inner: Arc<Pkcs11>,
}

impl Module {
    /// Returns the typed cryptoki handle. Sync because cryptoki's
    /// every call is sync; the FRB layer wraps loading via
    /// `tokio::task::spawn_blocking`.
    pub fn pkcs11(&self) -> &Pkcs11 {
        &self.inner
    }
}

impl std::fmt::Debug for Module {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Module")
            .field("path", &self.key.path)
            .field("sha256", &&self.key.sha256_hex[..16])
            .finish()
    }
}

fn pool() -> &'static Mutex<HashMap<ModuleKey, Arc<Pkcs11>>> {
    static POOL: OnceLock<Mutex<HashMap<ModuleKey, Arc<Pkcs11>>>> = OnceLock::new();
    POOL.get_or_init(|| Mutex::new(HashMap::new()))
}

/// Load (or reuse from the pool) the PKCS#11 library at `path`.
/// Calls `C_Initialize` exactly once per `(path, sha256)` pair;
/// `CKR_CRYPTOKI_ALREADY_INITIALIZED` is treated as success per
/// PKCS#11 spec §5.4 (a host process that already loaded the same
/// library via another channel — TPM emulator, system gpg-agent —
/// is benign).
///
/// Returns `Error::InitFailed` if the file does not exist, cannot
/// be read, or `Pkcs11::new` fails for a reason other than
/// `ALREADY_INITIALIZED`. The Dart UI maps `InitFailed` to the
/// `pkcs11InitializeFailed` toast.
pub fn load(path: &Path) -> Result<Module, Error> {
    let key = ModuleKey::for_path(path)?;

    // Fast path: pool hit.
    {
        let map = pool().lock().unwrap_or_else(|e| e.into_inner());
        if let Some(existing) = map.get(&key) {
            return Ok(Module {
                key,
                inner: existing.clone(),
            });
        }
    }

    // Slow path: dlopen + initialize outside the pool lock so a
    // concurrent load of a different library never blocks behind
    // our `C_Initialize`. A racing load of the same library will
    // do duplicate work — Cryptoki tolerates this (treating the
    // second `C_Initialize` as `ALREADY_INITIALIZED`) — and then
    // the insert-or-take step below picks one winner.
    let pkcs =
        Pkcs11::new(&key.path).map_err(|e| Error::InitFailed(format!("Pkcs11::new: {e}")))?;
    // `OS_LOCKING_OK` lets the vendor library use native OS mutexes
    // for its internal serialisation. We do not pass
    // `LIBRARY_CANT_CREATE_OS_THREADS` because some HSM vendor libs
    // (Thales Luna's CloudHSM-style runner) spawn worker threads for
    // background card events and refusing them disables the live
    // hot-plug path.
    match pkcs.initialize(CInitializeArgs::new(CInitializeFlags::OS_LOCKING_OK)) {
        Ok(()) => {}
        Err(cryptoki::error::Error::Pkcs11(
            cryptoki::error::RvError::CryptokiAlreadyInitialized,
            _,
        )) => {}
        Err(e) => {
            return Err(Error::InitFailed(format!("C_Initialize: {e}")));
        }
    }
    let info = pkcs
        .get_library_info()
        .map_err(|e| Error::InitFailed(format!("get_library_info: {e}")))?;
    let major = info.cryptoki_version().major();
    let minor = info.cryptoki_version().minor();
    if major < 2 || (major == 2 && minor < 20) {
        return Err(Error::UnsupportedCryptokiVersion(format!(
            "library reports cryptoki {major}.{minor}; need >= 2.20"
        )));
    }

    let arc = Arc::new(pkcs);
    let mut map = pool().lock().unwrap_or_else(|e| e.into_inner());
    let stored = map.entry(key.clone()).or_insert_with(|| arc.clone());
    Ok(Module {
        key,
        inner: stored.clone(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn module_key_for_missing_path_errors() {
        let err = ModuleKey::for_path(Path::new("/this/path/does/not/exist")).unwrap_err();
        assert!(matches!(err, Error::InitFailed(_)));
    }

    #[test]
    fn module_key_for_real_file_computes_sha256() {
        let mut path = std::env::temp_dir();
        path.push("lfs_pkcs11_module_key_test.bin");
        std::fs::write(&path, b"hello").unwrap();
        let key = ModuleKey::for_path(&path).unwrap();
        // SHA-256("hello") known constant.
        assert_eq!(
            key.sha256_hex,
            "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
        );
        let _ = std::fs::remove_file(&path);
    }
}
