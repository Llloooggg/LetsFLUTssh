import 'package:flutter/services.dart';

import '../../src/rust/api/terminal.dart' as rust_terminal;

/// Pure mapping from a Flutter [KeyEvent] to the Rust-side
/// [rust_terminal.TerminalKey] descriptor, or `null` when the event should
/// not be forwarded to the shell (a bare modifier press, an unmappable
/// special key, or a key with no character and no recognised logical key).
///
/// Why pure + standalone: the VT byte encoding lives Rust-side (it reads
/// the live terminal mode), so Dart only normalises the platform event
/// into a logical key + modifier bools. Keeping that normalisation in a
/// free function makes it unit-testable without a live `TerminalSession`
/// (whose `sendKey` reaches into FFI).
///
/// Modifiers are read from the passed [pressedKeys] set (the caller hands
/// in `HardwareKeyboard.instance.logicalKeysPressed`) rather than from the
/// event so a held modifier is reflected even when the event itself is the
/// non-modifier key. `meta` (Command / Windows / Super) is carried but the
/// Rust encoder does not fold it into the byte stream — it drives app
/// shortcuts, not PTY bytes.
rust_terminal.TerminalKey? terminalKeyFromEvent(
  KeyEvent event,
  Set<LogicalKeyboardKey> pressedKeys,
) {
  final ctrl = _anyPressed(pressedKeys, _ctrlKeys);
  final alt = _anyPressed(pressedKeys, _altKeys);
  final shift = _anyPressed(pressedKeys, _shiftKeys);
  final meta = _anyPressed(pressedKeys, _metaKeys);

  final name = _keyName(event, ctrl);
  if (name == null) return null;

  return rust_terminal.TerminalKey(
    name: name,
    ctrl: ctrl,
    alt: alt,
    shift: shift,
    meta: meta,
  );
}

/// Resolve the logical key name. Named special keys win over the typed
/// character (Enter/Tab/etc. also carry a control character); a printable
/// character maps to `Char`. Returns `null` for a bare modifier press or an
/// event with neither a recognised logical key nor a printable character.
rust_terminal.TerminalKeyName? _keyName(KeyEvent event, bool ctrl) {
  final special = _specialKeys[event.logicalKey];
  if (special != null) return special;

  final fnNumber = _functionNumber(event.logicalKey);
  if (fnNumber != null) {
    return rust_terminal.TerminalKeyName.f(number: fnNumber);
  }

  if (_modifierKeys.contains(event.logicalKey)) return null;

  // A printable character. Under Ctrl, `event.character` is often empty
  // (Ctrl+C produces no text) — fall back to the logical key's label so
  // the control combo still resolves to its letter.
  final ch = _printableChar(event, ctrl);
  if (ch == null) return null;
  return rust_terminal.TerminalKeyName.char(code: ch);
}

/// The scalar to encode as a `Char`, or `null` when the event carries no
/// printable input. Prefers `event.character` (already case- and
/// layout-resolved); under Ctrl, where the character is typically empty,
/// falls back to the logical key label so Ctrl+letter resolves.
int? _printableChar(KeyEvent event, bool ctrl) {
  final character = event.character;
  if (character != null && character.isNotEmpty) {
    final scalar = character.runes.first;
    // Drop C0 control characters (Flutter sometimes reports them as the
    // character for control combos) — the encoder derives the control
    // byte from the logical letter instead.
    if (scalar >= 0x20 && scalar != 0x7f) return scalar;
  }
  if (ctrl) {
    final label = event.logicalKey.keyLabel;
    if (label.length == 1) return label.toLowerCase().runes.first;
  }
  return null;
}

/// F1–F12 number for a function logical key, or `null` if not a function
/// key in that range.
int? _functionNumber(LogicalKeyboardKey key) {
  for (var n = 1; n <= 12; n++) {
    if (key == _functionKeys[n - 1]) return n;
  }
  return null;
}

bool _anyPressed(Set<LogicalKeyboardKey> pressed, List<LogicalKeyboardKey> of) {
  for (final k in of) {
    if (pressed.contains(k)) return true;
  }
  return false;
}

const List<LogicalKeyboardKey> _ctrlKeys = [
  LogicalKeyboardKey.controlLeft,
  LogicalKeyboardKey.controlRight,
  LogicalKeyboardKey.control,
];
const List<LogicalKeyboardKey> _altKeys = [
  LogicalKeyboardKey.altLeft,
  LogicalKeyboardKey.altRight,
  LogicalKeyboardKey.alt,
];
const List<LogicalKeyboardKey> _shiftKeys = [
  LogicalKeyboardKey.shiftLeft,
  LogicalKeyboardKey.shiftRight,
  LogicalKeyboardKey.shift,
];
const List<LogicalKeyboardKey> _metaKeys = [
  LogicalKeyboardKey.metaLeft,
  LogicalKeyboardKey.metaRight,
  LogicalKeyboardKey.meta,
];

/// Every modifier key — a bare press of one of these produces no PTY bytes.
final Set<LogicalKeyboardKey> _modifierKeys = {
  ..._ctrlKeys,
  ..._altKeys,
  ..._shiftKeys,
  ..._metaKeys,
  LogicalKeyboardKey.capsLock,
  LogicalKeyboardKey.numLock,
  LogicalKeyboardKey.scrollLock,
};

const List<LogicalKeyboardKey> _functionKeys = [
  LogicalKeyboardKey.f1,
  LogicalKeyboardKey.f2,
  LogicalKeyboardKey.f3,
  LogicalKeyboardKey.f4,
  LogicalKeyboardKey.f5,
  LogicalKeyboardKey.f6,
  LogicalKeyboardKey.f7,
  LogicalKeyboardKey.f8,
  LogicalKeyboardKey.f9,
  LogicalKeyboardKey.f10,
  LogicalKeyboardKey.f11,
  LogicalKeyboardKey.f12,
];

/// Named special keys → their logical-key descriptor. Resolved before the
/// printable-character path so Enter/Tab/Backspace (which also carry a
/// control character) map to their dedicated encoding.
final Map<LogicalKeyboardKey, rust_terminal.TerminalKeyName> _specialKeys = {
  LogicalKeyboardKey.enter: const rust_terminal.TerminalKeyName.enter(),
  LogicalKeyboardKey.numpadEnter: const rust_terminal.TerminalKeyName.enter(),
  LogicalKeyboardKey.tab: const rust_terminal.TerminalKeyName.tab(),
  LogicalKeyboardKey.backspace: const rust_terminal.TerminalKeyName.backspace(),
  LogicalKeyboardKey.escape: const rust_terminal.TerminalKeyName.escape(),
  LogicalKeyboardKey.arrowUp: const rust_terminal.TerminalKeyName.up(),
  LogicalKeyboardKey.arrowDown: const rust_terminal.TerminalKeyName.down(),
  LogicalKeyboardKey.arrowRight: const rust_terminal.TerminalKeyName.right(),
  LogicalKeyboardKey.arrowLeft: const rust_terminal.TerminalKeyName.left(),
  LogicalKeyboardKey.home: const rust_terminal.TerminalKeyName.home(),
  LogicalKeyboardKey.end: const rust_terminal.TerminalKeyName.end(),
  LogicalKeyboardKey.pageUp: const rust_terminal.TerminalKeyName.pageUp(),
  LogicalKeyboardKey.pageDown: const rust_terminal.TerminalKeyName.pageDown(),
  LogicalKeyboardKey.insert: const rust_terminal.TerminalKeyName.insert(),
  LogicalKeyboardKey.delete: const rust_terminal.TerminalKeyName.delete(),
};
