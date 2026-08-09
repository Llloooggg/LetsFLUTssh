/// Unit tests extracted from transfer/mod.rs
/// Declared via `#[path] mod tests;` in the source file.
use super::*;

#[test]
fn enqueue_and_progress() {
    let bus = EventBus::new();
    let q = TransferQueue::new();
    q.enqueue(
        EnqueueRequest {
            id: "t1".into(),
            kind: TaskKind::Download,
            session_id: "s1".into(),
            remote_path: "/r/path".into(),
            local_path: "/l/path".into(),
            bytes_total: 1024,
        },
        &bus,
    );
    q.set_progress("t1", 512, &bus);
    let snap = q.snapshot("t1").unwrap();
    assert_eq!(snap.bytes_done, 512);
    assert_eq!(snap.bytes_total, 1024);
    assert_eq!(snap.state, TaskState::Queued);
}

/// Regression for the bus-event storm: tight `set_progress`
/// calls per 64 KiB chunk used to publish one event each (~3200
/// events/s/conn at 100 MB/s — full Dart-side history snapshot
/// rebuild for every event). Throttling caps at one event per
/// 256 KiB (or per 100 ms — see `PROGRESS_BYTES_THRESHOLD` /
/// `PROGRESS_TIME_THRESHOLD`). 16 calls of 64 KiB increments
/// against a 10 MiB total cover that ladder: first publish
/// (always fires), then every 4-th call clears the byte
/// threshold. Sub-100 ms wall time so the time-based threshold
/// does NOT fire for the in-between calls.
#[test]
fn set_progress_throttles_high_frequency_byte_deltas() {
    let bus = EventBus::new();
    let mut rx = bus.subscribe(crate::bus::EventTopic::Transfer);
    let q = TransferQueue::new();
    q.enqueue(
        EnqueueRequest {
            id: "t1".into(),
            kind: TaskKind::Download,
            session_id: "s1".into(),
            remote_path: "/r".into(),
            local_path: "/l".into(),
            bytes_total: 10 * 1024 * 1024,
        },
        &bus,
    );
    // Drain the TransferTaskAdded event so the receiver only
    // sees TransferTaskProgress hits.
    let _ = rx.try_recv();
    const CHUNK: u64 = 64 * 1024;
    for i in 1..=16 {
        q.set_progress("t1", CHUNK * i, &bus);
    }
    // Snapshot reflects the LATEST byte count regardless of
    // throttle — counter updates are non-skipped.
    assert_eq!(q.snapshot("t1").unwrap().bytes_done, CHUNK * 16);
    // Count the published progress events. With a 256 KiB
    // threshold we expect 1 (first publish) + 1 every 4 chunks
    // ≤ 5 total. Without the throttle this would be 16.
    let mut progress_events = 0;
    while let Ok(evt) = rx.try_recv() {
        if let Event::TransferTaskProgress { .. } = evt {
            progress_events += 1;
        }
    }
    assert!(
        progress_events <= 5,
        "expected ≤ 5 throttled progress events, got {progress_events}"
    );
    assert!(
        progress_events >= 1,
        "first publish must always fire, got {progress_events}"
    );
}

/// The completion edge — `bytes_done == bytes_total > 0` —
/// must publish unconditionally so the Dart UI sees the final
/// counter value before the state→Completed transition.
#[test]
fn set_progress_publishes_final_value_unconditionally() {
    let bus = EventBus::new();
    let mut rx = bus.subscribe(crate::bus::EventTopic::Transfer);
    let q = TransferQueue::new();
    q.enqueue(
        EnqueueRequest {
            id: "t1".into(),
            kind: TaskKind::Upload,
            session_id: "s1".into(),
            remote_path: "/r".into(),
            local_path: "/l".into(),
            bytes_total: 1024,
        },
        &bus,
    );
    let _ = rx.try_recv();
    q.set_progress("t1", 1, &bus); // first publish (always)
                                   // A near-zero delta would normally be throttled. The
                                   // completion check overrides because bytes_done == total.
    q.set_progress("t1", 1024, &bus);
    let mut saw_complete = false;
    while let Ok(evt) = rx.try_recv() {
        if let Event::TransferTaskProgress {
            bytes_done: 1024, ..
        } = evt
        {
            saw_complete = true;
        }
    }
    assert!(
        saw_complete,
        "completion publish must fire even on tiny delta"
    );
}

