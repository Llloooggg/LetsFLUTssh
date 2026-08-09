/// Unit tests extracted from session_history.rs
/// Declared via `#[path] mod tests;` in the source file.
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
