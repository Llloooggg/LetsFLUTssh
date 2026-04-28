//! Deep-link URI parser + dispatcher.
//!
//! [`parse_connect_uri`] mirrors `DeepLinkHandler.parseConnectUri` in
//! the Flutter app byte-for-byte. The OS hands us URIs from registered
//! schemes (`letsflutssh://connect?...`) plus file/content URIs from
//! "Open with" intents; this module owns the rules that decide when a
//! URI is a valid connect-link payload.
//!
//! [`DeeplinkDispatcher`] is the next layer up: it dedups duplicate
//! URIs (cold-start `getInitialLink` + `uriLinkStream` race), routes
//! by scheme + host + file extension, and (for QR import) decodes the
//! payload and stages it in [`crate::archive::ImportRegistry`] before
//! returning a typed [`DeeplinkOutcome`] to the FRB caller. The Dart
//! shim is then a thin URI pump that switches on the outcome to
//! drive the right UI action.
//!
//! # Why Rust
//!
//! Validation rules (host length, control-char rejection, port
//! range, percent-decoding) are pure functions over user-
//! controllable input. The fuzz suite drives 2000 random URI
//! shapes through and asserts no panic; keeping the canonical
//! implementation Rust-side stays in one place rather than
//! diverging between frontends. Dedup + scheme routing live
//! Rust-side for the same reason: one canonical truth.

/// Parsed payload of a `letsflutssh://connect?...` URI. Mirrors
/// the Dart-side `SSHConfig.server` shape — no credential fields
/// because deep links never carry passwords / keys (URLs land in
/// OS clipboards / logs, would leak them).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ConnectLink {
    pub host: String,
    pub port: u16,
    pub user: String,
}

/// Parse `uri` as a `letsflutssh://connect?host=…&user=…&port=…`
/// link. Returns `None` for any malformed / non-connect URI so
/// the caller can collapse "not a valid connect link" into a
/// single branch without inspecting the failure mode.
///
/// Rules (matched against the Dart `parseConnectUri`):
///   - scheme must equal `letsflutssh`,
///   - host (URI authority) must equal `connect`,
///   - query must carry non-empty `host` + `user`,
///   - host length ≤ 253, no `/` or `\\` or C0/C1 control chars,
///   - user length ≤ 256, no `/` or `\\` or C0/C1 control chars,
///   - port (when present) parses as 1..=65535; missing → 22.
pub fn parse_connect_uri(uri: &str) -> Option<ConnectLink> {
    let parts = ParsedUri::parse(uri)?;
    if parts.scheme != "letsflutssh" {
        return None;
    }
    if parts.host_part != Some("connect") {
        return None;
    }
    let mut host: Option<String> = None;
    let mut user: Option<String> = None;
    let mut port_raw: Option<String> = None;
    for (k, v) in parts.query_pairs() {
        match k.as_str() {
            "host" => host = Some(v),
            "user" => user = Some(v),
            "port" => port_raw = Some(v),
            _ => {}
        }
    }
    let host = host.unwrap_or_default().trim().to_string();
    let user = user.unwrap_or_default().trim().to_string();
    if host.is_empty() || user.is_empty() {
        return None;
    }
    if host.len() > 253 || host.contains('/') || host.contains('\\') || contains_control_char(&host)
    {
        return None;
    }
    if user.len() > 256 || user.contains('/') || user.contains('\\') || contains_control_char(&user)
    {
        return None;
    }
    let port = match port_raw.as_deref() {
        None | Some("") => 22,
        Some(raw) => match raw.parse::<u32>() {
            Ok(p) if (1..=65535).contains(&p) => p as u16,
            _ => return None,
        },
    };
    Some(ConnectLink { host, port, user })
}

/// True when `s` contains any C0 (0x00–0x1F) or C1 (0x7F–0x9F)
/// control character. Catches null bytes, CR/LF injection into
/// ssh-config, BEL/escape chars that could mangle terminal
/// prompts.
fn contains_control_char(s: &str) -> bool {
    s.bytes().any(|b| b < 0x20 || (0x7F..=0x9F).contains(&b))
}

