//! LFSE archive envelope: outer Argon2id + AES-256-GCM wrapper that
//! turns a plain stored-mode ZIP into the on-disk `.lfs` container
//! the user picks in the file dialog. The inner ZIP composition lives
//! in [`super`]; this module owns only the byte-for-byte wire format
//! and the import-time KDF caps that gate untrusted parameters.
//!
//! # Wire layout
//!
//! ```text
//! magic    (4) = 'L','F','S','E'
//! version  (1) = 0x02 (Argon2id + AES-GCM)
//! kdf algo (1) = 0x01 (Argon2id)
//! mem KiB  (4) big-endian
//! iters    (4) big-endian
//! parallel (1)
//! salt    (32)
//! iv      (12)
//! ct      (..) AES-256-GCM(ZIP || tag)
//! ```
//!
//! The Dart reader (`lib/core/import/import_service.dart`) parses the
//! same layout — bumping any field here is a wire break and must move
//! in lockstep with the schema-version migration.
//!
//! # Why caps live here, not at the KDF
//!
//! [`crate::crypto::argon2id_derive`] honours whatever it is asked to
//! derive. An attacker who hands us an LFSE blob with `m=64 GiB / t=2^31`
//! could OOM-kill the app or pin the CPU before the password is even
//! tried. The import path enforces hard ceilings *before* calling the
//! KDF, with the mobile cap halved so a 2 GB-baseline phone does not
//! get terminated by the OOM killer mid-derive.

use rand::rngs::OsRng;
use rand::RngCore;
use zeroize::Zeroizing;

use crate::crypto::{aes_gcm_decrypt_raw, aes_gcm_encrypt_raw, argon2id_derive};
use crate::error::Error;

/// LFSE encrypted-archive magic (`'L','F','S','E'`).
pub(super) const ENC_HEADER_MAGIC: [u8; 4] = [0x4C, 0x46, 0x53, 0x45];
/// Version byte for the Argon2id + AES-GCM envelope.
const ENC_VERSION_ARGON2ID: u8 = 0x02;
/// Algorithm id for Argon2id in the embedded KdfParams block.
const KDF_ALGO_ARGON2ID: u8 = 0x01;
const SALT_LEN: usize = 32;
const IV_LEN: usize = 12;
const AES_KEY_LEN: u32 = 32;

/// Hard ceiling on the Argon2id memory cost we are willing to honour
/// from an untrusted archive header. Desktop = 1 GiB; mobile drops
/// to 512 MiB so the OOM killer on a 2 GB-baseline phone does not
/// terminate the process before the KDF returns. Exceeding any cap
/// rejects the archive as malformed before the KDF runs.
#[cfg(any(target_os = "android", target_os = "ios"))]
const MAX_IMPORT_MEMORY_KIB: u32 = 512 * 1024;
#[cfg(not(any(target_os = "android", target_os = "ios")))]
const MAX_IMPORT_MEMORY_KIB: u32 = 1024 * 1024;
const MAX_IMPORT_ITERATIONS: u32 = 20;
const MAX_IMPORT_PARALLELISM: u32 = 16;

/// Wrap `zip_bytes` in the LFSE envelope using `password` + the
/// caller-supplied Argon2id parameters. The salt + IV are fresh
/// random bytes from the OS CSPRNG on every call — never reused
/// across exports even with the same password.
pub(super) fn encrypt_with_password(
    zip_bytes: &[u8],
    password: &str,
    memory_kib: u32,
    iterations: u32,
    parallelism: u32,
) -> Result<Vec<u8>, Error> {
    let mut salt = [0u8; SALT_LEN];
    let mut iv = [0u8; IV_LEN];
    OsRng.fill_bytes(&mut salt);
    OsRng.fill_bytes(&mut iv);

    let derived = argon2id_derive(
        password.as_bytes(),
        &salt,
        memory_kib,
        iterations,
        parallelism,
        AES_KEY_LEN,
    )?;
    let ct = aes_gcm_encrypt_raw(&derived, &iv, zip_bytes, &[])?;

    let mut out = Vec::with_capacity(4 + 1 + 10 + SALT_LEN + IV_LEN + ct.len());
    out.extend_from_slice(&ENC_HEADER_MAGIC);
    out.push(ENC_VERSION_ARGON2ID);
    // KdfParams.encode() — Argon2id only.
    out.push(KDF_ALGO_ARGON2ID);
    out.extend_from_slice(&memory_kib.to_be_bytes());
    out.extend_from_slice(&iterations.to_be_bytes());
    out.push(parallelism.min(u8::MAX as u32) as u8);
    out.extend_from_slice(&salt);
    out.extend_from_slice(&iv);
    out.extend_from_slice(&ct);
    Ok(out)
}

