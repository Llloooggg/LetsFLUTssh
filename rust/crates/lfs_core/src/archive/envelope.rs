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
//! version  (1) = 0x03 (Argon2id + AES-GCM, header-bound AAD)
//! kdf algo (1) = 0x01 (Argon2id)
//! mem KiB  (4) big-endian
//! iters    (4) big-endian
//! parallel (1)
//! salt    (32)
//! iv      (12)
//! ct      (..) AES-256-GCM(ZIP || tag)
//! ```
//!
//! # Header-bound AAD (v0x03)
//!
//! Versions `0x03` and later sign the entire pre-IV header (magic +
//! version + KDF params block + salt — 47 bytes (`PRE_IV_HEADER_LEN`)
//! from offset 0 through end of salt) into the AES-GCM AAD. An attacker who
//! flips, say, `memory_kib` or the algo byte to coerce a different
//! KDF derivation invalidates the AEAD tag rather than feeding
//! cooked params into the verifier. The IV is NOT included in AAD
//! (its uniqueness is the GCM contract; binding it would be
//! redundant).
//!
//! Pre-v0x03 envelopes (`0x02`) used empty AAD. The decoder
//! version-dispatches: v0x02 envelopes still parse through the
//! legacy empty-AAD path, while every new export emits at v0x03.
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

use rand::Rng;
use zeroize::Zeroizing;

use crate::crypto::{aes_gcm_decrypt_raw, aes_gcm_encrypt_raw, argon2id_derive};
use crate::error::Error;

/// LFSE encrypted-archive magic (`'L','F','S','E'`).
pub(super) const ENC_HEADER_MAGIC: [u8; 4] = [0x4C, 0x46, 0x53, 0x45];
/// Version byte for the Argon2id + AES-GCM envelope with the
/// pre-IV header bound into the AES-GCM AAD. Every new export
/// emits at this version.
const ENC_VERSION_ARGON2ID_AAD: u8 = 0x03;
/// Pre-AAD version: the encoded header is identical but the AEAD
/// tag was computed with empty AAD. Decoded through a separate
/// fallback branch so older `.lfs` archives keep importing.
const ENC_VERSION_ARGON2ID_LEGACY: u8 = 0x02;
/// Algorithm id for Argon2id in the embedded KdfParams block.
const KDF_ALGO_ARGON2ID: u8 = 0x01;
const SALT_LEN: usize = 32;
const IV_LEN: usize = 12;
const AES_KEY_LEN: u32 = 32;
/// Pre-IV header byte count (magic plus version plus kdf algo plus
/// memory_kib plus iterations plus parallelism plus salt). v0x03
/// envelopes bind exactly this prefix into the AAD.
const PRE_IV_HEADER_LEN: usize = 4 + 1 + 1 + 4 + 4 + 1 + SALT_LEN;

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
/// DoS-cap on the parallelism field of the LFSE Argon2id header.
/// Combined with the iteration + memory caps above, this bounds the
/// work an attacker can force the import path to do before the
/// wrong-password check fires. Argon2id parallelism scales linearly
/// with thread count; capping at 4 keeps a malicious archive from
/// pinning every core for tens of seconds, while still allowing
/// legitimate exports to use the per-platform default (Argon2id
/// production tuning never exceeds 4).
const MAX_IMPORT_PARALLELISM: u32 = 4;

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
    // Mirror the import-side caps so a self-export never produces a
    // file the same binary refuses to import. Without this, callers
    // that pass `parallelism > MAX_IMPORT_PARALLELISM` (or memory /
    // iterations above their caps) write a valid LFSE blob whose
    // header trips the importer's identical check — a self-
    // unimportable export footgun.
    if memory_kib > MAX_IMPORT_MEMORY_KIB
        || iterations > MAX_IMPORT_ITERATIONS
        || parallelism > MAX_IMPORT_PARALLELISM
    {
        return Err(Error::Crypto(format!(
            "Argon2id params exceed import caps (m={memory_kib}, t={iterations}, p={parallelism})"
        )));
    }
    let mut salt = [0u8; SALT_LEN];
    let mut iv = [0u8; IV_LEN];
    rand::rng().fill_bytes(&mut salt);
    rand::rng().fill_bytes(&mut iv);

    let derived = argon2id_derive(
        password.as_bytes(),
        &salt,
        memory_kib,
        iterations,
        parallelism,
        AES_KEY_LEN,
    )?;

    // Compose the pre-IV header up front so it doubles as the
    // AES-GCM AAD: magic + version + KDF params + salt. Tampering
    // any of those bytes (algo flip, memory cap downgrade, salt
    // swap) invalidates the AEAD tag instead of feeding the
    // verifier a coerced KDF derivation. The IV is NOT in the AAD
    // — its uniqueness is the GCM contract.
    let mut header = Vec::with_capacity(PRE_IV_HEADER_LEN);
    header.extend_from_slice(&ENC_HEADER_MAGIC);
    header.push(ENC_VERSION_ARGON2ID_AAD);
    header.push(KDF_ALGO_ARGON2ID);
    header.extend_from_slice(&memory_kib.to_be_bytes());
    header.extend_from_slice(&iterations.to_be_bytes());
    header.push(parallelism.min(u8::MAX as u32) as u8);
    header.extend_from_slice(&salt);
    debug_assert_eq!(header.len(), PRE_IV_HEADER_LEN);

    let ct = aes_gcm_encrypt_raw(&derived, &iv, zip_bytes, &header)?;

    let mut out = Vec::with_capacity(PRE_IV_HEADER_LEN + IV_LEN + ct.len());
    out.extend_from_slice(&header);
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
    let version = envelope[4];
    if version != ENC_VERSION_ARGON2ID_AAD && version != ENC_VERSION_ARGON2ID_LEGACY {
        return Err(Error::Crypto(format!(
            "unsupported envelope version 0x{version:02x}"
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
    // The pre-IV header (offset 0 .. cursor) is exactly the bytes
    // the v0x03 encoder bound into AAD. Snapshot it before
    // advancing past the IV so we don't have to recompose the
    // header byte-by-byte just to verify the tag.
    let pre_iv_header = &envelope[..cursor];
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
    let aad: &[u8] = if version == ENC_VERSION_ARGON2ID_AAD {
        pre_iv_header
    } else {
        // Pre-AAD legacy envelopes (v0x02) signed the payload with
        // empty AAD. Decoding them through the new path needs the
        // empty slice so the AEAD tag still verifies.
        &[]
    };
    aes_gcm_decrypt_raw(&derived, iv, ct, aad)
}
#[cfg(test)]
#[path = "../../tests/unit/archive_envelope.rs"]
mod tests;
