import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

import '../../core/connection/connection.dart';
import '../../core/ssh/ssh_client.dart';

/// Terminal tab widget: xterm TerminalView connected to SSH shell.
class TerminalTab extends StatefulWidget {
  final Connection connection;
  final VoidCallback? onDisconnected;

  const TerminalTab({
    super.key,
    required this.connection,
    this.onDisconnected,
  });

  @override
  State<TerminalTab> createState() => _TerminalTabState();
}

class _TerminalTabState extends State<TerminalTab> {
  late final Terminal _terminal;
  late final TerminalController _terminalController;
  SSHSession? _shell;
  bool _connected = false;
  String? _error;
  StreamSubscription? _stdoutSub;
  StreamSubscription? _stderrSub;

  @override
  void initState() {
    super.initState();
    _terminal = Terminal(maxLines: 5000);
    _terminalController = TerminalController();
    _connectAndOpenShell();
  }

  Future<void> _connectAndOpenShell() async {
    final sshConn = widget.connection.sshConnection;
    if (sshConn == null || !sshConn.isConnected) {
      setState(() => _error = 'Not connected');
      return;
    }

    try {
      _shell = await sshConn.openShell(
        _terminal.viewWidth,
        _terminal.viewHeight,
      );

      // SSH stdout → terminal
      _stdoutSub = _shell!.stdout.listen((data) {
        _terminal.write(String.fromCharCodes(data));
      });

      // SSH stderr → terminal
      _stderrSub = _shell!.stderr.listen((data) {
        _terminal.write(String.fromCharCodes(data));
      });

      // Terminal output → SSH stdin
      _terminal.onOutput = (data) {
        _shell?.write(Uint8List.fromList(data.codeUnits));
      };

      // Terminal resize → SSH resize
      _terminal.onResize = (width, height, pixelWidth, pixelHeight) {
        sshConn.resizeTerminal(width, height);
      };

      // Shell done → disconnected
      _shell!.done.then((_) {
        if (mounted) {
          setState(() {
            _connected = false;
            _error = 'Session closed';
          });
          widget.onDisconnected?.call();
        }
      });

      setState(() => _connected = true);
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  Future<void> _reconnect() async {
    setState(() {
      _error = null;
      _connected = false;
    });
    _cleanup();

    final sshConn = widget.connection.sshConnection;
    if (sshConn == null || !sshConn.isConnected) {
      try {
        final newConn = SSHConnection(
          config: widget.connection.sshConfig,
          knownHosts: widget.connection.sshConnection!.knownHosts,
        );
        await newConn.connect();
        widget.connection.sshConnection = newConn;
        widget.connection.state = SSHConnectionState.connected;
      } catch (e) {
        setState(() => _error = 'Reconnect failed: $e');
        return;
      }
    }

    await _connectAndOpenShell();
  }

  void _cleanup() {
    _stdoutSub?.cancel();
    _stderrSub?.cancel();
    _shell?.close();
    _shell = null;
  }

  @override
  void dispose() {
    _cleanup();
    _terminalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return _buildErrorState();
    }
    if (!_connected) {
      return const Center(child: CircularProgressIndicator());
    }
    return TerminalView(
      _terminal,
      controller: _terminalController,
      autofocus: true,
      backgroundOpacity: 1.0,
      padding: const EdgeInsets.all(4),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
          const SizedBox(height: 16),
          Text(
            _error!,
            style: TextStyle(color: Colors.red[300]),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ElevatedButton.icon(
                onPressed: _reconnect,
                icon: const Icon(Icons.refresh),
                label: const Text('Reconnect'),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: widget.onDisconnected,
                icon: const Icon(Icons.close),
                label: const Text('Close'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
