import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme.dart';
import 'ssh_key_sequences.dart';

/// Virtual SSH keyboard bar — provides keys missing from mobile keyboards.
///
/// Sits above the system keyboard. Ctrl/Alt are sticky toggles:
/// tap once → active (highlighted), next key combines with modifier,
/// then modifier deactivates. Double-tap → lock on.
class SshKeyboardBar extends StatefulWidget {
  /// Called when the bar produces input to send to the terminal.
  final void Function(String data) onInput;

  /// Called when the user taps the paste button.
  final VoidCallback? onPaste;

  /// Called when text-select mode is toggled on/off.
  final ValueChanged<bool>? onSelectModeChanged;

  const SshKeyboardBar({
    super.key,
    required this.onInput,
    this.onPaste,
    this.onSelectModeChanged,
  });

  @override
  State<SshKeyboardBar> createState() => SshKeyboardBarState();
}

enum _ModifierState { off, once, locked }

class SshKeyboardBarState extends State<SshKeyboardBar> {
  _ModifierState _ctrl = _ModifierState.off;
  _ModifierState _alt = _ModifierState.off;
  bool _showFnKeys = false;
  bool _selectMode = false;

  /// Whether text-select mode is active.
  bool get selectMode => _selectMode;

  /// Exit text-select mode programmatically (e.g. after copy).
  void exitSelectMode() {
    if (!_selectMode) return;
    setState(() => _selectMode = false);
    widget.onSelectModeChanged?.call(false);
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
    if (_ctrl == _ModifierState.once) setState(() => _ctrl = _ModifierState.off);
    if (_alt == _ModifierState.once) setState(() => _alt = _ModifierState.off);
    return result;
  }

  void _send(String seq) {
    final data = applyModifiers(seq);
    widget.onInput(data);
  }

  void _toggleModifier(_ModifierState current, void Function(_ModifierState) set) {
    switch (current) {
      case _ModifierState.off:
        set(_ModifierState.once);
      case _ModifierState.once:
        set(_ModifierState.locked);
      case _ModifierState.locked:
        set(_ModifierState.off);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final barColor = theme.colorScheme.surfaceContainerLow;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // F-keys row (expandable)
        if (_showFnKeys)
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
        // Main row
        Container(
          height: AppTheme.itemHeightLg,
          color: barColor,
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Row(
            children: [
              // Scrollable keys
              Expanded(
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _KeyButton(label: 'Esc', onTap: () => _send(SshKeySequences.escape)),
                    _KeyButton(label: 'Tab', onTap: () => _send(SshKeySequences.tab)),
                    _ModifierButton(
                      label: 'Ctrl',
                      state: _ctrl,
                      onTap: () => setState(() => _toggleModifier(
                        _ctrl, (s) => _ctrl = s,
                      )),
                    ),
                    _ModifierButton(
                      label: 'Alt',
                      state: _alt,
                      onTap: () => setState(() => _toggleModifier(
                        _alt, (s) => _alt = s,
                      )),
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
              // Paste + Select + Fn toggles — fixed at right edge, always visible
              _KeyButton(
                icon: Icons.paste,
                onTap: () {
                  widget.onPaste?.call();
                },
              ),
              _KeyButton(
                icon: Icons.select_all,
                isActive: _selectMode,
                onTap: () {
                  setState(() => _selectMode = !_selectMode);
                  widget.onSelectModeChanged?.call(_selectMode);
                },
              ),
              _KeyButton(
                label: 'Fn',
                isActive: _showFnKeys,
                onTap: () => setState(() => _showFnKeys = !_showFnKeys),
              ),
            ],
          ),
        ),
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
        child: InkWell(
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
        child: InkWell(
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
