//! FRB adapter for `lfs_core::config::AppConfig` JSON ser/de.
//!
//! Sync — every op is a small JSON parse / serialise + a few enum
//! lookups. Two wire shapes coexist:
//!
//! - **JSON-string payloads** for legacy seams (export composer,
//!   migration runner, hand-written `config.json` round-trips). The
//!   `_to_json` / `_from_json` shims keep the bytes-on-the-wire
//!   stable so a future field bump lands inside `lfs_core` without
//!   re-generating bindings.
//! - **Typed `DbAppConfigSnapshot` mirror** — every consumer that reads the
//!   parsed shape (Dart `AppConfig` provider, settings UI, in-memory
//!   diffs) routes through this so the Dart side never re-implements
//!   the JSON grammar.

use lfs_core::config::{
    AppConfig, BehaviorConfig, LogLevel as CoreLogLevel, SshDefaults, SyncConfig, TerminalConfig,
    UiConfig,
};

use crate::api::frb_err;
use crate::api::security_capabilities::DbSecurityCapabilities;
use crate::api::security_config::DbSecurityConfig;
use crate::api::sync::DbSyncConfig;

/// Terminal display mirror. Field-for-field copy of
/// [`lfs_core::config::TerminalConfig`]; FRB codegen emits this as a
/// plain Dart class so the parsed shape crosses the boundary without
/// a `Map<String, dynamic>` round-trip.
#[derive(Debug, Clone)]
pub struct DbTerminalConfig {
    pub font_size: f64,
    pub theme: String,
    pub scrollback: i64,
}

impl From<TerminalConfig> for DbTerminalConfig {
    fn from(c: TerminalConfig) -> Self {
        Self {
            font_size: c.font_size,
            theme: c.theme,
            scrollback: c.scrollback,
        }
    }
}

impl From<DbTerminalConfig> for TerminalConfig {
    fn from(c: DbTerminalConfig) -> Self {
        Self {
            font_size: c.font_size,
            theme: c.theme,
            scrollback: c.scrollback,
        }
    }
}

/// SSH defaults mirror. Field-for-field copy of
/// [`lfs_core::config::SshDefaults`].
#[derive(Debug, Clone)]
pub struct DbSshDefaults {
    pub keepalive_sec: i64,
    pub default_port: i64,
    pub ssh_timeout_sec: i64,
    pub verbose_connection_log: bool,
}

impl From<SshDefaults> for DbSshDefaults {
    fn from(c: SshDefaults) -> Self {
        Self {
            keepalive_sec: c.keepalive_sec,
            default_port: c.default_port,
            ssh_timeout_sec: c.ssh_timeout_sec,
            verbose_connection_log: c.verbose_connection_log,
        }
    }
}

impl From<DbSshDefaults> for SshDefaults {
    fn from(c: DbSshDefaults) -> Self {
        Self {
            keepalive_sec: c.keepalive_sec,
            default_port: c.default_port,
            ssh_timeout_sec: c.ssh_timeout_sec,
            verbose_connection_log: c.verbose_connection_log,
        }
    }
}

/// UI / window mirror. Field-for-field copy of
/// [`lfs_core::config::UiConfig`].
#[derive(Debug, Clone)]
pub struct DbUiConfig {
    pub toast_duration_ms: i64,
    pub window_width: f64,
    pub window_height: f64,
    pub ui_scale: f64,
    pub show_folder_sizes: bool,
}

impl From<UiConfig> for DbUiConfig {
    fn from(c: UiConfig) -> Self {
        Self {
            toast_duration_ms: c.toast_duration_ms,
            window_width: c.window_width,
            window_height: c.window_height,
            ui_scale: c.ui_scale,
            show_folder_sizes: c.show_folder_sizes,
        }
    }
}

impl From<DbUiConfig> for UiConfig {
    fn from(c: DbUiConfig) -> Self {
        Self {
            toast_duration_ms: c.toast_duration_ms,
            window_width: c.window_width,
            window_height: c.window_height,
            ui_scale: c.ui_scale,
            show_folder_sizes: c.show_folder_sizes,
        }
    }
}

