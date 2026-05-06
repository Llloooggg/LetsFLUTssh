//! TPM2 seal/unseal. Two backends behind one public surface
//! (`probe` / `seal` / `unseal`):
//!
//! 1. **Subprocess (default)** — `tpm2-tools` CLI. Auth values
//!    pass via `file:<path>` (not argv) so the HMAC stays out
//!    of `/proc/<pid>/cmdline`; the per-op work dir is
//!    zero-overwritten on unlink.
//! 2. **Native (opt-in via `LFS_TPM_BACKEND=native`)** —
//!    direct `libtss2-esys` calls through `tss-esapi`, see
//!    [`super::tpm_native`]. Envelope bytes are identical to
//!    the subprocess path so envelopes round-trip between
//!    backends.
//!
//! Backend selection: [`TpmConfig::default`] reads
//! `LFS_TPM_BACKEND`; callers may also set `cfg.backend`
//! directly. Sync API; the caller wraps in `spawn_blocking`.

use std::fs::{self, File, OpenOptions};
use std::io::{Read, Write};
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::Duration;

use crate::error::Error;

const DEFAULT_BINARY: &str = "tpm2";
const DEFAULT_DEVICE: &str = "/dev/tpmrm0";
/// Hard upper bound on a single seal / unseal step.
pub const DEFAULT_TIMEOUT: Duration = Duration::from_secs(15);
/// TPM2 spec direct-seal limit. Mirrors the Dart guardrail.
pub const MAX_SEAL_BYTES: usize = 128;

/// Classified probe outcome. Lets the Settings UI render a
/// targeted hint instead of a generic "hardware unavailable".
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TpmProbeResult {
    /// Device node + binary + `getcap` + `createprimary` all
    /// succeeded — TPM sealing is ready to go.
    Available,
    /// `/dev/tpmrm0` (or the override) does not exist. Either
    /// no TPM, kernel module not loaded, or fTPM disabled in
    /// firmware.
    DeviceNodeMissing,
    /// `tpm2` binary not on `$PATH` or not executable.
    BinaryMissing,
    /// `getcap` / `createprimary` returned non-zero — usually
    /// a permissions issue on `/dev/tpmrm0` (wrong udev rule)
    /// or a TPM-side command failure.
    ProbeFailed,
}

/// Which seal/unseal implementation to dispatch to. Default is
/// [`TpmBackend::Subprocess`] (verified-working tpm2-tools
/// shell-out); set to [`TpmBackend::Native`] to opt into the
/// direct-libtss2 path while it is verification-pending.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TpmBackend {
    /// Spawn `tpm2 ...` per operation; on-disk envelope bytes
    /// produced by `tpm2 create -u/-r`. The historical default;
    /// stays the default until NI-2 verifies the native path on
    /// real TPM hardware.
    Subprocess,
    /// Direct calls into `libtss2-esys` via the `tss-esapi`
    /// crate; see [`super::tpm_native`]. Byte-compatible with
    /// the subprocess envelope at the marshalling layer (both
    /// go through `Tss2_MU_TPM2B_*` inside libtss2).
    Native,
}

impl Default for TpmBackend {
    fn default() -> Self {
        // Env-var opt-in is read here so a single `TpmConfig::default`
        // call captures the user's choice for the lifetime of the
        // resulting config. Recognised values: `native` (case-
        // insensitive) flips to the native path; anything else
        // (including unset) keeps the subprocess default.
        match std::env::var("LFS_TPM_BACKEND") {
            Ok(v) if v.eq_ignore_ascii_case("native") => TpmBackend::Native,
            _ => TpmBackend::Subprocess,
        }
    }
}

/// Configurable knobs — tests inject a fake binary path /
/// device path, production uses [`DEFAULT_BINARY`] +
/// [`DEFAULT_DEVICE`].
#[derive(Debug, Clone)]
pub struct TpmConfig {
    pub binary: String,
    pub device: String,
    pub timeout: Duration,
    /// Implementation backend — set via env var by default
    /// ([`TpmBackend::default`]); the FRB layer or tests can
    /// override programmatically.
    pub backend: TpmBackend,
}

impl Default for TpmConfig {
    fn default() -> Self {
        Self {
            binary: DEFAULT_BINARY.to_string(),
            device: DEFAULT_DEVICE.to_string(),
            timeout: DEFAULT_TIMEOUT,
            backend: TpmBackend::default(),
        }
    }
}

/// Probe the TPM availability path: device node, binary, and
/// a real `createprimary` round-trip. The full primary creation
/// matches the seal flow's first step, so `Available` here is
/// a strict guarantee that downstream sealing will not fail
/// with a permissions / lockout error.
pub fn probe(cfg: &TpmConfig) -> TpmProbeResult {
    if cfg.backend == TpmBackend::Native {
        return super::tpm_native::probe(cfg);
    }
    probe_subprocess(cfg)
}

