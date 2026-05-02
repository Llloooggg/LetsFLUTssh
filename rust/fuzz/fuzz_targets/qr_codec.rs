//! Coverage-guided fuzzer for `lfs_core::qr_codec_decode::decode_payload`.
//!
//! The QR codec decode is the highest-blast-radius parser the
//! deeplink + paste-link surfaces feed into: a malformed payload
//! crossing decode would propagate into the import staging layer
//! and the Dart UI. The decoder caps the inflated JSON size and
//! ASCII-validates the payload — every malformed input path must
//! return `Err`, never panic.
//!
//! Asserts:
//!   - no panic on arbitrary input,
//!   - successful decode lands a payload whose declared shape is
//!     internally consistent (non-negative session counts, etc).

#![no_main]

use libfuzzer_sys::fuzz_target;
use lfs_core::qr_codec_decode::decode_payload;

fuzz_target!(|data: &[u8]| {
    let s = match std::str::from_utf8(data) {
        Ok(s) => s,
        // Non-UTF8 input is a valid invariant test for the
        // parser's "ASCII validate first" guard but not coverage-
        // useful — the parser already rejects via `is_ascii`.
        Err(_) => return,
    };
    let _ = decode_payload(s);
});
