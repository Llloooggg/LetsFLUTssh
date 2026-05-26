/// Cell attribute bit layout, mirroring `alacritty_terminal`'s
/// `term::cell::Flags` bitfield. The Rust engine widens the `u16`
/// bitfield to `u32` and hands it to the renderer untouched
/// (`TerminalCell.flags`), so the renderer must test the same bits the
/// upstream crate defines. Keep in lock-step with
/// `alacritty_terminal-0.26.0/src/term/cell.rs` — a divergence here
/// silently mis-styles glyphs (e.g. testing the wrong bit paints bold
/// as italic).
///
/// Only the bits the renderer acts on are named; the underline-variant
/// and wrap bits are not consumed by the cell-grid painter and are left
/// out deliberately rather than padded with dead constants.
library;

/// Inverse video. Already resolved Rust-side into swapped `fg`/`bg`, so
/// the renderer does not test it — named here for completeness with the
/// upstream layout.
const int kCellFlagInverse = 0x0001;

/// Bold weight (`SGR 1`).
const int kCellFlagBold = 0x0002;

/// Italic (`SGR 3`).
const int kCellFlagItalic = 0x0004;

/// Single underline (`SGR 4`).
const int kCellFlagUnderline = 0x0008;

/// Leading half of a double-width character. The cell occupies two
/// columns; its spacer half is omitted from the sparse frame, so the
/// painter advances by two columns' worth of glyph for this cell.
const int kCellFlagWideChar = 0x0020;

/// Faint / dim (`SGR 2`). Already folded into a darker `fg` Rust-side,
/// so the painter does not re-dim — named for completeness.
const int kCellFlagDim = 0x0080;

/// Concealed (`SGR 8`). The glyph is suppressed; the background still
/// paints.
const int kCellFlagHidden = 0x0100;

/// Strikethrough (`SGR 9`).
const int kCellFlagStrikeout = 0x0200;

/// Decoded, render-relevant subset of a cell's attribute flags. INVERSE
/// and DIM are intentionally absent: the Rust engine resolves both into
/// the concrete `fg`/`bg` it hands the renderer, so re-applying them
/// Dart-side would double the effect.
class TerminalCellFlags {
  const TerminalCellFlags({
    required this.bold,
    required this.italic,
    required this.underline,
    required this.strikeout,
    required this.hidden,
    required this.wide,
  });

  /// Decode the raw `alacritty_terminal` bitfield into the render-flags
  /// the painter consumes.
  factory TerminalCellFlags.fromBits(int flags) => TerminalCellFlags(
    bold: flags & kCellFlagBold != 0,
    italic: flags & kCellFlagItalic != 0,
    underline: flags & kCellFlagUnderline != 0,
    strikeout: flags & kCellFlagStrikeout != 0,
    hidden: flags & kCellFlagHidden != 0,
    wide: flags & kCellFlagWideChar != 0,
  );

  final bool bold;
  final bool italic;
  final bool underline;
  final bool strikeout;
  final bool hidden;
  final bool wide;
}
