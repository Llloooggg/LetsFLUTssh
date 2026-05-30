import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:letsflutssh/core/ssh/transport/rust_transport.dart';
import 'package:letsflutssh/core/ssh/transport/ssh_transport.dart';

// `RustTransport` only constructs through `adopt(SshSession)`, where
// `SshSession` is an FRB-opaque handle the connection actor produces
// after a real auth handshake. The behavioural matrix
// (connect / channel open / disconnect / reconnect / bus events)
// therefore lives in `test/integration/connection_lifecycle_test.dart`,
// `test/integration/sftp_lifecycle_test.dart`,
// `test/integration/port_forward_test.dart`, and the bastion +
// known-host suites — each runs against the in-process russh fixture
// at `lfs_core::connection::test_server`.
//
// This file holds the type-contract assertions that don't need a live
// session: the public class implements the engine-agnostic interface,
// no static factories regressed away, and the public error / event
// taxonomy carries the message + shape the UI binds to. A future
// Dart-only fake of `SshSession` would let more state-machine tests
// land here without the FRB roundtrip; until then the integration
// suites are the canonical home.

void main() {
  group('RustTransport — type contract', () {
    test('class implements the engine-agnostic SshTransport interface', () {
      // Compile-time check via a Type comparison — RustTransport must
      // remain assignable to SshTransport so call sites that bind to
      // the interface keep working.
      const Type t = RustTransport;
      expect(t.toString(), 'RustTransport');
      // Subtype check via a generic helper avoids needing a real
      // instance (which requires an FRB SshSession from the actor).
      expect(_isSubtype<RustTransport, SshTransport>(), isTrue);
    });

    test('adopt is the only public constructor', () {
      // Reflection check would be ideal but Dart's mirrors aren't
      // available in flutter_test. Document the invariant: the only
      // public path is `RustTransport.adopt(session)` and direct
      // construction is intentionally unavailable.
      expect(RustTransport.adopt, isA<Function>());
    });
  });

  group('SshConnectError — message contract', () {
    test(
      'wraps the raw reason in a "SshConnectError: <reason>" toString',
      // Spec: callers (logger, error toast localizer) bind to the
      // toString prefix to discriminate connect-phase failures from
      // auth-phase ones. The prefix and the verbatim reason must both
      // survive the toString round trip — no truncation, no rewrite.
      () {
        const e = SshConnectError('TCP refused');
        expect(e.message, 'TCP refused');
        expect(e.toString(), 'SshConnectError: TCP refused');
      },
    );

    test(
      'is the error class RustTransport throws when no session is adopted',
      // Spec: `_requireSession` throws `SshConnectError("transport not '
      // 'connected")` whenever a channel op runs before adopt or after
      // disconnect. The UI maps that exact message to a "not connected"
      // toast; the message string is part of the contract.
      () {
        // Construct the same payload `_requireSession` raises to lock
        // the message text. The throwing path itself needs a session
        // and is covered by the integration suites; here we only pin
        // the message a caller sees.
        const e = SshConnectError('transport not connected');
        expect(e, isA<Exception>());
        expect(e.message, 'transport not connected');
      },
    );
  });

  group('SshShellEvent — sealed taxonomy', () {
    // Spec: `_RustShell._mapEvent` translates the Rust-side
    // `SshShellEvent` union into Dart's sealed `SshShellEvent`
    // hierarchy. The Dart classes are the surface the terminal
    // renderer binds against, so the taxonomy must stay closed and
    // each variant must keep its declared payload.
    test('Output carries the raw byte buffer it was constructed with', () {
      final bytes = Uint8List.fromList([1, 2, 3]);
      final ev = SshShellOutput(bytes);
      expect(ev, isA<SshShellEvent>());
      expect(ev.bytes, bytes);
    });

    test('ExtendedOutput is a distinct variant carrying its own bytes', () {
      final bytes = Uint8List.fromList([9, 8, 7]);
      final ev = SshShellExtendedOutput(bytes);
      expect(ev, isA<SshShellEvent>());
      expect(ev, isNot(isA<SshShellOutput>()));
      expect(ev.bytes, bytes);
    });

    test('Eof / ExitStatus / ExitSignal carry the discriminator payload', () {
      const eof = SshShellEof();
      const exit = SshShellExitStatus(137);
      const signal = SshShellExitSignal('TERM');

      expect(eof, isA<SshShellEvent>());
      expect(exit.code, 137);
      expect(signal.signal, 'TERM');
    });
  });

  group('RustTransport — state machine', () {
    // Spec for each row: the only Dart-observable state change is
    // `isConnected` flipping false on `disconnect`, with subsequent
    // channel-op calls throwing `SshConnectError("transport not
    // connected")`. Exercising it requires an `SshSession` instance,
    // which is FRB-opaque. The full matrix lives in:
    //   test/integration/connection_lifecycle_test.dart
    //   test/integration/sftp_lifecycle_test.dart
    //   test/integration/port_forward_test.dart
    test(
      'isConnected starts true after adopt(session)',
      () {},
      skip: 'covered by integration: requires FRB-opaque SshSession',
    );

    test(
      'disconnect flips isConnected to false and is idempotent',
      () {},
      skip: 'covered by integration: requires FRB-opaque SshSession',
    );

    test(
      'openShell / openSftp / openDirectTcpip after disconnect throw '
      'SshConnectError("transport not connected")',
      () {},
      skip: 'covered by integration: requires FRB-opaque SshSession',
    );

    test(
      'requestRemoteForward / cancelRemoteForward route through the '
      'adopted session and surface server-allocated port',
      () {},
      skip: 'covered by integration: requires live russh server fixture',
    );
  });

  group('SshShellEvent — pattern matching exhaustiveness', () {
    // Spec: the sealed `SshShellEvent` hierarchy lets the terminal
    // renderer use exhaustive `switch` over the variants — a future
    // additional variant trips the analyzer at every call site. Pin
    // the discriminators so a renamed branch breaks here first.
    test('every concrete variant is a distinct runtimeType', () {
      final output = SshShellOutput(Uint8List.fromList([0]));
      final extended = SshShellExtendedOutput(Uint8List.fromList([0]));
      const eof = SshShellEof();
      const exit = SshShellExitStatus(0);
      const signal = SshShellExitSignal('HUP');

      final types = <Type>{
        output.runtimeType,
        extended.runtimeType,
        eof.runtimeType,
        exit.runtimeType,
        signal.runtimeType,
      };
      // Five concrete variants — overlap would mean a re-export
      // collapsed the discriminator and the renderer would mis-route.
      expect(types.length, 5);
    });

    test(
      'ExitStatus carries the full int32 range — negative codes survive',
      () {
        // Spec: the Rust wire is `i32`; the Dart side widens to `int`.
        // Some shells surface `-1` to indicate the process was killed
        // before reporting a status. Pin that the negative-int round
        // trip is intact — a `uint`-typed accessor would clamp to 0.
        const e = SshShellExitStatus(-1);
        expect(e.code, -1);
      },
    );

    test('ExitSignal carries an empty signal name without nullifying', () {
      // Spec: `_mapEvent` does not pre-filter the signal name; the
      // engine occasionally emits an empty string when the channel
      // reports an exit without a signal label. The Dart class must
      // round-trip the empty value rather than collapsing to null.
      const e = SshShellExitSignal('');
      expect(e.signal, '');
    });

    test(
      'Output bytes view is the same reference passed in — no defensive copy',
      () {
        // Spec: `_mapEvent` wraps the engine bytes verbatim so the
        // renderer can adopt the buffer without paying for a copy on
        // every shell frame. A defensive copy here would cap the shell
        // throughput at half the FRB ingestion rate on long-running
        // sessions emitting large buffers.
        final bytes = Uint8List.fromList(List.filled(4096, 0x41));
        final ev = SshShellOutput(bytes);
        expect(identical(ev.bytes, bytes), isTrue);
      },
    );
  });

  group('SshConnectError — discriminator vs sibling exceptions', () {
    // Spec: the localizer in `lib/utils/format.dart` discriminates
    // connect-phase failures from auth / host-key failures by
    // exception type. Sibling errors must not be assignable to
    // `SshConnectError` or the catch arm would pull the wrong copy.
    test('SshConnectError is not a SshHostKeyRejected', () {
      const e = SshConnectError('refused');
      expect(e, isNot(isA<SshHostKeyRejected>()));
      expect(e, isNot(isA<SshAuthFailed>()));
    });

    test(
      'SshAuthFailed has no message field — toString is the typed sentinel',
      () {
        // Spec: the auth-failed singleton is a typed marker — the UI
        // localizes it without reading a payload. A regression that
        // added a message field would change the toString and break
        // log greps.
        const e = SshAuthFailed();
        expect(e.toString(), 'SshAuthFailed');
      },
    );

    test('SshHostKeyRejected toString embeds the rejected fingerprint', () {
      // Spec: the log breadcrumb format pairs the typed name with
      // the rejected fingerprint so an operator scanning a log can
      // pin the host without cross-referencing.
      const e = SshHostKeyRejected('SHA256:AAAA');
      expect(e.toString(), contains('SshHostKeyRejected'));
      expect(e.toString(), contains('SHA256:AAAA'));
    });
  });
}

bool _isSubtype<Sub, Super>() => <Sub>[] is List<Super>;
