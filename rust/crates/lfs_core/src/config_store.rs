//! Process-singleton actor for the persisted `config.json`.
//!
//! Owns three responsibilities the Dart `ConfigNotifier` used to
//! split across an in-memory state + a debounce timer + an
//! atomic file write chain:
//!
//! 1. **In-memory state** — the current [`AppConfig`] under a
//!    Mutex. `get_json` returns a snapshot; `set_json` swaps in
//!    a fresh state and schedules persistence.
//! 2. **Debounced disk writes** — slider drags / fast typing
//!    coalesce into a single trailing write. 300 ms window
//!    matches the Dart `_saveDebounce` const.
//! 3. **Bus event publication** — every successful write fires
//!    [`crate::bus::BusEvent::ConfigChanged`] so Dart Riverpod
//!    consumers refresh from the canonical state without polling.
//!
//! Lands independently of the Dart cutover so the additive
//! change is isolated; the Dart `ConfigNotifier` rewrite lands
//! as a follow-up against this stable API.

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
        crate::app::instance()
            .bus
            .publish(Event::ConfigChanged { json: json.clone() });
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
/// the call would panic with "there is no reactor running",
/// which is what the Dart-side silent fallback used to absorb.
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
mod tests {
    use super::*;
    use tempfile::TempDir;

    fn fresh_dir() -> TempDir {
        TempDir::new().unwrap()
    }

    #[test]
    fn init_returns_defaults_for_empty_dir() {
        let dir = fresh_dir();
        let store = Store::for_tests();
        let json = store.init(dir.path().to_path_buf()).unwrap();
        let value: serde_json::Value = serde_json::from_str(&json).unwrap();
        // Default AppConfig emits flat top-level keys (terminal
        // / ssh / ui / behavior fields all there).
        assert!(value.get("font_size").is_some());
        assert!(value.get("default_port").is_some());
    }

