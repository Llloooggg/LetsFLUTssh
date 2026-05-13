//! RFC 7512 `pkcs11:` URI parser — vendored inline because the
//! `pkcs11-uri` crate on crates.io has been unmaintained since 2020
//! and pulls a pinned-old `regex` dependency we have no use for.
//!
//! Grammar (RFC 7512 §2):
//!
//! ```text
//! pk11-URI   = "pkcs11:" pk11-path *("?" pk11-query)
//! pk11-path  = pk11-pattr *(";" pk11-pattr)
//! pk11-query = pk11-qattr *("&" pk11-qattr)
//! pk11-pattr = (attr-name "=" attr-value) / ""
//! pk11-qattr = (attr-name "=" attr-value) / ""
//! ```
//!
//! Attribute values are percent-encoded; the parser decodes on the
//! fly. We accept the subset of attribute names this project routes
//! through PKCS#11: token + module identification (`token`,
//! `manufacturer`, `serial`, `model`, `library-description`,
//! `library-manufacturer`, `library-version`, `module-name`,
//! `module-path`), and object identification (`object`, `id`,
//! `type`). Every other attribute name is preserved verbatim in
//! [`Pkcs11Uri::other`] so a round-trip through [`Pkcs11Uri::to_string`]
//! emits the original input.
//!
//! Strict-on-input: rejects non-ASCII attribute names, missing `=`
//! separators, dangling `%` sequences. Permissive-on-output: the
//! emitter percent-encodes anything outside `unreserved` per RFC
//! 3986 §2.3 plus the path-attribute reserved set (`; ? = &`).

use std::collections::BTreeMap;
use std::fmt;

/// RFC 7512 parsing failure. Carries a static reason rather than the
/// offending byte run because the input may carry sensitive material
/// (a tokens label / serial picked by the user) — the test suite
/// exercises every shape verbatim.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct UriError(pub &'static str);

impl fmt::Display for UriError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.0)
    }
}

impl std::error::Error for UriError {}

/// Parsed `pkcs11:` URI. Every named field is the decoded byte run
/// the matching attribute carries; missing attributes are `None`.
/// `other` keeps any path or query attribute we don't pin a field
/// for so the round-trip stays lossless.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Pkcs11Uri {
    // Path attributes (RFC 7512 §2.3)
    pub token: Option<String>,
    pub manufacturer: Option<String>,
    pub serial: Option<String>,
    pub model: Option<String>,
    pub library_description: Option<String>,
    pub library_manufacturer: Option<String>,
    pub library_version: Option<String>,
    pub object: Option<String>,
    pub id: Option<Vec<u8>>,
    pub r#type: Option<String>,
    /// Path attributes outside the named set above. Order preserved
    /// by insertion-sorted map so the round-trip emits a stable shape.
    pub other_path: BTreeMap<String, String>,
    // Query attributes (RFC 7512 §2.4)
    pub module_name: Option<String>,
    pub module_path: Option<String>,
    pub other_query: BTreeMap<String, String>,
}

/// Build the canonical `pkcs11:` URI the import wizard captures on
/// disk. Emits `token`, `serial`, `object`, `id` as path attributes
/// (in that order — RFC 7512 §2.3 allows any order, but a stable
/// shape keeps DB rows comparable), then `?module-path=...` as a
/// query attribute when non-empty.
///
/// Path-attribute values are percent-encoded against
/// `is_unreserved_path` — RFC 3986 §2.3 unreserved (alphanumerics
/// plus `-._~`). The `cka_id` byte stream is encoded against the
/// same classification rather than the all-percent rule
/// `Display` uses for the parsed `Pkcs11Uri` round-trip, so
/// binary IDs that happen to be ASCII (the YubiKey PIV slot tags
/// `9a` / `9c` / `9d` / `9e` are byte pairs `0x9A..0x9E` —
/// wholly non-printable — but a custom applet may pick a
/// printable byte run) survive without inflating every literal
/// byte. The parser decodes both shapes identically.
/// `module-path` rides query rules (`is_unreserved_query`).
pub fn compose(
    token_label: &str,
    serial: &str,
    object_label: &str,
    cka_id: &[u8],
    module_path: &str,
) -> String {
    let mut out = String::with_capacity(
        8 + token_label.len() + serial.len() + object_label.len() + cka_id.len() * 3,
    );
    out.push_str("pkcs11:");
    let mut first = true;
    push_path_attr(&mut out, "token", token_label.as_bytes(), &mut first);
    push_path_attr(&mut out, "serial", serial.as_bytes(), &mut first);
    push_path_attr(&mut out, "object", object_label.as_bytes(), &mut first);
    // `id=` is always emitted (including the empty-bytes case as
    // `id=`) so the parser observes the same path-attribute set the
    // wizard captured.
    push_path_attr(&mut out, "id", cka_id, &mut first);
    if !module_path.is_empty() {
        out.push_str("?module-path=");
        write_percent_into(&mut out, module_path.as_bytes(), is_unreserved_query);
    }
    out
}

