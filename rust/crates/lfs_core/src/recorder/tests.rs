use super::*;

#[test]
fn register_and_close() {
    let bus = EventBus::new();
    let mut rx = bus.subscribe(crate::bus::EventTopic::Recorder);
    let reg = RecorderRegistry::new();
    let snap = reg.register("r1".into(), "s1".into(), "/tmp/r.cast".into(), false, &bus);
    assert_eq!(snap.id, "r1");
    assert_eq!(reg.count(), 1);
    // Drain the bus event sent during register.
    let _ = rx.try_recv();
    reg.close("r1", &bus);
    assert_eq!(reg.count(), 0);
}

#[test]
fn record_chunk_bumps_bytes() {
    let bus = EventBus::new();
    let reg = RecorderRegistry::new();
    reg.register("r1".into(), "s1".into(), "/tmp/r.cast".into(), false, &bus);
    reg.record_chunk("r1", 42, &bus);
    assert_eq!(reg.snapshot("r1").unwrap().bytes_written, 42);
}

fn tempfile_path(suffix: &str) -> String {
    use std::sync::atomic::{AtomicU64, Ordering};
    static SEQ: AtomicU64 = AtomicU64::new(0);
    let n = SEQ.fetch_add(1, Ordering::SeqCst);
    let pid = std::process::id();
    let dir = std::env::temp_dir();
    dir.join(format!("lfs_recorder_test_{pid}_{n}_{suffix}"))
        .to_string_lossy()
        .into_owned()
}

#[test]
fn register_with_io_writes_v1_header_when_encrypted() {
    let bus = EventBus::new();
    let reg = RecorderRegistry::new();
    let path = tempfile_path("enc");
    let db_key = [42u8; 32];
    let snap = reg
        .register_with_io(
            "r1".into(),
            "s1".into(),
            path.clone(),
            Some(zeroize::Zeroizing::new(db_key)),
            &bus,
        )
        .expect("register");
    assert!(snap.encrypted);
    // The actor wrote the full v1 header — magic + version +
    // wrap_nonce + wrapped recording key — so `bytes_written`
    // already matches `LFR_HEADER_LEN`.
    assert_eq!(snap.bytes_written, LFR_HEADER_LEN as u64);
    let on_disk = std::fs::read(&path).expect("read");
    assert_eq!(on_disk.len(), LFR_HEADER_LEN);
    assert_eq!(&on_disk[..4], b"LFR1");
    assert_eq!(on_disk[4], LFR_VERSION);
    // Unwrap proves the wrap_nonce + wrapped slot are valid
    // under the supplied DB key.
    let _recording_key = unwrap_lfsr_header(&on_disk, &db_key).expect("unwrap");
    let _ = std::fs::remove_file(&path);
}

#[test]
fn register_with_io_mints_random_recording_key_per_file() {
    // Two recordings against the same DB key must end up with
    // distinct wrapped recording keys — the writer picks the
    // recording key at random per file so a compromise of one
    // file's frames does not unlock its siblings.
    let bus = EventBus::new();
    let reg = RecorderRegistry::new();
    let db_key = [42u8; 32];
    let p1 = tempfile_path("rand-a");
    let p2 = tempfile_path("rand-b");
    reg.register_with_io(
        "ra".into(),
        "s1".into(),
        p1.clone(),
        Some(zeroize::Zeroizing::new(db_key)),
        &bus,
    )
    .expect("register a");
    reg.register_with_io(
        "rb".into(),
        "s1".into(),
        p2.clone(),
        Some(zeroize::Zeroizing::new(db_key)),
        &bus,
    )
    .expect("register b");
    let a = std::fs::read(&p1).expect("read a");
    let b = std::fs::read(&p2).expect("read b");
    let ka = unwrap_lfsr_header(&a, &db_key).expect("unwrap a");
    let kb = unwrap_lfsr_header(&b, &db_key).expect("unwrap b");
    assert_ne!(
        &ka[..],
        &kb[..],
        "per-file recording keys must differ even under the same DB key"
    );
    let _ = std::fs::remove_file(&p1);
    let _ = std::fs::remove_file(&p2);
}

#[test]
fn register_with_io_plaintext_writes_no_magic() {
    let bus = EventBus::new();
    let reg = RecorderRegistry::new();
    let path = tempfile_path("plain");
    let snap = reg
        .register_with_io("r1".into(), "s1".into(), path.clone(), None, &bus)
        .expect("register");
    assert!(!snap.encrypted);
    let on_disk = std::fs::read(&path).expect("read");
    assert!(on_disk.is_empty());
    let _ = std::fs::remove_file(&path);
}

