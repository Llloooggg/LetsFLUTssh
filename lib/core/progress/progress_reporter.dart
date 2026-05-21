import 'dart:async';

import 'package:meta/meta.dart' show immutable;

/// Snapshot of work-in-progress state — consumed by
/// [AppProgressBarDialog] via [ProgressReporter.stream].
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

/// Mutable progress handle. Long-running operations own a reporter and
/// push phase/step updates; the UI subscribes to [stream] (seeded with
/// [current]) to render. Backed by a plain `dart:async` broadcast
/// stream so this stays free of any Flutter dependency in `core/`.
///
/// Must be disposed with [dispose] when the operation finishes.
class ProgressReporter {
  final StreamController<ProgressState> _controller =
      StreamController<ProgressState>.broadcast();
  ProgressState _current;

  ProgressReporter(String initialLabel)
    : _current = ProgressState.indeterminate(initialLabel);

  /// Latest state — seed for a late subscriber's first frame.
  ProgressState get current => _current;

  /// Broadcast updates. The dialog renders with `initialData: current`
  /// so a subscription that attaches after the first phase still shows
  /// the right label immediately.
  Stream<ProgressState> get stream => _controller.stream;

  /// Switch to an indeterminate phase — the bar animates without a value.
  void phase(String label) {
    _emit(ProgressState.indeterminate(label));
  }

  /// Report progress inside a step-based phase.
  ///
  /// `total <= 0` produces 0 %, treated as indeterminate numerator.
  void step(String label, int current, int total) {
    final pct = total <= 0 ? 0.0 : (current / total).clamp(0.0, 1.0);
    _emit(
      ProgressState(label: label, percent: pct, current: current, total: total),
    );
  }

  void _emit(ProgressState next) {
    _current = next;
    if (!_controller.isClosed) _controller.add(next);
  }

  void dispose() => _controller.close();
}
