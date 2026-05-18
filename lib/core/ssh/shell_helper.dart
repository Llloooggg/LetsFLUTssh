import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show VoidCallback;

import 'package:xterm/xterm.dart';

import '../connection/connection.dart';
import '../session/session_recorder.dart';
import 'transport/ssh_transport.dart';

/// Result of opening an SSH shell on a terminal.
class ShellConnection {
  final SshShellChannel transportShell;

  final StreamSubscription? eventsSub;
  final Terminal _terminal;

  /// Per-shell recorder. Mutable so the terminal toolbar's runtime
  /// record button can swap it in / out mid-stream — the shell's
  /// stdin / stdout listeners read this field on every chunk
  /// rather than capturing the value at openShell time. `null` =
  /// not recording right now; bytes flow to the terminal and back
  /// to the remote shell only.
  SessionRecorder? recorder;

  ShellConnection({
    required this.transportShell,
    this.eventsSub,
    required Terminal terminal,
    this.recorder,
  }) : _terminal = terminal;

  /// Send stdin bytes to the remote shell.
  void write(Uint8List bytes) => transportShell.write(bytes);

  /// Swap the active recorder. Closes the previous one (so the
  /// `.cast` / `.lfsr` file is sealed and shows up in the
  /// recordings browser) before adopting the new value. Pass
  /// `null` to stop recording without starting a new file.
  ///
  /// Best-effort close: the previous recorder's `close()` future
  /// is unawaited so the caller does not have to become async
  /// just to flip the recording state.
  void setRecorder(SessionRecorder? next) {
    final previous = recorder;
    recorder = next;
    if (previous != null && !identical(previous, next)) {
      unawaited(previous.close());
    }
  }

  /// Cancel stream subscriptions, clear terminal callbacks, and close the shell.
  ///
  /// Recorder closes after the shell so any final tail bytes
  /// (banner, "logout") still land in the recording before the
  /// file is sealed.
  void close() {
    eventsSub?.cancel();
    _terminal.onOutput = null;
    _terminal.onResize = null;
    // Rust shell drops on the FRB side when the wrapper goes out
    // of scope; explicit close is still useful to release the
    // events subscription early.
    unawaited(transportShell.close());
    final r = recorder;
    if (r != null) {
      // Best-effort — fire and forget so caller does not have to
      // become async to dispose a pane.
      unawaited(r.close());
    }
  }
}

/// Shared logic for connecting an SSH shell to an xterm Terminal.
///
/// Used by both desktop [TerminalPane] and mobile [MobileTerminalView].
class ShellHelper {
  ShellHelper._();

  /// Open an SSH shell and wire it to [terminal].
  ///
  /// Returns a [ShellConnection] on success, or throws on final failure.
  /// [onDone] is called when the shell session closes.
  ///
  /// [recorder] is optional — when supplied every byte the user
  /// sees on `terminal` and every byte the user types is forked
  /// into it before the normal write paths run. The recorder owns
  /// its own file lifecycle; this helper only feeds bytes.
  static Future<ShellConnection> openShell({
    required Connection connection,
    required Terminal terminal,
    VoidCallback? onDone,
    SessionRecorder? recorder,
  }) async {
    final transport = connection.transport;
    if (transport == null || !transport.isConnected) {
      throw StateError('Not connected');
    }

    final shell = await transport.openShell(
      cols: terminal.viewWidth,
      rows: terminal.viewHeight,
    );

    const decoder = Utf8Decoder(allowMalformed: true);

    // `late` capture so every chunk reads the live `shellConn.recorder`
    // field rather than the recorder reference handed in at openShell
    // time. The terminal-toolbar record button swaps recorders mid-
    // stream via `ShellConnection.setRecorder`; with a closure-captured
    // local the new bytes would still feed the old (closed) recorder.
    late final ShellConnection shellConn;
    final eventsSub = shell.events.listen((event) {
      switch (event) {
        case SshShellOutput(:final bytes):
          final decoded = decoder.convert(bytes);
          terminal.write(decoded);
          shellConn.recorder?.recordOutput(bytes);
        case SshShellExtendedOutput(:final bytes):
          final decoded = decoder.convert(bytes);
          terminal.write(decoded);
          shellConn.recorder?.recordOutput(bytes);
        case SshShellEof():
          if (onDone != null) onDone();
        case SshShellExitStatus():
        case SshShellExitSignal():
          if (onDone != null) onDone();
      }
    });

    terminal.onOutput = (data) {
      // utf8.encode already returns Uint8List on dart:convert ≥
      // 2.18; the prior Uint8List.fromList wrap doubled the
      // keystroke buffer for nothing.
      final bytes = utf8.encode(data);
      shell.write(bytes);
      shellConn.recorder?.recordInput(bytes);
    };
    terminal.onResize = (cols, rows, _, _) {
      shell.resize(cols: cols, rows: rows);
    };

    shellConn = ShellConnection(
      transportShell: shell,
      eventsSub: eventsSub,
      terminal: terminal,
      recorder: recorder,
    );
    return shellConn;
  }
}