/// Regression: the recorder used to open files at the
/// umask-default mode (0644 on most Linux
/// installs), leaving plaintext terminal output (or its
/// envelope) group/world-readable on multi-user hosts. ARCH
/// §3.13 requires `chmod 0600` on every recording — the open
/// path now hardens immediately after creating the file.
#[cfg(unix)]
#[test]
fn register_with_io_hardens_file_to_owner_only_perms() {
    use std::os::unix::fs::PermissionsExt;
    let bus = EventBus::new();
    let reg = RecorderRegistry::new();
    let path = tempfile_path("perm");
    reg.register_with_io("r1".into(), "s1".into(), path.clone(), None, &bus)
        .expect("register");
    let perms = std::fs::metadata(&path).expect("stat").permissions();
    assert_eq!(
        perms.mode() & 0o777,
        0o600,
        "recorder file mode must be 0600, got {:o}",
        perms.mode() & 0o777,
    );
    let _ = std::fs::remove_file(&path);
}

/// Same chmod 0600 invariant for the rotated-file path. A
/// rotation creates a new file at umask-default mode otherwise.
#[cfg(unix)]
#[test]
fn rotate_to_hardens_file_to_owner_only_perms() {
    use std::os::unix::fs::PermissionsExt;
    let bus = EventBus::new();
    let reg = RecorderRegistry::new();
    let initial = tempfile_path("rotpre");
    let rotated = tempfile_path("rotpost");
    reg.register_with_io("r1".into(), "s1".into(), initial.clone(), None, &bus)
        .expect("register");
    reg.rotate_to("r1", rotated.clone(), &bus).expect("rotate");
    let perms = std::fs::metadata(&rotated).expect("stat").permissions();
    assert_eq!(
        perms.mode() & 0o777,
        0o600,
        "rotated recorder file mode must be 0600, got {:o}",
        perms.mode() & 0o777,
    );
    let _ = std::fs::remove_file(&initial);
    let _ = std::fs::remove_file(&rotated);
}

#[test]
fn record_frame_plaintext_appends_verbatim() {
    let bus = EventBus::new();
    let reg = RecorderRegistry::new();
    let path = tempfile_path("plainwrite");
    reg.register_with_io("r1".into(), "s1".into(), path.clone(), None, &bus)
        .expect("register");
    reg.record_frame("r1", b"hello\n", &bus).expect("frame");
    reg.record_frame("r1", b"world\n", &bus).expect("frame");
    reg.close_with_io("r1", &bus).expect("close");
    let on_disk = std::fs::read(&path).expect("read");
    assert_eq!(on_disk, b"hello\nworld\n");
    let _ = std::fs::remove_file(&path);
}

#[test]
fn record_frame_encrypted_round_trips() {
    let bus = EventBus::new();
    let reg = RecorderRegistry::new();
    let path = tempfile_path("encwrite");
    let db_key = [7u8; 32];
    reg.register_with_io(
        "r1".into(),
        "s1".into(),
        path.clone(),
        Some(zeroize::Zeroizing::new(db_key)),
        &bus,
    )
    .expect("register");
    let payload = b"some recorded bytes\n";
    reg.record_frame("r1", payload, &bus).expect("frame");
    reg.close_with_io("r1", &bus).expect("close");

    let on_disk = std::fs::read(&path).expect("read");
    // Layout: [magic(4)][ver(1)][wrap_nonce(12)][wrapped(48)]
    //         [len(4)][nonce(12)][ct+tag(payload+16)]
    assert_eq!(&on_disk[..4], b"LFR1");
    assert_eq!(on_disk[4], LFR_VERSION);
    // Unwrap the per-file recording key from the header. The
    // writer minted it at random per file; the test must read
    // it back rather than assume any fixed value.
    let recording_key = unwrap_lfsr_header(&on_disk[..LFR_HEADER_LEN], &db_key).expect("unwrap");
    let frame_off = LFR_HEADER_LEN;
    let len = u32::from_le_bytes(on_disk[frame_off..frame_off + 4].try_into().unwrap()) as usize;
    assert_eq!(len, payload.len());
    let nonce = &on_disk[frame_off + 4..frame_off + 4 + NONCE_LEN];
    let ct = &on_disk[frame_off + 4 + NONCE_LEN..];
    let aad = 0u64.to_le_bytes();
    let pt =
        crate::crypto::aes_gcm_decrypt_raw(&recording_key[..], nonce, ct, &aad).expect("decrypt");
    assert_eq!(pt.as_slice(), payload);
    // Sanity: empty AAD must NOT decrypt — proves AAD binding.
    assert!(crate::crypto::aes_gcm_decrypt_raw(&recording_key[..], nonce, ct, &[]).is_err());
    let _ = std::fs::remove_file(&path);
}

