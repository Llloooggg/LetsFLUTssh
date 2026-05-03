import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/session/session.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/features/recordings/recordings_logic.dart';

Session _session({
  required String id,
  String label = '',
  String host = 'example.com',
  int port = 22,
  String user = 'alice',
}) => Session(
  id: id,
  label: label,
  server: ServerAddress(host: host, port: port, user: user),
);

void main() {
  group('resolveRecordingSessionLabel', () {
    test('matched session with non-empty label returns the label verbatim', () {
      final s = _session(id: 'sid-1', label: 'Production DB');
      expect(resolveRecordingSessionLabel('sid-1', [s]), 'Production DB');
    });

    test('matched session with empty label falls through to displayName', () {
      // displayName is "user@host:port" when the label is empty.
      final s = _session(
        id: 'sid-2',
        label: '',
        host: 'example.com',
        port: 2222,
        user: 'root',
      );
      expect(
        resolveRecordingSessionLabel('sid-2', [s]),
        'root@example.com:2222',
      );
    });

    test(
      'orphaned recording surfaces a `<deleted>` sentinel + first 8 id chars',
      () {
        // Recording outlived its session — the user must still be able
        // to spot the orphan and delete it. The truncation keeps the
        // label readable inside an AppDataRow without dropping all
        // identifying detail.
        final out = resolveRecordingSessionLabel('0123456789abcdef', [
          _session(id: 'other'),
        ]);
        expect(out, '<deleted> 01234567');
      },
    );

    test('first match wins when two sessions share the id (defensive)', () {
      // The session list is the source of truth, but a corrupt cache
      // could in principle hold duplicate ids; pin "first match" so
      // the contract is explicit.
      final s1 = _session(id: 'dup', label: 'first');
      final s2 = _session(id: 'dup', label: 'second');
      expect(resolveRecordingSessionLabel('dup', [s1, s2]), 'first');
    });

    test('empty session list always falls into the orphan branch', () {
      expect(
        resolveRecordingSessionLabel('abcdef0123456789', const <Session>[]),
        '<deleted> abcdef01',
      );
    });
  });
}
