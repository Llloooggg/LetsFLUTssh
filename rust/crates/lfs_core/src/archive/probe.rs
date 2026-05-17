//! `.lfs` candidate-file classifier — pre-decrypt probe used by the
//! file-picker flow to decide whether to prompt for a password,
//! offer the unencrypted-ZIP path, or reject the file before any
//! crypto runs.
//!
//! Mirrors the Dart-era `ExportImport.probeArchive` classifier, but
//! lives Rust-side so the ZIP decoder + size caps + marker scan run
//! through `lfs_core` and `package:archive` can retire from the
//! Dart deps tree.
//!
//! The probe is best-effort: any I/O / parse error collapses to
//! [`ProbeKind::NotLfs`] so the Dart caller surfaces a single
//! friendly rejection instead of a per-error stack trace. Logging
//! captures the underlying reason so a "why did import reject my
//! file?" support trace points at the actual cause.

use std::io::{Cursor, Read};

use zip::ZipArchive;

/// What kind of file the probe found at the given path.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ProbeKind {
    /// Doesn't start with the ZIP local-file-header magic
    /// `PK\x03\x04`. Almost certainly an encrypted `.lfs` (which
    /// starts with a random 32-byte salt). Caller surfaces the
    /// password prompt.
    EncryptedLfs,
    /// Plain ZIP that contains at least one of our marker entries
    /// (`manifest.json` / `sessions.json` / `keys.json` /
    /// `config.json`). Caller imports without a password.
    UnencryptedLfs,
    /// Anything else — non-ZIP that looks ZIP-y, ZIP that doesn't
    /// carry our markers (an `.apk` or random archive picked by
    /// mistake), file too big to probe, malformed ZIP, missing
    /// file. Caller refuses the import with a friendly toast.
    NotLfs,
}

/// Maximum accepted encrypted-archive size on disk. Past this the
/// probe rejects without trying to read the file — keeps a hostile
/// 5 GiB ZIP from pinning a tokio worker on the read.
pub const MAX_ARCHIVE_BYTES: u64 = 50 * 1024 * 1024;

/// Maximum total declared-uncompressed size across every ZIP entry.
/// A zip-bomb crafted to claim petabytes of inflation is rejected
/// at the per-entry-size scan before any decompression runs.
pub const MAX_DECOMPRESSED_BYTES: u64 = 200 * 1024 * 1024;

/// Marker entries we look for inside a plain ZIP. The presence of
/// any one is enough to classify as `unencryptedLfs` — the apply
/// driver tolerates partial archives and surfaces missing-entry
/// errors via [`super::apply::ApplyResult::errors`].
const MARKERS: &[&str] = &["manifest.json", "sessions.json", "config.json", "keys.json"];

/// Classify the file at [`path`]. See module doc for the variant
/// semantics. Pure best-effort: any I/O error → `NotLfs`.
pub fn probe(path: &str) -> ProbeKind {
    classify_or_default(path).unwrap_or(ProbeKind::NotLfs)
}

fn classify_or_default(path: &str) -> Option<ProbeKind> {
    let mut f = std::fs::File::open(path).ok()?;
    let mut head = [0u8; 4];
    let read = f.read(&mut head).ok()?;
    if read < 4 {
        return Some(ProbeKind::NotLfs);
    }
    if !is_zip_local_header(&head) {
        // Random 32-byte salt prefix on encrypted archives — anything
        // not matching the ZIP magic gets the encrypted-LFS path. The
        // false-positive rate is ~2⁻³² and the ZIP decoder rejects the
        // garbage downstream anyway.
        return Some(ProbeKind::EncryptedLfs);
    }
    // Plain ZIP — enforce the on-disk size cap before decoding so a
    // hostile big file does not pin the read syscall.
    let size_meta = std::fs::metadata(path).ok()?;
    if size_meta.len() > MAX_ARCHIVE_BYTES {
        return Some(ProbeKind::NotLfs);
    }
    let bytes = std::fs::read(path).ok()?;
    let cursor = Cursor::new(&bytes);
    let Ok(mut zip) = ZipArchive::new(cursor) else {
        return Some(ProbeKind::NotLfs);
    };
    let mut total: u64 = 0;
    let mut found_marker = false;
    for i in 0..zip.len() {
        let Ok(entry) = zip.by_index(i) else {
            return Some(ProbeKind::NotLfs);
        };
        // Per-entry declared-uncompressed-size scan — rejects a
        // zip-bomb claiming petabytes of inflation BEFORE we
        // decompress any byte.
        total = total.saturating_add(entry.size());
        if total > MAX_DECOMPRESSED_BYTES {
            return Some(ProbeKind::NotLfs);
        }
        let name = entry.name();
        if !found_marker && MARKERS.contains(&name) {
            found_marker = true;
        }
    }
    Some(if found_marker {
        ProbeKind::UnencryptedLfs
    } else {
        ProbeKind::NotLfs
    })
}

#[inline]
fn is_zip_local_header(head: &[u8]) -> bool {
    head.len() >= 4 && head[0] == 0x50 && head[1] == 0x4B && head[2] == 0x03 && head[3] == 0x04
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write as _;

    fn write_tmp(name: &str, bytes: &[u8]) -> tempfile::NamedTempFile {
        let mut f = tempfile::Builder::new()
            .prefix(name)
            .tempfile()
            .expect("tmp");
        f.write_all(bytes).expect("write");
        f
    }

    #[test]
    fn missing_file_classifies_as_not_lfs() {
        assert_eq!(probe("/no/such/file"), ProbeKind::NotLfs);
    }

    #[test]
    fn empty_file_classifies_as_not_lfs() {
        let f = write_tmp("empty", b"");
        assert_eq!(probe(f.path().to_str().unwrap()), ProbeKind::NotLfs);
    }

    #[test]
    fn random_bytes_classify_as_encrypted_lfs() {
        // Encrypted .lfs starts with a 32-byte random salt — anything
        // not matching the ZIP magic gets the encrypted path so the
        // password dialog fires. A real garbage file would fail the
        // decrypt downstream.
        let f = write_tmp("random", b"\xab\xcd\xef\x00........");
        assert_eq!(probe(f.path().to_str().unwrap()), ProbeKind::EncryptedLfs);
    }

    #[test]
    fn zip_with_marker_classifies_as_unencrypted_lfs() {
        // Build a minimal zip carrying `sessions.json`.
        let mut buf = Vec::new();
        {
            let cursor = Cursor::new(&mut buf);
            let mut zw = zip::ZipWriter::new(cursor);
            let opts: zip::write::SimpleFileOptions = Default::default();
            zw.start_file("sessions.json", opts).unwrap();
            zw.write_all(b"[]").unwrap();
            zw.finish().unwrap();
        }
        let f = write_tmp("our-zip", &buf);
        assert_eq!(probe(f.path().to_str().unwrap()), ProbeKind::UnencryptedLfs);
    }

    #[test]
    fn zip_without_markers_classifies_as_not_lfs() {
        // An APK / unrelated archive — ZIP magic but no markers.
        let mut buf = Vec::new();
        {
            let cursor = Cursor::new(&mut buf);
            let mut zw = zip::ZipWriter::new(cursor);
            let opts: zip::write::SimpleFileOptions = Default::default();
            zw.start_file("AndroidManifest.xml", opts).unwrap();
            zw.write_all(b"<?xml?>").unwrap();
            zw.finish().unwrap();
        }
        let f = write_tmp("apk-shaped", &buf);
        assert_eq!(probe(f.path().to_str().unwrap()), ProbeKind::NotLfs);
    }
}
