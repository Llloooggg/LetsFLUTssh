import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show VoidCallback;

import 'package:dartssh2/dartssh2.dart';
import 'package:xterm/xterm.dart';

import '../../utils/logger.dart';
import '../connection/connection.dart';
import '../session/session_recorder.dart';

/// Result of opening an SSH shell on a terminal.
class ShellConnection {
  final SSHSession shell;
  final StreamSubscription stdoutSub;
  final StreamSubscription stderrSub;
  final Terminal _terminal;
  final SessionRecorder? recorder;

  ShellConnection({
    required this.shell,
    required this.stdoutSub,
    required this.stderrSub,
    required Terminal terminal,
    this.recorder,
  }) : _terminal = terminal;

  /// Cancel stream subscriptions, clear terminal callbacks, and close the shell.
  ///
  /// Recorder closes after the shell so any final tail bytes
  /// (banner, "logout") still land in the recording before the
  /// file is sealed.
  void close() {
    stdoutSub.cancel();
    stderrSub.cancel();
    _terminal.onOutput = null;
    _terminal.onResize = null;
    shell.close();
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

  /// Base delay in milliseconds between shell open retry attempts.
  static const _retryDelayMs = 500;

  /// Open an SSH shell and wire it to [terminal].
  ///
  /// Retries up to [maxAttempts] times with incremental delay (SSH servers
  /// may reject rapid channel opens, e.g. during split).
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
    int maxAttempts = 5,
    VoidCallback? onDone,
    SessionRecorder? recorder,
  }) async {
    final sshConn = connection.sshConnection;
    if (sshConn == null || !sshConn.isConnected) {
      throw StateError('Not connected');
    }

    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        if (attempt > 0) {
          await Future.delayed(Duration(milliseconds: _retryDelayMs * attempt));
        }

        final shell = await sshConn.openShell(
          terminal.viewWidth,
          terminal.viewHeight,
        );

        const decoder = Utf8Decoder(allowMalformed: true);

        final stdoutSub = shell.stdout
            .cast<List<int>>()
            .transform(decoder)
            .listen((data) {
              terminal.write(data);
              recorder?.recordOutput(utf8.encode(data));
            });

        final stderrSub = shell.stderr
            .cast<List<int>>()
            .transform(decoder)
            .listen((data) {
              terminal.write(data);
              recorder?.recordOutput(utf8.encode(data));
            });

        try {
          terminal.onOutput = (data) {
            shell.write(Uint8List.fromList(utf8.encode(data)));
            recorder?.recordInput(utf8.encode(data));
          };

          terminal.onResize = (width, height, pixelWidth, pixelHeight) {
            shell.resizeTerminal(width, height);
          };

          if (onDone != null) {
            shell.done.then((_) => onDone(), onError: (_) => onDone());
          }
        } catch (e) {
          stdoutSub.cancel();
          stderrSub.cancel();
          shell.close();
          rethrow;
        }

        return ShellConnection(
          shell: shell,
          stdoutSub: stdoutSub,
          stderrSub: stderrSub,
          terminal: terminal,
          recorder: recorder,
        );
      } catch (e) {
        if (attempt == maxAttempts - 1) rethrow;
        AppLogger.instance.log(
          'Open attempt ${attempt + 1}/$maxAttempts failed: $e',
          name: 'Shell',
        );
      }
    }

    // Unreachable, but satisfies the type system
    throw StateError('Failed to open shell');
  }
}
