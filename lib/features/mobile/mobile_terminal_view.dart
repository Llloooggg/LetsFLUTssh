import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';

import '../../core/connection/connection.dart';
import '../../core/ssh/shell_helper.dart';
import '../../providers/config_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/logger.dart';
import '../../utils/terminal_clipboard.dart';
import '../../widgets/context_menu.dart';
import 'ssh_keyboard_bar.dart';

/// Full-screen mobile terminal with SSH keyboard bar.
///
/// No tiling/splitting — single pane, full screen.
/// Long press → context menu (copy/paste).
/// Pinch to zoom (font size).
class MobileTerminalView extends ConsumerStatefulWidget {
  final Connection connection;

  const MobileTerminalView({
    super.key,
    required this.connection,
  });

  @override
  ConsumerState<MobileTerminalView> createState() => _MobileTerminalViewState();
}

class _MobileTerminalViewState extends ConsumerState<MobileTerminalView> {
  late final Terminal _terminal;
  late final TerminalController _terminalController;
  final _keyboardKey = GlobalKey<SshKeyboardBarState>();
  ShellConnection? _shellConn;
  bool _connected = false;
  String? _error;
  double _fontSize = 14.0;
  double? _baseScaleFontSize;

  @override
  void initState() {
    super.initState();
    final config = ref.read(configProvider);
    _terminal = Terminal(maxLines: config.scrollback);
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

      // Override terminal.onOutput to apply keyboard bar modifiers
      // (Ctrl/Alt) to system keyboard input before sending to shell.
      _terminal.onOutput = (data) {
        final transformed = _keyboardKey.currentState?.applyModifiers(data) ?? data;
        _shellConn?.shell.write(Uint8List.fromList(transformed.codeUnits));
      };

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
    // React to font size changes from settings slider
    final configFontSize = ref.watch(configProvider.select((c) => c.fontSize));
    if (_baseScaleFontSize == null) {
      // Update only when not pinch-zooming
      _fontSize = configFontSize;
    }

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
            onScaleEnd: (_) {
              _baseScaleFontSize = null;
              // Persist pinch-zoomed font size to config
              ref.read(configProvider.notifier).update(
                (c) => c.copyWith(
                  terminal: c.terminal.copyWith(fontSize: _fontSize),
                ),
              );
            },
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
        SshKeyboardBar(key: _keyboardKey, onInput: _onKeyboardInput),
      ],
    );
  }

  void _showContextMenu(BuildContext context, Offset position) {
    final hasSelection = _terminalController.selection != null;
    showAppContextMenu(
      context: context,
      position: position,
      items: [
        if (hasSelection)
          ContextMenuItem(
            label: 'Copy',
            icon: Icons.copy,
            onTap: () => TerminalClipboard.copy(_terminal, _terminalController),
          ),
        ContextMenuItem(
          label: 'Paste',
          icon: Icons.paste,
          onTap: () => TerminalClipboard.paste(_terminal),
        ),
      ],
    );
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