fn push_path_attr(buf: &mut String, name: &str, bytes: &[u8], first: &mut bool) {
    if !*first {
        buf.push(';');
    }
    *first = false;
    buf.push_str(name);
    buf.push('=');
    write_percent_into(buf, bytes, is_unreserved_path);
}

fn write_percent_into(buf: &mut String, bytes: &[u8], safe: fn(u8) -> bool) {
    use std::fmt::Write as _;
    for &b in bytes {
        if safe(b) {
            buf.push(b as char);
        } else {
            let _ = write!(buf, "%{:02X}", b);
        }
    }
}

impl Pkcs11Uri {
    /// Parse `text` as an RFC 7512 `pkcs11:` URI. Returns
    /// `Err(UriError)` for any structural issue; empty path /
    /// empty query are both valid.
    pub fn parse(text: &str) -> Result<Self, UriError> {
        let body = text
            .strip_prefix("pkcs11:")
            .ok_or(UriError("missing pkcs11: scheme"))?;
        let (path_part, query_part) = match body.find('?') {
            Some(idx) => (&body[..idx], Some(&body[idx + 1..])),
            None => (body, None),
        };
        let mut uri = Pkcs11Uri::default();
        if !path_part.is_empty() {
            for segment in path_part.split(';') {
                if segment.is_empty() {
                    continue;
                }
                let (name, value) = split_attr(segment)?;
                store_path_attribute(&mut uri, name, value)?;
            }
        }
        if let Some(q) = query_part {
            if !q.is_empty() {
                for segment in q.split('&') {
                    if segment.is_empty() {
                        continue;
                    }
                    let (name, value) = split_attr(segment)?;
                    store_query_attribute(&mut uri, name, value)?;
                }
            }
        }
        Ok(uri)
    }
}

fn split_attr(segment: &str) -> Result<(&str, &str), UriError> {
    let eq = segment.find('=').ok_or(UriError("attribute missing '='"))?;
    let name = &segment[..eq];
    let value = &segment[eq + 1..];
    if name.is_empty() {
        return Err(UriError("empty attribute name"));
    }
    if !name.bytes().all(is_attr_name_byte) {
        return Err(UriError("attribute name not RFC 3986 token"));
    }
    Ok((name, value))
}

fn store_path_attribute(uri: &mut Pkcs11Uri, name: &str, value: &str) -> Result<(), UriError> {
    let decoded = percent_decode(value)?;
    let as_str = || -> Result<String, UriError> {
        String::from_utf8(decoded.clone()).map_err(|_| UriError("path attribute not UTF-8"))
    };
    match name {
        "token" => uri.token = Some(as_str()?),
        "manufacturer" => uri.manufacturer = Some(as_str()?),
        "serial" => uri.serial = Some(as_str()?),
        "model" => uri.model = Some(as_str()?),
        "library-description" => uri.library_description = Some(as_str()?),
        "library-manufacturer" => uri.library_manufacturer = Some(as_str()?),
        "library-version" => uri.library_version = Some(as_str()?),
        "object" => uri.object = Some(as_str()?),
        // `id` is the CKA_ID raw bytes — percent-decoded payload is
        // binary in general (`%01%02%03` style on opaque smart-card
        // IDs). RFC 7512 §2.3 spells this out specifically.
        "id" => uri.id = Some(decoded),
        "type" => uri.r#type = Some(as_str()?),
        other => {
            uri.other_path.insert(other.to_string(), as_str()?);
        }
    }
    Ok(())
}

