//! Typed mirror of the Dart-side `AppConfig` schema.
//!
//! Owns every persisted preference — terminal display, SSH defaults,
//! UI / window, behaviour (logging + update check), plus the
//! security-tier composite + the per-host `SecurityCapabilities`
//! probe cache. Mirror of `lib/core/config/app_config.dart`
//! field-for-field with the same JSON wire shape.
//!
//! **Why land the typed scaffold ahead of the actor.** Every other
//! actor under `lfs_core` that reads or writes config (tier
//! machine, transfer scheduler, recorder cap) wants the same typed
//! struct. Landing the mirror with JSON ser/de + sanitise lets the
//! Dart `AppConfig` route through the canonical encoder without
//! waiting on a `Store` actor; future arcs lift the persistence
//! layer (`config_store.dart`) into Rust on top of this scaffold.
//!
//! **Wire format invariants (load-bearing — drift = breaks every
//! install's `config.json`):**
//!
//! - JSON stays flat at the top level — sub-structs flatten their
//!   fields into the outer object so `terminal.theme` lands as
//!   `"theme"`, not `"terminal.theme"`. Same shape Dart's
//!   `AppConfig.toJson` writes via `...subStruct.toJson()`.
//! - Empty / default values are still emitted (no
//!   `if (x != default)` skip) — `Dart.copyWith` consumers expect
//!   to read the value back.
//! - `log_level` only appears when non-null (logging off = absent
//!   key).
//! - `security_tier` + `security_modifiers` only appear when the
//!   wizard has run.
//! - `locale` appears only when set.

use serde_json::{json, Value};

use crate::security::{capabilities::SecurityCapabilities, SecurityConfig, SecurityTier};

/// Terminal display settings. Mirror of Dart `TerminalConfig`.
#[derive(Debug, Clone, PartialEq)]
pub struct TerminalConfig {
    pub font_size: f64,
    /// `dark` / `light` / `system`.
    pub theme: String,
    pub scrollback: i64,
}

impl Default for TerminalConfig {
    fn default() -> Self {
        Self {
            font_size: 14.0,
            theme: "system".into(),
            scrollback: 5000,
        }
    }
}

const VALID_THEMES: &[&str] = &["dark", "light", "system"];

impl TerminalConfig {
    /// Validate config values, returning an English error message
    /// when invalid or `None` when every field is within range.
    /// Mirrors the Dart `validate()` method byte-for-byte; the
    /// returned strings are translated UI-side via the
    /// `app_*.arb` bundles' validation keys.
    pub fn validate(&self) -> Option<&'static str> {
        if !(6.0..=72.0).contains(&self.font_size) {
            return Some("Font size must be 6-72");
        }
        if !VALID_THEMES.contains(&self.theme.as_str()) {
            return Some("Theme must be one of: dark, light, system");
        }
        if self.scrollback < 100 {
            return Some("Scrollback must be at least 100");
        }
        None
    }

    /// Clamp / replace out-of-range values with defaults. Mirrors
    /// the Dart `sanitized()` rules byte-for-byte: font in `[6, 72]`,
    /// theme in the allow-list, scrollback floor at 100.
    #[must_use]
    pub fn sanitized(self) -> Self {
        let d = Self::default();
        Self {
            font_size: self.font_size.clamp(6.0, 72.0),
            theme: if VALID_THEMES.contains(&self.theme.as_str()) {
                self.theme
            } else {
                d.theme
            },
            scrollback: if self.scrollback < 100 {
                d.scrollback
            } else {
                self.scrollback
            },
        }
    }

    pub fn to_json_object(&self) -> serde_json::Map<String, Value> {
        let mut m = serde_json::Map::new();
        m.insert("font_size".into(), json!(self.font_size));
        m.insert("theme".into(), json!(self.theme));
        m.insert("scrollback".into(), json!(self.scrollback));
        m
    }

    pub fn from_json_object(json: &serde_json::Map<String, Value>) -> Self {
        let d = Self::default();
        Self {
            font_size: json
                .get("font_size")
                .and_then(|v| v.as_f64())
                .unwrap_or(d.font_size),
            theme: json
                .get("theme")
                .and_then(|v| v.as_str())
                .map(String::from)
                .unwrap_or(d.theme),
            scrollback: json
                .get("scrollback")
                .and_then(|v| v.as_i64())
                .unwrap_or(d.scrollback),
        }
        .sanitized()
    }
}

/// SSH connection defaults. Mirror of Dart `SshDefaults`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct SshDefaults {
    pub keepalive_sec: i64,
    pub default_port: i64,
    pub ssh_timeout_sec: i64,
}

impl Default for SshDefaults {
    fn default() -> Self {
        Self {
            keepalive_sec: 30,
            default_port: 22,
            ssh_timeout_sec: 10,
        }
    }
}

impl SshDefaults {
    /// Validate. Mirrors Dart `validate()`.
    pub fn validate(&self) -> Option<&'static str> {
        if self.keepalive_sec < 0 {
            return Some("Keep-alive must be non-negative");
        }
        if !(1..=65_535).contains(&self.default_port) {
            return Some("Port must be 1-65535");
        }
        if self.ssh_timeout_sec < 1 {
            return Some("SSH timeout must be at least 1 second");
        }
        None
    }

    #[must_use]
    pub fn sanitized(self) -> Self {
        let d = Self::default();
        Self {
            keepalive_sec: if self.keepalive_sec < 0 {
                d.keepalive_sec
            } else {
                self.keepalive_sec
            },
            default_port: if !(1..=65_535).contains(&self.default_port) {
                d.default_port
            } else {
                self.default_port
            },
            ssh_timeout_sec: if self.ssh_timeout_sec < 1 {
                d.ssh_timeout_sec
            } else {
                self.ssh_timeout_sec
            },
        }
    }

    pub fn to_json_object(&self) -> serde_json::Map<String, Value> {
        let mut m = serde_json::Map::new();
        m.insert("keepalive_sec".into(), json!(self.keepalive_sec));
        m.insert("default_port".into(), json!(self.default_port));
        m.insert("ssh_timeout_sec".into(), json!(self.ssh_timeout_sec));
        m
    }

    pub fn from_json_object(json: &serde_json::Map<String, Value>) -> Self {
        let d = Self::default();
        Self {
            keepalive_sec: json
                .get("keepalive_sec")
                .and_then(|v| v.as_i64())
                .unwrap_or(d.keepalive_sec),
            default_port: json
                .get("default_port")
                .and_then(|v| v.as_i64())
                .unwrap_or(d.default_port),
            ssh_timeout_sec: json
                .get("ssh_timeout_sec")
                .and_then(|v| v.as_i64())
                .unwrap_or(d.ssh_timeout_sec),
        }
        .sanitized()
    }
}

