/// Escape sequences for SSH-specific keys on the virtual keyboard.
///
/// Standard VT100/VT220/xterm sequences for keys that don't exist
/// on mobile software keyboards.
abstract final class SshKeySequences {
  static const String escape = '\x1b';
  static const String tab = '\x09';
  static const String backspace = '\x7f';
  static const String enter = '\r';
  static const String delete = '\x1b[3~';

  // Arrow keys
  static const String arrowUp = '\x1b[A';
  static const String arrowDown = '\x1b[B';
  static const String arrowRight = '\x1b[C';
  static const String arrowLeft = '\x1b[D';

  // Navigation
  static const String home = '\x1b[H';
  static const String end = '\x1b[F';
  static const String pageUp = '\x1b[5~';
  static const String pageDown = '\x1b[6~';
  static const String insert = '\x1b[2~';

  // Function keys (VT220 sequences)
  static const String f1 = '\x1bOP';
  static const String f2 = '\x1bOQ';
  static const String f3 = '\x1bOR';
  static const String f4 = '\x1bOS';
  static const String f5 = '\x1b[15~';
  static const String f6 = '\x1b[17~';
  static const String f7 = '\x1b[18~';
  static const String f8 = '\x1b[19~';
  static const String f9 = '\x1b[20~';
  static const String f10 = '\x1b[21~';
  static const String f11 = '\x1b[23~';
  static const String f12 = '\x1b[24~';

  /// Apply Ctrl modifier to a character.
  /// Ctrl+A = 0x01, Ctrl+C = 0x03, etc.
  static String ctrlKey(String char) {
    if (char.isEmpty) return '';
    final code = char.toUpperCase().codeUnitAt(0);
    if (code >= 0x40 && code <= 0x5F) {
      return String.fromCharCode(code & 0x1F);
    }
    return char;
  }

  /// Apply Alt modifier to a character (ESC prefix).
  static String altKey(String char) {
    if (char.isEmpty) return '';
    return '\x1b$char';
  }

  static const List<String> functionKeyNames = [
    'F1',
    'F2',
    'F3',
    'F4',
    'F5',
    'F6',
    'F7',
    'F8',
    'F9',
    'F10',
    'F11',
    'F12',
  ];

  static const List<String> functionKeySequences = [
    f1,
    f2,
    f3,
    f4,
    f5,
    f6,
    f7,
    f8,
    f9,
    f10,
    f11,
    f12,
  ];
}
