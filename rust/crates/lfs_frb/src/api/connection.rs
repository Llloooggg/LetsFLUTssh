//! FRB adapter for `lfs_core::connection::ConnectionRegistry`
//! generation tracking.
//!
//! The Dart `ConnectionManager` carried a per-connection
//! generation counter inline (`_connectGeneration: Map<String, int>`)
//! to drop late-arriving bus events from a superseded reconnect
//! attempt. This shim moves the cache to the Rust registry so
//! the bump + check live one place; the future actor cutover
//! folds the check into the Rust event dispatcher itself.
//!
//! All endpoints are sync — one mutex acquire + a `HashMap`
//! lookup, sub-microsecond. The Dart caller hits them per
//! event; an async hop would buy nothing.

/// Initialise the generation counter for [`id`] to `1`. Call on
/// the initial connect.
#[flutter_rust_bridge::frb(sync)]
pub fn connection_init_generation(id: String) {
    lfs_core::app::instance().connections.init_generation(&id);
}

/// Bump the generation counter for [`id`] and return the new
/// value. Call on every reconnect attempt; pass the returned
/// value through the connect driver so late events check
/// against this number.
#[flutter_rust_bridge::frb(sync)]
pub fn connection_bump_generation(id: String) -> u32 {
    lfs_core::app::instance().connections.bump_generation(&id)
}

/// True when [`generation`] matches the current value for
/// [`id`]. Returns `false` for unknown ids.
#[flutter_rust_bridge::frb(sync)]
pub fn connection_is_current_generation(id: String, generation: u32) -> bool {
    lfs_core::app::instance()
        .connections
        .is_current_generation(&id, generation)
}

/// Drop the generation counter for [`id`]. Call on
/// disconnect / connection-removed.
#[flutter_rust_bridge::frb(sync)]
pub fn connection_drop_generation(id: String) {
    lfs_core::app::instance().connections.drop_generation(&id);
}

/// Drop every generation counter — used by the
/// `disconnectAll` / auto-lock teardown path.
#[flutter_rust_bridge::frb(sync)]
pub fn connection_clear_generations() {
    lfs_core::app::instance().connections.clear_generations();
}

/// FRB mirror of `lfs_core::connection::ConnectionSnapshot` — the
/// per-actor view a Dart consumer materialises against. Carries
/// no plaintext (credentials live in the SecretStore, bastion
/// linkage is by id only) so the wire shape is safe to ship to
/// any Riverpod-side renderer.
#[derive(Debug, Clone)]
pub struct DbConnectionSnapshot {
    pub id: String,
    pub label: String,
    pub session_id: Option<String>,
    pub bastion_id: Option<String>,
    pub internal: bool,
    /// `"disconnected" | "connecting" | "connected"`. Wire-name
    /// matches the existing Dart `SSHConnectionState.name` so a
    /// future `StreamProvider` mirror can map without an extra
    /// translation table.
    pub state_wire_name: String,
    pub error: Option<String>,
    pub host: String,
    pub port: u16,
    pub user: String,
}

impl From<lfs_core::connection::ConnectionSnapshot> for DbConnectionSnapshot {
    fn from(s: lfs_core::connection::ConnectionSnapshot) -> Self {
        let state_wire_name = match s.state {
            lfs_core::connection::ConnectionState::Disconnected => "disconnected",
            lfs_core::connection::ConnectionState::Connecting => "connecting",
            lfs_core::connection::ConnectionState::Connected => "connected",
        }
        .to_string();
        // Resolve host/port/user from the actor handle since
        // ConnectionSnapshot doesn't carry them today (the manager
        // tracked the destination Dart-side). Pull off the registry.
        let app = lfs_core::app::instance();
        let (host, port, user) = if let Some(handle) = app.connections.get(&s.id) {
            // Recover from a poisoned lock instead of panicking
            // across the FRB boundary — a panic here would tear
            // down the FRB worker thread mid-snapshot.
            let actor = handle.lock().unwrap_or_else(|p| p.into_inner());
            (actor.host.clone(), actor.port, actor.user.clone())
        } else {
            (String::new(), 0, String::new())
        };
        DbConnectionSnapshot {
            id: s.id,
            label: s.label,
            session_id: s.session_id,
            bastion_id: s.bastion_id,
            internal: s.internal,
            state_wire_name,
            error: s.error,
            host,
            port,
            user,
        }
    }
}

/// Snapshot every connection actor in the registry. Used by the
/// Rust-driven mirror provider that future workspace UI consumers
/// subscribe to in lieu of the Dart `ConnectionManager` map.
#[flutter_rust_bridge::frb(sync)]
pub fn connection_snapshot_all() -> Vec<DbConnectionSnapshot> {
    lfs_core::app::instance()
        .connections
        .snapshot_all()
        .into_iter()
        .map(Into::into)
        .collect()
}
