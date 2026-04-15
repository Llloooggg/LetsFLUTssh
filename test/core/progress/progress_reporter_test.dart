import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/progress/progress_reporter.dart';

void main() {
  group('ProgressReporter', () {
    test('starts in indeterminate state with the initial label', () {
      final reporter = ProgressReporter('Loading');
      addTearDown(reporter.dispose);

      expect(reporter.state.value.label, 'Loading');
      expect(reporter.state.value.percent, isNull);
      expect(reporter.state.value.current, isNull);
      expect(reporter.state.value.total, isNull);
    });

    test('phase() switches to a new indeterminate label', () {
      final reporter = ProgressReporter('A');
      addTearDown(reporter.dispose);

      reporter.phase('B');
      expect(reporter.state.value.label, 'B');
      expect(reporter.state.value.percent, isNull);
    });

    test('step() computes percent from current/total', () {
      final reporter = ProgressReporter('work');
      addTearDown(reporter.dispose);

      reporter.step('Importing', 3, 10);
      expect(reporter.state.value.label, 'Importing');
      expect(reporter.state.value.current, 3);
      expect(reporter.state.value.total, 10);
      expect(reporter.state.value.percent, closeTo(0.3, 1e-6));
    });

    test('step() clamps the ratio into [0.0, 1.0]', () {
      final reporter = ProgressReporter('work');
      addTearDown(reporter.dispose);

      reporter.step('overflow', 12, 10);
      expect(reporter.state.value.percent, 1.0);
    });

    test('step() with total <= 0 degrades to 0 % rather than NaN', () {
      final reporter = ProgressReporter('work');
      addTearDown(reporter.dispose);

      reporter.step('weird', 5, 0);
      expect(reporter.state.value.percent, 0.0);
    });

    test('ValueNotifier fires on every transition', () {
      final reporter = ProgressReporter('A');
      addTearDown(reporter.dispose);
      final observed = <String>[];
      reporter.state.addListener(() {
        observed.add(reporter.state.value.label);
      });

      reporter.phase('B');
      reporter.step('C', 1, 2);
      reporter.phase('D');

      expect(observed, ['B', 'C', 'D']);
    });
  });
}
