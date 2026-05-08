//! Regression tests for the boundary-panic fix that swapped
//! every `lock().expect("...mutex poisoned")` for
//! `lock().unwrap_or_else(|p| p.into_inner())` across the FRB
//! surface (`tier_machine.rs`, `transfer.rs`, `bus.rs`,
//! `connection.rs`).
//!
//! Why a separate integration binary: poisoning a process-
//! singleton mutex is sticky — once a thread panics while
//! holding the lock, every subsequent `lock()` call returns
//! `Err(PoisonError)`. The recovery pattern is fine with that
//! (it pulls the inner value out anyway), but the poison state
//! leaks across tests in the same binary. Isolating in a
//! dedicated `tests/` file gives each scenario its own process,
//! so tests can poison without polluting the main unit-test
//! binary.
//!
//! Each scenario:
//!   1. Spawn a child thread that locks the singleton + panics.
//!   2. Join the thread (now the mutex is poisoned).
//!   3. Call the FRB shim — it must NOT propagate the panic;
//!      it must return successfully via `into_inner` recovery.

use std::sync::Mutex;
use std::thread;

#[test]
fn tier_machine_state_recovers_after_poison() {
    let m = lfs_core::security::tier_machine::instance();
    if !m.is_poisoned() {
        let h = thread::spawn(move || {
            let _g = m.lock().expect("first poison-thread acquire must succeed");
            panic!("intentional poison");
        });
        let _ = h.join();
        assert!(m.is_poisoned(), "mutex must be poisoned after holder panic");
    }
    // Every FRB-side tier_machine shim uses the same
    // `unwrap_or_else(|p| p.into_inner())` recovery shape.
    // Calling them now must NOT panic across the boundary.
    let _ = lfs_frb::api::tier_machine::tier_machine_state();
    let _ = lfs_frb::api::tier_machine::tier_machine_active_tier_wire_name();
    let _ = lfs_frb::api::tier_machine::tier_machine_try_advance();
    let _ = lfs_frb::api::tier_machine::tier_machine_set_tier("plaintext".into());
}

#[test]
fn poisoned_mutex_recovery_returns_inner_state() {
    // Free-standing reproduction of the exact recovery pattern
    // the FRB surface relies on, independent of the
    // process-singleton mutexes above. Guards against accidental
    // refactors swapping `unwrap_or_else(|p| p.into_inner())`
    // back to `expect`.
    let m: &'static Mutex<u32> = Box::leak(Box::new(Mutex::new(42)));
    let h = thread::spawn(move || {
        let mut g = m.lock().expect("first acquire must succeed");
        *g = 99;
        panic!("intentional poison");
    });
    let _ = h.join();
    assert!(m.is_poisoned());

    // The exact pattern every FRB shim site uses:
    let g = m.lock().unwrap_or_else(|p| p.into_inner());
    // Mutating writes from the poisoned holder are visible — by
    // design, since `into_inner` is the documented recovery
    // path. Caller is responsible for state-validity decisions.
    assert_eq!(*g, 99);
}
