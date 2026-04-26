//! Process-singleton app state. The root actor every Rust-owned
//! sub-module attaches to. Today it owns the [`SecretStore`] plus
//! the optional [`Db`] handle; runtime services (sessions,
//! connections, port forwards, recorder, transfer queue) plug their
//! own state buckets onto this struct as they migrate so the FRB
//! layer has a single root to dispatch commands against.
//!
//! Initialisation: `lfs_core::app::init()` runs once per process.
//! The Dart side calls it from `main.dart` right after `RustLib.init()`.
//! Idempotent — repeated calls return the same instance.

use std::path::Path;
use std::sync::Arc;
use std::sync::Mutex;
use std::sync::OnceLock;

use crate::archive::ImportRegistry;
use crate::autolock::AutoLockMachine;
use crate::bus::EventBus;
use crate::connection::ConnectionRegistry;
use crate::db::Db;
use crate::error::Error;
use crate::portforward::PortForwardRegistry;
use crate::recorder::RecorderRegistry;
use crate::secrets::SecretStore;
use crate::transfer::TransferQueue;

static APP_STATE: OnceLock<Arc<AppState>> = OnceLock::new();

pub struct AppState {
    pub secrets: SecretStore,
    /// Encrypted sqlite DB. `None` until `db_init` runs — the Dart
    /// side calls it after the security tier dispatcher has the
    /// master key in hand. Callers that hit a `None` here surface
    /// "DB not initialized" up the stack rather than panicking.
    db: Mutex<Option<Arc<Db>>>,
    /// Typed Command / Event bus. Domain actors append events;
    /// FRB subscribers consume them via per-screen view streams.
    /// See `crate::bus` for the wire contract.
    pub bus: EventBus,
    /// Connection registry. Owns every active connection actor;
    /// commands look up actors by [`crate::connection::ConnId`]
    /// and run state-machine transitions under per-actor locks.
    pub connections: ConnectionRegistry,
    /// Auto-lock state machine. Owns the canonical idle timer +
    /// lifecycle state; emits `AutoLockLocked` /
    /// `AutoLockUnlocked` events when transitions fire.
    pub autolock: Arc<AutoLockMachine>,
    /// Recorder registry. Owns the canonical state of every
    /// active recording — Dart-side `SessionRecorder` swaps to
    /// thin views over this once the frame-write driver lands.
    pub recorders: RecorderRegistry,
    /// Transfer queue. Owns the canonical task table + per-task
    /// progress; Tokio worker pool driver lands in a follow-up.
    pub transfers: TransferQueue,
    /// Port-forward registry. Owns the canonical rule table +
    /// status; Tokio listener-accept loops land in a follow-up.
    pub port_forwards: PortForwardRegistry,
    /// Import handle registry. Holds decrypted-but-not-yet-
    /// applied `.lfs` archives between the preview and apply FRB
    /// calls so plaintext entries never leak through the Dart
    /// heap during the user's preview review.
    pub imports: ImportRegistry,
}

impl AppState {
    fn new() -> Self {
        Self {
            secrets: SecretStore::new(),
            db: Mutex::new(None),
            bus: EventBus::new(),
            connections: ConnectionRegistry::new(),
            autolock: Arc::new(AutoLockMachine::new()),
            recorders: RecorderRegistry::new(),
            transfers: TransferQueue::new(),
            port_forwards: PortForwardRegistry::new(),
            imports: ImportRegistry::new(),
        }
    }

    /// Open the app DB at `path` with the given SQLCipher key. Runs
    /// on the caller's thread (rusqlite is blocking). Replaces any
    /// previously-initialised DB — used at startup once and on
    /// rekey events.
    pub fn db_init(&self, path: &Path, key: &[u8]) -> Result<(), Error> {
        let db = Db::open(path, key)?;
        let mut g = self.db.lock().expect("db slot lock");
        *g = Some(Arc::new(db));
        Ok(())
    }

    /// Fetch the DB handle. `None` when init hasn't run.
    pub fn db(&self) -> Option<Arc<Db>> {
        let g = self.db.lock().expect("db slot lock");
        g.clone()
    }

    /// Drop the running DB handle. Idempotent — calling twice is a
    /// no-op. Used by the auto-lock path to release the rusqlite
    /// connection (and SQLCipher's C-layer page-cipher state) when
    /// the user steps away. Unlock re-runs `db_init` to bring the
    /// handle back under the freshly re-derived master key.
    pub fn db_close(&self) {
        let mut g = self.db.lock().expect("db slot lock");
        *g = None;
    }
}

/// Build the singleton if it doesn't exist yet. Safe to call from
/// any thread; `OnceLock` serialises the first call. Starts the
/// auto-lock ticker on the first call so the idle timer runs for
/// the life of the process.
pub fn init() -> Arc<AppState> {
    let state = APP_STATE
        .get_or_init(|| {
            let app = Arc::new(AppState::new());
            app.autolock.clone().spawn_ticker();
            app
        })
        .clone();
    state
}

/// Fetch the running singleton. Panics if `init()` has not run —
/// callers should always go through the FRB `app_init` entry first.
pub fn instance() -> Arc<AppState> {
    APP_STATE
        .get()
        .expect("AppState not initialized — call app::init() first")
        .clone()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn init_is_idempotent() {
        let a = init();
        let b = init();
        assert!(Arc::ptr_eq(&a, &b));
    }

    #[test]
    fn secrets_round_trip_via_singleton() {
        let app = init();
        app.secrets.put("singleton-test", b"value");
        assert_eq!(&*app.secrets.get("singleton-test").unwrap(), b"value");
        app.secrets.drop_id("singleton-test");
    }
}
