//! Process-singleton actor for the persisted `config.json`.
//!
//! Owns three responsibilities:
//!
//! 1. **In-memory state** — the current [`AppConfig`] under a
//!    Mutex. `get_json` returns a snapshot; `set_json` swaps in
//!    a fresh state and schedules persistence.
//! 2. **Debounced disk writes** — slider drags / fast typing
//!    coalesce into a single trailing write. 300 ms window.
//! 3. **Bus event publication** — every successful write fires
//!    [`crate::bus::BusEvent::ConfigChanged`] so Dart Riverpod
//!    consumers refresh from the canonical state without polling.

use std::path::PathBuf;
use std::sync::{Mutex, OnceLock};
use std::time::{Duration, Instant};

use crate::bus::Event;
use crate::config::AppConfig;
use crate::path::write_bytes_atomic;

/// Window during which back-to-back `set_json` calls coalesce
/// into a single trailing disk write. Matches the Dart
/// `_saveDebounce` const — slider drag / fast typing collapse to
/// one I/O.
const DEBOUNCE: Duration = Duration::from_millis(300);

/// File name under `support_dir` the actor reads + writes.
/// Matches the Dart `ConfigStore._fileName` const. Exposed
/// `pub` so the wipe-coverage regression test in
/// `security::wipe::tests` can cross-reference the canonical
/// string rather than copy-pasting a literal that drifts.
pub const FILE_NAME: &str = "config.json";

/// Per-actor state guarded by the singleton's Mutex.
#[derive(Debug)]
struct Inner {
    /// Resolved file path. `None` until [`init`] runs.
    file_path: Option<PathBuf>,
    /// Current in-memory state. `None` until [`init`] runs.
    current: Option<AppConfig>,
    /// State pending a debounced write. `None` when no save is
    /// queued.
    pending: Option<AppConfig>,
    /// When the next debounced flush should fire; the worker
    /// loop checks every `DEBOUNCE` tick and writes if `now >=
    /// pending_at` and `pending.is_some()`.
    pending_at: Option<Instant>,
    /// True when the most recent [`Store::init`] found an
    /// existing `config.json` on disk and adopted its parsed
    /// contents; false when init seeded `AppConfig::default()`
    /// because the file was absent (fresh install) or unreadable
    /// for non-parse reasons (perm denied / ELOOP from a hostile
    /// symlink). Read by the Dart cold-start path to set
    /// `LoadedAppConfig.loadedFromFile` without a separate file
    /// existence probe — the load route is single-source-of-truth
    /// for "was there usable on-disk state".
    loaded_from_disk: bool,
}

impl Inner {
    const fn new() -> Self {
        Self {
            file_path: None,
            current: None,
            pending: None,
            pending_at: None,
            loaded_from_disk: false,
        }
    }
}

/// Process-singleton actor handle. The Dart `ConfigNotifier`
/// shim talks to this via FRB; tests construct a fresh instance
/// via [`Store::for_tests`].
pub struct Store {
    inner: Mutex<Inner>,
}

impl Store {
    /// Fresh actor with empty state — caller must invoke
    /// [`init`] before `get_json` / `set_json`.
    #[must_use]
    pub fn new() -> Self {
        Self {
            inner: Mutex::new(Inner::new()),
        }
    }

    /// Initialise the actor against a support directory. Loads
    /// the existing `config.json` if present; absent file seeds
    /// with `AppConfig::default()`. **Parse failure on a present
    /// file surfaces as `Err`** — the actor never silently
    /// downgrades to defaults, because the next `update` would
    /// flush those defaults over the on-disk content and lose the
    /// user's settings. The Dart-side `loadAppConfigFromDisk`
    /// catches `AppConfigParseException` and routes the user to
    /// the fatal-error screen so they can recover the file
    /// manually instead of seeing it overwritten.
    ///
    /// Idempotent on absent file / valid file under a different
    /// support_dir (test reset path) — previous in-memory state
    /// is dropped without a flush.
    pub fn init(&self, support_dir: PathBuf) -> Result<String, String> {
        let path = support_dir.join(FILE_NAME);
        // Track whether the on-disk file produced the adopted state.
        // Only the successful-read + parse branch flips this true;
        // every I/O failure path (absent file, perm denied, ELOOP)
        // seeds defaults and leaves the flag false, so the Dart-side
        // first-launch wizard logic does not run for a user whose
        // file is merely unreadable (the next `update` rewrites the
        // path atomically and the flag flips on the subsequent boot).
        let mut loaded_from_disk = false;
        let cfg = match crate::path::read_bytes_secure(&path) {
            Ok(bytes) => match std::str::from_utf8(&bytes) {
                Ok(text) => match serde_json::from_str::<serde_json::Value>(text) {
                    Ok(v) => {
                        loaded_from_disk = true;
                        AppConfig::from_json_value(&v)
                    }
                    Err(e) => {
                        return Err(format!("config_store::init: parse {}: {e}", path.display()));
                    }
                },
                Err(e) => {
                    return Err(format!("config_store::init: utf8 {}: {e}", path.display()));
                }
            },
            // Absent file — seed defaults. Any other I/O error (perm
            // denied, transient FS hiccup, ELOOP from a symlink
            // hijack at the path) ALSO seeds defaults so a hostile-
            // environment install does not refuse to launch; the
            // next successful `update` will atomically write the
            // defaults to disk via the symlink-safe write path.
            Err(_) => AppConfig::default(),
        };
        let json = cfg.to_json_value().to_string();
        let mut g = self.inner.lock().unwrap_or_else(|e| e.into_inner());
        g.file_path = Some(path);
        g.current = Some(cfg);
        g.pending = None;
        g.pending_at = None;
        g.loaded_from_disk = loaded_from_disk;
        Ok(json)
    }

