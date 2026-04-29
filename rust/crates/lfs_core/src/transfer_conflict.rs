//! Transfer-conflict resolution types + the batch-state machine
//! the Dart `BatchConflictResolver` wraps.
//!
//! The Dart `ConflictPrompt` callback (driving the modal dialog)
//! stays Dart-side because of UI ownership; this module covers
//! the pure pieces:
//!
//!   - `ConflictAction` enum — skip / keep_both / replace / cancel.
//!   - `ConflictDecision` struct — `(action, apply_to_all)`.
//!   - `BatchState::record_decision` — the cache-action +
//!     cancellation grammar `BatchConflictResolver.resolve` runs
//!     on every prompt result.
//!
//! Once the bus prompt-protocol arc lands the resolver itself can
//! move Rust-side; for now the Dart wrapper holds a `BatchState`
//! and folds prompt outcomes through `record_decision` so the
//! grammar lives one place.

/// What the user picked for a single conflicting destination.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ConflictAction {
    /// Skip this file — do not transfer.
    Skip,
    /// Transfer with a new name (e.g. `"file (1).txt"`).
    KeepBoth,
    /// Overwrite the existing destination.
    Replace,
    /// Cancel the entire batch — no further files in this batch
    /// should be processed.
    Cancel,
}

/// Decision returned by the prompt UI — pairs an [`action`] with
/// a flag indicating whether to reuse it for the rest of the
/// batch.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ConflictDecision {
    pub action: ConflictAction,
    pub apply_to_all: bool,
}

/// Per-batch state the resolver carries between prompts.
///
/// `cached` short-circuits future prompts when the user checked
/// "apply to all"; `cancelled` short-circuits everything once the
/// user cancelled. The Dart caller owns instances; folds prompt
/// outcomes through [`record_decision`].
#[derive(Debug, Default, Clone, Copy)]
pub struct BatchState {
    cached: Option<ConflictAction>,
    cancelled: bool,
}

impl BatchState {
    /// Cached action when the user previously checked
    /// "apply to all", `None` otherwise.
    #[must_use]
    pub fn cached(&self) -> Option<ConflictAction> {
        self.cached
    }

    /// True after the user cancelled — every subsequent
    /// `resolve` should short-circuit to [`ConflictAction::Cancel`]
    /// without prompting.
    #[must_use]
    pub fn is_cancelled(&self) -> bool {
        self.cancelled
    }

    /// Reset the per-batch state. Used by callers that reuse a
    /// resolver across consecutive batches without rebuilding.
    pub fn reset(&mut self) {
        self.cached = None;
        self.cancelled = false;
    }

    /// Fold a fresh prompt result into the state. Returns the
    /// effective action (for the current call) — same as
    /// `decision.action` unless the state was already cancelled.
    ///
    /// `Cancel` flips `cancelled` so future calls short-circuit.
    /// `apply_to_all` (with a non-cancel action) caches the
    /// action for future calls.
    pub fn record_decision(&mut self, decision: ConflictDecision) -> ConflictAction {
        if self.cancelled {
            return ConflictAction::Cancel;
        }
        match decision.action {
            ConflictAction::Cancel => {
                self.cancelled = true;
            }
            other if decision.apply_to_all => {
                self.cached = Some(other);
            }
            _ => {}
        }
        decision.action
    }
}

/// Process-wide registry of `BatchState` instances keyed by an
/// opaque handle id (UUIDv4 from the Dart caller). Lives one
/// place so the Dart `BatchConflictResolver` can stay a thin
/// per-batch wrapper that just folds prompt outcomes through
/// `record_decision` via FRB.
///
/// The registry uses a per-process `Mutex` because conflict
/// prompts are user-driven (≪10 / s in any realistic batch); the
/// lock contention is irrelevant.
pub struct BatchStateRegistry {
    inner: std::sync::Mutex<std::collections::HashMap<String, BatchState>>,
}

impl Default for BatchStateRegistry {
    fn default() -> Self {
        Self::new()
    }
}

impl BatchStateRegistry {
    pub fn new() -> Self {
        Self {
            inner: std::sync::Mutex::new(std::collections::HashMap::new()),
        }
    }

    /// Register a fresh state for [`handle`]. Idempotent — a
    /// second `create` with the same handle resets the state to
    /// the default (no cache, not cancelled).
    pub fn create(&self, handle: &str) {
        self.inner
            .lock()
            .expect("conflict-resolver registry mutex poisoned")
            .insert(handle.to_string(), BatchState::default());
    }

    /// Drop the state for [`handle`]. No-op when the handle is
    /// already gone.
    pub fn drop(&self, handle: &str) {
        self.inner
            .lock()
            .expect("conflict-resolver registry mutex poisoned")
            .remove(handle);
    }

