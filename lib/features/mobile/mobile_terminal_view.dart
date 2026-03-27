import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

import '../../core/connection/connection.dart';
import '../../core/ssh/shell_helper.dart';
import '../../theme/app_theme.dart';
import '../../utils/logger.dart';
import '../../utils/terminal_clipboard.dart';
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
  ShellConnection? _shellConn;
  bool _connected = false;
  String? _error;
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
    final conn = widget.connection;

    // Wait for connection if still connecting (connectAsync returns immediately)
    await conn.waitUntilReady();

    if (!conn.isConnected) {
      if (mounted) {
        setState(() => _error = conn.connectionError ?? 'Connection failed');
      }
      return;
    }

    try {
      _shellConn = await ShellHelper.openShell(
        connection: conn,
        terminal: _terminal,
        onDone: () {
          if (mounted) {
            setState(() {
              _connected = false;
              _error = 'Session closed';
            });
          }
        },
      );
      if (mounted) setState(() => _connected = true);
    } catch (e) {
      AppLogger.instance.log('Shell open failed: $e', name: 'MobileTerminal', error: e);
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  void dispose() {
    _shellConn?.close();
    _terminalController.dispose();
    super.dispose();
  }

  void _onKeyboardInput(String data) {
    _shellConn?.shell.write(Uint8List.fromList(data.codeUnits));
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
      popUpAnimationStyle: AnimationStyle.noAnimation,
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
          TerminalClipboard.copy(_terminal, _terminalController);
        case 'paste':
          TerminalClipboard.paste(_terminal);
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