/// UI / window settings. Mirror of Dart `UiConfig`.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct UiConfig {
    pub toast_duration_ms: i64,
    pub window_width: f64,
    pub window_height: f64,
    pub ui_scale: f64,
    pub show_folder_sizes: bool,
}

impl Default for UiConfig {
    fn default() -> Self {
        Self {
            toast_duration_ms: 4000,
            window_width: 1100.0,
            window_height: 650.0,
            ui_scale: 1.0,
            show_folder_sizes: false,
        }
    }
}

impl UiConfig {
    /// Validate. Mirrors Dart `validate()`.
    pub fn validate(&self) -> Option<&'static str> {
        if self.toast_duration_ms < 500 {
            return Some("Toast duration must be at least 500ms");
        }
        if self.window_width < 200.0 {
            return Some("Window width must be at least 200");
        }
        if self.window_height < 200.0 {
            return Some("Window height must be at least 200");
        }
        if !(0.5..=2.0).contains(&self.ui_scale) {
            return Some("UI scale must be 0.5-2.0");
        }
        None
    }

    #[must_use]
    pub fn sanitized(self) -> Self {
        let d = Self::default();
        Self {
            toast_duration_ms: if self.toast_duration_ms < 500 {
                d.toast_duration_ms
            } else {
                self.toast_duration_ms
            },
            window_width: if self.window_width < 200.0 {
                d.window_width
            } else {
                self.window_width
            },
            window_height: if self.window_height < 200.0 {
                d.window_height
            } else {
                self.window_height
            },
            ui_scale: self.ui_scale.clamp(0.5, 2.0),
            show_folder_sizes: self.show_folder_sizes,
        }
    }

    pub fn to_json_object(&self) -> serde_json::Map<String, Value> {
        let mut m = serde_json::Map::new();
        m.insert("toast_duration_ms".into(), json!(self.toast_duration_ms));
        m.insert("window_width".into(), json!(self.window_width));
        m.insert("window_height".into(), json!(self.window_height));
        m.insert("ui_scale".into(), json!(self.ui_scale));
        m.insert("show_folder_sizes".into(), json!(self.show_folder_sizes));
        m
    }

    pub fn from_json_object(json: &serde_json::Map<String, Value>) -> Self {
        let d = Self::default();
        Self {
            toast_duration_ms: json
                .get("toast_duration_ms")
                .and_then(|v| v.as_i64())
                .unwrap_or(d.toast_duration_ms),
            window_width: json
                .get("window_width")
                .and_then(|v| v.as_f64())
                .unwrap_or(d.window_width),
            window_height: json
                .get("window_height")
                .and_then(|v| v.as_f64())
                .unwrap_or(d.window_height),
            ui_scale: json
                .get("ui_scale")
                .and_then(|v| v.as_f64())
                .unwrap_or(d.ui_scale),
            show_folder_sizes: json
                .get("show_folder_sizes")
                .and_then(|v| v.as_bool())
                .unwrap_or(d.show_folder_sizes),
        }
        .sanitized()
    }
}

/// Routine file-sink severity floor. Mirror of Dart `LogLevel`.
/// `None` = logging off (default).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LogLevel {
    Info,
    Warn,
    Error,
}

impl LogLevel {
    pub fn wire_name(self) -> &'static str {
        match self {
            LogLevel::Info => "info",
            LogLevel::Warn => "warn",
            LogLevel::Error => "error",
        }
    }

    pub fn from_wire_name(s: &str) -> Option<Self> {
        match s {
            "info" => Some(LogLevel::Info),
            "warn" => Some(LogLevel::Warn),
            "error" => Some(LogLevel::Error),
            _ => None,
        }
    }
}

/// App behaviour: logging + update-check + skipped version.
/// Mirror of Dart `BehaviorConfig`. Auto-lock timeout lives in
/// the encrypted DB, not here.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BehaviorConfig {
    pub log_level: Option<LogLevel>,
    pub check_updates_on_start: bool,
    pub skipped_version: Option<String>,
}

impl Default for BehaviorConfig {
    fn default() -> Self {
        Self {
            log_level: None,
            check_updates_on_start: true,
            skipped_version: None,
        }
    }
}

impl BehaviorConfig {
    pub fn to_json_object(&self) -> serde_json::Map<String, Value> {
        let mut m = serde_json::Map::new();
        if let Some(l) = self.log_level {
            m.insert("log_level".into(), json!(l.wire_name()));
        }
        m.insert(
            "check_updates_on_start".into(),
            json!(self.check_updates_on_start),
        );
        if let Some(ref v) = self.skipped_version {
            m.insert("skipped_version".into(), json!(v));
        }
        m
    }

    pub fn from_json_object(json: &serde_json::Map<String, Value>) -> Self {
        let d = Self::default();
        Self {
            log_level: json
                .get("log_level")
                .and_then(|v| v.as_str())
                .and_then(LogLevel::from_wire_name)
                .or(d.log_level),
            check_updates_on_start: json
                .get("check_updates_on_start")
                .and_then(|v| v.as_bool())
                .unwrap_or(d.check_updates_on_start),
            skipped_version: json
                .get("skipped_version")
                .and_then(|v| v.as_str())
                .map(String::from),
        }
    }
}

/// Locale codes the app's `app_*.arb` bundles ship for. Same set
/// `AppConfig.supportedLocales` exposes Dart-side; an unknown
/// locale read from `config.json` collapses to `None` so the app
/// falls back to system default.
pub const SUPPORTED_LOCALES: &[&str] = &[
    "en", "ru", "zh", "de", "ja", "pt", "es", "fr", "ko", "ar", "fa", "tr", "vi", "id", "hi",
];

