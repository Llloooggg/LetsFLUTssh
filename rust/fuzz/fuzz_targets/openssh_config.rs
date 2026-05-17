//! Coverage-guided fuzzer for
//! `lfs_core::ssh_config::parse_openssh_config`.
//!
//! Drives raw bytes through `String::from_utf8_lossy` into the
//! grammar parser. The parser is the entry point for "user
//! pasted their `~/.ssh/config`" so every malformed shape — bad
//! quoting, unbalanced braces, oversized Include depth, control
//! chars in keyword/value — must fail-closed (return empty Vec or
//! drop the offending entry) rather than panic.
//!
//! `Include` directives are stubbed to `None` so the fuzzer
//! doesn't get to redirect reads through filesystem paths; this
//! keeps the harness pure-fn + side-effect-free.
//!
//! Asserts:
//!   - no panic on arbitrary input,
//!   - parser is idempotent: same content twice → identical entry
//!     count.

#![no_main]

use lfs_core::ssh_config::parse_openssh_config;
use libfuzzer_sys::fuzz_target;

fuzz_target!(|data: &[u8]| {
    let s = String::from_utf8_lossy(data);
    let no_includes: lfs_core::ssh_config::IncludeReader = &|_path: &str| None;
    let entries = parse_openssh_config(&s, no_includes, "/", 8);
    // Idempotency probe.
    let entries2 = parse_openssh_config(&s, no_includes, "/", 8);
    assert_eq!(entries.len(), entries2.len());
});