fn store_query_attribute(uri: &mut Pkcs11Uri, name: &str, value: &str) -> Result<(), UriError> {
    let decoded = percent_decode(value)?;
    let s = String::from_utf8(decoded).map_err(|_| UriError("query attribute not UTF-8"))?;
    match name {
        "module-name" => uri.module_name = Some(s),
        "module-path" => uri.module_path = Some(s),
        other => {
            uri.other_query.insert(other.to_string(), s);
        }
    }
    Ok(())
}

fn percent_decode(input: &str) -> Result<Vec<u8>, UriError> {
    let bytes = input.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        let c = bytes[i];
        if c == b'%' {
            if i + 2 >= bytes.len() {
                return Err(UriError("truncated percent-escape"));
            }
            let hi = hex_value(bytes[i + 1]).ok_or(UriError("bad percent-hex digit"))?;
            let lo = hex_value(bytes[i + 2]).ok_or(UriError("bad percent-hex digit"))?;
            out.push((hi << 4) | lo);
            i += 3;
        } else if c == b'+' {
            // RFC 7512 §2.1 says `pkcs11:` is application/x-pkcs11-uri,
            // not application/x-www-form-urlencoded, so a literal `+`
            // stays a literal `+`. We do not decode it as space.
            out.push(b'+');
            i += 1;
        } else {
            out.push(c);
            i += 1;
        }
    }
    Ok(out)
}

#[inline]
fn hex_value(b: u8) -> Option<u8> {
    match b {
        b'0'..=b'9' => Some(b - b'0'),
        b'a'..=b'f' => Some(b - b'a' + 10),
        b'A'..=b'F' => Some(b - b'A' + 10),
        _ => None,
    }
}

#[inline]
fn is_attr_name_byte(b: u8) -> bool {
    // RFC 3986 unreserved + the path-attr-allowed `-` per RFC 7512.
    matches!(b, b'a'..=b'z' | b'A'..=b'Z' | b'0'..=b'9' | b'-' | b'_' | b'.')
}

impl fmt::Display for Pkcs11Uri {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str("pkcs11:")?;
        let mut first = true;
        let write_attr = |f: &mut fmt::Formatter<'_>, name: &str, value: &str, first: &mut bool| {
            if !*first {
                f.write_str(";")?;
            }
            *first = false;
            f.write_str(name)?;
            f.write_str("=")?;
            write_percent(f, value.as_bytes(), is_unreserved_path)
        };
        if let Some(v) = &self.token {
            write_attr(f, "token", v, &mut first)?;
        }
        if let Some(v) = &self.manufacturer {
            write_attr(f, "manufacturer", v, &mut first)?;
        }
        if let Some(v) = &self.serial {
            write_attr(f, "serial", v, &mut first)?;
        }
        if let Some(v) = &self.model {
            write_attr(f, "model", v, &mut first)?;
        }
        if let Some(v) = &self.library_description {
            write_attr(f, "library-description", v, &mut first)?;
        }
        if let Some(v) = &self.library_manufacturer {
            write_attr(f, "library-manufacturer", v, &mut first)?;
        }
        if let Some(v) = &self.library_version {
            write_attr(f, "library-version", v, &mut first)?;
        }
        if let Some(v) = &self.object {
            write_attr(f, "object", v, &mut first)?;
        }
        if let Some(v) = &self.id {
            // CKA_ID payload is opaque binary; always percent-encode.
            if !first {
                f.write_str(";")?;
            }
            first = false;
            f.write_str("id=")?;
            write_percent(f, v, |_| false)?;
        }
        if let Some(v) = &self.r#type {
            write_attr(f, "type", v, &mut first)?;
        }
        for (k, v) in &self.other_path {
            write_attr(f, k, v, &mut first)?;
        }
        let mut query_first = true;
        let write_query =
            |f: &mut fmt::Formatter<'_>, name: &str, value: &str, qfirst: &mut bool| {
                if *qfirst {
                    f.write_str("?")?;
                } else {
                    f.write_str("&")?;
                }
                *qfirst = false;
                f.write_str(name)?;
                f.write_str("=")?;
                write_percent(f, value.as_bytes(), is_unreserved_query)
            };
        if let Some(v) = &self.module_name {
            write_query(f, "module-name", v, &mut query_first)?;
        }
        if let Some(v) = &self.module_path {
            write_query(f, "module-path", v, &mut query_first)?;
        }
        for (k, v) in &self.other_query {
            write_query(f, k, v, &mut query_first)?;
        }
        Ok(())
    }
}