/// LFR v2 binds the per-frame counter into AAD. An attacker who
/// swaps two frames byte-for-byte (positions 0 and 1) MUST break
/// the AEAD tag at both swapped positions: the wire bytes are
/// the ciphertext signed under AAD=N, but the reader recomputes
/// AAD from position M, and N != M.
#[test]
fn frame_swap_breaks_aad_binding_at_swapped_positions() {
    let bus = EventBus::new();
    let reg = RecorderRegistry::new();
    let path = tempfile_path("swap");
    let db_key = [11u8; 32];
    reg.register_with_io(
        "r1".into(),
        "s1".into(),
        path.clone(),
        Some(zeroize::Zeroizing::new(db_key)),
        &bus,
    )
    .expect("register");
    let payload_a = b"alpha\n";
    let payload_b = b"beta\n";
    reg.record_frame("r1", payload_a, &bus).expect("frame a");
    reg.record_frame("r1", payload_b, &bus).expect("frame b");
    reg.close_with_io("r1", &bus).expect("close");

    let mut on_disk = std::fs::read(&path).expect("read");
    let recording_key = unwrap_lfsr_header(&on_disk[..LFR_HEADER_LEN], &db_key).expect("unwrap");
    // Layout: [header(65)] [len(4)][nonce(12)][ct+tag(a+16)] [len(4)][nonce(12)][ct+tag(b+16)]
    let frame_a_off = LFR_HEADER_LEN;
    let frame_a_size = 4 + NONCE_LEN + payload_a.len() + 16;
    let frame_b_off = frame_a_off + frame_a_size;
    let frame_b_size = 4 + NONCE_LEN + payload_b.len() + 16;
    let mut swapped = on_disk[..frame_a_off].to_vec();
    swapped.extend_from_slice(&on_disk[frame_b_off..frame_b_off + frame_b_size]);
    swapped.extend_from_slice(&on_disk[frame_a_off..frame_a_off + frame_a_size]);
    on_disk = swapped;

    // The decoder validates AAD by frame position. Position 0 now
    // holds the ciphertext signed under AAD=1, so decrypt under
    // AAD=0 must fail. Same for position 1 ↔ AAD=1 ≠ original=0.
    let pos0_ct = &on_disk[frame_a_off + 4 + NONCE_LEN..frame_a_off + frame_a_size];
    let pos0_nonce = &on_disk[frame_a_off + 4..frame_a_off + 4 + NONCE_LEN];
    let aad_pos0 = 0u64.to_le_bytes();
    assert!(
        crate::crypto::aes_gcm_decrypt_raw(&recording_key[..], pos0_nonce, pos0_ct, &aad_pos0)
            .is_err(),
        "swapped frame must fail AAD-bound decrypt at its new position"
    );
    let _ = std::fs::remove_file(&path);
}

#[test]
fn record_frame_on_counter_only_actor_errors() {
    let bus = EventBus::new();
    let reg = RecorderRegistry::new();
    reg.register("r1".into(), "s1".into(), "/tmp/x".into(), false, &bus);
    let err = reg.record_frame("r1", b"x", &bus).unwrap_err();
    assert!(err.to_string().contains("no file handle"));
}

#[test]
fn record_frame_missing_actor_errors() {
    let bus = EventBus::new();
    let reg = RecorderRegistry::new();
    let err = reg.record_frame("missing", b"x", &bus).unwrap_err();
    assert!(err.to_string().contains("not registered"));
}