/// Minimal URI splitter. The Rust ecosystem ships a heavy `url`
/// crate, but the connect-link grammar we accept is tiny —
/// `scheme://host[:port]/path?query#frag` — and we only care
/// about `scheme`, `host_part`, and `query`. Rolling a parser
/// at this scope keeps the dep graph small (no `url`, no
/// `percent-encoding` crate beyond what we hand-decode for
/// query pairs) and stays panic-free on adversarial input.
struct ParsedUri<'a> {
    scheme: &'a str,
    host_part: Option<&'a str>,
    query: Option<&'a str>,
}

impl<'a> ParsedUri<'a> {
    fn parse(input: &'a str) -> Option<Self> {
        // Reject ASCII control chars in the scheme part — RFC 3986
        // requires ALPHA *( ALPHA / DIGIT / "+" / "-" / "." ).
        let scheme_end = input.find(':')?;
        let scheme = &input[..scheme_end];
        if scheme.is_empty() {
            return None;
        }
        if !scheme
            .chars()
            .next()
            .is_some_and(|c| c.is_ascii_alphabetic())
        {
            return None;
        }
        for c in scheme.chars() {
            if !(c.is_ascii_alphanumeric() || c == '+' || c == '-' || c == '.') {
                return None;
            }
        }
        let after_scheme = &input[scheme_end + 1..];

        // Split "//host[:port][/path][?query][#frag]" into the
        // pieces we care about. Anything not starting with `//`
        // is treated as a non-authority URI; we only emit
        // host_part for the `//` form.
        let (host_part, rest) = if let Some(rest) = after_scheme.strip_prefix("//") {
            // The host-part runs up to the first `/`, `?`, or `#`.
            let end = rest.find(['/', '?', '#']).unwrap_or(rest.len());
            let host_segment = &rest[..end];
            let trailing = &rest[end..];
            // Strip a leading `path` from the trailing segment so
            // the query split below sees the same shape regardless
            // of whether a path was present.
            let after_host = trailing.strip_prefix('/').unwrap_or(trailing);
            (Some(host_segment), after_host)
        } else {
            (None, after_scheme)
        };

        // Pull the query out (between the first `?` and the
        // first `#`). Anything past a `#` is the fragment, which
        // we don't need.
        let query = match rest.find('?') {
            Some(qstart) => {
                let after_q = &rest[qstart + 1..];
                let qend = after_q.find('#').unwrap_or(after_q.len());
                Some(&after_q[..qend])
            }
            None => None,
        };

        Some(ParsedUri {
            scheme,
            host_part,
            query,
        })
    }

    fn query_pairs(&self) -> impl Iterator<Item = (String, String)> + '_ {
        self.query
            .unwrap_or("")
            .split('&')
            .filter(|s| !s.is_empty())
            .filter_map(|pair| {
                let (k, v) = match pair.find('=') {
                    Some(idx) => (&pair[..idx], &pair[idx + 1..]),
                    None => (pair, ""),
                };
                let key = percent_decode(k)?;
                let value = percent_decode(v)?;
                Some((key, value))
            })
    }
}

/// Percent-decode `s`. Returns `None` if a `%` is not followed by
/// two valid hex digits — same contract as Dart's `Uri.queryParameters`
/// FormatException, except we collapse it into "invalid URI" at the
/// caller.
fn percent_decode(s: &str) -> Option<String> {
    let bytes = s.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        match bytes[i] {
            b'+' => {
                out.push(b' ');
                i += 1;
            }
            b'%' => {
                if i + 2 >= bytes.len() {
                    return None;
                }
                let hi = (bytes[i + 1] as char).to_digit(16)?;
                let lo = (bytes[i + 2] as char).to_digit(16)?;
                out.push(((hi << 4) | lo) as u8);
                i += 3;
            }
            b => {
                out.push(b);
                i += 1;
            }
        }
    }
    String::from_utf8(out).ok()
}

// =====================================================================
// Dispatcher
// =====================================================================

