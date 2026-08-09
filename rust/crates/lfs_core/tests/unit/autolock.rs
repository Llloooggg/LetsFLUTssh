/// Unit tests extracted from autolock.rs
/// Declared via `#[path] mod tests;` in the source file.
use super::*;

#[test]
fn set_timeout_publishes_event() {
    let bus = EventBus::new();
    let mut rx = bus.subscribe(crate::bus::EventTopic::AutoLock);
    let m = AutoLockMachine::new();
    m.set_timeout_minutes(5, &bus);
    assert_eq!(m.timeout_minutes(), 5);
    match rx.try_recv().expect("event") {
        Event::AutoLockTimeoutChanged { minutes } => assert_eq!(minutes, 5),
        other => panic!("unexpected event: {other:?}"),
    }
}

#[test]
fn negative_timeout_clamps_to_zero() {
    let bus = EventBus::new();
    let m = AutoLockMachine::new();
    m.set_timeout_minutes(-3, &bus);
    assert_eq!(m.timeout_minutes(), 0);
}

#[test]
fn pointer_activity_advances_last_activity() {
    let bus = EventBus::new();
    let m = AutoLockMachine::new();
    m.set_timeout_minutes(10, &bus);
    let before = m.lock().last_activity_ms;
    std::thread::sleep(Duration::from_millis(2));
    m.on_pointer_activity();
    assert!(m.lock().last_activity_ms > before);
}

#[test]
fn unlock_when_already_unlocked_is_idempotent() {
    let bus = EventBus::new();
    let mut rx = bus.subscribe(crate::bus::EventTopic::AutoLock);
    let m = AutoLockMachine::new();
    m.unlock(&bus);
    assert!(rx.try_recv().is_err(), "no event when not locked");
    assert!(!m.is_locked());
}

#[test]
fn lifecycle_foreground_does_not_lock() {
    let bus = EventBus::new();
    let m = AutoLockMachine::new();
    m.set_timeout_minutes(5, &bus);
    m.on_lifecycle_change(LifecycleState::Foreground, &bus);
    assert!(!m.is_locked());
}

#[test]
fn lifecycle_background_with_zero_timeout_does_not_lock() {
    let bus = EventBus::new();
    let m = AutoLockMachine::new();
    // Timeout left at 0 (off) — backgrounding must NOT lock.
    m.on_lifecycle_change(LifecycleState::Background, &bus);
    assert!(!m.is_locked());
}

#[test]
fn request_lock_publishes_locked_and_runs_action() {
    use std::sync::atomic::{AtomicU32, Ordering};
    let counter = Arc::new(AtomicU32::new(0));
    let bus = EventBus::new();
    let mut rx = bus.subscribe(crate::bus::EventTopic::AutoLock);
    let m = AutoLockMachine::new();
    let c2 = counter.clone();
    m.set_lock_action(Arc::new(move || {
        c2.fetch_add(1, Ordering::SeqCst);
    }));
    m.request_lock(&bus);
    assert!(m.is_locked());
    assert_eq!(counter.load(Ordering::SeqCst), 1);
    match rx.try_recv().expect("event") {
        Event::AutoLockLocked => {}
        other => panic!("unexpected event: {other:?}"),
    }
}

#[test]
fn request_lock_when_already_locked_is_idempotent() {
    use std::sync::atomic::{AtomicU32, Ordering};
    let counter = Arc::new(AtomicU32::new(0));
    let bus = EventBus::new();
    let m = AutoLockMachine::new();
    let c2 = counter.clone();
    m.set_lock_action(Arc::new(move || {
        c2.fetch_add(1, Ordering::SeqCst);
    }));
    m.request_lock(&bus);
    m.request_lock(&bus);
    assert_eq!(counter.load(Ordering::SeqCst), 1);
}

#[test]
fn unlock_after_lock_publishes_unlocked() {
    let bus = EventBus::new();
    let mut rx = bus.subscribe(crate::bus::EventTopic::AutoLock);
    let m = AutoLockMachine::new();
    m.set_lock_action(Arc::new(|| {}));
    m.request_lock(&bus);
    // Drain the Locked event.
    rx.try_recv().unwrap();
    m.unlock(&bus);
    assert!(!m.is_locked());
    match rx.try_recv().expect("event") {
        Event::AutoLockUnlocked => {}
        other => panic!("unexpected event: {other:?}"),
    }
}

#[test]
fn lifecycle_background_with_timeout_locks() {
    use std::sync::atomic::{AtomicU32, Ordering};
    let counter = Arc::new(AtomicU32::new(0));
    let bus = EventBus::new();
    let m = AutoLockMachine::new();
    let c2 = counter.clone();
    m.set_lock_action(Arc::new(move || {
        c2.fetch_add(1, Ordering::SeqCst);
    }));
    m.set_timeout_minutes(5, &bus);
    m.on_lifecycle_change(LifecycleState::Background, &bus);
    assert!(m.is_locked());
    assert_eq!(counter.load(Ordering::SeqCst), 1);
}
