//! Coverage-guided fuzzer for
//! `lfs_core::path::is_safe_transfer_entry_name`.
//!
//! An SFTP server supplies directory-entry names as untrusted bytes;
//! the download directory-walk joins each onto the user-chosen
//! destination, so the predicate is the directory-escape guard
//! standing between a hostile remote and an arbitrary local write.
//! Fuzz drives arbitrary bytes through the validator and asserts the
//! safety invariant directly: any name that is empty, equal to
//! `.`/`..`, whitespace-only, or that contains a path separator
//! (`/` or `\`) or a NUL MUST be rejected; the predicate is total
//! (never panics). Interior spaces and other content are allowed.
//!
//! Not run in CI (cargo-fuzz needs nightly) — local maintainer runs
//! `cargo +nightly fuzz run transfer_entry_name` from `rust/fuzz/`.

#![no_main]

use lfs_core::path::is_safe_transfer_entry_name;
use libfuzzer_sys::fuzz_target;

fuzz_target!(|data: &[u8]| {
    let name = String::from_utf8_lossy(data);
    let accepted = is_safe_transfer_entry_name(&name);

    // Re-derive the safety classification from the spec, independent
    // of the implementation: a name is unsafe to join when it is
    // empty, a self/parent reference, whitespace-only, or carries a
    // separator / NUL.
    let unsafe_shape = name.is_empty()
        || name == "."
        || name == ".."
        || name.contains('/')
        || name.contains('\\')
        || name.contains('\0')
        || name.trim().is_empty();

    assert_eq!(
        accepted, !unsafe_shape,
        "validator disagreed with the safety spec for {name:?}"
    );

    // A name the validator accepts must never contain a byte that
    // would let it escape the join — the load-bearing security
    // property stated without reference to the predicate's branches.
    if accepted {
        assert!(!name.contains('/'));
        assert!(!name.contains('\\'));
        assert!(!name.contains('\0'));
        assert_ne!(name, ".");
        assert_ne!(name, "..");
        assert!(!name.is_empty());
    }
});
