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
        DbConnectionSnapshot {
            id: s.id,
            label: s.label,
            session_id: s.session_id,
            bastion_id: s.bastion_id,
            internal: s.internal,
            state_wire_name,
            error: s.error,
            host: s.host,
            port: s.port,
            user: s.user,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // The full connect / disconnect lifecycle drives
    // `lfs_core::connection::connect_async` against a live russh
    // peer; the `tests/connection_lifecycle.rs` integration binary
    // spins up `lfs_core::connection::test_server` and exercises
    // it end-to-end. The standalone tests below pin the
    // generation-tracking surface (no transport needed) + the
    // DbConnectionSnapshot wire-shape mapping.

    #[test]
    fn generation_init_then_bump_increments_counter() {
        let _ = lfs_core::app::init();
        let id = "api-conn-test-bump".to_string();
        connection_init_generation(id.clone());
        let after = connection_bump_generation(id.clone());
        assert!(after >= 2, "bump after init must yield at least 2");
        connection_drop_generation(id);
    }

    #[test]
    fn is_current_generation_returns_false_for_stale_value() {
        let _ = lfs_core::app::init();
        let id = "api-conn-test-stale".to_string();
        connection_init_generation(id.clone());
        let current = connection_bump_generation(id.clone());
        assert!(connection_is_current_generation(id.clone(), current));
        // Stale generation (one behind current) is not current.
        assert!(!connection_is_current_generation(id.clone(), current - 1));
        connection_drop_generation(id);
    }

    #[test]
    fn is_current_generation_returns_false_for_unknown_id() {
        let _ = lfs_core::app::init();
        // Unknown id — every generation check must return false so
        // late events from a removed actor stay dropped.
        assert!(!connection_is_current_generation(
            "api-conn-test-ghost".into(),
            1
        ));
    }

    #[test]
    fn drop_generation_unknown_id_is_idempotent() {
        let _ = lfs_core::app::init();
        // Disconnect path runs unconditionally; pin no-panic on
        // missing.
        connection_drop_generation("api-conn-test-already-dropped".into());
    }

    #[test]
    fn db_connection_snapshot_maps_each_state_wire_name() {
        // Pin the canonical wire-name strings the Dart
        // `SSHConnectionState.name` getter mirrors.
        for (state, expected) in [
            (
                lfs_core::connection::ConnectionState::Disconnected,
                "disconnected",
            ),
            (
                lfs_core::connection::ConnectionState::Connecting,
                "connecting",
            ),
            (
                lfs_core::connection::ConnectionState::Connected,
                "connected",
            ),
        ] {
            let core = lfs_core::connection::ConnectionSnapshot {
                id: "x".into(),
                label: "Edge".into(),
                session_id: Some("sess-x".into()),
                bastion_id: None,
                internal: false,
                state,
                progress: Vec::new(),
                error: None,
                host: "edge.example.com".into(),
                port: 22,
                user: "deploy".into(),
            };
            let db: DbConnectionSnapshot = core.into();
            assert_eq!(db.state_wire_name, expected);
        }
    }

    #[test]
    fn db_connection_snapshot_carries_every_field() {
        let core = lfs_core::connection::ConnectionSnapshot {
            id: "actor-1".into(),
            label: "Production Edge".into(),
            session_id: Some("sess-prod".into()),
            bastion_id: Some("bastion-1".into()),
            internal: true,
            state: lfs_core::connection::ConnectionState::Connecting,
            progress: Vec::new(),
            error: Some("timeout".into()),
            host: "edge.prod.example.com".into(),
            port: 2222,
            user: "deploy".into(),
        };
        let db: DbConnectionSnapshot = core.into();
        assert_eq!(db.id, "actor-1");
        assert_eq!(db.label, "Production Edge");
        assert_eq!(db.session_id.as_deref(), Some("sess-prod"));
        assert_eq!(db.bastion_id.as_deref(), Some("bastion-1"));
        assert!(db.internal);
        assert_eq!(db.state_wire_name, "connecting");
        assert_eq!(db.error.as_deref(), Some("timeout"));
        assert_eq!(db.host, "edge.prod.example.com");
        assert_eq!(db.port, 2222);
        assert_eq!(db.user, "deploy");
    }
}
