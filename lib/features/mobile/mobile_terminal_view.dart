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
import 'terminal_copy_overlay.dart';

/// Full-screen mobile terminal with SSH keyboard bar.
///
/// No tiling/splitting — single pane, full screen.
///
/// **Gestures**. One-finger drags go to xterm (tap, scroll, long-press →
/// select-word). Two-finger drags are tracked manually via [Listener] and
/// translated into a pinch-zoom (font size) without routing through
/// Flutter's [ScaleGestureRecognizer] — the stock recognizer treats a
/// single-finger drag as a 1× scale and wins the gesture arena, which
/// silently kills xterm's long-press recognizer on the same subtree.
///
/// **Copy mode**. Tapping the Copy button in the keyboard bar enters a
/// trackpad-style [TerminalCopyOverlay]: xterm pointer input is
/// suspended, a virtual cursor overlays the terminal, single-finger
/// drags move the cursor in cell units, and the first pointer-down
/// drops a selection anchor that subsequent movement extends. Two-finger
/// pinch still zooms in copy mode (useful when precision hurts). The
/// toolbar inside the overlay exposes Copy and Cancel.
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
  final _copyOverlayKey = GlobalKey<TerminalCopyOverlayState>();
  ShellConnection? _shellConn;

  /// Whether the terminal pane is in an error state (for potential retry).
  bool hasError = false;
  StreamSubscription<ConnectionStep>? _progressSub;
  double _fontSize = 14.0;
  bool _copyMode = false;

  /// Manual pointer tracking — the outer [Listener] mirrors every active
  /// pointer here so we can distinguish single-finger drags (cursor pan in
  /// copy mode, otherwise delegated to xterm) from two-finger drags
  /// (pinch). See the class docstring for the rationale against
  /// [ScaleGestureRecognizer].
  final Map<int, Offset> _pointers = {};

  /// Pinch state — initial distance between the first two pointers and
  /// the font size at the moment the pinch started. Null when fewer than
  /// two pointers are down.
  double? _pinchInitialDistance;
  double? _pinchInitialFontSize;

  @override
  void initState() {
    super.initState();
    final config = ref.read(configProvider);
    _terminal = Terminal(maxLines: config.scrollback);
    TerminalScrubber.instance.register(_terminal);
    _terminalController = TerminalController();
    // Hard-block xterm's built-in touch selection (long-press → word,
    // finger-drag → character select). xterm's [TerminalGestureHandler]
    // internally calls `renderTerminal.selectWord/selectCharacters` on
    // every touch long-press + drag; there is no public flag to turn
    // that off, and winning the Flutter gesture arena at a parent level
    // would also steal the scroll gesture. Instead we listen to the
    // controller and drop any selection that appears while the copy-mode
    // overlay is not active — that overlay is the only sanctioned
    // selection surface on mobile. The listener no-ops when selection
    // is already null, so `clearSelection()` does not recurse through
    // `notifyListeners`. Users who want to select text must enter copy
    // mode via the keyboard bar's 📋 button.
    _terminalController.addListener(_enforceCopyModeSelectionGuard);
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

  /// See [initState] for the rationale — xterm's built-in touch
  /// selection is blocked outside copy mode by clearing any selection
  /// that lands on the controller when `_copyMode` is false.
  void _enforceCopyModeSelectionGuard() {
    if (_copyMode) return;
    if (_terminalController.selection == null) return;
    _terminalController.clearSelection();
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
    _shellConn?.close();
    _terminalController.removeListener(_enforceCopyModeSelectionGuard);
    _terminalController.dispose();
    super.dispose();
  }

  void _onKeyboardInput(String data) {
    _shellConn?.shell.write(Uint8List.fromList(utf8.encode(data)));
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

  // ── Pointer tracking ─────────────────────────────────────────────────

  void _onPointerDown(PointerDownEvent e) {
    _pointers[e.pointer] = e.localPosition;
    if (_pointers.length == 1 && _copyMode) {
      _copyOverlayKey.currentState?.onAnchorDown();
    }
    if (_pointers.length == 2) {
      _beginPinch();
    }
  }

  void _onPointerMove(PointerMoveEvent e) {
    final prev = _pointers[e.pointer];
    if (prev == null) return;
    _pointers[e.pointer] = e.localPosition;
    if (_pointers.length == 1) {
      if (_copyMode) {
        _copyOverlayKey.currentState?.onCursorPan(e.delta);
      }
      // Non-copy mode single-finger: do nothing — the pointer event has
      // already reached xterm (Listener does not consume events), which
      // handles tap / long-press / drag-select on its own.
      return;
    }
    if (_pointers.length >= 2 && _pinchInitialDistance != null) {
      _updatePinch();
    }
  }

  void _onPointerUp(PointerEvent e) {
    _pointers.remove(e.pointer);
    if (_pointers.length < 2 && _pinchInitialDistance != null) {
      _endPinch();
    }
  }

  // ── Pinch-zoom ───────────────────────────────────────────────────────

  void _beginPinch() {
    final positions = _pointers.values.toList(growable: false);
    if (positions.length < 2) return;
    _pinchInitialDistance = (positions[0] - positions[1]).distance;
    _pinchInitialFontSize = _fontSize;
  }

  void _updatePinch() {
    final positions = _pointers.values.toList(growable: false);
    if (positions.length < 2) return;
    final d = (positions[0] - positions[1]).distance;
    final d0 = _pinchInitialDistance;
    final f0 = _pinchInitialFontSize;
    if (d0 == null || f0 == null || d0 == 0) return;
    final scaled = (f0 * (d / d0)).clamp(8.0, 24.0);
    if ((scaled - _fontSize).abs() < 0.1) return;
    setState(() {
      _fontSize = scaled;
    });
  }

  void _endPinch() {
    if (_pinchInitialFontSize == null) return;
    _pinchInitialDistance = null;
    _pinchInitialFontSize = null;
    // Persist pinch-zoomed font size to config so the next launch / tab
    // uses the same size. The config save is debounced + async, so this
    // does not stall the UI even on slow storage.
    ref
        .read(configProvider.notifier)
        .update(
          (c) => c.copyWith(terminal: c.terminal.copyWith(fontSize: _fontSize)),
        );
  }

  // ── Copy mode ────────────────────────────────────────────────────────

  void _onCopyModeChanged(bool active) {
    setState(() => _copyMode = active);
  }

  void _copyFromOverlay() {
    HapticFeedback.lightImpact();
    TerminalClipboard.copy(_terminal, _terminalController);
    _keyboardKey.currentState?.exitCopyMode();
  }

  void _cancelCopyMode() {
    HapticFeedback.lightImpact();
    _keyboardKey.currentState?.exitCopyMode();
  }

  @override
  Widget build(BuildContext context) {
    // React to font size changes from settings slider
    final configFontSize = ref.watch(configProvider.select((c) => c.fontSize));
    if (_pinchInitialFontSize == null) {
      // Update only when not pinch-zooming
      _fontSize = configFontSize;
    }

    // Always render TerminalView — progress log and errors are written
    // directly into the terminal buffer via ANSI codes.
    //
    // Stack layout: terminal is bottom-bounded by the keyboard bar +
    // (when visible) the system keyboard, so the cursor line never
    // slips under either one.
    final mq = MediaQuery.of(context);
    final rawInset = mq.viewInsets.bottom;
    final bottomGap = AppTheme.itemHeightXl + mq.viewPadding.bottom;
    final keyboardInset = math.max(0.0, rawInset - bottomGap);
    final terminalBottom = AppTheme.itemHeightXl + keyboardInset;
    return Stack(
      children: [
        Positioned(
          left: 0,
          top: 0,
          right: 0,
          bottom: terminalBottom,
          child: _buildTerminalArea(),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: keyboardInset,
          child: SshKeyboardBar(
            key: _keyboardKey,
            onInput: _onKeyboardInput,
            onPaste: _paste,
            onSnippets: _showSnippets,
            onCopyModeChanged: _onCopyModeChanged,
          ),
        ),
      ],
    );
  }

  Widget _buildTerminalArea() {
    return Listener(
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerUp,
      child: Stack(
        children: [
          TerminalView(
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
          Positioned.fill(
            child: CursorTextOverlay(terminal: _terminal, fontSize: _fontSize),
          ),
          if (_copyMode)
            Positioned.fill(
              child: TerminalCopyOverlay(
                key: _copyOverlayKey,
                terminal: _terminal,
                controller: _terminalController,
                fontSize: _fontSize,
                fontFamily: AppFonts.monoFamily,
                fontFamilyFallback: AppFonts.monoFallback,
                onCopy: _copyFromOverlay,
                onCancel: _cancelCopyMode,
              ),
            ),
        ],
      ),
    );
  }
}
