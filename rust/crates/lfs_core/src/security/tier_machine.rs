//! Typed scaffold for the L0-L3 + Paranoid tier state machine.
//!
//! Owns the state + event + transition table only. Per-tier
//! orchestration (Plaintext / Keychain / KeychainWithPassword /
//! Hardware / Paranoid) lands incrementally behind feature
//! gates so each per-tier handler ships as a retain-rollback-able
//! commit.
//!
//! This file is **purely additive** and does not yet touch the
//! Dart `SecurityInitController` (1167 LOC) which still owns the
//! production unlock flow. That orchestrator retires once every
//! per-tier feature gate is on by default.
//!
//! **Why land the scaffold ahead of the wiring.** The transition
//! table is the contract every per-tier sub-machine implements.
//! Putting it down now (with property tests) lets the per-tier
//! work compose against a fixed shape instead of redesigning the
//! state machine each time.
//!
//! **Why no `dispatch` impl yet.** A dispatch with no per-tier
//! handlers wired would either return `Pending` for every event
//! (dead code) or fake side-effects with `todo!` (worse than no
//! impl). The transition table itself is enough scaffold —
//! per-tier handlers wire up the real transitions later.

use crate::security::SecurityTier;

/// User-facing lock state of the active tier. Mirrors the lock
/// model the Dart `SecurityInitController` exposes today: the app
/// either has a usable DB key (`Unlocked`), is mid-unlock with
/// the user staring at a prompt (`Unlocking`), or is at rest with
/// the DB closed (`Locked`). Wipe is its own terminal state because
/// rollback is impossible.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum TierState {
    /// No active session — the encrypted DB is closed and there is
    /// no in-memory key. Initial state on cold boot until the
    /// security bootstrap resolves the persisted tier.
    Locked,
    /// User has dismissed an unlock prompt or the bootstrap has
    /// requested unlock; we're waiting for the secret to land
    /// (passing through the typed prompt registry for L2 / L3 /
    /// Paranoid). For L0 / L1 this state is transient — the
    /// transition fires immediately on `UnlockRequested`.
    Unlocking,
    /// DB is open under the active tier's key; the rest of the app
    /// is live. The tier's modifier bag (biometric, password) is
    /// implicit in the active `SecurityTier` carried by
    /// `Machine.tier`.
    Unlocked,
    /// Catastrophic-reset path — `WipeAllService` is running. No
    /// further events are accepted; the next state is reached only
    /// by a process restart that re-enters `Locked` against the
    /// freshly-empty support dir.
    Wiping,
}

impl TierState {
    /// Stable wire name for the bus boundary. Each variant maps
    /// to a string so Dart subscribers branch without parsing
    /// the enum across FRB.
    pub fn wire_name(self) -> &'static str {
        match self {
            TierState::Locked => "locked",
            TierState::Unlocking => "unlocking",
            TierState::Unlocked => "unlocked",
            TierState::Wiping => "wiping",
        }
    }
}

/// Reason an unlock attempt failed. Surfaces to the bus so the UI
/// can pick the right copy / dialog variant.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub enum UnlockFailureReason {
    /// User-supplied secret rejected by the verifier (master
    /// password mismatch / L2 password mismatch / TPM auth value
    /// mismatch / wrong biometric enrolment).
    WrongSecret,
    /// Verifier fired but the platform plugin (keychain read,
    /// hardware-vault unwrap, biometric prompt) returned an
    /// error — distinct from `WrongSecret` because the user-typed
    /// value never reached the verifier.
    PluginUnavailable {
        /// Stable code mirroring the per-platform plugin
        /// classifier. The Dart UI already knows how to render
        /// these — passing through verbatim avoids a translation
        /// table.
        code: String,
    },
    /// User cancelled the unlock dialog / biometric prompt. Not
    /// strictly a failure but the actor needs an event to drop
    /// out of `Unlocking` back to `Locked`.
    UserCancelled,
    /// Persisted on-disk artefact (KDF record, sealed blob, HMAC
    /// envelope) is corrupt or signed under a stale key. The
    /// caller routes the user to the corruption-retry / reset
    /// dialog.
    Corruption {
        /// Free-form detail for the support trace; the UI shows a
        /// generic line.
        detail: String,
    },
}

