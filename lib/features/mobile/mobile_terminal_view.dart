import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';

import '../../core/connection/connection.dart';
import '../../core/ssh/shell_helper.dart';
import '../../providers/config_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../utils/logger.dart';
import '../../utils/terminal_clipboard.dart';
import '../terminal/cursor_overlay.dart';
import 'ssh_keyboard_bar.dart';

/// Full-screen mobile terminal with SSH keyboard bar.
///
/// No tiling/splitting — single pane, full screen.
/// Long press selects a word (xterm built-in) → floating toolbar appears.
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
  bool _hasSelection = false;

  @override
  void initState() {
    super.initState();
    final config = ref.read(configProvider);
    _terminal = Terminal(maxLines: config.scrollback);
    _terminalController = TerminalController();
    _terminalController.addListener(_onSelectionChanged);
    _connectAndOpenShell();
  }

  void _onSelectionChanged() {
    final hasSelection = _terminalController.selection != null;
    if (hasSelection != _hasSelection) {
      setState(() => _hasSelection = hasSelection);
    }
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
      if (mounted) setState(() => _error = sanitizeError(e));
    }
  }

  @override
  void dispose() {
    _terminalController.removeListener(_onSelectionChanged);
    _shellConn?.close();
    _terminalController.dispose();
    super.dispose();
  }

  void _onKeyboardInput(String data) {
    _shellConn?.shell.write(Uint8List.fromList(data.codeUnits));
  }

  void _copySelection() {
    TerminalClipboard.copy(_terminal, _terminalController);
    _keyboardKey.currentState?.exitSelectMode();
  }

  void _paste() {
    TerminalClipboard.paste(_terminal);
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
            behavior: HitTestBehavior.translucent,
            onScaleStart: (details) {
              if (details.pointerCount >= 2) {
                _baseScaleFontSize = _fontSize;
              }
            },
            onScaleUpdate: (details) {
              if (_baseScaleFontSize == null || details.pointerCount < 2) return;
              setState(() {
                _fontSize = (_baseScaleFontSize! * details.scale).clamp(8.0, 24.0);
              });
            },
            onScaleEnd: (_) {
              if (_baseScaleFontSize == null) return;
              _baseScaleFontSize = null;
              // Persist pinch-zoomed font size to config
              ref.read(configProvider.notifier).update(
                (c) => c.copyWith(
                  terminal: c.terminal.copyWith(fontSize: _fontSize),
                ),
              );
            },
            child: Stack(
              children: [
                TerminalView(
                  _terminal,
                  controller: _terminalController,
                  autofocus: true,
                  backgroundOpacity: 1.0,
                  padding: const EdgeInsets.all(4),
                  theme: TerminalTheme(
                    cursor: AppTheme.termCursor,
                    selection: AppTheme.termSelection,
                    foreground: AppTheme.fg,
                    background: AppTheme.bg2,
                    black: AppTheme.termBlack,
                    red: AppTheme.termRed,
                    green: AppTheme.termGreen,
                    yellow: AppTheme.termYellow,
                    blue: AppTheme.termBlue,
                    magenta: AppTheme.termMagenta,
                    cyan: AppTheme.termCyan,
                    white: AppTheme.termWhite,
                    brightBlack: AppTheme.termBrightBlack,
                    brightRed: AppTheme.termBrightRed,
                    brightGreen: AppTheme.termBrightGreen,
                    brightYellow: AppTheme.termBrightYellow,
                    brightBlue: AppTheme.termBrightBlue,
                    brightMagenta: AppTheme.termBrightMagenta,
                    brightCyan: AppTheme.termBrightCyan,
                    brightWhite: AppTheme.termBrightWhite,
                    searchHitBackground: AppTheme.accent.withValues(alpha: 0.3),
                    searchHitBackgroundCurrent: AppTheme.accent,
                    searchHitForeground: AppTheme.searchHitFg,
                  ),
                  textStyle: TerminalStyle(
                    fontSize: _fontSize,
                    fontFamily: 'JetBrains Mono',
                  ),
                ),
                Positioned.fill(
                  child: CursorTextOverlay(
                    terminal: _terminal,
                    fontSize: _fontSize,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_hasSelection) _buildSelectionToolbar(),
        SshKeyboardBar(
          key: _keyboardKey,
          onInput: _onKeyboardInput,
          onPaste: _paste,
          onSelectModeChanged: (active) {
            _terminalController.setSuspendPointerInput(active);
            if (!active) _terminalController.clearSelection();
          },
        ),
      ],
    );
  }

  Widget _buildSelectionToolbar() {
    return Container(
      color: AppTheme.bg3,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _ToolbarButton(
            icon: Icons.copy,
            label: 'Copy',
            onTap: _copySelection,
          ),
          const SizedBox(width: 16),
          _ToolbarButton(
            icon: Icons.paste,
            label: 'Paste',
            onTap: _paste,
          ),
        ],
      ),
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

class _ToolbarButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ToolbarButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      borderRadius: AppTheme.radiusLg,
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        borderRadius: AppTheme.radiusLg,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: theme.colorScheme.onSurface),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: AppFonts.md,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
