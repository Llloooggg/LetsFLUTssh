/// Unit tests extracted from storage/webdav.rs
/// Declared via `#[path] mod tests;` in the source file.
use super::*;

fn pe(href: &str, is_collection: bool, size: Option<u64>, mtime: Option<i64>) -> PropfindEntry {
    PropfindEntry {
        href: href.into(),
        display_name: None,
        size_bytes: size,
        last_modified_unix_ms: mtime,
        etag: None,
        content_type: None,
        is_collection,
    }
}

#[test]
fn entry_from_propfind_maps_file() {
    let e = entry_from_propfind(pe("/dav/file.txt", false, Some(42), Some(1_000)));
    assert_eq!(e.kind, EntryKind::File);
    assert_eq!(e.name, "file.txt");
    assert_eq!(e.path, "/dav/file.txt");
    assert_eq!(e.size_bytes, 42);
    assert_eq!(e.modified_unix_ms, Some(1_000));
}

#[test]
fn entry_from_propfind_maps_collection_and_strips_trailing_slash_in_name() {
    let e = entry_from_propfind(pe("/dav/sub/", true, None, None));
    assert_eq!(e.kind, EntryKind::Dir);
    assert_eq!(e.name, "sub");
    assert_eq!(e.path, "/dav/sub/");
    assert_eq!(e.size_bytes, 0);
    assert!(e.modified_unix_ms.is_none());
}

#[test]
fn entry_from_propfind_falls_back_to_display_name_when_href_basename_empty() {
    let p = PropfindEntry {
        href: "/".into(),
        display_name: Some("root".into()),
        size_bytes: None,
        last_modified_unix_ms: None,
        etag: None,
        content_type: None,
        is_collection: true,
    };
    let e = entry_from_propfind(p);
    assert_eq!(e.name, "root");
}

#[test]
fn metadata_from_propfind_round_trip_file() {
    let p = pe("/x", false, Some(10), Some(123));
    let m = metadata_from_propfind(&p);
    assert_eq!(m.kind, EntryKind::File);
    assert_eq!(m.size_bytes, 10);
    assert_eq!(m.modified_unix_ms, Some(123));
}

#[test]
fn metadata_from_propfind_round_trip_dir() {
    let p = pe("/x/", true, None, None);
    let m = metadata_from_propfind(&p);
    assert_eq!(m.kind, EntryKind::Dir);
    assert_eq!(m.size_bytes, 0);
    assert!(m.modified_unix_ms.is_none());
}

#[test]
fn href_basename_strips_trailing_slash_for_collection() {
    assert_eq!(href_basename("/a/b/", true).as_deref(), Some("b"));
}

#[test]
fn href_basename_returns_last_component_for_file() {
    assert_eq!(href_basename("/a/b/c.txt", false).as_deref(), Some("c.txt"));
}

#[test]
fn href_basename_none_for_root() {
    assert_eq!(href_basename("/", true), None);
}
