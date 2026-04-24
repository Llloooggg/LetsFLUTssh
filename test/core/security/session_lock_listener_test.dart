import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/session_lock_listener.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The listener is the only bridge between an OS-level Win+L / screen-
  // lock / dbus-lock event and the in-app auto-lock path. A regression
  // here silently reverts the "lock when the OS locks" behaviour
  // shipped in 7.0 — the user would think their session is locked
  // when the terminal UI in fact is still live.
  //
  // Tests seed a mock MethodChannel then drive the native-to-Dart
  // `sessionLocked` direction via `handlePlatformMessage`.

  group('SessionLockListener', () {
    const channelName = 'com.letsflutssh/session_lock';
    const channel = MethodChannel(channelName);
    final binding = TestDefaultBinaryMessengerBinding.instance;

    late List<MethodCall> outboundCalls;

    setUp(() {
      outboundCalls = [];
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        outboundCalls.add(call);
        return null;
      });
    });

    tearDown(() {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    });

    test(
      'first addListener installs the handler and calls `start` on desktop',
      () {
        final listener = SessionLockListener();
        listener.addListener(() {});
        // `start` is invoked on Linux / macOS / Windows; test host is
        // Linux, so exactly one `start` lands.
        expect(outboundCalls, hasLength(1));
        expect(outboundCalls.single.method, 'start');
      },
    );

    test('addListener is idempotent — only one `start` per instance', () {
      final listener = SessionLockListener();
      listener.addListener(() {});
      listener.addListener(() {});
      listener.addListener(() {});
      expect(outboundCalls, hasLength(1));
    });

    test(
      'sessionLocked native call fans out to every registered callback',
      () async {
        final listener = SessionLockListener();
        var a = 0;
        var b = 0;
        listener.addListener(() => a++);
        listener.addListener(() => b++);

        // Simulate the native side posting a session-lock event by
        // routing a platform message into the same channel's handler.
        final codec = const StandardMethodCodec();
        final payload = codec.encodeMethodCall(
          const MethodCall('sessionLocked'),
        );
        await binding.defaultBinaryMessenger.handlePlatformMessage(
          channelName,
          payload,
          (_) {},
        );

        expect(a, 1);
        expect(b, 1);
      },
    );

    test(
      'removeListener unsubscribes — further events skip that callback',
      () async {
        final listener = SessionLockListener();
        var hits = 0;
        final remove = listener.addListener(() => hits++);
        remove();

        final payload = const StandardMethodCodec().encodeMethodCall(
          const MethodCall('sessionLocked'),
        );
        await binding.defaultBinaryMessenger.handlePlatformMessage(
          channelName,
          payload,
          (_) {},
        );
        expect(hits, 0);
      },
    );

    test('a throwing callback does not stop the fan-out', () async {
      final listener = SessionLockListener();
      var secondFired = false;
      listener.addListener(() {
        throw StateError('ouch');
      });
      listener.addListener(() {
        secondFired = true;
      });

      final payload = const StandardMethodCodec().encodeMethodCall(
        const MethodCall('sessionLocked'),
      );
      await binding.defaultBinaryMessenger.handlePlatformMessage(
        channelName,
        payload,
        (_) {},
      );
      // Swallowing one callback's throw is load-bearing — the
      // auto-lock path registers one listener, but other surfaces
      // (e.g. the diagnostic overlay) could register more later.
      // A bad callback must not brick the rest of the chain.
      expect(secondFired, isTrue);
    });

    test('unknown native method is a no-op', () async {
      final listener = SessionLockListener();
      var hits = 0;
      listener.addListener(() => hits++);
      final payload = const StandardMethodCodec().encodeMethodCall(
        const MethodCall('somethingElse'),
      );
      await binding.defaultBinaryMessenger.handlePlatformMessage(
        channelName,
        payload,
        (_) {},
      );
      // Guards against a future native-side method name collision
      // that would otherwise fire the lock handler on an unrelated
      // event.
      expect(hits, 0);
    });
  });
}
