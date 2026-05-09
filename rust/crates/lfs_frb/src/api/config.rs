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

#[cfg(test)]
mod tests {
    use super::*;

    // The store-actor endpoints (`config_store_init` /
    // `config_store_get_json` / `_set_json` / `_flush` / `_tick_if_due`)
    // route through `lfs_core::config_store::instance()` — covered by
    // the Dart `config_store_test.dart` integration suite under a
    // tempdir + manual ticker. The standalone tests below pin the
    // pure JSON ser/de helpers that round-trip through `AppConfig`.

    #[test]
    fn defaults_json_decodes_back_into_appconfig() {
        let json = config_app_config_defaults_json();
        // Round-trip — the canonical JSON the cold-start writer
        // emits must be parseable by the validator.
        assert!(config_app_config_validate_json(json.clone()).is_none());
        // Re-encode through to_json must yield byte-identical bytes
        // (idempotent canonicalisation).
        let re = config_app_config_to_json(json.clone()).expect("re-encode");
        assert_eq!(re, json);
    }

    #[test]
    fn validate_json_returns_none_for_default_config() {
        let defaults = config_app_config_defaults_json();
        assert!(config_app_config_validate_json(defaults).is_none());
    }

    #[test]
    fn validate_json_returns_none_for_garbage_input() {
        // Pure parse-failure paths return None (the validator only
        // surfaces field-validation errors). The Dart caller
        // distinguishes via the load-time pre-parse step.
        assert!(config_app_config_validate_json("not json".into()).is_none());
    }

    #[test]
    fn sanitize_json_clamps_invalid_input_back_to_valid() {
        // Hand a config with an out-of-range terminal scrollback
        // (a hand-edited file or a pre-Phase-F drift); the
        // sanitiser must yield a JSON the validator accepts.
        let pathological = r#"{"terminal_scrollback": -999, "ssh_timeout_sec": -1}"#;
        let sanitized = config_app_config_sanitize_json(pathological.into()).expect("sanitize");
        assert!(
            config_app_config_validate_json(sanitized).is_none(),
            "sanitised output must validate clean"
        );
    }

    #[test]
    fn strip_for_export_drops_tier_field() {
        // The `.lfs` archive exporter routes through
        // `strip_for_export` so the importing host re-runs the
        // wizard rather than adopting the exporter's tier. Pin
        // that the per-host security fields are removed from the
        // JSON output.
        let with_tier = r#"{"security_tier": "keychain", "terminal_scrollback": 5000}"#;
        let stripped = config_app_config_strip_for_export(with_tier.into()).expect("strip");
        assert!(
            !stripped.contains("security_tier"),
            "stripped output must not carry security_tier"
        );
    }

    #[test]
    fn supported_locales_includes_every_arb_bundle_locale() {
        // Pin the locale set against the documented arb bundle
        // family. Dropping a locale here would break the Settings
        // dropdown without the validator catching it.
        let locales = config_supported_locales();
        for code in ["en", "de", "es", "fr", "pt"] {
            assert!(
                locales.iter().any(|c| c == code),
                "locale {code} must be in supported set"
            );
        }
    }

    #[test]
    fn to_json_returns_err_for_garbage_input() {
        let res = config_app_config_to_json("not json".into());
        assert!(res.is_err());
    }
}