/// Behaviour mirror — log level + update-check + skipped version
/// + the FIDO2 "prefer direct HID" Settings toggle.
///
/// `log_level` rides across as `Option<String>` (wire-name) — the
/// Dart codegen can't import the Rust-side `LogLevel` enum directly
/// without pulling the enum into FRB. The wire-name is the same set
/// the JSON envelope uses (`info` / `warn` / `error`); both Dart
/// and Rust resolve the string the same way (Rust via
/// `LogLevel::from_wire_name`, Dart via `logLevelFromJson`).
#[derive(Debug, Clone)]
pub struct DbBehaviorConfig {
    pub log_level_wire_name: Option<String>,
    pub check_updates_on_start: bool,
    pub skipped_version: Option<String>,
    pub fido2_prefer_direct_hid: bool,
}

impl From<BehaviorConfig> for DbBehaviorConfig {
    fn from(c: BehaviorConfig) -> Self {
        Self {
            log_level_wire_name: c.log_level.map(|l| l.wire_name().to_string()),
            check_updates_on_start: c.check_updates_on_start,
            skipped_version: c.skipped_version,
            fido2_prefer_direct_hid: c.fido2_prefer_direct_hid,
        }
    }
}

impl From<DbBehaviorConfig> for BehaviorConfig {
    fn from(c: DbBehaviorConfig) -> Self {
        Self {
            log_level: c
                .log_level_wire_name
                .as_deref()
                .and_then(CoreLogLevel::from_wire_name),
            check_updates_on_start: c.check_updates_on_start,
            skipped_version: c.skipped_version,
            fido2_prefer_direct_hid: c.fido2_prefer_direct_hid,
        }
    }
}

/// Typed FRB mirror of [`lfs_core::config::AppConfig`]. Every
/// persisted preference field crosses the boundary in its parsed
/// shape so the Dart side never reconstructs the grammar — the
/// `_get_typed` / `_set_typed` endpoints are the canonical reader
/// + writer for the in-memory snapshot.
///
/// Wire shape on disk stays JSON (`config.json` keys identical to
/// the Rust-side `to_json_value` output) — the disk format is owned
/// by [`AppConfig::to_json_value`] / [`AppConfig::from_json_value`]
/// inside `lfs_core`; this struct carries the parsed values, not
/// the file format.
#[derive(Debug, Clone)]
pub struct DbAppConfigSnapshot {
    pub terminal: DbTerminalConfig,
    pub ssh: DbSshDefaults,
    pub ui: DbUiConfig,
    pub behavior: DbBehaviorConfig,
    pub transfer_workers: i64,
    pub max_history: i64,
    pub locale: Option<String>,
    /// `None` until the wizard has run — the Dart cold-start path
    /// keys off this to decide between "first launch" vs "resume".
    pub security: Option<DbSecurityConfig>,
    /// Cached `securityCapabilitiesProvider` snapshot. `None` until
    /// a probe runs or after a Recheck-button invalidation.
    pub security_probe_cache: Option<DbSecurityCapabilities>,
    pub recordings_storage_cap_bytes: u64,
    pub sync: DbSyncConfig,
}

impl From<AppConfig> for DbAppConfigSnapshot {
    fn from(c: AppConfig) -> Self {
        Self {
            terminal: c.terminal.into(),
            ssh: c.ssh.into(),
            ui: c.ui.into(),
            behavior: c.behavior.into(),
            transfer_workers: c.transfer_workers,
            max_history: c.max_history,
            locale: c.locale,
            security: c.security.map(|s| DbSecurityConfig {
                tier: s.tier.into(),
                password: s.modifiers.password,
                biometric: s.modifiers.biometric,
            }),
            security_probe_cache: c.security_probe_cache.map(DbSecurityCapabilities::from),
            recordings_storage_cap_bytes: c.recordings_storage_cap_bytes,
            sync: c.sync.into(),
        }
    }
}