#[test]
fn fail_records_error() {
    let bus = EventBus::new();
    let q = TransferQueue::new();
    q.enqueue(
        EnqueueRequest {
            id: "t1".into(),
            kind: TaskKind::Upload,
            session_id: "s1".into(),
            remote_path: "/r".into(),
            local_path: "/l".into(),
            bytes_total: 0,
        },
        &bus,
    );
    q.fail("t1", "permission denied".into(), &bus);
    let snap = q.snapshot("t1").unwrap();
    assert_eq!(snap.state, TaskState::Failed);
    assert_eq!(snap.error.as_deref(), Some("permission denied"));
}

#[test]
fn cancel_running_task() {
    let bus = EventBus::new();
    let q = TransferQueue::new();
    q.enqueue(
        EnqueueRequest {
            id: "t1".into(),
            kind: TaskKind::Download,
            session_id: "s1".into(),
            remote_path: "/r".into(),
            local_path: "/l".into(),
            bytes_total: 0,
        },
        &bus,
    );
    q.set_state("t1", TaskState::Running, &bus);
    assert!(q.cancel("t1", &bus));
    assert_eq!(q.snapshot("t1").unwrap().state, TaskState::Cancelled);
}

#[test]
fn cancel_completed_is_noop() {
    let bus = EventBus::new();
    let q = TransferQueue::new();
    q.enqueue(
        EnqueueRequest {
            id: "t1".into(),
            kind: TaskKind::Download,
            session_id: "s1".into(),
            remote_path: "/r".into(),
            local_path: "/l".into(),
            bytes_total: 0,
        },
        &bus,
    );
    q.set_state("t1", TaskState::Completed, &bus);
    assert!(!q.cancel("t1", &bus));
    assert_eq!(q.snapshot("t1").unwrap().state, TaskState::Completed);
}

#[test]
fn cancel_failed_does_not_clobber_error() {
    let bus = EventBus::new();
    let q = TransferQueue::new();
    q.enqueue(
        EnqueueRequest {
            id: "t1".into(),
            kind: TaskKind::Download,
            session_id: "s1".into(),
            remote_path: "/r".into(),
            local_path: "/l".into(),
            bytes_total: 0,
        },
        &bus,
    );
    q.fail("t1", "boom".into(), &bus);
    assert!(!q.cancel("t1", &bus));
    let snap = q.snapshot("t1").unwrap();
    assert_eq!(snap.state, TaskState::Failed);
    assert_eq!(snap.error.as_deref(), Some("boom"));
}

#[test]
fn cancel_missing_id_returns_false() {
    let bus = EventBus::new();
    let q = TransferQueue::new();
    assert!(!q.cancel("ghost", &bus));
}

#[test]
fn drop_terminal_removes_completed_task() {
    let bus = EventBus::new();
    let q = TransferQueue::new();
    q.enqueue(
        EnqueueRequest {
            id: "t1".into(),
            kind: TaskKind::Upload,
            session_id: "s1".into(),
            remote_path: "/r".into(),
            local_path: "/l".into(),
            bytes_total: 0,
        },
        &bus,
    );
    q.set_state("t1", TaskState::Completed, &bus);
    assert!(q.drop_terminal("t1"));
    assert!(q.snapshot("t1").is_none());
    assert_eq!(q.count(), 0);
}

#[test]
fn drop_terminal_refuses_running_task() {
    let bus = EventBus::new();
    let q = TransferQueue::new();
    q.enqueue(
        EnqueueRequest {
            id: "t1".into(),
            kind: TaskKind::Upload,
            session_id: "s1".into(),
            remote_path: "/r".into(),
            local_path: "/l".into(),
            bytes_total: 0,
        },
        &bus,
    );
    q.set_state("t1", TaskState::Running, &bus);
    assert!(!q.drop_terminal("t1"));
    assert_eq!(q.count(), 1);
}

#[test]
fn snapshot_all_preserves_insertion_order() {
    let bus = EventBus::new();
    let q = TransferQueue::new();
    for n in 0..5 {
        q.enqueue(
            EnqueueRequest {
                id: format!("t{n}"),
                kind: TaskKind::Download,
                session_id: "s1".into(),
                remote_path: "/r".into(),
                local_path: "/l".into(),
                bytes_total: 0,
            },
            &bus,
        );
    }
    let ids: Vec<String> = q.snapshot_all().into_iter().map(|s| s.id).collect();
    assert_eq!(ids, vec!["t0", "t1", "t2", "t3", "t4"]);
}
