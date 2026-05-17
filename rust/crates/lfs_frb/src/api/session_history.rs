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

#[cfg(test)]
mod tests {
    use super::*;

    fn fresh_handle() -> u64 {
        let h = session_history_create();
        // Reset state in case a previous test left this handle dirty
        // (the registry is a process-wide singleton).
        session_history_clear(h);
        h
    }

    #[test]
    fn fresh_handle_can_neither_undo_nor_redo() {
        let h = fresh_handle();
        assert!(!session_history_can_undo(h));
        assert!(!session_history_can_redo(h));
        assert!(session_history_undo_description(h).is_none());
        assert!(session_history_redo_description(h).is_none());
        session_history_drop(h);
    }

    #[test]
    fn push_then_undo_round_trips_blob_and_description() {
        let h = fresh_handle();
        session_history_push_undo(h, "added session".into(), b"old-blob".to_vec());
        assert!(session_history_can_undo(h));
        assert_eq!(
            session_history_undo_description(h),
            Some("added session".to_string())
        );

        // Undo with a "current" snapshot — the registry pushes the
        // current state to the redo stack and pops the previous
        // entry off the undo stack.
        let undone = session_history_undo(h, "current".into(), b"new-blob".to_vec())
            .expect("undo yields previous snapshot");
        assert_eq!(undone.description, "added session");
        assert_eq!(undone.blob, b"old-blob");
        assert!(session_history_can_redo(h));
        assert!(!session_history_can_undo(h));
        session_history_drop(h);
    }

    #[test]
    fn redo_after_undo_round_trips_current_state() {
        let h = fresh_handle();
        session_history_push_undo(h, "step-1".into(), b"v1".to_vec());
        let _ = session_history_undo(h, "step-2".into(), b"v2".to_vec());
        // The stash from the undo (description="step-2", blob=b"v2")
        // is on the redo stack now. Redoing replays it.
        let redone = session_history_redo(h, "back-to-1".into(), b"v1".to_vec())
            .expect("redo yields stashed snapshot");
        assert_eq!(redone.description, "step-2");
        assert_eq!(redone.blob, b"v2");
        session_history_drop(h);
    }

    #[test]
    fn clear_drops_both_stacks() {
        let h = fresh_handle();
        session_history_push_undo(h, "x".into(), b"x".to_vec());
        session_history_clear(h);
        assert!(!session_history_can_undo(h));
        assert!(!session_history_can_redo(h));
        session_history_drop(h);
    }

    #[test]
    fn drop_handle_is_idempotent_on_unknown_id() {
        // Dart wrappers may call drop after a handle has already
        // been GC'd through the bus path; the call must be a no-op
        // rather than panic.
        session_history_drop(0xDEAD_BEEF);
    }
}
