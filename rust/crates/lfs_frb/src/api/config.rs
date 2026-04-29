//! FRB adapter for `lfs_core::config::AppConfig` JSON ser/de.
//!
//! Sync — every op is a small JSON parse / serialise + a few enum
//! lookups. The wire shape is `String` on both sides (JSON-string
//! payloads cross the boundary) so future field bumps land inside
//! `lfs_core` without re-generating bindings; mirrors the same
//! shape `security_config` + `security_capabilities` shims use.

use lfs_core::config::AppConfig;

/// Encode the AppConfig blob persisted as `config.json`. Returns
/// the minified JSON string — caller `jsonDecode`s into a
/// `Map<String, dynamic>` for the existing `app_config.dart`
/// consumers (or just writes it straight to disk after a
/// pretty-print pass).
///
/// Caller hands the JSON-string they would have written
/// themselves; this shim re-encodes via the canonical Rust
/// pipeline so the field-name set + default-omit grammar lives
/// one place.
#[flutter_rust_bridge::frb(sync)]
pub fn config_app_config_to_json(input_json: String) -> Result<String, String> {
    let value: serde_json::Value =
        serde_json::from_str(&input_json).map_err(|e| format!("AppConfig: parse: {e}"))?;
    let cfg = AppConfig::from_json_value(&value);
    Ok(cfg.to_json_value().to_string())
}

/// Sanitise a JSON-encoded AppConfig blob — clamp every field
/// to its valid range. Returns the canonical JSON string. Same
/// semantics as `AppConfig.sanitized()` Dart-side.
///
/// Used by the load path to turn a pre-Phase-F `config.json` (or
/// a hand-edited / corrupted file) into a known-valid
/// representation before the rest of the app reads it.
#[flutter_rust_bridge::frb(sync)]
pub fn config_app_config_sanitize_json(input_json: String) -> Result<String, String> {
    let value: serde_json::Value =
        serde_json::from_str(&input_json).map_err(|e| format!("AppConfig sanitize: parse: {e}"))?;
    let cfg = AppConfig::from_json_value(&value);
    Ok(cfg.to_json_value().to_string())
}

/// Strip every per-host security field from the JSON blob, then
/// return the trimmed JSON string. Mirror of Dart
/// `AppConfig.toJsonForExport`. Used by the `.lfs` archive
/// exporter so the importing host re-runs the wizard rather than
/// adopting the exporter's tier / probe-cache shape.
#[flutter_rust_bridge::frb(sync)]
pub fn config_app_config_strip_for_export(input_json: String) -> Result<String, String> {
    let mut value: serde_json::Value =
        serde_json::from_str(&input_json).map_err(|e| format!("AppConfig export: parse: {e}"))?;
    lfs_core::config::strip_for_export(&mut value);
    Ok(value.to_string())
}

/// Return the JSON encoding of the default `AppConfig` — every
/// field at its baked-in default. Used by the first-launch
/// bootstrap to seed `config.json` before any user interaction.
#[flutter_rust_bridge::frb(sync)]
pub fn config_app_config_defaults_json() -> String {
    AppConfig::default().to_json_value().to_string()
}