/// Events the tier machine accepts. Dispatched by the per-tier
/// sub-machine in response to bus subscriptions, FRB commands,
/// or internal timers.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum TierEvent {
    /// Bootstrap requested unlock under the persisted tier. The
    /// per-tier handler resolves the secret via the typed prompt
    /// registry where needed and emits `UnlockSucceeded` /
    /// `UnlockFailed` when the verifier returns.
    UnlockRequested,
    /// Verifier accepted the secret; the DB key is staged in the
    /// `SecretStore` under the canonical id. The actor flips to
    /// `Unlocked` and publishes the corresponding bus event.
    UnlockSucceeded,
    /// Verifier rejected the secret or the unlock cascade tripped
    /// before the verifier — see [`UnlockFailureReason`].
    UnlockFailed { reason: UnlockFailureReason },
    /// Auto-lock timer fired or user requested manual lock. The
    /// `SecretStore` evict + db close happen synchronously; the
    /// actor flips to `Locked`.
    LockRequested,
    /// `WipeAllService.wipeAll()` completed — the actor moves to
    /// `Wiping` (terminal). Process restart re-enters `Locked`
    /// against the empty support dir.
    Wiped,
}

/// Result of dispatching an event against the current state.
/// `Some(TierState)` = the transition fired and the actor should
/// move to the new state; `None` = the event is invalid for the
/// current state (no-op, log-and-drop).
pub type TransitionResult = Option<TierState>;

/// Pure transition table. Mirrors the contract every per-tier
/// sub-machine implements: given `(current_state, event)`, return
/// the next state or `None` if the event is invalid for that
/// state. No side effects — handlers own the SecretStore
/// staging, plugin invocation, and bus event publication.
#[must_use]
pub fn next_state(current: TierState, event: &TierEvent) -> TransitionResult {
    match (current, event) {
        // Cold-start / re-lock paths.
        (TierState::Locked, TierEvent::UnlockRequested) => Some(TierState::Unlocking),
        (TierState::Locked, TierEvent::Wiped) => Some(TierState::Wiping),

        // Mid-unlock paths.
        (TierState::Unlocking, TierEvent::UnlockSucceeded) => Some(TierState::Unlocked),
        (TierState::Unlocking, TierEvent::UnlockFailed { .. }) => Some(TierState::Locked),
        // Mid-unlock cancel from the auto-lock subsystem (rare;
        // user dismissed the unlock dialog and the lock timer
        // happened to fire in the same window). Defensive: drop
        // back to locked rather than wedging in Unlocking.
        (TierState::Unlocking, TierEvent::LockRequested) => Some(TierState::Locked),

        // Live-session paths.
        (TierState::Unlocked, TierEvent::LockRequested) => Some(TierState::Locked),
        (TierState::Unlocked, TierEvent::Wiped) => Some(TierState::Wiping),

        // Wiping is terminal — the only legal post-state is
        // process restart, which reconstructs the actor in
        // Locked against an empty support dir.
        (TierState::Wiping, _) => None,

        // Every other (state, event) is invalid — the per-tier
        // handler logs and drops.
        _ => None,
    }
}

/// Process-singleton tier machine handle.
///
/// Owns the current state + the active tier under which the
/// unlock cascade was last requested (the wizard / settings
/// change pushes a new tier in before kicking off
/// `UnlockRequested`).
///
/// **Not yet wired to anything.** Future commits attach
/// per-tier sub-machine handlers + bus event publication. For
/// now the type exists so the per-tier handler signatures are
/// fixed and the FRB shim layer can target a stable API.
#[derive(Debug)]
pub struct Machine {
    state: TierState,
    tier: SecurityTier,
}