fn probe_subprocess(cfg: &TpmConfig) -> TpmProbeResult {
    if !Path::new(&cfg.device).exists() {
        return TpmProbeResult::DeviceNodeMissing;
    }
    match run_tpm(cfg, &["getcap", "-l"]) {
        Ok(_) => {}
        Err(ProcessError::BinaryMissing) => return TpmProbeResult::BinaryMissing,
        Err(_) => return TpmProbeResult::ProbeFailed,
    }
    let work = match WorkDir::new("lfs-tpm-probe-") {
        Ok(w) => w,
        Err(_) => return TpmProbeResult::ProbeFailed,
    };
    let ctx = work.path().join("probe.ctx");
    let ctx_str = ctx.to_string_lossy().into_owned();
    match run_tpm(cfg, &["createprimary", "-Q", "-C", "o", "-c", &ctx_str]) {
        Ok(_) => TpmProbeResult::Available,
        Err(_) => TpmProbeResult::ProbeFailed,
    }
}

/// Seal `secret` under a freshly-created primary with
/// `auth_value` as the unseal password. Returns the packed
/// `[u32 BE pub_len][pub][u32 BE priv_len][priv]` blob.
pub fn seal(cfg: &TpmConfig, secret: &[u8], auth_value: &[u8]) -> Result<Vec<u8>, Error> {
    if cfg.backend == TpmBackend::Native {
        return super::tpm_native::seal(cfg, secret, auth_value);
    }
    seal_subprocess(cfg, secret, auth_value)
}

fn seal_subprocess(cfg: &TpmConfig, secret: &[u8], auth_value: &[u8]) -> Result<Vec<u8>, Error> {
    if secret.len() > MAX_SEAL_BYTES {
        return Err(Error::Crypto(format!(
            "tpm seal rejected: secret {} bytes > {}",
            secret.len(),
            MAX_SEAL_BYTES
        )));
    }
    let work = WorkDir::new("lfs-tpm-seal-")?;
    let primary = work.path().join("primary.ctx");
    let pub_path = work.path().join("sealed.pub");
    let priv_path = work.path().join("sealed.priv");
    let secret_path = work.path().join("secret.bin");
    write_0600(&secret_path, secret)?;
    let auth_arg = write_auth_file(&work, auth_value)?;

    let primary_str = primary.to_string_lossy().into_owned();
    let pub_str = pub_path.to_string_lossy().into_owned();
    let priv_str = priv_path.to_string_lossy().into_owned();
    let secret_str = secret_path.to_string_lossy().into_owned();

    run_tpm(cfg, &["createprimary", "-Q", "-C", "o", "-c", &primary_str])
        .map_err(|e| Error::Crypto(format!("tpm createprimary: {e}")))?;
    run_tpm(
        cfg,
        &[
            "create",
            "-Q",
            "-C",
            &primary_str,
            "-u",
            &pub_str,
            "-r",
            &priv_str,
            "-i",
            &secret_str,
            "-p",
            &auth_arg,
        ],
    )
    .map_err(|e| Error::Crypto(format!("tpm create: {e}")))?;

    let pub_bytes = read_all(&pub_path)?;
    let priv_bytes = read_all(&priv_path)?;
    Ok(pack(&pub_bytes, &priv_bytes))
}

/// Inverse of [`seal`]. Returns the original secret on
/// `verify-match`; format mismatch / wrong auth / missing TPM
/// all produce `Err`.
pub fn unseal(cfg: &TpmConfig, blob: &[u8], auth_value: &[u8]) -> Result<Vec<u8>, Error> {
    if cfg.backend == TpmBackend::Native {
        return super::tpm_native::unseal(cfg, blob, auth_value);
    }
    unseal_subprocess(cfg, blob, auth_value)
}

fn unseal_subprocess(cfg: &TpmConfig, blob: &[u8], auth_value: &[u8]) -> Result<Vec<u8>, Error> {
    let (pub_bytes, priv_bytes) =
        unpack(blob).ok_or_else(|| Error::Crypto("tpm unseal: malformed blob".to_string()))?;
    let work = WorkDir::new("lfs-tpm-unseal-")?;
    let primary = work.path().join("primary.ctx");
    let pub_path = work.path().join("sealed.pub");
    let priv_path = work.path().join("sealed.priv");
    let loaded_ctx = work.path().join("loaded.ctx");
    write_0600(&pub_path, pub_bytes)?;
    write_0600(&priv_path, priv_bytes)?;
    let auth_arg = write_auth_file(&work, auth_value)?;

    let primary_str = primary.to_string_lossy().into_owned();
    let pub_str = pub_path.to_string_lossy().into_owned();
    let priv_str = priv_path.to_string_lossy().into_owned();
    let loaded_str = loaded_ctx.to_string_lossy().into_owned();

    run_tpm(cfg, &["createprimary", "-Q", "-C", "o", "-c", &primary_str])
        .map_err(|e| Error::Crypto(format!("tpm createprimary: {e}")))?;
    run_tpm(
        cfg,
        &[
            "load",
            "-Q",
            "-C",
            &primary_str,
            "-u",
            &pub_str,
            "-r",
            &priv_str,
            "-c",
            &loaded_str,
        ],
    )
    .map_err(|e| Error::Crypto(format!("tpm load: {e}")))?;

    let stdout = run_tpm_capture(cfg, &["unseal", "-Q", "-c", &loaded_str, "-p", &auth_arg])
        .map_err(|e| Error::Crypto(format!("tpm unseal: {e}")))?;
    Ok(stdout)
}

