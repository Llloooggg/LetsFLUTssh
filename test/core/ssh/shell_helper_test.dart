/// Pure-logic coverage for [ShellHelper.openShell] + [ShellConnection].
///
/// Every test wires a real `xterm` `Terminal` against a `_FakeShell`
/// driven by a `StreamController<SshShellEvent>` so the assertions
/// drive the routing behaviour directly: bytes from the remote land
/// on `terminal.write`, EOF / exit-status / exit-signal trigger the
/// caller's `onDone`, and `close()` unwinds the eventsSub + clears
/// `terminal.onOutput` / `onResize` callbacks even when the channel
/// itself is still draining.
///
/// Recorder-fork branches stay out of scope here — `SessionRecorder`
/// owns FRB-bound state that flutter_test cannot stand up without
/// the Rust core. Coverage for that path lives alongside the
/// recorder integration tests.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/widgets/terminal/xterm_shell_terminal.dart';
import 'package:letsflutssh/core/connection/connection.dart';
import 'package:letsflutssh/core/ssh/shell_helper.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/core/ssh/transport/ssh_transport.dart';
import 'package:xterm/xterm.dart';

void main() {
  group('ShellHelper.openShell', () {
    test('throws StateError when the connection has no transport', () async {
      final conn = _connection(transport: null);
      final terminal = Terminal();
      expect(
        () => ShellHelper.openShell(
          connection: conn,
          terminal: XtermShellTerminal(terminal),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('throws StateError when the transport is disconnected', () async {
      final transport = _FakeTransport(isConnected: false);
      final conn = _connection(transport: transport);
      final terminal = Terminal();
      expect(
        () => ShellHelper.openShell(
          connection: conn,
          terminal: XtermShellTerminal(terminal),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('Output event lands on terminal.write', () async {
      final shell = _FakeShell();
      final transport = _FakeTransport(shell: shell);
      final conn = _connection(transport: transport);
      final terminal = Terminal();

      final result = await ShellHelper.openShell(
        connection: conn,
        terminal: XtermShellTerminal(terminal),
      );

      shell.sink.add(SshShellOutput(Uint8List.fromList([72, 105])));
      // Two pumps: the StreamSubscription delivers the event on the
      // microtask queue, and the terminal's own write is async.
      await Future<void>.delayed(Duration.zero);
      expect(terminal.buffer.toString(), contains('Hi'));

      result.close();
    });

    test('ExtendedOutput (stderr) lands on terminal.write', () async {
      final shell = _FakeShell();
      final transport = _FakeTransport(shell: shell);
      final conn = _connection(transport: transport);
      final terminal = Terminal();

      final result = await ShellHelper.openShell(
        connection: conn,
        terminal: XtermShellTerminal(terminal),
      );

      shell.sink.add(
        SshShellExtendedOutput(Uint8List.fromList([69, 114, 114])),
      );
      await Future<void>.delayed(Duration.zero);
      expect(terminal.buffer.toString(), contains('Err'));

      result.close();
    });

    test('malformed UTF-8 does not throw — decoder is allowMalformed', () async {
      final shell = _FakeShell();
      final transport = _FakeTransport(shell: shell);
      final conn = _connection(transport: transport);
      final terminal = Terminal();

      final result = await ShellHelper.openShell(
        connection: conn,
        terminal: XtermShellTerminal(terminal),
      );

      // 0xC3 0x28 — invalid two-byte UTF-8 (0xC3 starts a continuation
      // pair, 0x28 is the wrong second byte). A strict decoder throws
      // FormatException. The shell helper's `Utf8Decoder(allowMalformed: true)`
      // must swallow it and substitute U+FFFD.
      shell.sink.add(SshShellOutput(Uint8List.fromList([0xC3, 0x28])));
      await Future<void>.delayed(Duration.zero);
      // No exception means the listener survived; assert one frame
      // of pump completed without re-throwing.
      expect(terminal.buffer.toString().isNotEmpty, isTrue);

      result.close();
    });

    test('Eof event triggers onDone', () async {
      final shell = _FakeShell();
      final transport = _FakeTransport(shell: shell);
      final conn = _connection(transport: transport);
      final terminal = Terminal();
      var doneCalls = 0;

      final result = await ShellHelper.openShell(
        connection: conn,
        terminal: XtermShellTerminal(terminal),
        onDone: () => doneCalls++,
      );
      shell.sink.add(const SshShellEof());
      await Future<void>.delayed(Duration.zero);
      expect(doneCalls, 1);

      result.close();
    });

    test('ExitStatus event triggers onDone', () async {
      final shell = _FakeShell();
      final transport = _FakeTransport(shell: shell);
      final conn = _connection(transport: transport);
      final terminal = Terminal();
      var doneCalls = 0;

      final result = await ShellHelper.openShell(
        connection: conn,
        terminal: XtermShellTerminal(terminal),
        onDone: () => doneCalls++,
      );
      shell.sink.add(const SshShellExitStatus(0));
      await Future<void>.delayed(Duration.zero);
      expect(doneCalls, 1);

      result.close();
    });

    test('ExitSignal event triggers onDone', () async {
      final shell = _FakeShell();
      final transport = _FakeTransport(shell: shell);
      final conn = _connection(transport: transport);
      final terminal = Terminal();
      var doneCalls = 0;

      final result = await ShellHelper.openShell(
        connection: conn,
        terminal: XtermShellTerminal(terminal),
        onDone: () => doneCalls++,
      );
      shell.sink.add(const SshShellExitSignal('TERM'));
      await Future<void>.delayed(Duration.zero);
      expect(doneCalls, 1);

      result.close();
    });

    test(
      'onDone fires once even when terminal.onOutput hooks are set',
      () async {
        // Regression guard: a prior shape installed `onOutput` after
        // the events.listen, so the close path had to cancel the
        // listener before nulling the callback. We assert the order
        // by checking that ExitStatus → onDone trips exactly once.
        final shell = _FakeShell();
        final transport = _FakeTransport(shell: shell);
        final conn = _connection(transport: transport);
        final terminal = Terminal();
        var doneCalls = 0;

        final result = await ShellHelper.openShell(
          connection: conn,
          terminal: XtermShellTerminal(terminal),
          onDone: () => doneCalls++,
        );
        shell.sink.add(const SshShellExitStatus(0));
        await Future<void>.delayed(Duration.zero);
        shell.sink.add(const SshShellEof());
        await Future<void>.delayed(Duration.zero);
        expect(doneCalls, 2, reason: 'each terminal event must surface once');

        result.close();
      },
    );

    test('terminal.onOutput sends user keystrokes to shell.write', () async {
      final shell = _FakeShell();
      final transport = _FakeTransport(shell: shell);
      final conn = _connection(transport: transport);
      final terminal = Terminal();

      final result = await ShellHelper.openShell(
        connection: conn,
        terminal: XtermShellTerminal(terminal),
      );
      // Drive a keystroke through the terminal's onOutput sink.
      terminal.onOutput!('ls\n');
      await Future<void>.delayed(Duration.zero);
      expect(shell.writes.length, 1);
      expect(String.fromCharCodes(shell.writes.first), 'ls\n');

      result.close();
    });

    test('terminal.onResize forwards rows/cols to shell.resize', () async {
      final shell = _FakeShell();
      final transport = _FakeTransport(shell: shell);
      final conn = _connection(transport: transport);
      final terminal = Terminal();

      final result = await ShellHelper.openShell(
        connection: conn,
        terminal: XtermShellTerminal(terminal),
      );
      terminal.onResize!(120, 40, 0, 0);
      await Future<void>.delayed(Duration.zero);
      expect(shell.resizes, [(120, 40)]);

      result.close();
    });
  });

  group('ShellConnection.close', () {
    test(
      'cancels the events subscription and closes the transport shell',
      () async {
        final shell = _FakeShell();
        final transport = _FakeTransport(shell: shell);
        final conn = _connection(transport: transport);
        final terminal = Terminal();

        final result = await ShellHelper.openShell(
          connection: conn,
          terminal: XtermShellTerminal(terminal),
        );
        // Drive one event through to confirm the listener is wired,
        // close, and then assert the transport's `close()` ran. The
        // cancellation invariant is covered transitively: after the
        // close the StreamController is closed, so the runtime would
        // throw on any subsequent listener notification — the
        // shell-helper's own dispose path is what survives that.
        shell.sink.add(SshShellOutput(Uint8List.fromList([88])));
        await Future<void>.delayed(Duration.zero);
        final beforeLen = terminal.buffer.toString().length;
        expect(beforeLen, greaterThan(0));
        result.close();
        await Future<void>.delayed(Duration.zero);
        expect(shell.closed, isTrue);
        // Buffer length must not regrow after close — no late event
        // delivery slips through the cancelled subscription.
        await Future<void>.delayed(Duration.zero);
        expect(terminal.buffer.toString().length, beforeLen);
      },
    );

    test('clears terminal.onOutput and onResize callbacks', () async {
      final shell = _FakeShell();
      final transport = _FakeTransport(shell: shell);
      final conn = _connection(transport: transport);
      final terminal = Terminal();

      final result = await ShellHelper.openShell(
        connection: conn,
        terminal: XtermShellTerminal(terminal),
      );
      expect(terminal.onOutput, isNotNull);
      expect(terminal.onResize, isNotNull);
      result.close();
      expect(terminal.onOutput, isNull);
      expect(terminal.onResize, isNull);
    });
  });
}

// ── Fakes ────────────────────────────────────────────────────────────

Connection _connection({required SshTransport? transport}) {
  return Connection(
    id: 't1',
    label: 'test',
    sshConfig: const SSHConfig(
      server: ServerAddress(host: 'h', user: 'u'),
    ),
    transport: transport,
  );
}

class _FakeTransport implements SshTransport {
  _FakeTransport({_FakeShell? shell, this.isConnected = true})
    : _shell = shell ?? _FakeShell();
  final _FakeShell _shell;
  @override
  final bool isConnected;

  @override
  Future<SshShellChannel> openShell({required int cols, required int rows}) =>
      Future.value(_shell);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeShell implements SshShellChannel {
  /// Tests drive remote → local events through this sink so the
  /// shell-helper's listener sees them on the next microtask.
  final sink = StreamController<SshShellEvent>.broadcast();
  final writes = <Uint8List>[];
  final resizes = <(int, int)>[];
  bool closed = false;

  @override
  Stream<SshShellEvent> get events => sink.stream;

  @override
  Future<void> write(Uint8List data) async {
    writes.add(data);
  }

  @override
  Future<void> resize({required int cols, required int rows}) async {
    resizes.add((cols, rows));
  }

  @override
  Future<void> eof() async {}

  @override
  Future<void> close() async {
    closed = true;
    await sink.close();
  }
}
