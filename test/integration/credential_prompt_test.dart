/// End-to-end proof of the mid-connect credential overlay.
///
/// An encrypted private key whose passphrase was never saved used to be
/// un-connectable: the connect failed with `PassphraseRequired` and the
/// workspace only showed a "re-edit the session" hint. Now the Rust
/// connect actor (`run_auth_with_credential_prompts`) fires a
/// `CredentialPromptRequest`, suspends the handshake, and resumes once
/// the typed passphrase is staged. This test drives that loop against
/// the in-process russh fixture (which accepts any pubkey, so the only
/// barrier is the client-side key decryption): connect with an
/// encrypted key + no passphrase, assert the prompt fires, resolve it
/// over the same FRB path the Dart overlay uses, and assert the
/// connection then reaches `connected`.
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/bus/app_bus.dart';
import 'package:letsflutssh/core/connection/connection.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/providers/connection_provider.dart';
import 'package:letsflutssh/src/rust/api/app.dart' as rust_app;
import 'package:letsflutssh/src/rust/api/bus.dart' as rust_bus;
import 'package:letsflutssh/src/rust/api/credential_prompt.dart' as rust_cred;
import 'package:letsflutssh/src/rust/api/db.dart' as rust_db;
import 'package:letsflutssh/src/rust/api/test_hooks.dart' as rust_test;

import '../helpers/frb_bootstrap.dart';

// An aes256-ctr / bcrypt-encrypted OpenSSH ed25519 key. Passphrase
// below. The fixture is a throwaway keypair generated for this test
// only — never used against any real host.
const _encryptedKey = '''-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAACmFlczI1Ni1jdHIAAAAGYmNyeXB0AAAAGAAAABB/Vp4ARt
FIf0FEcy/ChD1mAAAAGAAAAAEAAAAzAAAAC3NzaC1lZDI1NTE5AAAAIO1ysVyis+Mo+e6s
vNZ1NTFMNhGGwnl90UroY3d+T3XBAAAAoL/ufJflAxYdA26UwWokk43kH/ZM2YArEKBFmA
TrDKtxP0iqQmNkqklIAhZWFsFfwaiUOMlQzzC/4ROrlDya1TASZHulLe/xqEcOQMkyfNmE
0O9+4vga6vp8CBXzJxe7awt5WTW9Fh4CuvwDzHqtZrQN9ZGuYsro98gsDIME9b9Y/leoPT
uLZdgnViv4kRg8ZPophJ2WeeS06ZeKHVReU1M=
-----END OPENSSH PRIVATE KEY-----''';
const _passphrase = 'testpass123';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late rust_test.TestSshServerInfo serverInfo;

  setUpAll(() async {
    await requireFrbLoaded();
    await rust_app.dbInit(path: ':memory:', key: const []);
    serverInfo = await rust_test.testSshServerStart();
    await rust_db.dbKnownHostsUpsertByHostPort(
      host: '127.0.0.1',
      port: serverInfo.port,
      keyType: serverInfo.hostPubkeyAlgorithm,
      keyBase64: serverInfo.hostPubkeyB64,
      addedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
  });

  tearDownAll(() async {
    rust_test.testSshServerStopAll();
    await rust_app.dbClose();
  });

  test(
    'encrypted key with no saved passphrase prompts, then connects on submit',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(connectionsProvider.notifier);

      // Capture the credential prompt the connect actor fires.
      String? promptId;
      String? kind;
      final sub = AppBus.instance
          .subscribe(rust_bus.BusTopic.securityPrompt)
          .listen((e) {
            if (e is rust_bus.BusEvent_CredentialPromptRequest) {
              promptId = e.promptId;
              kind = e.kindWireName;
            }
          });
      addTearDown(() => sub.cancel());

      final conn = notifier.connectAsync(
        SSHConfig(
          server: ServerAddress(
            host: '127.0.0.1',
            port: serverInfo.port,
            user: 'u',
          ),
          // passphrase defaults to '' — the un-saved-passphrase case.
          auth: const SshAuth(keyData: _encryptedKey),
        ),
        label: 'enc-key',
      );

      // The actor must surface a passphrase prompt rather than failing.
      await _waitUntil(() => promptId != null, const Duration(seconds: 10));
      expect(kind, 'passphrase');
      expect(
        conn.state,
        isNot(SSHConnectionState.connected),
        reason: 'connect must wait on the passphrase, not race ahead',
      );

      // Resolve it the same way the Dart overlay does.
      rust_cred.credentialPromptResolveSubmit(
        promptId: promptId!,
        secretBytes: utf8.encode(_passphrase),
        rememberForSession: false,
      );

      await _waitForState(
        conn,
        SSHConnectionState.connected,
        const Duration(seconds: 15),
      );
      expect(
        conn.state,
        SSHConnectionState.connected,
        reason:
            'with the passphrase supplied the key decrypts and the '
            'handshake completes',
      );

      notifier.disconnect(conn.id);
    },
  );

  test(
    'password auth with no stored password prompts, then connects',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(connectionsProvider.notifier);

      String? promptId;
      String? kind;
      final sub = AppBus.instance
          .subscribe(rust_bus.BusTopic.securityPrompt)
          .listen((e) {
            if (e is rust_bus.BusEvent_CredentialPromptRequest) {
              promptId = e.promptId;
              kind = e.kindWireName;
            }
          });
      addTearDown(() => sub.cancel());

      final conn = notifier.connectAsync(
        SSHConfig(
          server: ServerAddress(
            host: '127.0.0.1',
            port: serverInfo.port,
            user: 'u',
          ),
          // Empty password — the "ask on connect" case (quick-connect or
          // a session whose password was deliberately not stored).
          auth: const SshAuth(password: ''),
        ),
        label: 'no-password',
      );

      await _waitUntil(() => promptId != null, const Duration(seconds: 10));
      expect(kind, 'password');
      expect(conn.state, isNot(SSHConnectionState.connected));

      rust_cred.credentialPromptResolveSubmit(
        promptId: promptId!,
        secretBytes: utf8.encode(serverInfo.password),
        rememberForSession: false,
      );

      await _waitForState(
        conn,
        SSHConnectionState.connected,
        const Duration(seconds: 15),
      );
      expect(conn.state, SSHConnectionState.connected);

      notifier.disconnect(conn.id);
    },
  );
}

Future<void> _waitUntil(bool Function() done, Duration timeout) async {
  final deadline = DateTime.now().add(timeout);
  while (!done()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('condition not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

Future<void> _waitForState(
  Connection conn,
  SSHConnectionState target,
  Duration timeout,
) async {
  final deadline = DateTime.now().add(timeout);
  while (conn.state != target) {
    if (DateTime.now().isAfter(deadline)) {
      fail('state did not reach $target within $timeout (still ${conn.state})');
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}