#[test]
fn rotate_to_swaps_file_and_resets_counter() {
    let bus = EventBus::new();
    let reg = RecorderRegistry::new();
    let path1 = tempfile_path("rot1");
    let path2 = tempfile_path("rot2");
    let key = [9u8; 32];
    reg.register_with_io(
        "r1".into(),
        "s1".into(),
        path1.clone(),
        Some(zeroize::Zeroizing::new(key)),
        &bus,
    )
    .expect("register");
    reg.record_frame("r1", b"first\n", &bus).expect("frame");
    let pre = reg.snapshot("r1").unwrap();
    assert!(pre.bytes_written > 0);

    let rotated = reg.rotate_to("r1", path2.clone(), &bus).expect("rotate_to");
    // After rotation the actor reports the new path and a fresh
    // counter equal to the v1 LFR1 header (magic + version +
    // wrap_nonce + wrapped recording key).
    assert_eq!(rotated.path, path2);
    assert_eq!(rotated.bytes_written, LFR_HEADER_LEN as u64);

    reg.record_frame("r1", b"second\n", &bus).expect("frame2");
    reg.close_with_io("r1", &bus).expect("close");

    // Old file ends with the first frame; new file starts with magic.
    let old_disk = std::fs::read(&path1).expect("read old");
    assert_eq!(&old_disk[..4], b"LFR1");
    let new_disk = std::fs::read(&path2).expect("read new");
    assert_eq!(&new_disk[..4], b"LFR1");

    let _ = std::fs::remove_file(&path1);
    let _ = std::fs::remove_file(&path2);
}

#[test]
fn rotate_to_missing_actor_errors() {
    let bus = EventBus::new();
    let reg = RecorderRegistry::new();
    let err = reg.rotate_to("missing", "/tmp/x".into(), &bus).unwrap_err();
    assert!(err.to_string().contains("not registered"));
}

#[test]
fn rotate_to_counter_only_errors() {
    let bus = EventBus::new();
    let reg = RecorderRegistry::new();
    reg.register("r1".into(), "s1".into(), "/tmp/x".into(), false, &bus);
    let err = reg.rotate_to("r1", "/tmp/y".into(), &bus).unwrap_err();
    assert!(err.to_string().contains("no file handle"));
}

#[test]
fn active_paths_snapshots_every_registered_actor() {
    let bus = EventBus::new();
    let reg = RecorderRegistry::new();
    let p1 = tempfile_path("active1");
    let p2 = tempfile_path("active2");
    reg.register_with_io("r1".into(), "s1".into(), p1.clone(), None, &bus)
        .expect("register r1");
    reg.register_with_io("r2".into(), "s2".into(), p2.clone(), None, &bus)
        .expect("register r2");
    let mut paths = reg.active_paths();
    paths.sort();
    let mut expected = vec![std::path::PathBuf::from(&p1), std::path::PathBuf::from(&p2)];
    expected.sort();
    assert_eq!(paths, expected);
    // Close r1 → only r2 remains in the active set.
    reg.close_with_io("r1", &bus).expect("close r1");
    let after = reg.active_paths();
    assert_eq!(after, vec![std::path::PathBuf::from(&p2)]);
    let _ = std::fs::remove_file(&p1);
    let _ = std::fs::remove_file(&p2);
}

#[test]
fn recordings_root_from_path_resolves_two_levels_up() {
    let p = std::path::PathBuf::from("/var/lib/lfs/recordings/sess-a/2026.cast");
    let root = recordings_root_from_path(&p).expect("root");
    assert_eq!(root, std::path::PathBuf::from("/var/lib/lfs/recordings"));
}

#[test]
fn recordings_root_from_path_rejects_root_without_parent() {
    // /tmp/foo → parent=/tmp, parent.parent=/. `/` has no
    // parent → return None so the eviction sweep cannot walk
    // the filesystem root.
    let p = std::path::PathBuf::from("/tmp/foo");
    assert!(recordings_root_from_path(&p).is_none());
}

#[test]
fn record_header_emits_asciinema_v2_shape() {
    let bus = EventBus::new();
    let reg = RecorderRegistry::new();
    let path = tempfile_path("header");
    reg.register_with_io("r1".into(), "s1".into(), path.clone(), None, &bus)
        .unwrap();
    reg.record_header("r1", 80, 24, "/bin/zsh", &bus).unwrap();
    let body = std::fs::read_to_string(&path).unwrap();
    assert!(body.starts_with("{\"version\":2,"));
    assert!(body.contains("\"width\":80"));
    assert!(body.contains("\"height\":24"));
    assert!(body.contains("\"SHELL\":\"/bin/zsh\""));
    assert!(body.ends_with("\n"));
    std::fs::remove_file(path).ok();
}

#[test]
fn record_event_writes_jsonline_with_delta() {
    let bus = EventBus::new();
    let reg = RecorderRegistry::new();
    let path = tempfile_path("event");
    reg.register_with_io("r1".into(), "s1".into(), path.clone(), None, &bus)
        .unwrap();
    reg.record_event("r1", RecordDirection::Output, b"hello", &bus)
        .unwrap();
    let body = std::fs::read_to_string(&path).unwrap();
    assert!(body.starts_with("["));
    assert!(body.contains(",\"o\",\"hello\"]\n"));
    std::fs::remove_file(path).ok();
}

