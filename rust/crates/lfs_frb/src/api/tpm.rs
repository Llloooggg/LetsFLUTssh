//! FRB adapter for `lfs_core::platform::linux::tpm`.
//!
//! Async — every call shells out to `tpm2-tools`; the spawn +
//! wait would block the FRB tokio worker thread otherwise. The
//! core driver itself is sync (see its module doc — "we do not
//! own the runtime"), so the adapter wraps each call in
//! `tokio::task::spawn_blocking` per the same pattern the keygen
//! shim uses.
//!
//! Non-Linux hosts get a `TpmProbeFailedNotLinux` probe response
//! and `Err("tpm2 not available on this platform")` for seal /
//! unseal — Dart callers short-circuit on `Platform.isLinux`
//! before reaching the native lib, but the shim is defensive so
//! a misrouted call surfaces a clear error instead of a mystery
//! linker symbol.

/// Mirror of `lfs_core::platform::linux::tpm::TpmProbeResult` so
/// the Dart UI can branch on a typed enum instead of a magic
/// number.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DbTpmProbeResult {
    Available,
    DeviceNodeMissing,
    BinaryMissing,
    ProbeFailed,
    /// Non-Linux host. Caller short-circuits before reaching here.
    NotLinux,
}

#[cfg(target_os = "linux")]
fn map_probe(r: lfs_core::platform::linux::tpm::TpmProbeResult) -> DbTpmProbeResult {
    use lfs_core::platform::linux::tpm::TpmProbeResult as R;
    match r {
        R::Available => DbTpmProbeResult::Available,
        R::DeviceNodeMissing => DbTpmProbeResult::DeviceNodeMissing,
        R::BinaryMissing => DbTpmProbeResult::BinaryMissing,
        R::ProbeFailed => DbTpmProbeResult::ProbeFailed,
    }
}

/// Run the classified TPM availability probe (device node +
/// binary + `tpm2 createprimary` round-trip). On non-Linux hosts
/// returns `NotLinux` without doing any I/O — the call is cheap
/// to drop into a Dart `if (Platform.isLinux)` guard for safety
/// rather than performance.
///
/// `binary` / `device` / `timeout_ms` mirror the Dart
/// `TpmClient` knobs so unit tests can swap them. Production
/// callers pass `None` for all three to pick up the lfs_core
/// defaults.
pub async fn tpm_probe(
    binary: Option<String>,
    device: Option<String>,
    timeout_ms: Option<u64>,
) -> DbTpmProbeResult {
    #[cfg(target_os = "linux")]
    {
        let cfg = build_cfg(binary, device, timeout_ms);
        let r = tokio::task::spawn_blocking(move || lfs_core::platform::linux::tpm::probe(&cfg))
            .await
            .unwrap_or(lfs_core::platform::linux::tpm::TpmProbeResult::ProbeFailed);
        map_probe(r)
    }
    #[cfg(not(target_os = "linux"))]
    {
        let _ = (binary, device, timeout_ms);
        DbTpmProbeResult::NotLinux
    }
}

/// Seal `secret` (≤ 128 bytes — TPM2 direct-seal spec ceiling)
/// under a freshly-created primary with `auth_value` as the
/// unseal password. Returns the packed
/// `[u32 BE pub_len][pub][u32 BE priv_len][priv]` blob the Dart
/// vault writes verbatim to `hardware_vault.bin`.
///
/// Plaintext discipline — `secret` and `auth_value` cross FRB
/// once per seal, get written to 0600 temp files inside an RAII
/// work dir that zero-overwrites on drop. The auth-value file is
/// passed via `tpm2-tools`' `file:<path>` argument, never via
/// `hex:<hex>`, so the bytes never appear in
/// `/proc/<pid>/cmdline`.
pub async fn tpm_seal(
    secret: Vec<u8>,
    auth_value: Vec<u8>,
    binary: Option<String>,
    device: Option<String>,
    timeout_ms: Option<u64>,
) -> Result<Vec<u8>, String> {
    #[cfg(target_os = "linux")]
    {
        let cfg = build_cfg(binary, device, timeout_ms);
        tokio::task::spawn_blocking(move || {
            lfs_core::platform::linux::tpm::seal(&cfg, &secret, &auth_value)
        })
        .await
        .map_err(|e| format!("tpm seal task: {e}"))?
        .map_err(|e| e.to_string())
    }
    #[cfg(not(target_os = "linux"))]
    {
        let _ = (secret, auth_value, binary, device, timeout_ms);
        Err("tpm2 not available on this platform".to_string())
    }
}

/// Inverse of [`tpm_seal`]. Returns the original secret on
/// successful unseal; format mismatch / wrong auth / missing
/// TPM all surface as `Err(<stderr or io error>)`.
pub async fn tpm_unseal(
    blob: Vec<u8>,
    auth_value: Vec<u8>,
    binary: Option<String>,
    device: Option<String>,
    timeout_ms: Option<u64>,
) -> Result<Vec<u8>, String> {
    #[cfg(target_os = "linux")]
    {
        let cfg = build_cfg(binary, device, timeout_ms);
        tokio::task::spawn_blocking(move || {
            lfs_core::platform::linux::tpm::unseal(&cfg, &blob, &auth_value)
        })
        .await
        .map_err(|e| format!("tpm unseal task: {e}"))?
        .map_err(|e| e.to_string())
    }
    #[cfg(not(target_os = "linux"))]
    {
        let _ = (blob, auth_value, binary, device, timeout_ms);
        Err("tpm2 not available on this platform".to_string())
    }
}

#[cfg(target_os = "linux")]
fn build_cfg(
    binary: Option<String>,
    device: Option<String>,
    timeout_ms: Option<u64>,
) -> lfs_core::platform::linux::tpm::TpmConfig {
    let mut cfg = lfs_core::platform::linux::tpm::TpmConfig::default();
    if let Some(b) = binary {
        cfg.binary = b;
    }
    if let Some(d) = device {
        cfg.device = d;
    }
    if let Some(ms) = timeout_ms {
        cfg.timeout = std::time::Duration::from_millis(ms);
    }
    cfg
}
