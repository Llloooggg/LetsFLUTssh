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
/// Matches the Dart `ConfigStore._fileName` const.
const FILE_NAME: &str = "config.json";

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
}

impl Inner {
    const fn new() -> Self {
        Self {
            file_path: None,
            current: None,
            pending: None,
            pending_at: None,
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
    /// the existing `config.json` if present; otherwise seeds
    /// with `AppConfig::default()`. Returns the loaded config
    /// JSON so the caller doesn't need a follow-up `get_json`.
    ///
    /// Idempotent — re-init under a different support_dir is
    /// allowed (test reset path), the previous in-memory state
    /// is dropped without a flush. Production callers init once
    /// at startup.
    pub fn init(&self, support_dir: PathBuf) -> Result<String, String> {
        let path = support_dir.join(FILE_NAME);
        let cfg = match std::fs::read_to_string(&path) {
            Ok(text) => match serde_json::from_str::<serde_json::Value>(&text) {
                Ok(v) => AppConfig::from_json_value(&v),
                Err(_) => AppConfig::default(),
            },
            Err(_) => AppConfig::default(),
        };
        let json = cfg.to_json_value().to_string();
        let mut g = self.inner.lock().expect("config store mutex poisoned");
        g.file_path = Some(path);
        g.current = Some(cfg);
        g.pending = None;
        g.pending_at = None;
        Ok(json)
    }

    /// Snapshot the current config as a JSON string. Returns
    /// `None` when the actor has not been [`init`]-ed yet — the
    /// Dart caller treats that as "use defaults" until the
    /// startup init lands.
    pub fn get_json(&self) -> Option<String> {
        let g = self.inner.lock().expect("config store mutex poisoned");
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
        let mut g = self.inner.lock().expect("config store mutex poisoned");
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
            let mut g = self.inner.lock().expect("config store mutex poisoned");
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
            let g = self.inner.lock().expect("config store mutex poisoned");
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

fn write_to_disk(path: &std::path::Path, json: &str) -> Result<(), String> {
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent).map_err(|e| format!("config_store: create dir: {e}"))?;
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
    fn init_falls_back_to_defaults_for_corrupt_file() {
        let dir = fresh_dir();
        let path = dir.path().join("config.json");
        std::fs::write(&path, "{not json").unwrap();
        let store = Store::for_tests();
        let json = store.init(dir.path().to_path_buf()).unwrap();
        let value: serde_json::Value = serde_json::from_str(&json).unwrap();
        // Defaults — font_size = 14.0
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
