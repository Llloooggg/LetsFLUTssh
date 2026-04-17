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
class BatchConflictResolver {
  final ConflictPrompt _prompt;
  ConflictAction? _cached;
  bool _cancelled = false;

  BatchConflictResolver(this._prompt);

  /// Ask for a decision on [targetPath].
  ///
  /// Returns the cached action if the user previously checked
  /// "apply to all" or cancelled the batch.
  Future<ConflictAction> resolve(
    String targetPath, {
    bool isRemote = false,
  }) async {
    if (_cancelled) return ConflictAction.cancel;
    if (_cached != null) return _cached!;

    final decision = await _prompt(targetPath, isRemote: isRemote);
    if (decision.action == ConflictAction.cancel) {
      _cancelled = true;
    } else if (decision.applyToAll) {
      _cached = decision.action;
    }
    return decision.action;
  }

  /// Whether the user has cancelled the batch.
  bool get isCancelled => _cancelled;
}
