import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';

import '../../core/connection/connection.dart';
import '../../core/ssh/shell_helper.dart';
import '../../providers/config_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_icon_button.dart';
import '../../utils/format.dart';
import '../../utils/logger.dart';
import '../../utils/terminal_clipboard.dart';
import '../../widgets/context_menu.dart';
import '../../widgets/error_state.dart';
import '../../utils/platform.dart' as plat;

/// A single terminal pane — xterm TerminalView connected to one SSH shell.
///
/// Multiple panes can share the same [Connection] (each opens its own shell).
/// Factory for opening SSH shell — injectable for testing.
typedef ShellOpenFactory = Future<ShellConnection> Function({
  required Connection connection,
  required Terminal terminal,
  VoidCallback? onDone,
});

class TerminalPane extends ConsumerStatefulWidget {
  final Connection connection;
  final bool isFocused;

  /// Whether there are multiple panes in the tiling layout.
  /// Focus border is only shown when this is true.
  final bool hasMultiplePanes;
  final VoidCallback? onFocused;
  final VoidCallback? onSplitVertical;
  final VoidCallback? onSplitHorizontal;
  final VoidCallback? onClose;

  /// Optional factory for testing — bypasses real SSH shell.
  final ShellOpenFactory? shellFactory;

  const TerminalPane({
    super.key,
    required this.connection,
    this.isFocused = false,
    this.hasMultiplePanes = false,
    this.onFocused,
    this.onSplitVertical,
    this.onSplitHorizontal,
    this.onClose,
    this.shellFactory,
  });

  @override
  ConsumerState<TerminalPane> createState() => TerminalPaneState();
}

class TerminalPaneState extends ConsumerState<TerminalPane> {
  late final Terminal _terminal;
  late final TerminalController _terminalController;
  ShellConnection? _shellConn;
  bool _connected = false;
  String? _error;

  // Search visibility — ValueNotifier so toggling doesn't rebuild TerminalView
  final _showSearch = ValueNotifier<bool>(false);

  /// Exposed for testing — toggle search bar visibility.
  @visibleForTesting
  ValueNotifier<bool> get showSearchNotifier => _showSearch;

  @override
  void initState() {
    super.initState();
    _terminal = Terminal(maxLines: ref.read(configProvider).scrollback);
    _terminalController = TerminalController();
    _connectAndOpenShell();
  }

  Future<void> _connectAndOpenShell() async {
    final conn = widget.connection;

    // Wait for connection if still connecting
    await conn.waitUntilReady();

    // Check connection result
    if (!conn.isConnected) {
      final error = conn.connectionError ?? 'Connection failed';
      _terminal.write('\x1B[31m$error\x1B[0m\r\n');
      if (mounted) setState(() => _error = error);
      return;
    }

    void onDone() {
      if (mounted) {
        setState(() {
          _connected = false;
          _error = 'Session closed';
        });
      }
    }

    try {
      if (widget.shellFactory != null) {
        _shellConn = await widget.shellFactory!(
          connection: conn,
          terminal: _terminal,
          onDone: onDone,
        );
      } else {
        _shellConn = await ShellHelper.openShell(
          connection: conn,
          terminal: _terminal,
          onDone: onDone,
        );
      }
      if (mounted) setState(() => _connected = true);
    } catch (e) {
      AppLogger.instance.log('Shell open failed: $e', name: 'TerminalPane', error: e);
      _terminal.write('\r\n\x1B[31mShell error: ${sanitizeError(e)}\x1B[0m\r\n');
      if (mounted) setState(() => _error = sanitizeError(e));
    }
  }

  @override
  void dispose() {
    _shellConn?.close();
    _terminalController.dispose();
    _showSearch.dispose();
    super.dispose();
  }

  /// Toggle search bar visibility. Exposed for testing — in production
  /// triggered by Ctrl+Shift+F shortcut.
  @visibleForTesting
  void toggleSearch() {
    _showSearch.value = !_showSearch.value;
  }

  void _closeSearch() {
    _showSearch.value = false;
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return _buildErrorState();
    }
    if (!_connected) {
      return const Center(child: CircularProgressIndicator());
    }

    final fontSize = ref.watch(configProvider.select((c) => c.fontSize));

    final Border? border;
    if (!widget.hasMultiplePanes) {
      border = null;
    } else {
      border = Border.all(color: AppTheme.bg0, width: 0.5);
    }

