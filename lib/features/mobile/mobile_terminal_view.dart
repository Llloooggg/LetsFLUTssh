import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';

import '../../core/connection/connection.dart';
import '../../core/connection/connection_step.dart';
import '../../core/connection/progress_tracker.dart';
import '../../core/connection/progress_writer.dart';
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

  /// Whether the terminal pane is in an error state (for potential retry).
  bool hasError = false;
  StreamSubscription<ConnectionStep>? _progressSub;
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
    final l10n = S.of(context);
    final tracker = ProgressTracker(conn);
    final writer = ProgressWriter(
      terminal: _terminal,
      l10n: l10n,
      config: conn.sshConfig,
    );

    _progressSub = writer.subscribe(tracker);
    await conn.waitUntilReady();
    _progressSub?.cancel();
    _progressSub = null;
    tracker.dispose();

    if (!conn.isConnected) {
      if (mounted) {
        final error = conn.connectionError != null
            ? localizeError(l10n, conn.connectionError!)
            : l10n.errConnectionFailed;
        _terminal.write('\x1B[?25h\x1B[31m$error\x1B[0m\r\n');
        setState(() => hasError = true);
      }
      return;
    }

    try {
      // Clear progress log before opening shell — openShell wires stdout
      // to terminal.write(), so any server output must not be erased.
      writer.clear();
      _shellConn = await ShellHelper.openShell(
        connection: conn,
        terminal: _terminal,
        onDone: () {
          if (mounted) {
            setState(() => hasError = true);
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

      if (mounted) setState(() {});
    } catch (e) {
      AppLogger.instance.log(
        'Shell open failed: $e',
        name: 'MobileTerminal',
        error: e,
      );
      if (mounted) {
        final localized = localizeError(l10n, e);
        _terminal.write('\x1B[?25h\x1B[31m$localized\x1B[0m\r\n');
        setState(() => hasError = true);
      }
    }
  }

  @override
  void dispose() {
    _progressSub?.cancel();
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

    // Always render TerminalView — progress log and errors are written
    // directly into the terminal buffer via ANSI codes.
    //
    // Stack layout: terminal fills all available space (never resizes on
    // keyboard show/hide), keyboard bar floats at the bottom above the
    // system keyboard.  Paired with Scaffold(resizeToAvoidBottomInset: false)
    // in MobileShell to prevent xterm buffer reflow that caused duplicate
    // lines when the soft keyboard appeared.
    // viewInsets.bottom is measured from the screen bottom, but this Stack
    // sits inside the Scaffold body which ends above the bottomNavigationBar
    // and the device safe-area.  Subtract that gap so the keyboard bar sits
    // flush against the system keyboard instead of floating above it.
    final mq = MediaQuery.of(context);
    final rawInset = mq.viewInsets.bottom;
    final bottomGap = AppTheme.itemHeightXl + mq.viewPadding.bottom;
    final keyboardInset = math.max(0.0, rawInset - bottomGap);
    return Stack(
      children: [
        Positioned.fill(child: _buildPinchZoomArea()),
        Positioned(
          left: 0,
          right: 0,
          bottom: keyboardInset,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_hasSelection) _buildSelectionToolbar(),
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
          ),
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
    final mq = MediaQuery.of(context);
    const keyboardBarHeight = AppTheme.itemHeightLg;
    final rawInset = mq.viewInsets.bottom;
    final bottomGap = AppTheme.itemHeightXl + mq.viewPadding.bottom;
    final keyboardInset = math.max(0.0, rawInset - bottomGap);
    return Stack(
      children: [
        IgnorePointer(
          ignoring: _pointerCount >= 2,
          child: TerminalView(
            _terminal,
            controller: _terminalController,
            autofocus: true,
            backgroundOpacity: 1.0,
            padding: EdgeInsets.only(
              left: 4,
              top: 4,
              right: 4,
              bottom: 4 + keyboardInset + keyboardBarHeight,
            ),
            theme: AppTheme.terminalTheme,
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
