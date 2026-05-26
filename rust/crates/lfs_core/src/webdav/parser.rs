//! WebDAV multistatus XML parser.
//!
//! PROPFIND responses arrive as XML with shape:
//!
//! ```xml
//! <multistatus xmlns="DAV:">
//!   <response>
//!     <href>/remote.php/dav/files/alice/notes.txt</href>
//!     <propstat>
//!       <prop>
//!         <getcontentlength>123</getcontentlength>
//!         <getlastmodified>Sun, 06 Nov 1994 08:49:37 GMT</getlastmodified>
//!         <getetag>"abc"</getetag>
//!         <getcontenttype>text/plain</getcontenttype>
//!         <resourcetype/>
//!         <displayname>notes.txt</displayname>
//!       </prop>
//!       <status>HTTP/1.1 200 OK</status>
//!     </propstat>
//!   </response>
//! </multistatus>
//! ```
//!
//! Real-world servers vary on:
//!
//! - **Namespace prefix** — Apache mod_dav binds `DAV:` to the
//!   default namespace (`<multistatus xmlns="DAV:">`), nginx-dav
//!   uses `D:` (`<D:multistatus xmlns:D="DAV:">`), Microsoft IIS
//!   alternates between `D:` and `a:`. The parser strips any
//!   prefix and matches local names case-insensitively.
//! - **Element ordering** — `<status>` may appear before
//!   `<prop>` (mod_dav), after (Nextcloud), or twice (when the
//!   server splits per-property status). The parser collects
//!   props from every `<propstat>` whose `<status>` carries an
//!   `HTTP/1.x 2xx` code and ignores the rest.
//! - **getetag formatting** — `"strong"`, `W/"weak"`, or rarely
//!   the bare token. The parser strips the surrounding quotes
//!   and any `W/` prefix; the bytes between survive verbatim.
//! - **`<resourcetype>`** — `<collection/>` inside marks a
//!   directory; anything else (including `<resourcetype/>` self-
//!   closed empty) is a file.
//!
//! ## Sanity caps
//!
//! 16 MiB max input — anything larger is rejected before the
//! XML reader runs. Mainstream WebDAV directories at depth=1
//! return well under 1 MiB even with thousands of entries; the
//! 16 MiB cap is a malicious-server bomb defence, not a real
//! capacity limit.

use quick_xml::events::Event;
use quick_xml::Reader;

use crate::error::Error;

/// Hard cap on PROPFIND response body size accepted by
/// [`parse_propfind`]. Anything larger is rejected as a
/// suspected server bomb. Mainstream listings at depth=1 sit
/// well under 1 MiB; the value gives headroom without letting
/// a hostile server pin gigabytes of RAM.
pub const MAX_RESPONSE_BYTES: usize = 16 * 1024 * 1024;

/// One entry parsed out of the multistatus response. Field
/// shape mirrors the PROPFIND props we actually consume — the
/// sync orchestrator and file browser both need exactly this
/// set, and pulling extra props would just grow the parser
/// surface.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PropfindEntry {
    /// Raw `<href>` value — percent-encoded path on the server.
    /// Callers that need a Rust path strip the prefix matching
    /// the request URI; the parser does not, because the prefix
    /// depends on the server's base URL configuration.
    pub href: String,
    pub display_name: Option<String>,
    pub size_bytes: Option<u64>,
    /// Unix epoch milliseconds, parsed from RFC 1123. `None`
    /// when the server omitted the field or the date failed to
    /// parse (which we log a warn for but do not fail the
    /// whole listing on — a single broken mtime should not lose
    /// the directory).
    pub last_modified_unix_ms: Option<i64>,
    /// ETag bytes with surrounding quotes and any `W/` weak
    /// prefix stripped. `Some("abc")` for either `"abc"` or
    /// `W/"abc"` on the wire. `None` when the server omitted it.
    pub etag: Option<String>,
    pub content_type: Option<String>,
    /// `true` when `<resourcetype>` contained `<collection/>`.
    /// Servers that omit `<resourcetype>` entirely yield `false`.
    pub is_collection: bool,
}

