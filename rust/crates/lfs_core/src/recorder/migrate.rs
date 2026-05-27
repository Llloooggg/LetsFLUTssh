//! Tier-transition migration helpers for the recordings tree.
//!
//! Recordings are tied to the active DB key — `.lfsr` files store
//! their per-file recording key wrapped under the DB key in a
//! 65-byte header. When the security tier changes (master-password
//! rotation, T0↔T1 toggle, hardware bind/unbind), every existing
//! recording must be migrated under the new DB-key discipline or
//! it becomes unreadable.
//!
//! Three migration operations live here:
//!
//! - [`rewrap_all_headers`] — DB-key rotation (T1↔T1', T1↔T2,
//!   T2↔T2'). Header re-encryption only; frame body + sidecar
//!   untouched. Constant-time per file regardless of recording
//!   length.
//! - [`convert_all_cast_to_lfsr`] — `T0 → T1` enable. Reads each
//!   plaintext `.cast` file, wraps a fresh recording key under the
//!   new DB key, re-encrypts every frame, builds a fresh encrypted
//!   sidecar. Linear in the recordings tree.
//! - [`convert_all_lfsr_to_cast`] — `T1 → T0` disable. Decrypts
//!   every `.lfsr` body to plaintext asciinema, drops the encrypted
//!   sidecar (plaintext recordings don't need one). MUST run while
//!   the current DB key is still in memory.
//!
//! All three are atomic per file (`<file>.tmp` + `fsync` + `rename`)
//! so a crash mid-walk leaves either the old or the new shape on
//! disk — never a half-migrated file. They walk
//! `<recordings_root>/<session_id>/<basename>.<ext>`; symlinks are
//! followed only through directory components, file-level symlinks
//! are skipped (mirrors the [`crate::recorder::browser`] discipline).
//!
//! Failures during the walk surface as the first error — the caller
//! decides whether to abort or proceed. The recommended posture is
//! abort-then-restore: if [`rewrap_all_headers`] fails partway, do
//! NOT swap the active DB-key slot, because any rewrapped headers
//! are now bound to a key the [`crate::secrets::SecretStore`] does
//! not yet hold.

use std::fs;
use std::io::{Read, Write};
use std::path::{Path, PathBuf};

use crate::error::Error;
use crate::recorder::index_sidecar;
use crate::recorder::{
    LFR_HEADER_LEN, LFR_MAGIC, LFR_VERSION, MAX_FRAME_PLAINTEXT_BYTES, NONCE_LEN,
};

/// Outcome of a recordings-tree migration sweep. Single counter per
/// shape so callers can log a one-liner.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct MigrateOutcome {
    /// Number of `.lfsr` files whose 65-byte header was rewrapped
    /// in place under the new DB key. Frames + sidecars stayed put.
    pub headers_rewrapped: u32,
    /// Number of `.cast` files promoted to fresh `.lfsr` under the
    /// new DB key. Their plaintext is now encrypted under a per-file
    /// recording key wrapped in the v1 header.
    pub cast_to_lfsr: u32,
    /// Number of `.lfsr` files demoted to plaintext `.cast`. Their
    /// encrypted sidecars dropped — plaintext recordings rebuild
    /// the sidecar on next open if the index helper grows one.
    pub lfsr_to_cast: u32,
    /// Files the sweep walked but did not touch — already in the
    /// target shape (idempotent re-run) or in the other format
    /// (e.g. a stray `.cast` during a header-rewrap).
    pub skipped: u32,
}

/// Walk the recordings tree under `root` and rewrite every `.lfsr`
/// file's 65-byte header so the wrapped per-file recording key is
/// bound to `new_db_key` instead of `old_db_key`. Frame bodies and
/// sidecars are left untouched — the recording key itself does not
/// change, only the AES-256-GCM wrap that holds it.
///
/// Atomic per file: write the new header to `<file>.tmp.<random>`,
/// follow with the existing body bytes, `fsync`, then rename over
/// the original. A crash mid-walk leaves either the old or the new
/// file at every step — never a torn header.
///
/// Idempotent re-run with the same `(old, new)` pair is a no-op
/// once the sweep has completed: the second pass's unwrap fails
/// under the old key (because the headers were already rewrapped),
/// the file is skipped, and the outcome counter only reports new
/// rewraps.
pub fn rewrap_all_headers(
    root: &Path,
    old_db_key: &[u8; 32],
    new_db_key: &[u8; 32],
) -> Result<MigrateOutcome, Error> {
    let mut outcome = MigrateOutcome::default();
    if !root.is_dir() {
        return Ok(outcome);
    }
    for_each_lfsr_file(root, |path| {
        match rewrap_one_header(path, old_db_key, new_db_key) {
            Ok(true) => outcome.headers_rewrapped += 1,
            Ok(false) => outcome.skipped += 1,
            Err(e) => return Err(e),
        }
        Ok(())
    })?;
    Ok(outcome)
}