/// Canonical SecretStore id for the WebDAV password / bearer token
/// used by the sync orchestrator. Mirrors the per-session
/// `session.webdav.<id>` convention but uses a singleton slot
/// because the sync surface holds exactly one remote endpoint at a
/// time. Plaintext never lands in `config.json`.
pub const SYNC_PASSWORD_SECRET_ID: &str = "sync.webdav.password";

/// Canonical SecretStore id for the sync passphrase — the secret
/// that encrypts the `.lfs` archive shipped between devices. The
/// UI enforces "must differ from the master password" so a leaked
/// sync passphrase does not unlock the on-disk DB.
pub const SYNC_PASSPHRASE_SECRET_ID: &str = "sync.passphrase";

/// Default remote path the sync orchestrator writes the encrypted
/// archive to under the configured WebDAV base URL.
pub const SYNC_DEFAULT_REMOTE_PATH: &str = "letsflutssh.lfs";

/// WebDAV-backed sync settings. Mirror of Dart `SyncConfig` (the
/// Dart side reads / writes the fields via the FRB `sync_config_*`
/// surface — there is no Dart struct because every consumer that
/// needs the values is Rust-side).
///
/// Plaintext discipline: passwords / passphrases never land here.
/// `webdav_password_ref` and `passphrase_ref` are SecretStore ids
/// pointing into the process-singleton `SecretStore`; the Settings
/// UI stages the plaintext under those ids and `config.json`
/// carries only the ids themselves.
///
/// JSON wire shape (flat at the top level alongside the rest of
/// `AppConfig`, prefixed with `sync_` to avoid collisions):
/// `sync_enabled`, `sync_webdav_url`, `sync_webdav_username`,
/// `sync_webdav_password_ref`, `sync_webdav_auth_method`,
/// `sync_passphrase_ref`, `sync_remote_path`,
/// `sync_last_pushed_at_ms`, `sync_last_pulled_at_ms`,
/// `sync_last_pushed_sha256`, `sync_last_pushed_etag`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SyncConfig {
    pub enabled: bool,
    pub webdav_url: String,
    pub webdav_username: String,
    /// SecretStore id holding the WebDAV password / bearer token.
    /// Default [`SYNC_PASSWORD_SECRET_ID`]; never plaintext in JSON.
    pub webdav_password_ref: String,
    /// One of `basic` / `digest` / `bearer`. Unknown values fall
    /// through to `basic` on sanitise.
    pub webdav_auth_method: String,
    /// SecretStore id holding the sync passphrase. Default
    /// [`SYNC_PASSPHRASE_SECRET_ID`]. MUST differ semantically from
    /// the master password — the Settings UI enforces this and the
    /// orchestrator surfaces a typed error when the staged
    /// passphrase matches the master password's wrapping value.
    pub passphrase_ref: String,
    /// Remote path under the WebDAV base URL where the archive
    /// lands. Default [`SYNC_DEFAULT_REMOTE_PATH`].
    pub remote_path: String,
    /// Last successful push timestamp (unix ms). `0` = never pushed.
    pub last_pushed_at_ms: i64,
    /// Last successful pull timestamp (unix ms). `0` = never pulled.
    pub last_pulled_at_ms: i64,
    /// SHA-256 (lowercase hex) of the archive plaintext bytes the
    /// last successful push produced. Used to skip a push when the
    /// local state hasn't changed since the previous one.
    pub last_pushed_sha256: String,
    /// Server-supplied ETag from the last successful push. Used to
    /// stamp `If-Match` on the next push so a peer device cannot
    /// overwrite a more recent remote without observing the change
    /// first.
    pub last_pushed_etag: String,
}

const SYNC_VALID_AUTH_METHODS: &[&str] = &["basic", "digest", "bearer"];

impl Default for SyncConfig {
    fn default() -> Self {
        Self {
            enabled: false,
            webdav_url: String::new(),
            webdav_username: String::new(),
            webdav_password_ref: SYNC_PASSWORD_SECRET_ID.to_string(),
            webdav_auth_method: "basic".to_string(),
            passphrase_ref: SYNC_PASSPHRASE_SECRET_ID.to_string(),
            remote_path: SYNC_DEFAULT_REMOTE_PATH.to_string(),
            last_pushed_at_ms: 0,
            last_pulled_at_ms: 0,
            last_pushed_sha256: String::new(),
            last_pushed_etag: String::new(),
        }
    }
}

impl SyncConfig {
    /// Replace malformed wire values with safe defaults. Empty
    /// `webdav_url` is fine — the orchestrator surfaces "url not
    /// configured" via [`crate::error::Error::WebDav`] at push /
    /// pull time so the Settings UI can render the message; a
    /// URL-parse failure on a non-empty value is also left for the
    /// orchestrator to surface (the user types in the field, the
    /// only signal we have at parse time is that the field is
    /// non-empty).
    #[must_use]
    pub fn sanitized(self) -> Self {
        let d = Self::default();
        Self {
            enabled: self.enabled,
            webdav_url: self.webdav_url,
            webdav_username: self.webdav_username,
            webdav_password_ref: if self.webdav_password_ref.is_empty() {
                d.webdav_password_ref
            } else {
                self.webdav_password_ref
            },
            webdav_auth_method: if SYNC_VALID_AUTH_METHODS
                .contains(&self.webdav_auth_method.as_str())
            {
                self.webdav_auth_method
            } else {
                d.webdav_auth_method
            },
            passphrase_ref: if self.passphrase_ref.is_empty() {
                d.passphrase_ref
            } else {
                self.passphrase_ref
            },
            remote_path: if self.remote_path.is_empty() {
                d.remote_path
            } else {
                self.remote_path
            },
            last_pushed_at_ms: self.last_pushed_at_ms.max(0),
            last_pulled_at_ms: self.last_pulled_at_ms.max(0),
            last_pushed_sha256: self.last_pushed_sha256,
            last_pushed_etag: self.last_pushed_etag,
        }
    }