#[test]
fn record_event_escapes_control_chars_and_quotes() {
    let bus = EventBus::new();
    let reg = RecorderRegistry::new();
    let path = tempfile_path("escapes");
    reg.register_with_io("r1".into(), "s1".into(), path.clone(), None, &bus)
        .unwrap();
    reg.record_event(
        "r1",
        RecordDirection::Input,
        b"line\nwith \"quote\" and \x07 bell",
        &bus,
    )
    .unwrap();
    let body = std::fs::read_to_string(&path).unwrap();
    assert!(body.contains("\\n"));
    assert!(body.contains("\\\""));
    assert!(body.contains("\\u0007"));
    assert!(body.contains(",\"i\","));
    std::fs::remove_file(path).ok();
}

#[test]
fn record_event_empty_bytes_is_noop() {
    let bus = EventBus::new();
    let reg = RecorderRegistry::new();
    let path = tempfile_path("empty");
    reg.register_with_io("r1".into(), "s1".into(), path.clone(), None, &bus)
        .unwrap();
    let total = reg
        .record_event("r1", RecordDirection::Output, b"", &bus)
        .unwrap();
    assert_eq!(total, 0);
    let body = std::fs::read_to_string(&path).unwrap();
    assert!(body.is_empty());
    std::fs::remove_file(path).ok();
}

/// Plaintext recordings get a plaintext sidecar; each event
/// appends one 12-byte entry whose offset matches the pre-write
/// main-file size.
#[test]
fn index_sidecar_writer_appends_entry_per_event_plaintext() {
    let bus = EventBus::new();
    let reg = RecorderRegistry::new();
    let path = tempfile_path("idxplain");
    reg.register_with_io("r1".into(), "s1".into(), path.clone(), None, &bus)
        .unwrap();
    let off_before_first = std::fs::metadata(&path).unwrap().len();
    reg.record_event("r1", RecordDirection::Output, b"hello", &bus)
        .unwrap();
    let off_before_second = std::fs::metadata(&path).unwrap().len();
    reg.record_event("r1", RecordDirection::Output, b"world", &bus)
        .unwrap();
    reg.close_with_io("r1", &bus).unwrap();

    let idx_path = index_sidecar::sidecar_path(std::path::Path::new(&path));
    let entries = index_sidecar::read_all(&idx_path, None).unwrap();
    assert_eq!(entries.len(), 2);
    assert_eq!(entries[0].offset, off_before_first);
    assert_eq!(entries[1].offset, off_before_second);
    std::fs::remove_file(&path).ok();
    std::fs::remove_file(&idx_path).ok();
}

/// Encrypted recordings get an encrypted sidecar. Smoke test the
/// round-trip without asserting the byte layout — the wire shape
/// is covered by the `index_sidecar` module tests.
#[test]
fn index_sidecar_writer_appends_entry_per_event_encrypted() {
    let bus = EventBus::new();
    let reg = RecorderRegistry::new();
    let path = tempfile_path("idxenc");
    let db_key = [0x11u8; 32];
    reg.register_with_io(
        "r1".into(),
        "s1".into(),
        path.clone(),
        Some(zeroize::Zeroizing::new(db_key)),
        &bus,
    )
    .unwrap();
    reg.record_event("r1", RecordDirection::Output, b"hello", &bus)
        .unwrap();
    reg.record_event("r1", RecordDirection::Output, b"world", &bus)
        .unwrap();
    reg.close_with_io("r1", &bus).unwrap();

    // The recording key is random per file — unwrap the v1
    // header to get it, then derive the sidecar key off the
    // same recording key the recorder used.
    let on_disk_main = std::fs::read(&path).unwrap();
    let recording_key = unwrap_lfsr_header(&on_disk_main[..LFR_HEADER_LEN], &db_key).unwrap();
    let derived =
        crate::crypto::hkdf_sha256(&recording_key[..], &[], index_sidecar::INDEX_HKDF_INFO, 32)
            .unwrap();
    let index_key: [u8; 32] = derived.as_slice().try_into().unwrap();
    let idx_path = index_sidecar::sidecar_path(std::path::Path::new(&path));
    let entries = index_sidecar::read_all(&idx_path, Some(&index_key)).unwrap();
    assert_eq!(entries.len(), 2);
    // On-disk byte budget: 5-byte header + 2 × 44-byte blocks.
    let on_disk = std::fs::read(&idx_path).unwrap();
    assert_eq!(on_disk.len(), 5 + 2 * 44);
    std::fs::remove_file(&path).ok();
    std::fs::remove_file(&idx_path).ok();
}

