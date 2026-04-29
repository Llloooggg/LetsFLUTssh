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
#[derive(Debug, Default)]
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
}
