//! Coverage-guided fuzzer for `lfs_core::keys::parse_sk_private_key`.
//!
//! `parse_sk_private_key` ingests an OpenSSH-armored `sk-*` FIDO2
//! private key (`id_ed25519_sk`, `id_ecdsa_sk`). The file is never
//! passphrase-encrypted — it carries the public point, the
//! application string, the variable-length CTAP2 credential id (up
//! to 255 bytes per PROTOCOL.u2f), and the flags byte; the real
//! signing key lives on the authenticator. The interesting failure
//! modes are a non-`sk-*` key body that must be rejected rather than
//! mis-routed, a truncated credential-id length prefix, and an armor
//! that decodes but carries a non-FIDO2 keypair.
//!
//! Drives raw bytes through `String::from_utf8_lossy`. The Result is
//! discarded: the parser must fail-closed (`Err`) on every malformed
//! input and only ever panic on a real bug.

#![no_main]

use lfs_core::keys::parse_sk_private_key;
use libfuzzer_sys::fuzz_target;

fuzz_target!(|data: &[u8]| {
    let pem = String::from_utf8_lossy(data);
    let _ = parse_sk_private_key(&pem);
});
