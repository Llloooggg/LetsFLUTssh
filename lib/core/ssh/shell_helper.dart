import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' show VoidCallback;

import 'package:dartssh2/dartssh2.dart';
import 'package:xterm/xterm.dart';

import '../../utils/logger.dart';
import '../connection/connection.dart';

/// Result of opening an SSH shell on a terminal.
class ShellConnection {
  final SSHSession shell;
  final StreamSubscription stdoutSub;
  final StreamSubscription stderrSub;

  ShellConnection({
    required this.shell,
    required this.stdoutSub,
    required this.stderrSub,
  });

  /// Cancel stream subscriptions and close the shell.
  void close() {
    stdoutSub.cancel();
    stderrSub.cancel();
    shell.close();
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
  static Future<ShellConnection> openShell({
    required Connection connection,
    required Terminal terminal,
    int maxAttempts = 5,
    VoidCallback? onDone,
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

        final stdoutSub = shell.stdout.listen((data) {
          terminal.write(String.fromCharCodes(data));
        });

        final stderrSub = shell.stderr.listen((data) {
          terminal.write(String.fromCharCodes(data));
        });

        try {
          terminal.onOutput = (data) {
            shell.write(Uint8List.fromList(data.codeUnits));
          };

          terminal.onResize = (width, height, pixelWidth, pixelHeight) {
            shell.resizeTerminal(width, height);
          };

          if (onDone != null) {
            shell.done.then((_) => onDone());
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
        );
      } catch (e) {
        if (attempt == maxAttempts - 1) rethrow;
        AppLogger.instance.log('Open attempt ${attempt + 1}/$maxAttempts failed: $e', name: 'Shell');
      }
    }

    // Unreachable, but satisfies the type system
    throw StateError('Failed to open shell');
  }
}
