//! FRB adapter for `lfs_core::security::tier_machine`.
//!
//! Sync — every call is a small mutex acquire + transition table
//! lookup, sub-microsecond. Exposes the typed scaffold so Dart
//! can read state + drive transitions for diagnostics. Per-tier
//! handlers wire production unlock cascades on top of these
//! primitives.
//!
//! **Currently not wired into the Dart unlock flow.** The Dart
//! `SecurityInitController` (1167 LOC) still owns the production
//! unlock cascade. Each per-tier handler migrates one tier at a
//! time under a feature gate; this scaffold lets the per-tier
//! wiring commits target a stable FRB API.

use std::sync::Mutex;

use lfs_core::security::tier_machine::{
    instance, Machine, TierEvent, TierState, UnlockFailureReason,
};
use lfs_core::security::SecurityTier;

/// Process-singleton tier machine instance — alias for the
/// `lfs_core::security::tier_machine::instance()` so the per-tier
/// unlock orchestrators share the same handle as the FRB shims.
fn machine_lock() -> &'static Mutex<Machine> {
    instance()
}

/// FRB mirror of `lfs_core::security::tier_machine::TierState`.
#[derive(Debug, Clone, Copy)]
pub enum DbTierState {
    Locked,
    Unlocking,
    Unlocked,
    Wiping,
}

impl From<TierState> for DbTierState {
    fn from(s: TierState) -> Self {
        match s {
            TierState::Locked => DbTierState::Locked,
            TierState::Unlocking => DbTierState::Unlocking,
            TierState::Unlocked => DbTierState::Unlocked,
            TierState::Wiping => DbTierState::Wiping,
        }
    }
}

/// FRB mirror of `lfs_core::security::tier_machine::UnlockFailureReason`.
/// FRB codegen emits a sealed Dart class with one subclass per
/// variant; replaces the earlier `discriminant: String` +
/// untyped `code` / `detail` shape that the same file's
/// `DbTierState` always avoided.
#[derive(Debug, Clone)]
pub enum DbUnlockFailureReason {
    WrongSecret,
    PluginUnavailable { code: String },
    UserCancelled,
    Corruption { detail: String },
}

impl DbUnlockFailureReason {
    fn into_core(self) -> UnlockFailureReason {
        match self {
            DbUnlockFailureReason::WrongSecret => UnlockFailureReason::WrongSecret,
            DbUnlockFailureReason::PluginUnavailable { code } => {
                UnlockFailureReason::PluginUnavailable { code }
            }
            DbUnlockFailureReason::UserCancelled => UnlockFailureReason::UserCancelled,
            DbUnlockFailureReason::Corruption { detail } => {
                UnlockFailureReason::Corruption { detail }
            }
        }
    }
}

/// FRB mirror of `lfs_core::security::tier_machine::TierEvent`.
/// Tagged enum — Dart pattern-matches on the FRB-generated
/// sealed class instead of branching on a string discriminant.
#[derive(Debug, Clone)]
pub enum DbTierEvent {
    UnlockRequested,
    UnlockSucceeded,
    UnlockFailed { reason: DbUnlockFailureReason },
    LockRequested,
    Wiped,
}

impl DbTierEvent {
    fn into_core(self) -> TierEvent {
        match self {
            DbTierEvent::UnlockRequested => TierEvent::UnlockRequested,
            DbTierEvent::UnlockSucceeded => TierEvent::UnlockSucceeded,
            DbTierEvent::UnlockFailed { reason } => TierEvent::UnlockFailed {
                reason: reason.into_core(),
            },
            DbTierEvent::LockRequested => TierEvent::LockRequested,
            DbTierEvent::Wiped => TierEvent::Wiped,
        }
    }
}

/// Snapshot the current state. Returns `Locked` before any
/// dispatch lands (cold-boot default).
#[flutter_rust_bridge::frb(sync)]
pub fn tier_machine_state() -> DbTierState {
    machine_lock()
        .lock()
        .unwrap_or_else(|p| p.into_inner())
        .state()
        .into()
}

/// Snapshot the active tier wire-name (`plaintext` /
/// `keychain` / `keychain_with_password` / `hardware` /
/// `paranoid`). Mirrors `SecurityTier::wire_name`.
#[flutter_rust_bridge::frb(sync)]
pub fn tier_machine_active_tier_wire_name() -> String {
    machine_lock()
        .lock()
        .unwrap_or_else(|p| p.into_inner())
        .tier()
        .wire_name()
        .to_string()
}