    #[test]
    fn init_loads_existing_file() {
        let dir = fresh_dir();
        let path = dir.path().join("config.json");
        std::fs::write(&path, r#"{"font_size":18.0}"#).unwrap();
        let store = Store::for_tests();
        let json = store.init(dir.path().to_path_buf()).unwrap();
        let value: serde_json::Value = serde_json::from_str(&json).unwrap();
        assert_eq!(
            value.get("font_size").and_then(serde_json::Value::as_f64),
            Some(18.0),
        );
    }

    #[test]
    fn init_returns_err_for_corrupt_file() {
        // Pre-fix: silently dropped the corrupt file's contents and
        // seeded `AppConfig::default()`; the next `update` would
        // flush those defaults over the on-disk content and lose
        // the user's settings. The Dart-side `loadAppConfigFromDisk`
        // catches the matching `AppConfigParseException` and routes
        // the user to the fatal-error screen so they can recover
        // the file manually.
        let dir = fresh_dir();
        let path = dir.path().join("config.json");
        std::fs::write(&path, "{not json").unwrap();
        let store = Store::for_tests();
        let err = store.init(dir.path().to_path_buf()).unwrap_err();
        assert!(err.contains("parse"), "unexpected error tag: {err}");
    }

    #[test]
    fn init_seeds_defaults_when_file_absent() {
        // Absent file is the legitimate first-launch path — seed
        // defaults silently so a fresh install does not surface
        // the fatal-error screen.
        let dir = fresh_dir();
        let store = Store::for_tests();
        let json = store.init(dir.path().to_path_buf()).unwrap();
        let value: serde_json::Value = serde_json::from_str(&json).unwrap();
        assert_eq!(
            value.get("font_size").and_then(serde_json::Value::as_f64),
            Some(14.0),
        );
    }

    #[test]
    fn get_json_returns_none_before_init() {
        let store = Store::for_tests();
        assert!(store.get_json().is_none());
    }

    #[test]
    fn set_json_updates_in_memory_state_synchronously() {
        let dir = fresh_dir();
        let store = Store::for_tests();
        store.init(dir.path().to_path_buf()).unwrap();
        store.set_json(r#"{"font_size":20.0}"#).unwrap();
        let snapshot: serde_json::Value = serde_json::from_str(&store.get_json().unwrap()).unwrap();
        assert_eq!(
            snapshot
                .get("font_size")
                .and_then(serde_json::Value::as_f64),
            Some(20.0),
        );
    }

    #[test]
    fn set_json_errors_when_not_initialised() {
        let store = Store::for_tests();
        let result = store.set_json(r#"{}"#);
        assert!(result.is_err());
    }

    #[test]
    fn set_json_errors_on_malformed_json() {
        let dir = fresh_dir();
        let store = Store::for_tests();
        store.init(dir.path().to_path_buf()).unwrap();
        let result = store.set_json("{not json");
        assert!(result.is_err());
    }

    #[test]
    fn flush_persists_pending_state_to_disk() {
        let dir = fresh_dir();
        let store = Store::for_tests();
        store.init(dir.path().to_path_buf()).unwrap();
        store.set_json(r#"{"font_size":24.0}"#).unwrap();
        store.flush().unwrap();
        let on_disk = std::fs::read_to_string(dir.path().join("config.json")).unwrap();
        let value: serde_json::Value = serde_json::from_str(&on_disk).unwrap();
        assert_eq!(
            value.get("font_size").and_then(serde_json::Value::as_f64),
            Some(24.0),
        );
    }

    #[test]
    fn flush_with_no_pending_writes_current_state() {
        // Fresh init — current is the loaded/default state, no
        // pending. Flush still writes the current snapshot so
        // callers can use it as "ensure on disk now".
        let dir = fresh_dir();
        let store = Store::for_tests();
        store.init(dir.path().to_path_buf()).unwrap();
        store.flush().unwrap();
        assert!(dir.path().join("config.json").exists());
    }

    #[test]
    fn flush_returns_none_before_init() {
        let store = Store::for_tests();
        assert!(store.flush().unwrap().is_none());
    }

    #[test]
    fn tick_if_due_returns_false_within_debounce_window() {
        let dir = fresh_dir();
        let store = Store::for_tests();
        store.init(dir.path().to_path_buf()).unwrap();
        store.set_json(r#"{"font_size":24.0}"#).unwrap();
        // pending_at is set to now + DEBOUNCE; tick immediately
        // should be a no-op.
        assert!(!store.tick_if_due().unwrap());
        assert!(!std::fs::read_to_string(dir.path().join("config.json"))
            .map(|c| c.contains("24.0"))
            .unwrap_or(false));
    }

    #[test]
    fn back_to_back_set_calls_collapse_into_one_pending() {
        // Three rapid set_json calls — only the last value
        // should land on disk after flush. Pending replaces in
        // place.
        let dir = fresh_dir();
        let store = Store::for_tests();
        store.init(dir.path().to_path_buf()).unwrap();
        store.set_json(r#"{"font_size":14.0}"#).unwrap();
        store.set_json(r#"{"font_size":18.0}"#).unwrap();
        store.set_json(r#"{"font_size":24.0}"#).unwrap();
        store.flush().unwrap();
        let on_disk = std::fs::read_to_string(dir.path().join("config.json")).unwrap();
        let value: serde_json::Value = serde_json::from_str(&on_disk).unwrap();
        assert_eq!(
            value.get("font_size").and_then(serde_json::Value::as_f64),
            Some(24.0),
        );
    }

    #[test]
    fn was_loaded_from_disk_is_false_before_init() {
        // Fresh actor — no init has run yet. The flag stays false so
        // a Dart caller that reads the value before `config_store_init`
        // returns gets a deterministic "no file adopted" signal.
        let store = Store::for_tests();
        assert!(!store.was_loaded_from_disk());
    }

    #[test]
    fn was_loaded_from_disk_is_false_when_file_absent() {
        // Fresh-install path: empty support dir → defaults seeded.
        // The flag must stay false so the SecurityInitController routes
        // the user through the first-launch wizard.
        let dir = fresh_dir();
        let store = Store::for_tests();
        store.init(dir.path().to_path_buf()).unwrap();
        assert!(!store.was_loaded_from_disk());
    }

    #[test]
    fn was_loaded_from_disk_is_true_when_file_present_and_valid() {
        // Existing valid file → parsed + adopted. The flag flips true
        // so the SecurityInitController takes the resume-saved-tier
        // branch instead of re-running the first-launch wizard.
        let dir = fresh_dir();
        let path = dir.path().join("config.json");
        std::fs::write(&path, r#"{"font_size":18.0}"#).unwrap();
        let store = Store::for_tests();
        store.init(dir.path().to_path_buf()).unwrap();
        assert!(store.was_loaded_from_disk());
    }

    #[test]
    fn was_loaded_from_disk_resets_when_re_init_finds_no_file() {
        // Test reset path: a successful disk load followed by an init
        // against a fresh tempdir (no file) must roll the flag back
        // to false, otherwise the Dart wipe path would skip wizard
        // setup after a reset-and-relaunch.
        let dir1 = fresh_dir();
        std::fs::write(dir1.path().join("config.json"), r#"{"font_size":18.0}"#).unwrap();
        let store = Store::for_tests();
        store.init(dir1.path().to_path_buf()).unwrap();
        assert!(store.was_loaded_from_disk());
        let dir2 = fresh_dir();
        store.init(dir2.path().to_path_buf()).unwrap();
        assert!(!store.was_loaded_from_disk());
    }

    #[test]
    fn re_init_drops_pending_without_flush() {
        // Test reset path: re-init under a different dir
        // discards the previous in-memory state without writing.
        let dir1 = fresh_dir();
        let store = Store::for_tests();
        store.init(dir1.path().to_path_buf()).unwrap();
        store.set_json(r#"{"font_size":99.0}"#).unwrap();
        let dir2 = fresh_dir();
        store.init(dir2.path().to_path_buf()).unwrap();
        // Original dir never received the 99.0 write.
        assert!(!dir1.path().join("config.json").exists());
    }
}