    pub fn to_json_object(&self) -> serde_json::Map<String, Value> {
        let mut m = serde_json::Map::new();
        m.insert("sync_enabled".into(), json!(self.enabled));
        m.insert("sync_webdav_url".into(), json!(self.webdav_url));
        m.insert("sync_webdav_username".into(), json!(self.webdav_username));
        m.insert(
            "sync_webdav_password_ref".into(),
            json!(self.webdav_password_ref),
        );
        m.insert(
            "sync_webdav_auth_method".into(),
            json!(self.webdav_auth_method),
        );
        m.insert("sync_passphrase_ref".into(), json!(self.passphrase_ref));
        m.insert("sync_remote_path".into(), json!(self.remote_path));
        m.insert(
            "sync_last_pushed_at_ms".into(),
            json!(self.last_pushed_at_ms),
        );
        m.insert(
            "sync_last_pulled_at_ms".into(),
            json!(self.last_pulled_at_ms),
        );
        m.insert(
            "sync_last_pushed_sha256".into(),
            json!(self.last_pushed_sha256),
        );
        m.insert("sync_last_pushed_etag".into(), json!(self.last_pushed_etag));
        m
    }

    pub fn from_json_object(json: &serde_json::Map<String, Value>) -> Self {
        let d = Self::default();
        Self {
            enabled: json
                .get("sync_enabled")
                .and_then(|v| v.as_bool())
                .unwrap_or(d.enabled),
            webdav_url: json
                .get("sync_webdav_url")
                .and_then(|v| v.as_str())
                .map(String::from)
                .unwrap_or(d.webdav_url),
            webdav_username: json
                .get("sync_webdav_username")
                .and_then(|v| v.as_str())
                .map(String::from)
                .unwrap_or(d.webdav_username),
            webdav_password_ref: json
                .get("sync_webdav_password_ref")
                .and_then(|v| v.as_str())
                .map(String::from)
                .unwrap_or(d.webdav_password_ref),
            webdav_auth_method: json
                .get("sync_webdav_auth_method")
                .and_then(|v| v.as_str())
                .map(String::from)
                .unwrap_or(d.webdav_auth_method),
            passphrase_ref: json
                .get("sync_passphrase_ref")
                .and_then(|v| v.as_str())
                .map(String::from)
                .unwrap_or(d.passphrase_ref),
            remote_path: json
                .get("sync_remote_path")
                .and_then(|v| v.as_str())
                .map(String::from)
                .unwrap_or(d.remote_path),
            last_pushed_at_ms: json
                .get("sync_last_pushed_at_ms")
                .and_then(|v| v.as_i64())
                .unwrap_or(d.last_pushed_at_ms),
            last_pulled_at_ms: json
                .get("sync_last_pulled_at_ms")
                .and_then(|v| v.as_i64())
                .unwrap_or(d.last_pulled_at_ms),
            last_pushed_sha256: json
                .get("sync_last_pushed_sha256")
                .and_then(|v| v.as_str())
                .map(String::from)
                .unwrap_or(d.last_pushed_sha256),
            last_pushed_etag: json
                .get("sync_last_pushed_etag")
                .and_then(|v| v.as_str())
                .map(String::from)
                .unwrap_or(d.last_pushed_etag),
        }
        .sanitized()
    }
}

/// Default byte ceiling for the recordings tree. 500 MiB is large
/// enough to hold months of typical interactive sessions plus a
/// handful of long-running terminal multiplexer dumps, small
/// enough that a forgotten `record-everything` toggle does not eat
/// a laptop's free disk before the user notices. Sweep details:
/// [`crate::recorder::storage_cap::enforce_storage_cap`].
pub const DEFAULT_RECORDINGS_STORAGE_CAP_BYTES: u64 = 500 * 1024 * 1024;

/// Hard ceiling on the configured recordings cap. A user-supplied
/// value above this is treated as a fat-finger error and clamped
/// to the default — there is no realistic scenario where the
/// recordings tree should occupy a terabyte, and an unsanitised
/// `u64::MAX` would silently disable the cap.
const MAX_RECORDINGS_STORAGE_CAP_BYTES: u64 = 1024 * 1024 * 1024 * 1024; // 1 TiB

/// Top-level app configuration. Mirror of Dart `AppConfig`.
///
/// Sub-structs flatten into the JSON object at the same level so
/// the wire format stays stable across the two sides — the same
/// `config.json` round-trips through either encoder.
#[derive(Debug, Clone, PartialEq)]
pub struct AppConfig {
    pub terminal: TerminalConfig,
    pub ssh: SshDefaults,
    pub ui: UiConfig,
    pub behavior: BehaviorConfig,
    pub transfer_workers: i64,
    pub max_history: i64,
    pub locale: Option<String>,
    pub security: Option<SecurityConfig>,
    pub security_probe_cache: Option<SecurityCapabilities>,
    /// Aggregate byte ceiling for the recordings tree. The
    /// recorder's `register_with_io` + `close_with_io` hooks call
    /// [`crate::recorder::storage_cap::enforce_storage_cap`] after
    /// every register / close to bring the on-disk total at or below
    /// this value via oldest-mtime eviction. Default
    /// [`DEFAULT_RECORDINGS_STORAGE_CAP_BYTES`] (500 MiB); zero or
    /// values above 1 TiB collapse to the default on sanitise.
    pub recordings_storage_cap_bytes: u64,
    /// WebDAV-backed sync settings. The orchestrator
    /// (`crate::sync`) reads these to drive push / pull; the
    /// Settings UI mutates them through the `sync_config_*` FRB
    /// surface. Plaintext credentials never live here — the two
    /// `*_ref` fields are SecretStore ids.
    pub sync: SyncConfig,
}

impl Default for AppConfig {
    fn default() -> Self {
        Self {
            terminal: TerminalConfig::default(),
            ssh: SshDefaults::default(),
            ui: UiConfig::default(),
            behavior: BehaviorConfig::default(),
            transfer_workers: 2,
            max_history: 500,
            locale: None,
            security: None,
            security_probe_cache: None,
            recordings_storage_cap_bytes: DEFAULT_RECORDINGS_STORAGE_CAP_BYTES,
            sync: SyncConfig::default(),
        }
    }
}

