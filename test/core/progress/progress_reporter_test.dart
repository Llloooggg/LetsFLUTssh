import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/progress/progress_reporter.dart';

void main() {
  group('ProgressReporter', () {
    test('starts in indeterminate state with the initial label', () {
      final reporter = ProgressReporter('Loading');
      addTearDown(reporter.dispose);

      expect(reporter.current.label, 'Loading');
      expect(reporter.current.percent, isNull);
      expect(reporter.current.current, isNull);
      expect(reporter.current.total, isNull);
    });

    test('phase() switches to a new indeterminate label', () {
      final reporter = ProgressReporter('A');
      addTearDown(reporter.dispose);

      reporter.phase('B');
      expect(reporter.current.label, 'B');
      expect(reporter.current.percent, isNull);
    });

    test('step() computes percent from current/total', () {
      final reporter = ProgressReporter('work');
      addTearDown(reporter.dispose);

      reporter.step('Importing', 3, 10);
      expect(reporter.current.label, 'Importing');
      expect(reporter.current.current, 3);
      expect(reporter.current.total, 10);
      expect(reporter.current.percent, closeTo(0.3, 1e-6));
    });

    test('step() clamps the ratio into [0.0, 1.0]', () {
      final reporter = ProgressReporter('work');
      addTearDown(reporter.dispose);

      reporter.step('overflow', 12, 10);
      expect(reporter.current.percent, 1.0);
    });

    test('step() with total <= 0 degrades to 0 % rather than NaN', () {
      final reporter = ProgressReporter('work');
      addTearDown(reporter.dispose);

      reporter.step('weird', 5, 0);
      expect(reporter.current.percent, 0.0);
    });

    test('step() with a negative current clamps the ratio up to 0.0', () {
      // A nonsensical negative numerator must not surface a negative
      // percent to the bar; the clamp pins the floor at 0.0.
      final reporter = ProgressReporter('work');
      addTearDown(reporter.dispose);

      reporter.step('underflow', -3, 10);
      expect(reporter.current.percent, 0.0);
    });

    test('after dispose, step() updates current but does not throw', () {
      // `_emit` guards on `_controller.isClosed`, so a late update
      // after dispose still refreshes `current` (a late frame seed)
      // without adding to a closed stream and crashing.
      final reporter = ProgressReporter('A');
      reporter.dispose();

      expect(() => reporter.step('late', 1, 2), returnsNormally);
      expect(reporter.current.label, 'late');
      expect(reporter.current.percent, closeTo(0.5, 1e-6));
    });

    test('stream emits on every transition', () async {
      final reporter = ProgressReporter('A');
      addTearDown(reporter.dispose);
      final observed = <String>[];
      final sub = reporter.stream.listen((s) => observed.add(s.label));

      reporter.phase('B');
      reporter.step('C', 1, 2);
      reporter.phase('D');

      // Broadcast delivery is async — let the microtask queue drain.
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(observed, ['B', 'C', 'D']);
    });
  });

  group('ProgressState', () {
    test('default constructor carries an explicit percent + step counts', () {
      // The step-based constructor path: a measurable phase populates
      // percent within [0,1] plus the current/total step counters the
      // dialog renders as "3 of 12".
      const state = ProgressState(
        label: 'Importing',
        percent: 0.25,
        current: 3,
        total: 12,
      );
      expect(state.label, 'Importing');
      expect(state.percent, 0.25);
      expect(state.current, 3);
      expect(state.total, 12);
    });

    test('indeterminate constructor nulls out percent + step counts', () {
      const state = ProgressState.indeterminate('Hashing');
      expect(state.label, 'Hashing');
      expect(state.percent, isNull);
      expect(state.current, isNull);
      expect(state.total, isNull);
    });
  });
}