// ---- Internals ---------------------------------------------------------

#[derive(Debug)]
enum ProcessError {
    BinaryMissing,
    NonZero { exit: i32, stderr: String },
    Io(String),
}

impl std::fmt::Display for ProcessError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            ProcessError::BinaryMissing => write!(f, "tpm2 binary missing"),
            ProcessError::NonZero { exit, stderr } => {
                write!(f, "tpm2 exit={exit} stderr={stderr}")
            }
            ProcessError::Io(s) => write!(f, "tpm2 io: {s}"),
        }
    }
}

fn run_tpm(cfg: &TpmConfig, args: &[&str]) -> Result<(), ProcessError> {
    let _ = run_tpm_capture(cfg, args)?;
    Ok(())
}

fn run_tpm_capture(cfg: &TpmConfig, args: &[&str]) -> Result<Vec<u8>, ProcessError> {
    let mut cmd = Command::new(&cfg.binary);
    cmd.args(args)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .stdin(Stdio::null());
    let child = match cmd.spawn() {
        Ok(c) => c,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
            return Err(ProcessError::BinaryMissing);
        }
        Err(e) => return Err(ProcessError::Io(e.to_string())),
    };
    let output = match wait_with_timeout(child, cfg.timeout) {
        Ok(o) => o,
        Err(e) => return Err(ProcessError::Io(e)),
    };
    if !output.status.success() {
        return Err(ProcessError::NonZero {
            exit: output.status.code().unwrap_or(-1),
            stderr: String::from_utf8_lossy(&output.stderr).into_owned(),
        });
    }
    Ok(output.stdout)
}

fn wait_with_timeout(
    child: std::process::Child,
    timeout: Duration,
) -> Result<std::process::Output, String> {
    use std::sync::mpsc;
    use std::thread;
    let (tx, rx) = mpsc::channel();
    // Move stdin/stdout/stderr off the parent thread via wait_with_output.
    thread::spawn(move || {
        let result = child.wait_with_output();
        let _ = tx.send(result);
    });
    match rx.recv_timeout(timeout) {
        Ok(Ok(o)) => Ok(o),
        Ok(Err(e)) => Err(e.to_string()),
        Err(_) => Err(format!("tpm2 timed out after {}s", timeout.as_secs())),
    }
}

fn write_0600(path: &Path, bytes: &[u8]) -> Result<(), Error> {
    let mut opts = OpenOptions::new();
    opts.create(true).write(true).truncate(true);
    use std::os::unix::fs::OpenOptionsExt;
    opts.mode(0o600);
    let mut f = opts
        .open(path)
        .map_err(|e| Error::Platform(format!("tpm write {}: {e}", path.display())))?;
    f.write_all(bytes)
        .map_err(|e| Error::Platform(format!("tpm write {}: {e}", path.display())))?;
    f.sync_all()
        .map_err(|e| Error::Platform(format!("tpm sync {}: {e}", path.display())))?;
    Ok(())
}

fn read_all(path: &Path) -> Result<Vec<u8>, Error> {
    let mut f =
        File::open(path).map_err(|e| Error::Platform(format!("tpm read {}: {e}", path.display())))?;
    let mut buf = Vec::new();
    f.read_to_end(&mut buf)
        .map_err(|e| Error::Platform(format!("tpm read {}: {e}", path.display())))?;
    Ok(buf)
}

