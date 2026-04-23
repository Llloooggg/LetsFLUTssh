import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import 'ssh_key_sequences.dart';

/// Virtual SSH keyboard bar — provides keys missing from mobile keyboards.
///
/// Sits above the system keyboard. Ctrl/Alt are sticky toggles:
/// tap once → active (highlighted), next key combines with modifier,
/// then modifier deactivates. Double-tap → lock on.
///
/// **Copy-mode swap.** When the user enters copy mode the main row
/// replaces the keys Row in-place with a copy-mode Row (hint text +
/// Copy + Cancel), keeping the outer `Container(height: itemHeightLg)`
/// constant. Swapping the *contents* — not the widget — is the load-
/// bearing invariant: any widget-tree height change would propagate
/// into the enclosing `MobileTerminalView` Column and force an
/// xterm `buffer.resize`, which reshuffles scrollback lines and was
/// the root cause of the recurring "mid-buffer gaps on copy toggle"
/// reports. The bar is also the single surface for the hint — no
/// separate banner over the terminal rows, so none of the terminal's
/// visible rows are ever covered.
class SshKeyboardBar extends StatefulWidget {
  /// Called when the bar produces input to send to the terminal.
  final void Function(String data) onInput;

  /// Called when the user taps the paste button.
  final VoidCallback? onPaste;

  /// Called when the user taps the snippets button.  When null the button
  /// is hidden — desktop / read-only views can keep the bar minimal.
  final VoidCallback? onSnippets;

  /// Called when the bar's copy-mode state flips. The parent drives
  /// the trackpad-style [TerminalCopyOverlay] on `true` and tears it
  /// down on `false`. The bar tracks active state so the main row
  /// swaps to the copy-mode variant while the mode is live.
  final ValueChanged<bool>? onCopyModeChanged;

  /// Called when the user taps the Copy action inside the copy-mode
  /// row. Only consulted while copy mode is active. Exiting copy
  /// mode after Copy is the parent's responsibility via
  /// [SshKeyboardBarState.exitCopyMode].
  final VoidCallback? onCopyPressed;

  /// Whether the overlay's selection anchor has been dropped. Drives
  /// the copy-mode hint copy between "tap to mark start" (no anchor
  /// yet) and "tap to extend" (anchor set). Defaults to `false`.
  final bool anchorSet;

  const SshKeyboardBar({
    super.key,
    required this.onInput,
    this.onPaste,
    this.onSnippets,
    this.onCopyModeChanged,
    this.onCopyPressed,
    this.anchorSet = false,
  });

  @override
  State<SshKeyboardBar> createState() => SshKeyboardBarState();
}

enum _ModifierState { off, once, locked }

class SshKeyboardBarState extends State<SshKeyboardBar> {
  _ModifierState _ctrl = _ModifierState.off;
  _ModifierState _alt = _ModifierState.off;
  bool _showFnKeys = false;
  bool _copyMode = false;

  /// Whether trackpad-style copy mode is active.
  bool get copyMode => _copyMode;

  /// Exit copy mode programmatically. Called by the parent after
  /// the user taps Copy (copy finished → close the session) or
  /// when any external teardown needs the bar back to normal.
  void exitCopyMode() {
    if (!_copyMode) return;
    setState(() => _copyMode = false);
    widget.onCopyModeChanged?.call(false);
  }

  /// Apply active Ctrl/Alt modifiers to [data] and consume one-shot modifiers.
  ///
  /// Used by [MobileTerminalView] to transform system keyboard input before
  /// sending it to the SSH shell.
  String applyModifiers(String data) {
    if (_ctrl == _ModifierState.off && _alt == _ModifierState.off) return data;
    String result = data;
    if (_alt != _ModifierState.off && data.length == 1) {
      result = SshKeySequences.altKey(data);
    }
    if (_ctrl != _ModifierState.off && data.length == 1) {
      result = SshKeySequences.ctrlKey(data);
    }
    if (_ctrl == _ModifierState.once) {
      setState(() => _ctrl = _ModifierState.off);
    }
    if (_alt == _ModifierState.once) setState(() => _alt = _ModifierState.off);
    return result;
  }

  void _send(String seq) {
    final data = applyModifiers(seq);
    widget.onInput(data);
  }

  void _toggleModifier(
    _ModifierState current,
    void Function(_ModifierState) set,
  ) {
    switch (current) {
      case _ModifierState.off:
        set(_ModifierState.once);
      case _ModifierState.once:
        set(_ModifierState.locked);
      case _ModifierState.locked:
        set(_ModifierState.off);
    }
  }