/// Walk the recordings tree under `root` and promote every `.cast`
/// file (plaintext asciinema) to a fresh `.lfsr` file encrypted
/// under `new_db_key`. The promoted file uses the canonical v1
/// LFR1 layout — random per-file recording key wrapped in the
/// header, AES-256-GCM frame body with `frame_index` AAD.
///
/// A fresh encrypted sidecar is built alongside, mirroring the
/// per-frame offsets so playback's scrub bar lights up on the
/// first open without sequential-decode fallback.
///
/// The original `.cast` is removed only after the new `.lfsr` +
/// sidecar are `fsync`-ed in place. A crash mid-convert leaves the
/// `.cast` intact + an orphan `.tmp.lfsr`; resumption picks up the
/// next `.cast` since the original is still there.
pub fn convert_all_cast_to_lfsr(
    root: &Path,
    new_db_key: &[u8; 32],
) -> Result<MigrateOutcome, Error> {
    let mut outcome = MigrateOutcome::default();
    if !root.is_dir() {
        return Ok(outcome);
    }
    for_each_file_with_ext(root, "cast", |path| {
        match convert_one_cast_to_lfsr(path, new_db_key) {
            Ok(true) => outcome.cast_to_lfsr += 1,
            Ok(false) => outcome.skipped += 1,
            Err(e) => return Err(e),
        }
        Ok(())
    })?;
    Ok(outcome)
}

/// Walk the recordings tree under `root` and demote every `.lfsr`
/// file to a plaintext `.cast` by decrypting each frame under the
/// recording key the header carries. `current_db_key` must be the
/// DB key the headers are currently wrapped under — typically the
/// active slot just before the caller flushes it on a `T1 → T0`
/// disable.
///
/// The encrypted sidecar drops with the `.lfsr` rename — playback
/// of the resulting `.cast` falls back to sequential decode for
/// scrub-bar seeks. A future plaintext-sidecar pass can rebuild
/// it lazily; the current behaviour keeps the `T1 → T0` flow
/// O(plaintext bytes written) without an extra index pass.
pub fn convert_all_lfsr_to_cast(
    root: &Path,
    current_db_key: &[u8; 32],
) -> Result<MigrateOutcome, Error> {
    let mut outcome = MigrateOutcome::default();
    if !root.is_dir() {
        return Ok(outcome);
    }
    for_each_lfsr_file(root, |path| {
        match convert_one_lfsr_to_cast(path, current_db_key) {
            Ok(true) => outcome.lfsr_to_cast += 1,
            Ok(false) => outcome.skipped += 1,
            Err(e) => return Err(e),
        }
        Ok(())
    })?;
    Ok(outcome)
}

// ──────────────────────────────────────────────────────────────────
// Internals
// ──────────────────────────────────────────────────────────────────

