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
  maximizePanel(
    SingleActivator(LogicalKeyboardKey.keyM, control: true, shift: true),
  ),
  openSettings(SingleActivator(LogicalKeyboardKey.comma, control: true)),

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
  sessionCut(SingleActivator(LogicalKeyboardKey.keyX, control: true)),
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
  ///
  /// Throws [StateError] when two requested shortcuts resolve to the
  /// same [SingleActivator]. Several [AppShortcut] values intentionally
  /// share activators (e.g. `sessionCopy` + `fileCopy` both bind Ctrl+C;
  /// `sessionEdit` + `fileRename` both bind F2) because each is meant
  /// for a different widget subtree — the caller mounts each
  /// `CallbackShortcuts` under the scope that should receive it, never
  /// both together. If a caller ever did collide them into one map the
  /// output would silently coalesce to the last-written entry, turning
  /// one of the shortcuts into a no-op with no error message. Failing
  /// loud here keeps that regression visible.
  Map<ShortcutActivator, VoidCallback> buildCallbackMap(
    Map<AppShortcut, VoidCallback> actions,
  ) {
    final out = <ShortcutActivator, VoidCallback>{};
    final origins = <SingleActivator, AppShortcut>{};
    for (final entry in actions.entries) {
      final activator = _bindings[entry.key]!;
      final prior = origins[activator];
      if (prior != null) {
        throw StateError(
          'Duplicate shortcut activator ${formatShortcut(activator)}: '
          '${prior.name} and ${entry.key.name} both resolve to the same '
          'binding. Mount them under separate CallbackShortcuts scopes.',
        );
      }
      origins[activator] = entry.key;
      out[activator] = entry.value;
    }
    return out;
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

  /// Human-readable label for the current binding of [shortcut]
  /// (e.g. `Ctrl+Shift+V`, `F2`, `Delete`).
  ///
  /// Used by the context-menu factory so the shortcut hint always
  /// reflects the live binding — hardcoded strings like "Ctrl+V" in
  /// menus drift the moment a binding changes (the terminal copy/paste
  /// bug that triggered this helper: the menu advertised `Ctrl+V` while
  /// the real bind was `Ctrl+Shift+V`).
  String shortcutLabel(AppShortcut shortcut) =>
      formatShortcut(_bindings[shortcut]!);
}

/// Format a [SingleActivator] as a display string like `Ctrl+Shift+V`.
///
/// Modifier order: Ctrl, Alt, Shift, Meta — the GTK / Windows / macOS
/// convention. Key glyph mirrors what the user sees on the cap.
String formatShortcut(SingleActivator a) {
  final parts = <String>[];
  if (a.control) parts.add('Ctrl');
  if (a.alt) parts.add('Alt');
  if (a.shift) parts.add('Shift');
  if (a.meta) parts.add('Meta');
  parts.add(_keyLabel(a.trigger));
  return parts.join('+');
}

String _keyLabel(LogicalKeyboardKey key) {
  // Named keys whose `keyLabel` is empty or reads worse than the usual
  // "cap" glyph (navigation keys, Esc, Tab, …). Map is rebuilt per call
  // because `LogicalKeyboardKey` has a custom `==`/`hashCode` and can't
  // key a const map — the method runs only when rendering a context
  // menu, so cost is negligible.
  final named = <LogicalKeyboardKey, String>{
    LogicalKeyboardKey.escape: 'Esc',
    LogicalKeyboardKey.enter: 'Enter',
    LogicalKeyboardKey.tab: 'Tab',
    LogicalKeyboardKey.space: 'Space',
    LogicalKeyboardKey.backspace: 'Backspace',
    LogicalKeyboardKey.delete: 'Delete',
    LogicalKeyboardKey.arrowUp: '↑',
    LogicalKeyboardKey.arrowDown: '↓',
    LogicalKeyboardKey.arrowLeft: '←',
    LogicalKeyboardKey.arrowRight: '→',
  };
  final mapped = named[key];
  if (mapped != null) return mapped;
  // Function keys (F1..F12) + printable chars: `keyLabel` is set.
  final kl = key.keyLabel;
  if (kl.isNotEmpty) return kl.toUpperCase();
  return key.debugName ?? key.toString();
}
