//! Auto-lock state machine.
//!
//! Owns the canonical idle-lock state. Dart side dispatches
//! lifecycle + activity commands through the bus; Rust mutates
//! state, runs the idle timer on a Tokio task, and emits `Locked`
//! / `Unlocked` events that view-models pick up.
//!
//! # State model
//!
//! Tracks last-activity timestamp + configured timeout. A
//! background ticker fires every second; when
//! `now - last_activity >= lock_after`, the machine flips
//! `locked = true`, calls `db_close()` to zero the SQLCipher
//! page-cipher state, clears the SecretStore, and publishes
//! `Event::AutoLockLocked`. The `Unlock` command flips it back +
//! emits `AutoLockUnlocked` (the actual key derivation happens in
//! the Dart unlock dialog and is fed back through the
//! `secrets_*` + `db_init` FRB calls).
//!
//! Lifecycle: `lock_after_ms = 0` disables the timer entirely
//! ("Off"). Backgrounding the app while the timeout is non-zero
//! triggers an immediate lock, mirroring the Dart-era
//! `AutoLockDetector.didChangeAppLifecycleState` policy.

use std::sync::Mutex;
use std::time::Duration;

use tokio::sync::Notify;

use crate::bus::{Event, EventBus};

/// Mirrors the Dart `AppLifecycleState` enum the lifecycle
/// observer dispatches. We only care about the foreground /
/// background distinction — `inactive` and `paused` both count
/// as "user stepped away".
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LifecycleState {
    Foreground,
    Background,
}

#[derive(Debug, Clone)]
struct State {
    last_activity_ms: i64,
    lock_after_ms: i64,
    lifecycle: LifecycleState,
    locked: bool,
}

impl State {
    fn now_ms() -> i64 {
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_millis() as i64)
            .unwrap_or(0)
    }
}

/// Process-singleton state machine. Owned by [`crate::app::AppState`].
pub struct AutoLockMachine {
    inner: Mutex<State>,
    /// Wakes the ticker task on state transitions so a freshly
    /// configured timeout takes effect without waiting for the
    /// next tick.
    waker: Notify,
}

impl AutoLockMachine {
    pub fn new() -> Self {
        Self {
            inner: Mutex::new(State {
                last_activity_ms: State::now_ms(),
                lock_after_ms: 0,
                lifecycle: LifecycleState::Foreground,
                locked: false,
            }),
            waker: Notify::new(),
        }
    }

    fn lock(&self) -> std::sync::MutexGuard<'_, State> {
        self.inner.lock().expect("autolock mutex poisoned")
    }

    /// User interacted with the app — reset the idle countdown.
    pub fn on_pointer_activity(&self) {
        let mut g = self.lock();
        g.last_activity_ms = State::now_ms();
        // Activity wakes the ticker so it re-computes the
        // remaining-until-lock window.
        self.waker.notify_one();
    }

    /// App lifecycle change. Backgrounding while a timeout is
    /// configured locks immediately (mirrors the Dart policy).
    pub fn on_lifecycle_change(&self, state: LifecycleState, bus: &EventBus) {
        let mut g = self.lock();
        let was = g.lifecycle;
        g.lifecycle = state;
        if state == LifecycleState::Background && g.lock_after_ms > 0 && !g.locked {
            g.locked = true;
            drop(g);
            self.fire_lock(bus);
            return;
        }
        if state != was {
            // Coming back to the foreground resets the activity
            // clock so the user gets a fresh idle window.
            g.last_activity_ms = State::now_ms();
            self.waker.notify_one();
        }
    }

    /// Configure the idle timeout in minutes (0 = off).
    pub fn set_timeout_minutes(&self, minutes: i64, bus: &EventBus) {
        let lock_after_ms = minutes.max(0) * 60_000;
        {
            let mut g = self.lock();
            g.lock_after_ms = lock_after_ms;
            g.last_activity_ms = State::now_ms();
        }
        bus.publish(Event::AutoLockTimeoutChanged {
            minutes: minutes.max(0),
        });
        self.waker.notify_one();
    }

    /// Force a lock (Settings → Lock now / explicit gesture).
    pub fn request_lock(&self, bus: &EventBus) {
        {
            let mut g = self.lock();
            if g.locked {
                return;
            }
            g.locked = true;
        }
        self.fire_lock(bus);
    }

    /// Release the lock — the Dart unlock dialog has supplied a
    /// fresh key + reopened the DB, so the machine resets its
    /// activity clock and emits `Unlocked`.
    pub fn unlock(&self, bus: &EventBus) {
        {
            let mut g = self.lock();
            if !g.locked {
                return;
            }
            g.locked = false;
            g.last_activity_ms = State::now_ms();
        }
        bus.publish(Event::AutoLockUnlocked);
        self.waker.notify_one();
    }

    /// True when the machine is in the locked state.
    pub fn is_locked(&self) -> bool {
        self.lock().locked
    }

    /// Configured timeout in minutes (0 = off).
    pub fn timeout_minutes(&self) -> i64 {
        self.lock().lock_after_ms / 60_000
    }

    fn fire_lock(&self, bus: &EventBus) {
        // Zero the cached secrets + close the encrypted DB so
        // SQLCipher's C-layer page-cipher state is wiped at the
        // same instant the lock event fires.
        let app = crate::app::instance();
        app.secrets.clear();
        app.db_close();
        bus.publish(Event::AutoLockLocked);
    }

    /// Spin off the background ticker. Called once during
    /// `AppState` initialisation; the task lives for the life of
    /// the process. Wakes on the configured tick interval or on
    /// any state transition (`Notify`) so a freshly applied
    /// timeout / activity ping takes effect within the same
    /// tokio cycle.
    ///
    /// No-op when no tokio runtime is reachable — synchronous
    /// unit tests that call `app::init()` outside a runtime
    /// context would otherwise panic on the spawn.
    pub fn spawn_ticker(self: std::sync::Arc<Self>) {
        if tokio::runtime::Handle::try_current().is_err() {
            return;
        }
        tokio::spawn(async move {
            loop {
                let sleep = tokio::time::sleep(Duration::from_secs(1));
                let waker = self.waker.notified();
                tokio::pin!(sleep);
                tokio::pin!(waker);
                tokio::select! {
                    _ = &mut sleep => {},
                    _ = &mut waker => {},
                }

                let should_lock = {
                    let g = self.lock();
                    !g.locked
                        && g.lock_after_ms > 0
                        && State::now_ms() - g.last_activity_ms >= g.lock_after_ms
                };
                if should_lock {
                    let mut g = self.lock();
                    if g.locked {
                        continue;
                    }
                    g.locked = true;
                    drop(g);
                    let app = crate::app::instance();
                    self.fire_lock(&app.bus);
                }
            }
        });
    }
}

impl Default for AutoLockMachine {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn set_timeout_publishes_event() {
        let bus = EventBus::new();
        let mut rx = bus.subscribe();
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
        let mut rx = bus.subscribe();
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
}
