import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/connection/connection.dart';
import 'package:letsflutssh/core/connection/connection_manager.dart';
import 'package:letsflutssh/core/security/lock_state.dart';
import 'package:letsflutssh/core/security/security_level.dart';
import 'package:letsflutssh/core/ssh/known_hosts.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/providers/auto_lock_provider.dart';
import 'package:letsflutssh/providers/connection_provider.dart';
import 'package:letsflutssh/providers/security_provider.dart';
import 'package:letsflutssh/widgets/auto_lock_detector.dart';

/// Notifier test doubles ----------------------------------------------------

class _AutoLockMinutes extends AutoLockMinutesNotifier {
  _AutoLockMinutes(this.initial);
  final int initial;

  @override
  int build() => initial;
}

/// Always-ready connection manager double — the detector only reads
/// `connections` to decide whether to wipe the DB key on lock, so we
/// don't need a real SSH stack.
class _StubConnectionManager extends ConnectionManager {
  _StubConnectionManager(this._conns) : super(knownHosts: KnownHostsManager());
  final List<Connection> _conns;

  @override
  List<Connection> get connections => _conns;
}

Widget _host(Widget child) {
  return MaterialApp(home: Scaffold(body: child));
}

void main() {
  group('AutoLockDetector timer behaviour', () {
    testWidgets('plaintext mode never arms the lock timer', (tester) async {
      final container = ProviderContainer(
        overrides: [
          autoLockMinutesProvider.overrideWith(() => _AutoLockMinutes(1)),
          knownHostsProvider.overrideWithValue(KnownHostsManager()),
          connectionManagerProvider.overrideWithValue(
            _StubConnectionManager(const []),
          ),
        ],
      );
      addTearDown(container.dispose);

      // Security level stays at default `plaintext` — no transition.
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: _host(const AutoLockDetector(child: Text('content'))),
        ),
      );
      await tester.pumpAndSettle();

      // Advance far beyond the configured 1 minute — lock must not fire
      // because security level is plaintext.
      await tester.pump(const Duration(minutes: 10));

      expect(
        container.read(lockStateProvider),
        false,
        reason:
            'auto-lock is only meaningful in master-password mode; '
            'plaintext has no secret to re-prove',
      );
    });

    testWidgets(
      'minutes=0 disables the timer even under master-password mode',
      (tester) async {
        final container = ProviderContainer(
          overrides: [
            autoLockMinutesProvider.overrideWith(() => _AutoLockMinutes(0)),
            knownHostsProvider.overrideWithValue(KnownHostsManager()),
            connectionManagerProvider.overrideWithValue(
              _StubConnectionManager(const []),
            ),
          ],
        );
        addTearDown(container.dispose);
        container
            .read(securityStateProvider.notifier)
            .set(SecurityLevel.masterPassword, Uint8List(32));

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: _host(const AutoLockDetector(child: Text('content'))),
          ),
        );
        await tester.pumpAndSettle();

        await tester.pump(const Duration(hours: 2));

        expect(container.read(lockStateProvider), false);
      },
    );

    testWidgets(
      'idle timeout in MP mode with no sessions locks AND clears the key',
      (tester) async {
        final container = ProviderContainer(
          overrides: [
            // 1-minute timeout so the test only advances wall-clock once.
            autoLockMinutesProvider.overrideWith(() => _AutoLockMinutes(1)),
            knownHostsProvider.overrideWithValue(KnownHostsManager()),
            connectionManagerProvider.overrideWithValue(
              _StubConnectionManager(const []),
            ),
          ],
        );
        addTearDown(container.dispose);
        container
            .read(securityStateProvider.notifier)
            .set(SecurityLevel.masterPassword, Uint8List(32));
        expect(container.read(securityStateProvider).encryptionKey, isNotNull);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: _host(const AutoLockDetector(child: Text('content'))),
          ),
        );
        await tester.pumpAndSettle();

        // Tick past the 1-minute budget.
        await tester.pump(const Duration(minutes: 1, seconds: 1));

        expect(
          container.read(lockStateProvider),
          true,
          reason: 'timer expiry must flip the lock overlay',
        );
        expect(
          container.read(securityStateProvider).encryptionKey,
          isNull,
          reason:
              'no live sessions → the in-memory DB key must be zeroed '
              'at the same time as the lock',
        );
      },
    );

    testWidgets('idle timeout with live sessions locks but keeps the key warm', (
      tester,
    ) async {
      // One "active" connection so the detector can see the list is non-empty.
      final liveConn = Connection(
        id: 'alive',
        label: 'alive',
        sshConfig: const SSHConfig(
          server: ServerAddress(host: 'x', user: 'u'),
        ),
        state: SSHConnectionState.connected,
      );
      final container = ProviderContainer(
        overrides: [
          autoLockMinutesProvider.overrideWith(() => _AutoLockMinutes(1)),
          knownHostsProvider.overrideWithValue(KnownHostsManager()),
          connectionManagerProvider.overrideWithValue(
            _StubConnectionManager([liveConn]),
          ),
        ],
      );
      addTearDown(container.dispose);
      container
          .read(securityStateProvider.notifier)
          .set(SecurityLevel.masterPassword, Uint8List(32));

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: _host(const AutoLockDetector(child: Text('content'))),
        ),
      );
      await tester.pumpAndSettle();

      await tester.pump(const Duration(minutes: 1, seconds: 1));

      expect(
        container.read(lockStateProvider),
        true,
        reason: 'lock overlay always fires on timeout',
      );
      expect(
        container.read(securityStateProvider).encryptionKey,
        isNotNull,
        reason:
            'live sessions need DB reads on unlock — keep the key '
            'warm even while the UI is locked',
      );
    });

    testWidgets(
      'minimize with timer=Off does NOT lock (regression for user report '
      '"блокировка срабатывает если свернуть приложение")',
      (tester) async {
        final container = ProviderContainer(
          overrides: [
            // Timer OFF — auto-lock disabled entirely.
            autoLockMinutesProvider.overrideWith(() => _AutoLockMinutes(0)),
            knownHostsProvider.overrideWithValue(KnownHostsManager()),
            connectionManagerProvider.overrideWithValue(
              _StubConnectionManager(const []),
            ),
          ],
        );
        addTearDown(container.dispose);
        container
            .read(securityStateProvider.notifier)
            .set(SecurityLevel.masterPassword, Uint8List(32));

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: _host(const AutoLockDetector(child: Text('content'))),
          ),
        );
        await tester.pumpAndSettle();

        // Simulate the user switching away from the app.
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pump();

        expect(
          container.read(lockStateProvider),
          false,
          reason:
              'with the timer off the user has opted out of auto-lock '
              'entirely; minimizing must not lock',
        );
      },
    );

    testWidgets('minimize with timer>0 locks immediately', (tester) async {
      final container = ProviderContainer(
        overrides: [
          autoLockMinutesProvider.overrideWith(() => _AutoLockMinutes(15)),
          knownHostsProvider.overrideWithValue(KnownHostsManager()),
          connectionManagerProvider.overrideWithValue(
            _StubConnectionManager(const []),
          ),
        ],
      );
      addTearDown(container.dispose);
      container
          .read(securityStateProvider.notifier)
          .set(SecurityLevel.masterPassword, Uint8List(32));

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: _host(const AutoLockDetector(child: Text('content'))),
        ),
      );
      await tester.pumpAndSettle();

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();

      expect(
        container.read(lockStateProvider),
        true,
        reason:
            'when the user has chosen an idle timeout, backgrounding '
            'is treated as activity stop and the lock screen is '
            'pre-overlaid so the OS lock dismisses onto the lock UI',
      );
    });

    testWidgets('pointer activity resets the idle timer', (tester) async {
      final container = ProviderContainer(
        overrides: [
          autoLockMinutesProvider.overrideWith(() => _AutoLockMinutes(1)),
          knownHostsProvider.overrideWithValue(KnownHostsManager()),
          connectionManagerProvider.overrideWithValue(
            _StubConnectionManager(const []),
          ),
        ],
      );
      addTearDown(container.dispose);
      container
          .read(securityStateProvider.notifier)
          .set(SecurityLevel.masterPassword, Uint8List(32));

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: _host(const AutoLockDetector(child: SizedBox.expand())),
        ),
      );
      await tester.pumpAndSettle();

      // Sit idle for 50s, then tap to reset — 11s more should NOT fire
      // the lock because the reset gave another full minute.
      await tester.pump(const Duration(seconds: 50));
      // Listener uses `HitTestBehavior.translucent` so it always sees
      // pointer-down even over empty children — warnIfMissed=false
      // silences flutter_test's false-positive hit-test complaint.
      await tester.tap(find.byType(SizedBox).first, warnIfMissed: false);
      await tester.pump(const Duration(seconds: 11));

      expect(
        container.read(lockStateProvider),
        false,
        reason:
            'pointer-down within the window must restart the timer, '
            'otherwise an actively-used app would auto-lock mid-work',
      );
    });
  });
}
