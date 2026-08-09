//! Process-singleton registry mapping connection ids to live
//! [`Provider`] handles. The Rust-side transfer worker pool looks
//! up the provider by connection id when running a non-SSH task —
//! the SSH path uses `app.connections` (the russh actor map) and
//! routes through `crate::sftp::Sftp`, but WebDAV / S3 have no
//! russh actor, so without this registry the worker couldn't reach
//! their providers.
//!
//! Lifecycle: the FRB connect helpers (`webdav_connect`,
//! `s3_connect`) call [`ProviderRegistry::register`] right after
//! the connect probe succeeds. The returned opaque FRB handle
//! (`WebDavConnection` / `S3Connection`) holds a
//! [`ProviderRegistration`] guard that calls
//! [`ProviderRegistry::unregister`] on `Drop` — so the moment the
//! Dart side drops its handle (disconnect, app teardown), the
//! global slot frees. The registry never owns the only `Arc` to
//! the provider; the opaque handle on the Dart side does. The
//! registry's clone is purely a back-channel for the transfer
//! worker.
//!
//! Keying by **connection id** rather than session id matches the
//! existing `app.connections: ConnectionRegistry` shape — a single
//! saved session can spawn multiple reconnect attempts, each with
//! its own connection id, and the transfer queue tracks tasks by
//! the connection id the file browser captured at enqueue time.

use std::collections::HashMap;
use std::sync::{Arc, Mutex, Weak};

use crate::storage::Provider;

/// Process-singleton map: connection id → live [`Provider`].
///
/// Locking: a plain `Mutex` (not `RwLock`) — the registry is on
/// the hot path for every transfer task `execute`, but a transfer
/// rate of even 100/sec sees one lock per task lookup, and
/// contention against the connect/disconnect path is rare. Keep
/// the surface uniform with [`crate::secrets::SecretStore`].
#[derive(Default)]
pub struct ProviderRegistry {
    inner: Mutex<HashMap<String, Arc<dyn Provider>>>,
}

impl ProviderRegistry {
    pub fn new() -> Self {
        Self::default()
    }

    /// Register `provider` under `connection_id`. Replaces any
    /// prior entry under the same id — a re-connect on the same id
    /// (rare; the connections notifier mints a fresh UUID per
    /// attempt) gets the newer provider rather than two stale
    /// `Arc`s racing.
    pub fn register(&self, connection_id: &str, provider: Arc<dyn Provider>) {
        let mut g = self.inner.lock().unwrap_or_else(|e| e.into_inner());
        g.insert(connection_id.to_string(), provider);
    }

    /// Drop the entry under `connection_id`. Idempotent on a
    /// missing id (the FRB-opaque `Drop` may race with an explicit
    /// disconnect).
    pub fn unregister(&self, connection_id: &str) {
        let mut g = self.inner.lock().unwrap_or_else(|e| e.into_inner());
        g.remove(connection_id);
    }

    /// Fetch a clone of the provider Arc for `connection_id`.
    /// Returns `None` when the slot is empty — the caller (the
    /// transfer executor) treats that as "this is an SSH session,
    /// fall through to the russh actor path".
    pub fn get(&self, connection_id: &str) -> Option<Arc<dyn Provider>> {
        let g = self.inner.lock().unwrap_or_else(|e| e.into_inner());
        g.get(connection_id).cloned()
    }

    /// Whether a slot exists for `connection_id`. Cheap probe
    /// used by tests; production callers use [`Self::get`].
    pub fn contains(&self, connection_id: &str) -> bool {
        let g = self.inner.lock().unwrap_or_else(|e| e.into_inner());
        g.contains_key(connection_id)
    }
}

/// RAII guard that unregisters a connection id on `Drop`. The
/// FRB-opaque connect handle owns one — when the Dart side drops
/// the handle the guard drops, the registry slot frees, and the
/// `Arc<dyn Provider>` clone the registry held releases.
///
/// `registry` is held as a `Weak` so a guard outliving the global
/// `AppState` (only conceivable during process teardown) doesn't
/// dereference a dangling pointer.
pub struct ProviderRegistration {
    connection_id: String,
    registry: Weak<ProviderRegistry>,
}

impl ProviderRegistration {
    /// Create a guard tied to `registry` for `connection_id`. The
    /// caller is responsible for having called
    /// [`ProviderRegistry::register`] before constructing the
    /// guard; the two operations bookend a single registration.
    pub fn new(registry: Weak<ProviderRegistry>, connection_id: String) -> Self {
        Self {
            connection_id,
            registry,
        }
    }
}

impl Drop for ProviderRegistration {
    fn drop(&mut self) {
        if let Some(registry) = self.registry.upgrade() {
            registry.unregister(&self.connection_id);
        }
    }
}
#[cfg(test)]
#[path = "../../tests/unit/storage_registry.rs"]
mod tests;
