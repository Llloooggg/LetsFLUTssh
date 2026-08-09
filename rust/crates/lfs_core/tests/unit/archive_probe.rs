/// Unit tests extracted from archive/probe.rs
/// Declared via `#[path] mod tests;` in the source file.
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
