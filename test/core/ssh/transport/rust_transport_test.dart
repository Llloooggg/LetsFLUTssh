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
// no static factories regressed away. A future Dart-only fake of
// `SshSession` would let more state-machine tests land here without
// the FRB roundtrip; until then the integration suites are the
// canonical home.

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
}

bool _isSubtype<Sub, Super>() => <Sub>[] is List<Super>;
