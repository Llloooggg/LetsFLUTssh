/// Unit tests extracted from recorder/reader.rs
/// Declared via `#[path] mod tests;` in the source file.
use super::*;

use crate::recorder::{RecorderActor, RecorderRegistry};
use std::io::Write;

/// Test-only LFR1 v1 writer. Wraps `recording_key` under
/// `db_key` into the 65-byte header and appends one frame per
/// line so the reader's round-trip + decrypt path can be
/// exercised without spinning a full `RecorderRegistry`.
fn write_v1_recording(path: &Path, db_key: &[u8; 32], recording_key: &[u8; 32], lines: &[&str]) {
    let mut f = std::fs::File::create(path).unwrap();
    let header = super::super::build_lfsr_header(db_key, recording_key).unwrap();
    f.write_all(&header).unwrap();
    for (i, line) in lines.iter().enumerate() {
        // Mirror the writer's `build_frame` shape exactly: append
        // a trailing newline to the plaintext so the round-trip
        // matches what a live recorder would emit.
        let mut payload = line.as_bytes().to_vec();
        payload.push(b'\n');
        let nonce = [0u8; NONCE_LEN]; // deterministic for tests
        let aad = (i as u64).to_le_bytes();
        let ct = crypto::aes_gcm_encrypt_raw(recording_key, &nonce, &payload, &aad).unwrap();
        f.write_all(&(payload.len() as u32).to_le_bytes()).unwrap();
        f.write_all(&nonce).unwrap();
        f.write_all(&ct).unwrap();
    }
}

fn _silence_unused() {
    // Keep imports cited even when no test path uses them so a
    // re-arrange doesn't strip them silently.
    let _ = std::any::type_name::<RecorderRegistry>();
    let _ = std::any::type_name::<RecorderActor>();
}

/// Bare-magic header builder for negative tests — emits the
/// 65-byte v1 shape but skips the actual wrap so we can hit
/// truncated / frame-length / nonce-only fault paths without
/// caring about decryptability. Wrap nonce + slot are zeros;
/// any test that calls this must NOT also try to decrypt.
fn write_v1_header_only(path: &Path) {
    let mut bytes = LFR_MAGIC.to_vec();
    bytes.push(LFR_VERSION);
    bytes.extend_from_slice(&[0u8; NONCE_LEN]);
    bytes.extend_from_slice(&[0u8; 48]); // wrapped slot
    std::fs::write(path, &bytes).unwrap();
}

#[test]
fn open_rejects_missing_file() {
    let key = [0u8; 32];
    let err =
        open_lfsr_iter(Path::new("/nonexistent/path-7c8f.lfsr"), key).expect_err("missing file");
    assert!(matches!(err, ReaderError::Io(_)));
}

#[test]
fn open_rejects_bad_magic() {
    let tmp = tempfile::NamedTempFile::new().unwrap();
    // 65 bytes so the header read succeeds — fault must come
    // from the magic compare, not the truncation guard.
    let mut bytes = vec![b'N', b'O', b'P', b'E', LFR_VERSION];
    bytes.extend_from_slice(&[0u8; LFR_HEADER_LEN - 5]);
    std::fs::write(tmp.path(), &bytes).unwrap();
    let key = [0u8; 32];
    let err = open_lfsr_iter(tmp.path(), key).expect_err("bad magic");
    assert!(matches!(err, ReaderError::BadMagic));
}

#[test]
fn open_rejects_unsupported_version() {
    let tmp = tempfile::NamedTempFile::new().unwrap();
    let mut bytes = LFR_MAGIC.to_vec();
    bytes.push(0xFE);
    bytes.extend_from_slice(&[0u8; LFR_HEADER_LEN - 5]);
    std::fs::write(tmp.path(), &bytes).unwrap();
    let key = [0u8; 32];
    let err = open_lfsr_iter(tmp.path(), key).expect_err("bad version");
    assert!(matches!(err, ReaderError::UnsupportedVersion(0xFE)));
}

#[test]
fn open_rejects_truncated_header() {
    let tmp = tempfile::NamedTempFile::new().unwrap();
    // Only 2 of the 65 header bytes — the read fails before any
    // field decode.
    std::fs::write(tmp.path(), &LFR_MAGIC[..2]).unwrap();
    let key = [0u8; 32];
    let err = open_lfsr_iter(tmp.path(), key).expect_err("trunc header");
    assert!(matches!(err, ReaderError::TruncatedHeader));
}

#[test]
fn round_trip_v1_yields_original_lines() {
    let tmp = tempfile::NamedTempFile::new().unwrap();
    let db_key = [0x42u8; 32];
    let recording_key = [0x33u8; 32];
    let lines = vec![
        r#"{"version":2,"width":80,"height":24}"#,
        r#"[0.5,"o","hello"]"#,
        r#"[1.0,"i","q"]"#,
    ];
    write_v1_recording(tmp.path(), &db_key, &recording_key, &lines);
    let iter = open_lfsr_iter(tmp.path(), db_key).unwrap();
    let decoded: Vec<Result<String, _>> = iter.collect();
    assert_eq!(decoded.len(), 3);
    for (got, want) in decoded.iter().zip(lines.iter()) {
        let got_line = got.as_ref().expect("frame must decrypt");
        assert_eq!(got_line, want);
    }
}