    /// Cached action for [`handle`], or `None` when the handle
    /// is unknown / the user hasn't checked "apply to all" yet.
    #[must_use]
    pub fn cached(&self, handle: &str) -> Option<ConflictAction> {
        self.inner
            .lock()
            .expect("conflict-resolver registry mutex poisoned")
            .get(handle)
            .and_then(|s| s.cached())
    }

    /// True after the user cancelled the batch behind [`handle`].
    /// Returns `false` for unknown handles so callers default to
    /// "not cancelled" instead of branching.
    #[must_use]
    pub fn is_cancelled(&self, handle: &str) -> bool {
        self.inner
            .lock()
            .expect("conflict-resolver registry mutex poisoned")
            .get(handle)
            .map(|s| s.is_cancelled())
            .unwrap_or(false)
    }

    /// Fold [`decision`] into the state behind [`handle`] and
    /// return the effective action. Auto-creates the state when
    /// the handle is unknown so callers don't have to call
    /// [`create`] explicitly first; the typical path threads
    /// `create → record_decision* → drop`.
    pub fn record_decision(&self, handle: &str, decision: ConflictDecision) -> ConflictAction {
        let mut g = self
            .inner
            .lock()
            .expect("conflict-resolver registry mutex poisoned");
        let state = g.entry(handle.to_string()).or_default();
        state.record_decision(decision)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn dec(action: ConflictAction, all: bool) -> ConflictDecision {
        ConflictDecision {
            action,
            apply_to_all: all,
        }
    }

    #[test]
    fn fresh_state_has_no_cache_and_is_not_cancelled() {
        let s = BatchState::default();
        assert!(s.cached().is_none());
        assert!(!s.is_cancelled());
    }

    #[test]
    fn record_decision_returns_the_action_when_apply_to_all_is_false() {
        let mut s = BatchState::default();
        let result = s.record_decision(dec(ConflictAction::Skip, false));
        assert_eq!(result, ConflictAction::Skip);
        // Not cached when apply_to_all is false.
        assert!(s.cached().is_none());
    }

    #[test]
    fn record_decision_caches_action_when_apply_to_all_is_true() {
        let mut s = BatchState::default();
        s.record_decision(dec(ConflictAction::Replace, true));
        assert_eq!(s.cached(), Some(ConflictAction::Replace));
    }

    #[test]
    fn record_decision_cancel_sets_cancelled_flag_and_skips_caching() {
        let mut s = BatchState::default();
        // `apply_to_all=true` on a cancel must NOT cache `Cancel`
        // as the per-row action — cancellation already short-
        // circuits future calls.
        s.record_decision(dec(ConflictAction::Cancel, true));
        assert!(s.is_cancelled());
        assert!(s.cached().is_none());
    }

    #[test]
    fn record_decision_short_circuits_after_cancel() {
        let mut s = BatchState::default();
        s.record_decision(dec(ConflictAction::Cancel, false));
        // Subsequent prompts return Cancel without consulting
        // the new decision.
        let result = s.record_decision(dec(ConflictAction::Replace, true));
        assert_eq!(result, ConflictAction::Cancel);
        // And the cache stays empty.
        assert!(s.cached().is_none());
    }

    #[test]
    fn reset_clears_cache_and_cancellation() {
        let mut s = BatchState::default();
        s.record_decision(dec(ConflictAction::Replace, true));
        s.record_decision(dec(ConflictAction::Cancel, false));
        assert!(s.is_cancelled());
        s.reset();
        assert!(!s.is_cancelled());
        assert!(s.cached().is_none());
    }

    #[test]
    fn registry_create_drop_round_trip() {
        let r = BatchStateRegistry::new();
        r.create("h1");
        assert!(r.cached("h1").is_none());
        assert!(!r.is_cancelled("h1"));
        r.drop("h1");
        // Unknown handle reads as default — no panic.
        assert!(r.cached("h1").is_none());
        assert!(!r.is_cancelled("h1"));
    }

    #[test]
    fn registry_record_decision_caches_per_handle() {
        let r = BatchStateRegistry::new();
        r.record_decision("h1", dec(ConflictAction::Replace, true));
        r.record_decision("h2", dec(ConflictAction::Skip, false));
        // h1 cached Replace; h2 didn't cache anything.
        assert_eq!(r.cached("h1"), Some(ConflictAction::Replace));
        assert!(r.cached("h2").is_none());
    }

    #[test]
    fn registry_short_circuits_after_cancel_per_handle() {
        let r = BatchStateRegistry::new();
        r.record_decision("h1", dec(ConflictAction::Cancel, false));
        // Subsequent record on h1 returns Cancel without
        // affecting h2.
        let result = r.record_decision("h1", dec(ConflictAction::Replace, true));
        assert_eq!(result, ConflictAction::Cancel);
        assert!(r.is_cancelled("h1"));
        assert!(!r.is_cancelled("h2"));
    }
}
