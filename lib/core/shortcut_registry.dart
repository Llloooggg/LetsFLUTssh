import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Every app-level keyboard shortcut with its default key binding.
///
/// Shortcuts are grouped by context (global, terminal, file browser, session
/// panel, dialog). The [AppShortcutRegistry] class maps each value to its
/// binding — initially the default, but designed for future user overrides.
enum AppShortcut {
  // ── Global ──────────────────────────────────────────────────────────────
  newSession(SingleActivator(LogicalKeyboardKey.keyN, control: true)),
  closeTab(SingleActivator(LogicalKeyboardKey.keyW, control: true)),
  nextTab(SingleActivator(LogicalKeyboardKey.tab, control: true)),
  prevTab(SingleActivator(LogicalKeyboardKey.tab, control: true, shift: true)),
  toggleSidebar(SingleActivator(LogicalKeyboardKey.keyB, control: true)),
  splitRight(SingleActivator(LogicalKeyboardKey.backslash, control: true)),
  splitDown(
    SingleActivator(LogicalKeyboardKey.backslash, control: true, shift: true),
  ),
  openSettings(SingleActivator(LogicalKeyboardKey.comma, control: true)),
  closeSettings(SingleActivator(LogicalKeyboardKey.escape)),

  // ── Terminal ────────────────────────────────────────────────────────────
  terminalCopy(
    SingleActivator(LogicalKeyboardKey.keyC, control: true, shift: true),
  ),
  terminalPaste(
    SingleActivator(LogicalKeyboardKey.keyV, control: true, shift: true),
  ),
  terminalSearch(
    SingleActivator(LogicalKeyboardKey.keyF, control: true, shift: true),
  ),
  terminalCloseSearch(SingleActivator(LogicalKeyboardKey.escape)),
  zoomIn(SingleActivator(LogicalKeyboardKey.equal, control: true)),
  zoomOut(SingleActivator(LogicalKeyboardKey.minus, control: true)),
  zoomReset(SingleActivator(LogicalKeyboardKey.digit0, control: true)),

  // ── File browser ────────────────────────────────────────────────────────
  fileSelectAll(SingleActivator(LogicalKeyboardKey.keyA, control: true)),
  fileCopy(SingleActivator(LogicalKeyboardKey.keyC, control: true)),
  filePaste(SingleActivator(LogicalKeyboardKey.keyV, control: true)),
  fileDelete(SingleActivator(LogicalKeyboardKey.delete)),
  fileRename(SingleActivator(LogicalKeyboardKey.f2)),
  fileRefresh(SingleActivator(LogicalKeyboardKey.f5)),

  // ── Session panel ──────────────────────────────────────────────────────
  sessionUndo(SingleActivator(LogicalKeyboardKey.keyZ, control: true)),
  sessionRedo(SingleActivator(LogicalKeyboardKey.keyY, control: true)),
  sessionCopy(SingleActivator(LogicalKeyboardKey.keyC, control: true)),
  sessionPaste(SingleActivator(LogicalKeyboardKey.keyV, control: true)),
  sessionDelete(SingleActivator(LogicalKeyboardKey.delete)),
  sessionEdit(SingleActivator(LogicalKeyboardKey.f2)),

  // ── Dialog ─────────────────────────────────────────────────────────────
  dismissDialog(SingleActivator(LogicalKeyboardKey.escape));

  const AppShortcut(this.defaultBinding);

  /// The default key combination for this shortcut.
  final SingleActivator defaultBinding;
}

/// Central registry that maps [AppShortcut] values to their current key
/// bindings. Initially every shortcut uses its [AppShortcut.defaultBinding].
///
/// Consumers use [buildCallbackMap] for `CallbackShortcuts` widgets and
/// [matches] for raw `onKeyEvent` handlers (e.g. inside xterm).
class AppShortcutRegistry {
  AppShortcutRegistry._();

  static final instance = AppShortcutRegistry._();

  final Map<AppShortcut, SingleActivator> _bindings = {
    for (final s in AppShortcut.values) s: s.defaultBinding,
  };

  /// Returns the current binding for [shortcut].
  SingleActivator binding(AppShortcut shortcut) => _bindings[shortcut]!;

  /// Builds a map suitable for [CallbackShortcuts.bindings].
  ///
  /// ```dart
  /// CallbackShortcuts(
  ///   bindings: AppShortcutRegistry.instance.buildCallbackMap({
  ///     AppShortcut.newSession: () => _newSession(),
  ///   }),
  ///   child: …,
  /// )
  /// ```
  Map<ShortcutActivator, VoidCallback> buildCallbackMap(
    Map<AppShortcut, VoidCallback> actions,
  ) {
    return {
      for (final entry in actions.entries) _bindings[entry.key]!: entry.value,
    };
  }

  /// Returns `true` when [event] matches the current binding for [shortcut].
  ///
  /// Use this in `onKeyEvent` handlers where `CallbackShortcuts` cannot
  /// intercept events (e.g. inside xterm's `TerminalView`).
  ///
  /// Unlike [SingleActivator.accepts], only the required modifiers are
  /// checked — extra modifiers (alt / meta) are tolerated. This matches the
  /// original hand-written handlers and avoids false negatives on platforms
  /// where a phantom modifier flag can appear (e.g. WSLg).
  bool matches(AppShortcut shortcut, KeyEvent event) {
    final b = _bindings[shortcut]!;
    if (event.logicalKey != b.trigger) return false;
    final hw = HardwareKeyboard.instance;
    if (b.control != hw.isControlPressed) return false;
    if (b.shift != hw.isShiftPressed) return false;
    return true;
  }
}