#[test]
fn frame_too_large_collapses_to_typed_error() {
    // Hand-build a real header (so unwrap succeeds) with a
    // bogus frame length immediately after; the iterator must
    // short-circuit with FrameTooLarge before it tries to
    // allocate the body buffer.
    let tmp = tempfile::NamedTempFile::new().unwrap();
    let db_key = [0x42u8; 32];
    let recording_key = [0x33u8; 32];
    let header = super::super::build_lfsr_header(&db_key, &recording_key).unwrap();
    let mut bytes = header;
    let bogus_len: u32 = MAX_FRAME_PLAINTEXT_BYTES.saturating_add(1);
    bytes.extend_from_slice(&bogus_len.to_le_bytes());
    std::fs::write(tmp.path(), &bytes).unwrap();
    let mut iter = open_lfsr_iter(tmp.path(), db_key).expect("header ok");
    let first = iter.next().expect("yields error");
    assert!(matches!(first, Err(ReaderError::FrameTooLarge(_))));
    assert!(iter.next().is_none());
}

#[test]
fn frame_with_u32_max_length_rejects_without_allocating() {
    // Attacker handing us `pt_len = u32::MAX` (~4 GiB) — the
    // `pt_len > MAX_FRAME_PLAINTEXT_BYTES` guard fires before
    // the ciphertext allocation; the file stays at the header
    // + 4-byte length read.
    let tmp = tempfile::NamedTempFile::new().unwrap();
    let db_key = [0x42u8; 32];
    let recording_key = [0x33u8; 32];
    let header = super::super::build_lfsr_header(&db_key, &recording_key).unwrap();
    let mut bytes = header;
    bytes.extend_from_slice(&u32::MAX.to_le_bytes());
    std::fs::write(tmp.path(), &bytes).unwrap();
    let mut iter = open_lfsr_iter(tmp.path(), db_key).expect("header ok");
    let first = iter.next().expect("yields error");
    match first {
        Err(ReaderError::FrameTooLarge(reported)) => {
            assert_eq!(reported, u32::MAX);
        }
        other => panic!("expected FrameTooLarge(u32::MAX), got {other:?}"),
    }
    assert!(iter.next().is_none());
}

#[test]
fn truncated_frame_after_length_collapses_to_typed_error() {
    let tmp = tempfile::NamedTempFile::new().unwrap();
    let db_key = [0x42u8; 32];
    let recording_key = [0x33u8; 32];
    let header = super::super::build_lfsr_header(&db_key, &recording_key).unwrap();
    let mut bytes = header;
    // length = 4, but no nonce / ciphertext follows.
    bytes.extend_from_slice(&4u32.to_le_bytes());
    std::fs::write(tmp.path(), &bytes).unwrap();
    let mut iter = open_lfsr_iter(tmp.path(), db_key).expect("header ok");
    assert!(matches!(
        iter.next(),
        Some(Err(ReaderError::TruncatedFrame))
    ));
    assert!(iter.next().is_none());
}

