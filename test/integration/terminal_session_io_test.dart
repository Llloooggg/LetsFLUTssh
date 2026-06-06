/// End-to-end terminal-session I/O against the in-process russh fixture.
///
/// Guards the write path of `TerminalSession`: input no longer awaits
/// `shell.write` inline on the read pump — every keystroke / paste / PTY
/// reply is queued for a dedicated per-session writer task
/// (`shell_writer_loop`). The decoupling exists because an inline write
/// that blocks on the channel's exhausted send-window would stall the
/// read loop, fill the shell's inbound buffer, head-of-line-block the
/// shared russh session loop, and starve the window-adjust that would
/// unblock the write — a whole-connection deadlock across every shell.
///
/// These tests can't deterministically force that flow-control deadlock,
/// but they pin the load-bearing wiring it depends on: that bytes written
/// through the queue actually reach the shell (a mis-wired enqueue would
/// silently drop input — exactly the user-visible "input is dead" symptom)
/// and that the pump keeps flowing for a SECOND round trip after the first
/// (a wedged read loop would hang the second echo). The fixture echoes
/// shell-channel input straight back as output, so a snapshot after a
/// write reflects the full `write → writer-task → shell → server → pump →
/// engine` loop.
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/connection/connection.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/providers/connection_provider.dart';
import 'package:letsflutssh/src/rust/api/app.dart' as rust_app;
import 'package:letsflutssh/src/rust/api/db.dart' as rust_db;
import 'package:letsflutssh/src/rust/api/terminal.dart' as rust_terminal;
import 'package:letsflutssh/src/rust/api/test_hooks.dart' as rust_test;

import '../helpers/frb_bootstrap.dart';

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

  ProviderContainer makeContainer() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    return c;
  }

  SSHConfig configFor(String password) => SSHConfig(
    server: ServerAddress(host: '127.0.0.1', port: serverInfo.port, user: 'u'),
    auth: SshAuth(password: password),
  );

  /// Flatten a snapshot's sparse cells into reading order so a marker can
  /// be matched as a contiguous substring (the echo of a single write
  /// lands on one row, columns left-to-right).
  String gridText(rust_terminal.TerminalFrame frame) {
    final cells = [...frame.cells]
      ..sort(
        (a, b) =>
            a.row != b.row ? a.row.compareTo(b.row) : a.col.compareTo(b.col),
      );
    return cells.map((c) => String.fromCharCode(c.ch)).join();
  }

  /// Poll the engine grid until `needle` appears or the deadline passes.
  /// `snapshot()` reads the Rust-owned grid directly, so this observes the
  /// pump's feeds without depending on the UI-event stream.
  Future<void> waitForEcho(
    rust_terminal.TerminalSession session,
    String needle,
  ) async {
    final deadline = DateTime.now().add(const Duration(seconds: 8));
    while (DateTime.now().isBefore(deadline)) {
      if (gridText(session.snapshot()).contains(needle)) return;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    fail('terminal grid never echoed "$needle"');
  }

  test('input written through the writer queue round-trips, and the pump '
      'stays live for a second write', () async {
    final container = makeContainer();
    final notifier = container.read(connectionsProvider.notifier);
    final conn = notifier.connectAsync(
      configFor(serverInfo.password),
      label: 'terminal-io',
    );
    await conn.waitUntilReady();
    await conn.transportReady;
    expect(conn.state, SSHConnectionState.connected);

    final transport = conn.transport!;
    final session = await transport.openTerminalSession(
      cols: 80,
      rows: 24,
      scrollback: 1000,
      palette: rust_terminal.terminalPaletteDefault(),
    );

    // Subscribing starts the Rust pump (the single consumer of the
    // shell's events). It must be live before we write so the echoed
    // bytes get fed into the engine.
    final pump = session.events().listen((_) {});

    // First round trip: a write through the queue must reach the shell
    // and the echo must feed back into the grid. A mis-wired enqueue
    // would drop the bytes and this would time out.
    await session.writeInput(bytes: utf8.encode('roundtripONE'));
    await waitForEcho(session, 'roundtripONE');

    // Second round trip: proves the read pump did not wedge on the
    // first write (the deadlock symptom). With the old inline-write
    // pump a blocked write could stall the loop; here the queue keeps
    // the loop draining, so the second echo must arrive too.
    await session.writeInput(bytes: utf8.encode('roundtripTWO'));
    await waitForEcho(session, 'roundtripTWO');

    await pump.cancel();
    session.dispose();
    notifier.disconnect(conn.id);
  });
}
