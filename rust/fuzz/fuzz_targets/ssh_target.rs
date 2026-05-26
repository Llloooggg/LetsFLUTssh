//! Coverage-guided fuzzer for
//! `lfs_core::sessions::parse_ssh_target`.
//!
//! Drives raw bytes from the fuzzer through `String::from_utf8_lossy`
//! into the parser. The parser is `pub fn parse_ssh_target(input:
//! &str) -> Option<SshTarget>` — pure, no I/O, fail-closed on every
//! malformed shape (rejects empty input, control chars in host /
//! user, oversized fields, out-of-range port, bare `@` with no user
//! prefix, unterminated IPv6 brackets). Asserts "no panic" — every
//! `Some` result must additionally satisfy the contract bounds the
//! parser documents.
//!
//! Not run in CI (cargo-fuzz needs nightly + a separate corpus dir)
//! but lives in-tree so a maintainer running
//! `cargo +nightly fuzz run ssh_target` against this target gets
//! immediate coverage on the session-edit smart-paste parser.

#![no_main]

use lfs_core::sessions::parse_ssh_target;
use libfuzzer_sys::fuzz_target;

fuzz_target!(|data: &[u8]| {
    let s = String::from_utf8_lossy(data);
    let result = parse_ssh_target(&s);
    if let Some(target) = result {
        // Contract: parser only returns Some when the bounds hold.
        // Anything else is a parser bug — catch it here so fuzzing
        // surfaces the regression rather than letting bad data
        // through to the connect path.
        assert!(!target.host.is_empty());
        assert!(target.host.len() <= 253);
        assert!(!target.host.contains('/') && !target.host.contains('\\'));
        if let Some(user) = target.user.as_deref() {
            assert!(!user.is_empty());
            assert!(user.len() <= 256);
            assert!(!user.contains('/') && !user.contains('\\'));
            for b in user.bytes() {
                assert!(
                    b >= 0x20 && !(0x7F..=0x9F).contains(&b),
                    "control char in user"
                );
            }
        }
        for b in target.host.bytes() {
            assert!(
                b >= 0x20 && !(0x7F..=0x9F).contains(&b),
                "control char in host"
            );
        }
        if let Some(port) = target.port {
            // SmallInt = u16, so the upper bound is enforced by the
            // type; the lower bound is the parser's contract.
            assert!(port >= 1);
        }
    }
});
