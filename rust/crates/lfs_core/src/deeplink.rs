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

/// Typed outcome of a [`DeeplinkDispatcher::dispatch`] call. One
/// variant per Dart-side callback (`Connect`, `QrImport`,
/// `QrImportRejected`) plus `Duplicate` / `Unknown` branches the
/// dispatcher logs and drops. The app handles only the
/// `letsflutssh://` URL scheme — it registers no file-extension
/// associations, so `file://` / `content://` URIs route to
/// `Unknown`.
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
    /// Recognised URI but no actionable mapping (unknown
    /// `letsflutssh://` action, a `file://` / `content://` URI we
    /// no longer claim, or an unknown scheme). Logged Rust-side;
    /// Dart UI does nothing.
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
        let g = self.inner.lock().unwrap_or_else(|e| e.into_inner());
        match (&g.last_uri, &g.last_at) {
            (Some(last), Some(at)) => last == uri && at.elapsed().as_millis() < DEDUP_WINDOW_MS,
            _ => false,
        }
    }

    fn record(&self, uri: &str) {
        let mut g = self.inner.lock().unwrap_or_else(|e| e.into_inner());
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
        // `file://` / `content://` are intentionally unhandled — the app
        // registers no file-extension associations, so the OS never hands
        // us a file URI and any that arrives is not ours to open.
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
            let handle_id = crate::id::random_handle_hex_32();
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
#[cfg(test)]
#[path = "../tests/unit/deeplink.rs"]
mod tests;
