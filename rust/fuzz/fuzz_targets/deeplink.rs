//! Coverage-guided fuzzer for `lfs_core::deeplink::parse_connect_uri`.
//!
//! Drives raw bytes from the fuzzer through `String::from_utf8_lossy`
//! into the parser. The parser is `pub fn parse_connect_uri(uri:
//! &str) -> Option<ConnectLink>` — pure, no I/O, fail-closed on
//! every malformed shape (rejects non-letsflutssh schemes, control
//! chars in host/user, oversized fields, malformed query). Asserts
//! "no panic" — every Some result must additionally satisfy the
//! contract bounds the parser documents.
//!
//! Not run in CI (cargo-fuzz needs nightly + a separate corpus dir)
//! but lives in-tree so a maintainer running
//! `cargo +nightly fuzz run deeplink` against this target gets
//! immediate coverage on the deeplink parser.

#![no_main]

use lfs_core::deeplink::parse_connect_uri;
use libfuzzer_sys::fuzz_target;

fuzz_target!(|data: &[u8]| {
    let s = String::from_utf8_lossy(data);
    let result = parse_connect_uri(&s);
    if let Some(link) = result {
        // Contract: parser only returns Some when the bounds hold.
        // Anything else is a parser bug — catch it here so
        // fuzzing surfaces the regression rather than letting
        // bad data through.
        assert!(!link.host.is_empty());
        assert!(!link.user.is_empty());
        assert!(link.host.len() <= 253);
        assert!(link.user.len() <= 256);
        assert!(link.port >= 1);
        assert!(!link.host.contains('/') && !link.host.contains('\\'));
        assert!(!link.user.contains('/') && !link.user.contains('\\'));
        for b in link.host.bytes() {
            assert!(
                b >= 0x20 && !(0x7F..=0x9F).contains(&b),
                "control char in host"
            );
        }
        for b in link.user.bytes() {
            assert!(
                b >= 0x20 && !(0x7F..=0x9F).contains(&b),
                "control char in user"
            );
        }
    }
});