/// Rewrap one `.lfsr` file's 65-byte header from `old_db_key` to
/// `new_db_key`. Returns `Ok(true)` when the rewrap happened,
/// `Ok(false)` when the file was already on the new key (the
/// `old_db_key` unwrap failed — idempotent skip), or `Err` for I/O
/// failures.
fn rewrap_one_header(
    path: &Path,
    old_db_key: &[u8; 32],
    new_db_key: &[u8; 32],
) -> Result<bool, Error> {
    let mut file = match fs::File::open(path) {
        Ok(f) => f,
        Err(e) => {
            return Err(Error::Recorder(format!(
                "rewrap open {}: {e}",
                path.display()
            )))
        }
    };
    let mut header = [0u8; LFR_HEADER_LEN];
    if file.read_exact(&mut header).is_err() {
        // Truncated / corrupt — treat as skip so one stuck file
        // does not block the sweep. Caller logs separately.
        return Ok(false);
    }
    if header[..4] != LFR_MAGIC || header[4] != LFR_VERSION {
        return Ok(false);
    }
    // Idempotent skip: if the header already unwraps under the NEW
    // key, the sweep ran earlier with this pair. Don't re-rewrap.
    if super::unwrap_lfsr_header(&header, new_db_key).is_ok() {
        return Ok(false);
    }
    let recording_key = match super::unwrap_lfsr_header(&header, old_db_key) {
        Ok(rk) => rk,
        Err(_) => return Ok(false),
    };
    let mut rk_arr = [0u8; 32];
    rk_arr.copy_from_slice(&recording_key[..]);
    let new_header = super::build_lfsr_header(new_db_key, &rk_arr)?;
    // Drop the bound-to-old-key recording key copy as soon as we
    // have the new header built — `recording_key` is Zeroizing so
    // it scrubs on the let-binding's end-of-scope.
    drop(recording_key);

    // Atomic in-place header rewrite: write new file with the new
    // header followed by the existing body, fsync, rename over.
    // The existing reader requires `[header][frames…]` contiguous,
    // so a partial-overwrite of the header risks a truncated body
    // when the OS schedules our write between magic and frame.
    let tmp = atomic_tmp_path(path)?;
    {
        let mut out = fs::File::create(&tmp)
            .map_err(|e| Error::Recorder(format!("rewrap tmp create {}: {e}", tmp.display())))?;
        out.write_all(&new_header)
            .map_err(|e| Error::Recorder(format!("rewrap tmp header: {e}")))?;
        // Stream the body from the original file. The cursor sits
        // right after `header` from the earlier `read_exact`.
        copy_remaining(&mut file, &mut out)?;
        out.sync_all()
            .map_err(|e| Error::Recorder(format!("rewrap tmp fsync: {e}")))?;
    }
    if let Err(msg) = crate::path::harden_file_perms(&tmp) {
        return Err(Error::Recorder(format!("rewrap tmp harden: {msg}")));
    }
    fs::rename(&tmp, path).map_err(|e| {
        // Best-effort tmp cleanup — leaving the tmp on rename
        // failure would otherwise pile up under the recordings
        // dir on every re-run.
        let _ = fs::remove_file(&tmp);
        Error::Recorder(format!("rewrap rename {}: {e}", path.display()))
    })?;
    Ok(true)
}

