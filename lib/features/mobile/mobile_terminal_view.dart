import 'dart:async';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';

import '../../core/connection/connection.dart';
import '../../theme/app_theme.dart';
import 'ssh_keyboard_bar.dart';

/// Full-screen mobile terminal with SSH keyboard bar.
///
/// No tiling/splitting — single pane, full screen.
/// Long press → context menu (copy/paste).
/// Pinch to zoom (font size).
class MobileTerminalView extends StatefulWidget {
  final Connection connection;

  const MobileTerminalView({
    super.key,
    required this.connection,
  });

  @override
  State<MobileTerminalView> createState() => _MobileTerminalViewState();
}

class _MobileTerminalViewState extends State<MobileTerminalView> {
  late final Terminal _terminal;
  late final TerminalController _terminalController;
  SSHSession? _shell;
  bool _connected = false;
  String? _error;
  StreamSubscription? _stdoutSub;
  StreamSubscription? _stderrSub;
  double _fontSize = 12.0;
  double? _baseScaleFontSize;

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

    const maxAttempts = 3;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        if (attempt > 0) {
          await Future.delayed(Duration(milliseconds: 300 * attempt));
          if (!mounted) return;
        }

        _shell = await sshConn.openShell(
          _terminal.viewWidth,
          _terminal.viewHeight,
        );

        _stdoutSub = _shell!.stdout.listen((data) {
          _terminal.write(String.fromCharCodes(data));
        });

        _stderrSub = _shell!.stderr.listen((data) {
          _terminal.write(String.fromCharCodes(data));
        });

        _terminal.onOutput = (data) {
          _shell?.write(Uint8List.fromList(data.codeUnits));
        };

        _terminal.onResize = (width, height, pixelWidth, pixelHeight) {
          _shell?.resizeTerminal(width, height);
        };

        _shell!.done.then((_) {
          if (mounted) {
            setState(() {
              _connected = false;
              _error = 'Session closed';
            });
          }
        });

        setState(() => _connected = true);
        return;
      } catch (e) {
        if (attempt == maxAttempts - 1) {
          if (mounted) setState(() => _error = e.toString());
        }
      }
    }
  }

  @override
  void dispose() {
    _stdoutSub?.cancel();
    _stderrSub?.cancel();
    _shell?.close();
    _terminalController.dispose();
    super.dispose();
  }

  void _onKeyboardInput(String data) {
    _shell?.write(Uint8List.fromList(data.codeUnits));
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return _buildError();
    if (!_connected) return const Center(child: CircularProgressIndicator());

    return Column(
      children: [
        Expanded(
          child: GestureDetector(
            onScaleStart: (_) => _baseScaleFontSize = _fontSize,
            onScaleUpdate: (details) {
              if (_baseScaleFontSize == null) return;
              setState(() {
                _fontSize = (_baseScaleFontSize! * details.scale).clamp(8.0, 24.0);
              });
            },
            onScaleEnd: (_) => _baseScaleFontSize = null,
            onLongPressStart: (details) => _showContextMenu(context, details.globalPosition),
            child: TerminalView(
              _terminal,
              controller: _terminalController,
              autofocus: true,
              backgroundOpacity: 1.0,
              padding: const EdgeInsets.all(4),
              textStyle: TerminalStyle(fontSize: _fontSize),
            ),
          ),
        ),
        SshKeyboardBar(onInput: _onKeyboardInput),
      ],
    );
  }

  void _showContextMenu(BuildContext context, Offset position) {
    final hasSelection = _terminalController.selection != null;
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx, position.dy),
      items: [
        if (hasSelection)
          const PopupMenuItem(value: 'copy', child: ListTile(
            dense: true, leading: Icon(Icons.copy, size: 18),
            title: Text('Copy'), contentPadding: EdgeInsets.zero, visualDensity: VisualDensity.compact,
          )),
        const PopupMenuItem(value: 'paste', child: ListTile(
          dense: true, leading: Icon(Icons.paste, size: 18),
          title: Text('Paste'), contentPadding: EdgeInsets.zero, visualDensity: VisualDensity.compact,
        )),
      ],
    ).then((action) {
      switch (action) {
        case 'copy':
          final sel = _terminalController.selection;
          if (sel != null) {
            Clipboard.setData(ClipboardData(text: _terminal.buffer.getText(sel)));
            _terminalController.clearSelection();
          }
        case 'paste':
          Clipboard.getData('text/plain').then((data) {
            if (data?.text != null && data!.text!.isNotEmpty) {
              _terminal.textInput(data.text!);
            }
          });
        default:
          break;
      }
    });
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48, color: AppTheme.disconnected),
          const SizedBox(height: 16),
          Text(_error!, style: const TextStyle(color: AppTheme.disconnected), textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
