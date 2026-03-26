import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';

import '../../core/connection/connection.dart';
import '../../core/ssh/shell_helper.dart';
import '../../theme/app_theme.dart';
import '../../utils/logger.dart';
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

class TerminalPane extends StatefulWidget {
  final Connection connection;
  final bool isFocused;
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
    this.onFocused,
    this.onSplitVertical,
    this.onSplitHorizontal,
    this.onClose,
    this.shellFactory,
  });

  @override
  State<TerminalPane> createState() => TerminalPaneState();
}

class TerminalPaneState extends State<TerminalPane> {
  late final Terminal _terminal;
  late final TerminalController _terminalController;
  ShellConnection? _shellConn;
  bool _connected = false;
  String? _error;

  // Search visibility — ValueNotifier so toggling doesn't rebuild TerminalView
  final _showSearch = ValueNotifier<bool>(false);

  @override
  void initState() {
    super.initState();
    _terminal = Terminal(maxLines: 5000);
    _terminalController = TerminalController();
    _connectAndOpenShell();
  }

  Future<void> _connectAndOpenShell() async {
    final conn = widget.connection;
    final config = conn.sshConfig;

    // Show connection info in terminal
    _terminal.write('Connecting to ${config.user}@${config.host}:${config.effectivePort}...\r\n');

    // Wait for connection if still connecting
    if (conn.isConnecting) {
      await _waitForConnection(conn);
    }

    // Check connection result
    if (!conn.isConnected) {
      final error = conn.connectionError ?? 'Connection failed';
      _terminal.write('\r\n\x1B[31m$error\x1B[0m\r\n'); // red text
      _terminal.write('\r\nPress any key to close this tab.\r\n');
      if (mounted) setState(() => _error = error);
      return;
    }

    _terminal.write('Connected.\r\n\r\n');

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
      _terminal.write('\r\n\x1B[31mShell error: $e\x1B[0m\r\n');
      if (mounted) setState(() => _error = e.toString());
    }
  }

  /// Poll connection state until it's no longer connecting.
  Future<void> _waitForConnection(Connection conn) async {
    while (conn.isConnecting && mounted) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
  }

  @override
  void dispose() {
    _shellConn?.close();
    _terminalController.dispose();
    _showSearch.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    _showSearch.value = !_showSearch.value;
  }

  void _closeSearch() {
    _showSearch.value = false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_error != null) {
      return _buildErrorState();
    }
    if (!_connected) {
      return const Center(child: CircularProgressIndicator());
    }

    final border = widget.isFocused
        ? Border.all(color: theme.colorScheme.primary, width: 1.5)
        : Border.all(color: theme.dividerColor, width: 0.5);

    return GestureDetector(
      onTap: widget.onFocused,
      child: Container(
        decoration: BoxDecoration(border: border),
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.keyF, control: true, shift: true): _toggleSearch,
            const SingleActivator(LogicalKeyboardKey.escape): _closeSearch,
          },
          child: Column(
            children: [
              ValueListenableBuilder<bool>(
                valueListenable: _showSearch,
                builder: (context, show, _) {
                  if (!show) return const SizedBox.shrink();
                  return _TerminalSearchBar(
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
        if (hasSplit) ...[
          const PopupMenuDivider(),
          const PopupMenuItem(value: 'split-v', child: ListTile(
            dense: true, leading: Icon(Icons.vertical_split, size: 18),
            title: Text('Split Right'), contentPadding: EdgeInsets.zero, visualDensity: VisualDensity.compact,
          )),
          const PopupMenuItem(value: 'split-h', child: ListTile(
            dense: true, leading: Icon(Icons.horizontal_split, size: 18),
            title: Text('Split Down'), contentPadding: EdgeInsets.zero, visualDensity: VisualDensity.compact,
          )),
          if (widget.onClose != null)
            const PopupMenuItem(value: 'close', child: ListTile(
              dense: true, leading: Icon(Icons.close, size: 18),
              title: Text('Close Pane'), contentPadding: EdgeInsets.zero, visualDensity: VisualDensity.compact,
            )),
        ],
      ],
    ).then((action) {
      switch (action) {
        case 'copy': _copySelection();
        case 'paste': _pasteClipboard();
        case 'split-v': widget.onSplitVertical?.call();
        case 'split-h': widget.onSplitHorizontal?.call();
        case 'close': widget.onClose?.call();
        default: break;
      }
    });
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

  void _copySelection() {
    final selection = _terminalController.selection;
    if (selection == null) return;
    final text = _terminal.buffer.getText(selection);
    Clipboard.setData(ClipboardData(text: text));
    _terminalController.clearSelection();
  }

  Future<void> _pasteClipboard() async {
    final data = await Clipboard.getData('text/plain');
    if (data?.text != null && data!.text!.isNotEmpty) {
      _terminal.textInput(data.text!);
    }
  }

  Widget _buildErrorState() {
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

/// Self-contained search bar widget — manages its own state so that
/// search interactions (typing, next/prev) don't rebuild the TerminalView.
class _TerminalSearchBar extends StatefulWidget {
  final Terminal terminal;
  final TerminalController terminalController;
  final VoidCallback onClose;

  const _TerminalSearchBar({
    required this.terminal,
    required this.terminalController,
    required this.onClose,
  });

  @override
  State<_TerminalSearchBar> createState() => _TerminalSearchBarState();
}

class _TerminalSearchBarState extends State<_TerminalSearchBar> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  List<TerminalHighlight> _searchHighlights = [];
  int _currentMatchIndex = -1;
  int _totalMatches = 0;

  @override
  void initState() {
    super.initState();
    _searchFocusNode.requestFocus();
  }

  @override
  void dispose() {
    _clearHighlights();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _performSearch() {
    _clearHighlights();
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              autofocus: true,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                border: const OutlineInputBorder(),
                hintText: 'Search...',
                suffixText: _totalMatches > 0
                    ? '${_currentMatchIndex + 1}/$_totalMatches'
                    : null,
                suffixStyle: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
              ),
              onChanged: (_) => _performSearch(),
              onSubmitted: (_) => _nextMatch(),
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 28,
            height: 28,
            child: IconButton(
              onPressed: _totalMatches > 0 ? _prevMatch : null,
              icon: const Icon(Icons.keyboard_arrow_up, size: 18),
              tooltip: 'Previous',
              padding: EdgeInsets.zero,
            ),
          ),
          SizedBox(
            width: 28,
            height: 28,
            child: IconButton(
              onPressed: _totalMatches > 0 ? _nextMatch : null,
              icon: const Icon(Icons.keyboard_arrow_down, size: 18),
              tooltip: 'Next',
              padding: EdgeInsets.zero,
            ),
          ),
          SizedBox(
            width: 28,
            height: 28,
            child: IconButton(
              onPressed: _close,
              icon: const Icon(Icons.close, size: 18),
              tooltip: 'Close (Esc)',
              padding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
  }
}
