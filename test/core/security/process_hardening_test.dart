import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/process_hardening.dart';

void main() {
  group('ProcessHardening', () {
    test('applyOnStartup never throws', () {
      // The whole point is "best-effort + log on failure". A test process
      // already running under a debugger or with quirky libc bindings must
      // not crash app startup. We just verify the call returns normally.
      ProcessHardening.applyOnStartup();
      ProcessHardening.applyOnStartup(); // second call also fine
    });
  });
}