impl Machine {
    /// Fresh machine in the cold-boot state. Caller seeds the
    /// active tier from the persisted `AppConfig.security` (or
    /// `Plaintext` when the wizard has not yet run).
    #[must_use]
    pub fn new(initial_tier: SecurityTier) -> Self {
        Self {
            state: TierState::Locked,
            tier: initial_tier,
        }
    }

    pub fn state(&self) -> TierState {
        self.state
    }

    pub fn tier(&self) -> SecurityTier {
        self.tier
    }

    /// Apply a transition. Returns the new state on success,
    /// `None` when the event is invalid for the current state
    /// (caller logs + drops). On a successful transition, also
    /// publishes [`crate::bus::Event::TierStateChanged`] through
    /// the AppState bus so subscribers can refresh without
    /// polling.
    pub fn dispatch(&mut self, event: &TierEvent) -> TransitionResult {
        let next = next_state(self.state, event)?;
        self.state = next;
        // Publish through the AppState singleton so subscribers
        // refresh without polling. The `wire_name` carries the
        // new state across FRB without a typed enum surface.
        // Test-only constructions of `Machine` trigger this too;
        // the bus' `broadcast` channel returns Ok(0) when there
        // are no subscribers (test isolation), so the publish is
        // a harmless no-op there.
        crate::app::instance()
            .bus
            .publish(crate::bus::Event::TierStateChanged {
                state_wire_name: next.wire_name().to_string(),
            });
        Some(next)
    }

    /// Replace the active tier. Called by the wizard / settings
    /// change before kicking off a fresh `UnlockRequested`.
    pub fn set_tier(&mut self, tier: SecurityTier) {
        self.tier = tier;
    }

