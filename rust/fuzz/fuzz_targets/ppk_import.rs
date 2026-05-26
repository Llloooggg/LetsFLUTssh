//! Coverage-guided fuzzer for `lfs_core::keys::import_ppk`.
//!
//! `import_ppk` is the PuTTY `.ppk` (v2 / v3) private-key parser the
//! key-import dialog feeds straight from user paste / file pick. The
//! format is length-prefixed and binary-ish: a magic header, base64
//! key bodies, a hex MAC, and — for v3 — Argon2id KDF params
//! (`Argon2-Memory`, `Argon2-Passes`, `Argon2-Parallelism`). The
//! pre-parse header sniff (`parse_ppk_argon2_memory`) caps the
//! declared memory cost before russh-keys forwards it to the Argon2
//! derive, so a hostile `.ppk` cannot trigger an unbounded
//! allocation. The interesting failure modes are a truncated header,
//! a non-`u32` `Argon2-Memory` value, a corrupt MAC line, and a body
//! whose declared length runs past the input.
//!
//! Drives raw bytes through `String::from_utf8_lossy` and a fixed
//! passphrase. The contract the fuzzer asserts is the only one a
//! parser owes against arbitrary input: no panic, no UB. The Result
//! is discarded — both `Ok` (somehow valid) and `Err` (the common
//! case) are correct outcomes; only a crash is a bug.

#![no_main]

use lfs_core::keys::import_ppk;
use libfuzzer_sys::fuzz_target;

fuzz_target!(|data: &[u8]| {
    let text = String::from_utf8_lossy(data);
    let _ = import_ppk(&text, Some("fuzz-passphrase"), "fuzz");
});
