/// Unit tests extracted from id.rs
/// Declared via `#[path] mod tests;` in the source file.
use super::*;

#[test]
fn handle_hex_32_has_correct_shape() {
    let id = random_handle_hex_32();
    assert_eq!(id.len(), 32, "handle id must be 32 chars");
    assert!(
        id.bytes()
            .all(|b| b.is_ascii_hexdigit() && !b.is_ascii_uppercase()),
        "handle id must be lowercase hex only: {id}"
    );
}

#[test]
fn handle_hex_32_is_unique_across_calls() {
    // 16 random bytes → 2^128 space; collision probability
    // across 1000 calls is negligible. The assertion would
    // catch a stuck OsRng or a deduped const.
    let a = random_handle_hex_32();
    let b = random_handle_hex_32();
    assert_ne!(a, b);
}

#[test]
fn uuid_v4_has_correct_shape() {
    let id = random_uuid_v4();
    // 8-4-4-4-12 hyphenated form
    assert_eq!(id.len(), 36, "uuid v4 must be 36 chars");
    let parts: Vec<&str> = id.split('-').collect();
    assert_eq!(parts.len(), 5);
    assert_eq!(parts[0].len(), 8);
    assert_eq!(parts[1].len(), 4);
    assert_eq!(parts[2].len(), 4);
    assert_eq!(parts[3].len(), 4);
    assert_eq!(parts[4].len(), 12);
    // Version nibble at byte index 14 must be '4' for v4.
    assert_eq!(id.as_bytes()[14], b'4', "uuid version must be 4");
}

#[test]
fn uuid_v4_is_unique_across_calls() {
    let a = random_uuid_v4();
    let b = random_uuid_v4();
    assert_ne!(a, b);
}