fn write_auth_file(work: &WorkDir, auth_value: &[u8]) -> Result<String, Error> {
    let path = work.path().join("auth.bin");
    write_0600(&path, auth_value)?;
    Ok(format!("file:{}", path.display()))
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

/// RAII temp dir — Drop wipes every file (zero-overwrite then
/// unlink) so a sealed-but-transient plaintext (`secret.bin`)
/// is not left readable on whatever filesystem `/tmp` lives on.
struct WorkDir {
    path: PathBuf,
}

impl WorkDir {
    fn new(prefix: &str) -> Result<Self, Error> {
        // std doesn't ship a `mkdtemp`; build one against a
        // monotonic counter + pid + random suffix. Collisions
        // get retried up to 16 times.
        use rand::RngCore;
        let base = std::env::temp_dir();
        let pid = std::process::id();
        let mut rng = rand::rngs::OsRng;
        for _ in 0..16 {
            let mut bytes = [0u8; 8];
            rng.fill_bytes(&mut bytes);
            let suffix: String = bytes.iter().map(|b| format!("{b:02x}")).collect();
            let candidate = base.join(format!("{prefix}{pid}-{suffix}"));
            match fs::create_dir(&candidate) {
                Ok(_) => {
                    let _ = fs::set_permissions(&candidate, fs::Permissions::from_mode(0o700));
                    return Ok(Self { path: candidate });
                }
                Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists => continue,
                Err(e) => return Err(Error::Platform(format!("tpm mkdtemp: {e}"))),
            }
        }
        Err(Error::Io("tpm mkdtemp: out of retries".to_string()))
    }

    fn path(&self) -> &Path {
        &self.path
    }
}

impl Drop for WorkDir {
    fn drop(&mut self) {
        if let Ok(entries) = fs::read_dir(&self.path) {
            for entry in entries.flatten() {
                let p = entry.path();
                if let Ok(meta) = fs::metadata(&p) {
                    if meta.is_file() {
                        // Best-effort overwrite before unlink.
                        let len = meta.len();
                        let zeros = vec![0u8; len as usize];
                        let _ = fs::write(&p, zeros);
                    }
                }
                let _ = fs::remove_file(&p);
            }
        }
        let _ = fs::remove_dir(&self.path);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

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
    fn unpack_rejects_short_blob() {
        assert!(unpack(&[0u8; 7]).is_none());
        assert!(unpack(&[]).is_none());
    }

    #[test]
    fn unpack_rejects_truncated_priv_section() {
        // pub_len=2, pub=[0xaa,0xbb], priv_len=10 (way beyond
        // remaining bytes) → must reject without panicking.
        let mut blob = vec![0, 0, 0, 2, 0xaa, 0xbb, 0, 0, 0, 10];
        blob.extend_from_slice(&[0xcc, 0xcc]);
        assert!(unpack(&blob).is_none());
    }

    #[test]
    fn probe_with_missing_device_returns_devicenodemissing() {
        let cfg = TpmConfig {
            binary: "tpm2".into(),
            device: "/nonexistent/tpm-test-node".into(),
            timeout: Duration::from_secs(2),
            backend: TpmBackend::Subprocess,
        };
        assert_eq!(probe(&cfg), TpmProbeResult::DeviceNodeMissing);
    }

    #[test]
    fn probe_with_present_device_but_missing_binary() {
        // Use /dev/null (always exists on Linux) as the fake
        // device node so the probe gets past the device check
        // and tries to spawn the (missing) binary.
        let cfg = TpmConfig {
            binary: "/nonexistent/tpm2-binary-test".into(),
            device: "/dev/null".into(),
            timeout: Duration::from_secs(2),
            backend: TpmBackend::Subprocess,
        };
        assert_eq!(probe(&cfg), TpmProbeResult::BinaryMissing);
    }

    #[test]
    fn backend_default_reads_env() {
        // Saved + restored to keep test cases independent.
        let prev = std::env::var("LFS_TPM_BACKEND").ok();
        // SAFETY rationale: env mutation in tests is the
        // standard Rust pattern; lfs_core's `unsafe_code = "forbid"`
        // doesn't apply here because `set_var` / `remove_var`
        // are not unsafe in std.
        std::env::set_var("LFS_TPM_BACKEND", "native");
        assert_eq!(TpmBackend::default(), TpmBackend::Native);
        std::env::set_var("LFS_TPM_BACKEND", "Native");
        assert_eq!(TpmBackend::default(), TpmBackend::Native);
        std::env::set_var("LFS_TPM_BACKEND", "subprocess");
        assert_eq!(TpmBackend::default(), TpmBackend::Subprocess);
        std::env::remove_var("LFS_TPM_BACKEND");
        assert_eq!(TpmBackend::default(), TpmBackend::Subprocess);
        if let Some(v) = prev {
            std::env::set_var("LFS_TPM_BACKEND", v);
        }
    }

    #[test]
    fn workdir_wipes_files_on_drop() {
        let work = WorkDir::new("lfs-tpm-test-").expect("mkdtemp");
        let path = work.path().to_path_buf();
        let file = path.join("secret.bin");
        write_0600(&file, b"deadbeef").expect("write");
        assert!(file.exists());
        drop(work);
        assert!(!path.exists(), "workdir leaked: {}", path.display());
    }
}
