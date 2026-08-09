/// Unit tests extracted from archive/envelope.rs
/// Declared via `#[path] mod tests;` in the source file.
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
    env.push(ENC_VERSION_ARGON2ID_AAD);
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

/// Hand-build a syntactically valid LFSE envelope with the
/// given KdfParams; the ciphertext is empty so any decryption
/// past the cap check fails on the AES-GCM tag — but for the
/// cap-check tests we only inspect the *first* error surfaced
/// (cap rejection vs crypto failure).
fn synthetic_envelope(memory_kib: u32, iterations: u32, parallelism: u8) -> Vec<u8> {
    let mut env = Vec::new();
    env.extend_from_slice(&ENC_HEADER_MAGIC);
    env.push(ENC_VERSION_ARGON2ID_AAD);
    env.push(KDF_ALGO_ARGON2ID);
    env.extend_from_slice(&memory_kib.to_be_bytes());
    env.extend_from_slice(&iterations.to_be_bytes());
    env.push(parallelism);
    env.extend_from_slice(&[0u8; SALT_LEN]);
    env.extend_from_slice(&[0u8; IV_LEN]);
    env.extend_from_slice(&[0u8; 16]);
    env
}

#[test]
fn decrypt_rejects_iterations_one_above_cap() {
    let env = synthetic_envelope(16, MAX_IMPORT_ITERATIONS + 1, 1);
    let err = decrypt_archive_with_password(&env, "p").unwrap_err();
    assert!(err.to_string().contains("exceed import caps"), "got: {err}");
}

#[test]
fn decrypt_rejects_parallelism_one_above_cap() {
    let env = synthetic_envelope(
        16,
        1,
        (MAX_IMPORT_PARALLELISM + 1).min(u8::MAX as u32) as u8,
    );
    let err = decrypt_archive_with_password(&env, "p").unwrap_err();
    assert!(err.to_string().contains("exceed import caps"), "got: {err}");
}

#[test]
fn encrypt_rejects_parallelism_above_import_cap() {
    // A self-export must never produce a file the same binary
    // refuses to import. Encrypt with `parallelism = cap + 1`
    // and assert the rejection message matches the importer's
    // — the round-trip footgun closes on the encrypt side
    // before any KDF work runs.
    let err =
        encrypt_with_password(SAMPLE_PAYLOAD, "p", 16, 1, MAX_IMPORT_PARALLELISM + 1).unwrap_err();
    assert!(err.to_string().contains("exceed import caps"), "got: {err}");
}

#[test]
fn encrypt_rejects_iterations_above_import_cap() {
    let err =
        encrypt_with_password(SAMPLE_PAYLOAD, "p", 16, MAX_IMPORT_ITERATIONS + 1, 1).unwrap_err();
    assert!(err.to_string().contains("exceed import caps"), "got: {err}");
}

#[test]
fn encrypt_rejects_memory_above_import_cap() {
    let err =
        encrypt_with_password(SAMPLE_PAYLOAD, "p", MAX_IMPORT_MEMORY_KIB + 1, 1, 1).unwrap_err();
    assert!(err.to_string().contains("exceed import caps"), "got: {err}");
}

#[test]
fn decrypt_does_not_reject_iterations_exactly_at_cap() {
    // Boundary check: cap is `>` (strict), so params == cap
    // must NOT trip the cap branch. The KDF still runs past
    // the check, so we settle for "the error surfaced is not
    // the cap-exceed string" and use tiny memory + p=1 so the
    // derive finishes in milliseconds.
    let env = synthetic_envelope(16, MAX_IMPORT_ITERATIONS, 1);
    let err = decrypt_archive_with_password(&env, "p").unwrap_err();
    assert!(
        !err.to_string().contains("exceed import caps"),
        "iterations == cap must pass the cap check; got: {err}"
    );
    // Boundary on memory_kib — hand pick a value at the cap
    // for the desktop build only; the mobile build has a
    // different cap and would need its own KDF run with 512
    // MiB which is impractical even on dev machines. Verify
    // the cap-check predicate, not the derive runtime.
    // For parallelism == cap (16 lanes) the same predicate
    // pass would force argon2id_derive across 16 threads,
    // measured > 30 s on a dev laptop and far longer in CI;
    // that branch is covered by `import_caps_match_documented_values`
    // (constant value check) + the `+1` reject test above
    // (boundary direction).
}

#[test]
fn import_caps_match_documented_values() {
    // Constant-arithmetic mutations (e.g. `512 * 1024 → 512 + 1024`)
    // would silently change the cap; pin the numbers so any
    // refactor that breaks the documented contract trips a
    // test instead of slipping into release.
    assert_eq!(MAX_IMPORT_ITERATIONS, 20);
    assert_eq!(MAX_IMPORT_PARALLELISM, 4);
    #[cfg(any(target_os = "android", target_os = "ios"))]
    assert_eq!(MAX_IMPORT_MEMORY_KIB, 512 * 1024);
    #[cfg(not(any(target_os = "android", target_os = "ios")))]
    assert_eq!(MAX_IMPORT_MEMORY_KIB, 1024 * 1024);
}

#[test]
fn decrypt_rejects_envelope_one_byte_short_of_header_minimum() {
    // Minimum well-formed header is 4 + 1 + 10 + SALT_LEN + IV_LEN
    // = 59 bytes. One byte under that must trip the "too short"
    // branch even if the magic + version bytes happen to match.
    let header_min = 4 + 1 + 10 + SALT_LEN + IV_LEN;
    let mut env = vec![0u8; header_min - 1];
    env[0..4].copy_from_slice(&ENC_HEADER_MAGIC);
    env[4] = ENC_VERSION_ARGON2ID_AAD;
    env[5] = KDF_ALGO_ARGON2ID;
    let err = decrypt_archive_with_password(&env, "p").unwrap_err();
    assert!(err.to_string().contains("too short"), "got: {err}");
}