/// Promote one `.cast` plaintext recording to a freshly-encrypted
/// `.lfsr` under `new_db_key`. The original `.cast` + its (optional
/// plaintext) sidecar are removed only after the new `.lfsr` +
/// encrypted sidecar are `fsync`-ed.
fn convert_one_cast_to_lfsr(cast_path: &Path, new_db_key: &[u8; 32]) -> Result<bool, Error> {
    let stem = cast_path
        .file_stem()
        .and_then(|s| s.to_str())
        .ok_or_else(|| Error::Recorder(format!("cast path bad stem: {}", cast_path.display())))?;
    let parent = cast_path
        .parent()
        .ok_or_else(|| Error::Recorder(format!("cast path no parent: {}", cast_path.display())))?;
    let lfsr_path = parent.join(format!("{stem}.lfsr"));
    if lfsr_path.exists() {
        // A previous sweep already produced the `.lfsr` and crashed
        // before deleting the source `.cast`. Conservative skip —
        // leave both intact so the user can decide which to keep.
        return Ok(false);
    }

    // Generate the fresh per-file recording key + write the v1
    // header. Each frame is one line of the .cast file (asciinema
    // JSON-Lines), encrypted with `frame_index` as AAD.
    let mut rk_bytes = [0u8; 32];
    use rand::Rng;
    rand::rng().fill_bytes(&mut rk_bytes);
    let recording_key = zeroize::Zeroizing::new(rk_bytes);
    let header = super::build_lfsr_header(new_db_key, &recording_key)?;

    let tmp_lfsr = atomic_tmp_path(&lfsr_path)?;
    let tmp_idx_path = atomic_tmp_path(&index_sidecar::sidecar_path(&lfsr_path))?;

    let cast_file = fs::File::open(cast_path)
        .map_err(|e| Error::Recorder(format!("cast open {}: {e}", cast_path.display())))?;
    let mut cast_reader = std::io::BufReader::new(cast_file);

    // Build a sidecar writer side-by-side so seek works on first
    // playback. Derive the same HKDF chain `derive_index_key` does.
    let index_key = derive_index_key_from_recording(&recording_key)?;
    let mut sidecar = index_sidecar::IndexWriter::create(&tmp_idx_path, Some(index_key))
        .map_err(|e| Error::Recorder(format!("sidecar create: {e}")))?;

    let mut frame_index: u64 = 0;
    let mut bytes_written: u64 = 0;
    {
        let mut out = fs::File::create(&tmp_lfsr)
            .map_err(|e| Error::Recorder(format!("cast→lfsr tmp create: {e}")))?;
        out.write_all(&header)
            .map_err(|e| Error::Recorder(format!("cast→lfsr header: {e}")))?;
        bytes_written += header.len() as u64;

        let mut buf = Vec::with_capacity(256);
        loop {
            buf.clear();
            // Bound each line at the same cap the reader enforces
            // so a malformed cast cannot pull a multi-GiB read.
            let mut take = (&mut cast_reader).take(MAX_FRAME_PLAINTEXT_BYTES as u64 + 1);
            use std::io::BufRead as _;
            match take.read_until(b'\n', &mut buf) {
                Ok(0) => break,
                Ok(_) => {}
                Err(e) => {
                    return Err(Error::Recorder(format!(
                        "cast read {}: {e}",
                        cast_path.display()
                    )));
                }
            }
            // Skip empty lines — same posture as the reader.
            if buf.iter().all(|b| matches!(b, b'\r' | b'\n')) {
                continue;
            }
            bytes_written += encode_cast_frame(
                &buf,
                frame_index,
                bytes_written,
                &recording_key,
                &mut out,
                &mut sidecar,
            )?;
            frame_index = frame_index.saturating_add(1);
        }
        out.sync_all()
            .map_err(|e| Error::Recorder(format!("cast→lfsr fsync: {e}")))?;
    }
    if let Err(msg) = crate::path::harden_file_perms(&tmp_lfsr) {
        return Err(Error::Recorder(format!("cast→lfsr harden: {msg}")));
    }
    // The sidecar writer flushes its own header on Drop / append.
    drop(sidecar);
    if tmp_idx_path.exists() {
        if let Err(msg) = crate::path::harden_file_perms(&tmp_idx_path) {
            return Err(Error::Recorder(format!("cast→lfsr sidecar harden: {msg}")));
        }
    }

    // Commit: rename the .lfsr first; if the sidecar rename fails
    // afterwards, playback still works (sequential fallback) —
    // a missing sidecar is non-fatal.
    fs::rename(&tmp_lfsr, &lfsr_path).map_err(|e| {
        let _ = fs::remove_file(&tmp_lfsr);
        let _ = fs::remove_file(&tmp_idx_path);
        Error::Recorder(format!("cast→lfsr rename {}: {e}", lfsr_path.display()))
    })?;
    if tmp_idx_path.exists() {
        let final_idx = index_sidecar::sidecar_path(&lfsr_path);
        if let Err(e) = fs::rename(&tmp_idx_path, &final_idx) {
            crate::app_log_warn!(
                "Recorder",
                "cast→lfsr sidecar rename failed (best-effort): {e}"
            );
            let _ = fs::remove_file(&tmp_idx_path);
        }
    }

    // Source removal happens last so a crash before this point
    // leaves the .cast intact. The .lfsr now exists; future
    // sweeps see the .cast still around and would re-promote it.
    // Detect that via the early `if lfsr_path.exists() return` guard.
    let _ = fs::remove_file(cast_path);
    // Plaintext recordings used to write a plaintext sidecar (when
    // we ship the lazy-build path). If one exists, drop it — the
    // `.cast` is gone.
    let cast_sidecar = index_sidecar::sidecar_path(cast_path);
    if cast_sidecar.exists() {
        let _ = fs::remove_file(&cast_sidecar);
    }
    Ok(true)
}

/// Encrypt and write one `.cast` line as an `.lfsr` frame, appending
/// a best-effort sidecar entry. `frame_offset` is the byte offset
/// the frame starts at on disk (`bytes_written` before this call),
/// which the sidecar maps a target timestamp into. Returns the
/// number of bytes written for this frame so the caller can advance
/// its running offset.
///
/// Frame layout: `[len(4 LE)][nonce(12)][ct+tag(payload+16)]`.
/// AAD = `frame_index` as little-endian u64, same as the writer.
fn encode_cast_frame(
    payload: &[u8],
    frame_index: u64,
    frame_offset: u64,
    recording_key: &[u8; 32],
    out: &mut fs::File,
    sidecar: &mut index_sidecar::IndexWriter,
) -> Result<u64, Error> {
    use rand::Rng;
    let mut nonce = [0u8; NONCE_LEN];
    rand::rng().fill_bytes(&mut nonce);
    let aad = frame_index.to_le_bytes();
    let ct = crate::crypto::aes_gcm_encrypt_raw(&recording_key[..], &nonce, payload, &aad)?;
    let pt_len = u32::try_from(payload.len())
        .map_err(|_| Error::Recorder("cast frame payload exceeds u32 length".to_string()))?;
    out.write_all(&pt_len.to_le_bytes())
        .and_then(|_| out.write_all(&nonce))
        .and_then(|_| out.write_all(&ct))
        .map_err(|e| Error::Recorder(format!("cast→lfsr frame write: {e}")))?;

    // Append a sidecar entry per event (not per header line).
    // The first line in an asciinema cast is the header
    // object; events start at line 2. We treat every line
    // the same — the cap reader skips the header at
    // playback time so a few unreachable sidecar entries
    // are harmless.
    if let Some(ts_ms) = parse_event_timestamp_ms(payload) {
        let entry = index_sidecar::IndexEntry {
            offset: frame_offset,
            timestamp_ms: ts_ms,
        };
        if let Err(e) = sidecar.append(entry) {
            crate::app_log_warn!(
                "Recorder",
                "convert cast→lfsr sidecar append failed (best-effort): {e}"
            );
        }
    }
    Ok(4 + NONCE_LEN as u64 + ct.len() as u64)
}

