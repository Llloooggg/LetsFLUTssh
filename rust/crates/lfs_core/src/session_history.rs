//! Per-handle undo/redo stack for session-manager operations.
//!
//! The Dart `SessionHistory` class used to live as an in-memory
//! `List<SessionSnapshot>` pair. Moving it Rust-side puts state-
//! machine ownership in the same place every other domain actor
//! lives — single source of truth for "where does the user's undo
//! state actually live?". The actor stores opaque blobs (the Dart
//! side serialises `SessionSnapshot` to JSON and hands the bytes
//! over) plus the `description` string used for the undo/redo
//! menu labels. The Rust side never inspects the blobs — it just
//! provides bounded LIFO semantics and the description-getter
//! surface the UI consumes.
//!
//! Why per-handle instead of process-singleton: Riverpod's
//! `NotifierProvider` rebuild lifecycle creates a fresh
//! `SessionNotifier` per test container, and each owns its own
//! history. A process-singleton would leak undo state between
//! containers; per-handle keeps semantics matching the retired
//! Dart-side `final SessionHistory _history = SessionHistory();`
//! field.

use std::collections::HashMap;
use std::sync::{Mutex, OnceLock};

/// Cap on each per-pane history stack. 50 entries fit a typical
/// browsing session (cd → ls → cd back) without unbounded growth
/// when a script churns through directories in a tight loop.
const MAX_STACK: usize = 50;

/// Opaque handle the caller stores. `create` mints one; `drop_handle`
/// disposes the underlying state.
pub type HandleId = u64;

/// Single snapshot — opaque bytes + the description label.
#[derive(Debug, Clone)]
pub struct Snapshot {
    pub description: String,
    pub blob: Vec<u8>,
}

#[derive(Default)]
struct State {
    undo_stack: Vec<Snapshot>,
    redo_stack: Vec<Snapshot>,
}

static REGISTRY: OnceLock<Mutex<HashMap<HandleId, State>>> = OnceLock::new();
static NEXT_ID: OnceLock<Mutex<HandleId>> = OnceLock::new();

fn registry() -> &'static Mutex<HashMap<HandleId, State>> {
    REGISTRY.get_or_init(|| Mutex::new(HashMap::new()))
}

fn next_id() -> HandleId {
    let m = NEXT_ID.get_or_init(|| Mutex::new(1));
    let mut g = m.lock().unwrap_or_else(|e| e.into_inner());
    let id = *g;
    *g = g.wrapping_add(1);
    id
}

/// Mint a fresh history actor and return its handle id.
pub fn create() -> HandleId {
    let id = next_id();
    let mut reg = registry().lock().unwrap_or_else(|e| e.into_inner());
    reg.insert(id, State::default());
    id
}

/// Dispose the actor for `id`. Idempotent — disposing twice is a
/// no-op. Production callers tear down on `Notifier` dispose.
pub fn drop_handle(id: HandleId) {
    let mut reg = registry().lock().unwrap_or_else(|e| e.into_inner());
    reg.remove(&id);
}

/// Push a snapshot onto the undo stack. Clears the redo stack —
/// any new operation invalidates the redo path. Caps the undo
/// stack at `MAX_STACK`; oldest entry drops when full.
pub fn push_undo(id: HandleId, description: String, blob: Vec<u8>) {
    let mut reg = registry().lock().unwrap_or_else(|e| e.into_inner());
    let Some(state) = reg.get_mut(&id) else {
        return;
    };
    state.undo_stack.push(Snapshot { description, blob });
    if state.undo_stack.len() > MAX_STACK {
        state.undo_stack.remove(0);
    }
    state.redo_stack.clear();
}

/// Pop the last undo snapshot and push the caller's current state
/// onto the redo stack. Returns the popped snapshot, or `None`
/// when the undo stack is empty.
pub fn undo(id: HandleId, current_description: String, current_blob: Vec<u8>) -> Option<Snapshot> {
    let mut reg = registry().lock().unwrap_or_else(|e| e.into_inner());
    let state = reg.get_mut(&id)?;
    let popped = state.undo_stack.pop()?;
    state.redo_stack.push(Snapshot {
        description: current_description,
        blob: current_blob,
    });
    Some(popped)
}

/// Pop the last redo snapshot and push the caller's current state
/// onto the undo stack. Returns the popped snapshot, or `None`
/// when the redo stack is empty.
pub fn redo(id: HandleId, current_description: String, current_blob: Vec<u8>) -> Option<Snapshot> {
    let mut reg = registry().lock().unwrap_or_else(|e| e.into_inner());
    let state = reg.get_mut(&id)?;
    let popped = state.redo_stack.pop()?;
    state.undo_stack.push(Snapshot {
        description: current_description,
        blob: current_blob,
    });
    Some(popped)
}

/// Clear both stacks.
pub fn clear(id: HandleId) {
    let mut reg = registry().lock().unwrap_or_else(|e| e.into_inner());
    if let Some(state) = reg.get_mut(&id) {
        state.undo_stack.clear();
        state.redo_stack.clear();
    }
}