    return GestureDetector(
      onTap: widget.onFocused,
      child: Container(
        decoration: border != null ? BoxDecoration(border: border) : null,
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.keyF, control: true, shift: true): toggleSearch,
            const SingleActivator(LogicalKeyboardKey.escape): _closeSearch,
          },
          child: Column(
            children: [
              ValueListenableBuilder<bool>(
                valueListenable: _showSearch,
                builder: (context, show, _) {
                  if (!show) return const SizedBox.shrink();
                  return TerminalSearchBar(
                    terminal: _terminal,
                    terminalController: _terminalController,
                    onClose: _closeSearch,
                  );
                },
              ),
              Expanded(
                child: TerminalView(
                  _terminal,
                  controller: _terminalController,
                  autofocus: widget.isFocused,
                  hardwareKeyboardOnly: plat.isDesktopPlatform,
                  onKeyEvent: _handleTerminalKey,
                  backgroundOpacity: 1.0,
                  padding: const EdgeInsets.all(4),
                  theme: TerminalTheme(
                    cursor: AppTheme.accent,
                    selection: AppTheme.selection,
                    foreground: AppTheme.fg,
                    background: AppTheme.bg2,
                    black: const Color(0xFF1B1D23),
                    red: AppTheme.red,
                    green: AppTheme.green,
                    yellow: AppTheme.yellow,
                    blue: AppTheme.blue,
                    magenta: AppTheme.purple,
                    cyan: AppTheme.cyan,
                    white: AppTheme.fg,
                    brightBlack: AppTheme.fgFaint,
                    brightRed: AppTheme.red,
                    brightGreen: AppTheme.green,
                    brightYellow: AppTheme.yellow,
                    brightBlue: AppTheme.blue,
                    brightMagenta: AppTheme.purple,
                    brightCyan: AppTheme.cyan,
                    brightWhite: AppTheme.fgBright,
                    searchHitBackground: AppTheme.accent.withValues(alpha: 0.3),
                    searchHitBackgroundCurrent: AppTheme.accent,
                    searchHitForeground: Colors.white,
                  ),
                  textStyle: TerminalStyle(
                    fontSize: fontSize,
                    fontFamily: 'JetBrains Mono',
                  ),
                  onSecondaryTapUp: (details, _) => _showContextMenu(context, details.globalPosition),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showContextMenu(BuildContext context, Offset position) {
    final hasSelection = _terminalController.selection != null;
    final hasSplit = widget.onSplitVertical != null;

    showAppContextMenu(
      context: context,
      position: position,
      items: [
        if (hasSelection)
          ContextMenuItem(
            label: 'Copy',
            icon: Icons.copy,
            shortcut: 'Ctrl+C',
            onTap: _copySelection,
          ),
        ContextMenuItem(
          label: 'Paste',
          icon: Icons.paste,
          shortcut: 'Ctrl+V',
          onTap: _pasteClipboard,
        ),
        if (hasSplit) ...[
          const ContextMenuItem.divider(),
          ContextMenuItem(
            label: 'Split Right',
            icon: Icons.vertical_split,
            onTap: () => widget.onSplitVertical?.call(),
          ),
          ContextMenuItem(
            label: 'Split Down',
            icon: Icons.horizontal_split,
            onTap: () => widget.onSplitHorizontal?.call(),
          ),
          if (widget.onClose != null)
            ContextMenuItem(
              label: 'Close Pane',
              icon: Icons.close,
              onTap: () => widget.onClose?.call(),
            ),
        ],
      ],
    );
  }

  /// Handle Ctrl+Shift+C (copy) and Ctrl+Shift+V (paste) before xterm's
  /// built-in shortcut manager — xterm only maps Ctrl+V for paste (no Shift),
  /// and its ShortcutManager uses a protected API that can be fragile.
  KeyEventResult _handleTerminalKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    if (ctrl && shift) {
      if (event.logicalKey == LogicalKeyboardKey.keyC) {
        _copySelection();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.keyV) {
        _pasteClipboard();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  void _copySelection() =>
      TerminalClipboard.copy(_terminal, _terminalController);

  Future<void> _pasteClipboard() =>
      TerminalClipboard.paste(_terminal);

  Widget _buildErrorState() {
    return ErrorState(message: _error!);
  }
}

/// Self-contained search bar widget — manages its own state so that
/// search interactions (typing, next/prev) don't rebuild the TerminalView.
class TerminalSearchBar extends StatefulWidget {
  final Terminal terminal;
  final TerminalController terminalController;
  final VoidCallback onClose;

  const TerminalSearchBar({
    super.key,
    required this.terminal,
    required this.terminalController,
    required this.onClose,
  });

  @override
  State<TerminalSearchBar> createState() => TerminalSearchBarState();
}

class TerminalSearchBarState extends State<TerminalSearchBar> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  List<TerminalHighlight> _searchHighlights = [];
  int _currentMatchIndex = -1;
  int _totalMatches = 0;
  bool _disposed = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _searchFocusNode.requestFocus();
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    _clearHighlights();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _debouncedSearch() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), _performSearch);
  }

  void _performSearch() {
    _clearHighlights();
    if (_disposed) return;
    final query = _searchController.text;
    if (query.isEmpty) {
      setState(() {
        _totalMatches = 0;
        _currentMatchIndex = -1;
      });
      return;
    }

    final queryLower = query.toLowerCase();
    final buffer = widget.terminal.buffer;
    final highlights = <TerminalHighlight>[];

    for (var y = 0; y < buffer.height; y++) {
      final line = buffer.lines[y];
      final lineText = line.toString().toLowerCase();
      var startIndex = 0;
      while (true) {
        final pos = lineText.indexOf(queryLower, startIndex);
        if (pos < 0) break;
        try {
          final p1 = buffer.createAnchor(pos, y);
          final p2 = buffer.createAnchor(pos + query.length, y);
          highlights.add(widget.terminalController.highlight(p1: p1, p2: p2, color: AppTheme.searchHighlight));
        } catch (e) {
          AppLogger.instance.log('Highlight failed at ($pos, $y): $e', name: 'TerminalSearch');
        }
        startIndex = pos + 1;
      }
    }

    setState(() {
      _searchHighlights = highlights;
      _totalMatches = highlights.length;
      _currentMatchIndex = highlights.isNotEmpty ? 0 : -1;
    });
  }

  void _nextMatch() {
    if (_totalMatches == 0) return;
    setState(() => _currentMatchIndex = (_currentMatchIndex + 1) % _totalMatches);
  }

  void _prevMatch() {
    if (_totalMatches == 0) return;
    setState(() => _currentMatchIndex = (_currentMatchIndex - 1 + _totalMatches) % _totalMatches);
  }

  void _clearHighlights() {
    for (final h in _searchHighlights) {
      h.dispose();
    }
    _searchHighlights = [];
  }

  void _close() {
    _clearHighlights();
    widget.onClose();
  }

  @override
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: AppTheme.bg1,
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              autofocus: true,
              style: AppFonts.mono(fontSize: AppFonts.sm, color: AppTheme.fg),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: AppTheme.bg3,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.zero,
                  borderSide: BorderSide(color: AppTheme.borderLight),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.zero,
                  borderSide: BorderSide(color: AppTheme.accent),
                ),
                hintText: 'Search...',
                hintStyle: AppFonts.mono(fontSize: AppFonts.sm, color: AppTheme.fgFaint),
                suffixText: _totalMatches > 0
                    ? '${_currentMatchIndex + 1}/$_totalMatches'
                    : null,
                suffixStyle: AppFonts.mono(fontSize: AppFonts.sm, color: AppTheme.fgDim),
              ),
              onChanged: (_) => _debouncedSearch(),
              onSubmitted: (_) => _nextMatch(),
            ),
          ),
          const SizedBox(width: 4),
          AppIconButton(
            icon: Icons.keyboard_arrow_up,
            onTap: _totalMatches > 0 ? _prevMatch : null,
            tooltip: 'Previous',
            size: 18,
            boxSize: 28,
          ),
          AppIconButton(
            icon: Icons.keyboard_arrow_down,
            onTap: _totalMatches > 0 ? _nextMatch : null,
            tooltip: 'Next',
            size: 18,
            boxSize: 28,
          ),
          AppIconButton(
            icon: Icons.close,
            onTap: _close,
            tooltip: 'Close (Esc)',
            size: 18,
            boxSize: 28,
          ),
        ],
      ),
    );
  }
}