impl AppConfig {
    /// Validate. Walks the sub-structs in order, returns the
    /// first error message or `None` when every field is valid.
    /// Mirrors the Dart `validate()` chain.
    pub fn validate(&self) -> Option<&'static str> {
        if let Some(e) = self.terminal.validate() {
            return Some(e);
        }
        if let Some(e) = self.ssh.validate() {
            return Some(e);
        }
        if let Some(e) = self.ui.validate() {
            return Some(e);
        }
        if self.transfer_workers < 1 {
            return Some("Transfer workers must be at least 1");
        }
        if self.max_history < 0 {
            return Some("Max history must be non-negative");
        }
        None
    }

    #[must_use]
    pub fn sanitized(self) -> Self {
        let d = Self::default();
        Self {
            terminal: self.terminal.sanitized(),
            ssh: self.ssh.sanitized(),
            ui: self.ui.sanitized(),
            behavior: self.behavior,
            transfer_workers: if self.transfer_workers < 1 {
                d.transfer_workers
            } else {
                self.transfer_workers
            },
            max_history: if self.max_history < 0 {
                d.max_history
            } else {
                self.max_history
            },
            locale: self
                .locale
                .filter(|l| SUPPORTED_LOCALES.contains(&l.as_str())),
            security: self.security,
            security_probe_cache: self.security_probe_cache,
            // Zero would mean "evict everything continuously" (the
            // sweep deletes until total <= cap); values above 1 TiB
            // are well outside any plausible disk budget for a
            // recordings tree. Both collapse to the default so a
            // hand-edited config.json that flips the field to
            // garbage still produces a usable cap on the next
            // launch.
            recordings_storage_cap_bytes: if self.recordings_storage_cap_bytes == 0
                || self.recordings_storage_cap_bytes > MAX_RECORDINGS_STORAGE_CAP_BYTES
            {
                d.recordings_storage_cap_bytes
            } else {
                self.recordings_storage_cap_bytes
            },
            sync: self.sync.sanitized(),
        }
    }

    /// JSON wire format — flat object. Sub-struct fields land at
    /// the top level so the format stays stable across the Dart +
    /// Rust encoders. `config_schema_version` is stamped from
    /// `SchemaVersions::CONFIG` on every write so the migration
    /// runner can route any non-current value through its chain on
    /// the next launch.
    ///
    /// Threat model: config.json is plaintext + unauthenticated by
    /// design. The file is user-modifiable (support / hand-debug
    /// flow). A tampered `security_tier` downgrades the indicator
    /// only; the DB cipher key is the actual security boundary, so
    /// an attacker who flips the tier still fails to open the DB
    /// and the user lands on the reset dialog (the intended
    /// detection path — see `security::wipe::has_any_state` and
    /// the cipher-mismatch fatal-error route). A tampered
    /// `config_schema_version` is mitigated by
    /// `migration_history.json`, which records what actually ran
    /// rather than trusting the version field on its own.
    /// Filesystem hardening — 0700 parent dir, `O_NOFOLLOW` on
    /// read and write — closes the remaining symlink-attack
    /// surface; full AEAD on the body is not feasible because no
    /// key source exists pre-DB-unlock.
    pub fn to_json_value(&self) -> Value {
        let mut m = serde_json::Map::new();
        m.insert(
            "config_schema_version".into(),
            json!(crate::migration::SchemaVersions::CONFIG),
        );
        m.extend(self.terminal.to_json_object());
        m.extend(self.ssh.to_json_object());
        m.extend(self.ui.to_json_object());
        m.extend(self.behavior.to_json_object());
        m.insert("transfer_workers".into(), json!(self.transfer_workers));
        m.insert("max_history".into(), json!(self.max_history));
        m.insert(
            "recordings_storage_cap_bytes".into(),
            json!(self.recordings_storage_cap_bytes),
        );
        m.extend(self.sync.to_json_object());
        if let Some(ref l) = self.locale {
            m.insert("locale".into(), json!(l));
        }
        if let Some(ref sec) = self.security {
            m.insert("security_tier".into(), json!(sec.tier.wire_name()));
            let modifiers_map = sec.modifiers.to_json_map();
            let modifiers_value: serde_json::Map<String, Value> = modifiers_map
                .into_iter()
                .map(|(k, v)| (k.to_string(), v))
                .collect();
            m.insert("security_modifiers".into(), Value::Object(modifiers_value));
        }
        // Emit `security_probe_cache` as an explicit value (object or
        // null) rather than omitting it on `None`. The v1 writer
        // omitted, which collapsed "never probed" and "probed-but-
        // empty" on the round-trip. v2 stamps the field unconditionally
        // so the load path (and the cold-start cache hit / miss
        // decision) sees the same shape every write produced.
        m.insert(
            "security_probe_cache".into(),
            self.security_probe_cache
                .as_ref()
                .map(|c| c.to_json_value())
                .unwrap_or(Value::Null),
        );
        Value::Object(m)
    }

    pub fn from_json_value(value: &Value) -> Self {
        let Some(obj) = value.as_object() else {
            return Self::default();
        };
        let d = Self::default();
        let security = read_security_config(obj);
        let security_probe_cache = obj
            .get("security_probe_cache")
            .and_then(SecurityCapabilities::from_json_value);
        Self {
            terminal: TerminalConfig::from_json_object(obj),
            ssh: SshDefaults::from_json_object(obj),
            ui: UiConfig::from_json_object(obj),
            behavior: BehaviorConfig::from_json_object(obj),
            transfer_workers: obj
                .get("transfer_workers")
                .and_then(|v| v.as_i64())
                .unwrap_or(d.transfer_workers),
            max_history: obj
                .get("max_history")
                .and_then(|v| v.as_i64())
                .unwrap_or(d.max_history),
            locale: obj.get("locale").and_then(|v| v.as_str()).map(String::from),
            security,
            security_probe_cache,
            recordings_storage_cap_bytes: obj
                .get("recordings_storage_cap_bytes")
                .and_then(|v| v.as_u64())
                .unwrap_or(d.recordings_storage_cap_bytes),
            sync: SyncConfig::from_json_object(obj),
        }
        .sanitized()
    }
}

