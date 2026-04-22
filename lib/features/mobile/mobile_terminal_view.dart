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
/// drags move the cursor in cell units. The selection anchor is
/// dropped on the *first pointer-up* of the session, not on the first
/// pointer-down — this gives the user an explicit "aim" phase: drag
/// the virtual cursor to the start cell, lift → anchor drops, then
/// drag again to extend. Subsequent pointer-ups don't re-anchor, so
/// the user can lift + re-touch without losing progress. Two-finger
/// pinch still zooms in copy mode. The Copy/Cancel toolbar lives in
/// the parent Column (below the terminal), not floating over it.
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
    if (_pointers.length == 2) {
      _beginPinch();
    }
    // Intentionally no `onAnchorDown` here — in copy mode the first
    // touch moves the cursor freely so the user can *aim* at the start
    // of the selection before committing. The anchor drops on the
    // matching pointer-up below (aim-first, then extend). Two touches
    // are the pinch-zoom signal; no anchor logic for them.
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
      // handles tap / long-press / drag-select on its own. The
      // controller-side guard in [_enforceCopyModeSelectionGuard] wipes
      // any selection xterm tries to stamp.
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
    // Copy mode's two-phase model: the first *release* (after the user
    // has aimed the virtual cursor at the start of the selection) drops
    // the anchor. Subsequent releases don't re-anchor — [onAnchorDown]
    // is idempotent — so the user can lift and re-touch to keep
    // extending from the same start point.
    if (_copyMode && _pointers.isEmpty) {
      _copyOverlayKey.currentState?.onAnchorDown();
      // Force a rebuild so the `CopyModeHint` copy in the parent Column
      // flips from "tap to start" to "tap to extend" once `anchorSet`
      // becomes true. `TerminalCopyOverlay` uses a GlobalKey state
      // lookup, so `setState` on this parent widget re-reads the flag
      // on the next build.
      if (mounted) setState(() {});
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

    // Layout rationale. Scaffold disables `resizeToAvoidBottomInset` on
    // the terminal page (see MobileShell) so the viewport never shrinks
    // when the soft keyboard opens — shrinking would make xterm reflow
    // its buffer and duplicate the first scrollback lines (see commit
    // 20c60c9). That's the **hard** invariant: the terminal's rendered
    // size cannot track the keyboard.
    //
    // Copy-mode hint + toolbar are a different story. They are small
    // strips (~24 px + ~40 px) and shrinking the terminal by that much
    // is user-visible *and requested* — the toolbar must dock against
    // the virtual keyboard so the user's thumb does not chase a
    // floating button while selecting. A minor reflow when the mode
    // toggles is the tradeoff.
    //
    // Result: Stack with the terminal Column reserving only the
    // keyboard-bar slot at the bottom (fixed `itemHeightXl`, not
    // keyboard-inset-aware). The bottom control strip — either the SSH
    // keyboard bar (normal mode) or the copy-mode toolbar (copy mode)
    // — lives in a separate Positioned that floats above the soft
    // keyboard via `viewInsets.bottom`. Swapping the bottom widget
    // between the two modes keeps the visible height of the terminal
    // stable across keyboard open/close and matches what the user asked
    // for ("toolbar docked against keyboard").
    final mq = MediaQuery.of(context);
    final keyboardInset = mq.viewInsets.bottom;
    // Bottom nav bar (MobileShell) sits at the very bottom of the
    // viewport. MobileShell turns on `extendBody: true` for the
    // terminal page so this MobileTerminalView renders under the nav
    // bar — that's why the bar's `bottom` offset must clamp to
    // `navBarHeight` when the keyboard is closed (so the bar sits
    // above the nav, not behind it) and follow `keyboardInset` when
    // the keyboard covers both nav and lower content.
    const navBarHeight = AppTheme.itemHeightXl;
    final barBottom = math.max(navBarHeight, keyboardInset);
    final anchorSet =
        _copyMode && (_copyOverlayKey.currentState?.anchorSet ?? false);
    // Reserve enough vertical space below the terminal Column for the
    // bottom control strip (toolbar stacked on top of the SSH keyboard
    // bar in copy mode, or just the keyboard bar in normal mode) PLUS
    // the fixed nav-bar slot underneath. The reservation is a fixed
    // constant — it never tracks `viewInsets` — so the terminal
    // widget's height is invariant across keyboard open/close. Hint +
    // toolbar toggling still reflows by their own small height; the
    // terminal never reflows by the ~300 px the soft keyboard would
    // otherwise consume.
    final bottomStripHeight =
        navBarHeight +
        AppTheme.itemHeightXl +
        (_copyMode ? _copyToolbarHeight : 0);
    return Stack(
      fit: StackFit.expand,
      children: [
        // Terminal + hint: bottom pinned to a fixed `bottomStripHeight`
        // — does NOT include `keyboardInset`. Terminal rendered height
        // stays constant while the keyboard opens / closes.
        //
        // `SelectionContainer.disabled` opts the terminal area out of
        // the app-wide `AppSelectionArea` that wraps `MobileShell`:
        // without it, taps inside the xterm widget could bubble up to
        // the SelectionArea's gesture recognizers and bring up the
        // system text-selection toolbar ("select all / copy / paste"),
        // which is a surprise on a terminal whose copy path is a
        // dedicated Copy button. The overlay is still fully
        // interactive — SelectionContainer.disabled only suppresses
        // the selection machinery, not taps.
        Positioned(
          left: 0,
          top: 0,
          right: 0,
          bottom: bottomStripHeight,
          child: SelectionContainer.disabled(
            child: Column(
              children: [
                if (_copyMode) CopyModeHint(anchorSet: anchorSet),
                Expanded(child: _buildTerminalArea()),
              ],
            ),
          ),
        ),
        // Bottom control strip — floats above the soft keyboard via
        // `viewInsets.bottom`, clamped to `navBarHeight` so it stays
        // above the mobile shell's bottom nav bar when the keyboard is
        // closed. Copy toolbar stacks on top of the SSH keyboard bar
        // when copy mode is active; otherwise just the keyboard bar.
        Positioned(
          left: 0,
          right: 0,
          bottom: barBottom,
          child: SelectionContainer.disabled(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_copyMode)
                  SizedBox(
                    height: _copyToolbarHeight,
                    child: CopyModeToolbar(
                      onCopy: _copyFromOverlay,
                      onCancel: _cancelCopyMode,
                    ),
                  ),
                SshKeyboardBar(
                  key: _keyboardKey,
                  onInput: _onKeyboardInput,
                  onPaste: _paste,
                  onSnippets: _showSnippets,
                  onCopyModeChanged: _onCopyModeChanged,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Fixed height for the copy-mode toolbar slot. Matches the Material
  /// 48-dp tap-target grid and the `itemHeightLg` theme constant used by
  /// other inline action rows, so the bottom strip lines up with the SSH
  /// keyboard bar's button row.
  static const double _copyToolbarHeight = AppTheme.itemHeightLg;

  Widget _buildTerminalArea() {
    // xterm's `TerminalView` paints whole cells only — its viewport
    // rounds the available height down to `floor(h / cellHeight)` rows
    // and leaves the remainder as a theme-coloured strip at the bottom
    // that the user reads as "dead terminal space" (the literal
    // complaint: *"он выглядит как терминал, но туда ничего не
    // выписывается"*). `LayoutBuilder` below snaps the widget's own
    // height to an integer-row multiple so the last rendered row sits
    // flush against the next widget in the Column; the few remaining
    // pixels between the snapped height and the parent's height become
    // a `ColoredBox` strip that visually belongs to the bottom control
    // strip instead of the terminal.
    return LayoutBuilder(
      builder: (context, constraints) {
        // Cell height mirrors xterm's painter: fontSize × the shared
        // `kTerminalLineHeight` multiplier. Padding is the same
        // `EdgeInsets.all(4)` we pass to TerminalView below.
        const verticalPadding = 8.0; // EdgeInsets.all(4).vertical
        final cellHeight = _fontSize * kTerminalLineHeight;
        final usable = constraints.maxHeight - verticalPadding;
        final rows = usable > 0 ? (usable / cellHeight).floor() : 0;
        final snappedHeight = rows > 0
            ? rows * cellHeight + verticalPadding
            : constraints.maxHeight;
        return Column(
          children: [
            SizedBox(height: snappedHeight, child: _buildTerminalListener()),
            if (snappedHeight < constraints.maxHeight)
              Expanded(
                child: ColoredBox(color: AppTheme.terminalTheme.background),
              ),
          ],
        );
      },
    );
  }

  Widget _buildTerminalListener() {
    return Listener(
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerUp,
      child: Stack(
        children: [
          // Isolate xterm's internal gesture recognizers (drag-select,
          // scroll) while copy mode is active. xterm still sees
          // `setSuspendPointerInput(true)` which gates mouse-reporting
          // to the remote shell, but its LOCAL LongPressGestureRecognizer
          // + PanGestureRecognizer keep firing without this shield:
          // a single-finger drag in copy mode used to run both
          // `renderTerminal.selectCharacters` (xterm) *and*
          // `onCursorPan` (our overlay) on every frame, and the two
          // competing setSelection calls produced the duplicate-rows +
          // gaps artefacts users saw in scrollback. `AbsorbPointer`
          // blocks pointers from reaching TerminalView; the outer
          // Listener still observes them via its ancestor hit-test so
          // cursor-pan deltas keep flowing.
          AbsorbPointer(
            absorbing: _copyMode,
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
          if (_copyMode)
            Positioned.fill(
              child: TerminalCopyOverlay(
                key: _copyOverlayKey,
                terminal: _terminal,
                controller: _terminalController,
                fontSize: _fontSize,
                fontFamily: AppFonts.monoFamily,
                fontFamilyFallback: AppFonts.monoFallback,
              ),
            ),
        ],
      ),
    );
  }
}