/// Demote one `.lfsr` recording to plaintext `.cast`. Reads the
/// header under `current_db_key`, decrypts each frame, writes the
/// JSON-Lines record verbatim to a new `.cast`. The encrypted
/// sidecar drops alongside the `.lfsr` — playback re-builds it
/// (or falls back to sequential decode) on next open.
fn convert_one_lfsr_to_cast(lfsr_path: &Path, current_db_key: &[u8; 32]) -> Result<bool, Error> {
    let stem = lfsr_path
        .file_stem()
        .and_then(|s| s.to_str())
        .ok_or_else(|| Error::Recorder(format!("lfsr path bad stem: {}", lfsr_path.display())))?;
    let parent = lfsr_path
        .parent()
        .ok_or_else(|| Error::Recorder(format!("lfsr path no parent: {}", lfsr_path.display())))?;
    let cast_path = parent.join(format!("{stem}.cast"));
    if cast_path.exists() {
        return Ok(false);
    }

    // Stream-decrypt the body via the existing reader so the AAD
    // chain matches the recorder's writer exactly. The reader
    // unwraps the header internally under `current_db_key`.
    let iter = super::reader::open_lfsr_iter(lfsr_path, *current_db_key)
        .map_err(|e| Error::Recorder(format!("lfsr open {}: {e}", lfsr_path.display())))?;

    let tmp_cast = atomic_tmp_path(&cast_path)?;
    {
        let mut out = fs::File::create(&tmp_cast)
            .map_err(|e| Error::Recorder(format!("lfsr→cast tmp create: {e}")))?;
        for record in iter {
            let line = record.map_err(|e| Error::Recorder(format!("lfsr→cast frame: {e}")))?;
            // Reader trims the trailing newline — restore it so the
            // resulting `.cast` is valid asciinema JSON-Lines.
            out.write_all(line.as_bytes())
                .and_then(|_| out.write_all(b"\n"))
                .map_err(|e| Error::Recorder(format!("lfsr→cast line write: {e}")))?;
        }
        out.sync_all()
            .map_err(|e| Error::Recorder(format!("lfsr→cast fsync: {e}")))?;
    }
    if let Err(msg) = crate::path::harden_file_perms(&tmp_cast) {
        return Err(Error::Recorder(format!("lfsr→cast harden: {msg}")));
    }
    fs::rename(&tmp_cast, &cast_path).map_err(|e| {
        let _ = fs::remove_file(&tmp_cast);
        Error::Recorder(format!("lfsr→cast rename {}: {e}", cast_path.display()))
    })?;
    // Drop the encrypted body + its sidecar.
    let _ = fs::remove_file(lfsr_path);
    let lfsr_sidecar = index_sidecar::sidecar_path(lfsr_path);
    if lfsr_sidecar.exists() {
        let _ = fs::remove_file(&lfsr_sidecar);
    }
    Ok(true)
}

/// HKDF chain off the per-file recording key matching
/// `recorder::derive_index_key`. Kept here as a small private
/// helper so the migration sidecar build stays independent of the
/// `RecorderRegistry::register_with_io` write path.
fn derive_index_key_from_recording(
    recording_key: &[u8; 32],
) -> Result<zeroize::Zeroizing<[u8; 32]>, Error> {
    let derived =
        crate::crypto::hkdf_sha256(recording_key, &[], index_sidecar::INDEX_HKDF_INFO, 32)?;
    let arr: [u8; 32] = derived
        .as_slice()
        .try_into()
        .map_err(|_| Error::Recorder("index key derivation length".to_string()))?;
    Ok(zeroize::Zeroizing::new(arr))
}

