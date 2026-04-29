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