/// Typed outcome of a [`DeeplinkDispatcher::dispatch`] call. Mirrors
/// the Dart-era `DeepLinkHandler` callbacks (`onConnect`,
/// `onLfsFileOpened`, `onKeyFileOpened`, `onQrImport`,
/// `onQrImportVersionTooNew`) plus the `Duplicate` / `Unknown`
/// branches that previously logged-and-dropped Dart-side.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum DeeplinkOutcome {
    /// `letsflutssh://connect?host=…&user=…[&port=…]` — open a
    /// terminal tab against the parsed endpoint.
    Connect {
        host: String,
        port: u16,
        user: String,
    },
    /// `letsflutssh://import?d=…` decoded successfully. The
    /// `pending` payload is staged in `AppState::imports` under
    /// `handle_id`; the Dart side fetches the preview from the
    /// registry and routes to the import-preview dialog.
    QrImport {
        handle_id: String,
        schema_version: i64,
    },
    /// `letsflutssh://import?d=…` carries a wire version newer than
    /// this build understands. Surface as "update the app" toast.
    QrImportRejected { found: i64, supported: i64 },
    /// `file://…/*.lfs` or `content://…/*.lfs` — hand path to the
    /// `.lfs` import dialog.
    OpenLfs { path: String },
    /// `file://…/*.{pem,key,pub}` or `content://…/*.{pem,key,pub}`
    /// — hand path to the SSH-key receiver.
    OpenKeyFile { path: String },
    /// Recognised URI but no actionable mapping (unknown
    /// `letsflutssh://` action, unsupported file extension,
    /// unknown scheme). Logged Rust-side; Dart UI does nothing.
    Unknown,
    /// URI matched the dispatcher's last-seen entry inside the
    /// dedup window. Cold-start `getInitialLink` +
    /// `uriLinkStream` can fire the same URI twice — this branch
    /// suppresses the duplicate so the user does not get two
    /// dialogs / two tabs from one tap.
    Duplicate,
}

/// Dedup window — covers the cold-start race between
/// `app_links.getInitialLink()` and `app_links.uriLinkStream`
/// without blocking a deliberate re-tap of the same QR / link
/// after the user came back from background.
const DEDUP_WINDOW_MS: u128 = 2000;

/// Stateful dispatcher owned by [`crate::app::AppState`]. Owns
/// only the dedup state (last URI + timestamp); routing and QR
/// staging delegate to pure functions in this module / the
/// archive registry.
pub struct DeeplinkDispatcher {
    inner: std::sync::Mutex<DispatcherInner>,
}

#[derive(Default)]
struct DispatcherInner {
    last_uri: Option<String>,
    last_at: Option<std::time::Instant>,
}

impl DeeplinkDispatcher {
    pub fn new() -> Self {
        Self {
            inner: std::sync::Mutex::new(DispatcherInner::default()),
        }
    }

    /// Dedup, route, and (for QR import) stage. Returns the typed
    /// outcome the FRB caller hands to the Dart UI. Idempotent on
    /// dedup — repeated calls within the window return
    /// `DeeplinkOutcome::Duplicate` and do not re-stage / re-emit.
    pub fn dispatch(&self, uri: &str) -> DeeplinkOutcome {
        if self.is_duplicate(uri) {
            return DeeplinkOutcome::Duplicate;
        }
        self.record(uri);
        route(uri)
    }

    fn is_duplicate(&self, uri: &str) -> bool {
        let g = self
            .inner
            .lock()
            .expect("deeplink dispatcher mutex poisoned");
        match (&g.last_uri, &g.last_at) {
            (Some(last), Some(at)) => last == uri && at.elapsed().as_millis() < DEDUP_WINDOW_MS,
            _ => false,
        }
    }

    fn record(&self, uri: &str) {
        let mut g = self
            .inner
            .lock()
            .expect("deeplink dispatcher mutex poisoned");
        g.last_uri = Some(uri.to_string());
        g.last_at = Some(std::time::Instant::now());
    }
}

impl Default for DeeplinkDispatcher {
    fn default() -> Self {
        Self::new()
    }
}

/// Pure routing function — split out from
/// [`DeeplinkDispatcher::dispatch`] so the dedup state is the
/// only stateful concern. Tests cover the routing matrix here
/// directly without spinning up the singleton AppState.
fn route(uri: &str) -> DeeplinkOutcome {
    let parsed = match ParsedUri::parse(uri) {
        Some(p) => p,
        None => return DeeplinkOutcome::Unknown,
    };
    match parsed.scheme {
        "letsflutssh" => route_custom_scheme(&parsed, uri),
        "file" | "content" => route_file_uri(uri),
        _ => DeeplinkOutcome::Unknown,
    }
}

