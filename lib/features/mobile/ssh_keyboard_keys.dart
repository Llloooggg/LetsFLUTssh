import '../../src/rust/api/terminal.dart' as rust_terminal;

/// Pure mapping from the mobile SSH keyboard bar's on-bar keys to the
/// Rust-side [rust_terminal.TerminalKey] descriptor.
///
/// Why a logical key, not pre-encoded bytes: the new terminal engine
/// encodes VT bytes Rust-side against the live terminal mode (arrows flip
/// to SS3 under DECCKM, Enter to CR+LF under LNM, …). Producing a
/// [rust_terminal.TerminalKey] here and letting `TerminalSession.sendKey`
/// encode it keeps the mobile bar in step with the desktop pane — both
/// feed the same encoder — instead of the bar shipping a second copy of the
/// VT byte tables. The sticky Ctrl / Alt modifiers the bar tracks fold into
/// the key's modifier flags so `Ctrl+C` from the bar lands as a real SIGINT
/// and `Alt+x` as a meta sequence.
///
/// Kept pure + standalone so the mapping is unit-testable without a live
/// `TerminalSession` (whose `sendKey` reaches into FFI).

/// Build a printable-character key (`|`, `~`, `/`, `-`, …) with the given
/// sticky modifiers folded in. The character is a single Unicode scalar.
rust_terminal.TerminalKey charKey(
  String ch, {
  bool ctrl = false,
  bool alt = false,
}) {
  return rust_terminal.TerminalKey(
    name: rust_terminal.TerminalKeyName.char(code: ch.runes.first),
    ctrl: ctrl,
    alt: alt,
    shift: false,
    meta: false,
  );
}

/// Build a named-key press (Esc, Tab, an arrow, a function key, …) with the
/// given sticky modifiers folded in.
rust_terminal.TerminalKey namedKey(
  rust_terminal.TerminalKeyName name, {
  bool ctrl = false,
  bool alt = false,
}) {
  return rust_terminal.TerminalKey(
    name: name,
    ctrl: ctrl,
    alt: alt,
    shift: false,
    meta: false,
  );
}

/// The named keys the bar offers, by their logical role. Function keys are
/// built on demand via [rust_terminal.TerminalKeyName.f].
abstract final class SshBarKeys {
  static const escape = rust_terminal.TerminalKeyName.escape();
  static const tab = rust_terminal.TerminalKeyName.tab();
  static const arrowUp = rust_terminal.TerminalKeyName.up();
  static const arrowDown = rust_terminal.TerminalKeyName.down();
  static const arrowLeft = rust_terminal.TerminalKeyName.left();
  static const arrowRight = rust_terminal.TerminalKeyName.right();

  /// Function-key descriptor for `F<number>` (1..12). The Rust encoder
  /// drops out-of-range numbers, so the bar passes 1..12 directly.
  static rust_terminal.TerminalKeyName function(int number) =>
      rust_terminal.TerminalKeyName.f(number: number);
}