impl From<DbAppConfigSnapshot> for AppConfig {
    fn from(c: DbAppConfigSnapshot) -> Self {
        let security = c.security.map(|s| lfs_core::security::SecurityConfig {
            tier: s.tier.into(),
            modifiers: lfs_core::security::SecurityTierModifiers {
                password: s.password,
                biometric: s.biometric,
            },
        });
        Self {
            terminal: c.terminal.into(),
            ssh: c.ssh.into(),
            ui: c.ui.into(),
            behavior: c.behavior.into(),
            transfer_workers: c.transfer_workers,
            max_history: c.max_history,
            locale: c.locale,
            security,
            security_probe_cache: c.security_probe_cache.map(Into::into),
            recordings_storage_cap_bytes: c.recordings_storage_cap_bytes,
            sync: SyncConfig::from(c.sync),
        }
        .sanitized()
    }
}

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
    let value: serde_json::Value = serde_json::from_str(&input_json)
        .map_err(|e| frb_err::wire(frb_err::kind::GENERIC, &format!("AppConfig: parse: {e}")))?;
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
    let value: serde_json::Value = serde_json::from_str(&input_json).map_err(|e| {
        frb_err::wire(
            frb_err::kind::GENERIC,
            &format!("AppConfig sanitize: parse: {e}"),
        )
    })?;
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
    let mut value: serde_json::Value = serde_json::from_str(&input_json).map_err(|e| {
        frb_err::wire(
            frb_err::kind::GENERIC,
            &format!("AppConfig export: parse: {e}"),
        )
    })?;
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
/// Wires four actors in a load-bearing order:
///   1. [`lfs_core::security::master_password::pin_support_dir`]
///      — pin the process-singleton support-dir so every other
///      FRB endpoint that needs `<support_dir>/...` paths
///      (master_password, hardware vault wizard probe, recorder
///      browser root, update cleanup) resolves through one
///      canonical accessor. `OnceLock` first wins; subsequent
///      calls under the same path are no-ops.
///   2. [`lfs_core::config_store::Store::init`] — populate the
///      in-memory snapshot from disk so the actor's update calls
///      have somewhere to land.
///   3. [`lfs_core::config_store::start_background_ticker`] —
///      drive the debounced atomic write so partial-update
///      calls (sync, security probe cache) flush within
///      `DEBOUNCE`.
///   4. [`lfs_core::security::capabilities_persister::start`] —
///      subscribe to `Event::SecurityCapabilitiesChanged` and
///      mirror every fresh snapshot back into the
///      `security_probe_cache` slot of `config.json`. Must
///      attach AFTER the store init so its update calls don't
///      hit the "not initialised" branch, and BEFORE the
///      capabilities orchestrator runs its first probe so no
///      startup snapshot evaporates on the broadcast channel.
#[flutter_rust_bridge::frb(sync)]
pub fn config_store_init(support_dir: String) -> Result<String, String> {
    let dir = std::path::PathBuf::from(support_dir);
    lfs_core::security::master_password::pin_support_dir(dir.clone());
    let json = lfs_core::config_store::instance().init(dir)?;
    lfs_core::config_store::start_background_ticker();
    lfs_core::security::capabilities_persister::start();
    Ok(json)
}

/// Snapshot the actor's current config. Returns `None` before
/// `config_store_init` runs; callers treat that as "use defaults
/// until startup init lands".
#[flutter_rust_bridge::frb(sync)]
pub fn config_store_get_json() -> Option<String> {
    lfs_core::config_store::instance().get_json()
}

/// True when the most recent `config_store_init` adopted an
/// existing `<support_dir>/config.json` from disk; false when
/// the file was absent or unreadable and the actor seeded
/// defaults instead. The Dart cold-start path reads this to set
/// `LoadedAppConfig.loadedFromFile` without a separate Dart-side
/// `File.exists` probe — keeps the load route single-source-of-
/// truth (Rust owns persistent state, Dart consumes).
///
/// Returns false before any `config_store_init` call lands;
/// callers only read this immediately after init, so the pre-init
/// value is structurally unreachable.
#[flutter_rust_bridge::frb(sync)]
pub fn config_store_was_loaded_from_disk() -> bool {
    lfs_core::config_store::instance().was_loaded_from_disk()
}

