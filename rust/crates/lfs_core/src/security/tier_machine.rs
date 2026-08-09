//! Typed T0-T2 + Paranoid tier state machine.
//!
//! Owns the state + event + transition table plus a `dispatch`
//! that publishes [`crate::bus::Event::TierStateChanged`] on every
//! committed transition. Per-tier orchestration (Plaintext /
//! Keychain / Keychain+password / Hardware / Paranoid) lives in
//! [`crate::security::tier_unlock_orchestrator`], which drives this
//! machine across the `Locked → Unlocking → Unlocked` cascade. The
//! Dart `SecurityInitController` delegates each tier's unlock to
//! that orchestrator over FRB and only feeds the resolved DB key to
//! drift — the DB-open step stays Dart because drift is a Dart ORM.
//! This machine is the source of truth for the lock state the Dart
//! `lockStateProvider` renders.
//!
//! **Why a single transition table.** The table is the contract
//! every per-tier sub-machine implements. Pinning it down with
//! property tests lets per-tier work compose against a fixed
//! shape rather than redesigning the state machine each time.

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
    /// (passing through the typed prompt registry for T1+pw / T2 /
    /// Paranoid). For T0 / T1 this state is transient — the
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
    /// password mismatch / T1+pw password mismatch / TPM auth value
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

/// Process-singleton tier machine instance. Held behind a Mutex
/// so dispatch is race-free; the underlying handle does not need
/// internal locking because every access goes through this
/// guard. Initialised lazily to `Plaintext` (cold-boot tier);
/// the wizard / persisted config seeds the real tier on first
/// use via [`Machine::set_tier`].
///
/// FRB shims and the per-tier unlock orchestrators share this
/// instance so the cascade visibility lives one place.
pub fn instance() -> &'static std::sync::Mutex<Machine> {
    static GLOBAL: std::sync::OnceLock<std::sync::Mutex<Machine>> = std::sync::OnceLock::new();
    GLOBAL.get_or_init(|| std::sync::Mutex::new(Machine::new(SecurityTier::Plaintext)))
}

/// Convenience: lock the singleton, set the tier, dispatch the
/// event. Used by orchestrators that need to atomically swap
/// the active tier and fire a cascade event in one critical
/// section.
pub fn instance_dispatch(tier: SecurityTier, event: &TierEvent) -> TransitionResult {
    let m = instance();
    let mut g = m.lock().unwrap_or_else(|e| e.into_inner());
    g.set_tier(tier);
    g.dispatch(event)
}

/// Process-singleton tier machine handle.
///
/// Owns the current state + the active tier under which the
/// unlock cascade was last requested (the wizard / settings
/// change pushes a new tier in before kicking off
/// `UnlockRequested`).
///
/// Driven by the per-tier handlers in
/// [`crate::security::tier_unlock_orchestrator`]: the wizard /
/// settings change pushes the new tier in, then the orchestrator
/// dispatches `UnlockRequested → … → UnlockSucceeded`, publishing
/// [`crate::bus::Event::TierStateChanged`] on every committed
/// transition (the Dart `lockStateProvider` subscribes).
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
#[path = "../../tests/unit/security_tier_machine.rs"]
mod tests;
