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

/// Locale codes the app's `app_*.arb` bundles ship for. Mirror of
/// `AppConfig.supportedLocales` Dart-side; exposed via FRB so the
/// validator + Settings dropdown read the same Rust-side const.
#[flutter_rust_bridge::frb(sync)]
pub fn config_supported_locales() -> Vec<String> {
    lfs_core::config::SUPPORTED_LOCALES
        .iter()
        .map(|s| (*s).to_string())
        .collect()
}

/// Validate a JSON-encoded AppConfig. Returns `Some(message)` on
/// the first failure (terminal → ssh → ui → workers → history)
/// and `None` when every field is in range. Mirror of
/// `AppConfig.validate` Dart-side; the returned message is an
/// English placeholder that the Settings UI translates via the
/// `app_*.arb` validation keys.
#[flutter_rust_bridge::frb(sync)]
pub fn config_app_config_validate_json(input_json: String) -> Option<String> {
    let value: serde_json::Value = serde_json::from_str(&input_json).ok()?;
    let cfg = AppConfig::from_json_value(&value);
    cfg.validate().map(String::from)
}

// ── Store actor ───────────────────────────────────────────────

/// Initialise the process-singleton config store actor against
/// `support_dir`. Loads `<support_dir>/config.json` if present;
/// seeds with `AppConfig::default()` otherwise. Returns the
/// canonical JSON the actor adopted so the Dart caller doesn't
/// need a follow-up `config_store_get_json` round-trip.
///
/// Rust owns debounce + atomic file I/O + bus event publication.
/// Dart `ConfigNotifier` shrinks to a `BusEvent::ConfigChanged`
/// subscriber + `set_json` calls.
///
/// Also spawns the singleton background ticker that drives the
/// debounce flush — production calls this once at startup; tests
/// drive ticks manually via `config_store_tick_if_due`.
#[flutter_rust_bridge::frb(sync)]
pub fn config_store_init(support_dir: String) -> Result<String, String> {
    let json = lfs_core::config_store::instance().init(std::path::PathBuf::from(support_dir))?;
    lfs_core::config_store::start_background_ticker();
    Ok(json)
}

/// Snapshot the actor's current config. Returns `None` before
/// `config_store_init` runs; callers treat that as "use defaults
/// until startup init lands".
#[flutter_rust_bridge::frb(sync)]
pub fn config_store_get_json() -> Option<String> {
    lfs_core::config_store::instance().get_json()
}

/// Replace the in-memory state and arm the debounce timer. The
/// disk write is fire-and-forget (300 ms after the last
/// `set_json` call); callers that want save-settled guarantees
/// use [`config_store_flush`].
#[flutter_rust_bridge::frb(sync)]
pub fn config_store_set_json(new_json: String) -> Result<(), String> {
    lfs_core::config_store::instance().set_json(&new_json)
}

/// Force any pending state to disk synchronously. Returns the
/// JSON written (or the current snapshot when nothing was
/// pending). Used at app shutdown / test teardown so the last
/// `set_json` is durable.
#[flutter_rust_bridge::frb(sync)]
pub fn config_store_flush() -> Result<Option<String>, String> {
    lfs_core::config_store::instance().flush()
}

/// Drive the debounce loop one tick — caller checks if the
/// pending-flush deadline has passed and flushes if so. Used by
/// the Dart-side periodic ticker (300 ms timer) so the actor
/// doesn't need its own background tokio task. Returns `true`
/// when a flush fired.
#[flutter_rust_bridge::frb(sync)]
pub fn config_store_tick_if_due() -> Result<bool, String> {
    lfs_core::config_store::instance().tick_if_due()
}