/// Replace the in-memory state and arm the debounce timer. The
/// disk write is fire-and-forget (300 ms after the last
/// `set_json` call); callers that want save-settled guarantees
/// use [`config_store_flush`].
#[flutter_rust_bridge::frb(sync)]
pub fn config_store_set_json(new_json: String) -> Result<(), String> {
    lfs_core::config_store::instance().set_json(&new_json)
}

/// Force any pending state to disk. Returns the JSON written (or
/// the current snapshot when nothing was pending). Used by the
/// debounced settings save + at app shutdown / test teardown so the
/// last `set_json` is durable.
///
/// Async on purpose: `Store::flush` does a synchronous
/// `write_bytes_atomic` (temp + fsync + rename), and on Windows that
/// fsync — plus the AV real-time scan of the new file — can take
/// well over a second. A `#[frb(sync)]` flush ran that on the Dart
/// UI isolate, freezing the interface after every settings change
/// (most visibly on a language switch). Parking the write on
/// `spawn_blocking` keeps the UI isolate responsive; the background
/// ticker remains the steady-state persister.
pub async fn config_store_flush() -> Result<Option<String>, String> {
    tokio::task::spawn_blocking(|| lfs_core::config_store::instance().flush())
        .await
        .map_err(|e| {
            frb_err::wire(
                frb_err::kind::GENERIC,
                &format!("config_store_flush join: {e}"),
            )
        })?
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

/// Typed snapshot of the live `AppConfig`. Returns `None` before
/// [`config_store_init`] runs (cold-start window) — the caller
/// falls through to defaults until init lands. Same data
/// [`config_store_get_json`] surfaces but routed in the parsed
/// shape so the Dart side never re-implements the JSON grammar.
#[flutter_rust_bridge::frb(sync)]
pub fn config_store_get_typed() -> Option<DbAppConfigSnapshot> {
    lfs_core::config_store::instance()
        .get_app_config()
        .map(Into::into)
}

/// Replace the live `AppConfig` with the typed value and arm the
/// debounce timer. Round-trips through the canonical
/// [`AppConfig::sanitized`] step so out-of-range fields (slider
/// drag past the clamp, hand-edited DTO) land back inside the
/// allowed range before the disk write fires.
#[flutter_rust_bridge::frb(sync)]
pub fn config_store_set_typed(value: DbAppConfigSnapshot) -> Result<(), String> {
    let cfg = AppConfig::from(value);
    lfs_core::config_store::instance().set_json(&cfg.to_json_value().to_string())
}

/// Typed default `AppConfig` — every field at its baked-in
/// default. Used by the Dart cold-start seam to initialise a
/// notifier before the store actor publishes a snapshot.
#[flutter_rust_bridge::frb(sync)]
pub fn config_app_config_defaults_typed() -> DbAppConfigSnapshot {
    AppConfig::default().into()
}

/// Strip every per-host security field from the typed value, then
/// return the trimmed JSON string the `.lfs` archive exporter
/// embeds. Same shape [`config_app_config_strip_for_export`]
/// returns but accepts the typed mirror so the caller skips a
/// `jsonEncode` step.
#[flutter_rust_bridge::frb(sync)]
pub fn config_app_config_strip_for_export_typed(value: DbAppConfigSnapshot) -> String {
    let cfg = AppConfig::from(value);
    let mut json = cfg.to_json_value();
    lfs_core::config::strip_for_export(&mut json);
    json.to_string()
}

/// Encode the typed value as the canonical JSON the disk format
/// uses. Mirror of [`config_app_config_to_json`] but accepts the
/// typed mirror — used by the QR composer + the archive size
/// preview, which want the on-wire shape (`security_tier` /
/// `security_modifiers` / `security_probe_cache` / per-host sync
/// state included) rather than the export-stripped shape.
#[flutter_rust_bridge::frb(sync)]
pub fn config_app_config_to_json_typed(value: DbAppConfigSnapshot) -> String {
    let cfg = AppConfig::from(value);
    cfg.to_json_value().to_string()
}

/// Parse a canonical-JSON config blob (the shape an `.lfs` apply
/// driver hands back in `DbApplyResult.config_json`, or the bytes
/// `config.json` carries on disk) into the typed mirror. Returns
/// `None` for a malformed shape (non-object root, syntax error)
/// so the caller can route the failure to the fatal-error screen
/// rather than silently picking defaults. Sanitisation runs
/// inside [`AppConfig::from_json_value`] before the conversion to
/// the typed mirror.
#[flutter_rust_bridge::frb(sync)]
pub fn config_app_config_from_json_typed(input_json: String) -> Option<DbAppConfigSnapshot> {
    let value: serde_json::Value = serde_json::from_str(&input_json).ok()?;
    Some(AppConfig::from_json_value(&value).into())
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

    #[test]
    fn db_app_config_round_trips_through_core_appconfig() {
        // The typed mirror must survive a full Db → Core → Db
        // round-trip without losing any field. Pins the From-impl
        // contract — a future field added to one side without the
        // other becomes a compile-time error here.
        let cfg = AppConfig::default();
        let db: DbAppConfigSnapshot = cfg.clone().into();
        let back: AppConfig = db.into();
        assert_eq!(back, cfg);
    }

    #[test]
    fn db_app_config_security_tier_wire_round_trips() {
        use lfs_core::security::{SecurityConfig, SecurityTier, SecurityTierModifiers};
        let cfg = AppConfig {
            security: Some(SecurityConfig {
                tier: SecurityTier::Hardware,
                modifiers: SecurityTierModifiers {
                    password: true,
                    biometric: false,
                },
            }),
            ..AppConfig::default()
        };
        let db: DbAppConfigSnapshot = cfg.clone().into();
        let back: AppConfig = db.into();
        assert_eq!(back.security, cfg.security);
    }

    #[test]
    fn db_app_config_strip_for_export_typed_drops_per_host_fields() {
        // Mirror of the JSON-string `strip_for_export` test — the
        // typed variant must drop the same per-host keys before the
        // bytes land inside an `.lfs` archive.
        use lfs_core::security::{SecurityConfig, SecurityTier, SecurityTierModifiers};
        let cfg = AppConfig {
            security: Some(SecurityConfig {
                tier: SecurityTier::Keychain,
                modifiers: SecurityTierModifiers::default(),
            }),
            ..AppConfig::default()
        };
        let db: DbAppConfigSnapshot = cfg.into();
        let stripped = config_app_config_strip_for_export_typed(db);
        let value: serde_json::Value = serde_json::from_str(&stripped).expect("valid JSON");
        let obj = value.as_object().expect("object root");
        assert!(!obj.contains_key("security_tier"));
        assert!(!obj.contains_key("security_modifiers"));
        assert!(!obj.contains_key("config_schema_version"));
        assert!(obj.contains_key("font_size"));
    }

    #[test]
    fn db_app_config_defaults_typed_matches_core_defaults() {
        let db = config_app_config_defaults_typed();
        let cfg = AppConfig::from(db);
        assert_eq!(cfg, AppConfig::default());
    }

    #[test]
    fn db_app_config_behavior_log_level_wire_name_round_trips() {
        let cfg = AppConfig {
            behavior: BehaviorConfig {
                log_level: Some(CoreLogLevel::Warn),
                check_updates_on_start: false,
                skipped_version: Some("1.2.3".into()),
                fido2_prefer_direct_hid: true,
            },
            ..AppConfig::default()
        };
        let db: DbAppConfigSnapshot = cfg.clone().into();
        assert_eq!(db.behavior.log_level_wire_name.as_deref(), Some("warn"));
        let back: AppConfig = db.into();
        assert_eq!(back.behavior, cfg.behavior);
    }
}