    /// True when the most recent [`init`] call adopted an existing
    /// `config.json` from disk; false when the file was absent or
    /// unreadable and the actor seeded defaults instead. Read by
    /// the Dart cold-start path so `LoadedAppConfig.loadedFromFile`
    /// reflects the single source of truth on whether the user
    /// already has persisted preferences — the SecurityInitController
    /// uses the flag to decide between "first-launch wizard" and
    /// "resume saved tier" branches.
    ///
    /// Returns false when no `init` has run yet; the Dart caller
    /// only reads this after `config_store_init` returns, so the
    /// pre-init value is unreachable in practice.
    pub fn was_loaded_from_disk(&self) -> bool {
        let g = self.inner.lock().unwrap_or_else(|e| e.into_inner());
        g.loaded_from_disk
    }

    /// Snapshot the current config as a JSON string. Returns
    /// `None` when the actor has not been [`init`]-ed yet — the
    /// Dart caller treats that as "use defaults" until the
    /// startup init lands.
    pub fn get_json(&self) -> Option<String> {
        let g = self.inner.lock().unwrap_or_else(|e| e.into_inner());
        g.current.as_ref().map(|c| c.to_json_value().to_string())
    }

    /// Replace the in-memory state with [`new_json`] and arm the
    /// debounce timer. Returns `Err` only when `init` has not
    /// run or the JSON does not parse — the disk write is
    /// fire-and-forget (callers that want save-settled
    /// guarantees use [`flush`]).
    pub fn set_json(&self, new_json: &str) -> Result<(), String> {
        let value: serde_json::Value =
            serde_json::from_str(new_json).map_err(|e| format!("config_store: parse: {e}"))?;
        let cfg = AppConfig::from_json_value(&value);
        let mut g = self.inner.lock().unwrap_or_else(|e| e.into_inner());
        if g.file_path.is_none() {
            return Err("config_store: not initialised".into());
        }
        g.current = Some(cfg.clone());
        g.pending = Some(cfg);
        g.pending_at = Some(Instant::now() + DEBOUNCE);
        Ok(())
    }

    /// Typed snapshot of the current [`AppConfig`]. Returns
    /// `None` when the actor has not been [`init`]-ed yet —
    /// mirrors [`get_json`] but skips the JSON round-trip when
    /// the caller already wants the typed shape (the sync
    /// orchestrator's read path is the canonical caller).
    pub fn get_app_config(&self) -> Option<AppConfig> {
        let g = self.inner.lock().unwrap_or_else(|e| e.into_inner());
        g.current.clone()
    }

    /// Replace just the `sync` slice of the current [`AppConfig`]
    /// and arm the debounce timer. Returns `Err` when the actor
    /// has not been [`init`]-ed yet. Used by
    /// [`crate::sync::service`] after every push / pull to
    /// persist `last_pushed_at_ms` / `last_pulled_at_ms` /
    /// `last_pushed_sha256` / `last_pushed_etag` without
    /// re-walking the full config from JSON. Atomic on disk via
    /// the same debounce + `write_bytes_atomic` chain
    /// [`set_json`] uses.
    pub fn update_sync(&self, sync: crate::config::SyncConfig) -> Result<(), String> {
        let mut g = self.inner.lock().unwrap_or_else(|e| e.into_inner());
        if g.file_path.is_none() {
            return Err("config_store: not initialised".into());
        }
        let Some(current) = g.current.as_ref() else {
            return Err("config_store: no current state".into());
        };
        let mut updated = current.clone();
        updated.sync = sync.sanitized();
        g.current = Some(updated.clone());
        g.pending = Some(updated);
        g.pending_at = Some(Instant::now() + DEBOUNCE);
        Ok(())
    }