    /// Per-tier handler — checks if the current state has a tier
    /// that can self-advance without external input. Returns the
    /// new state if a self-advance fired.
    ///
    /// **Plaintext.** Plaintext tier has no secret, no plugin
    /// call, no user prompt. From `Unlocking` it fires
    /// `UnlockSucceeded` immediately — same shape the Dart
    /// `_unlockByTier` switch used (`case SecurityTier.plaintext:
    /// await _injectDatabase()`).
    ///
    /// **Other tiers.** Keychain / Hardware / Paranoid stay stuck
    /// in `Unlocking` until their per-tier handler (typed prompt
    /// registry + Dart plugin callback) resolves. This function
    /// is a no-op for those tiers — the actor waits on an
    /// explicit `UnlockSucceeded` / `UnlockFailed` dispatch from
    /// the handler.
    pub fn try_advance(&mut self) -> TransitionResult {
        if self.state != TierState::Unlocking {
            return None;
        }
        match self.tier {
            SecurityTier::Plaintext => self.dispatch(&TierEvent::UnlockSucceeded),
            // Other tiers wait for the per-tier handler to dispatch
            // the resolution event.
            _ => None,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fail() -> TierEvent {
        TierEvent::UnlockFailed {
            reason: UnlockFailureReason::WrongSecret,
        }
    }

    // ── Transition table coverage ──────────────────────────────

    #[test]
    fn locked_unlock_requested_moves_to_unlocking() {
        assert_eq!(
            next_state(TierState::Locked, &TierEvent::UnlockRequested),
            Some(TierState::Unlocking),
        );
    }

    #[test]
    fn locked_wiped_moves_to_wiping() {
        assert_eq!(
            next_state(TierState::Locked, &TierEvent::Wiped),
            Some(TierState::Wiping),
        );
    }

    #[test]
    fn locked_drops_unlock_succeeded_unlock_failed_lock_requested() {
        // Defensive: the bootstrap path may legitimately fire
        // these spuriously after a tier-transition crash. The
        // table drops them rather than wedging the machine.
        assert_eq!(
            next_state(TierState::Locked, &TierEvent::UnlockSucceeded),
            None,
        );
        assert_eq!(next_state(TierState::Locked, &fail()), None);
        assert_eq!(
            next_state(TierState::Locked, &TierEvent::LockRequested),
            None,
        );
    }

    #[test]
    fn unlocking_succeeded_moves_to_unlocked() {
        assert_eq!(
            next_state(TierState::Unlocking, &TierEvent::UnlockSucceeded),
            Some(TierState::Unlocked),
        );
    }

    #[test]
    fn unlocking_failed_falls_back_to_locked() {
        assert_eq!(
            next_state(TierState::Unlocking, &fail()),
            Some(TierState::Locked),
        );
    }

    #[test]
    fn unlocking_lock_requested_falls_back_to_locked() {
        // Race: user dismissed unlock dialog while auto-lock
        // timer fired. Defensive — drop to locked rather than
        // wedging in Unlocking.
        assert_eq!(
            next_state(TierState::Unlocking, &TierEvent::LockRequested),
            Some(TierState::Locked),
        );
    }

    #[test]
    fn unlocking_drops_unlock_requested_repeat() {
        // User double-tapped the unlock button — the second
        // request is a no-op, the in-flight prompt resolves.
        assert_eq!(
            next_state(TierState::Unlocking, &TierEvent::UnlockRequested),
            None,
        );
    }

    #[test]
    fn unlocked_lock_requested_moves_to_locked() {
        assert_eq!(
            next_state(TierState::Unlocked, &TierEvent::LockRequested),
            Some(TierState::Locked),
        );
    }

    #[test]
    fn unlocked_wiped_moves_to_wiping() {
        assert_eq!(
            next_state(TierState::Unlocked, &TierEvent::Wiped),
            Some(TierState::Wiping),
        );
    }

    #[test]
    fn unlocked_drops_unlock_events() {
        assert_eq!(
            next_state(TierState::Unlocked, &TierEvent::UnlockRequested),
            None,
        );
        assert_eq!(
            next_state(TierState::Unlocked, &TierEvent::UnlockSucceeded),
            None,
        );
        assert_eq!(next_state(TierState::Unlocked, &fail()), None);
    }

    #[test]
    fn wiping_is_terminal() {
        // Every event from Wiping returns None — the only legal
        // exit is process restart, which constructs a fresh
        // Machine in Locked against the post-wipe empty support
        // dir. Property test: no event escapes the terminal
        // state.
        for event in [
            TierEvent::UnlockRequested,
            TierEvent::UnlockSucceeded,
            fail(),
            TierEvent::LockRequested,
            TierEvent::Wiped,
        ] {
            assert_eq!(
                next_state(TierState::Wiping, &event),
                None,
                "wiping must drop {event:?}",
            );
        }
    }

    // ── Machine handle ────────────────────────────────────────

    #[test]
    fn machine_starts_locked_in_supplied_tier() {
        let m = Machine::new(SecurityTier::Hardware);
        assert_eq!(m.state(), TierState::Locked);
        assert_eq!(m.tier(), SecurityTier::Hardware);
    }

    #[test]
    fn machine_dispatch_advances_state_on_valid_event() {
        let mut m = Machine::new(SecurityTier::Plaintext);
        let next = m.dispatch(&TierEvent::UnlockRequested);
        assert_eq!(next, Some(TierState::Unlocking));
        assert_eq!(m.state(), TierState::Unlocking);
    }

    #[test]
    fn machine_dispatch_returns_none_on_invalid_event() {
        let mut m = Machine::new(SecurityTier::Plaintext);
        // Locked + UnlockSucceeded = invalid (defensive drop).
        let result = m.dispatch(&TierEvent::UnlockSucceeded);
        assert_eq!(result, None);
        // State unchanged.
        assert_eq!(m.state(), TierState::Locked);
    }

    #[test]
    fn machine_full_unlock_cycle() {
        let mut m = Machine::new(SecurityTier::KeychainWithPassword);
        m.dispatch(&TierEvent::UnlockRequested).unwrap();
        m.dispatch(&TierEvent::UnlockSucceeded).unwrap();
        assert_eq!(m.state(), TierState::Unlocked);
        m.dispatch(&TierEvent::LockRequested).unwrap();
        assert_eq!(m.state(), TierState::Locked);
    }

    #[test]
    fn machine_failed_unlock_falls_back_to_locked() {
        let mut m = Machine::new(SecurityTier::Paranoid);
        m.dispatch(&TierEvent::UnlockRequested).unwrap();
        m.dispatch(&fail()).unwrap();
        assert_eq!(m.state(), TierState::Locked);
    }

    #[test]
    fn try_advance_plaintext_self_advances_to_unlocked() {
        let mut m = Machine::new(SecurityTier::Plaintext);
        m.dispatch(&TierEvent::UnlockRequested).unwrap();
        assert_eq!(m.state(), TierState::Unlocking);
        let next = m.try_advance().unwrap();
        assert_eq!(next, TierState::Unlocked);
        assert_eq!(m.state(), TierState::Unlocked);
    }

    #[test]
    fn try_advance_other_tiers_waits_for_handler() {
        for tier in [
            SecurityTier::Keychain,
            SecurityTier::KeychainWithPassword,
            SecurityTier::Hardware,
            SecurityTier::Paranoid,
        ] {
            let mut m = Machine::new(tier);
            m.dispatch(&TierEvent::UnlockRequested).unwrap();
            assert_eq!(m.state(), TierState::Unlocking);
            // Non-plaintext tiers stay in Unlocking — the per-tier
            // handler resolves through the typed prompt registry
            // later.
            assert_eq!(m.try_advance(), None);
            assert_eq!(m.state(), TierState::Unlocking);
        }
    }

    #[test]
    fn try_advance_outside_unlocking_is_noop() {
        // From Locked / Unlocked / Wiping there's nothing to
        // advance from — the function returns None without
        // mutating state.
        let mut m = Machine::new(SecurityTier::Plaintext);
        assert_eq!(m.try_advance(), None);
        assert_eq!(m.state(), TierState::Locked);

        m.dispatch(&TierEvent::UnlockRequested).unwrap();
        m.dispatch(&TierEvent::UnlockSucceeded).unwrap();
        assert_eq!(m.state(), TierState::Unlocked);
        assert_eq!(m.try_advance(), None);
        assert_eq!(m.state(), TierState::Unlocked);
    }

    #[test]
    fn machine_set_tier_swaps_active_tier_without_state_change() {
        // Wizard / settings tier change does not move state on
        // its own — the caller fires `UnlockRequested` separately
        // when ready.
        let mut m = Machine::new(SecurityTier::Plaintext);
        m.set_tier(SecurityTier::Hardware);
        assert_eq!(m.tier(), SecurityTier::Hardware);
        assert_eq!(m.state(), TierState::Locked);
    }

    #[test]
    fn unlock_failure_reasons_carry_detail() {
        // Property: every UnlockFailed reason variant is
        // distinguishable so the UI can pick the right copy.
        let wrong = TierEvent::UnlockFailed {
            reason: UnlockFailureReason::WrongSecret,
        };
        let plugin = TierEvent::UnlockFailed {
            reason: UnlockFailureReason::PluginUnavailable {
                code: "linux_device_missing".into(),
            },
        };
        let cancelled = TierEvent::UnlockFailed {
            reason: UnlockFailureReason::UserCancelled,
        };
        let corrupt = TierEvent::UnlockFailed {
            reason: UnlockFailureReason::Corruption {
                detail: "kdf record HMAC mismatch".into(),
            },
        };
        // All four are distinct events for transition purposes
        // (table can later branch on reason without changing the
        // state graph).
        assert_ne!(wrong, plugin);
        assert_ne!(plugin, cancelled);
        assert_ne!(cancelled, corrupt);
        assert_ne!(corrupt, wrong);
    }
}