/// Parse the second element of an asciinema event tuple to
/// milliseconds. Returns `None` for the header line (object, not
/// array), malformed JSON, or anything not shaped as
/// `[ts, "o"|"i", "data"]`. Bounded numeric clamp matches
/// `record_event` so a runaway `f64::INFINITY` does not panic.
fn parse_event_timestamp_ms(payload: &[u8]) -> Option<u32> {
    let value: serde_json::Value = serde_json::from_slice(payload).ok()?;
    let arr = value.as_array()?;
    if arr.len() < 3 {
        return None;
    }
    let ts = arr[0].as_f64()?;
    let ms = (ts * 1000.0).clamp(0.0, u32::MAX as f64);
    Some(ms as u32)
}

/// Walk every `<root>/<session>/<file>.lfsr` and apply `op`. Keeps
/// the symlink discipline tight — see the file-level safety
/// rationale: symlinks at the file layer are skipped; directories
/// follow the OS's `read_dir` (no extra `O_NOFOLLOW` because the
/// recordings tree is always under app-support, which the OS
/// enforces against non-app writes anyway).
fn for_each_lfsr_file<F: FnMut(&Path) -> Result<(), Error>>(
    root: &Path,
    mut op: F,
) -> Result<(), Error> {
    for_each_file_with_ext(root, "lfsr", &mut op)
}

fn for_each_file_with_ext<F: FnMut(&Path) -> Result<(), Error>>(
    root: &Path,
    ext: &str,
    mut op: F,
) -> Result<(), Error> {
    let entries = match fs::read_dir(root) {
        Ok(it) => it,
        Err(_) => return Ok(()),
    };
    for session_entry in entries.flatten() {
        if !session_entry
            .file_type()
            .map(|t| t.is_dir())
            .unwrap_or(false)
        {
            continue;
        }
        apply_in_session_dir(&session_entry.path(), ext, &mut op)?;
    }
    Ok(())
}

/// Apply `op` to every file directly under `session_path` whose
/// extension matches `ext` (ASCII-case-insensitive). Symlinks and
/// nested directories at the file layer are skipped; an unreadable
/// session directory is silently ignored (the caller already
/// filtered to directories).
fn apply_in_session_dir<F: FnMut(&Path) -> Result<(), Error>>(
    session_path: &Path,
    ext: &str,
    op: &mut F,
) -> Result<(), Error> {
    let inner = match fs::read_dir(session_path) {
        Ok(it) => it,
        Err(_) => return Ok(()),
    };
    for file_entry in inner.flatten() {
        let file_path = file_entry.path();
        // Skip symlinks + directories at the file layer.
        if !file_entry.file_type().map(|t| t.is_file()).unwrap_or(false) {
            continue;
        }
        let matches = file_path
            .extension()
            .and_then(|e| e.to_str())
            .map(|s| s.eq_ignore_ascii_case(ext))
            .unwrap_or(false);
        if !matches {
            continue;
        }
        op(&file_path)?;
    }
    Ok(())
}

/// Per-file scratch path under the same directory. Picking a
/// fresh suffix per call so two interleaved sweeps cannot collide
/// (sweep retries on the same recording during the same session).
fn atomic_tmp_path(target: &Path) -> Result<PathBuf, Error> {
    use rand::Rng;
    let mut bytes = [0u8; 8];
    rand::rng().fill_bytes(&mut bytes);
    let suffix: String = bytes.iter().map(|b| format!("{b:02x}")).collect();
    let parent = target
        .parent()
        .ok_or_else(|| Error::Recorder(format!("tmp target no parent: {}", target.display())))?;
    let name = target
        .file_name()
        .and_then(|s| s.to_str())
        .ok_or_else(|| Error::Recorder(format!("tmp target bad name: {}", target.display())))?;
    Ok(parent.join(format!("{name}.tmp.{suffix}")))
}

