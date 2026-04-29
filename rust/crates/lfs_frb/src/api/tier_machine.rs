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

use lfs_core::security::tier_machine::{Machine, TierEvent, TierState, UnlockFailureReason};
use lfs_core::security::SecurityTier;

/// Process-singleton tier machine instance. Held behind a Mutex
/// so dispatch is race-free; the underlying handle does not need
/// internal locking because every access goes through this
/// guard.
fn machine_lock() -> &'static Mutex<Machine> {
    static GLOBAL: std::sync::OnceLock<Mutex<Machine>> = std::sync::OnceLock::new();
    GLOBAL.get_or_init(|| Mutex::new(Machine::new(SecurityTier::Plaintext)))
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

/// FRB mirror of `UnlockFailureReason`. The `code` /
/// `detail` / `discriminant` strings carry the per-variant
/// payload; the discriminant is the variant tag the Dart caller
/// branches on.
#[derive(Debug, Clone)]
pub struct DbUnlockFailureReason {
    /// One of `wrong_secret` / `plugin_unavailable` /
    /// `user_cancelled` / `corruption`.
    pub discriminant: String,
    /// Plugin-classifier code (only populated when
    /// discriminant == "plugin_unavailable").
    pub code: String,
    /// Free-form detail (only populated when
    /// discriminant == "corruption").
    pub detail: String,
}

impl DbUnlockFailureReason {
    fn into_core(self) -> UnlockFailureReason {
        match self.discriminant.as_str() {
            "plugin_unavailable" => UnlockFailureReason::PluginUnavailable { code: self.code },
            "user_cancelled" => UnlockFailureReason::UserCancelled,
            "corruption" => UnlockFailureReason::Corruption {
                detail: self.detail,
            },
            _ => UnlockFailureReason::WrongSecret,
        }
    }
}

/// FRB-side variant tag for `TierEvent`. Each event variant
/// crosses with the discriminant + the per-variant payload. The
/// Dart caller constructs one of these and dispatches via
/// [`tier_machine_dispatch`].
#[derive(Debug, Clone)]
pub struct DbTierEvent {
    /// One of `unlock_requested` / `unlock_succeeded` /
    /// `unlock_failed` / `lock_requested` / `wiped`.
    pub discriminant: String,
    /// Populated only when discriminant == "unlock_failed".
    pub fail_reason: Option<DbUnlockFailureReason>,
}

impl DbTierEvent {
    fn into_core(self) -> Option<TierEvent> {
        Some(match self.discriminant.as_str() {
            "unlock_requested" => TierEvent::UnlockRequested,
            "unlock_succeeded" => TierEvent::UnlockSucceeded,
            "unlock_failed" => TierEvent::UnlockFailed {
                reason: self.fail_reason?.into_core(),
            },
            "lock_requested" => TierEvent::LockRequested,
            "wiped" => TierEvent::Wiped,
            _ => return None,
        })
    }
}

/// Snapshot the current state. Returns `Locked` before any
/// dispatch lands (cold-boot default).
#[flutter_rust_bridge::frb(sync)]
pub fn tier_machine_state() -> DbTierState {
    machine_lock()
        .lock()
        .expect("tier machine poisoned")
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
        .expect("tier machine poisoned")
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
    let mut g = machine_lock().lock().expect("tier machine poisoned");
    g.set_tier(tier);
    Ok(tier.wire_name().to_string())
}

/// Apply a transition. Returns the new state on success, `None`
/// when the event is invalid for the current state (caller logs
/// + drops). `Err` for an unknown event discriminant.
#[flutter_rust_bridge::frb(sync)]
pub fn tier_machine_dispatch(event: DbTierEvent) -> Result<Option<DbTierState>, String> {
    let core = event
        .into_core()
        .ok_or_else(|| "unknown event discriminant".to_string())?;
    let mut g = machine_lock().lock().expect("tier machine poisoned");
    Ok(g.dispatch(&core).map(DbTierState::from))
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
        .expect("tier machine poisoned")
        .try_advance()
        .map(DbTierState::from)
}
