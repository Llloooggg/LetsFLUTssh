//! Coverage-guided fuzzer for `lfs_core::keys::import_openssh`.
//!
//! `import_openssh` ingests a PEM-armored OpenSSH private key
//! (also accepting the PKCS#1 / PKCS#8 armors russh-keys understands)
//! from the key-import dialog's paste / file-pick path. It parses the
//! armor, and — when the key is encrypted — decrypts with the
//! supplied passphrase before re-encoding to canonical OpenSSH form.
//! The interesting failure modes are a truncated base64 body, a
//! mismatched BEGIN/END armor pair, an encrypted key with a corrupt
//! KDF block, and adversarial UTF-8 around the armor boundary.
//!
//! Drives raw bytes through `String::from_utf8_lossy` and a fixed
//! passphrase (so the encrypted-key decrypt branch is reachable).
//! The Result is discarded: a parse failure is the expected outcome
//! for nearly all inputs, and the only contract worth asserting
//! against arbitrary bytes is no panic / no UB.

#![no_main]

use lfs_core::keys::import_openssh;
use libfuzzer_sys::fuzz_target;

fuzz_target!(|data: &[u8]| {
    let pem = String::from_utf8_lossy(data);
    let _ = import_openssh(&pem, Some("fuzz-passphrase"), "fuzz");
});
