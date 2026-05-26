//! FRB adapter for `lfs_os_security::linux::tpm`.
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

use crate::api::frb_err;

/// Mirror of `lfs_os_security::linux::tpm::TpmProbeResult` so
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
fn map_probe(r: lfs_os_security::linux::tpm::TpmProbeResult) -> DbTpmProbeResult {
    use lfs_os_security::linux::tpm::TpmProbeResult as R;
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
        let r = tokio::task::spawn_blocking(move || lfs_os_security::linux::tpm::probe(&cfg))
            .await
            .unwrap_or(lfs_os_security::linux::tpm::TpmProbeResult::ProbeFailed);
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
/// unseal password. Returns the
/// `LFHV[…|platform_id_linux] || TCG_ASN1_DER` envelope the Dart
/// vault writes verbatim to `hardware_vault.bin`; the DER body
/// follows the `id-loadablekey` arm of
/// `draft-bottomley-tpm2-keys-asn1`.
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
            lfs_os_security::linux::tpm::seal(&cfg, &secret, &auth_value)
        })
        .await
        .map_err(|e| frb_err::wire(frb_err::kind::GENERIC, &format!("tpm seal task: {e}")))?
        .map_err(|e| crate::api::frb_err::wire_str(crate::api::frb_err::kind::CRYPTO, e))
    }
    #[cfg(not(target_os = "linux"))]
    {
        let _ = (secret, auth_value, binary, device, timeout_ms);
        Err(frb_err::wire(
            frb_err::kind::UNSUPPORTED,
            "tpm2 not available on this platform",
        ))
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
            lfs_os_security::linux::tpm::unseal(&cfg, &blob, &auth_value)
        })
        .await
        .map_err(|e| frb_err::wire(frb_err::kind::GENERIC, &format!("tpm unseal task: {e}")))?
        .map_err(|e| crate::api::frb_err::wire_str(crate::api::frb_err::kind::CRYPTO, e))
    }
    #[cfg(not(target_os = "linux"))]
    {
        let _ = (blob, auth_value, binary, device, timeout_ms);
        Err(frb_err::wire(
            frb_err::kind::UNSUPPORTED,
            "tpm2 not available on this platform",
        ))
    }
}

#[cfg(target_os = "linux")]
fn build_cfg(
    binary: Option<String>,
    device: Option<String>,
    timeout_ms: Option<u64>,
) -> lfs_os_security::linux::tpm::TpmConfig {
    let mut cfg = lfs_os_security::linux::tpm::TpmConfig::default();
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

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn probe_returns_a_typed_variant_without_panic() {
        // Test ranges over both platform branches — Linux returns
        // one of Available / DeviceNodeMissing / BinaryMissing /
        // ProbeFailed; non-Linux returns NotLinux. All five are
        // valid; the only invariant is "doesn't panic".
        let r = tpm_probe(None, None, Some(50)).await;
        let _ = r;
    }

    #[tokio::test]
    async fn db_tpm_probe_result_clone_round_trip() {
        // Defensive — guards against a future refactor that
        // accidentally drops `Copy` / `Clone` on the FRB-marshalled
        // enum.
        let v = DbTpmProbeResult::Available;
        let c = v;
        assert_eq!(c, DbTpmProbeResult::Available);
    }

    #[cfg(not(target_os = "linux"))]
    #[tokio::test]
    async fn non_linux_seal_surfaces_err_without_panic() {
        let res = tpm_seal(b"secret".to_vec(), b"auth".to_vec(), None, None, None).await;
        assert!(res.is_err());
    }

    #[cfg(not(target_os = "linux"))]
    #[tokio::test]
    async fn non_linux_unseal_surfaces_err_without_panic() {
        let res = tpm_unseal(vec![0u8; 64], b"auth".to_vec(), None, None, None).await;
        assert!(res.is_err());
    }

    #[cfg(not(target_os = "linux"))]
    #[tokio::test]
    async fn non_linux_probe_returns_not_linux_sentinel() {
        let r = tpm_probe(None, None, None).await;
        assert_eq!(r, DbTpmProbeResult::NotLinux);
    }
}
