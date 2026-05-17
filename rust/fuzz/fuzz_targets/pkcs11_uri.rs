//! Coverage-guided fuzzer for `lfs_os_security::pkcs11::uri::Pkcs11Uri::parse`.
//!
//! The PKCS#11 URI parser is the user-pasted-text frontier between
//! a smart-card vendor's `pkcs11-tool -L` output and the Rust
//! connect / import path. RFC 7512 is small (under 200 lines of
//! grammar) but the parser handles percent-decoded binary payloads
//! (`id=%01%02%FF`) and arbitrary attribute names. Fuzz drives
//! arbitrary bytes through the parser and asserts the contract:
//! "no panic, parser is total — every byte sequence either parses
//! or returns a typed `UriError`".
//!
//! Not run in CI (cargo-fuzz needs nightly) — local maintainer runs
//! `cargo +nightly fuzz run pkcs11_uri` from `rust/fuzz/` to surface
//! regressions on the parser.

#![no_main]

use lfs_os_security::pkcs11::uri::Pkcs11Uri;
use libfuzzer_sys::fuzz_target;

fuzz_target!(|data: &[u8]| {
    let s = String::from_utf8_lossy(data);
    match Pkcs11Uri::parse(&s) {
        Ok(parsed) => {
            // Round-trip: emit + re-parse + compare. If the parser
            // round-trips successfully, every field must match.
            let emitted = parsed.to_string();
            let reparsed = Pkcs11Uri::parse(&emitted).expect("re-parse own emission");
            assert_eq!(parsed, reparsed, "URI round-trip mismatch");
            // The emitted shape always carries the canonical scheme.
            assert!(emitted.starts_with("pkcs11:"));
        }
        Err(_) => {
            // Errors are typed — no panic. The fuzzer is happy with
            // "didn't panic"; nothing further to assert.
        }
    }
});