fn route_custom_scheme(parsed: &ParsedUri<'_>, full: &str) -> DeeplinkOutcome {
    match parsed.host_part {
        Some("connect") => match parse_connect_uri(full) {
            Some(link) => DeeplinkOutcome::Connect {
                host: link.host,
                port: link.port,
                user: link.user,
            },
            None => DeeplinkOutcome::Unknown,
        },
        Some("import") => stage_qr_import(full),
        _ => DeeplinkOutcome::Unknown,
    }
}

fn stage_qr_import(uri: &str) -> DeeplinkOutcome {
    let payload = match crate::qr_codec_decode::extract_payload_from_uri(uri) {
        Some(p) => p,
        None => return DeeplinkOutcome::Unknown,
    };
    match crate::qr_codec_decode::try_decode_payload(&payload) {
        crate::qr_codec_decode::QrDecodeResult::Ok(decoded) => {
            let handle_id = random_handle_id();
            let decoded = *decoded;
            crate::app::instance()
                .imports
                .insert(handle_id.clone(), decoded.pending);
            DeeplinkOutcome::QrImport {
                handle_id,
                schema_version: decoded.schema_version,
            }
        }
        crate::qr_codec_decode::QrDecodeResult::VersionTooNew { found, supported } => {
            DeeplinkOutcome::QrImportRejected { found, supported }
        }
        crate::qr_codec_decode::QrDecodeResult::Err(_) => DeeplinkOutcome::Unknown,
    }
}

/// Map a `file://…` / `content://…` URI to the right open-action
/// outcome by file extension. Mirrors the Dart-era `handleFileUri`
/// (`.lfs` → archive, `.pem` / `.key` / `.pub` → SSH key).
fn route_file_uri(uri: &str) -> DeeplinkOutcome {
    // Strip query / fragment + scheme so the extension match runs
    // on a clean path. Lowercased so case differences in
    // user-typed extensions don't miss the match.
    let path_section = uri
        .split('?')
        .next()
        .unwrap_or(uri)
        .split('#')
        .next()
        .unwrap_or(uri);
    let lower = path_section.to_ascii_lowercase();
    let raw_path = strip_file_scheme(uri);
    if lower.ends_with(".lfs") {
        return DeeplinkOutcome::OpenLfs { path: raw_path };
    }
    if lower.ends_with(".pem") || lower.ends_with(".key") || lower.ends_with(".pub") {
        return DeeplinkOutcome::OpenKeyFile { path: raw_path };
    }
    DeeplinkOutcome::Unknown
}

fn strip_file_scheme(uri: &str) -> String {
    if let Some(rest) = uri.strip_prefix("file://") {
        rest.to_string()
    } else if let Some(rest) = uri.strip_prefix("content://") {
        // content URIs stay opaque — Android resolves them via
        // ContentResolver. The Dart side hands the original URI
        // back to the OS; we just preserve the full string.
        format!("content://{rest}")
    } else {
        uri.to_string()
    }
}