#[test]
fn wrong_db_key_yields_crypto_error() {
    let tmp = tempfile::NamedTempFile::new().unwrap();
    let db_key_write = [0x42u8; 32];
    let recording_key = [0x33u8; 32];
    write_v1_recording(
        tmp.path(),
        &db_key_write,
        &recording_key,
        &[r#"[0,"o","x"]"#],
    );
    let db_key_read = [0x99u8; 32];
    // Wrap unwrap fails — the wrong DB key cannot decrypt the
    // recording-key slot, so the iterator never starts.
    let err = open_lfsr_iter(tmp.path(), db_key_read).expect_err("wrong db key");
    assert!(matches!(err, ReaderError::Crypto(_)));
}

#[test]
fn header_only_with_zero_wrap_yields_crypto_error_on_open() {
    // A file that carries the magic + version + zeros (no real
    // wrap) must reject at open-time — the GCM tag mismatches
    // before any frame read.
    let tmp = tempfile::NamedTempFile::new().unwrap();
    write_v1_header_only(tmp.path());
    let err = open_lfsr_iter(tmp.path(), [0u8; 32]).expect_err("zero-wrap");
    assert!(matches!(err, ReaderError::Crypto(_)));
}

#[test]
fn cast_iter_yields_each_line_trimmed() {
    let tmp = tempfile::NamedTempFile::new().unwrap();
    let body = "{\"version\":2,\"width\":80,\"height\":24}\n[0.5,\"o\",\"hi\"]\n";
    std::fs::write(tmp.path(), body).unwrap();
    let mut it = open_cast_iter(tmp.path()).unwrap();
    assert_eq!(
        it.next().unwrap().unwrap(),
        "{\"version\":2,\"width\":80,\"height\":24}"
    );
    assert_eq!(it.next().unwrap().unwrap(), "[0.5,\"o\",\"hi\"]");
    assert!(it.next().is_none());
}

#[test]
fn cast_iter_skips_empty_lines() {
    let tmp = tempfile::NamedTempFile::new().unwrap();
    // Empty line between records — user-edited file in the
    // wild. The iterator skips them so the playback loop stays
    // straight.
    std::fs::write(tmp.path(), "a\n\nb\n").unwrap();
    let mut it = open_cast_iter(tmp.path()).unwrap();
    assert_eq!(it.next().unwrap().unwrap(), "a");
    assert_eq!(it.next().unwrap().unwrap(), "b");
    assert!(it.next().is_none());
}

#[test]
fn cast_iter_strips_crlf_line_endings() {
    // Windows-line-ending exports sometimes carry `\r\n`. The
    // trailing `\r` would otherwise leak into the JSON parser
    // on the Dart side and reject every record.
    let tmp = tempfile::NamedTempFile::new().unwrap();
    std::fs::write(tmp.path(), "{\"version\":2}\r\n[0,\"o\",\"x\"]\r\n").unwrap();
    let mut it = open_cast_iter(tmp.path()).unwrap();
    assert_eq!(it.next().unwrap().unwrap(), "{\"version\":2}");
    assert_eq!(it.next().unwrap().unwrap(), "[0,\"o\",\"x\"]");
}

#[test]
fn cast_iter_handles_no_trailing_newline() {
    let tmp = tempfile::NamedTempFile::new().unwrap();
    std::fs::write(tmp.path(), "[0,\"o\",\"x\"]").unwrap();
    let mut it = open_cast_iter(tmp.path()).unwrap();
    assert_eq!(it.next().unwrap().unwrap(), "[0,\"o\",\"x\"]");
    assert!(it.next().is_none());
}

#[test]
fn cast_iter_rejects_oversized_line() {
    // A single line beyond MAX_CAST_LINE_BYTES surfaces as
    // FrameTooLarge. The cap matches the encrypted path's
    // per-frame cap so a malformed plaintext file cannot pull
    // a multi-GiB allocation just by omitting newlines.
    let tmp = tempfile::NamedTempFile::new().unwrap();
    let mut bytes = vec![b'x'; MAX_CAST_LINE_BYTES + 8];
    bytes.push(b'\n');
    std::fs::write(tmp.path(), &bytes).unwrap();
    let mut it = open_cast_iter(tmp.path()).unwrap();
    assert!(matches!(
        it.next(),
        Some(Err(ReaderError::FrameTooLarge(_)))
    ));
    assert!(it.next().is_none());
}

#[test]
fn cast_iter_rejects_missing_file() {
    let err = open_cast_iter(Path::new("/nonexistent/path-cast-7c8f.cast")).unwrap_err();
    assert!(matches!(err, ReaderError::Io(_)));
}

#[test]
fn open_for_playback_dispatches_on_extension() {
    // .cast → CastFrameIter regardless of the supplied db key.
    let cast = tempfile::Builder::new().suffix(".cast").tempfile().unwrap();
    std::fs::write(cast.path(), "first\nsecond\n").unwrap();
    let dummy_key = [0u8; 32];
    let mut it = open_for_playback(cast.path(), dummy_key).unwrap();
    assert!(matches!(it, PlaybackIter::Cast(_)));
    assert_eq!(it.next_record().unwrap().unwrap(), "first");
    assert_eq!(it.next_record().unwrap().unwrap(), "second");
    assert!(it.next_record().is_none());

    // .lfsr → LfsrFrameIter through the header-unwrap path.
    let lfsr = tempfile::Builder::new().suffix(".lfsr").tempfile().unwrap();
    let db_key = [0x42u8; 32];
    let recording_key = [0x33u8; 32];
    write_v1_recording(lfsr.path(), &db_key, &recording_key, &[r#"[0,"o","x"]"#]);
    let it = open_for_playback(lfsr.path(), db_key).unwrap();
    assert!(matches!(it, PlaybackIter::Lfsr(_)));
}

#[test]
fn open_for_playback_treats_missing_extension_as_cast() {
    // A user-renamed file without an extension falls through to
    // the plaintext branch — no LFR1 magic match to attempt.
    let tmp = tempfile::NamedTempFile::new().unwrap();
    std::fs::write(tmp.path(), "raw\n").unwrap();
    let mut it = open_for_playback(tmp.path(), [0u8; 32]).unwrap();
    assert!(matches!(it, PlaybackIter::Cast(_)));
    assert_eq!(it.next_record().unwrap().unwrap(), "raw");
}

#[test]
fn open_for_playback_extension_check_is_case_insensitive() {
    // `.LFSR` (uppercase) routes to the encrypted path.
    let lfsr = tempfile::Builder::new().suffix(".LFSR").tempfile().unwrap();
    let db_key = [0x42u8; 32];
    let recording_key = [0x33u8; 32];
    write_v1_recording(lfsr.path(), &db_key, &recording_key, &[r#"[0,"o","x"]"#]);
    let it = open_for_playback(lfsr.path(), db_key).unwrap();
    assert!(matches!(it, PlaybackIter::Lfsr(_)));
}
