import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/src/rust/api/rate_limit.dart' as rust_rate_limit;

import 'frb_bootstrap.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await requireFrbLoaded();
  });

  test('rateLimitBackoffScheduleSeconds returns the Rust schedule', () {
    final schedule = rust_rate_limit.rateLimitBackoffScheduleSeconds();
    expect(schedule, isNotEmpty);
    expect(schedule.first.toInt(), 0);
    expect(schedule.last.toInt(), 60);
  });
}
