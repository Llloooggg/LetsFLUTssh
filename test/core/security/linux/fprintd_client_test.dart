import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/linux/fprintd_client.dart';

/// Drives [FprintdClient] through its DI seams. No D-Bus, no fprintd
/// daemon, no real biometric reader — every off-Linux short-circuit
/// and every reachable / verify / enrolment branch gets exercised
/// against deterministic fakes.
void main() {
  group('FprintdClient.isServiceReachable', () {
    test('off-Linux short-circuit never calls Rust', () async {
      var calls = 0;
      final client = FprintdClient(
        isLinuxFn: () => false,
        reachableFn: () {
          calls += 1;
          return Future.value(true);
        },
      );
      expect(await client.isServiceReachable(), isFalse);
      expect(calls, 0);
    });

    test('forwards Rust true / false through unchanged', () async {
      bool nextValue = true;
      final client = FprintdClient(
        isLinuxFn: () => true,
        reachableFn: () => Future.value(nextValue),
      );
      expect(await client.isServiceReachable(), isTrue);
      nextValue = false;
      expect(await client.isServiceReachable(), isFalse);
    });
  });

  group('FprintdClient.getEnrolmentHash', () {
    test('off-Linux returns null without calling Rust', () async {
      var calls = 0;
      final client = FprintdClient(
        isLinuxFn: () => false,
        enrolmentHashFn: () {
          calls += 1;
          return Future.value(Uint8List.fromList([1, 2, 3]));
        },
      );
      expect(await client.getEnrolmentHash(), isNull);
      expect(calls, 0);
    });

    test(
      'Rust null (no fprintd / no enrolment) is propagated as null',
      () async {
        final client = FprintdClient(
          isLinuxFn: () => true,
          enrolmentHashFn: () => Future.value(null),
        );
        expect(await client.getEnrolmentHash(), isNull);
      },
    );

    test('Rust bytes are wrapped in a typed Uint8List', () async {
      final raw = Uint8List.fromList(List.generate(32, (i) => i ^ 0x42));
      final client = FprintdClient(
        isLinuxFn: () => true,
        enrolmentHashFn: () => Future.value(raw),
      );
      final got = await client.getEnrolmentHash();
      expect(got, isNotNull);
      expect(got!.length, 32);
      expect(got, raw);
    });
  });

  group('FprintdClient.hasEnrolledFingers', () {
    test('off-Linux returns false', () async {
      final client = FprintdClient(
        isLinuxFn: () => false,
        hasFingersFn: () => Future.value(true),
      );
      expect(await client.hasEnrolledFingers(), isFalse);
    });

    test('on-Linux forwards Rust verdict', () async {
      bool next = true;
      final client = FprintdClient(
        isLinuxFn: () => true,
        hasFingersFn: () => Future.value(next),
      );
      expect(await client.hasEnrolledFingers(), isTrue);
      next = false;
      expect(await client.hasEnrolledFingers(), isFalse);
    });
  });

  group('FprintdClient.verify', () {
    test(
      'off-Linux short-circuit returns false without calling Rust',
      () async {
        var calls = 0;
        final client = FprintdClient(
          isLinuxFn: () => false,
          verifyFn: ({required timeoutMs}) {
            calls += 1;
            return Future.value(true);
          },
        );
        expect(await client.verify(), isFalse);
        expect(calls, 0);
      },
    );

    test('passes the configured verify timeout into Rust as ms', () async {
      late int capturedMs;
      final client = FprintdClient(
        verifyTimeout: const Duration(seconds: 12),
        isLinuxFn: () => true,
        verifyFn: ({required timeoutMs}) {
          capturedMs = timeoutMs;
          return Future.value(true);
        },
      );
      await client.verify();
      expect(capturedMs, 12000);
    });

    test('default timeout is 30s when none is supplied', () async {
      late int capturedMs;
      final client = FprintdClient(
        isLinuxFn: () => true,
        verifyFn: ({required timeoutMs}) {
          capturedMs = timeoutMs;
          return Future.value(false);
        },
      );
      await client.verify();
      expect(capturedMs, 30000);
    });

    test('Rust verdict (match / no-match) is forwarded', () async {
      bool next = true;
      final client = FprintdClient(
        isLinuxFn: () => true,
        verifyFn: ({required timeoutMs}) => Future.value(next),
      );
      expect(await client.verify(), isTrue);
      next = false;
      expect(await client.verify(), isFalse);
    });
  });

  test('default ctor compiles without seam args', () {
    final client = FprintdClient();
    expect(client, isNotNull);
  });
}
