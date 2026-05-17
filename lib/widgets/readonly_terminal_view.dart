import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';

import '../l10n/app_localizations.dart';
import '../widgets/context_menu.dart';
import '../widgets/shortcut_registry.dart' show AppShortcut;
import '../theme/app_theme.dart';
import '../utils/terminal_clipboard.dart';

/// Read-only xterm TerminalView — no keyboard input, no context menu.
///
/// Used by [ConnectionProgress] for SFTP tab progress/error display.
class ReadOnlyTerminalView extends StatefulWidget {
  final Terminal terminal;
  final double fontSize;

  const ReadOnlyTerminalView({
    super.key,
    required this.terminal,
    this.fontSize = 14.0,
  });

  @override
  State<ReadOnlyTerminalView> createState() => _ReadOnlyTerminalViewState();
}

class _ReadOnlyTerminalViewState extends State<ReadOnlyTerminalView> {
  late final TerminalController _controller;

  /// Last non-empty selected text snapshot. Kept up-to-date by
  /// [`_onControllerChanged`] so a secondary-tap (which starts a
  /// fresh xterm gesture that immediately clears
  /// `_controller.selection`) still has a stable source for the
  /// "Copy" menu item. Without this cache the right-click reads
  /// `selection` *after* xterm has already cleared it on the new
  /// pointer-down, the if-branch in [`_onPointerDown`] sees no
  /// selection, and the menu silently doesn't open — the original
  /// user-reported "выбор просто спадает и нет контекстного меню"
  /// symptom.
  String? _cachedSelection;

  @override
  void initState() {
    super.initState();
    _controller = TerminalController();
    _controller.addListener(_onControllerChanged);
    widget.terminal.write('\x1B[?25l'); // hide cursor — read-only view
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    super.dispose();
  }

  /// Cache the latest non-empty selection text. Fires on every
  /// controller mutation — `xterm`'s drag-select calls
  /// `notifyListeners` as the selection range grows, so the cache
  /// holds the most-recent populated range. Selection-clear
  /// notifications (range goes null) deliberately do *not* reset
  /// the cache: right-click on a primary-cleared selection still
  /// needs the prior text.
  void _onControllerChanged() {
    final sel = _controller.selection;
    if (sel == null) return;
    final text = widget.terminal.buffer.getText(sel);
    if (text.isNotEmpty) {
      _cachedSelection = text;
    }
  }

  /// Activators that copy the current selection out of this
  /// read-only log surface. We use plain `Ctrl+C` / `Cmd+C` here —
  /// not [`AppShortcut.terminalCopy`] (`Ctrl+Shift+C`) — because
  /// this widget renders a connection-progress log, not a live
  /// PTY: there is no foreground process to SIGINT, so the Unix
  /// convention of reserving Ctrl+C for interrupt doesn't apply.
  /// Ctrl+C is what the user reaches for when copying out of any
  /// non-terminal text surface.
  static const _copyActivators = <ShortcutActivator>[
    SingleActivator(LogicalKeyboardKey.keyC, control: true),
    SingleActivator(LogicalKeyboardKey.keyC, meta: true),
  ];

  /// Intercept the copy shortcut before xterm dispatches the key
  /// event to its built-in `_shortcutManager`. xterm calls
  /// `widget.onKeyEvent` first and short-circuits on a non-ignored
  /// return — so passing this directly as
  /// [`TerminalView.onKeyEvent`] is the only ordering that
  /// reliably wins against xterm's defaults. An ancestor
  /// `Focus(onKeyEvent:)` runs AFTER the inner Focus and gets
  /// nothing because xterm already returned `handled`.
  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    for (final activator in _copyActivators) {
      if (activator.accepts(event, HardwareKeyboard.instance)) {
        TerminalClipboard.copy(widget.terminal, _controller);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  /// Right-click handler. The earlier shape used a `Listener` on
  /// `PointerDownEvent` filtered by `kSecondaryButton`, which
  /// silently never fired in practice — xterm's internal
  /// `PanGestureRecognizer` accepts every button and the parent
  /// `Listener` only sees the event when the deepest child's
  /// hit-test passes through. `GestureDetector.onSecondaryTapUp`
  /// is the canonical Flutter shape for right-click; xterm has no
  /// competing secondary-tap recogniser so the arena awards it to
  /// us cleanly. `HitTestBehavior.translucent` keeps xterm's
  /// primary-button drag-select working — events propagate to
  /// both this detector AND the child.
  void _onSecondaryTap(TapUpDetails details, BuildContext menuContext) {
    final text = _cachedSelection;
    final hasSelection = text != null && text.isNotEmpty;
    showAppContextMenu(
      context: menuContext,
      position: details.globalPosition,
      items: [
        if (hasSelection)
          StandardMenuAction.copy.item(
            menuContext,
            // The on-wire activator on this surface is `Ctrl+C`, not
            // `Ctrl+Shift+C` — this is a log view, not a live PTY
            // (see `_copyActivators` for the rationale). `fileCopy`
            // is the registry entry that resolves to that binding;
            // reusing it keeps the hint label accurate without
            // growing the registry.
            shortcut: AppShortcut.fileCopy,
            onTap: () {
              TerminalClipboard.copyText(text);
              _controller.clearSelection();
              _cachedSelection = null;
            },
          ),
        // "Select all" is always visible — gives the user a way to
        // grab the full log buffer without dragging end-to-end. The
        // cache populates via `_onControllerChanged` so an immediate
        // Copy on the next right-click fires off the full text.
        ContextMenuItem(
          label: S.of(menuContext).selectAll,
          icon: Icons.select_all,
          onTap: _selectAll,
        ),
      ],
    );
  }

  /// Set the controller's selection to the entire scrollback +
  /// viewport. Mirrors the shape xterm's built-in
  /// `SelectAllTextIntent` action uses
  /// (`terminal.buffer.createAnchor(col, row)`), which is the only
  /// public API xterm 4 exposes for synthesising selection anchors
  /// outside a live drag. The cache populates via
  /// [`_onControllerChanged`] so the immediate Copy on the user's
  /// next tap fires off the full-buffer text.
  void _selectAll() {
    final terminal = widget.terminal;
    final buffer = terminal.buffer;
    if (buffer.height == 0) return;
    _controller.setSelection(
      buffer.createAnchor(0, buffer.height - terminal.viewHeight),
      buffer.createAnchor(terminal.viewWidth, buffer.height - 1),
      mode: SelectionMode.line,
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // `translucent` so xterm's own primary-button drag-select
      // recogniser still receives the pointer alongside us —
      // `opaque` would consume all events and break selection.
      behavior: HitTestBehavior.translucent,
      onSecondaryTapUp: (details) => _onSecondaryTap(details, context),
      child: TerminalView(
        widget.terminal,
        controller: _controller,
        autofocus: false,
        hardwareKeyboardOnly: true,
        onKeyEvent: _handleKey,
        backgroundOpacity: 1.0,
        padding: const EdgeInsets.all(AppSpacing.xs),
        theme: AppTheme.terminalTheme,
        textStyle: TerminalStyle(
          fontSize: widget.fontSize,
          fontFamily: AppFonts.monoFamily,
        ),
      ),
    );
  }
}
