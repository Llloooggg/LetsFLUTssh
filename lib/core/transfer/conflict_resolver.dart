import 'package:uuid/uuid.dart';

import '../../src/rust/api/transfer_conflict.dart' as rust_conflict;

/// Result of a file-conflict resolution: how to proceed when the
/// destination of a transfer already exists.
enum ConflictAction {
  /// Skip this file — do not transfer.
  skip,

  /// Transfer with a new name (e.g. "file (1).txt").
  keepBoth,

  /// Overwrite the existing destination.
  replace,

  /// Cancel the entire batch — no further files in this batch
  /// should be processed.
  cancel,
}

ConflictAction _fromRust(rust_conflict.DbConflictAction a) => switch (a) {
  rust_conflict.DbConflictAction.skip => ConflictAction.skip,
  rust_conflict.DbConflictAction.keepBoth => ConflictAction.keepBoth,
  rust_conflict.DbConflictAction.replace => ConflictAction.replace,
  rust_conflict.DbConflictAction.cancel => ConflictAction.cancel,
};

rust_conflict.DbConflictAction _toRust(ConflictAction a) => switch (a) {
  ConflictAction.skip => rust_conflict.DbConflictAction.skip,
  ConflictAction.keepBoth => rust_conflict.DbConflictAction.keepBoth,
  ConflictAction.replace => rust_conflict.DbConflictAction.replace,
  ConflictAction.cancel => rust_conflict.DbConflictAction.cancel,
};

/// Decision returned by a conflict UI, pairing an [action] with a
/// flag indicating whether the same action should be reused for
/// the remaining files in the current batch.
class ConflictDecision {
  final ConflictAction action;
  final bool applyToAll;

  const ConflictDecision(this.action, {this.applyToAll = false});
}

/// Prompts the user for a conflict decision for a single destination
/// path. Implementations must be safe to call from an async transfer
/// pipeline — the returned Future completes once the user chooses.
typedef ConflictPrompt =
    Future<ConflictDecision> Function(String targetPath, {bool isRemote});

/// Shared conflict-resolution state for a batch of transfers.
///
/// Wraps a [ConflictPrompt] and caches the decision whenever the user
/// checks "apply to all remaining" — subsequent calls return the
/// cached action without showing the dialog again.
///
/// [cancel] short-circuits every further call to [resolve]: once the
/// user cancels, the resolver yields [ConflictAction.cancel] for the
/// rest of the batch.
///
/// State management routes through the Rust registry
/// (`lfs_core::transfer_conflict::BatchStateRegistry`) — the cache
/// + cancellation grammar lives one place. Tests bootstrap FRB via
/// `requireFrbLoaded()`.
class BatchConflictResolver {
  final ConflictPrompt _prompt;
  final String _handle = const Uuid().v4();

  BatchConflictResolver(this._prompt) {
    rust_conflict.transferConflictCreate(handle: _handle);
  }

  /// Ask for a decision on [targetPath].
  ///
  /// Returns the cached action if the user previously checked
  /// "apply to all" or cancelled the batch.
  Future<ConflictAction> resolve(
    String targetPath, {
    bool isRemote = false,
  }) async {
    if (rust_conflict.transferConflictIsCancelled(handle: _handle)) {
      return ConflictAction.cancel;
    }
    final cached = rust_conflict.transferConflictCached(handle: _handle);
    if (cached != null) return _fromRust(cached);
    final decision = await _prompt(targetPath, isRemote: isRemote);
    return _fromRust(
      rust_conflict.transferConflictRecordDecision(
        handle: _handle,
        action: _toRust(decision.action),
        applyToAll: decision.applyToAll,
      ),
    );
  }

  /// Whether the user has cancelled the batch.
  bool get isCancelled =>
      rust_conflict.transferConflictIsCancelled(handle: _handle);

  /// Drop the Rust-side state. Idempotent. Call from the
  /// surrounding `dispose` so the registry doesn't grow per-batch
  /// orphan entries.
  void dispose() {
    rust_conflict.transferConflictDrop(handle: _handle);
  }
}