/// Strip every per-host security field. Mirror of Dart
/// `AppConfig.toJsonForExport`. The `.lfs` archive carries the
/// portable preferences only; security is per-install and the
/// importer re-runs the wizard on first launch.
pub fn strip_for_export(value: &mut Value) {
    let Some(obj) = value.as_object_mut() else {
        return;
    };
    obj.remove("security_tier");
    obj.remove("security_modifiers");
    obj.remove("security_probe_cache");
    obj.remove("config_schema_version");
    // Sync settings are per-install — the WebDAV URL / username,
    // the SecretStore-id pointers, and the per-device push /
    // pull state all describe the current machine's relationship
    // with the remote. An archive imported on a different device
    // re-runs the sync setup wizard rather than adopting the
    // exporter's WebDAV endpoint.
    obj.remove("sync_enabled");
    obj.remove("sync_webdav_url");
    obj.remove("sync_webdav_username");
    obj.remove("sync_webdav_password_ref");
    obj.remove("sync_webdav_auth_method");
    obj.remove("sync_passphrase_ref");
    obj.remove("sync_remote_path");
    obj.remove("sync_last_pushed_at_ms");
    obj.remove("sync_last_pulled_at_ms");
    obj.remove("sync_last_pushed_sha256");
    obj.remove("sync_last_pushed_etag");
}

