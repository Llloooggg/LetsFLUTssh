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
import '../../core/security/terminal_scrubber.dart';
import '../../core/ssh/shell_helper.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/config_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../utils/logger.dart';
import '../../utils/terminal_clipboard.dart';
import '../snippets/snippet_picker.dart';
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
    TerminalScrubber.instance.register(_terminal);
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
      //
      // Encode via `utf8.encode` — `String.codeUnits` returns UTF-16
      // code units, and `Uint8List.fromList` masks each element to its
      // low byte, which silently collapses every non-ASCII codepoint
      // onto the 0x00–0xFF range. On a Russian Gboard long-press the
      // symptom was Cyrillic letters landing as ASCII punctuation /
      // digits: U+0430 `а` → 0x30 `0`, U+0440 `р` → 0x40 `@`, and so
      // on across U+0430..U+044F → 0x30..0x4F. The same truncation
      // would silently corrupt CJK, Arabic, emoji and every other
      // non-ASCII script. `utf8.encode` produces the correct
      // multi-byte sequence the SSH shell expects.
      _terminal.onOutput = (data) {
        final transformed =
            _keyboardKey.currentState?.applyModifiers(data) ?? data;
        _shellConn?.shell.write(Uint8List.fromList(utf8.encode(transformed)));
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
    TerminalScrubber.instance.unregister(_terminal);
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

  /// Open the snippet picker and, if the user picks a snippet, send the
  /// command to the shell with a trailing newline — matching the desktop
  /// terminal pane behaviour.
  Future<void> _showSnippets() async {
    final shell = _shellConn?.shell;
    if (shell == null) return;
    final command = await SnippetPicker.show(
      context,
      sessionId: widget.connection.sessionId,
    );
    if (command == null) return;
    final payload = command.endsWith('\n') ? command : '$command\n';
    shell.write(Uint8List.fromList(utf8.encode(payload)));
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
    // Stack layout: terminal is bottom-bounded by the keyboard bar +
    // (when visible) the system keyboard, so the cursor line never
    // slips under either one. xterm reflows on resize — the earlier
    // "never resize" policy was a workaround for a duplicate-line
    // quirk in old xterm versions; modern xterm handles the reflow
    // correctly, and leaving the terminal full-size while the
    // keyboard is up meant the user typed into a viewport whose
    // bottom rows were hidden under the keyboard. The fix trades a
    // reflow for content visibility.
    //
    // viewInsets.bottom is measured from the screen bottom, but this
    // Stack sits inside the Scaffold body which ends above the
    // bottomNavigationBar and the device safe-area. Subtract that
    // gap so the keyboard bar sits flush against the system
    // keyboard instead of floating above it.
    final mq = MediaQuery.of(context);
    final rawInset = mq.viewInsets.bottom;
    final bottomGap = AppTheme.itemHeightXl + mq.viewPadding.bottom;
    final keyboardInset = math.max(0.0, rawInset - bottomGap);
    // Terminal bottom = keyboard bar height + system-keyboard inset.
    // When no keyboard is visible, collapses to bar height alone.
    final terminalBottom = AppTheme.itemHeightXl + keyboardInset;
    return Stack(
      children: [
        Positioned(
          left: 0,
          top: 0,
          right: 0,
          bottom: terminalBottom,
          child: _buildPinchZoomArea(),
        ),
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
                onSnippets: _showSnippets,
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
            theme: AppTheme.terminalTheme,
            textStyle: TerminalStyle(
              fontSize: _fontSize,
              fontFamily: AppFonts.monoFamily,
              fontFamilyFallback: AppFonts.monoFallback,
            ),
            // xterm's default is `TextInputType.emailAddress`, which
            // tells Gboard/iOS that the field holds an email — the
            // IME then surfaces email-specific helpers (the
            // clipboard/@-symbol pill, auto-suggest toolbars that
            // wouldn't dismiss with a tap on the terminal) that
            // users correctly interpreted as "random popups I
            // can't close". `TextInputType.text` removes the
            // email hint while still advertising a text field so
            // IMEs keep full cursor-gesture support; xterm's own
            // `CustomTextEdit` already disables autocorrect,
            // suggestions, and IME personalisation inside its
            // `TextInputConfiguration`, so the field stays
            // prediction-free regardless.
            keyboardType: TextInputType.text,
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
      // `canRequestFocus: false` so tapping Copy/Paste does not
      // steal focus from `TerminalView`. Without it, every tap
      // would dismiss the system keyboard (xterm closes its
      // input connection as soon as its `FocusNode` loses focus).
      child: InkWell(
        canRequestFocus: false,
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
