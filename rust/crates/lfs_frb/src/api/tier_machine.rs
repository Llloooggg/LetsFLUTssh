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
/// + drops). The tagged enum eliminates the previous
/// "unknown discriminant" failure mode — every variant maps to a
/// concrete `TierEvent` at the FRB type-system level.
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