/// Replace the active tier. Caller (wizard / settings) pushes
/// the new tier in before kicking off `UnlockRequested`. Returns
/// the new tier's wire name; `Err` for an unknown wire name.
#[flutter_rust_bridge::frb(sync)]
pub fn tier_machine_set_tier(tier_wire_name: String) -> Result<String, String> {
    let tier = SecurityTier::from_wire_name(&tier_wire_name)
        .ok_or_else(|| format!("unknown tier wire name: {tier_wire_name}"))?;
    let mut g = machine_lock().lock().unwrap_or_else(|p| p.into_inner());
    g.set_tier(tier);
    Ok(tier.wire_name().to_string())
}

/// Apply a transition. Returns the new state on success, `None`
/// when the event is invalid for the current state (caller logs
/// + drops). Tagged-enum shape — every variant maps to a concrete
/// `TierEvent` at the FRB type-system level, so an unknown
/// discriminant is a compile-time error, not a runtime drop.
#[flutter_rust_bridge::frb(sync)]
pub fn tier_machine_dispatch(event: DbTierEvent) -> Option<DbTierState> {
    let core = event.into_core();
    let mut g = machine_lock().lock().unwrap_or_else(|p| p.into_inner());
    g.dispatch(&core).map(DbTierState::from)
}

/// Per-tier handler hook — checks the current state + active
/// tier and self-advances if the tier needs no external input.
/// Returns the new state when an advance fired, `None`
/// otherwise.
///
/// Plaintext is the only tier that self-advances today; Dart
/// calls this immediately after dispatching `unlock_requested`
/// so the synchronous unlock path lands without waiting on a
/// no-op prompt round-trip. Keychain / Hardware / Paranoid
/// keep returning `None` until their per-tier handlers wire
/// in.
#[flutter_rust_bridge::frb(sync)]
pub fn tier_machine_try_advance() -> Option<DbTierState> {
    machine_lock()
        .lock()
        .unwrap_or_else(|p| p.into_inner())
        .try_advance()
        .map(DbTierState::from)
}

#[cfg(test)]
mod tests {
    use super::*;

    // The tier-machine singleton is process-static + tests share it.
    // Acquire `TIER_TEST_LOCK` at the top of every test that mutates
    // the singleton's tier slot or dispatches a state transition;
    // without serialization one test's `LockRequested` can land
    // mid-way through another's `UnlockSucceeded` and flip the
    // observed state under the second test's assert. `dispatch`
    // publishes a bus event through `app::instance()` so tests that
    // exercise it bootstrap the singleton via `lfs_core::app::init()`
    // (idempotent).
    static TIER_TEST_LOCK: std::sync::Mutex<()> = std::sync::Mutex::new(());

    #[test]
    fn set_tier_then_read_active_returns_the_pinned_wire_name() {
        let _guard = TIER_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
        // Pin the tier round-trip — the Dart wizard pins the tier
        // before kicking off the unlock dispatch and reads it back
        // immediately.
        for wire in ["plaintext", "keychain", "hardware", "paranoid"] {
            let echoed = tier_machine_set_tier(wire.into()).expect("set");
            assert_eq!(echoed, wire);
            assert_eq!(tier_machine_active_tier_wire_name(), wire);
        }
    }

    #[test]
    fn set_tier_with_unknown_wire_name_surfaces_err() {
        let _guard = TIER_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
        let res = tier_machine_set_tier("not-a-tier".into());
        assert!(res.is_err());
    }

    #[test]
    fn dispatch_unlock_succeeded_advances_to_unlocked() {
        let _guard = TIER_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
        // Bootstrap the app singleton — `dispatch` publishes through
        // `app::instance().bus`; without init the publish would
        // panic.
        let _ = lfs_core::app::init();
        let _ = tier_machine_set_tier("plaintext".into()).expect("set");
        // Drive the documented Locked → Unlocking → Unlocked path.
        let _ = tier_machine_dispatch(DbTierEvent::UnlockRequested);
        let next = tier_machine_dispatch(DbTierEvent::UnlockSucceeded);
        assert!(matches!(next, Some(DbTierState::Unlocked)));
        // Reset for sibling tests by dispatching LockRequested.
        let _ = tier_machine_dispatch(DbTierEvent::LockRequested);
    }

    #[test]
    fn dispatch_invalid_event_for_state_returns_none() {
        let _guard = TIER_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
        let _ = lfs_core::app::init();
        let _ = tier_machine_set_tier("plaintext".into());
        // Drive to Unlocked then dispatch UnlockSucceeded again —
        // the documented transition table rejects it (nothing to
        // succeed; already unlocked).
        let _ = tier_machine_dispatch(DbTierEvent::UnlockRequested);
        let _ = tier_machine_dispatch(DbTierEvent::UnlockSucceeded);
        let invalid = tier_machine_dispatch(DbTierEvent::UnlockSucceeded);
        assert!(invalid.is_none());
        // Reset.
        let _ = tier_machine_dispatch(DbTierEvent::LockRequested);
    }
}
