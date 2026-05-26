//! Coverage-guided fuzzer for
//! `lfs_core::webdav::client::parse_pem_certs`.
//!
//! The parser splits a PEM blob (one or more `-----BEGIN
//! CERTIFICATE-----` blocks) into one `reqwest::Certificate` per
//! block — the session-edit dialog's trusted-cert textarea feeds
//! it straight from user paste. The interesting failure modes are
//! unterminated blocks (BEGIN without END), embedded NULs, oversize
//! inputs, and adversarial UTF-8 that confuses the block boundary
//! search.
//!
//! Asserts no panic / no UB. A successful parse returns a `Vec` of
//! certificates; the only contract bound the fuzzer can verify
//! without re-implementing reqwest's DER decoder is that the count
//! is bounded by the number of `BEGIN CERTIFICATE` markers in the
//! input — anything else implies the splitter is creating phantom
//! blocks.
//!
//! Not run in CI (cargo-fuzz needs nightly + a separate corpus dir)
//! but lives in-tree so a maintainer running
//! `cargo +nightly fuzz run pem_certs` against this target gets
//! immediate coverage on the trusted-cert ingest path.

#![no_main]

use lfs_core::webdav::client::parse_pem_certs;
use libfuzzer_sys::fuzz_target;

fuzz_target!(|data: &[u8]| {
    let s = String::from_utf8_lossy(data);
    let result = parse_pem_certs(&s);
    if let Ok(certs) = result {
        // Upper bound: the splitter cannot emit more certificates
        // than there are BEGIN markers in the source. The exact
        // count check would re-implement the splitter; the
        // upper-bound guard is enough to catch a phantom-cert
        // regression while staying parser-agnostic.
        let begin_count = s.matches("-----BEGIN CERTIFICATE-----").count();
        assert!(
            certs.len() <= begin_count,
            "parser emitted {} certs from {} BEGIN markers",
            certs.len(),
            begin_count
        );
    }
});
