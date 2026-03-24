import 'dart:async';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  // Search state
  bool _showSearch = false;
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  List<TerminalHighlight> _searchHighlights = [];
  int _currentMatchIndex = -1;
  int _totalMatches = 0;

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
    _clearHighlights();
    _terminalController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
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
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyF, control: true, shift: true): _toggleSearch,
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_showSearch) _closeSearch();
        },
      },
      child: Focus(
        autofocus: true,
        child: Column(
          children: [
            if (_showSearch) _buildSearchBar(context),
            Expanded(
              child: TerminalView(
                _terminal,
                controller: _terminalController,
                autofocus: !_showSearch,
                backgroundOpacity: 1.0,
                padding: const EdgeInsets.all(4),
                onSecondaryTapUp: (details, _) => _showContextMenu(context, details.globalPosition),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context) {
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
                hintText: 'Search terminal...',
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
              tooltip: 'Previous match',
              padding: EdgeInsets.zero,
            ),
          ),
          SizedBox(
            width: 28,
            height: 28,
            child: IconButton(
              onPressed: _totalMatches > 0 ? _nextMatch : null,
              icon: const Icon(Icons.keyboard_arrow_down, size: 18),
              tooltip: 'Next match',
              padding: EdgeInsets.zero,
            ),
          ),
          SizedBox(
            width: 28,
            height: 28,
            child: IconButton(
              onPressed: _closeSearch,
              icon: const Icon(Icons.close, size: 18),
              tooltip: 'Close (Esc)',
              padding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
  }

  void _toggleSearch() {
    setState(() {
      _showSearch = !_showSearch;
      if (_showSearch) {
        _searchFocusNode.requestFocus();
      } else {
        _closeSearch();
      }
    });
  }

  void _closeSearch() {
    _clearHighlights();
    setState(() {
      _showSearch = false;
      _searchController.clear();
      _totalMatches = 0;
      _currentMatchIndex = -1;
    });
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
    final buffer = _terminal.buffer;
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
          highlights.add(_terminalController.highlight(
            p1: p1,
            p2: p2,
            color: const Color(0xFFFFFF2B),
          ));
        } catch (_) {
          // Anchor creation can fail if position is out of bounds
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
    setState(() {
      _currentMatchIndex = (_currentMatchIndex + 1) % _totalMatches;
    });
  }

  void _prevMatch() {
    if (_totalMatches == 0) return;
    setState(() {
      _currentMatchIndex = (_currentMatchIndex - 1 + _totalMatches) % _totalMatches;
    });
  }

  void _clearHighlights() {
    for (final h in _searchHighlights) {
      h.dispose();
    }
    _searchHighlights = [];
  }

  void _showContextMenu(BuildContext context, Offset position) {
    final hasSelection = _terminalController.selection != null;

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx, position.dy),
      items: [
        if (hasSelection)
          const PopupMenuItem(value: 'copy', child: ListTile(
            dense: true,
            leading: Icon(Icons.copy, size: 18),
            title: Text('Copy'),
            contentPadding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
          )),
        const PopupMenuItem(value: 'paste', child: ListTile(
          dense: true,
          leading: Icon(Icons.paste, size: 18),
          title: Text('Paste'),
          contentPadding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
        )),
      ],
    ).then((action) {
      if (action == 'copy') {
        _copySelection();
      } else if (action == 'paste') {
        _pasteClipboard();
      }
    });
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