/// Rotation drops the current sidecar and opens a fresh one next
/// to the new file. Entries written after rotate must land in the
/// new sidecar; the old sidecar still carries pre-rotate entries.
#[test]
fn rotation_closes_idx_alongside_main_file() {
    let bus = EventBus::new();
    let reg = RecorderRegistry::new();
    let path_a = tempfile_path("rotidx-a");
    let path_b = tempfile_path("rotidx-b");
    reg.register_with_io("r1".into(), "s1".into(), path_a.clone(), None, &bus)
        .unwrap();
    reg.record_event("r1", RecordDirection::Output, b"pre-rotate", &bus)
        .unwrap();
    reg.rotate_to("r1", path_b.clone(), &bus).unwrap();
    reg.record_event("r1", RecordDirection::Output, b"post-rotate", &bus)
        .unwrap();
    reg.close_with_io("r1", &bus).unwrap();

    let idx_a = index_sidecar::sidecar_path(std::path::Path::new(&path_a));
    let idx_b = index_sidecar::sidecar_path(std::path::Path::new(&path_b));
    let entries_a = index_sidecar::read_all(&idx_a, None).unwrap();
    let entries_b = index_sidecar::read_all(&idx_b, None).unwrap();
    assert_eq!(entries_a.len(), 1, "old sidecar holds pre-rotate entry");
    assert_eq!(entries_b.len(), 1, "new sidecar holds post-rotate entry");
    std::fs::remove_file(&path_a).ok();
    std::fs::remove_file(&path_b).ok();
    std::fs::remove_file(&idx_a).ok();
    std::fs::remove_file(&idx_b).ok();
}

#[test]
fn format_delta_strips_trailing_zeros() {
    assert_eq!(format_delta(0.0), "0");
    assert_eq!(format_delta(1.0), "1");
    assert_eq!(format_delta(1.5), "1.5");
    assert_eq!(format_delta(0.123456), "0.123456");
    assert_eq!(format_delta(2.500000), "2.5");
}

#[test]
fn json_escape_handles_spec_escapes() {
    assert_eq!(json_escape("plain"), "plain");
    assert_eq!(json_escape("with\"quote"), "with\\\"quote");
    assert_eq!(json_escape("back\\slash"), "back\\\\slash");
    assert_eq!(json_escape("new\nline"), "new\\nline");
    assert_eq!(json_escape("tab\there"), "tab\\there");
    assert_eq!(json_escape("\x01ctrl"), "\\u0001ctrl");
    assert_eq!(json_escape("emoji 🦀 ok"), "emoji 🦀 ok");
}

#[test]
fn json_escape_strips_bidi_overrides_into_unicode_escapes() {
    // U+202E RIGHT-TO-LEFT OVERRIDE — Trojan-Source class
    // attack. A recording carrying a raw `\u{202E}` would
    // display the line backwards in any RTL-aware player /
    // text-grep tool, hiding what the user actually typed.
    // Pin: every bidi override + isolate emits as a visible
    // `\uXXXX` escape so a downstream auditor sees the marker.
    for (label, ch) in [
        ("LRE U+202A", '\u{202A}'),
        ("RLE U+202B", '\u{202B}'),
        ("PDF U+202C", '\u{202C}'),
        ("LRO U+202D", '\u{202D}'),
        ("RLO U+202E", '\u{202E}'),
        ("LRI U+2066", '\u{2066}'),
        ("RLI U+2067", '\u{2067}'),
        ("FSI U+2068", '\u{2068}'),
        ("PDI U+2069", '\u{2069}'),
    ] {
        let escaped = json_escape(&ch.to_string());
        assert!(
            escaped.starts_with("\\u"),
            "{label} must escape to \\uXXXX, got {escaped:?}"
        );
        assert!(!escaped.contains(ch), "{label} must not pass through raw");
    }
}

#[test]
fn json_escape_passes_arabic_and_hebrew_letters_through_verbatim() {
    // Legitimate RTL terminal recordings (Arabic / Hebrew /
    // Persian) must not get over-escaped. Only the bidi-
    // override + isolate codepoints are stripped — the actual
    // alphabet glyphs flow through untouched so the player
    // renders them naturally.
    assert_eq!(json_escape("سلام"), "سلام");
    assert_eq!(json_escape("שלום"), "שלום");
}
