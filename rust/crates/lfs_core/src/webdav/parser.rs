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
    // No per-event trim: quick-xml reports entity references (`&amp;`,
    // `&#38;`) as their own events, so trimming each text fragment would
    // drop the whitespace around an entity inside a value (a display name
    // like "My Files & Docs"). `read_text` trims the assembled value once
    // instead. Structural loops ignore stray whitespace text events.

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
    let mut acc = ResponseAccum::default();

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
                        acc.merge_propstat(parse_propstat(reader)?);
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
    if href.is_empty() || !acc.any_2xx_propstat {
        return Ok(None);
    }
    Ok(Some(PropfindEntry {
        href,
        display_name: acc.display_name,
        size_bytes: acc.size_bytes,
        last_modified_unix_ms: acc.last_modified_unix_ms,
        etag: acc.etag,
        content_type: acc.content_type,
        is_collection: acc.is_collection,
    }))
}

/// Accumulates the first 2xx value seen for each property across a
/// response's `<propstat>` blocks. A WebDAV server may split props
/// across multiple propstat groups (e.g. one 200 block, one 404
/// block); only 2xx values are kept, first-writer-wins per field.
#[derive(Default)]
struct ResponseAccum {
    display_name: Option<String>,
    size_bytes: Option<u64>,
    last_modified_unix_ms: Option<i64>,
    etag: Option<String>,
    content_type: Option<String>,
    is_collection: bool,
    any_2xx_propstat: bool,
}

impl ResponseAccum {
    fn merge_propstat(&mut self, parsed: PropstatParsed) {
        if !parsed.status_2xx {
            return;
        }
        self.any_2xx_propstat = true;
        if let Some(v) = parsed.display_name {
            self.display_name.get_or_insert(v);
        }
        if let Some(v) = parsed.size_bytes {
            self.size_bytes.get_or_insert(v);
        }
        if let Some(v) = parsed.last_modified_unix_ms {
            self.last_modified_unix_ms.get_or_insert(v);
        }
        if let Some(v) = parsed.etag {
            self.etag.get_or_insert(v);
        }
        if let Some(v) = parsed.content_type {
            self.content_type.get_or_insert(v);
        }
        if parsed.is_collection {
            self.is_collection = true;
        }
    }
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
                handle_prop_element(&local, e.name().as_ref(), reader, out)?;
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

/// Dispatch a single `<prop>` child element into `out`. `name` is the
/// raw element name, used to skip the body of an unrecognised prop so
/// the reader cursor doesn't leak into a following sibling.
fn handle_prop_element<R: std::io::BufRead>(
    local: &str,
    name: &[u8],
    reader: &mut Reader<R>,
    out: &mut PropstatParsed,
) -> Result<(), Error> {
    match local {
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
            skip_to_end(reader, name)?;
        }
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
                    .decode()
                    .map_err(|e| Error::WebDav(format!("propfind xml decode: {e}")))?;
                out.push_str(&s);
            }
            Event::GeneralRef(r) => {
                let s = crate::xml::resolve_general_ref(&r)
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
    // Trim once over the assembled value (replacing the reader's former
    // per-event trim), so surrounding whitespace is stripped but spaces
    // around an inner entity are kept.
    Ok(out.trim().to_string())
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
#[path = "../../tests/unit/webdav_parser.rs"]
mod tests;
