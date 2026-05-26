/// Test-only frame-pump helper that drains FRB-async isolate-port
/// message delivery alongside Flutter's frame scheduler.
///
/// `WidgetTester.pumpAndSettle()` runs Flutter's scheduler until the
/// frame queue idles, but it does not guarantee that Dart's isolate
/// `ReceivePort` queues drain. `flutter_rust_bridge` returns from an
/// async Rust call by posting a completion message on a `SendPort`
/// the binding owns; under `testWidgets` that delivery rides on a
/// real `Timer.run` callback, which `testWidgets`'s fake-async zone
/// holds back until the simulated clock advances. The loop here
/// alternates a `tester.runAsync` step (which escapes the fake-async
/// zone for one real event-loop tick — long enough for the FRB
/// completion port message to flow) with a `tester.pump` frame so
/// `setState` callbacks scheduled by the FRB-future continuation
/// flush before the next iteration.
///
/// Usage:
///
/// ```dart
/// final rows = await pumpUntilFrbSettles(
///   tester,
///   rust_db.dbPortForwardsListForSession(sessionId: 's1'),
/// );
/// expect(rows, isEmpty);
/// ```
///
/// Production code does NOT need this helper — only `testWidgets`
/// tests where an FRB-async call is awaited inside (or transitively
/// triggered by) a widget event handler.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

/// Pumps frames and yields real event-loop ticks until [future]
/// completes or [timeout] elapses.
///
/// Returns the resolved value when the future succeeds. Rethrows the
/// future's error with its original stack trace when the future
/// fails. Throws [TimeoutException] when neither happens within
/// [timeout].
///
/// [step] is the duration passed to `tester.pump(step)`; the default
/// of zero keeps the simulated clock still while still allowing the
/// scheduler to advance one frame per iteration. Pass a non-zero
/// step when the future itself depends on a `Timer` firing in
/// fake-async time.
Future<T> pumpUntilFrbSettles<T>(
  WidgetTester tester,
  Future<T> future, {
  Duration timeout = const Duration(seconds: 5),
  Duration step = Duration.zero,
}) async {
  final stopwatch = Stopwatch()..start();
  T? value;
  Object? error;
  StackTrace? errorStack;
  var done = false;
  // Attaching the listener before the pump loop guarantees we
  // observe completion that happens on the very first microtask
  // turn after the future was created by the caller's argument
  // expression.
  unawaited(
    future.then(
      (v) {
        value = v;
        done = true;
      },
      onError: (Object e, StackTrace st) {
        error = e;
        errorStack = st;
        done = true;
      },
    ),
  );
  while (!done) {
    if (stopwatch.elapsed > timeout) {
      throw TimeoutException(
        'pumpUntilFrbSettles: future did not complete within $timeout',
      );
    }
    // `tester.runAsync` escapes the FakeAsync zone `testWidgets`
    // installs, so a real `Timer.run` (which `Future<void>.delayed
    // (Duration.zero)` schedules under the hood) actually fires.
    // The FRB completion port handler ships its result through that
    // tick; without escaping, the Timer queues against fake time
    // and never runs.
    await tester.runAsync(() async {
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump(step);
  }
  if (error != null) {
    Error.throwWithStackTrace(error!, errorStack ?? StackTrace.empty);
  }
  return value as T;
}
