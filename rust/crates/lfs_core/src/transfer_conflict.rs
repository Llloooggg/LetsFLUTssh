//! Transfer-conflict resolution state machine.
//!
//! The Dart `BatchConflictResolver` is a thin façade: every call
//! routes through `BatchStateRegistry` here so the cache /
//! cancellation grammar lives one place. The Dart `ConflictPrompt`
//! callback (driving the modal dialog) stays Dart-side because UI
//! rendering is not portable; the resolver hands prompt outcomes
//! back through [`BatchState::record_decision`] and reads the
//! cached action via [`BatchState::cached_action`] before showing
//! the next dialog.
//!
//! Public surface:
//!
//!   - `ConflictAction` enum — skip / keep_both / replace / cancel.
//!   - `ConflictDecision` struct — `(action, apply_to_all)`.
//!   - `BatchState::record_decision` + `cached_action` —
//!     cache lifecycle.
//!   - `BatchStateRegistry` — process-singleton handle map keyed
//!     by the Dart-allocated UUID per resolver instance.

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
    /// Cached action when the user checked "apply to all" on an
    /// earlier prompt, `None` otherwise.
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
            .unwrap_or_else(|e| e.into_inner())
            .insert(handle.to_string(), BatchState::default());
    }

    /// Drop the state for [`handle`]. No-op when the handle is
    /// already gone.
    pub fn drop(&self, handle: &str) {
        self.inner
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .remove(handle);
    }

    /// Cached action for [`handle`], or `None` when the handle
    /// is unknown / the user hasn't checked "apply to all" yet.
    #[must_use]
    pub fn cached(&self, handle: &str) -> Option<ConflictAction> {
        self.inner
            .lock()
            .unwrap_or_else(|e| e.into_inner())
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
            .unwrap_or_else(|e| e.into_inner())
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
        let mut g = self.inner.lock().unwrap_or_else(|e| e.into_inner());
        let state = g.entry(handle.to_string()).or_default();
        state.record_decision(decision)
    }
}
#[cfg(test)]
#[path = "../tests/unit/transfer_conflict.rs"]
mod tests;