/// Error shape returned from inside a per-resource `<propstat>`.
/// The outer [`parse_propfind`] returns [`Error::WebDav`] only
/// for transport / well-formedness failures; a 207 multistatus
/// with per-resource 4xx / 5xx statuses is the success path,
/// the caller decides what to do with the partial result.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum MultistatusError {
    /// XML well-formedness or schema mismatch — the body wasn't
    /// a parseable multistatus.
    Xml(String),
    /// One `<propstat>` carried a non-2xx HTTP status.
    Http(u16, String),
}

/// Parse a multistatus XML body into a list of entries.
///
/// Returns [`Error::WebDav`] on:
/// - body larger than [`MAX_RESPONSE_BYTES`],
/// - the XML reader hitting a fatal parse error,
/// - missing `<multistatus>` root.
///
/// Per-resource `<propstat>` blocks with non-2xx status are
/// silently dropped from the result — they're a normal partial
/// failure inside an otherwise valid response, not a transport
/// error. The caller that needs to know about them goes back to
/// the raw HTTP layer.
pub fn parse_propfind(xml_body: &[u8]) -> Result<Vec<PropfindEntry>, Error> {
    if xml_body.len() > MAX_RESPONSE_BYTES {
        return Err(Error::WebDav(format!(
            "propfind body too large: {} bytes (cap {})",
            xml_body.len(),
            MAX_RESPONSE_BYTES
        )));
    }
    let mut reader = Reader::from_reader(xml_body);
    reader.config_mut().trim_text(true);

    let mut entries: Vec<PropfindEntry> = Vec::new();
    let mut saw_root = false;
    let mut buf = Vec::new();

    loop {
        match reader
            .read_event_into(&mut buf)
            .map_err(|e| Error::WebDav(format!("propfind xml: {e}")))?
        {
            Event::Start(e) => {
                let local = local_name_lowercase(e.name().as_ref());
                if local == "multistatus" {
                    saw_root = true;
                } else if local == "response" {
                    if let Some(entry) = parse_response(&mut reader)? {
                        entries.push(entry);
                    }
                }
            }
            Event::Eof => break,
            _ => {}
        }
        buf.clear();
    }
    if !saw_root {
        return Err(Error::WebDav("propfind: missing <multistatus> root".into()));
    }
    Ok(entries)
}

/// Read a single `<response>` element and produce a
/// [`PropfindEntry`]. Returns `Ok(None)` when none of the
/// nested `<propstat>` blocks carried a 2xx status — those
/// responses (e.g. PROPFIND on a path the user has read but
/// not stat permission for) drop out of the listing.
fn parse_response<R: std::io::BufRead>(
    reader: &mut Reader<R>,
) -> Result<Option<PropfindEntry>, Error> {
    let mut href = String::new();
    let mut display_name = None;
    let mut size_bytes = None;
    let mut last_modified_unix_ms = None;
    let mut etag = None;
    let mut content_type = None;
    let mut is_collection = false;
    let mut any_2xx_propstat = false;

    let mut buf = Vec::new();
    loop {
        match reader
            .read_event_into(&mut buf)
            .map_err(|e| Error::WebDav(format!("propfind xml: {e}")))?
        {
            Event::Start(e) => {
                let local = local_name_lowercase(e.name().as_ref());
                match local.as_str() {
                    "href" => {
                        href = read_text(reader)?;
                    }
                    "propstat" => {
                        let parsed = parse_propstat(reader)?;
                        if parsed.status_2xx {
                            any_2xx_propstat = true;
                            if let Some(v) = parsed.display_name {
                                display_name.get_or_insert(v);
                            }
                            if let Some(v) = parsed.size_bytes {
                                size_bytes.get_or_insert(v);
                            }
                            if let Some(v) = parsed.last_modified_unix_ms {
                                last_modified_unix_ms.get_or_insert(v);
                            }
                            if let Some(v) = parsed.etag {
                                etag.get_or_insert(v);
                            }
                            if let Some(v) = parsed.content_type {
                                content_type.get_or_insert(v);
                            }
                            if parsed.is_collection {
                                is_collection = true;
                            }
                        }
                    }
                    _ => {}
                }
            }
            Event::End(e) if local_name_lowercase(e.name().as_ref()) == "response" => {
                break;
            }
            Event::Eof => break,
            _ => {}
        }
        buf.clear();
    }
    if href.is_empty() || !any_2xx_propstat {
        return Ok(None);
    }
    Ok(Some(PropfindEntry {
        href,
        display_name,
        size_bytes,
        last_modified_unix_ms,
        etag,
        content_type,
        is_collection,
    }))
}