/// True when the undo stack is non-empty.
pub fn can_undo(id: HandleId) -> bool {
    registry()
        .lock()
        .ok()
        .and_then(|reg| reg.get(&id).map(|s| !s.undo_stack.is_empty()))
        .unwrap_or(false)
}

/// True when the redo stack is non-empty.
pub fn can_redo(id: HandleId) -> bool {
    registry()
        .lock()
        .ok()
        .and_then(|reg| reg.get(&id).map(|s| !s.redo_stack.is_empty()))
        .unwrap_or(false)
}

/// Description label of the topmost undo snapshot, or `None` when
/// empty. Surface used by the menu's "Undo: ..." copy.
pub fn undo_description(id: HandleId) -> Option<String> {
    registry()
        .lock()
        .ok()?
        .get(&id)?
        .undo_stack
        .last()
        .map(|s| s.description.clone())
}

/// Description label of the topmost redo snapshot.
pub fn redo_description(id: HandleId) -> Option<String> {
    registry()
        .lock()
        .ok()?
        .get(&id)?
        .redo_stack
        .last()
        .map(|s| s.description.clone())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn b(s: &str) -> Vec<u8> {
        s.as_bytes().to_vec()
    }

    #[test]
    fn fresh_handle_is_empty() {
        let id = create();
        assert!(!can_undo(id));
        assert!(!can_redo(id));
        assert!(undo_description(id).is_none());
        assert!(redo_description(id).is_none());
        drop_handle(id);
    }

    #[test]
    fn push_undo_enables_undo_and_records_description() {
        let id = create();
        push_undo(id, "delete".into(), b("blob1"));
        assert!(can_undo(id));
        assert_eq!(undo_description(id).as_deref(), Some("delete"));
        assert!(!can_redo(id));
        drop_handle(id);
    }

    #[test]
    fn undo_returns_snapshot_and_arms_redo() {
        let id = create();
        push_undo(id, "before".into(), b("snap_before"));
        let popped = undo(id, "current".into(), b("snap_current")).unwrap();
        assert_eq!(popped.description, "before");
        assert_eq!(popped.blob, b("snap_before"));
        assert!(!can_undo(id));
        assert!(can_redo(id));
        assert_eq!(redo_description(id).as_deref(), Some("current"));
        drop_handle(id);
    }

    #[test]
    fn redo_pops_arm_undo_and_returns_snapshot() {
        let id = create();
        push_undo(id, "step1".into(), b("s1"));
        let _ = undo(id, "step2".into(), b("s2"));
        let popped = redo(id, "s_present".into(), b("sp")).unwrap();
        assert_eq!(popped.description, "step2");
        assert_eq!(popped.blob, b("s2"));
        assert!(can_undo(id));
        assert!(!can_redo(id));
        drop_handle(id);
    }

    #[test]
    fn push_clears_redo_stack() {
        let id = create();
        push_undo(id, "op1".into(), b("o1"));
        let _ = undo(id, "current".into(), b("c"));
        assert!(can_redo(id));
        push_undo(id, "op2".into(), b("o2"));
        assert!(!can_redo(id));
        drop_handle(id);
    }

    #[test]
    fn undo_on_empty_returns_none() {
        let id = create();
        assert!(undo(id, "x".into(), b("x")).is_none());
        drop_handle(id);
    }

    #[test]
    fn redo_on_empty_returns_none() {
        let id = create();
        assert!(redo(id, "x".into(), b("x")).is_none());
        drop_handle(id);
    }

    #[test]
    fn max_stack_evicts_oldest() {
        let id = create();
        for i in 0..60 {
            push_undo(id, format!("op{i}"), b(&format!("blob{i}")));
        }
        assert_eq!(undo_description(id).as_deref(), Some("op59"));
        let mut count = 0;
        while can_undo(id) {
            let _ = undo(id, format!("c{count}"), b("c"));
            count += 1;
        }
        assert_eq!(count, MAX_STACK);
        drop_handle(id);
    }

    #[test]
    fn clear_empties_both_stacks() {
        let id = create();
        push_undo(id, "op".into(), b("o"));
        let _ = undo(id, "current".into(), b("c"));
        assert!(can_redo(id));
        clear(id);
        assert!(!can_undo(id));
        assert!(!can_redo(id));
        drop_handle(id);
    }

    #[test]
    fn handles_are_independent() {
        let a = create();
        let b_id = create();
        push_undo(a, "a-op".into(), b("a"));
        assert!(can_undo(a));
        assert!(!can_undo(b_id));
        push_undo(b_id, "b-op".into(), b("b"));
        assert_eq!(undo_description(a).as_deref(), Some("a-op"));
        assert_eq!(undo_description(b_id).as_deref(), Some("b-op"));
        drop_handle(a);
        assert!(can_undo(b_id));
        drop_handle(b_id);
    }
}
