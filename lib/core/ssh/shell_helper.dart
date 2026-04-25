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
  final SessionRecorder? recorder;

  ShellConnection({
    required this.transportShell,
    this.eventsSub,
    required Terminal terminal,
    this.recorder,
  }) : _terminal = terminal;

  /// Send stdin bytes to the remote shell.
  void write(Uint8List bytes) => transportShell.write(bytes);

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

    final eventsSub = shell.events.listen((event) {
      switch (event) {
        case SshShellOutput(:final bytes):
          final decoded = decoder.convert(bytes);
          terminal.write(decoded);
          recorder?.recordOutput(bytes);
        case SshShellExtendedOutput(:final bytes):
          final decoded = decoder.convert(bytes);
          terminal.write(decoded);
          recorder?.recordOutput(bytes);
        case SshShellEof():
          if (onDone != null) onDone();
        case SshShellExitStatus():
        case SshShellExitSignal():
          if (onDone != null) onDone();
      }
    });

    terminal.onOutput = (data) {
      final bytes = Uint8List.fromList(utf8.encode(data));
      shell.write(bytes);
      recorder?.recordInput(bytes);
    };
    terminal.onResize = (cols, rows, _, _) {
      shell.resize(cols: cols, rows: rows);
    };

    return ShellConnection(
      transportShell: shell,
      eventsSub: eventsSub,
      terminal: terminal,
      recorder: recorder,
    );
  }
}
