//! Small shared helpers over `quick_xml` event parsing.

use quick_xml::events::BytesRef;

/// Resolve a `quick_xml` general / character reference to its text.
///
/// Since quick-xml 0.37 entity references (`&amp;`, `&#xNN;`) are reported as
/// a separate `Event::GeneralRef` rather than inlined into `Event::Text`. Any
/// loop that accumulates element text must resolve each ref and append it, or
/// values containing `&` (WebDAV display names, S3 keys) come back truncated.
///
/// `BytesRef` holds the token between `&` and `;`, so we rebuild `&…;` and run
/// it through `escape::unescape`, which resolves the five predefined entities
/// and numeric character references. Returns the reason on failure so each
/// caller can wrap it in its own error variant.
pub(crate) fn resolve_general_ref(r: &BytesRef) -> Result<String, String> {
    let raw = r.decode().map_err(|e| format!("xml ref decode: {e}"))?;
    quick_xml::escape::unescape(&format!("&{raw};"))
        .map(|resolved| resolved.into_owned())
        .map_err(|e| format!("xml entity &{raw};: {e}"))
}