  void _enterCopyMode() {
    setState(() => _copyMode = true);
    widget.onCopyModeChanged?.call(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final barColor = theme.colorScheme.surfaceContainerLow;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // F-keys row — only in normal mode. In copy mode we collapse
        // to the single main row so the bar height does not grow /
        // shrink, which would otherwise resize the terminal above.
        if (_showFnKeys && !_copyMode)
          Container(
            height: AppTheme.barHeightLg,
            color: barColor,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              children: [
                for (int i = 0; i < 12; i++)
                  _KeyButton(
                    label: SshKeySequences.functionKeyNames[i],
                    onTap: () => _send(SshKeySequences.functionKeySequences[i]),
                  ),
              ],
            ),
          ),
        // Main row — height identical between the two content
        // variants so copy-mode toggling never changes the outer
        // bar size.
        Container(
          height: AppTheme.itemHeightLg,
          color: barColor,
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: _copyMode ? _buildCopyModeRow() : _buildNormalRow(),
        ),
      ],
    );
  }

  Widget _buildNormalRow() {
    return Row(
      children: [
        // Scrollable keys
        Expanded(
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _KeyButton(
                label: 'Esc',
                onTap: () => _send(SshKeySequences.escape),
              ),
              _KeyButton(label: 'Tab', onTap: () => _send(SshKeySequences.tab)),
              _ModifierButton(
                label: 'Ctrl',
                state: _ctrl,
                onTap: () =>
                    setState(() => _toggleModifier(_ctrl, (s) => _ctrl = s)),
              ),
              _ModifierButton(
                label: 'Alt',
                state: _alt,
                onTap: () =>
                    setState(() => _toggleModifier(_alt, (s) => _alt = s)),
              ),
              _KeyButton(
                icon: Icons.keyboard_arrow_left,
                onTap: () => _send(SshKeySequences.arrowLeft),
              ),
              _KeyButton(
                icon: Icons.keyboard_arrow_up,
                onTap: () => _send(SshKeySequences.arrowUp),
              ),
              _KeyButton(
                icon: Icons.keyboard_arrow_down,
                onTap: () => _send(SshKeySequences.arrowDown),
              ),
              _KeyButton(
                icon: Icons.keyboard_arrow_right,
                onTap: () => _send(SshKeySequences.arrowRight),
              ),
              _KeyButton(label: '|', onTap: () => _send('|')),
              _KeyButton(label: '~', onTap: () => _send('~')),
              _KeyButton(label: '/', onTap: () => _send('/')),
              _KeyButton(label: '-', onTap: () => _send('-')),
            ],
          ),
        ),
        if (widget.onSnippets != null)
          _KeyButton(icon: Icons.code, onTap: () => widget.onSnippets!.call()),
        _KeyButton(
          icon: Icons.paste,
          onTap: () {
            widget.onPaste?.call();
          },
        ),
        _KeyButton(icon: Icons.copy, onTap: _enterCopyMode),
        _KeyButton(
          label: 'Fn',
          isActive: _showFnKeys,
          onTap: () => setState(() => _showFnKeys = !_showFnKeys),
        ),
      ],
    );
  }

  Widget _buildCopyModeRow() {
    final l10n = S.of(context);
    final theme = Theme.of(context);
    final hint = widget.anchorSet
        ? l10n.copyModeExtending
        : l10n.copyModeTapToStart;
    return Row(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              hint,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: AppFonts.sm,
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
        _KeyButton(
          icon: Icons.copy,
          onTap: () {
            widget.onCopyPressed?.call();
          },
        ),
        _KeyButton(icon: Icons.close, onTap: exitCopyMode),
      ],
    );
  }
}

class _KeyButton extends StatelessWidget {
  final String? label;
  final IconData? icon;
  final VoidCallback onTap;
  final bool isActive;

  const _KeyButton({
    this.label,
    this.icon,
    required this.onTap,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1.5, vertical: 2),
      child: Material(
        color: isActive
            ? theme.colorScheme.primary.withValues(alpha: 0.3)
            : theme.colorScheme.surfaceContainerHigh,
        borderRadius: AppTheme.radiusLg,
        // `canRequestFocus: false` so tapping an `Esc`/`Tab`/`Ctrl`
        // key does not steal focus from the `TerminalView`, which
        // would dismiss the system keyboard mid-type. The xterm
        // input connection is tied to its internal `FocusNode`;
        // every InkWell tap would otherwise trip
        // `CustomTextEdit._onFocusChange → _closeInputConnection`
        // and the Gboard surface would slide away on every
        // modifier keypress.
        child: InkWell(
          canRequestFocus: false,
          onTap: () {
            HapticFeedback.lightImpact();
            onTap();
          },
          borderRadius: AppTheme.radiusLg,
          child: Container(
            constraints: const BoxConstraints(minWidth: 38),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            alignment: Alignment.center,
            child: icon != null
                ? Icon(icon, size: 20, color: theme.colorScheme.onSurface)
                : Text(
                    label!,
                    style: TextStyle(
                      fontSize: AppFonts.lg,
                      fontWeight: FontWeight.w500,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _ModifierButton extends StatelessWidget {
  final String label;
  final _ModifierState state;
  final VoidCallback onTap;

  const _ModifierButton({
    required this.label,
    required this.state,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Color bg;
    final Color fg;
    switch (state) {
      case _ModifierState.off:
        bg = theme.colorScheme.surfaceContainerHigh;
        fg = theme.colorScheme.onSurface;
      case _ModifierState.once:
        bg = theme.colorScheme.primary.withValues(alpha: 0.4);
        fg = theme.colorScheme.onSurface;
      case _ModifierState.locked:
        bg = theme.colorScheme.primary;
        fg = theme.colorScheme.onPrimary;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1.5, vertical: 2),
      child: Material(
        color: bg,
        borderRadius: AppTheme.radiusLg,
        // See `_KeyButton` — keep the system keyboard up when the
        // user toggles a sticky modifier.
        child: InkWell(
          canRequestFocus: false,
          onTap: () {
            HapticFeedback.lightImpact();
            onTap();
          },
          borderRadius: AppTheme.radiusLg,
          child: Container(
            constraints: const BoxConstraints(minWidth: 42),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                fontSize: AppFonts.lg,
                fontWeight: FontWeight.w600,
                color: fg,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