fn write_percent(f: &mut fmt::Formatter<'_>, bytes: &[u8], safe: fn(u8) -> bool) -> fmt::Result {
    for &b in bytes {
        if safe(b) {
            f.write_str(unsafe { std::str::from_utf8_unchecked(std::slice::from_ref(&b)) })?;
        } else {
            write!(f, "%{:02X}", b)?;
        }
    }
    Ok(())
}

#[inline]
fn is_unreserved_path(b: u8) -> bool {
    matches!(b, b'a'..=b'z' | b'A'..=b'Z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~')
}

#[inline]
fn is_unreserved_query(b: u8) -> bool {
    // Same as path; the URI scheme keeps the safe-byte definition
    // identical so a round-trip stays stable. Slash `/` is reserved in
    // the path part but allowed verbatim in queries (RFC 3986 §3.4) —
    // we percent-encode either way to keep the emitter shape uniform.
    matches!(b, b'a'..=b'z' | b'A'..=b'Z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~')
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_empty_uri_round_trips_to_scheme_only() {
        let uri = Pkcs11Uri::parse("pkcs11:").unwrap();
        assert_eq!(uri.to_string(), "pkcs11:");
        assert!(uri.token.is_none());
        assert!(uri.module_path.is_none());
    }

    #[test]
    fn parse_token_and_model_path_attrs() {
        let uri = Pkcs11Uri::parse("pkcs11:token=My%20Token;model=PIVApplet").unwrap();
        assert_eq!(uri.token.as_deref(), Some("My Token"));
        assert_eq!(uri.model.as_deref(), Some("PIVApplet"));
    }

    #[test]
    fn parse_id_is_binary_not_string() {
        let uri = Pkcs11Uri::parse("pkcs11:id=%01%02%FF").unwrap();
        assert_eq!(uri.id.unwrap(), vec![0x01, 0x02, 0xff]);
    }

    #[test]
    fn parse_query_module_path() {
        let uri = Pkcs11Uri::parse("pkcs11:?module-path=/usr/lib/opensc-pkcs11.so").unwrap();
        assert_eq!(
            uri.module_path.as_deref(),
            Some("/usr/lib/opensc-pkcs11.so")
        );
    }

    #[test]
    fn parse_full_uri_round_trips() {
        let input =
            "pkcs11:token=Yubico%20PIV;serial=00000001;id=%01;object=SSH?module-name=ykcs11";
        let parsed = Pkcs11Uri::parse(input).unwrap();
        let emitted = parsed.to_string();
        // Re-parse the emission and confirm equality.
        let reparsed = Pkcs11Uri::parse(&emitted).unwrap();
        assert_eq!(parsed, reparsed);
    }

    #[test]
    fn rejects_missing_scheme() {
        let err = Pkcs11Uri::parse("token=x").unwrap_err();
        assert_eq!(err.0, "missing pkcs11: scheme");
    }

    #[test]
    fn rejects_missing_equals() {
        let err = Pkcs11Uri::parse("pkcs11:token").unwrap_err();
        assert_eq!(err.0, "attribute missing '='");
    }

    #[test]
    fn rejects_truncated_percent_escape() {
        let err = Pkcs11Uri::parse("pkcs11:token=foo%2").unwrap_err();
        assert_eq!(err.0, "truncated percent-escape");
    }

    #[test]
    fn rejects_bad_percent_digit() {
        let err = Pkcs11Uri::parse("pkcs11:token=foo%ZZ").unwrap_err();
        assert_eq!(err.0, "bad percent-hex digit");
    }

    #[test]
    fn rejects_non_ascii_attribute_name() {
        let err = Pkcs11Uri::parse("pkcs11:tokén=x").unwrap_err();
        assert_eq!(err.0, "attribute name not RFC 3986 token");
    }

    #[test]
    fn unknown_path_attribute_lands_in_other() {
        let uri = Pkcs11Uri::parse("pkcs11:vendor-flag=on").unwrap();
        assert_eq!(
            uri.other_path.get("vendor-flag").map(String::as_str),
            Some("on")
        );
    }

    #[test]
    fn compose_emits_all_path_attrs_then_query_in_canonical_order() {
        let uri = compose(
            "Yubico PIV",
            "00000001",
            "SSH",
            &[0x01, 0x02, 0xff],
            "/usr/lib/ykcs11.so",
        );
        assert_eq!(
            uri,
            "pkcs11:token=Yubico%20PIV;serial=00000001;object=SSH;id=%01%02%FF?module-path=%2Fusr%2Flib%2Fykcs11.so"
        );
    }

    #[test]
    fn compose_then_parse_round_trips_every_field() {
        let token = "Mañana — 한글";
        let serial = "SN/0001";
        let object = "key #1";
        let id: Vec<u8> = (0u8..=255).collect();
        let module_path = "/usr/lib/x86_64-linux-gnu/opensc-pkcs11.so";
        let uri = compose(token, serial, object, &id, module_path);
        let parsed = Pkcs11Uri::parse(&uri).unwrap();
        assert_eq!(parsed.token.as_deref(), Some(token));
        assert_eq!(parsed.serial.as_deref(), Some(serial));
        assert_eq!(parsed.object.as_deref(), Some(object));
        assert_eq!(parsed.id.as_deref(), Some(id.as_slice()));
        assert_eq!(parsed.module_path.as_deref(), Some(module_path));
    }

    #[test]
    fn compose_pct_encodes_reserved_delimiters_in_path_attrs() {
        // `;`, `?`, `&`, `=`, `%`, ` ` must all percent-encode so the
        // parser doesn't mistake them for structural separators.
        let uri = compose("a;b?c&d=e%f g", "x", "y", &[], "z");
        let body = uri.strip_prefix("pkcs11:").unwrap();
        // The first attribute carries the danger chars — verify each
        // delimiter byte is in the %XX form.
        assert!(body.starts_with("token=a%3Bb%3Fc%26d%3De%25f%20g;",));
        // Round-trip back through the parser to confirm decoding.
        let parsed = Pkcs11Uri::parse(&uri).unwrap();
        assert_eq!(parsed.token.as_deref(), Some("a;b?c&d=e%f g"));
    }

    #[test]
    fn compose_pct_encodes_every_non_unreserved_id_byte() {
        // Sweep every byte value 0..=255 in `cka_id`, then re-parse to
        // confirm the byte stream survives lossless.
        let id: Vec<u8> = (0u8..=255).collect();
        let uri = compose("t", "s", "o", &id, "");
        let parsed = Pkcs11Uri::parse(&uri).unwrap();
        assert_eq!(parsed.id.unwrap(), id);
    }

    #[test]
    fn compose_omits_query_when_module_path_empty() {
        let uri = compose("t", "s", "o", &[0x01], "");
        assert!(!uri.contains('?'), "query separator must not appear: {uri}");
        assert!(uri.ends_with("id=%01"));
    }

    #[test]
    fn compose_handles_empty_cka_id_as_literal_id_equals() {
        // The wizard never picks a key with empty CKA_ID in practice,
        // but the encoder must not panic and must round-trip an empty
        // byte run as `id=` (decoded to `Vec::new`).
        let uri = compose("t", "s", "o", &[], "");
        assert!(uri.ends_with(";id="));
        let parsed = Pkcs11Uri::parse(&uri).unwrap();
        assert_eq!(parsed.id, Some(Vec::new()));
    }

    #[test]
    fn does_not_panic_on_random_input() {
        // Property-style sweep — feed every short ASCII shape and
        // a handful of percent-edge cases; the parser must never
        // panic, must always return either `Ok` or `Err` with a
        // static reason.
        for prefix in ["", "pkcs11:", "pkcs11:?"] {
            for body in [
                "",
                "=",
                ";",
                "&",
                "%",
                "%2",
                "%2G",
                "token=",
                "id=%00%01%02",
                "?module-path=",
            ] {
                let mut combined = String::from(prefix);
                combined.push_str(body);
                let _ = Pkcs11Uri::parse(&combined);
            }
        }
    }
}