#[derive(Default)]
struct PropstatParsed {
    status_2xx: bool,
    display_name: Option<String>,
    size_bytes: Option<u64>,
    last_modified_unix_ms: Option<i64>,
    etag: Option<String>,
    content_type: Option<String>,
    is_collection: bool,
}

fn parse_propstat<R: std::io::BufRead>(reader: &mut Reader<R>) -> Result<PropstatParsed, Error> {
    let mut out = PropstatParsed::default();
    let mut buf = Vec::new();
    loop {
        match reader
            .read_event_into(&mut buf)
            .map_err(|e| Error::WebDav(format!("propfind xml: {e}")))?
        {
            Event::Start(e) => {
                let local = local_name_lowercase(e.name().as_ref());
                match local.as_str() {
                    "status" => {
                        let text = read_text(reader)?;
                        out.status_2xx = status_is_2xx(&text);
                    }
                    "prop" => {
                        parse_prop(reader, &mut out)?;
                    }
                    _ => {}
                }
            }
            Event::End(e) if local_name_lowercase(e.name().as_ref()) == "propstat" => {
                break;
            }
            Event::Eof => break,
            _ => {}
        }
        buf.clear();
    }
    Ok(out)
}

fn parse_prop<R: std::io::BufRead>(
    reader: &mut Reader<R>,
    out: &mut PropstatParsed,
) -> Result<(), Error> {
    let mut buf = Vec::new();
    loop {
        match reader
            .read_event_into(&mut buf)
            .map_err(|e| Error::WebDav(format!("propfind xml: {e}")))?
        {
            Event::Start(e) => {
                let local = local_name_lowercase(e.name().as_ref());
                match local.as_str() {
                    "displayname" => {
                        let v = read_text(reader)?;
                        if !v.is_empty() {
                            out.display_name = Some(v);
                        }
                    }
                    "getcontentlength" => {
                        let v = read_text(reader)?;
                        if let Ok(n) = v.trim().parse::<u64>() {
                            out.size_bytes = Some(n);
                        }
                    }
                    "getlastmodified" => {
                        let v = read_text(reader)?;
                        out.last_modified_unix_ms = parse_http_date_ms(&v);
                    }
                    "getetag" => {
                        let v = read_text(reader)?;
                        out.etag = Some(normalise_etag(&v));
                    }
                    "getcontenttype" => {
                        let v = read_text(reader)?;
                        if !v.is_empty() {
                            out.content_type = Some(v);
                        }
                    }
                    "resourcetype" => {
                        out.is_collection = resourcetype_has_collection(reader)?;
                    }
                    _ => {
                        // Unknown prop — skip its body so the
                        // reader cursor doesn't leak into a
                        // following sibling.
                        skip_to_end(reader, e.name().as_ref())?;
                    }
                }
            }
            Event::Empty(e) => {
                // Self-closed elements like `<resourcetype/>` or
                // empty `<getetag/>` — counts as "absent" except
                // for `resourcetype` where the empty form means
                // "not a collection" (already the default).
                let _ = local_name_lowercase(e.name().as_ref());
            }
            Event::End(e) if local_name_lowercase(e.name().as_ref()) == "prop" => {
                break;
            }
            Event::Eof => break,
            _ => {}
        }
        buf.clear();
    }
    Ok(())
}

fn resourcetype_has_collection<R: std::io::BufRead>(reader: &mut Reader<R>) -> Result<bool, Error> {
    let mut found = false;
    let mut buf = Vec::new();
    loop {
        match reader
            .read_event_into(&mut buf)
            .map_err(|e| Error::WebDav(format!("propfind xml: {e}")))?
        {
            Event::Start(e) | Event::Empty(e)
                if local_name_lowercase(e.name().as_ref()) == "collection" =>
            {
                found = true;
            }
            Event::End(e) if local_name_lowercase(e.name().as_ref()) == "resourcetype" => {
                break;
            }
            Event::Eof => break,
            _ => {}
        }
        buf.clear();
    }
    Ok(found)
}

