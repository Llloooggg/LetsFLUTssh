//! Helper hooks around the sessions / folders DAOs.
//!
//! The canonical session table lives in `lfs_core::db::sessions`
//! (rusqlite + SQLCipher); the Dart `SessionStore` mirrors it as
//! a UI snapshot. This module exposes [`notify_changed`] so the
//! FRB DAO wrappers can publish a single `SessionsChanged` event
//! after every successful write — sessions, folders, M2M
//! junctions, secret-slot updates, all coalesced under one
//! topic the Dart shim subscribes to.
//!
//! No state-bearing struct yet — the manager actor with cache +
//! folder cascade lives behind a separate arc. Today this is
//! the Rust-side push that lets the Dart cache stay in sync
//! without polling.

use std::sync::Arc;

use crate::app::AppState;
use crate::bus::Event;

/// Publish [`Event::SessionsChanged`] on the global bus. Called
/// by the FRB layer after every mutating session / folder DAO so
/// the Dart `SessionStore` re-fetches in one microtask-coalesced
/// reload rather than per-call.
pub fn notify_changed(app: &Arc<AppState>) {
    app.bus.publish(Event::SessionsChanged);
}
