import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/src/rust/api/log_sanitize.dart' as rust_sanitize;
import 'package:letsflutssh/utils/sanitize.dart' as dart_sanitize;

import '../helpers/frb_bootstrap.dart';

/// Drift guard: the Dart sanitizer in `lib/utils/sanitize.dart` and the
/// Rust sanitizer in `rust/crates/lfs_core/src/log_sanitize.rs` must
/// produce byte-identical output for every redaction shape.
///
/// Background. The pipeline used to live Rust-side only (FRB hop on
/// every error fan-out), but the cold-start path needs sanitisation
/// callable BEFORE `RustLib.init` completes — the global zone /
/// FlutterError handlers fire from the moment
/// `WidgetsFlutterBinding.ensureInitialized` returns, which is before
/// the post-frame `_initRustCoreOrFatal` hook runs. The Dart copy
/// stays as a structural pre-FRB safe path; this test is the
/// drift gate that catches if either implementation grows a regex
/// the other doesn't.
///
/// Add a row to `_corpus` whenever a new redaction shape lands on
/// either side.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(requireFrbLoaded);

  // Each entry exercises one redaction shape. Inputs are kept small
  // so a failure surfaces the exact site without log noise.
  final corpus = <String>[
    // PEM private key block.
    '-----BEGIN OPENSSH PRIVATE KEY-----\nb3BlbnNzaC1rZXkt\n-----END OPENSSH PRIVATE KEY-----',
    '-----BEGIN RSA PRIVATE KEY-----\nMIIEpAIBAAKCAQEA\n-----END RSA PRIVATE KEY-----',
    // Long base64 run.
    'config dump: ${'A' * 220}',
    // IPv4 with port.
    'connection refused: 192.168.1.10:22 on local',
    // IPv6 (compressed).
    'no route to host ::1',
    'no route to host fe80::abcd:1234:5678 retry',
    // user@host.
    'authentication failed for alice@bastion.example.com:2222',
    // as-user=, user=, login=.
    'sudo: as-user=root command="ls" denied',
    'sssd: user=admin login=admin auth fail',
    // host:port without an IP literal.
    'telnet to mail.example.org:993 timed out',
    // Unix home path.
    'open /home/alice/.ssh/known_hosts: permission denied',
    // Windows home path.
    r'open C:\Users\Alice\AppData\config.json: access denied',
    // Mix of two redactions in one message.
    'private key /home/bob/.ssh/id_ed25519 rejected by user@host:22',
    // Empty + plain control surface.
    '',
    'plain text with no secrets',
  ];

  group('sanitizer cross-impl drift', () {
    test('redactSecrets — Dart and Rust agree on every corpus row', () {
      for (final input in corpus) {
        final dartOut = dart_sanitize.redactSecrets(input);
        final rustOut = rust_sanitize.redactSecrets(input: input);
        expect(
          rustOut,
          dartOut,
          reason:
              'redactSecrets drift on input ${input.length} bytes:\n  $input',
        );
      }
    });

    test('sanitizeErrorMessage — Dart and Rust agree on every corpus row', () {
      for (final input in corpus) {
        final dartOut = dart_sanitize.sanitizeErrorMessage(input);
        final rustOut = rust_sanitize.sanitizeErrorMessage(input: input);
        expect(
          rustOut,
          dartOut,
          reason:
              'sanitizeErrorMessage drift on input ${input.length} bytes:\n  $input',
        );
      }
    });
  });
}
