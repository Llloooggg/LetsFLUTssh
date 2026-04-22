import 'dart:ffi';
import 'dart:io' show Platform;

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/libc_loader.dart';

void main() {
  group('openLibc', () {
    test('resolves a libc that exposes mlock on POSIX hosts', () {
      if (Platform.isWindows) {
        // Windows has no libc.so — the helper is POSIX-only. The production
        // call sites already gate on Platform.isWindows before calling.
        return;
      }
      final libc = openLibc();
      // `mlock` must be present on every POSIX libc we care about
      // (glibc, bionic, musl, Darwin libSystem). A successful lookup
      // confirms the helper returned a real libc handle, not a stub.
      final mlock = libc
          .lookup<NativeFunction<Int32 Function(Pointer<Void>, IntPtr)>>(
            'mlock',
          );
      expect(mlock, isNotNull);
    });
  });
}