fn skip_to_end<R: std::io::BufRead>(reader: &mut Reader<R>, name: &[u8]) -> Result<(), Error> {
    let target = local_name_lowercase(name);
    let mut depth = 1;
    let mut buf = Vec::new();
    while depth > 0 {
        match reader
            .read_event_into(&mut buf)
            .map_err(|e| Error::WebDav(format!("propfind xml: {e}")))?
        {
            Event::Start(e) if local_name_lowercase(e.name().as_ref()) == target => {
                depth += 1;
            }
            Event::End(e) if local_name_lowercase(e.name().as_ref()) == target => {
                depth -= 1;
            }
            Event::Eof => break,
            _ => {}
        }
        buf.clear();
    }
    Ok(())
}

/// Read a `Text` / `CData` run until the next end tag at the
/// current depth. Concatenates split text events the XML reader
/// surfaces around entity references.
fn read_text<R: std::io::BufRead>(reader: &mut Reader<R>) -> Result<String, Error> {
    let mut out = String::new();
    let mut buf = Vec::new();
    loop {
        match reader
            .read_event_into(&mut buf)
            .map_err(|e| Error::WebDav(format!("propfind xml: {e}")))?
        {
            Event::Text(t) => {
                let s = t
                    .unescape()
                    .map_err(|e| Error::WebDav(format!("propfind xml entity: {e}")))?;
                out.push_str(&s);
            }
            Event::CData(c) => {
                let s = std::str::from_utf8(c.as_ref())
                    .map_err(|e| Error::WebDav(format!("propfind cdata utf8: {e}")))?;
                out.push_str(s);
            }
            Event::End(_) | Event::Eof => break,
            _ => {}
        }
        buf.clear();
    }
    Ok(out)
}

/// Strip the namespace prefix (`D:`, `d:`, `a:`, …) and lower-case
/// the local name. PROPFIND elements are case-insensitive on the
/// wire in practice; matching lower-case keeps the parser
/// tolerant.
fn local_name_lowercase(name: &[u8]) -> String {
    let s = std::str::from_utf8(name).unwrap_or("");
    let local = match s.rfind(':') {
        Some(idx) => &s[idx + 1..],
        None => s,
    };
    local.to_ascii_lowercase()
}

/// Parse "HTTP/1.1 200 OK" → 200, then check the 2xx range.
/// Unrecognised shapes fail closed (treated as non-2xx).
fn status_is_2xx(status_line: &str) -> bool {
    let mut parts = status_line.split_whitespace();
    let _http = parts.next();
    let code = parts.next().and_then(|s| s.parse::<u16>().ok());
    matches!(code, Some(c) if (200..300).contains(&c))
}

/// `"abc"` → `abc`; `W/"abc"` → `abc`. Bytes between the quotes
/// pass through unchanged.
fn normalise_etag(raw: &str) -> String {
    let trimmed = raw.trim();
    let stripped = trimmed
        .strip_prefix("W/")
        .or_else(|| trimmed.strip_prefix("w/"))
        .unwrap_or(trimmed);
    stripped
        .strip_prefix('"')
        .and_then(|s| s.strip_suffix('"'))
        .unwrap_or(stripped)
        .to_string()
}

/// RFC 1123 → Unix epoch milliseconds. Returns `None` on parse
/// failure; the entry survives without an mtime rather than
/// failing the whole listing.
fn parse_http_date_ms(raw: &str) -> Option<i64> {
    let trimmed = raw.trim();
    if trimmed.is_empty() {
        return None;
    }
    let when = httpdate::parse_http_date(trimmed).ok()?;
    let dur = when.duration_since(std::time::UNIX_EPOCH).ok()?;
    let ms = dur.as_millis();
    i64::try_from(ms).ok()
}

#[cfg(test)]
mod tests {
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
}