    /// Replace just the `security_probe_cache` slice of the
    /// current [`AppConfig`] and arm the debounce timer. Same
    /// atomic-write contract as [`update_sync`]. `None` clears the
    /// slot — mirrors the wizard "Re-check tier support" path that
    /// publishes an empty [`Event::SecurityCapabilitiesChanged`]
    /// after [`crate::security::capabilities_cache::Cache::clear`].
    ///
    /// Returns `Err` when the actor has not been [`init`]-ed yet —
    /// the Rust-side persister actor that wires Cache → Store
    /// starts only after [`crate::config_store::start_background_ticker`],
    /// so the order-of-operations invariant in
    /// `lfs_frb::api::config::config_store_init` keeps this branch
    /// structurally unreachable in production.
    pub fn update_security_probe_cache(
        &self,
        caps: Option<crate::security::capabilities::SecurityCapabilities>,
    ) -> Result<(), String> {
        let mut g = self.inner.lock().unwrap_or_else(|e| e.into_inner());
        if g.file_path.is_none() {
            return Err("config_store: not initialised".into());
        }
        let Some(current) = g.current.as_ref() else {
            return Err("config_store: no current state".into());
        };
        let mut updated = current.clone();
        updated.security_probe_cache = caps;
        g.current = Some(updated.clone());
        g.pending = Some(updated);
        g.pending_at = Some(Instant::now() + DEBOUNCE);
        Ok(())
    }

    /// Replace just the `security.tier` slice of the current
    /// [`AppConfig`] (modifiers + capabilities preserved) and arm
    /// the debounce timer. Same atomic-write contract as
    /// [`update_sync`]. Idempotent: skips the swap when the
    /// current `(tier, modifiers)` already matches the resolved
    /// `(tier, existing_modifiers_or_defaults)` pair — the same
    /// no-write check the Dart `_persistSecurityTier` helper used
    /// to perform before this moved Rust-side.
    ///
    /// Returns `Err` when the actor has not been [`init`]-ed yet.
    pub fn update_security_tier(&self, tier: crate::security::SecurityTier) -> Result<(), String> {
        let mut g = self.inner.lock().unwrap_or_else(|e| e.into_inner());
        if g.file_path.is_none() {
            return Err("config_store: not initialised".into());
        }
        let Some(current) = g.current.as_ref() else {
            return Err("config_store: no current state".into());
        };
        let modifiers = current.security.map(|s| s.modifiers).unwrap_or_default();
        let resolved = crate::security::SecurityConfig { tier, modifiers };
        // Idempotent skip — `(tier, modifiers)` already canonical.
        if current.security == Some(resolved) {
            return Ok(());
        }
        let mut updated = current.clone();
        updated.security = Some(resolved);
        g.current = Some(updated.clone());
        g.pending = Some(updated);
        g.pending_at = Some(Instant::now() + DEBOUNCE);
        Ok(())
    }

    /// Force any pending state to disk synchronously, return the
    /// JSON written (or the current state when nothing was
    /// pending). Used at app shutdown / test teardown so the last
    /// `set_json` call is durable. Idempotent — calling with
    /// nothing pending is a no-op that still returns the current
    /// JSON.
    pub fn flush(&self) -> Result<Option<String>, String> {
        let (path, cfg) = {
            let mut g = self.inner.lock().unwrap_or_else(|e| e.into_inner());
            let Some(path) = g.file_path.clone() else {
                return Ok(None);
            };
            // Pending takes priority; otherwise persist the current
            // snapshot so callers can rely on flush as
            // "ensure on disk now".
            let cfg = g.pending.take().or_else(|| g.current.clone());
            g.pending_at = None;
            (path, cfg)
        };
        let Some(cfg) = cfg else {
            return Ok(None);
        };
        let json = cfg.to_json_value().to_string();
        write_to_disk(&path, &json)?;
        // Publish through the AppState singleton so subscribers
        // re-snapshot without a follow-up `get_json` round-trip.
        // `try_instance` (not `instance`) so a flush in the pre-init
        // window — cold-start config writes before `app_init`, unit
        // tests that don't prime the singleton — drops the no-audience
        // notification instead of panicking; the disk write above is
        // the durable part and already happened.
        if let Some(app) = crate::app::try_instance() {
            app.bus.publish(Event::ConfigChanged { json: json.clone() });
        }
        Ok(Some(json))
    }