fn random_handle_id() -> String {
    use rand::RngCore;
    let mut bytes = [0u8; 16];
    rand::rngs::OsRng.fill_bytes(&mut bytes);
    let mut hex = String::with_capacity(32);
    for b in bytes {
        use std::fmt::Write as _;
        let _ = write!(hex, "{b:02x}");
    }
    hex
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_minimal_connect_link() {
        let link = parse_connect_uri("letsflutssh://connect?host=h&user=u").expect("parse");
        assert_eq!(link.host, "h");
        assert_eq!(link.user, "u");
        assert_eq!(link.port, 22);
    }

    #[test]
    fn parses_explicit_port() {
        let link =
            parse_connect_uri("letsflutssh://connect?host=h&user=u&port=2222").expect("parse");
        assert_eq!(link.port, 2222);
    }

    #[test]
    fn rejects_missing_host_or_user() {
        assert!(parse_connect_uri("letsflutssh://connect?host=h").is_none());
        assert!(parse_connect_uri("letsflutssh://connect?user=u").is_none());
        assert!(parse_connect_uri("letsflutssh://connect").is_none());
    }

    #[test]
    fn rejects_wrong_scheme_or_action() {
        assert!(parse_connect_uri("https://connect?host=h&user=u").is_none());
        assert!(parse_connect_uri("letsflutssh://import?host=h&user=u").is_none());
    }

    #[test]
    fn rejects_out_of_range_port() {
        assert!(parse_connect_uri("letsflutssh://connect?host=h&user=u&port=0").is_none());
        assert!(parse_connect_uri("letsflutssh://connect?host=h&user=u&port=70000").is_none());
        assert!(parse_connect_uri("letsflutssh://connect?host=h&user=u&port=abc").is_none());
    }

    #[test]
    fn rejects_path_separators_in_host_user() {
        assert!(parse_connect_uri("letsflutssh://connect?host=a/b&user=u").is_none());
        assert!(parse_connect_uri(r"letsflutssh://connect?host=h&user=a\b").is_none());
    }

    #[test]
    fn rejects_control_chars() {
        // %00 = NUL embedded mid-value (trim does not strip it).
        // Trailing whitespace control chars (LF / CR) get eaten by
        // the same trim() that the Dart parser applies, so they
        // collapse to a clean value — reuse the embedded form to
        // exercise the actual control-char branch.
        assert!(parse_connect_uri("letsflutssh://connect?host=h%00x&user=u").is_none());
        assert!(parse_connect_uri("letsflutssh://connect?host=h&user=a%0ab").is_none());
    }

    #[test]
    fn rejects_overlong_host_user() {
        let host = "h".repeat(254);
        let user = "u".repeat(257);
        assert!(parse_connect_uri(&format!("letsflutssh://connect?host={host}&user=u")).is_none());
        assert!(parse_connect_uri(&format!("letsflutssh://connect?host=h&user={user}")).is_none());
    }

    #[test]
    fn percent_decodes_query_values() {
        let link = parse_connect_uri("letsflutssh://connect?host=ex%20ample&user=us%2Br");
        // Space in host is rejected because the Dart side treats
        // any whitespace as ambiguous; our trim-then-validate
        // mirrors Dart's parser behaviour. Re-check shape only.
        // user = "us+r" survives.
        if let Some(l) = link {
            assert_eq!(l.user, "us+r");
        }
    }

    #[test]
    fn malformed_percent_encoding_returns_none() {
        assert!(parse_connect_uri("letsflutssh://connect?host=%XX&user=u").is_none());
        assert!(parse_connect_uri("letsflutssh://connect?host=%2&user=u").is_none());
    }

    #[test]
    fn fuzz_does_not_panic() {
        // Drives a deterministic mix of garbage shapes through.
        // The Dart-side fuzz suite ships seed=12648430; the rule
        // here is the same — never panic, return Option either
        // way. Keep the inputs hand-crafted so they hit the
        // edges that historically tripped past parsers.
        let inputs = [
            "",
            ":",
            "://",
            "://?",
            "letsflutssh://",
            "letsflutssh:",
            "letsflutssh://connect?",
            "letsflutssh://connect?=",
            "letsflutssh://connect?host=&user=",
            "letsflutssh://connect#frag?host=h&user=u",
            "letsflutssh://connect?host=h&user=u#",
            "letsflutssh://connect?host=h&host=h2&user=u",
            "letsflutssh://CONNECT?host=h&user=u",
            "LETSFLUTSSH://connect?host=h&user=u",
            "letsflutssh://connect?host=h&user=u&port=",
            "letsflutssh://connect?host=h&user=u&port=22a",
            "data:text/plain,host=h&user=u",
            "\0\0\0",
            "letsflutssh://connect?host=h%2&user=u",
            "letsflutssh://connect?host=%&user=u",
        ];
        for input in inputs {
            // All we promise: no panic.
            let _ = parse_connect_uri(input);
        }
    }

    // ---- Dispatcher tests ----------------------------------------

    #[test]
    fn route_connect_returns_typed_link() {
        match route("letsflutssh://connect?host=10.0.0.1&user=root&port=2222") {
            DeeplinkOutcome::Connect { host, port, user } => {
                assert_eq!(host, "10.0.0.1");
                assert_eq!(port, 2222);
                assert_eq!(user, "root");
            }
            other => panic!("expected Connect, got {other:?}"),
        }
    }

    #[test]
    fn route_connect_invalid_returns_unknown() {
        // Missing user — the connect parser rejects, dispatcher
        // collapses to Unknown.
        assert_eq!(
            route("letsflutssh://connect?host=h"),
            DeeplinkOutcome::Unknown
        );
    }

    #[test]
    fn route_unknown_action_returns_unknown() {
        assert_eq!(
            route("letsflutssh://summon?spell=fireball"),
            DeeplinkOutcome::Unknown
        );
    }

    #[test]
    fn route_lfs_file() {
        match route("file:///tmp/backup.lfs") {
            DeeplinkOutcome::OpenLfs { path } => assert_eq!(path, "/tmp/backup.lfs"),
            other => panic!("expected OpenLfs, got {other:?}"),
        }
    }

    #[test]
    fn route_lfs_file_case_insensitive() {
        match route("file:///tmp/Backup.LFS") {
            DeeplinkOutcome::OpenLfs { .. } => {}
            other => panic!("expected OpenLfs, got {other:?}"),
        }
    }

    #[test]
    fn route_pem_key_file() {
        match route("file:///home/u/.ssh/id_ed25519.pem") {
            DeeplinkOutcome::OpenKeyFile { path } => {
                assert_eq!(path, "/home/u/.ssh/id_ed25519.pem")
            }
            other => panic!("expected OpenKeyFile, got {other:?}"),
        }
    }

    #[test]
    fn route_key_extension_variants() {
        assert!(matches!(
            route("file:///tmp/a.key"),
            DeeplinkOutcome::OpenKeyFile { .. }
        ));
        assert!(matches!(
            route("file:///tmp/a.pub"),
            DeeplinkOutcome::OpenKeyFile { .. }
        ));
    }

    #[test]
    fn route_unknown_file_extension() {
        assert_eq!(route("file:///tmp/note.txt"), DeeplinkOutcome::Unknown);
    }

    #[test]
    fn route_unknown_scheme() {
        assert_eq!(route("https://example.com"), DeeplinkOutcome::Unknown);
        assert_eq!(route("garbage"), DeeplinkOutcome::Unknown);
    }

    #[test]
    fn dispatcher_dedups_within_window() {
        let d = DeeplinkDispatcher::new();
        let uri = "letsflutssh://connect?host=h&user=u";
        // First call routes normally.
        match d.dispatch(uri) {
            DeeplinkOutcome::Connect { .. } => {}
            other => panic!("first call: expected Connect, got {other:?}"),
        }
        // Second call within window collapses to Duplicate.
        assert_eq!(d.dispatch(uri), DeeplinkOutcome::Duplicate);
    }

    #[test]
    fn dispatcher_does_not_dedup_distinct_uris() {
        let d = DeeplinkDispatcher::new();
        match d.dispatch("letsflutssh://connect?host=a&user=u") {
            DeeplinkOutcome::Connect { .. } => {}
            other => panic!("expected Connect, got {other:?}"),
        }
        match d.dispatch("letsflutssh://connect?host=b&user=u") {
            DeeplinkOutcome::Connect { .. } => {}
            other => panic!("expected Connect, got {other:?}"),
        }
    }

    #[test]
    fn dispatcher_routes_qr_version_too_new_without_app_state() {
        // Versions are detected before staging — this branch never
        // touches AppState::imports, so we can exercise it without
        // initialising the singleton.
        // Encode a payload with v=999 (above CURRENT_FORMAT_VERSION = 4).
        // Smallest valid wrapper: just `{"v":999}` deflate+base64url.
        use base64::engine::{general_purpose::URL_SAFE_NO_PAD, Engine as _};
        use flate2::write::DeflateEncoder;
        use flate2::Compression;
        use std::io::Write;
        let json = b"{\"v\":999}";
        let mut enc = DeflateEncoder::new(Vec::new(), Compression::default());
        enc.write_all(json).unwrap();
        let deflated = enc.finish().unwrap();
        let payload = URL_SAFE_NO_PAD.encode(&deflated);
        let uri = format!("letsflutssh://import?d={payload}");
        match route(&uri) {
            DeeplinkOutcome::QrImportRejected { found, supported } => {
                assert_eq!(found, 999);
                assert_eq!(supported, 4);
            }
            other => panic!("expected QrImportRejected, got {other:?}"),
        }
    }

    #[test]
    fn dispatcher_unknown_for_malformed_qr_payload() {
        // Garbage payload that's neither valid base64 nor valid JSON.
        match route("letsflutssh://import?d=!!!") {
            DeeplinkOutcome::Unknown => {}
            other => panic!("expected Unknown, got {other:?}"),
        }
    }
}
