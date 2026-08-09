/// Unit tests extracted from recorder/queue.rs
/// Declared via `#[path] mod tests;` in the source file.
use super::*;

fn tempfile(suffix: &str) -> String {
    use std::sync::atomic::{AtomicU64, Ordering};
    static SEQ: AtomicU64 = AtomicU64::new(0);
    let n = SEQ.fetch_add(1, Ordering::SeqCst);
    let pid = std::process::id();
    let dir = std::env::temp_dir();
    dir.join(format!("lfs_recorder_queue_test_{pid}_{n}_{suffix}"))
        .to_string_lossy()
        .into_owned()
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn enqueue_event_via_singleton_serialises_writes() {
    // App + registry + queue are singletons. Smoke that
    // enqueueing through the queue lands a frame on disk.
    let app = crate::app::init();
    let path = tempfile("queue-enqueue");
    let id = format!("queue-{}", uuid_like());
    app.recorders
        .register_with_io(id.clone(), "s".into(), path.clone(), None, &app.bus)
        .expect("register");
    app.recorder_queue.spawn(id.clone()).await;

    for chunk in 0..16 {
        app.recorder_queue
            .enqueue(
                &id,
                QueueEntry::Event {
                    kind: RecordDirection::Output,
                    bytes: format!("chunk-{chunk}\n").into_bytes(),
                },
            )
            .await
            .expect("enqueue");
    }
    // Close drains the channel + closes the file.
    app.recorder_queue
        .enqueue(&id, QueueEntry::Close)
        .await
        .expect("close enqueue");
    // Give the worker a tick to drain.
    tokio::time::sleep(std::time::Duration::from_millis(150)).await;
    let body = std::fs::read_to_string(&path).expect("read");
    // Plaintext mode → events appear verbatim, in order.
    for chunk in 0..16 {
        let token = format!("chunk-{chunk}");
        assert!(body.contains(&token), "expected {token:?} in {body:?}");
    }
    // Ordering check: chunk-0 appears before chunk-15.
    let pos_first = body.find("chunk-0").expect("first");
    let pos_last = body.find("chunk-15").expect("last");
    assert!(pos_first < pos_last, "events out of order: {body:?}");
    let _ = std::fs::remove_file(&path);
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn enqueue_close_drops_worker() {
    let app = crate::app::init();
    let path = tempfile("queue-close");
    let id = format!("queue-close-{}", uuid_like());
    app.recorders
        .register_with_io(id.clone(), "s".into(), path.clone(), None, &app.bus)
        .expect("register");
    app.recorder_queue.spawn(id.clone()).await;
    let before = app.recorder_queue.worker_count().await;
    assert!(before >= 1, "spawn should add a worker");
    app.recorder_queue
        .enqueue(&id, QueueEntry::Close)
        .await
        .expect("close enqueue");
    // Worker is async; poll briefly until it's gone.
    for _ in 0..50 {
        tokio::time::sleep(std::time::Duration::from_millis(20)).await;
        let g = app.recorder_queue.workers.lock().await;
        if !g.contains_key(&id) {
            let _ = std::fs::remove_file(&path);
            return;
        }
    }
    panic!("worker never dropped");
}

/// Sequence-suffixed id so concurrent test cases don't collide
/// inside the singleton registry.
fn uuid_like() -> String {
    use std::sync::atomic::{AtomicU64, Ordering};
    static SEQ: AtomicU64 = AtomicU64::new(0);
    let n = SEQ.fetch_add(1, Ordering::SeqCst);
    let pid = std::process::id();
    format!("{pid}-{n}")
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn enqueue_event_chunk_coalesces_under_threshold() {
    let app = crate::app::init();
    let path = tempfile("chunk-coalesce");
    let id = format!("queue-chunk-{}", uuid_like());
    app.recorders
        .register_with_io(id.clone(), "s".into(), path.clone(), None, &app.bus)
        .expect("register");
    app.recorder_queue.spawn(id.clone()).await;

    // Three small chunks well under the 8 KiB threshold. The
    // 10 ms timer is what eventually pushes them to the worker.
    for word in ["alpha", "bravo", "charlie"] {
        app.recorder_queue
            .enqueue_event_chunk(&id, RecordDirection::Output, word.as_bytes().to_vec())
            .await
            .expect("chunk");
    }
    // Wait long enough for the deadline to fire and the worker to
    // drain.
    tokio::time::sleep(Duration::from_millis(150)).await;
    app.recorder_queue
        .enqueue_blocking(&id, QueueEntry::Close)
        .await
        .expect("close");
    tokio::time::sleep(Duration::from_millis(150)).await;

    let body = std::fs::read_to_string(&path).expect("read");
    // The three chunks merged into one asciinema event line —
    // i.e. the substring `"alphabravocharlie"` must appear once
    // (the JSON payload escaping doesn't split runs of ASCII
    // letters).
    assert!(
        body.contains("alphabravocharlie"),
        "expected coalesced chunk in {body:?}"
    );
    let _ = std::fs::remove_file(&path);
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn enqueue_event_chunk_flushes_on_threshold() {
    let app = crate::app::init();
    let path = tempfile("chunk-threshold");
    let id = format!("queue-thresh-{}", uuid_like());
    app.recorders
        .register_with_io(id.clone(), "s".into(), path.clone(), None, &app.bus)
        .expect("register");
    app.recorder_queue.spawn(id.clone()).await;

    // One chunk over the threshold — flush should run before the
    // 10 ms timer would fire.
    let big = vec![b'A'; FLUSH_THRESHOLD_BYTES + 1];
    app.recorder_queue
        .enqueue_event_chunk(&id, RecordDirection::Output, big)
        .await
        .expect("chunk");
    // Brief wait — much shorter than the 10 ms deadline — to let
    // the worker process the immediate-flush mailbox entry.
    tokio::time::sleep(Duration::from_millis(50)).await;
    app.recorder_queue
        .enqueue_blocking(&id, QueueEntry::Close)
        .await
        .expect("close");
    tokio::time::sleep(Duration::from_millis(150)).await;

    let body = std::fs::read_to_string(&path).expect("read");
    // The 8 KiB+ run lands as a single event line in the file.
    let run = "A".repeat(FLUSH_THRESHOLD_BYTES + 1);
    assert!(
        body.contains(&run),
        "expected over-threshold chunk verbatim"
    );
    let _ = std::fs::remove_file(&path);
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn enqueue_blocking_drains_pending_chunks_before_entry() {
    let app = crate::app::init();
    let path = tempfile("blocking-drain");
    let id = format!("queue-drain-{}", uuid_like());
    app.recorders
        .register_with_io(id.clone(), "s".into(), path.clone(), None, &app.bus)
        .expect("register");
    app.recorder_queue.spawn(id.clone()).await;

    // Buffer some bytes that haven't crossed the threshold and
    // would otherwise wait for the 10 ms timer.
    app.recorder_queue
        .enqueue_event_chunk(&id, RecordDirection::Output, b"pending-payload".to_vec())
        .await
        .expect("chunk");
    // Close must drain the buffered chunk first. Without the
    // pre-entry drain the trailing bytes would race the file
    // close and disappear.
    app.recorder_queue
        .enqueue_blocking(&id, QueueEntry::Close)
        .await
        .expect("close");
    tokio::time::sleep(Duration::from_millis(150)).await;

    let body = std::fs::read_to_string(&path).expect("read");
    assert!(
        body.contains("pending-payload"),
        "buffered chunk lost across close: {body:?}"
    );
    let _ = std::fs::remove_file(&path);
}
