/// Unit tests extracted from webdav/parser.rs
/// Declared via `#[path] mod tests;` in the source file.
use super::*;

fn fixture(name: &str) -> Vec<u8> {
    let path = format!(
        "{}/tests/fixtures/webdav/{name}",
        env!("CARGO_MANIFEST_DIR")
    );
    std::fs::read(&path).unwrap_or_else(|e| panic!("missing fixture {path}: {e}"))
}

#[test]
fn nextcloud_depth1_listing_parses_files_and_collections() {
    let entries = parse_propfind(&fixture("nextcloud_depth1.xml")).unwrap();
    // Fixture has the parent collection + two files + one subfolder.
    assert_eq!(entries.len(), 4);
    let parent = &entries[0];
    assert!(parent.is_collection, "first entry should be the collection");
    assert!(parent.href.ends_with('/'));
    let file = entries
        .iter()
        .find(|e| e.href.ends_with("notes.txt"))
        .expect("notes.txt missing");
    assert!(!file.is_collection);
    assert_eq!(file.size_bytes, Some(123));
    assert_eq!(file.etag.as_deref(), Some("abc123"));
    assert!(file.last_modified_unix_ms.is_some());
    let subdir = entries
        .iter()
        .find(|e| e.href.ends_with("subdir/"))
        .expect("subdir missing");
    assert!(subdir.is_collection);
}

#[test]
fn display_name_resolves_xml_entities() {
    // quick-xml reports entity references as a separate event from text,
    // so the parser must reassemble `&amp;` / `&#38;` / `&#x263A;` back
    // into their characters; a display name with `&` must not truncate.
    let body = br#"<?xml version="1.0"?>
<d:multistatus xmlns:d="DAV:">
<d:response>
<d:href>/files/q.txt</d:href>
<d:propstat>
<d:prop>
<d:displayname>Q&amp;A &#38; &#x263A;</d:displayname>
<d:getcontentlength>1</d:getcontentlength>
<d:resourcetype/>
</d:prop>
<d:status>HTTP/1.1 200 OK</d:status>
</d:propstat>
</d:response>
</d:multistatus>"#;
    let entries = parse_propfind(body).unwrap();
    assert_eq!(entries.len(), 1);
    assert_eq!(entries[0].display_name.as_deref(), Some("Q&A & ☺"));
}

#[test]
fn mod_dav_root_listing_parses_with_default_namespace() {
    let entries = parse_propfind(&fixture("mod_dav_root.xml")).unwrap();
    assert_eq!(entries.len(), 2);
    assert!(entries[0].is_collection);
    let file = &entries[1];
    assert_eq!(file.size_bytes, Some(4096));
    assert_eq!(
        file.content_type.as_deref(),
        Some("application/octet-stream")
    );
}

#[test]
fn owncloud_single_file_depth0_returns_one_entry() {
    let entries = parse_propfind(&fixture("owncloud_single_file.xml")).unwrap();
    assert_eq!(entries.len(), 1);
    let e = &entries[0];
    assert!(!e.is_collection);
    assert_eq!(e.size_bytes, Some(42));
    // ownCloud emits weak etag — strip the W/ prefix.
    assert_eq!(e.etag.as_deref(), Some("oc-weak-etag"));
    assert_eq!(e.display_name.as_deref(), Some("file.bin"));
}

#[test]
fn iis_d_prefix_namespace_parses_correctly() {
    let entries = parse_propfind(&fixture("iis_d_prefix.xml")).unwrap();
    assert_eq!(entries.len(), 2);
    // Both entries should resolve despite the D: prefix.
    assert!(entries.iter().any(|e| e.is_collection));
    assert!(entries.iter().any(|e| !e.is_collection));
}

#[test]
fn multistatus_with_per_resource_404_skips_failed_propstat() {
    let entries = parse_propfind(&fixture("partial_404.xml")).unwrap();
    // Fixture has one 200 + one 404 — only the 200 surfaces.
    assert_eq!(entries.len(), 1);
    assert!(entries[0].href.ends_with("readable.txt"));
}

#[test]
fn empty_resourcetype_means_file_not_collection() {
    // Inline XML — `<resourcetype/>` self-closed marks a file.
    let xml = br#"<?xml version="1.0"?>
<multistatus xmlns="DAV:">
<response>
<href>/x.bin</href>
<propstat>
<prop>
<resourcetype/>
<getcontentlength>10</getcontentlength>
</prop>
<status>HTTP/1.1 200 OK</status>
</propstat>
</response>
</multistatus>"#;
    let entries = parse_propfind(xml).unwrap();
    assert_eq!(entries.len(), 1);
    assert!(!entries[0].is_collection);
    assert_eq!(entries[0].size_bytes, Some(10));
}

#[test]
fn missing_root_element_returns_webdav_error() {
    let err = parse_propfind(b"<notxml>oops</notxml>").unwrap_err();
    assert!(err.to_string().contains("multistatus"));
}

#[test]
fn body_over_cap_rejected() {
    let huge = vec![b'x'; MAX_RESPONSE_BYTES + 1];
    let err = parse_propfind(&huge).unwrap_err();
    assert!(err.to_string().contains("too large"));
}

#[test]
fn normalise_etag_strips_weak_prefix_and_quotes() {
    assert_eq!(normalise_etag("\"abc\""), "abc");
    assert_eq!(normalise_etag("W/\"abc\""), "abc");
    assert_eq!(normalise_etag("w/\"abc\""), "abc");
    // Bare token (rare, RFC-allowed) — no quotes to strip.
    assert_eq!(normalise_etag("bare"), "bare");
}

#[test]
fn status_parse_2xx_only() {
    assert!(status_is_2xx("HTTP/1.1 200 OK"));
    assert!(status_is_2xx("HTTP/1.1 207 Multi-Status"));
    assert!(!status_is_2xx("HTTP/1.1 404 Not Found"));
    assert!(!status_is_2xx("garbage"));
}
