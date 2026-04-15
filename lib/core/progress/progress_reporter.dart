import 'package:flutter/foundation.dart';

/// Snapshot of work-in-progress state — consumed by
/// [AppProgressBarDialog] via a [ValueListenable].
///
/// [percent] = `null` means the current phase is indeterminate
/// (no measurable progress — e.g. a single atomic call to PBKDF2 inside
/// an isolate). A non-null value is in the closed range `[0.0, 1.0]`.
/// [current]/[total] are optional and only populated for step-based
/// phases (e.g. "importing session 3 of 12").
@immutable
class ProgressState {
  final String label;
  final double? percent;
  final int? current;
  final int? total;

  const ProgressState({
    required this.label,
    this.percent,
    this.current,
    this.total,
  });

  const ProgressState.indeterminate(this.label)
    : percent = null,
      current = null,
      total = null;
}

/// Mutable progress handle.  Long-running operations own a reporter and
/// push phase/step updates; the UI subscribes to [state] to render.
///
/// Must be disposed with [dispose] when the operation finishes.
class ProgressReporter {
  final ValueNotifier<ProgressState> state;

  ProgressReporter(String initialLabel)
    : state = ValueNotifier<ProgressState>(
        ProgressState.indeterminate(initialLabel),
      );

  /// Switch to an indeterminate phase — the bar animates without a value.
  void phase(String label) {
    state.value = ProgressState.indeterminate(label);
  }

  /// Report progress inside a step-based phase.
  ///
  /// `total <= 0` produces 0 %, treated as indeterminate numerator.
  void step(String label, int current, int total) {
    final pct = total <= 0 ? 0.0 : (current / total).clamp(0.0, 1.0);
    state.value = ProgressState(
      label: label,
      percent: pct,
      current: current,
      total: total,
    );
  }

  void dispose() => state.dispose();
}
