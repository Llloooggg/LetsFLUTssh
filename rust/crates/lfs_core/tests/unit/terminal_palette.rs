/// Unit tests extracted from terminal/palette.rs
/// Declared via `#[path] mod tests;` in the source file.
use super::*;

#[test]
fn indexed_first_16_hit_ansi_table() {
    // Spec: indices 0..16 of the 256-palette are exactly the ANSI base
    // colors — index N must equal ansi[N], never the cube.
    let p = TermPalette::one_dark();
    for i in 0..16u8 {
        assert_eq!(p.indexed(i), p.ansi[i as usize]);
    }
}

#[test]
fn indexed_cube_corners() {
    // Spec: the 6x6x6 cube channel steps are 0,95,135,175,215,255.
    // Index 16 is the cube origin (all channels at step 0 => black);
    // index 231 is the cube's far corner (all channels at step 5 => white).
    let p = TermPalette::one_dark();
    assert_eq!(p.indexed(16), Rgb::new(0, 0, 0));
    assert_eq!(p.indexed(231), Rgb::new(255, 255, 255));
    // Pure red corner: r at step 5, g/b at step 0 => index 16 + 5*36.
    assert_eq!(p.indexed(16 + 5 * 36), Rgb::new(255, 0, 0));
}

#[test]
fn indexed_grayscale_ramp() {
    // Spec: indices 232..256 are a 24-step gray ramp from 8 to 238,
    // stepping by 10, with R==G==B at each step.
    let p = TermPalette::one_dark();
    assert_eq!(p.indexed(232), Rgb::new(8, 8, 8));
    assert_eq!(p.indexed(255), Rgb::new(238, 238, 238));
}

#[test]
fn dim_halves_channels() {
    // Spec: SGR DIM produces a faint color — each channel halved.
    assert_eq!(dim(Rgb::new(200, 100, 50)), Rgb::new(100, 50, 25));
}

#[test]
fn named_semantic_colors() {
    // Spec: the semantic Named entries map to the palette's named
    // swatches, not to an ANSI index.
    let p = TermPalette::one_dark();
    assert_eq!(p.named(NamedColor::Foreground), p.foreground);
    assert_eq!(p.named(NamedColor::Background), p.background);
    assert_eq!(p.named(NamedColor::Red), p.ansi[1]);
}