/// Reverse of [`encrypt_with_password`]. Takes the LFSE envelope
/// produced by export, returns the inner ZIP bytes. Errors on
/// magic / version mismatch, malformed KdfParams, KDF parameters
/// that exceed the import caps, or AES-GCM tag failure (wrong
/// password / corruption).
pub fn decrypt_archive_with_password(
    envelope: &[u8],
    password: &str,
) -> Result<Zeroizing<Vec<u8>>, Error> {
    if envelope.len() < 4 + 1 + 10 + SALT_LEN + IV_LEN {
        return Err(Error::Crypto("archive envelope too short".to_string()));
    }
    if envelope[..4] != ENC_HEADER_MAGIC {
        return Err(Error::Crypto("not an LFSE archive".to_string()));
    }
    if envelope[4] != ENC_VERSION_ARGON2ID {
        return Err(Error::Crypto(format!(
            "unsupported envelope version 0x{:02x}",
            envelope[4]
        )));
    }
    let mut cursor = 5usize;
    if envelope[cursor] != KDF_ALGO_ARGON2ID {
        return Err(Error::Crypto(format!(
            "unsupported kdf algorithm 0x{:02x}",
            envelope[cursor]
        )));
    }
    cursor += 1;
    let memory_kib = u32::from_be_bytes(envelope[cursor..cursor + 4].try_into().unwrap());
    cursor += 4;
    let iterations = u32::from_be_bytes(envelope[cursor..cursor + 4].try_into().unwrap());
    cursor += 4;
    let parallelism = envelope[cursor] as u32;
    cursor += 1;
    if memory_kib > MAX_IMPORT_MEMORY_KIB
        || iterations > MAX_IMPORT_ITERATIONS
        || parallelism > MAX_IMPORT_PARALLELISM
    {
        return Err(Error::Crypto(format!(
            "Argon2id params exceed import caps (m={memory_kib}, t={iterations}, p={parallelism})"
        )));
    }
    let salt = &envelope[cursor..cursor + SALT_LEN];
    cursor += SALT_LEN;
    let iv = &envelope[cursor..cursor + IV_LEN];
    cursor += IV_LEN;
    let ct = &envelope[cursor..];

    let derived = argon2id_derive(
        password.as_bytes(),
        salt,
        memory_kib,
        iterations,
        parallelism,
        AES_KEY_LEN,
    )?;
    aes_gcm_decrypt_raw(&derived, iv, ct, &[])
}

#[cfg(test)]
mod tests {
    use super::*;

    // The envelope is opaque to the inner payload: arbitrary bytes
    // round-trip the same way a real ZIP does, so we keep the tests
    // self-contained and skip pulling in a ZIP builder helper.
    const SAMPLE_PAYLOAD: &[u8] = b"\x50\x4b\x03\x04 inner-zip-bytes";

    #[test]
    fn encrypt_decrypt_round_trip_with_correct_password() {
        // Argon2id parameters tuned tiny so the test runs in a few ms.
        let enc = encrypt_with_password(SAMPLE_PAYLOAD, "hunter2", 16, 1, 1).expect("encrypt");
        assert_eq!(&enc[..4], &ENC_HEADER_MAGIC);
        let plaintext = decrypt_archive_with_password(&enc, "hunter2").expect("decrypt");
        assert_eq!(plaintext.as_slice(), SAMPLE_PAYLOAD);
    }

    #[test]
    fn decrypt_with_wrong_password_fails() {
        let enc = encrypt_with_password(SAMPLE_PAYLOAD, "hunter2", 16, 1, 1).expect("encrypt");
        let err = decrypt_archive_with_password(&enc, "wrong").unwrap_err();
        assert!(matches!(err, Error::Crypto(_)));
    }

    #[test]
    fn decrypt_rejects_wrong_magic() {
        let mut bytes = encrypt_with_password(SAMPLE_PAYLOAD, "p", 16, 1, 1).unwrap();
        bytes[0] = 0xFF;
        let err = decrypt_archive_with_password(&bytes, "p").unwrap_err();
        let s = err.to_string();
        assert!(s.contains("not an LFSE archive"), "got: {s}");
    }

    #[test]
    fn decrypt_rejects_unknown_version() {
        let mut enc = encrypt_with_password(SAMPLE_PAYLOAD, "p", 16, 1, 1).unwrap();
        enc[4] = 0x99;
        let err = decrypt_archive_with_password(&enc, "p").unwrap_err();
        assert!(err.to_string().contains("unsupported envelope version"));
    }

    #[test]
    fn decrypt_rejects_short_envelope() {
        let err = decrypt_archive_with_password(&[0u8; 10], "p").unwrap_err();
        assert!(err.to_string().contains("too short"));
    }

    #[test]
    fn decrypt_rejects_kdf_params_above_caps() {
        // Build an envelope by hand whose memory_kib exceeds the
        // import cap. We don't actually call argon2id_derive — the
        // cap check fires before the KDF runs.
        let mut env = Vec::new();
        env.extend_from_slice(&ENC_HEADER_MAGIC);
        env.push(ENC_VERSION_ARGON2ID);
        env.push(KDF_ALGO_ARGON2ID);
        env.extend_from_slice(&(MAX_IMPORT_MEMORY_KIB + 1).to_be_bytes());
        env.extend_from_slice(&1u32.to_be_bytes());
        env.push(1);
        env.extend_from_slice(&[0u8; SALT_LEN]);
        env.extend_from_slice(&[0u8; IV_LEN]);
        env.extend_from_slice(&[0u8; 16]); // dummy ct
        let err = decrypt_archive_with_password(&env, "p").unwrap_err();
        assert!(err.to_string().contains("exceed import caps"), "got: {err}");
    }
}
