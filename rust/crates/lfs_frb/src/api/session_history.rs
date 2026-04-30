//! FRB adapter for `lfs_core::session_history`. Per-handle
//! undo/redo stack — Dart serialises `SessionSnapshot` to bytes,
//! Rust stores opaque blobs + the description label.

#[derive(Debug, Clone)]
pub struct DbSessionHistorySnapshot {
    pub description: String,
    pub blob: Vec<u8>,
}

#[flutter_rust_bridge::frb(sync)]
pub fn session_history_create() -> u64 {
    lfs_core::session_history::create()
}

#[flutter_rust_bridge::frb(sync)]
pub fn session_history_drop(handle_id: u64) {
    lfs_core::session_history::drop_handle(handle_id);
}

#[flutter_rust_bridge::frb(sync)]
pub fn session_history_push_undo(handle_id: u64, description: String, blob: Vec<u8>) {
    lfs_core::session_history::push_undo(handle_id, description, blob);
}

#[flutter_rust_bridge::frb(sync)]
pub fn session_history_undo(
    handle_id: u64,
    current_description: String,
    current_blob: Vec<u8>,
) -> Option<DbSessionHistorySnapshot> {
    lfs_core::session_history::undo(handle_id, current_description, current_blob).map(|s| {
        DbSessionHistorySnapshot {
            description: s.description,
            blob: s.blob,
        }
    })
}

#[flutter_rust_bridge::frb(sync)]
pub fn session_history_redo(
    handle_id: u64,
    current_description: String,
    current_blob: Vec<u8>,
) -> Option<DbSessionHistorySnapshot> {
    lfs_core::session_history::redo(handle_id, current_description, current_blob).map(|s| {
        DbSessionHistorySnapshot {
            description: s.description,
            blob: s.blob,
        }
    })
}

#[flutter_rust_bridge::frb(sync)]
pub fn session_history_clear(handle_id: u64) {
    lfs_core::session_history::clear(handle_id);
}

#[flutter_rust_bridge::frb(sync)]
pub fn session_history_can_undo(handle_id: u64) -> bool {
    lfs_core::session_history::can_undo(handle_id)
}

#[flutter_rust_bridge::frb(sync)]
pub fn session_history_can_redo(handle_id: u64) -> bool {
    lfs_core::session_history::can_redo(handle_id)
}

#[flutter_rust_bridge::frb(sync)]
pub fn session_history_undo_description(handle_id: u64) -> Option<String> {
    lfs_core::session_history::undo_description(handle_id)
}

#[flutter_rust_bridge::frb(sync)]
pub fn session_history_redo_description(handle_id: u64) -> Option<String> {
    lfs_core::session_history::redo_description(handle_id)
}
