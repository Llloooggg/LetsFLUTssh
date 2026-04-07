import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';

import '../../core/connection/connection.dart';
import '../../core/ssh/shell_helper.dart';
import '../../l10n/app_localizations.dart';
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

  const MobileTerminalView({super.key, required this.connection});

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
  bool _selectMode = false;
  int _pointerCount = 0;

  @override
  void initState() {
    super.initState();
    final config = ref.read(configProvider);
    _terminal = Terminal(maxLines: config.scrollback);
    _terminalController = TerminalController();
    _terminalController.addListener(_onSelectionChanged);
    // Delay connection until after the first frame so TerminalView can
    // set the correct terminal dimensions. Without this, the shell opens
    // with the default 80x24 and the server sends output for that size;
    // when TerminalView later resizes, the buffer rearranges and causes
    // duplicated/garbled first lines on mobile (where the actual viewport
    // differs significantly from 80x24).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _connectAndOpenShell();
    });
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
        final l10n = S.of(context);
        setState(
          () => _error = conn.connectionError != null
              ? localizeError(l10n, conn.connectionError!)
              : l10n.errConnectionFailed,
        );
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
              _error = S.of(context).errSessionClosed;
            });
          }
        },
      );

      // Override terminal.onOutput to apply keyboard bar modifiers
      // (Ctrl/Alt) to system keyboard input before sending to shell.
      _terminal.onOutput = (data) {
        final transformed =
            _keyboardKey.currentState?.applyModifiers(data) ?? data;
        _shellConn?.shell.write(Uint8List.fromList(transformed.codeUnits));
      };

      if (mounted) setState(() => _connected = true);
    } catch (e) {
      AppLogger.instance.log(
        'Shell open failed: $e',
        name: 'MobileTerminal',
        error: e,
      );
      if (mounted) {
        setState(() => _error = localizeError(S.of(context), e));
      }
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
    _shellConn?.shell.write(Uint8List.fromList(utf8.encode(data)));
  }

  void _copySelection() {
    TerminalClipboard.copy(_terminal, _terminalController);
    _keyboardKey.currentState?.exitSelectMode();
  }

  void _paste() {
    TerminalClipboard.paste(_terminal);
  }

  void _onPointerUp() {
    _pointerCount = (_pointerCount - 1).clamp(0, 99);
    if (_pointerCount < 2 && _baseScaleFontSize != null) {
      setState(() {});
    }
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

    // Always render TerminalView so it can lay out and set the correct
    // terminal dimensions before the shell opens (avoids buffer artifacts).
    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              _buildPinchZoomArea(),
              if (!_connected) const Center(child: CircularProgressIndicator()),
              if (_hasSelection)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _buildSelectionToolbar(),
                ),
            ],
          ),
        ),
        SshKeyboardBar(
          key: _keyboardKey,
          onInput: _onKeyboardInput,
          onPaste: _paste,
          onSelectModeChanged: (active) {
            setState(() => _selectMode = active);
            _terminalController.setSuspendPointerInput(active);
            if (!active) _terminalController.clearSelection();
          },
        ),
      ],
    );
  }

  Widget _buildPinchZoomArea() {
    return Listener(
      onPointerDown: (_) => _pointerCount++,
      onPointerUp: (_) => _onPointerUp(),
      onPointerCancel: (_) => _onPointerUp(),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        // Disable scale gestures during select mode so xterm's
        // drag-select gesture recognizer wins the arena.
        onScaleStart: _selectMode ? null : _onPinchStart,
        onScaleUpdate: _selectMode ? null : _onPinchUpdate,
        onScaleEnd: _selectMode ? null : _onPinchEnd,
        child: _buildTerminalStack(),
      ),
    );
  }

  void _onPinchStart(ScaleStartDetails details) {
    if (details.pointerCount >= 2) {
      _baseScaleFontSize = _fontSize;
    }
  }

  void _onPinchUpdate(ScaleUpdateDetails details) {
    if (_baseScaleFontSize == null) return;
    setState(() {
      _fontSize = (_baseScaleFontSize! * details.scale).clamp(8.0, 24.0);
    });
  }

  void _onPinchEnd(ScaleEndDetails _) {
    if (_baseScaleFontSize == null) return;
    _baseScaleFontSize = null;
    ref
        .read(configProvider.notifier)
        .update(
          (c) => c.copyWith(terminal: c.terminal.copyWith(fontSize: _fontSize)),
        );
  }

  Widget _buildTerminalStack() {
    return Stack(
      children: [
        IgnorePointer(
          ignoring: _pointerCount >= 2,
          child: TerminalView(
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
        ),
        Positioned.fill(
          child: CursorTextOverlay(terminal: _terminal, fontSize: _fontSize),
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
            label: S.of(context).copy,
            onTap: _copySelection,
          ),
          const SizedBox(width: 16),
          _ToolbarButton(
            icon: Icons.paste,
            label: S.of(context).paste,
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
          const Icon(
            Icons.error_outline,
            size: 48,
            color: AppTheme.disconnected,
          ),
          const SizedBox(height: 16),
          Text(
            _error!,
            style: const TextStyle(color: AppTheme.disconnected),
            textAlign: TextAlign.center,
          ),
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
