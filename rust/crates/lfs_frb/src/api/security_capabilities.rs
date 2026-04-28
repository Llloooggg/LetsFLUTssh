//! FRB adapter for `lfs_core::security::capabilities`.
//!
//! Sync — encode is a small JSON serialise + a few enum lookups,
//! decode is a parse + per-field type-check. The wizard probes
//! capabilities once on open and caches the result, so the
//! per-call work happens at most a handful of times per session;
//! the no-async-hop overhead matters less than the simpler API.
//!
//! Wire shape on both sides: the Dart caller hands a JSON-string
//! payload to / from the FRB boundary. Crossing the boundary as a
//! string keeps the field set additive — a future schema bump
//! lands inside `lfs_core` without re-generating bindings.

use lfs_core::security::capabilities::SecurityCapabilities;

/// Encode a [`SecurityCapabilities`] snapshot into the JSON wire
/// format the wizard persists inside `config.json` under
/// `security_probe_cache`. Returns the minified JSON string —
/// caller stores it as a Dart `Map<String, dynamic>` after a
/// `jsonDecode` round-trip.
///
/// Inputs come unpacked because FRB cannot derive a struct mirror
/// for `SecurityCapabilities` without re-encoding the
/// `KeyringProbeResult` enum + every field. A flat parameter list
/// keeps the Dart side from having to mirror the enum twice (once
/// in the Rust DTO, once in its own `KeyringProbeResult`).
#[flutter_rust_bridge::frb(sync)]
pub fn security_capabilities_to_json(
    keychain_available: bool,
    hardware_vault_available: bool,
    biometric_available: bool,
    fprintd_available: bool,
    is_linux_host: bool,
    keychain_probe_wire_name: String,
    hardware_probe_code: String,
) -> Result<String, String> {
    let probe = lfs_core::security::capabilities::KeyringProbeResult::from_wire_name(
        &keychain_probe_wire_name,
    )
    .ok_or_else(|| format!("unknown keychain_probe wire name: {keychain_probe_wire_name}"))?;
    let caps = SecurityCapabilities {
        keychain_available,
        hardware_vault_available,
        biometric_available,
        fprintd_available,
        is_linux_host,
        keychain_probe: probe,
        hardware_probe_code,
    };
    Ok(caps.to_json_value().to_string())
}

/// FRB-side mirror of the parsed snapshot. Returned as a flat DTO
/// so the Dart caller can rebuild `SecurityCapabilities` without
/// re-importing the enum from a generated file.
#[derive(Debug, Clone)]
pub struct DbSecurityCapabilities {
    pub keychain_available: bool,
    pub hardware_vault_available: bool,
    pub biometric_available: bool,
    pub fprintd_available: bool,
    pub is_linux_host: bool,
    /// Stable Dart `name` for `KeyringProbeResult` — `available`,
    /// `linuxNoSecretService`, or `probeFailed`.
    pub keychain_probe_wire_name: String,
    pub hardware_probe_code: String,
}

/// Parse a `security_probe_cache` JSON snapshot. Returns `None` for
/// any malformed shape (non-object root, unknown enum case,
/// missing required strings) so the Dart caller falls through to
/// "no cache" and reprobes.
#[flutter_rust_bridge::frb(sync)]
pub fn security_capabilities_from_json(json: String) -> Option<DbSecurityCapabilities> {
    let value: serde_json::Value = serde_json::from_str(&json).ok()?;
    SecurityCapabilities::from_json_value(&value).map(|c| DbSecurityCapabilities {
        keychain_available: c.keychain_available,
        hardware_vault_available: c.hardware_vault_available,
        biometric_available: c.biometric_available,
        fprintd_available: c.fprintd_available,
        is_linux_host: c.is_linux_host,
        keychain_probe_wire_name: c.keychain_probe.wire_name().to_string(),
        hardware_probe_code: c.hardware_probe_code,
    })
}
