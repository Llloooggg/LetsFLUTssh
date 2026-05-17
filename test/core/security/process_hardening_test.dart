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

    test('isBeingDebugged returns a bool without throwing', () {
      // Pin the no-throw contract — biometric unlock consults this on
      // every attempt; a throw here would brick T1+pw / T2+pw startup.
      // The probe is fail-safe-false on FRB unreachability (flutter_test
      // never boots the native blob), so under the test runner this
      // always returns false, but the contract that matters is the
      // no-throw guarantee.
      final got = ProcessHardening.isBeingDebugged();
      expect(got, isA<bool>());
      // In flutter_test FRB is unreachable → probe falls through to
      // the catch branch and returns false. Pin this so a future
      // refactor that swallows the catch doesn't silently flip the
      // policy default.
      expect(got, isFalse);
    });
  });
}
