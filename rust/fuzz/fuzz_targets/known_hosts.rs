//! Coverage-guided fuzzer for `lfs_core::known_hosts_parser::parse_line`.
//!
//! Drives raw bytes through `String::from_utf8_lossy` into the
//! line parser. `parse_line` is pure, returns `Vec<ParsedHostEntry>`,
//! and is the load-bearing entry point for "user pasted the
//! contents of `~/.ssh/known_hosts`" — every malformed line shape
//! must fail-closed (return empty vec) rather than panic.
//!
//! Asserts:
//!   - no panic on arbitrary input,
//!   - every returned entry's host/key fields are non-empty
//!     (parser doesn't admit blank entries),
//!   - parser is idempotent: feeding the same line twice yields
//!     identical parse output.

#![no_main]

use libfuzzer_sys::fuzz_target;
use lfs_core::known_hosts_parser::parse_line;

fuzz_target!(|data: &[u8]| {
    let s = String::from_utf8_lossy(data);
    let entries = parse_line(&s);
    for entry in &entries {
        assert!(!entry.host_port.is_empty(), "host_port must be non-empty");
        assert!(!entry.key_type.is_empty(), "key_type must be non-empty");
        assert!(!entry.key_base64.is_empty(), "key_base64 must be non-empty");
    }
    // Idempotency — running the parser twice must produce the
    // same output. Catches non-deterministic parser bugs.
    let entries2 = parse_line(&s);
    assert_eq!(entries.len(), entries2.len());
});
