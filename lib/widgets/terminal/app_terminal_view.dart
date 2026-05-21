import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

import '../../theme/app_theme.dart';
import 'anchor_pinning_terminal_controller.dart';

/// Shared xterm `TerminalView` wrapper used by both the live PTY
/// pane and the read-only log viewer.
///
/// Centralises the gesture wiring + standard styling that every
/// consumer in the app needs:
///   * Right-click context menu → routed through xterm's own
///     `TerminalView.onSecondaryTapDown` prop. xterm registers an
///     internal `TapGestureRecognizer` that already claims the
///     secondary-tap gesture in the Flutter arena; layering an
///     outer `GestureDetector.onSecondaryTapDown` would lose the
///     arena race (the inner recogniser accepts first even when
///     its own secondary callback is null), and `Listener.onPointerDown`
///     only observes — it never claims, so xterm's primary-tap
///     handler could still run. Threading through the inner prop
///     guarantees delivery for two-finger trackpad taps too. xterm
///     does NOT clear the active selection on secondary tap — only
///     primary `_onTapDown` clears it — so the highlight stays
///     visible behind the menu (best-practice match: xshell,
///     Windows Terminal, browsers).
///   * `beginDrag` / `endDrag` on the [AnchorPinningTerminalController]
///     for primary mouse buttons so wheel-scroll mid-drag does
///     not re-anchor the selection base onto the new cell under
///     the original click pixel.
///   * Standard padding ([padding]) / theme / monospace font
///     matching the app's terminal look.
///   * Optional [CursorTextOverlay] (toggled via [showCursorOverlay])
///     for the live PTY view — the read-only log viewer leaves
///     it off and writes `\x1B[?25l` itself to hide the cursor.
///
/// Consumers own the [Terminal] and the [AnchorPinningTerminalController]
/// instances — both are passed in. This keeps lifecycle decisions
/// (when to write content, when to dispose, etc.) with the caller.
typedef SecondaryTapBuilder =
    void Function(BuildContext context, Offset globalPosition);

class AppTerminalView extends StatelessWidget {
  /// Inset around the inner `TerminalView`. Single source of truth
  /// across every terminal surface — PTY pane, log viewer, connection
  /// progress all read this constant rather than hardcoding their
  /// own. The PTY pane's row-snap math (`_buildTerminalStack`) reads
  /// [verticalPadding] so a future tweak here propagates without a
  /// silent miscalculation.
  static const double padding = AppSpacing.xs;

  /// Combined vertical inset (top + bottom). Exposed for callers that
  /// need to subtract the padding from a `LayoutBuilder` constraint
  /// before computing how many cells fit.
  static const double verticalPadding = padding * 2;

  /// The xterm `Terminal` instance to render. Owned by the caller.
  final Terminal terminal;

  /// Selection controller — caller owns the lifecycle. Use
  /// [AnchorPinningTerminalController] (not vanilla
  /// `TerminalController`) so the `beginDrag` / `endDrag` calls
  /// below pin the drag-start cell across wheel scrolls.
  final AnchorPinningTerminalController controller;

  /// Body font size in logical pixels.
  final double fontSize;

  /// Whether `TerminalView` autofocuses on mount. Read-only views
  /// pass `false`; the live PTY pane uses focus state from its
  /// parent.
  final bool autofocus;

  /// `TerminalView`'s `hardwareKeyboardOnly` flag. Desktop pane
  /// sets it; embeddings that share focus with text fields
  /// (mobile) leave it off.
  final bool hardwareKeyboardOnly;

  /// When `true`, paints the cursor-position glyph overlay on top
  /// of the terminal. The PTY pane needs it (live cursor); the
  /// log viewer does not.
  final bool showCursorOverlay;

  /// Right-click context-menu opener. Wired into xterm's
  /// `TerminalView.onSecondaryTapDown` so two-finger trackpad
  /// taps (which the OS reports as `kSecondaryButton`) land here
  /// alongside traditional right-mouse clicks. The caller decides
  /// what items to show and invokes `showAppContextMenu` itself.
  final SecondaryTapBuilder? secondaryTapBuilder;

  /// Keyboard hook forwarded to `TerminalView.onKeyEvent`. The
  /// PTY pane intercepts Ctrl+Shift+C/V here; the log viewer
  /// intercepts plain Ctrl+C.
  final KeyEventResult Function(FocusNode, KeyEvent)? onKeyEvent;

  /// Pointer signal hook — typically Ctrl+wheel font-size
  /// adjustment in the live pane.
  final void Function(PointerSignalEvent)? onPointerSignal;

  /// Optional widget painted as a `Positioned.fill` overlay above
  /// `TerminalView`. Used by the PTY pane for [CursorTextOverlay];
  /// the log viewer passes `null`.
  final Widget Function(BuildContext)? overlayBuilder;

  /// Optional `FocusNode` to wire into `TerminalView` so callers can
  /// `requestFocus()` programmatically (e.g. the PTY pane when its
  /// tab becomes the focused panel, the log viewer when the user
  /// reveals the section). Without one, `TerminalView` creates an
  /// internal node and the caller can only ever rely on
  /// `autofocus` + xterm's tap-down focus request — both of which
  /// fire ONLY when there is no active selection (per xterm 4
  /// `_onTapDown`), so re-clicking after a drag-select does not
  /// re-focus the terminal and any external `onKeyEvent` consumer
  /// (e.g. `Ctrl+C` in the read-only log view) stops receiving
  /// key events.
  final FocusNode? focusNode;

  const AppTerminalView({
    super.key,
    required this.terminal,
    required this.controller,
    this.fontSize = 14.0,
    this.autofocus = false,
    this.hardwareKeyboardOnly = false,
    this.showCursorOverlay = false,
    this.secondaryTapBuilder,
    this.onKeyEvent,
    this.onPointerSignal,
    this.overlayBuilder,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    final view = TerminalView(
      terminal,
      controller: controller,
      focusNode: focusNode,
      autofocus: autofocus,
      hardwareKeyboardOnly: hardwareKeyboardOnly,
      onKeyEvent: onKeyEvent,
      backgroundOpacity: 1.0,
      padding: const EdgeInsets.all(padding),
      theme: AppTheme.terminalTheme,
      textStyle: TerminalStyle(
        fontSize: fontSize,
        fontFamily: AppFonts.monoFamily,
        fontFamilyFallback: AppFonts.monoFallback,
      ),
      onSecondaryTapDown: secondaryTapBuilder == null
          ? null
          : (details, _) {
              secondaryTapBuilder!.call(context, details.globalPosition);
            },
    );

    final Widget body = overlayBuilder == null
        ? view
        : Stack(
            children: [
              view,
              Positioned.fill(child: overlayBuilder!(context)),
            ],
          );

    return Listener(
      onPointerDown: (event) {
        // Primary mouse button down → pin the drag base so a wheel
        // scroll mid-drag doesn't re-anchor `base` to the cell
        // under the original click pixel after scrolling. Alt-buffer
        // skips the pin: alt-buffer has no scrollback so the bug
        // cannot occur and touch long-press word-extend would
        // otherwise freeze the pinned position.
        if (event.kind == PointerDeviceKind.mouse &&
            event.buttons == kPrimaryButton &&
            !terminal.isUsingAltBuffer) {
          controller.beginDrag();
        }
      },
      onPointerUp: (_) => controller.endDrag(),
      onPointerCancel: (_) => controller.endDrag(),
      onPointerSignal: onPointerSignal,
      child: body,
    );
  }
}