fn read_security_config(json: &serde_json::Map<String, Value>) -> Option<SecurityConfig> {
    let tier_str = json.get("security_tier").and_then(|v| v.as_str())?;
    let tier = SecurityTier::from_wire_name(tier_str)?;
    let modifiers = json
        .get("security_modifiers")
        .and_then(|v| v.as_object())
        .map(crate::security::SecurityTierModifiers::from_json_map)
        .unwrap_or_default();
    Some(SecurityConfig { tier, modifiers })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn terminal_validate_accepts_defaults() {
        assert!(TerminalConfig::default().validate().is_none());
    }

    #[test]
    fn terminal_validate_rejects_oversize_font() {
        let t = TerminalConfig {
            font_size: 200.0,
            ..TerminalConfig::default()
        };
        assert!(t.validate().is_some());
    }

    #[test]
    fn ssh_validate_rejects_zero_port() {
        let s = SshDefaults {
            default_port: 0,
            ..SshDefaults::default()
        };
        assert!(s.validate().is_some());
    }

    #[test]
    fn ui_validate_rejects_extreme_scale() {
        let u = UiConfig {
            ui_scale: 10.0,
            ..UiConfig::default()
        };
        assert!(u.validate().is_some());
    }

    #[test]
    fn app_config_validate_walks_sub_structs() {
        // Bad font size in TerminalConfig surfaces as the first
        // error from the AppConfig walk.
        let cfg = AppConfig {
            terminal: TerminalConfig {
                font_size: 1.0,
                ..TerminalConfig::default()
            },
            ..AppConfig::default()
        };
        let err = cfg.validate().unwrap();
        assert!(err.contains("Font size"));
    }

    #[test]
    fn app_config_validate_catches_negative_max_history() {
        let cfg = AppConfig {
            max_history: -1,
            ..AppConfig::default()
        };
        let err = cfg.validate().unwrap();
        assert!(err.contains("Max history"));
    }

    #[test]
    fn terminal_defaults_match_dart() {
        let d = TerminalConfig::default();
        assert_eq!(d.font_size, 14.0);
        assert_eq!(d.theme, "system");
        assert_eq!(d.scrollback, 5000);
    }

    #[test]
    fn terminal_sanitized_clamps_font_size() {
        let t = TerminalConfig {
            font_size: 1000.0,
            theme: "system".into(),
            scrollback: 5000,
        }
        .sanitized();
        assert_eq!(t.font_size, 72.0);
    }

    #[test]
    fn terminal_sanitized_replaces_unknown_theme() {
        let t = TerminalConfig {
            font_size: 14.0,
            theme: "neon".into(),
            scrollback: 5000,
        }
        .sanitized();
        assert_eq!(t.theme, "system");
    }

    #[test]
    fn terminal_round_trip_preserves_fields() {
        let t = TerminalConfig {
            font_size: 16.0,
            theme: "dark".into(),
            scrollback: 10_000,
        };
        let json = t.to_json_object();
        let parsed = TerminalConfig::from_json_object(&json);
        assert_eq!(parsed, t);
    }

    #[test]
    fn ssh_defaults_clamp_invalid_port() {
        let s = SshDefaults {
            keepalive_sec: 30,
            default_port: 999_999,
            ssh_timeout_sec: 10,
        }
        .sanitized();
        assert_eq!(s.default_port, 22);
    }

    #[test]
    fn ui_clamps_window_size() {
        let u = UiConfig {
            toast_duration_ms: 4000,
            window_width: 100.0,
            window_height: 100.0,
            ui_scale: 1.0,
            show_folder_sizes: false,
        }
        .sanitized();
        assert_eq!(u.window_width, 1100.0);
        assert_eq!(u.window_height, 650.0);
    }

    #[test]
    fn ui_clamps_ui_scale_outside_range() {
        let u = UiConfig {
            toast_duration_ms: 4000,
            window_width: 1100.0,
            window_height: 650.0,
            ui_scale: 5.0,
            show_folder_sizes: false,
        }
        .sanitized();
        assert_eq!(u.ui_scale, 2.0);
    }

    #[test]
    fn behavior_log_level_omitted_when_none() {
        let b = BehaviorConfig::default();
        let json = b.to_json_object();
        assert!(!json.contains_key("log_level"));
    }

    #[test]
    fn behavior_log_level_round_trips() {
        for level in [LogLevel::Info, LogLevel::Warn, LogLevel::Error] {
            let b = BehaviorConfig {
                log_level: Some(level),
                check_updates_on_start: true,
                skipped_version: None,
            };
            let json = b.to_json_object();
            let parsed = BehaviorConfig::from_json_object(&json);
            assert_eq!(parsed.log_level, Some(level));
        }
    }

    #[test]
    fn app_config_default_round_trip() {
        let cfg = AppConfig::default();
        let json = cfg.to_json_value();
        let parsed = AppConfig::from_json_value(&json);
        assert_eq!(parsed, cfg);
    }

    #[test]
    fn app_config_emits_flat_top_level_keys() {
        let cfg = AppConfig::default();
        let v = cfg.to_json_value();
        let obj = v.as_object().unwrap();
        // Sub-struct fields land at the top level — mirrors Dart
        // `AppConfig.toJson` which spreads `...subStruct.toJson()`.
        assert!(obj.contains_key("font_size"));
        assert!(obj.contains_key("default_port"));
        assert!(obj.contains_key("toast_duration_ms"));
        assert!(obj.contains_key("check_updates_on_start"));
    }

    #[test]
    fn app_config_security_omitted_until_wizard_runs() {
        let cfg = AppConfig::default();
        let v = cfg.to_json_value();
        let obj = v.as_object().unwrap();
        assert!(!obj.contains_key("security_tier"));
        assert!(!obj.contains_key("security_modifiers"));
    }

    #[test]
    fn to_json_value_stamps_config_schema_version() {
        let v = AppConfig::default().to_json_value();
        let stamped = v
            .as_object()
            .and_then(|o| o.get("config_schema_version"))
            .and_then(|n| n.as_i64());
        assert_eq!(
            stamped,
            Some(crate::migration::SchemaVersions::CONFIG as i64),
        );
    }

    #[test]
    fn from_json_then_to_json_preserves_current_schema_version_even_if_input_was_stale() {
        // Simulates a `Store::set_json` round-trip: caller hands JSON
        // produced by an older build that wrote an outdated version;
        // the canonicaliser must re-stamp the current `SchemaVersions::CONFIG`
        // on the way out so the on-disk file always reflects the live
        // build's target version.
        let stale = json!({"font_size": 14.0, "config_schema_version": 0});
        let cfg = AppConfig::from_json_value(&stale);
        let out = cfg.to_json_value();
        assert_eq!(
            out.as_object()
                .and_then(|o| o.get("config_schema_version"))
                .and_then(|n| n.as_i64()),
            Some(crate::migration::SchemaVersions::CONFIG as i64),
        );
    }

    #[test]
    fn app_config_security_round_trips_when_set() {
        let cfg = AppConfig {
            security: Some(SecurityConfig {
                tier: SecurityTier::Hardware,
                modifiers: crate::security::SecurityTierModifiers::default(),
            }),
            ..AppConfig::default()
        };
        let v = cfg.to_json_value();
        let obj = v.as_object().unwrap();
        assert_eq!(
            obj.get("security_tier").and_then(|v| v.as_str()),
            Some("hardware"),
        );
        let parsed = AppConfig::from_json_value(&v);
        assert_eq!(parsed.security.unwrap().tier, SecurityTier::Hardware);
    }

    #[test]
    fn app_config_unknown_tier_string_collapses_to_none() {
        let v = json!({"security_tier": "L99"});
        let parsed = AppConfig::from_json_value(&v);
        assert!(parsed.security.is_none());
    }

    #[test]
    fn app_config_locale_unknown_falls_through() {
        let v = json!({"locale": "klingon"});
        let parsed = AppConfig::from_json_value(&v);
        assert!(parsed.locale.is_none());
    }

    #[test]
    fn app_config_locale_known_round_trips() {
        let v = json!({"locale": "ru"});
        let parsed = AppConfig::from_json_value(&v);
        assert_eq!(parsed.locale.as_deref(), Some("ru"));
    }

    #[test]
    fn strip_for_export_removes_per_host_fields() {
        let cfg = AppConfig {
            security: Some(SecurityConfig {
                tier: SecurityTier::Hardware,
                modifiers: crate::security::SecurityTierModifiers::default(),
            }),
            ..AppConfig::default()
        };
        let mut v = cfg.to_json_value();
        // `to_json_value` always stamps `config_schema_version`;
        // `strip_for_export` is responsible for removing it before
        // the blob lands inside an `.lfs` archive.
        assert_eq!(
            v.as_object()
                .and_then(|o| o.get("config_schema_version"))
                .and_then(|n| n.as_i64()),
            Some(crate::migration::SchemaVersions::CONFIG as i64),
        );
        strip_for_export(&mut v);
        let obj = v.as_object().unwrap();
        assert!(!obj.contains_key("security_tier"));
        assert!(!obj.contains_key("security_modifiers"));
        assert!(!obj.contains_key("security_probe_cache"));
        assert!(!obj.contains_key("config_schema_version"));
        // Non-security fields survive.
        assert!(obj.contains_key("font_size"));
    }

    #[test]
    fn transfer_workers_clamped_to_minimum_one() {
        let cfg = AppConfig {
            transfer_workers: 0,
            ..AppConfig::default()
        }
        .sanitized();
        assert_eq!(cfg.transfer_workers, 2);
    }

    #[test]
    fn max_history_clamped_to_non_negative() {
        let cfg = AppConfig {
            max_history: -5,
            ..AppConfig::default()
        }
        .sanitized();
        assert_eq!(cfg.max_history, 500);
    }

    #[test]
    fn recordings_storage_cap_default_is_500_mib() {
        let cfg = AppConfig::default();
        assert_eq!(
            cfg.recordings_storage_cap_bytes,
            DEFAULT_RECORDINGS_STORAGE_CAP_BYTES,
        );
        assert_eq!(cfg.recordings_storage_cap_bytes, 500 * 1024 * 1024);
    }

    #[test]
    fn recordings_storage_cap_round_trips_through_json() {
        let cfg = AppConfig {
            recordings_storage_cap_bytes: 750 * 1024 * 1024,
            ..AppConfig::default()
        };
        let v = cfg.to_json_value();
        let parsed = AppConfig::from_json_value(&v);
        assert_eq!(parsed.recordings_storage_cap_bytes, 750 * 1024 * 1024);
    }

    #[test]
    fn recordings_storage_cap_zero_collapses_to_default() {
        // Zero means "evict every file every sweep" — that is never
        // what the user wants; sanitiser maps it to the default.
        let cfg = AppConfig {
            recordings_storage_cap_bytes: 0,
            ..AppConfig::default()
        }
        .sanitized();
        assert_eq!(
            cfg.recordings_storage_cap_bytes,
            DEFAULT_RECORDINGS_STORAGE_CAP_BYTES,
        );
    }

    #[test]
    fn recordings_storage_cap_absurd_value_collapses_to_default() {
        let cfg = AppConfig {
            recordings_storage_cap_bytes: u64::MAX,
            ..AppConfig::default()
        }
        .sanitized();
        assert_eq!(
            cfg.recordings_storage_cap_bytes,
            DEFAULT_RECORDINGS_STORAGE_CAP_BYTES,
        );
    }

    #[test]
    fn sync_config_defaults_are_disabled_with_canonical_secret_ids() {
        let s = SyncConfig::default();
        assert!(!s.enabled);
        assert!(s.webdav_url.is_empty());
        assert_eq!(s.webdav_password_ref, SYNC_PASSWORD_SECRET_ID);
        assert_eq!(s.passphrase_ref, SYNC_PASSPHRASE_SECRET_ID);
        assert_eq!(s.remote_path, SYNC_DEFAULT_REMOTE_PATH);
        assert_eq!(s.webdav_auth_method, "basic");
        assert_eq!(s.last_pushed_at_ms, 0);
        assert_eq!(s.last_pulled_at_ms, 0);
        assert!(s.last_pushed_sha256.is_empty());
        assert!(s.last_pushed_etag.is_empty());
    }

    #[test]
    fn sync_config_round_trips_through_json_object() {
        let s = SyncConfig {
            enabled: true,
            webdav_url: "https://dav.example.com/remote.php/dav/files/user/".into(),
            webdav_username: "alice".into(),
            webdav_password_ref: SYNC_PASSWORD_SECRET_ID.into(),
            webdav_auth_method: "digest".into(),
            passphrase_ref: SYNC_PASSPHRASE_SECRET_ID.into(),
            remote_path: "lfssh/sync.lfs".into(),
            last_pushed_at_ms: 1_700_000_000_000,
            last_pulled_at_ms: 1_700_000_001_000,
            last_pushed_sha256: "abc123".into(),
            last_pushed_etag: "etag-1".into(),
        };
        let obj = s.to_json_object();
        let parsed = SyncConfig::from_json_object(&obj);
        assert_eq!(parsed, s);
    }

    #[test]
    fn sync_config_unknown_auth_method_collapses_to_basic() {
        let s = SyncConfig {
            webdav_auth_method: "oauth2".into(),
            ..SyncConfig::default()
        }
        .sanitized();
        assert_eq!(s.webdav_auth_method, "basic");
    }

    #[test]
    fn sync_config_empty_remote_path_falls_back_to_default() {
        let s = SyncConfig {
            remote_path: String::new(),
            ..SyncConfig::default()
        }
        .sanitized();
        assert_eq!(s.remote_path, SYNC_DEFAULT_REMOTE_PATH);
    }

    #[test]
    fn sync_config_negative_timestamps_clamp_to_zero() {
        let s = SyncConfig {
            last_pushed_at_ms: -42,
            last_pulled_at_ms: -1,
            ..SyncConfig::default()
        }
        .sanitized();
        assert_eq!(s.last_pushed_at_ms, 0);
        assert_eq!(s.last_pulled_at_ms, 0);
    }

    #[test]
    fn app_config_sync_round_trips_through_full_envelope() {
        let cfg = AppConfig {
            sync: SyncConfig {
                enabled: true,
                webdav_url: "https://dav.example.com/dav/".into(),
                webdav_username: "alice".into(),
                webdav_password_ref: SYNC_PASSWORD_SECRET_ID.into(),
                webdav_auth_method: "basic".into(),
                passphrase_ref: SYNC_PASSPHRASE_SECRET_ID.into(),
                remote_path: "letsflutssh.lfs".into(),
                last_pushed_at_ms: 1_700_000_000_000,
                last_pulled_at_ms: 0,
                last_pushed_sha256: "deadbeef".into(),
                last_pushed_etag: "etag-7".into(),
            },
            ..AppConfig::default()
        };
        let v = cfg.to_json_value();
        let parsed = AppConfig::from_json_value(&v);
        assert_eq!(parsed.sync, cfg.sync);
    }

    #[test]
    fn strip_for_export_drops_sync_state() {
        // Sync settings describe the current install's relationship
        // with a remote — never portable. The export pipeline must
        // remove them before the JSON lands inside an `.lfs` archive,
        // otherwise an importer on a different machine would adopt
        // the exporter's WebDAV endpoint.
        let cfg = AppConfig {
            sync: SyncConfig {
                enabled: true,
                webdav_url: "https://dav.example.com/dav/".into(),
                last_pushed_sha256: "deadbeef".into(),
                ..SyncConfig::default()
            },
            ..AppConfig::default()
        };
        let mut v = cfg.to_json_value();
        strip_for_export(&mut v);
        let obj = v.as_object().unwrap();
        assert!(!obj.contains_key("sync_enabled"));
        assert!(!obj.contains_key("sync_webdav_url"));
        assert!(!obj.contains_key("sync_webdav_username"));
        assert!(!obj.contains_key("sync_webdav_password_ref"));
        assert!(!obj.contains_key("sync_webdav_auth_method"));
        assert!(!obj.contains_key("sync_passphrase_ref"));
        assert!(!obj.contains_key("sync_remote_path"));
        assert!(!obj.contains_key("sync_last_pushed_at_ms"));
        assert!(!obj.contains_key("sync_last_pulled_at_ms"));
        assert!(!obj.contains_key("sync_last_pushed_sha256"));
        assert!(!obj.contains_key("sync_last_pushed_etag"));
    }

    #[test]
    fn recordings_storage_cap_field_in_json_envelope() {
        // The cap is part of the persisted shape — it must show up
        // at the top level so a hand-edit / out-of-band tool can
        // round-trip the field.
        let v = AppConfig::default().to_json_value();
        let obj = v.as_object().unwrap();
        assert!(obj.contains_key("recordings_storage_cap_bytes"));
    }
}