/// Stream the rest of `src` into `dst` in 64 KiB chunks. Used by
/// the in-place rewrap to copy the body after the new header lands
/// in the temp file.
fn copy_remaining(src: &mut fs::File, dst: &mut fs::File) -> Result<(), Error> {
    let mut buf = [0u8; 64 * 1024];
    loop {
        let n = src
            .read(&mut buf)
            .map_err(|e| Error::Recorder(format!("copy_remaining read: {e}")))?;
        if n == 0 {
            return Ok(());
        }
        dst.write_all(&buf[..n])
            .map_err(|e| Error::Recorder(format!("copy_remaining write: {e}")))?;
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::bus::EventBus;
    use crate::recorder::{RecordDirection, RecorderRegistry};
    use std::sync::atomic::{AtomicU64, Ordering};

    fn fresh_recordings_root(tag: &str) -> PathBuf {
        static SEQ: AtomicU64 = AtomicU64::new(0);
        let n = SEQ.fetch_add(1, Ordering::SeqCst);
        let pid = std::process::id();
        let dir = std::env::temp_dir().join(format!("lfs_mig_test_{tag}_{pid}_{n}"));
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    /// Build one real .lfsr + sidecar under `<root>/<session>/<id>.lfsr`
    /// driven through the live writer so the header, frame layout, and
    /// sidecar chain match a production recording byte-for-byte.
    fn record_one(
        root: &Path,
        session: &str,
        db_key: &[u8; 32],
        events: &[(&str, &str)],
    ) -> PathBuf {
        let session_dir = root.join(session);
        std::fs::create_dir_all(&session_dir).unwrap();
        let file_path = session_dir.join(format!("rec-{}.lfsr", session));
        let bus = EventBus::new();
        let reg = RecorderRegistry::new();
        let id = format!("r-{session}");
        reg.register_with_io(
            id.clone(),
            session.to_string(),
            file_path.to_string_lossy().into_owned(),
            Some(zeroize::Zeroizing::new(*db_key)),
            &bus,
        )
        .unwrap();
        // Asciinema header is required for the lfsr → cast helper's
        // smoke checks (line 0 starts with `{"version":2`), and the
        // rewrap round-trip test counts records including the
        // header — emit it here so both call sites match real
        // recordings byte-for-byte.
        reg.record_header(&id, 80, 24, "/bin/bash", &bus).unwrap();
        for (dir, payload) in events {
            let direction = match *dir {
                "o" => RecordDirection::Output,
                "i" => RecordDirection::Input,
                _ => unreachable!(),
            };
            reg.record_event(&id, direction, payload.as_bytes(), &bus)
                .unwrap();
        }
        reg.close_with_io(&id, &bus).unwrap();
        file_path
    }

    #[test]
    fn rewrap_all_headers_round_trips_under_new_key() {
        let root = fresh_recordings_root("rewrap");
        let old_db = [0x11u8; 32];
        let new_db = [0x22u8; 32];
        let p = record_one(&root, "s1", &old_db, &[("o", "hello"), ("i", "q")]);

        // Before rewrap the file unwraps under the OLD key, not new.
        let before = std::fs::read(&p).unwrap();
        assert!(super::super::unwrap_lfsr_header(&before[..LFR_HEADER_LEN], &old_db).is_ok());
        assert!(super::super::unwrap_lfsr_header(&before[..LFR_HEADER_LEN], &new_db).is_err());

        let outcome = rewrap_all_headers(&root, &old_db, &new_db).unwrap();
        assert_eq!(outcome.headers_rewrapped, 1);
        assert_eq!(outcome.skipped, 0);

        // After rewrap the file unwraps under the NEW key, not old.
        let after = std::fs::read(&p).unwrap();
        assert!(super::super::unwrap_lfsr_header(&after[..LFR_HEADER_LEN], &new_db).is_ok());
        assert!(super::super::unwrap_lfsr_header(&after[..LFR_HEADER_LEN], &old_db).is_err());

        // Frame bodies are byte-identical past the 65-byte header.
        assert_eq!(after.len(), before.len());
        assert_eq!(&after[LFR_HEADER_LEN..], &before[LFR_HEADER_LEN..]);

        // Re-running the rewrap with the same pair is a no-op —
        // headers already on the new key. Idempotency.
        let outcome2 = rewrap_all_headers(&root, &old_db, &new_db).unwrap();
        assert_eq!(outcome2.headers_rewrapped, 0);
        assert_eq!(outcome2.skipped, 1);

        // Playback still works under the new key.
        let iter = super::super::reader::open_lfsr_iter(&p, new_db).unwrap();
        let lines: Vec<_> = iter.map(|r| r.unwrap()).collect();
        // asciinema header + 2 events.
        assert_eq!(lines.len(), 3);

        std::fs::remove_dir_all(&root).ok();
    }

    #[test]
    fn rewrap_skips_files_under_wrong_old_key() {
        let root = fresh_recordings_root("skip-wrong");
        let real_db = [0x77u8; 32];
        let wrong_db = [0x88u8; 32];
        let new_db = [0x99u8; 32];
        record_one(&root, "s1", &real_db, &[("o", "ping")]);
        // Walking with the wrong "old" key: every unwrap fails, so
        // every file should be skipped — not corrupted, not
        // rewrapped under a key the user did not authorize.
        let outcome = rewrap_all_headers(&root, &wrong_db, &new_db).unwrap();
        assert_eq!(outcome.headers_rewrapped, 0);
        assert_eq!(outcome.skipped, 1);
        std::fs::remove_dir_all(&root).ok();
    }

    #[test]
    fn convert_cast_to_lfsr_round_trips_under_new_key() {
        let root = fresh_recordings_root("c2l");
        let new_db = [0x44u8; 32];
        let session_dir = root.join("s1");
        std::fs::create_dir_all(&session_dir).unwrap();
        let cast_path = session_dir.join("rec.cast");
        let body =
            "{\"version\":2,\"width\":80,\"height\":24}\n[0.1,\"o\",\"hi\"]\n[0.5,\"i\",\"q\"]\n";
        std::fs::write(&cast_path, body).unwrap();

        let outcome = convert_all_cast_to_lfsr(&root, &new_db).unwrap();
        assert_eq!(outcome.cast_to_lfsr, 1);
        let lfsr_path = session_dir.join("rec.lfsr");
        assert!(lfsr_path.exists());
        assert!(!cast_path.exists());

        // Playback yields the original lines under the new DB key.
        let iter = super::super::reader::open_lfsr_iter(&lfsr_path, new_db).unwrap();
        let lines: Vec<_> = iter.map(|r| r.unwrap()).collect();
        assert_eq!(
            lines,
            vec![
                "{\"version\":2,\"width\":80,\"height\":24}".to_string(),
                "[0.1,\"o\",\"hi\"]".to_string(),
                "[0.5,\"i\",\"q\"]".to_string(),
            ]
        );

        std::fs::remove_dir_all(&root).ok();
    }

    #[test]
    fn convert_lfsr_to_cast_round_trips_to_plaintext() {
        let root = fresh_recordings_root("l2c");
        let db = [0x55u8; 32];
        let lfsr_path = record_one(&root, "s1", &db, &[("o", "alpha"), ("o", "beta")]);

        let outcome = convert_all_lfsr_to_cast(&root, &db).unwrap();
        assert_eq!(outcome.lfsr_to_cast, 1);
        let cast_path = lfsr_path.with_extension("cast");
        assert!(cast_path.exists());
        assert!(!lfsr_path.exists());

        // .cast is plain asciinema JSON-Lines.
        let cast_body = std::fs::read_to_string(&cast_path).unwrap();
        let lines: Vec<_> = cast_body.lines().collect();
        // Header object + 2 event tuples.
        assert!(lines[0].starts_with("{\"version\":2"));
        assert!(lines[1].contains("\"o\""));
        assert!(lines[1].contains("alpha"));
        assert!(lines[2].contains("beta"));

        std::fs::remove_dir_all(&root).ok();
    }

    #[test]
    fn round_trip_cast_lfsr_cast_preserves_event_payloads() {
        // T0 → T1 → T0: starts plaintext, encrypted under DB key,
        // back to plaintext. The frame payloads must match across
        // the two cast files byte-for-byte (modulo header which
        // the recorder produces fresh).
        let root = fresh_recordings_root("round");
        let db = [0x66u8; 32];
        let session_dir = root.join("s1");
        std::fs::create_dir_all(&session_dir).unwrap();
        let cast_path = session_dir.join("rec.cast");
        let original_body =
            "{\"version\":2,\"width\":80,\"height\":24}\n[0.1,\"o\",\"hi\"]\n[0.5,\"i\",\"q\"]\n";
        std::fs::write(&cast_path, original_body).unwrap();

        convert_all_cast_to_lfsr(&root, &db).unwrap();
        assert!(session_dir.join("rec.lfsr").exists());
        convert_all_lfsr_to_cast(&root, &db).unwrap();
        let final_body = std::fs::read_to_string(&cast_path).unwrap();

        // The asciinema events round-trip exactly; the header line
        // might differ in numeric precision so just smoke-check the
        // event tuples.
        let final_lines: Vec<&str> = final_body.lines().collect();
        assert!(final_lines[1].contains("\"o\""));
        assert!(final_lines[1].contains("hi"));
        assert!(final_lines[2].contains("\"i\""));
        assert!(final_lines[2].contains("q"));

        std::fs::remove_dir_all(&root).ok();
    }

    #[test]
    fn rewrap_missing_root_returns_empty_outcome() {
        let root = std::env::temp_dir().join(format!("lfs_mig_missing_{}", std::process::id()));
        let outcome = rewrap_all_headers(&root, &[0u8; 32], &[1u8; 32]).unwrap();
        assert_eq!(outcome, MigrateOutcome::default());
    }
}