    /// Drive the debounce loop one tick — caller (the Dart
    /// FRB-side worker, or the actor's own background task once
    /// wired) checks if `now >= pending_at` and, if so, calls
    /// flush. Exposed instead of a tokio-spawned background loop
    /// because the FRB `tokio::Runtime::Handle::current` is not
    /// always available at actor-construct time, and a manual
    /// tick keeps the test surface deterministic.
    pub fn tick_if_due(&self) -> Result<bool, String> {
        let due = {
            let g = self.inner.lock().unwrap_or_else(|e| e.into_inner());
            match (g.pending_at, &g.pending) {
                (Some(when), Some(_)) => Instant::now() >= when,
                _ => false,
            }
        };
        if due {
            self.flush()?;
            Ok(true)
        } else {
            Ok(false)
        }
    }

    /// Test-only constructor — fresh actor instance, not the
    /// singleton. Used by unit tests so two cases don't share
    /// state through `instance()`.
    #[cfg(test)]
    pub fn for_tests() -> Self {
        Self::new()
    }
}

impl Default for Store {
    fn default() -> Self {
        Self::new()
    }
}

/// Process-singleton instance. Dart FRB shim init + reads route
/// through this. Tests use `Store::for_tests` instead.
static GLOBAL: OnceLock<Store> = OnceLock::new();

pub fn instance() -> &'static Store {
    GLOBAL.get_or_init(Store::new)
}

/// Spawn a background ticker that drives [`Store::tick_if_due`]
/// against the singleton every [`TICK_INTERVAL`]. Production
/// callers invoke this once at app startup after the FRB tokio
/// runtime is ready; tests don't call it (they tick manually
/// via `Store::tick_if_due`).
///
/// Idempotent — repeated calls are no-ops; the ticker spawns
/// at most once per process. Cancellation happens implicitly at
/// process exit; no manual teardown needed.
///
/// Skips the spawn (and stays armed for a later call) when no
/// Tokio runtime is reachable from the calling thread — this
/// happens for sync FRB calls outside the FRB worker pool and
/// in unit tests that drive ticks manually. Without this guard
/// the call would panic with "there is no reactor running".
pub fn start_background_ticker() {
    static TICKER_STARTED: OnceLock<()> = OnceLock::new();
    if tokio::runtime::Handle::try_current().is_err() {
        return;
    }
    if TICKER_STARTED.set(()).is_err() {
        return;
    }
    tokio::spawn(async {
        let mut interval = tokio::time::interval(TICK_INTERVAL);
        // Edge-trigger logging: log only the first failure in a
        // consecutive run so a transient FS hiccup does not flood
        // the log every 100 ms while the user types in a settings
        // slider. The flag clears on a successful tick — the next
        // failure run logs once more.
        let mut last_was_err = false;
        loop {
            interval.tick().await;
            // `tick_if_due` does sync std::fs work via
            // `write_bytes_atomic` — park on `spawn_blocking` so
            // the disk syscall does not stall the runtime worker
            // for ~100 ms on a slow filesystem.
            let result = tokio::task::spawn_blocking(|| instance().tick_if_due()).await;
            match result {
                Err(join_err) => {
                    if !last_was_err {
                        crate::app_log_warn!(
                            "ConfigStore",
                            "ticker spawn_blocking join failed: {}",
                            join_err
                        );
                    }
                    last_was_err = true;
                }
                Ok(Err(write_err)) => {
                    if !last_was_err {
                        crate::app_log_warn!(
                            "ConfigStore",
                            "ticker disk write failed: {}",
                            write_err
                        );
                    }
                    last_was_err = true;
                }
                Ok(Ok(_)) => {
                    last_was_err = false;
                }
            }
        }
    });
}

/// Background ticker cadence. Picks a value tight enough that a
/// pending write lands within ~one frame after `DEBOUNCE`
/// expires, loose enough to keep the wakeup cost off the
/// idle-app profile.
const TICK_INTERVAL: Duration = Duration::from_millis(100);

fn write_to_disk(path: &std::path::Path, json: &str) -> Result<(), String> {
    if let Some(parent) = path.parent() {
        crate::path::create_dir_all_secure(parent)
            .map_err(|e| format!("config_store: create dir: {e}"))?;
    }
    write_bytes_atomic(path, json.as_bytes()).map_err(|e| format!("config_store: write: {e}"))
}
#[cfg(test)]
#[path = "../tests/unit/config_store.rs"]
mod tests;
