//! FRB adapter for `lfs_core::transfer_conflict::BatchStateRegistry`.
//!
//! Sync — every endpoint is one mutex acquire + a `HashMap`
//! lookup; the work runs sub-microsecond. Conflict prompts are
//! user-driven (≪10 / s), so async-jump overhead would buy
//! nothing.
//!
//! Wire shape: the Dart `BatchConflictResolver` allocates a
//! UUIDv4 handle on construction, folds prompt outcomes through
//! `transfer_conflict_record_decision`, and calls
//! `transfer_conflict_drop` on dispose. The cancellation +
//! cache grammar (`is_cancelled`, `cached`) reads via the
//! matching probes so the Dart wrapper stays a thin façade over
//! the canonical Rust state machine.

use lfs_core::transfer_conflict::{ConflictAction, ConflictDecision};

/// Mirror of `lfs_core::transfer_conflict::ConflictAction` that
/// crosses the FRB boundary.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DbConflictAction {
    Skip,
    KeepBoth,
    Replace,
    Cancel,
}

impl From<ConflictAction> for DbConflictAction {
    fn from(a: ConflictAction) -> Self {
        match a {
            ConflictAction::Skip => DbConflictAction::Skip,
            ConflictAction::KeepBoth => DbConflictAction::KeepBoth,
            ConflictAction::Replace => DbConflictAction::Replace,
            ConflictAction::Cancel => DbConflictAction::Cancel,
        }
    }
}

impl From<DbConflictAction> for ConflictAction {
    fn from(a: DbConflictAction) -> Self {
        match a {
            DbConflictAction::Skip => ConflictAction::Skip,
            DbConflictAction::KeepBoth => ConflictAction::KeepBoth,
            DbConflictAction::Replace => ConflictAction::Replace,
            DbConflictAction::Cancel => ConflictAction::Cancel,
        }
    }
}

/// Register a fresh state for [`handle`]. Idempotent — a second
/// `create` with the same handle resets the state to default.
#[flutter_rust_bridge::frb(sync)]
pub fn transfer_conflict_create(handle: String) {
    lfs_core::app::instance().conflict_resolvers.create(&handle);
}

/// Drop the state for [`handle`]. No-op when the handle is
/// already gone — Dart `dispose` runs unconditionally.
#[flutter_rust_bridge::frb(sync)]
pub fn transfer_conflict_drop(handle: String) {
    lfs_core::app::instance().conflict_resolvers.drop(&handle);
}

/// Cached action for [`handle`], or `None` when the user hasn't
/// checked "apply to all" yet (or the handle is unknown).
#[flutter_rust_bridge::frb(sync)]
pub fn transfer_conflict_cached(handle: String) -> Option<DbConflictAction> {
    lfs_core::app::instance()
        .conflict_resolvers
        .cached(&handle)
        .map(DbConflictAction::from)
}

/// True after the user cancelled the batch behind [`handle`].
#[flutter_rust_bridge::frb(sync)]
pub fn transfer_conflict_is_cancelled(handle: String) -> bool {
    lfs_core::app::instance()
        .conflict_resolvers
        .is_cancelled(&handle)
}

/// Fold a prompt result into the state behind [`handle`] and
/// return the effective action. `apply_to_all` (with a non-cancel
/// action) caches the action for future calls; `Cancel` flips
/// the cancellation flag so subsequent calls short-circuit.
#[flutter_rust_bridge::frb(sync)]
pub fn transfer_conflict_record_decision(
    handle: String,
    action: DbConflictAction,
    apply_to_all: bool,
) -> DbConflictAction {
    lfs_core::app::instance()
        .conflict_resolvers
        .record_decision(
            &handle,
            ConflictDecision {
                action: action.into(),
                apply_to_all,
            },
        )
        .into()
}

#[cfg(test)]
mod tests {
    use super::*;

    // The create / drop / cached / record / is_cancelled endpoints
    // route through `lfs_core::app::instance()` and need
    // `lfs_core::app::init()` (FRB worker bootstrap, not the
    // cargo-test harness). The Dart `transfer_conflict_test.dart`
    // covers those paths end-to-end. The standalone tests below pin
    // the `From` mapping that crosses the FRB boundary in either
    // direction.

    #[test]
    fn db_conflict_action_round_trips_through_core() {
        for db in [
            DbConflictAction::Skip,
            DbConflictAction::KeepBoth,
            DbConflictAction::Replace,
            DbConflictAction::Cancel,
        ] {
            let core: ConflictAction = db.into();
            let back: DbConflictAction = core.into();
            assert_eq!(db, back, "round-trip must be lossless for {db:?}");
        }
    }

    #[test]
    fn db_conflict_action_maps_each_variant_distinctly() {
        // Pin the variant→variant mapping so a future refactor that
        // accidentally collapses two arms (e.g. `Skip` → `KeepBoth`)
        // breaks loudly here, not in the wild as a Dart-side
        // cancel-instead-of-skip.
        assert_eq!(
            ConflictAction::from(DbConflictAction::Skip),
            ConflictAction::Skip
        );
        assert_eq!(
            ConflictAction::from(DbConflictAction::KeepBoth),
            ConflictAction::KeepBoth
        );
        assert_eq!(
            ConflictAction::from(DbConflictAction::Replace),
            ConflictAction::Replace
        );
        assert_eq!(
            ConflictAction::from(DbConflictAction::Cancel),
            ConflictAction::Cancel
        );
    }
}