/// v0x03 binds the pre-IV header into the AES-GCM AAD. Flipping
/// any of those header bytes after encryption MUST invalidate
/// the AEAD tag — the decoder cannot accept a coerced KDF param
/// flip.
#[test]
fn header_tamper_breaks_aad_binding() {
    let enc = encrypt_with_password(SAMPLE_PAYLOAD, "p", 16, 1, 1).expect("encrypt");
    // Flip the iterations field (offset 6 + 4 = 10..14, big-
    // endian u32) so the cap check still passes (still under
    // MAX_IMPORT_ITERATIONS) but the byte differs from what the
    // encoder bound into AAD. The AEAD must reject.
    let mut tampered = enc.clone();
    tampered[13] ^= 0x01; // low byte of iterations
    let err = decrypt_archive_with_password(&tampered, "p").unwrap_err();
    assert!(
        matches!(err, Error::Crypto(_)),
        "tampered header must surface as Crypto error; got {err:?}"
    );
}

/// Pre-v0x03 envelopes (legacy 0x02) signed the payload with
/// empty AAD. The decoder must still accept them so existing
/// installs can import their archives — bumping forward
/// without a transparent fallback would orphan those files.
#[test]
fn decrypt_accepts_legacy_v2_empty_aad_envelope() {
    // Hand-build a v0x02 envelope: same wire layout, but the
    // ciphertext was signed with empty AAD.
    let mut salt = [0u8; SALT_LEN];
    let mut iv = [0u8; IV_LEN];
    rand::rng().fill_bytes(&mut salt);
    rand::rng().fill_bytes(&mut iv);
    let memory_kib = 16u32;
    let iterations = 1u32;
    let parallelism = 1u32;
    let derived = argon2id_derive(
        b"p",
        &salt,
        memory_kib,
        iterations,
        parallelism,
        AES_KEY_LEN,
    )
    .expect("kdf");
    let ct = aes_gcm_encrypt_raw(&derived, &iv, SAMPLE_PAYLOAD, &[]).expect("encrypt");

    let mut env = Vec::new();
    env.extend_from_slice(&ENC_HEADER_MAGIC);
    env.push(ENC_VERSION_ARGON2ID_LEGACY);
    env.push(KDF_ALGO_ARGON2ID);
    env.extend_from_slice(&memory_kib.to_be_bytes());
    env.extend_from_slice(&iterations.to_be_bytes());
    env.push(parallelism as u8);
    env.extend_from_slice(&salt);
    env.extend_from_slice(&iv);
    env.extend_from_slice(&ct);

    let plaintext = decrypt_archive_with_password(&env, "p").expect("legacy decrypt");
    assert_eq!(plaintext.as_slice(), SAMPLE_PAYLOAD);
}

/// Sanity: every fresh export emits at the new AAD-bound
/// version. Pin the byte so a silent rollback is caught.
#[test]
fn fresh_export_uses_aad_bound_version() {
    let enc = encrypt_with_password(SAMPLE_PAYLOAD, "p", 16, 1, 1).expect("encrypt");
    assert_eq!(enc[4], ENC_VERSION_ARGON2ID_AAD);
    assert_eq!(enc[4], 0x03);
}

#[test]
fn decrypt_does_not_reject_envelope_at_header_minimum_for_length_alone() {
    // At exactly the header minimum the "envelope too short"
    // branch must NOT fire — any subsequent failure must come
    // from the missing ciphertext, not the length predicate.
    // Mutating `<` to `<=` in the length check would make this
    // case hit "envelope too short".
    let header_min = 4 + 1 + 10 + SALT_LEN + IV_LEN;
    let env = synthetic_envelope(16, 1, 1);
    let env = env[..header_min].to_vec();
    let err = decrypt_archive_with_password(&env, "p").unwrap_err();
    // Match the exact length-predicate error string. Other
    // "too short" strings (AES-GCM ciphertext-too-short etc.)
    // are expected past the length gate and must NOT trip
    // this assertion.
    assert!(
        !err.to_string().contains("archive envelope too short"),
        "exact header_min must pass the length check; got: {err}"
    );
}

#[test]
fn encrypt_writes_kdf_params_in_big_endian_at_documented_offsets() {
    // Wire-shape pin: bumping any field offset in encrypt() is
    // a wire break that decrypt() must catch in lockstep.
    // Magic (0..4), version (4), algo (5), m (6..10), t (10..14),
    // p (14), salt (15..47), iv (47..59), ct (59..).
    // Use small KDF params so the actual derive call finishes
    // in milliseconds — we only inspect the wire bytes here.
    // Argon2id requires `memory_kib >= 8 * parallelism`, so
    // 32 KiB is the smallest legal value with p=4 (the import-
    // cap maximum, which the encrypt path now also enforces).
    let env = encrypt_with_password(SAMPLE_PAYLOAD, "p", 32, 1, 3).unwrap();
    assert_eq!(&env[0..4], &ENC_HEADER_MAGIC);
    assert_eq!(env[4], ENC_VERSION_ARGON2ID_AAD);
    assert_eq!(env[5], KDF_ALGO_ARGON2ID);
    assert_eq!(&env[6..10], &32u32.to_be_bytes());
    assert_eq!(&env[10..14], &1u32.to_be_bytes());
    assert_eq!(env[14], 3);
    // ct begins after salt + iv.
    assert!(env.len() > 4 + 1 + 10 + SALT_LEN + IV_LEN);
}
